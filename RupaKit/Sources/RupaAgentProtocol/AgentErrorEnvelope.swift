import Foundation
import RupaCore

public struct AgentErrorEnvelope: Codable, Equatable, Sendable {
    public var code: EditorError.Code
    public var message: String
    public var committedMutation: AgentCommittedMutationOutcome?

    public init(
        code: EditorError.Code,
        message: String,
        committedMutation: AgentCommittedMutationOutcome? = nil
    ) {
        self.code = code
        self.message = message
        self.committedMutation = committedMutation
    }

    public init(error: EditorError) {
        self.init(
            code: error.code,
            message: error.message
        )
    }

    public init(committedMutation: AgentCommittedMutationOutcome) {
        self.init(
            code: .commandFailed,
            message: committedMutation.message,
            committedMutation: committedMutation
        )
    }

    public var editorError: EditorError {
        EditorError(code: code, message: message)
    }
}
