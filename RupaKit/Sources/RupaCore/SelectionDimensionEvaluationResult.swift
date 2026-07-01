import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SelectionDimensionMeasurementResult: Codable, Equatable, Sendable {
    public var dimension: SelectionDimension
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var measured: Quantity
    public var target: Quantity
    public var residual: Quantity
    public var valueKind: DimensionSummaryValueKind
    public var measuredDisplayValue: Double
    public var targetDisplayValue: Double
    public var residualDisplayValue: Double
    public var displayUnitSymbol: String

    private enum CodingKeys: String, CodingKey {
        case dimension
        case first
        case second
        case measured
        case target
        case residual
        case valueKind
        case measuredDisplayValue
        case targetDisplayValue
        case residualDisplayValue
        case displayUnitSymbol
    }

    public init(
        dimension: SelectionDimension,
        first: SelectionMeasurementPoint,
        second: SelectionMeasurementPoint,
        measured: Quantity,
        target: Quantity,
        residual: Quantity,
        valueKind: DimensionSummaryValueKind? = nil,
        measuredDisplayValue: Double? = nil,
        targetDisplayValue: Double? = nil,
        residualDisplayValue: Double? = nil,
        displayUnitSymbol: String? = nil
    ) {
        let resolvedKind = valueKind ?? Self.valueKind(for: measured.kind)
        self.dimension = dimension
        self.first = first
        self.second = second
        self.measured = measured
        self.target = target
        self.residual = residual
        self.valueKind = resolvedKind
        self.measuredDisplayValue = measuredDisplayValue ?? measured.value
        self.targetDisplayValue = targetDisplayValue ?? target.value
        self.residualDisplayValue = residualDisplayValue ?? residual.value
        self.displayUnitSymbol = displayUnitSymbol ?? Self.defaultDisplayUnitSymbol(for: resolvedKind)
    }

    public init(
        measurement: SwiftCAD.SelectionDimensionMeasurement,
        displayUnit: LengthDisplayUnit
    ) {
        let valueKind = Self.valueKind(for: measurement.measured.kind)
        self.init(
            dimension: measurement.dimension,
            first: measurement.first,
            second: measurement.second,
            measured: measurement.measured,
            target: measurement.target,
            residual: measurement.residual,
            valueKind: valueKind,
            measuredDisplayValue: Self.displayValue(
                for: measurement.measured,
                valueKind: valueKind,
                unit: displayUnit
            ),
            targetDisplayValue: Self.displayValue(
                for: measurement.target,
                valueKind: valueKind,
                unit: displayUnit
            ),
            residualDisplayValue: Self.displayValue(
                for: measurement.residual,
                valueKind: valueKind,
                unit: displayUnit
            ),
            displayUnitSymbol: Self.displayUnitSymbol(for: valueKind, unit: displayUnit)
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let measured = try container.decode(Quantity.self, forKey: .measured)
        let valueKind = try container.decodeIfPresent(
            DimensionSummaryValueKind.self,
            forKey: .valueKind
        ) ?? Self.valueKind(for: measured.kind)
        self.init(
            dimension: try container.decode(SelectionDimension.self, forKey: .dimension),
            first: try container.decode(SelectionMeasurementPoint.self, forKey: .first),
            second: try container.decode(SelectionMeasurementPoint.self, forKey: .second),
            measured: measured,
            target: try container.decode(Quantity.self, forKey: .target),
            residual: try container.decode(Quantity.self, forKey: .residual),
            valueKind: valueKind,
            measuredDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .measuredDisplayValue
            ),
            targetDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .targetDisplayValue
            ),
            residualDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .residualDisplayValue
            ),
            displayUnitSymbol: try container.decodeIfPresent(
                String.self,
                forKey: .displayUnitSymbol
            )
        )
    }

    public func displayed(in unit: LengthDisplayUnit) -> SelectionDimensionMeasurementResult {
        let valueKind = Self.valueKind(for: measured.kind)
        return SelectionDimensionMeasurementResult(
            dimension: dimension,
            first: first,
            second: second,
            measured: measured,
            target: target,
            residual: residual,
            valueKind: valueKind,
            measuredDisplayValue: Self.displayValue(for: measured, valueKind: valueKind, unit: unit),
            targetDisplayValue: Self.displayValue(for: target, valueKind: valueKind, unit: unit),
            residualDisplayValue: Self.displayValue(for: residual, valueKind: valueKind, unit: unit),
            displayUnitSymbol: Self.displayUnitSymbol(for: valueKind, unit: unit)
        )
    }

    public func isSatisfied(tolerance: ModelingTolerance = .standard) throws -> Bool {
        try tolerance.validate()
        switch residual.kind {
        case .length:
            return abs(residual.value) <= tolerance.distance
        case .angle:
            return abs(residual.value) <= tolerance.angle
        case .scalar:
            return abs(residual.value) <= tolerance.distance
        }
    }

    private static func valueKind(for quantityKind: QuantityKind) -> DimensionSummaryValueKind {
        switch quantityKind {
        case .length:
            .length
        case .angle:
            .angle
        case .scalar:
            .scalar
        }
    }

    private static func defaultDisplayUnitSymbol(for valueKind: DimensionSummaryValueKind) -> String {
        switch valueKind {
        case .length:
            LengthDisplayUnit.meter.symbol
        case .angle:
            "deg"
        case .scalar:
            ""
        }
    }

    private static func displayValue(
        for quantity: Quantity,
        valueKind: DimensionSummaryValueKind,
        unit: LengthDisplayUnit
    ) -> Double {
        switch valueKind {
        case .length:
            unit.value(fromMeters: quantity.value)
        case .angle:
            quantity.value * 180.0 / Double.pi
        case .scalar:
            quantity.value
        }
    }

    private static func displayUnitSymbol(
        for valueKind: DimensionSummaryValueKind,
        unit: LengthDisplayUnit
    ) -> String {
        switch valueKind {
        case .length:
            unit.symbol
        case .angle:
            "deg"
        case .scalar:
            ""
        }
    }
}

public struct SelectionDimensionEvaluationResult: Codable, Equatable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var displayUnitSymbol: String
    public var measurements: [SelectionDimensionMeasurementResult]

    private enum CodingKeys: String, CodingKey {
        case displayUnit
        case displayUnitSymbol
        case measurements
    }

    public init(
        displayUnit: LengthDisplayUnit,
        measurements: [SelectionDimensionMeasurementResult] = []
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnit.symbol
        self.measurements = measurements.map { $0.displayed(in: displayUnit) }
    }

    public init(
        evaluation: SwiftCAD.SelectionDimensionEvaluation,
        displayUnit: LengthDisplayUnit
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnit.symbol
        self.measurements = evaluation.measurements.map {
            SelectionDimensionMeasurementResult(
                measurement: $0,
                displayUnit: displayUnit
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayUnit = try container.decodeIfPresent(
            LengthDisplayUnit.self,
            forKey: .displayUnit
        ) ?? .meter
        self.init(
            displayUnit: displayUnit,
            measurements: try container.decode(
                [SelectionDimensionMeasurementResult].self,
                forKey: .measurements
            )
        )
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        for measurement in measurements {
            _ = try measurement.isSatisfied(tolerance: tolerance)
        }
    }
}
