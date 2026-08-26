import RupaAutomation
import RupaCore
import RupaCoreTypes

/// A non-source project interaction transaction.
///
/// Selection and workspace state are staged together and published as one state
/// when all requested changes validate. It never advances the source transaction
/// revision and is guarded by both source revision and publication sequence.
public struct ProjectInteractionTransaction: Sendable {
    public let mutation: ProjectInteractionMutation
    public let expectedProjectID: ProjectID
    public let expectedTransactionRevision: DocumentTransactionRevision
    public let expectedPublicationSequence: UInt64

    public init(
        selection: ProjectSelectionOperation? = nil,
        workspaceCommands: [WorkspaceCommand] = [],
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard selection != nil || !workspaceCommands.isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project interaction transactions require a selection operation or workspace command."
            )
        }
        self.mutation = .direct(
            selection: selection,
            workspaceCommands: workspaceCommands
        )
        self.expectedProjectID = expectedProjectID
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }

    public init(
        automation: PreparedAutomationBatch,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64
    ) throws {
        guard automation.effect == .workspaceMutation else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project interaction Automation transactions require a workspace-mutation batch."
            )
        }
        self.mutation = .automation(automation)
        self.expectedProjectID = expectedProjectID
        self.expectedTransactionRevision = expectedTransactionRevision
        self.expectedPublicationSequence = expectedPublicationSequence
    }

    public var selection: ProjectSelectionOperation? {
        guard case .direct(let selection, _) = mutation else {
            return nil
        }
        return selection
    }

    public var workspaceCommands: [WorkspaceCommand] {
        guard case .direct(_, let commands) = mutation else {
            return []
        }
        return commands
    }
}
