public enum SemanticPayloadPathComponent: Codable, Hashable, Sendable {
    case key(String)
    case index(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case key
        case index
    }

    private enum Kind: String, Codable {
        case key
        case index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .key:
            self = .key(try container.decode(String.self, forKey: .key))
        case .index:
            self = .index(try container.decode(Int.self, forKey: .index))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let key):
            try container.encode(Kind.key, forKey: .kind)
            try container.encode(key, forKey: .key)
        case .index(let index):
            try container.encode(Kind.index, forKey: .kind)
            try container.encode(index, forKey: .index)
        }
    }
}
