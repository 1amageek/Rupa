import RupaCore

/// The Section Analysis distance a drag of the section handle sets: the plane's offset along
/// its source normal.
public struct ViewportSectionAnalysisDistanceDragTarget: Equatable, Sendable {
    public var distanceMeters: Double

    public init(distanceMeters: Double) {
        self.distanceMeters = distanceMeters
    }
}

/// The section handle the viewport offers while Section Analysis is placing its plane: the
/// current distance and the source normal it moves along (the normal before Flip).
public struct ViewportSectionAnalysisDistanceHandle: Equatable, Sendable {
    public var distanceMeters: Double
    public var sourceNormal: Vector3D

    public init(distanceMeters: Double, sourceNormal: Vector3D) {
        self.distanceMeters = distanceMeters
        self.sourceNormal = sourceNormal
    }
}
