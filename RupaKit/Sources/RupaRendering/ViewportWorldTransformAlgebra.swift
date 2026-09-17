import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Throwing 4x4 world algebra shared by the viewport's transform gizmos.
///
/// `RupaViewportScene`'s `Transform3D.concatenating` answers a mis-sized or
/// unrepresentable product with the receiver, and its inverse helper answers a
/// singular basis with `nil`. A gizmo mutation composed through either would
/// commit a transform nobody asked for, so this owner validates every operand,
/// product, inverse and applied point and refuses instead.
///
/// The stored convention is row-major with column vectors: translation occupies
/// indices 3, 7 and 11, and `multiplied(a, b)` applies `b` first.
package enum ViewportWorldTransformAlgebra {
    /// A basis whose determinant does not clear this floor cannot be inverted
    /// back into the node's local frame, so the mutation is refused rather
    /// than committed against a reconstructed frame.
    static let singularDeterminantFloor = 1.0e-12

    static func multiplied(_ lhs: Transform3D, _ rhs: Transform3D) throws -> Transform3D {
        let left = try elements(of: lhs)
        let right = try elements(of: rhs)
        var product = [Double](repeating: 0.0, count: 16)
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                var sum = 0.0
                for index in 0 ..< 4 {
                    sum += left[row * 4 + index] * right[index * 4 + column]
                }
                product[row * 4 + column] = sum
            }
        }
        return try transform(product, describing: "product")
    }

    static func inverted(_ value: Transform3D) throws -> Transform3D {
        let m = try elements(of: value)
        var cofactors = [Double](repeating: 0.0, count: 16)
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                let minor = try minorDeterminant(m, skippingRow: row, skippingColumn: column)
                let sign = (row + column) % 2 == 0 ? 1.0 : -1.0
                // Transposed on write, so `cofactors` is already the adjugate.
                cofactors[column * 4 + row] = sign * minor
            }
        }
        var determinant = 0.0
        for column in 0 ..< 4 {
            determinant += m[column] * cofactors[column * 4]
        }
        guard determinant.isFinite, abs(determinant) > singularDeterminantFloor else {
            throw RealityViewportSpatialBatch.invalid(
                "A viewport transform frame is singular and cannot be inverted."
            )
        }
        for index in 0 ..< 16 {
            cofactors[index] /= determinant
        }
        return try transform(cofactors, describing: "inverse")
    }

    /// Answers the local frame that realises `worldMutation` for a node whose
    /// current local frame is `baseLocal` and whose parent's world frame is
    /// `parent`, which is `P^-1 * M_w * P * L`. Answers `nil` when the
    /// composition leaves the frame unchanged, so a released gesture that
    /// moved nothing writes no undo step.
    ///
    /// Both transform gizmos commit through this one entry. A sketch
    /// occurrence's role mutation and a body's placement translation differ in
    /// how they build `worldMutation` and in nothing after it, so a second
    /// composition would be a second chance to disagree about what a released
    /// gesture means.
    package static func localTransform(
        applying worldMutation: Transform3D,
        within parent: Transform3D,
        to baseLocal: Transform3D
    ) throws -> Transform3D? {
        let inverseParent = try inverted(parent)
        let mutatedParent = try multiplied(worldMutation, parent)
        let localMutation = try multiplied(inverseParent, mutatedParent)
        let localTransform = try multiplied(localMutation, baseLocal)
        let base = baseLocal.matrix.values
        let next = localTransform.matrix.values
        guard base.count == next.count else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform frame is not a 4x4 matrix.")
        }
        let changed = zip(base, next).contains { abs($0 - $1) > singularDeterminantFloor }
        guard changed else { return nil }
        return localTransform
    }

    package static func translation(_ vector: Vector3D) throws -> Transform3D {
        guard vector.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport translation is not finite.")
        }
        return try transform([
            1.0, 0.0, 0.0, vector.x,
            0.0, 1.0, 0.0, vector.y,
            0.0, 0.0, 1.0, vector.z,
            0.0, 0.0, 0.0, 1.0,
        ], describing: "translation")
    }

    static func scale(_ factor: Double, about pivot: Point3D) throws -> Transform3D {
        guard factor.isFinite, pivot.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport scale is not finite.")
        }
        let offset = 1.0 - factor
        return try transform([
            factor, 0.0, 0.0, pivot.x * offset,
            0.0, factor, 0.0, pivot.y * offset,
            0.0, 0.0, factor, pivot.z * offset,
            0.0, 0.0, 0.0, 1.0,
        ], describing: "scale")
    }

    static func rotation(axis: Vector3D, radians: Double, about pivot: Point3D) throws -> Transform3D {
        guard radians.isFinite, pivot.isFinite, axis.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport rotation is not finite.")
        }
        let unit = try normalized(axis, describing: "rotation axis")
        let c = cos(radians)
        let s = sin(radians)
        let t = 1.0 - c
        let basis = [
            t * unit.x * unit.x + c, t * unit.x * unit.y - s * unit.z, t * unit.x * unit.z + s * unit.y,
            t * unit.x * unit.y + s * unit.z, t * unit.y * unit.y + c, t * unit.y * unit.z - s * unit.x,
            t * unit.x * unit.z - s * unit.y, t * unit.y * unit.z + s * unit.x, t * unit.z * unit.z + c,
        ]
        let origin = Vector3D(x: pivot.x, y: pivot.y, z: pivot.z)
        var values = [Double](repeating: 0.0, count: 16)
        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                values[row * 4 + column] = basis[row * 3 + column]
            }
            let rotated = basis[row * 3] * origin.x + basis[row * 3 + 1] * origin.y + basis[row * 3 + 2] * origin.z
            values[row * 4 + 3] = componentOf(origin, at: row) - rotated
        }
        values[15] = 1.0
        return try transform(values, describing: "rotation")
    }

    static func transformedPoint(_ point: Point3D, by value: Transform3D) throws -> Point3D {
        let m = try elements(of: value)
        guard point.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform point is not finite.")
        }
        let w = m[12] * point.x + m[13] * point.y + m[14] * point.z + m[15]
        guard w.isFinite, abs(w) > singularDeterminantFloor else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform point is not representable.")
        }
        let result = Point3D(
            x: (m[0] * point.x + m[1] * point.y + m[2] * point.z + m[3]) / w,
            y: (m[4] * point.x + m[5] * point.y + m[6] * point.z + m[7]) / w,
            z: (m[8] * point.x + m[9] * point.y + m[10] * point.z + m[11]) / w
        )
        guard result.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform point is not representable.")
        }
        return result
    }

    static func transformedVector(_ vector: Vector3D, by value: Transform3D) throws -> Vector3D {
        let m = try elements(of: value)
        guard vector.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform vector is not finite.")
        }
        let result = Vector3D(
            x: m[0] * vector.x + m[1] * vector.y + m[2] * vector.z,
            y: m[4] * vector.x + m[5] * vector.y + m[6] * vector.z,
            z: m[8] * vector.x + m[9] * vector.y + m[10] * vector.z
        )
        guard result.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform vector is not representable.")
        }
        return result
    }

    static func normalized(_ vector: Vector3D, describing subject: String) throws -> Vector3D {
        guard vector.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform \(subject) is not finite.")
        }
        let length = vector.length
        guard length.isFinite, length > 1.0e-10 else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform \(subject) is degenerate.")
        }
        return vector * (1.0 / length)
    }

    private static func componentOf(_ vector: Vector3D, at index: Int) -> Double {
        switch index {
        case 0: vector.x
        case 1: vector.y
        default: vector.z
        }
    }

    private static func elements(of value: Transform3D) throws -> [Double] {
        let values = value.matrix.values
        guard values.count == 16 else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform frame is not a 4x4 matrix.")
        }
        for element in values where !element.isFinite {
            throw RealityViewportSpatialBatch.invalid("A viewport transform frame is not finite.")
        }
        return values
    }

    private static func transform(_ values: [Double], describing subject: String) throws -> Transform3D {
        for element in values where !element.isFinite {
            throw RealityViewportSpatialBatch.invalid("A viewport transform \(subject) is not finite.")
        }
        do {
            return Transform3D(matrix: try Matrix4x4(values: values))
        } catch {
            throw RealityViewportSpatialBatch.invalid("A viewport transform \(subject) is not representable.")
        }
    }

    private static func minorDeterminant(
        _ m: [Double], skippingRow: Int, skippingColumn: Int
    ) throws -> Double {
        var minor = [Double]()
        minor.reserveCapacity(9)
        for row in 0 ..< 4 where row != skippingRow {
            for column in 0 ..< 4 where column != skippingColumn {
                minor.append(m[row * 4 + column])
            }
        }
        guard minor.count == 9 else {
            throw RealityViewportSpatialBatch.invalid("A viewport transform minor is malformed.")
        }
        return minor[0] * (minor[4] * minor[8] - minor[5] * minor[7])
            - minor[1] * (minor[3] * minor[8] - minor[5] * minor[6])
            + minor[2] * (minor[3] * minor[7] - minor[4] * minor[6])
    }
}
