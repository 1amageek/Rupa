import Foundation
import SwiftCAD
import RupaCoreTypes

/// The placement Place and Paste with Placement make from two picked reference points.
///
/// The source reference point moves onto the destination reference point. The object turns so the
/// source surface normal faces the destination surface normal (face to face), or points along it
/// when flipped; a source point without a surface normal uses the object's up axis, pointing its
/// underside (`-up`) at the destination. A destination without a normal keeps the up axis vertical.
/// The object then spins by `angleRadians` about the destination normal and scales uniformly about
/// the destination point.
public struct SceneNodePlacementSpec: Codable, Hashable, Sendable {
    public enum UpAxis: String, Codable, Hashable, Sendable, CaseIterable {
        case x, y, z

        public var vector: Vector3D {
            switch self {
            case .x: .unitX
            case .y: .unitY
            case .z: .unitZ
            }
        }
    }

    public var sourcePoint: Point3D
    public var sourceNormal: Vector3D?
    public var destinationPoint: Point3D
    public var destinationNormal: Vector3D?
    public var upAxis: UpAxis
    public var flipsOrientation: Bool
    public var angleRadians: Double
    public var scale: Double

    public init(
        sourcePoint: Point3D,
        sourceNormal: Vector3D? = nil,
        destinationPoint: Point3D,
        destinationNormal: Vector3D? = nil,
        upAxis: UpAxis = .z,
        flipsOrientation: Bool = false,
        angleRadians: Double = 0,
        scale: Double = 1
    ) {
        self.sourcePoint = sourcePoint
        self.sourceNormal = sourceNormal
        self.destinationPoint = destinationPoint
        self.destinationNormal = destinationNormal
        self.upAxis = upAxis
        self.flipsOrientation = flipsOrientation
        self.angleRadians = angleRadians
        self.scale = scale
    }

    /// The world-space transform applied to the selection.
    public func transform() throws -> Transform3D {
        let tolerance = ModelingTolerance.standard.distance
        guard scale.isFinite, scale > tolerance else {
            throw EditorError(code: .commandInvalid, message: "A placement scale must be a positive finite number.")
        }
        guard angleRadians.isFinite else {
            throw EditorError(code: .commandInvalid, message: "A placement angle must be finite.")
        }
        let up = upAxis.vector
        let destinationNormal = try (self.destinationNormal ?? up).normalized(tolerance: tolerance)
        let sourceNormal = try (self.sourceNormal ?? up * -1).normalized(tolerance: tolerance)
        let facing = flipsOrientation ? destinationNormal : destinationNormal * -1
        let align = try Self.rotation(taking: sourceNormal, onto: facing)
        let spin = try Transform3D.rotation(axis: destinationNormal, angleRadians: angleRadians)
        let scaling = try Transform3D.scale(Vector3D(x: scale, y: scale, z: scale), about: .origin)
        let toOrigin = try Transform3D.translation(Point3D.origin - sourcePoint)
        let toDestination = try Transform3D.translation(destinationPoint - Point3D.origin)
        return try toDestination
            .composed(with: spin)
            .composed(with: align)
            .composed(with: scaling)
            .composed(with: toOrigin)
    }

    /// The smallest rotation taking unit `from` onto unit `to`; opposite vectors turn half a turn
    /// about an axis perpendicular to both.
    private static func rotation(taking from: Vector3D, onto to: Vector3D) throws -> Transform3D {
        let axis = from.cross(to)
        let sine = axis.length
        let cosine = from.dot(to)
        if sine > 1.0e-12 {
            return try Transform3D.rotation(axis: axis, angleRadians: atan2(sine, cosine))
        }
        guard cosine < 0 else {
            return .identity
        }
        let seed: Vector3D = abs(from.x) < 0.9 ? .unitX : .unitY
        return try Transform3D.rotation(axis: from.cross(seed), angleRadians: .pi)
    }
}
