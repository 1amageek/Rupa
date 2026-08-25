import Foundation
import RupaCoreTypes

public struct PreparedEditorSourceTransaction<Value> {
    public let value: Value
    public let stagedDocument: DesignDocument
    public let baseGeneration: DocumentGeneration
    public let proposedGeneration: DocumentGeneration
    public let baseTransactionRevision: DocumentTransactionRevision
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let wouldMutate: Bool

    let ownerID: UUID
    let commandName: String
    let before: DocumentSnapshot
    let after: EditorSessionTransactionSnapshot

    init(
        value: Value,
        ownerID: UUID,
        commandName: String,
        before: DocumentSnapshot,
        after: EditorSessionTransactionSnapshot,
        baseTransactionRevision: DocumentTransactionRevision,
        proposedTransactionRevision: DocumentTransactionRevision,
        wouldMutate: Bool
    ) {
        self.value = value
        self.ownerID = ownerID
        self.commandName = commandName
        self.before = before
        self.after = after
        stagedDocument = after.store.document.document
        baseGeneration = before.generation
        proposedGeneration = after.store.document.generation
        self.baseTransactionRevision = baseTransactionRevision
        self.proposedTransactionRevision = proposedTransactionRevision
        self.wouldMutate = wouldMutate
    }
}

extension PreparedEditorSourceTransaction: Sendable where Value: Sendable {}
