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
        public var isPrimaryForTarget: Bool

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
