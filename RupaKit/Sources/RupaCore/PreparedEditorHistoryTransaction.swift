import Foundation
import RupaCoreTypes

/// An immutable undo or redo transition that has not been published to its owner session.
public struct PreparedEditorHistoryTransaction: Sendable {
    public let result: CommandExecutionResult
    public let stagedDocument: DesignDocument
    public let baseGeneration: DocumentGeneration
    public let proposedGeneration: DocumentGeneration
    public let baseTransactionRevision: DocumentTransactionRevision
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let canUndo: Bool
    public let canRedo: Bool

    public var stagedEvaluation: DocumentEvaluationContext? {
        after.store.evaluationCache.map(DocumentEvaluationContext.init(cache:))
    }

    let ownerID: UUID
    let baseSelection: SelectionModel
    let baseWorkspaceRevision: WorkspaceRevision
    let baseHistoryMutationToken: CommandStackMutationToken
    let after: EditorSessionTransactionSnapshot

    init(
        result: CommandExecutionResult,
        ownerID: UUID,
        baseGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        baseSelection: SelectionModel,
        baseWorkspaceRevision: WorkspaceRevision,
        baseHistoryMutationToken: CommandStackMutationToken,
        after: EditorSessionTransactionSnapshot
    ) {
        self.result = result
        self.stagedDocument = after.store.document.document
        self.baseGeneration = baseGeneration
        self.proposedGeneration = after.store.document.generation
        self.baseTransactionRevision = baseTransactionRevision
        self.proposedTransactionRevision = after.transactionRevision
        self.canUndo = !after.commandStack.undoEntries.isEmpty
        self.canRedo = !after.commandStack.redoEntries.isEmpty
        self.ownerID = ownerID
        self.baseSelection = baseSelection
        self.baseWorkspaceRevision = baseWorkspaceRevision
        self.baseHistoryMutationToken = baseHistoryMutationToken
        self.after = after
    }
}
