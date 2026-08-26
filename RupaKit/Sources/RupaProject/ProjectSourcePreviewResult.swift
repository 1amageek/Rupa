import RupaAutomation
import RupaCore
import RupaCoreTypes

/// A validated source proposal that was never published to project authority.
public struct ProjectSourcePreviewResult: Sendable {
    public let base: ProjectPreviewBaseCoordinate
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let proposedDocumentGeneration: DocumentGeneration
    public let wouldMutate: Bool
    public let commandResults: [CommandExecutionResult]
    public let geometrySourceCommandResults: [GeometrySourceCommandResult]
    public let automationExecution: AutomationBatchExecution?
    public let diagnostics: [EditorDiagnostic]

    public init(
        base: ProjectPreviewBaseCoordinate,
        proposedTransactionRevision: DocumentTransactionRevision,
        proposedDocumentGeneration: DocumentGeneration,
        wouldMutate: Bool,
        commandResults: [CommandExecutionResult],
        geometrySourceCommandResults: [GeometrySourceCommandResult],
        automationExecution: AutomationBatchExecution? = nil,
        diagnostics: [EditorDiagnostic]
    ) {
        self.base = base
        self.proposedTransactionRevision = proposedTransactionRevision
        self.proposedDocumentGeneration = proposedDocumentGeneration
        self.wouldMutate = wouldMutate
        self.commandResults = commandResults
        self.geometrySourceCommandResults = geometrySourceCommandResults
        self.automationExecution = automationExecution
        self.diagnostics = diagnostics
    }
}
