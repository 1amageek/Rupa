import Foundation

public struct RulerConfiguration: Codable, Hashable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var minorTickMeters: Double
    public var majorTickMeters: Double
    public var visibleSpanMeters: Double

    public init(
        displayUnit: LengthDisplayUnit,
        minorTickMeters: Double,
        majorTickMeters: Double,
        visibleSpanMeters: Double
    ) {
        self.displayUnit = displayUnit
        self.minorTickMeters = minorTickMeters
        self.majorTickMeters = majorTickMeters
        self.visibleSpanMeters = visibleSpanMeters
    }

    public static func standard(for unit: LengthDisplayUnit) -> RulerConfiguration {
        RulerConfiguration(
            displayUnit: unit,
            minorTickMeters: unit.meters(from: 1.0),
            majorTickMeters: unit.meters(from: 10.0),
            visibleSpanMeters: unit.meters(from: 1_000.0)
        )
    }

    public func validate() throws {
        guard minorTickMeters.isFinite,
              majorTickMeters.isFinite,
              visibleSpanMeters.isFinite,
              minorTickMeters > 0.0,
              majorTickMeters > minorTickMeters,
              visibleSpanMeters >= majorTickMeters else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Ruler distances must be finite, positive, and ordered."
            )
        }
    }
}
