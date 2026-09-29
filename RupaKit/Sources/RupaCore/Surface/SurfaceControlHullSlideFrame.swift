import SwiftCAD

/// The directions a surface control point slides along: the control hull's tangents at it — the
/// difference of its neighbors along u and along v, one-sided at an end of a row — and the
/// normal of the two. B-spline surface sources and PolySpline patches' interior points slide by
/// it, and the viewport's slide handles point along it.
struct SurfaceControlHullSlideFrame {
    let positiveU: Vector3D
    let positiveV: Vector3D
    let normal: Vector3D

    init(controlPoints: [[Point3D]], uIndex: Int, vIndex: Int, owner: String) throws {
        guard controlPoints.indices.contains(vIndex), controlPoints[vIndex].indices.contains(uIndex) else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) references a missing surface control point.")
        }
        func tangent(along axis: String, count: Int, index: Int, point: (Int) -> Point3D) throws -> Vector3D {
            let lower = max(index - 1, 0), upper = min(index + 1, count - 1)
            guard count >= 2, lower != upper else {
                throw EditorError(code: .commandInvalid, message: "\(owner) has no control hull direction along \(axis).")
            }
            return try Self.unit(point(upper) - point(lower), axis, owner: owner)
        }
        positiveU = try tangent(along: "U", count: controlPoints[vIndex].count, index: uIndex) { controlPoints[vIndex][$0] }
        positiveV = try tangent(along: "V", count: controlPoints.count, index: vIndex) { row in
            guard controlPoints[row].indices.contains(uIndex) else { return controlPoints[vIndex][uIndex] }
            return controlPoints[row][uIndex]
        }
        normal = try Self.unit(positiveU.cross(positiveV), "N", owner: owner)
    }

    func vector(for direction: PolySplineSurfaceVertexSlideDirection) -> Vector3D {
        switch direction {
        case .positiveU: positiveU
        case .negativeU: -positiveU
        case .normal: normal
        case .positiveV: positiveV
        case .negativeV: -positiveV
        }
    }

    private static func unit(_ vector: Vector3D, _ axis: String, owner: String) throws -> Vector3D {
        do {
            return try vector.normalized(tolerance: ModelingTolerance.standard.distance)
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(owner) control hull direction along \(axis) is collapsed.")
        }
    }
}
