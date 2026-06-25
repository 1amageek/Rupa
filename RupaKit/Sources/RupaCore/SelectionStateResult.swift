import Foundation

public struct SelectionStateResult: Codable, Equatable, Sendable {
    public var message: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var selectedTargets: [SelectionTarget]
    public var selectedReferences: [SelectionReference]
    public var hoveredTarget: SelectionTarget?
    public var hoveredReference: SelectionReference?
    public var diagnostics: [EditorDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case message
        case generation
        case dirty
        case selectedTargets
        case selectedReferences
        case hoveredTarget
        case hoveredReference
        case diagnostics
    }

    public init(
        message: String,
        generation: DocumentGeneration,
        dirty: Bool,
        selectedTargets: [SelectionTarget],
        selectedReferences: [SelectionReference] = [],
        hoveredTarget: SelectionTarget? = nil,
        hoveredReference: SelectionReference? = nil,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.selectedTargets = selectedTargets
        self.selectedReferences = selectedReferences
        self.hoveredTarget = hoveredTarget
        self.hoveredReference = hoveredReference
        self.diagnostics = diagnostics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            message: try container.decode(String.self, forKey: .message),
            generation: try container.decode(DocumentGeneration.self, forKey: .generation),
            dirty: try container.decode(Bool.self, forKey: .dirty),
            selectedTargets: try container.decode([SelectionTarget].self, forKey: .selectedTargets),
            selectedReferences: try container.decodeIfPresent(
                [SelectionReference].self,
                forKey: .selectedReferences
            ) ?? [],
            hoveredTarget: try container.decodeIfPresent(
                SelectionTarget.self,
                forKey: .hoveredTarget
            ),
            hoveredReference: try container.decodeIfPresent(
                SelectionReference.self,
                forKey: .hoveredReference
            ),
            diagnostics: try container.decode([EditorDiagnostic].self, forKey: .diagnostics)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(generation, forKey: .generation)
        try container.encode(dirty, forKey: .dirty)
        try container.encode(selectedTargets, forKey: .selectedTargets)
        try container.encode(selectedReferences, forKey: .selectedReferences)
        try container.encodeIfPresent(hoveredTarget, forKey: .hoveredTarget)
        try container.encodeIfPresent(hoveredReference, forKey: .hoveredReference)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}
