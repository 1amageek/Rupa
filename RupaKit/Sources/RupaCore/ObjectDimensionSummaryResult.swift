import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ObjectDimensionSummaryResult: Codable, Equatable, Sendable {
    public enum SourceKind: String, Codable, Equatable, Sendable {
        case box
        case cylinder
    }

    public struct Counts: Codable, Equatable, Sendable {
        public var targetCount: Int
        public var entryCount: Int

        public init(targetCount: Int = 0, entryCount: Int = 0) {
            self.targetCount = targetCount
            self.entryCount = entryCount
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var target: SelectionTarget
        public var sceneNodeID: String
        public var sourceFeatureID: String
        public var sourceKind: SourceKind
        public var kind: ObjectDimensionKind
        public var label: String
        public var inputExpression: CADExpression
        public var sourceExpression: CADExpression?
        public var resolvedMeters: Double
        public var valueKind: DimensionSummaryValueKind
        public var resolvedDisplayValue: Double
        public var resolvedDisplayUnitSymbol: String
        public var isPrimaryForTarget: Bool

        private enum CodingKeys: String, CodingKey {
            case target
            case sceneNodeID
            case sourceFeatureID
            case sourceKind
            case kind
            case label
            case inputExpression
            case sourceExpression
            case resolvedMeters
            case valueKind
            case resolvedDisplayValue
            case resolvedDisplayUnitSymbol
            case isPrimaryForTarget
        }

        public init(
            target: SelectionTarget,
            sceneNodeID: String,
            sourceFeatureID: String,
            sourceKind: SourceKind,
            kind: ObjectDimensionKind,
            label: String,
            inputExpression: CADExpression,
            sourceExpression: CADExpression? = nil,
            resolvedMeters: Double,
            valueKind: DimensionSummaryValueKind = .length,
            resolvedDisplayValue: Double? = nil,
            resolvedDisplayUnitSymbol: String? = nil,
            isPrimaryForTarget: Bool
        ) {
            self.target = target
            self.sceneNodeID = sceneNodeID
            self.sourceFeatureID = sourceFeatureID
            self.sourceKind = sourceKind
            self.kind = kind
            self.label = label
            self.inputExpression = inputExpression
            self.sourceExpression = sourceExpression
            self.resolvedMeters = resolvedMeters
            self.valueKind = valueKind
            self.resolvedDisplayValue = resolvedDisplayValue ?? resolvedMeters
            self.resolvedDisplayUnitSymbol = resolvedDisplayUnitSymbol ?? LengthDisplayUnit.meter.symbol
            self.isPrimaryForTarget = isPrimaryForTarget
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let resolvedMeters = try container.decode(Double.self, forKey: .resolvedMeters)
            self.init(
                target: try container.decode(SelectionTarget.self, forKey: .target),
                sceneNodeID: try container.decode(String.self, forKey: .sceneNodeID),
                sourceFeatureID: try container.decode(String.self, forKey: .sourceFeatureID),
                sourceKind: try container.decode(SourceKind.self, forKey: .sourceKind),
                kind: try container.decode(ObjectDimensionKind.self, forKey: .kind),
                label: try container.decode(String.self, forKey: .label),
                inputExpression: try container.decode(CADExpression.self, forKey: .inputExpression),
                sourceExpression: try container.decodeIfPresent(
                    CADExpression.self,
                    forKey: .sourceExpression
                ),
                resolvedMeters: resolvedMeters,
                valueKind: try container.decodeIfPresent(
                    DimensionSummaryValueKind.self,
                    forKey: .valueKind
                ) ?? .length,
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
            Entry(
                target: target,
                sceneNodeID: sceneNodeID,
                sourceFeatureID: sourceFeatureID,
                sourceKind: sourceKind,
                kind: kind,
                label: label,
                inputExpression: inputExpression,
                sourceExpression: sourceExpression,
                resolvedMeters: resolvedMeters,
                valueKind: .length,
                resolvedDisplayValue: unit.value(fromMeters: resolvedMeters),
                resolvedDisplayUnitSymbol: unit.symbol,
                isPrimaryForTarget: isPrimaryForTarget
            )
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
