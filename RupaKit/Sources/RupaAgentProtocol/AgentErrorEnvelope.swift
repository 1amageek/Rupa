import Foundation
import RupaCore

public struct AgentErrorEnvelope: Codable, Equatable, Sendable {
    public var code: EditorError.Code
    public var message: String
    public var committedMutation: AgentCommittedMutationOutcome?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case committedMutation
    }

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

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["code", "message", "committedMutation"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(EditorError.Code.self, forKey: .code)
        self.message = try container.decode(String.self, forKey: .message)
        self.committedMutation = try container.decodeIfPresent(
            AgentCommittedMutationOutcome.self,
            forKey: .committedMutation
        )
    }

    public var editorError: EditorError {
        EditorError(code: code, message: message)
    }
}
