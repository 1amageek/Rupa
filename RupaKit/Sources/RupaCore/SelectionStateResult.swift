import Foundation

public struct SelectionStateResult: Codable, Equatable, Sendable {
    public var message: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var selectedTargets: [SelectionTarget]
    public var hoveredTarget: SelectionTarget?
    public var diagnostics: [EditorDiagnostic]

    public init(
        message: String,
        generation: DocumentGeneration,
        dirty: Bool,
        selectedTargets: [SelectionTarget],
        hoveredTarget: SelectionTarget? = nil,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.selectedTargets = selectedTargets
        self.hoveredTarget = hoveredTarget
        self.diagnostics = diagnostics
    }
}
