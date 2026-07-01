import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SketchDimensionSummaryResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var targetCount: Int
        public var entryCount: Int

        public init(targetCount: Int = 0, entryCount: Int = 0) {
            self.targetCount = targetCount
            self.entryCount = entryCount
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var requestedTarget: SelectionTarget
        public var target: SelectionTarget
        public var sceneNodeID: String
        public var sourceFeatureID: String
        public var entityID: String
        public var entityKind: String
        public var kind: SketchEntityDimensionKind
        public var label: String
        public var inputExpression: CADExpression
        public var resolvedValue: Double
        public var valueKind: DimensionSummaryValueKind
        public var resolvedDisplayValue: Double
        public var resolvedDisplayUnitSymbol: String
        public var isPrimaryForTarget: Bool

        private enum CodingKeys: String, CodingKey {
            case requestedTarget
            case target
            case sceneNodeID
            case sourceFeatureID
            case entityID
            case entityKind
            case kind
            case label
            case inputExpression
            case resolvedValue
            case valueKind
            case resolvedDisplayValue
            case resolvedDisplayUnitSymbol
            case isPrimaryForTarget
        }

        public init(
            requestedTarget: SelectionTarget,
            target: SelectionTarget,
            sceneNodeID: String,
            sourceFeatureID: String,
            entityID: String,
            entityKind: String,
            kind: SketchEntityDimensionKind,
            label: String,
            inputExpression: CADExpression,
            resolvedValue: Double,
            valueKind: DimensionSummaryValueKind? = nil,
            resolvedDisplayValue: Double? = nil,
            resolvedDisplayUnitSymbol: String? = nil,
            isPrimaryForTarget: Bool
        ) {
            self.requestedTarget = requestedTarget
            self.target = target
            self.sceneNodeID = sceneNodeID
            self.sourceFeatureID = sourceFeatureID
            self.entityID = entityID
            self.entityKind = entityKind
            self.kind = kind
            self.label = label
            self.inputExpression = inputExpression
            self.resolvedValue = resolvedValue
            self.valueKind = valueKind ?? Self.valueKind(for: kind)
            self.resolvedDisplayValue = resolvedDisplayValue ?? resolvedValue
            self.resolvedDisplayUnitSymbol = resolvedDisplayUnitSymbol ?? Self.defaultDisplayUnitSymbol(for: kind)
            self.isPrimaryForTarget = isPrimaryForTarget
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(SketchEntityDimensionKind.self, forKey: .kind)
            let resolvedValue = try container.decode(Double.self, forKey: .resolvedValue)
            self.init(
                requestedTarget: try container.decode(SelectionTarget.self, forKey: .requestedTarget),
                target: try container.decode(SelectionTarget.self, forKey: .target),
                sceneNodeID: try container.decode(String.self, forKey: .sceneNodeID),
                sourceFeatureID: try container.decode(String.self, forKey: .sourceFeatureID),
                entityID: try container.decode(String.self, forKey: .entityID),
                entityKind: try container.decode(String.self, forKey: .entityKind),
                kind: kind,
                label: try container.decode(String.self, forKey: .label),
                inputExpression: try container.decode(CADExpression.self, forKey: .inputExpression),
                resolvedValue: resolvedValue,
                valueKind: try container.decodeIfPresent(
                    DimensionSummaryValueKind.self,
                    forKey: .valueKind
                ),
                resolvedDisplayValue: try container.decodeIfPresent(
                    Double.self,
                    forKey: .resolvedDisplayValue
                ),
                resolvedDisplayUnitSymbol: try container.decodeIfPresent(
                    String.self,
                    forKey: .resolvedDisplayUnitSymbol
                ),
                isPrimaryForTarget: try container.decode(Bool.self, forKey: .isPrimaryForTarget)
            )
        }

        public func displayed(in unit: LengthDisplayUnit) -> Entry {
            let valueKind = Self.valueKind(for: kind)
            return Entry(
                requestedTarget: requestedTarget,
                target: target,
                sceneNodeID: sceneNodeID,
                sourceFeatureID: sourceFeatureID,
                entityID: entityID,
                entityKind: entityKind,
                kind: kind,
                label: label,
                inputExpression: inputExpression,
                resolvedValue: resolvedValue,
                valueKind: valueKind,
                resolvedDisplayValue: Self.displayValue(
                    for: resolvedValue,
                    valueKind: valueKind,
                    unit: unit
                ),
                resolvedDisplayUnitSymbol: Self.displayUnitSymbol(
                    for: valueKind,
                    unit: unit
                ),
                isPrimaryForTarget: isPrimaryForTarget
            )
        }

        private static func valueKind(for kind: SketchEntityDimensionKind) -> DimensionSummaryValueKind {
            switch kind {
            case .angle:
                .angle
            case .length, .radius, .diameter:
                .length
            }
        }

        private static func defaultDisplayUnitSymbol(for kind: SketchEntityDimensionKind) -> String {
            switch valueKind(for: kind) {
            case .angle:
                "deg"
            case .length:
                LengthDisplayUnit.meter.symbol
            }
        }

        private static func displayValue(
            for resolvedValue: Double,
            valueKind: DimensionSummaryValueKind,
            unit: LengthDisplayUnit
        ) -> Double {
            switch valueKind {
            case .angle:
                resolvedValue * 180.0 / Double.pi
            case .length:
                unit.value(fromMeters: resolvedValue)
            }
        }

        private static func displayUnitSymbol(
            for valueKind: DimensionSummaryValueKind,
            unit: LengthDisplayUnit
        ) -> String {
            switch valueKind {
            case .angle:
                "deg"
            case .length:
                unit.symbol
            }
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var displayUnitSymbol: String
    public var counts: Counts
    public var entries: [Entry]
    public var diagnostics: [EditorDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case displayUnit
        case displayUnitSymbol
        case counts
        case entries
        case diagnostics
    }

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        entries: [Entry] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnit.symbol
        self.counts = counts
        self.entries = entries.map { $0.displayed(in: displayUnit) }
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayUnit = try container.decode(LengthDisplayUnit.self, forKey: .displayUnit)
        self.init(
            displayUnit: displayUnit,
            counts: try container.decode(Counts.self, forKey: .counts),
            entries: try container.decode([Entry].self, forKey: .entries),
            diagnostics: try container.decodeIfPresent(
                [EditorDiagnostic].self,
                forKey: .diagnostics
            ) ?? []
        )
    }
}
