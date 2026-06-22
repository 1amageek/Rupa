import Foundation

public struct CurveRebuildReport: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Equatable, Sendable {
        case points
        case refit
        case explicitControl
    }

    public enum DeviationMeasurement: String, Codable, Equatable, Sendable {
        case analyticCubicBezier
    }

    public var sourceFeatureID: String
    public var entityID: String
    public var method: Method
    public var originalControlPointCount: Int
    public var rebuiltControlPointCount: Int
    public var originalSpanCount: Int
    public var rebuiltSpanCount: Int
    public var deviationMeasurement: DeviationMeasurement
    public var maximumDeviationMeters: Double
    public var rootMeanSquareDeviationMeters: Double
    public var maximumDeviationFraction: Double
    public var evaluatedIntervalCount: Int
    public var criticalPointCount: Int

    public init(
        sourceFeatureID: String,
        entityID: String,
        method: Method,
        originalControlPointCount: Int,
        rebuiltControlPointCount: Int,
        originalSpanCount: Int,
        rebuiltSpanCount: Int,
        deviationMeasurement: DeviationMeasurement,
        maximumDeviationMeters: Double,
        rootMeanSquareDeviationMeters: Double,
        maximumDeviationFraction: Double,
        evaluatedIntervalCount: Int,
        criticalPointCount: Int
    ) {
        self.sourceFeatureID = sourceFeatureID
        self.entityID = entityID
        self.method = method
        self.originalControlPointCount = originalControlPointCount
        self.rebuiltControlPointCount = rebuiltControlPointCount
        self.originalSpanCount = originalSpanCount
        self.rebuiltSpanCount = rebuiltSpanCount
        self.deviationMeasurement = deviationMeasurement
        self.maximumDeviationMeters = maximumDeviationMeters
        self.rootMeanSquareDeviationMeters = rootMeanSquareDeviationMeters
        self.maximumDeviationFraction = maximumDeviationFraction
        self.evaluatedIntervalCount = evaluatedIntervalCount
        self.criticalPointCount = criticalPointCount
    }
}
