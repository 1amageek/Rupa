import Foundation
import SwiftCAD

/// A Product scene placement that has already passed the affine-placement checks.
///
/// Construction is the failure boundary: the matrix must be finite, affine and invertible, and
/// its inverse is computed once. Every mapping afterwards is plain affine arithmetic, so it has no
/// identity, input or projective fallback to hide a malformed placement behind. Callers that map
/// untrusted coordinates still validate those coordinates at their own boundary; a non-finite input
/// maps to a non-finite output rather than to a substitute value.
public struct ScenePlacement: Hashable, Sendable {
    public static let identity = ScenePlacement(
        uncheckedAffine: .identity,
        inverse: .identity
    )

    /// The validated row-major placement matrix.
    public let transform: Transform3D
    private let inverseTransform: Transform3D

    public init(_ transform: Transform3D) throws {
        try transform.validateAffinePlacement()
        self.transform = transform
        self.inverseTransform = try transform.inverse()
    }

    private init(uncheckedAffine transform: Transform3D, inverse: Transform3D) {
        self.transform = transform
        self.inverseTransform = inverse
    }

    public static func == (lhs: ScenePlacement, rhs: ScenePlacement) -> Bool {
        lhs.transform == rhs.transform
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(transform)
    }

    /// The placement that undoes this one.
    public var inverse: ScenePlacement {
        ScenePlacement(uncheckedAffine: inverseTransform, inverse: transform)
    }

    /// The translation column.
    public var translation: Vector3D {
        let m = transform.matrix.values
        return Vector3D(x: m[3], y: m[7], z: m[11])
    }

    /// The placement that applies `self` after `other`.
    public func composed(with other: ScenePlacement) throws -> ScenePlacement {
        try ScenePlacement(transform.composed(with: other.transform))
    }

    /// Maps a local point into the placed frame.
    public func point(_ point: Point3D) -> Point3D {
        Self.affinePoint(point, values: transform.matrix.values)
    }

    /// Maps a placed-frame point back into the local frame.
    public func inversePoint(_ point: Point3D) -> Point3D {
        Self.affinePoint(point, values: inverseTransform.matrix.values)
    }

    /// Maps a local direction through the linear part.
    public func vector(_ vector: Vector3D) -> Vector3D {
        Self.linearVector(vector, values: transform.matrix.values)
    }

    /// Maps a placed-frame direction back into the local frame.
    public func inverseVector(_ vector: Vector3D) -> Vector3D {
        Self.linearVector(vector, values: inverseTransform.matrix.values)
    }

    /// Maps a local plane normal into the placed frame through the inverse transpose.
    ///
    /// The result is unnormalized; a normal that the placement collapses cannot occur because the
    /// placement is invertible, so normalization is left to callers that need unit length.
    public func normal(_ normal: Vector3D) -> Vector3D {
        let m = inverseTransform.matrix.values
        return Vector3D(
            x: m[0] * normal.x + m[4] * normal.y + m[8] * normal.z,
            y: m[1] * normal.x + m[5] * normal.y + m[9] * normal.z,
            z: m[2] * normal.x + m[6] * normal.y + m[10] * normal.z
        )
    }

    private static func affinePoint(_ point: Point3D, values m: [Double]) -> Point3D {
        Point3D(
            x: m[0] * point.x + m[1] * point.y + m[2] * point.z + m[3],
            y: m[4] * point.x + m[5] * point.y + m[6] * point.z + m[7],
            z: m[8] * point.x + m[9] * point.y + m[10] * point.z + m[11]
        )
    }

    private static func linearVector(_ vector: Vector3D, values m: [Double]) -> Vector3D {
        Vector3D(
            x: m[0] * vector.x + m[1] * vector.y + m[2] * vector.z,
            y: m[4] * vector.x + m[5] * vector.y + m[6] * vector.z,
            z: m[8] * vector.x + m[9] * vector.y + m[10] * vector.z
        )
    }
}
