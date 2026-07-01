import Foundation
import RupaCoreTypes

public struct RulerConfiguration: Codable, Hashable, Sendable {
    public static let minorTickMetersRange: ClosedRange<Double> = 1.0e-6 ... 10_000.0
    public static let majorTickMetersRange: ClosedRange<Double> = 2.0e-6 ... 100_000.0
    public static let visibleSpanMetersRange: ClosedRange<Double> = 1.0e-5 ... 1_000_000.0

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
        ).normalizedForWorkspaceScale()
    }

    public func replacingDisplayUnit(
        _ unit: LengthDisplayUnit
    ) -> RulerConfiguration {
        RulerConfiguration(
            displayUnit: unit,
            minorTickMeters: minorTickMeters,
            majorTickMeters: majorTickMeters,
            visibleSpanMeters: visibleSpanMeters
        ).normalizedForWorkspaceScale()
    }

    public func normalizedForWorkspaceScale() -> RulerConfiguration {
        var configuration = self
        configuration.minorTickMeters = Self.clamped(
            configuration.minorTickMeters,
            to: Self.minorTickMetersRange
        )
        configuration.majorTickMeters = Self.clamped(
            configuration.majorTickMeters,
            to: Self.majorTickMetersRange
        )
        configuration.visibleSpanMeters = Self.clamped(
            configuration.visibleSpanMeters,
            to: Self.visibleSpanMetersRange
        )

        configuration.majorTickMeters = max(
            configuration.majorTickMeters,
            configuration.minorTickMeters * 2.0
        )
        configuration.majorTickMeters = Self.clamped(
            configuration.majorTickMeters,
            to: Self.majorTickMetersRange
        )
        configuration.minorTickMeters = min(
            configuration.minorTickMeters,
            configuration.majorTickMeters / 2.0
        )
        configuration.minorTickMeters = Self.clamped(
            configuration.minorTickMeters,
            to: Self.minorTickMetersRange
        )

        configuration.visibleSpanMeters = max(
            configuration.visibleSpanMeters,
            configuration.majorTickMeters
        )
        configuration.visibleSpanMeters = Self.clamped(
            configuration.visibleSpanMeters,
            to: Self.visibleSpanMetersRange
        )
        configuration.majorTickMeters = min(
            configuration.majorTickMeters,
            configuration.visibleSpanMeters
        )
        configuration.majorTickMeters = max(
            configuration.majorTickMeters,
            configuration.minorTickMeters * 2.0
        )
        return configuration
    }

    public func validate() throws {
        guard minorTickMeters.isFinite,
              majorTickMeters.isFinite,
              visibleSpanMeters.isFinite,
              minorTickMeters > 0.0,
              majorTickMeters > minorTickMeters,
              visibleSpanMeters >= majorTickMeters else {
            throw DocumentValidationError.invalidProductMetadata(
                "Ruler distances must be finite, positive, and ordered."
            )
        }
        guard Self.minorTickMetersRange.contains(minorTickMeters),
              Self.majorTickMetersRange.contains(majorTickMeters),
              Self.visibleSpanMetersRange.contains(visibleSpanMeters) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Ruler distances must stay within the CAD workspace scale range."
            )
        }
    }

    private static func clamped(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else {
            return range.lowerBound
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
