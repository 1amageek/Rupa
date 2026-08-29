import Foundation

/// Candidate action for changing the placement of the seeded source geometry.
public struct CADTransformAction: Codable, Equatable, Hashable, Sendable {
    public let translation: CADPoint3D
    public let axisPoint: CADPoint3D
    public let rotationAxis: CADDirection3D
    public let rotation: CADAngle

    public init(
        translation: CADPoint3D,
        axisPoint: CADPoint3D,
        rotationAxis: CADDirection3D,
        rotation: CADAngle
    ) {
        self.translation = translation
        self.axisPoint = axisPoint
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }
}
