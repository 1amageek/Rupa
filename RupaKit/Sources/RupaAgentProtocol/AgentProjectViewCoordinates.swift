import Foundation
import RupaCore
import RupaCoreTypes

/// Coordinates and presentation state captured with a project Agent result.
/// This value is wire-safe; it never contains a live project view.
public struct AgentProjectViewCoordinates: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let projectID: ProjectID
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let workspaceRevision: WorkspaceRevision
    public let isDirty: Bool
    public let canUndo: Bool
    public let canRedo: Bool
    public let diagnostics: [EditorDiagnostic]

    public init(
        sessionID: UUID,
        projectID: ProjectID,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        workspaceRevision: WorkspaceRevision,
        isDirty: Bool,
        canUndo: Bool,
        canRedo: Bool,
        diagnostics: [EditorDiagnostic]
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.workspaceRevision = workspaceRevision
        self.isDirty = isDirty
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.diagnostics = diagnostics
    }
}
