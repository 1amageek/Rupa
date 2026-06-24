import SwiftCAD

public struct PatternArrayAnglePolicy: Equatable, Sendable {
    public var tolerance: ModelingTolerance
    public var minimumAngleMultiplier: Double

    public init(
        tolerance: ModelingTolerance = .standard,
        minimumAngleMultiplier: Double = 2.0
    ) {
        precondition(tolerance.angle.isFinite)
        precondition(tolerance.angle > 0.0)
        precondition(minimumAngleMultiplier.isFinite)
        precondition(minimumAngleMultiplier > 1.0)
        self.tolerance = tolerance
        self.minimumAngleMultiplier = minimumAngleMultiplier
    }

    public static let standard = PatternArrayAnglePolicy()

    public var minimumAngleRadians: Double {
        tolerance.angle * minimumAngleMultiplier
    }

    public func normalizedSignedAngleRadians(_ value: Double) -> Double {
        guard value.isFinite else {
            return minimumAngleRadians
        }
        guard abs(value) < minimumAngleRadians else {
            return value
        }
        return value < 0.0 ? -minimumAngleRadians : minimumAngleRadians
    }
}
