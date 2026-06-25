import RupaAutomation
import RupaCore

public struct CLISelectionDimensionAddResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var diagnostics: [EditorDiagnostic]
    public var selectionDimensionID: SelectionDimensionID?

    public init(
        result: AutomationResult,
        dirty: Bool,
        saved: Bool
    ) {
        self.message = result.message
        self.generation = result.generation.value
        self.dirty = dirty
        self.saved = saved
        self.diagnostics = result.diagnostics
        self.selectionDimensionID = result.addedSelectionDimensionID
    }
}
