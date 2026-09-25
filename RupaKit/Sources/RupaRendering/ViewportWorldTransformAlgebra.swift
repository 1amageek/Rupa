import RupaCore
import SwiftCAD

/// Viewport error adapter for the shared checked scene transform contract.
package enum ViewportWorldTransformAlgebra {
    static let singularDeterminantFloor = 1.0e-12

    static func multiplied(_ lhs: Transform3D, _ rhs: Transform3D) throws -> Transform3D {
        try viewportTransform { try lhs.composed(with: rhs) }
    }

    static func inverted(_ value: Transform3D) throws -> Transform3D {
        try viewportTransform { try value.inverse() }
    }

    /// Applies a world-space gesture in the node's parent frame.
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
        guard zip(base, next).contains(where: { abs($0 - $1) > singularDeterminantFloor }) else {
            return nil
        }
        return localTransform
    }

    package static func translation(_ vector: Vector3D) throws -> Transform3D {
        try viewportTransform { try Transform3D.translation(vector) }
    }

    static func scale(_ factor: Double, about pivot: Point3D) throws -> Transform3D {
        try viewportTransform {
            try Transform3D.scale(Vector3D(x: factor, y: factor, z: factor), about: pivot)
        }
    }

    static func rotation(axis: Vector3D, radians: Double, about pivot: Point3D) throws -> Transform3D {
        try viewportTransform {
            try Transform3D.rotation(axis: axis, angleRadians: radians, about: pivot)
        }
    }

    static func transformedPoint(_ point: Point3D, by value: Transform3D) throws -> Point3D {
        try viewportTransform { try value.applied(to: point) }
    }

    static func transformedVector(_ vector: Vector3D, by value: Transform3D) throws -> Vector3D {
        try viewportTransform { try value.applyingLinearPart(to: vector) }
    }

    static func transformedPoint(_ point: Point3D, by placement: ScenePlacement) throws -> Point3D {
        try viewportTransform {
            let mapped = placement.point(point)
            try mapped.validate()
            return mapped
        }
    }

    static func transformedVector(_ vector: Vector3D, by placement: ScenePlacement) throws -> Vector3D {
        try viewportTransform {
            let mapped = placement.vector(vector)
            try mapped.validate()
            return mapped
        }
    }

    static func normalized(_ vector: Vector3D, describing subject: String) throws -> Vector3D {
        try viewportTransform { try vector.normalized(tolerance: 1.0e-10) }
    }

    private static func viewportTransform<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            throw RealityViewportSpatialBatch.invalid(
                "A viewport transform could not be represented: \(error)."
            )
        }
    }
}
