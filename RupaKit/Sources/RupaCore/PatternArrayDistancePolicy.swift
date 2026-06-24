import SwiftCAD

public struct PatternArrayDistancePolicy: Equatable, Sendable {
    public var tolerance: ModelingTolerance
    public var minimumLinearDistanceMultiplier: Double

    public init(
        tolerance: ModelingTolerance = .standard,
        minimumLinearDistanceMultiplier: Double = 2.0
    ) {
        precondition(tolerance.distance.isFinite)
        precondition(tolerance.distance > 0.0)
        precondition(minimumLinearDistanceMultiplier.isFinite)
        precondition(minimumLinearDistanceMultiplier > 1.0)
        self.tolerance = tolerance
        self.minimumLinearDistanceMultiplier = minimumLinearDistanceMultiplier
    }

    public static let standard = PatternArrayDistancePolicy()

    public var minimumLinearDistanceMeters: Double {
        tolerance.distance * minimumLinearDistanceMultiplier
    }

    public func normalizedLinearDistanceMeters(_ value: Double) -> Double {
        guard value.isFinite else {
            return minimumLinearDistanceMeters
        }
        return max(value, minimumLinearDistanceMeters)
    }
}
