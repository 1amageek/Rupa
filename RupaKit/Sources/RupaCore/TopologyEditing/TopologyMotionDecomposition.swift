import Foundation
import SwiftCAD
import RupaCoreTypes

/// Reads a motion of a body's own coordinates as the kernel's typed topology motion: a
/// translation, a rotation about a fixed axis, or a scale along three perpendicular axes about a
/// fixed point. Shears, mirrors and screw motions have no such form and are refused.
public enum TopologyMotionDecomposition {
    public static func motion(_ delta: Transform3D) throws -> TopologyMotion {
        let tolerance = ModelingTolerance.standard
        let columns = try [Vector3D.unitX, .unitY, .unitZ].map { try delta.applyingLinearPart(to: $0) }
        // L[i][j] is component i of column j.
        func entry(_ i: Int, _ j: Int) -> Double {
            let column = columns[j]
            return i == 0 ? column.x : (i == 1 ? column.y : column.z)
        }
        let translation = try delta.applied(to: .origin) - .origin
        let identityResidual = (0..<3).flatMap { i in (0..<3).map { j in abs(entry(i, j) - (i == j ? 1 : 0)) } }.max() ?? 0
        if identityResidual <= 1e-12 {
            guard translation.length > tolerance.distance else {
                throw EditorError(code: .commandInvalid, message: "A topology motion must move something.")
            }
            return .translation(DirectMoveVector(
                direction: try translation.normalized(tolerance: tolerance.distance),
                distance: .length(translation.length, .meter)
            ))
        }
        let determinant = columns[0].dot(columns[1].cross(columns[2]))
        guard determinant > 0 else {
            throw EditorError(code: .commandInvalid, message: "A topology motion cannot mirror.")
        }
        let orthonormalResidual = (0..<3).flatMap { i in (0..<3).map { j in abs(columns[i].dot(columns[j]) - (i == j ? 1 : 0)) } }.max() ?? 0
        if orthonormalResidual <= 1e-9 {
            let trace = entry(0, 0) + entry(1, 1) + entry(2, 2)
            let angle = acos(min(1, max(-1, (trace - 1) / 2)))
            var axis = Vector3D(x: entry(2, 1) - entry(1, 2), y: entry(0, 2) - entry(2, 0), z: entry(1, 0) - entry(0, 1))
            if axis.length <= 1e-9 {
                // A half turn: the axis is the column of L + I with the largest length.
                let candidates = (0..<3).map { j in columns[j] + Vector3D(x: j == 0 ? 1 : 0, y: j == 1 ? 1 : 0, z: j == 2 ? 1 : 0) }
                axis = candidates.max { $0.length < $1.length } ?? .unitZ
            }
            let unitAxis = try axis.normalized(tolerance: 1e-12)
            guard abs(translation.dot(unitAxis)) <= tolerance.distance else {
                throw EditorError(code: .commandInvalid, message: "A topology rotation cannot also slide along its axis.")
            }
            let origin = try fixedPoint(columns: columns, translation: translation, freeDirections: [unitAxis])
            return .rotation(DirectRotation(origin: origin, axis: unitAxis, angle: .angle(angle, .radian)))
        }
        let symmetricResidual = max(abs(entry(0, 1) - entry(1, 0)), abs(entry(0, 2) - entry(2, 0)), abs(entry(1, 2) - entry(2, 1)))
        guard symmetricResidual <= 1e-9 else {
            throw EditorError(code: .commandInvalid, message: "A topology motion must be a move, a rotation or a scale without shear.")
        }
        let (values, vectors) = symmetricEigen((0..<3).map { i in (0..<3).map { j in entry(i, j) } })
        guard values.allSatisfy({ $0 > tolerance.relative }) else {
            throw EditorError(code: .commandInvalid, message: "A topology scale needs positive factors.")
        }
        let free = zip(values, vectors).filter { abs($0.0 - 1) <= 1e-12 }.map(\.1)
        for direction in free where abs(translation.dot(direction)) > tolerance.distance {
            throw EditorError(code: .commandInvalid, message: "A topology scale cannot also slide along an axis it keeps.")
        }
        let origin = try fixedPoint(columns: columns, translation: translation, freeDirections: free)
        // Jacobi rotations keep the eigenvector frame right-handed, so the third axis is x × y.
        return .scale(DirectScale(
            origin: origin, xAxis: vectors[0], yAxis: vectors[1],
            factors: values.map { .scalar($0) }
        ))
    }

    /// The point the motion keeps, chosen with no component along `freeDirections`, in which the
    /// linear part is the identity: it solves (I − L + Σ d dᵀ) o = t.
    private static func fixedPoint(columns: [Vector3D], translation t: Vector3D, freeDirections: [Vector3D]) throws -> Point3D {
        var rows = [[Double]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                let column = columns[j]
                let l = i == 0 ? column.x : (i == 1 ? column.y : column.z)
                var value = (i == j ? 1 : 0) - l
                for d in freeDirections {
                    let di = i == 0 ? d.x : (i == 1 ? d.y : d.z)
                    let dj = j == 0 ? d.x : (j == 1 ? d.y : d.z)
                    value += di * dj
                }
                rows[i][j] = value
            }
        }
        let a = Vector3D(x: rows[0][0], y: rows[1][0], z: rows[2][0])
        let b = Vector3D(x: rows[0][1], y: rows[1][1], z: rows[2][1])
        let c = Vector3D(x: rows[0][2], y: rows[1][2], z: rows[2][2])
        let determinant = a.dot(b.cross(c))
        guard abs(determinant) > 1e-15 else {
            throw EditorError(code: .commandInvalid, message: "A topology motion has no fixed point to turn or scale about.")
        }
        // Cramer's rule on the columns a, b, c.
        return Point3D(
            x: t.dot(b.cross(c)) / determinant,
            y: a.dot(t.cross(c)) / determinant,
            z: a.dot(b.cross(t)) / determinant
        )
    }

    /// Eigenvalues and orthonormal eigenvectors of a symmetric 3 × 3 matrix, by Jacobi rotations.
    private static func symmetricEigen(_ matrix: [[Double]]) -> ([Double], [Vector3D]) {
        var a = matrix
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<64 {
            var p = 0, q = 1
            for (i, j) in [(0, 1), (0, 2), (1, 2)] where abs(a[i][j]) > abs(a[p][q]) { p = i; q = j }
            guard abs(a[p][q]) > 1e-15 else { break }
            let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
            let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
            let c = 1 / (t * t + 1).squareRoot(), s = t * c
            for k in 0..<3 {
                let akp = a[k][p], akq = a[k][q]
                a[k][p] = c * akp - s * akq
                a[k][q] = s * akp + c * akq
            }
            for k in 0..<3 {
                let apk = a[p][k], aqk = a[q][k]
                a[p][k] = c * apk - s * aqk
                a[q][k] = s * apk + c * aqk
            }
            for k in 0..<3 {
                let vkp = v[k][p], vkq = v[k][q]
                v[k][p] = c * vkp - s * vkq
                v[k][q] = s * vkp + c * vkq
            }
        }
        let vectors = (0..<3).map { j in Vector3D(x: v[0][j], y: v[1][j], z: v[2][j]) }
        return ((0..<3).map { a[$0][$0] }, vectors)
    }
}
