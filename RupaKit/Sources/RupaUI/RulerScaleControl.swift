import Foundation
import RupaCore

enum RulerScaleControl {
    typealias FieldPresentation = WorkspaceLengthFieldPresentation

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

    static func fieldPresentation(
        fromMeters meters: Double,
        preferredUnit: LengthDisplayUnit,
        for kind: Kind
    ) -> FieldPresentation {
        let resolvedMeters = clampedMeters(meters, for: kind)
        return workspaceLengthFieldPresentation(
            fromMeters: resolvedMeters,
            preferredUnit: preferredUnit
        )
    }

    static func fieldUnit(
        fromMeters meters: Double,
        preferredUnit: LengthDisplayUnit,
        for kind: Kind
    ) -> LengthDisplayUnit {
        fieldPresentation(
            fromMeters: meters,
            preferredUnit: preferredUnit,
            for: kind
        ).unit
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

    static func meters(
        fromFieldText text: String,
        unit: LengthDisplayUnit,
        for kind: Kind
    ) -> Double? {
        guard let meters = workspaceLengthMeters(
            fromFieldText: text,
            defaultUnit: unit
        ) else {
            return nil
        }
        return clampedMeters(max(meters, 0.0), for: kind)
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
