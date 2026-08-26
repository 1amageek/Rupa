import Foundation
import RupaAgentProtocol

/// Preserves an Agent commit receipt at the CLI boundary.
public struct CLICommittedMutationError: Error, LocalizedError, Sendable {
    public let outcome: AgentCommittedMutationOutcome

    public init(outcome: AgentCommittedMutationOutcome) {
        self.outcome = outcome
    }

    public var errorDescription: String? {
        "Mutation already committed at project \(outcome.projectID.rawValue), generation \(outcome.documentGeneration.value), transaction \(outcome.transactionRevision.value), publication \(outcome.publicationSequence), workspace revision \(outcome.workspaceRevision.value). Refresh before continuing; retry is forbidden. \(outcome.message)"
    }
}
