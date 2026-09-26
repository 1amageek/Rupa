import SwiftCAD
import RupaCoreTypes

extension Transform3D {
    /// This placement as an exact rigid motion, for kernel operations that accept only rigid
    /// placements; a scaled, sheared or reflected placement is a typed failure.
    func rigidPlacement(tolerance: ModelingTolerance = .standard) throws -> RigidTransform3D {
        let v = matrix.values
        do {
            return try RigidTransform3D(
                basisX: Vector3D(x: v[0], y: v[4], z: v[8]),
                basisY: Vector3D(x: v[1], y: v[5], z: v[9]),
                basisZ: Vector3D(x: v[2], y: v[6], z: v[10]),
                translation: Vector3D(x: v[3], y: v[7], z: v[11]),
                tolerance: tolerance
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "The placement is not a rigid motion (it scales, shears or mirrors)."
            )
        }
    }

    /// Whether every matrix entry equals the identity's within `tolerance`.
    func isApproximatelyIdentity(tolerance: Double = 1.0e-12) -> Bool {
        zip(matrix.values, Transform3D.identity.matrix.values).allSatisfy { abs($0 - $1) <= tolerance }
    }
}
