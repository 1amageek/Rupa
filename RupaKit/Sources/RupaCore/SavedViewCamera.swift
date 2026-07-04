import SwiftCAD

public struct SavedViewCamera: Codable, Hashable, Sendable {
    public var target: Point3D
    public var distanceMeters: Double
    public var yawRadians: Double
    public var pitchRadians: Double
    public var rollRadians: Double

    public init(
        target: Point3D = .origin,
        distanceMeters: Double,
        yawRadians: Double,
        pitchRadians: Double,
        rollRadians: Double = 0.0
    ) {
        self.target = target
        self.distanceMeters = distanceMeters
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
        self.rollRadians = rollRadians
    }

    public func validate() throws {
        try target.validate()
        guard distanceMeters.isFinite,
              distanceMeters > 0.0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view camera distance must be finite and positive."
            )
        }
        guard yawRadians.isFinite,
              pitchRadians.isFinite,
              rollRadians.isFinite else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view camera angles must be finite."
            )
        }
    }
}
