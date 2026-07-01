import Foundation
import RupaCore

enum RulerScaleControl {
    enum Kind: CaseIterable {
        case minor
        case major
        case visible

        var meterRange: ClosedRange<Double> {
            switch self {
            case .minor:
                RulerConfiguration.minorTickMetersRange
            case .major:
                RulerConfiguration.majorTickMetersRange
            case .visible:
                RulerConfiguration.visibleSpanMetersRange
            }
        }
    }

    static func sliderRange(for kind: Kind) -> ClosedRange<Double> {
        let range = kind.meterRange
        return log10(range.lowerBound) ... log10(range.upperBound)
    }

    static func sliderValue(
        fromMeters meters: Double,
        for kind: Kind
    ) -> Double {
        log10(clampedMeters(meters, for: kind))
    }

    static func meters(
        fromSliderValue value: Double,
        for kind: Kind
    ) -> Double {
        clampedMeters(pow(10.0, value), for: kind)
    }

    static func fieldValue(
        fromMeters meters: Double,
        unit: LengthDisplayUnit,
        for kind: Kind
    ) -> Double {
        unit.value(fromMeters: clampedMeters(meters, for: kind))
    }

    static func meters(
        fromFieldValue value: Double,
        unit: LengthDisplayUnit,
        for kind: Kind
    ) -> Double {
        guard value.isFinite else {
            return kind.meterRange.lowerBound
        }
        return clampedMeters(unit.meters(from: max(value, 0.0)), for: kind)
    }

    static func clampedMeters(
        _ meters: Double,
        for kind: Kind
    ) -> Double {
        let range = kind.meterRange
        guard meters.isFinite else {
            return range.lowerBound
        }
        return min(max(meters, range.lowerBound), range.upperBound)
    }
}
