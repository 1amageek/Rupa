public enum AgentSemanticExecutionResult: Codable, Equatable, Sendable {
    case success(AgentSemanticExecutionSuccess)
    case prepublicationFailure(AgentSemanticPrepublicationFailure)
    case committedFailure(AgentSemanticCommittedFailure)

    private enum Kind: String, Codable {
        case success
        case prepublicationFailure
        case committedFailure
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case success
        case prepublicationFailure
        case committedFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .success: ["kind", "success"]
        case .prepublicationFailure: ["kind", "prepublicationFailure"]
        case .committedFailure: ["kind", "committedFailure"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .success:
            self = .success(try container.decode(AgentSemanticExecutionSuccess.self, forKey: .success))
        case .prepublicationFailure:
            self = .prepublicationFailure(
                try container.decode(AgentSemanticPrepublicationFailure.self, forKey: .prepublicationFailure)
            )
        case .committedFailure:
            self = .committedFailure(
                try container.decode(AgentSemanticCommittedFailure.self, forKey: .committedFailure)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let value):
            try container.encode(Kind.success, forKey: .kind)
            try container.encode(value, forKey: .success)
        case .prepublicationFailure(let value):
            try container.encode(Kind.prepublicationFailure, forKey: .kind)
            try container.encode(value, forKey: .prepublicationFailure)
        case .committedFailure(let value):
            try container.encode(Kind.committedFailure, forKey: .kind)
            try container.encode(value, forKey: .committedFailure)
        }
    }
}
