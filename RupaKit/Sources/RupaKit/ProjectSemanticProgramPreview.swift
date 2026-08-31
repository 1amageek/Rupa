import RupaCoreTypes
import RupaProject

public struct ProjectSemanticProgramPreview: Sendable, Equatable {
    public let authority: ProjectAuthorityCoordinate
    public let proposedDocumentGeneration: DocumentGeneration
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let diagnostics: [ProjectSemanticDiagnostic]
    public let telemetry: ProjectSemanticTelemetry

    public init(
        authority: ProjectAuthorityCoordinate,
        proposedDocumentGeneration: DocumentGeneration,
        proposedTransactionRevision: DocumentTransactionRevision,
        diagnostics: [ProjectSemanticDiagnostic],
        telemetry: ProjectSemanticTelemetry
    ) {
        self.authority = authority
        self.proposedDocumentGeneration = proposedDocumentGeneration
        self.proposedTransactionRevision = proposedTransactionRevision
        self.diagnostics = diagnostics
        self.telemetry = telemetry
    }
}
