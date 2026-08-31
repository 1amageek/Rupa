public enum AgentSemanticExecutionSuccess: Codable, Equatable, Sendable {
    case preview(AgentSemanticPreviewReceipt)
    case committed(AgentSemanticCommitReceipt)

    private enum Kind: String, Codable {
        case preview
        case committed
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case preview
        case committed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .preview: ["kind", "preview"]
        case .committed: ["kind", "committed"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .preview:
            self = .preview(try container.decode(AgentSemanticPreviewReceipt.self, forKey: .preview))
        case .committed:
            self = .committed(try container.decode(AgentSemanticCommitReceipt.self, forKey: .committed))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preview(let value):
            try container.encode(Kind.preview, forKey: .kind)
            try container.encode(value, forKey: .preview)
        case .committed(let value):
            try container.encode(Kind.committed, forKey: .kind)
            try container.encode(value, forKey: .committed)
        }
    }
}
