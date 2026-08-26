import RupaCore
import RupaCoreTypes

/// A non-source project interaction transaction.
///
/// Selection and workspace state are staged together and published as one state
/// when all requested changes validate. It never advances the source transaction
/// revision and is guarded by both source revision and publication sequence.
public struct ProjectInteractionTransaction: Sendable {
    public let selection: ProjectSelectionOperation?
    public let workspaceCommands: [WorkspaceCommand]
    public let expectedTransactionRevision: DocumentTransactionRevision
    public let expectedPublicationSequence: UInt64

    public init(
        selection: ProjectSelectionOperation? = nil,
        workspaceCommands: [WorkspaceCommand] = [],
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard selection != nil || !workspaceCommands.isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project interaction transactions require a selection operation or workspace command."
            )
        }
        self.selection = selection
        self.workspaceCommands = workspaceCommands
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }
}
