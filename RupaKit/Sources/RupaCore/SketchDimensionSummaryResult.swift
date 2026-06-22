import Foundation
import SwiftCAD

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
        public var isPrimaryForTarget: Bool

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
            self.isPrimaryForTarget = isPrimaryForTarget
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var entries: [Entry]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        entries: [Entry] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.entries = entries
        self.diagnostics = diagnostics
    }
}
