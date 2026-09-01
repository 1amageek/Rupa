import RupaAutomation
import RupaCore

public enum SemanticOutputSelector: Codable, Sendable, Equatable, Hashable {
    case feature(index: Int)
    case sourceBody(role: SourceBodyOutputRole, index: Int)
    case sceneNode(index: Int)
    case componentDefinition(index: Int)
    case componentInstance(index: Int)
    case patternArraySource(index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case index
        case role
    }

    private enum Kind: String, Codable {
        case feature
        case sourceBody
        case sceneNode
        case componentDefinition
        case componentInstance
        case patternArraySource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let index = try container.decode(Int.self, forKey: .index)
        switch kind {
        case .feature: self = .feature(index: index)
        case .sourceBody:
            self = .sourceBody(
                role: try container.decode(SourceBodyOutputRole.self, forKey: .role),
                index: index
            )
        case .sceneNode: self = .sceneNode(index: index)
        case .componentDefinition: self = .componentDefinition(index: index)
        case .componentInstance: self = .componentInstance(index: index)
        case .patternArraySource: self = .patternArraySource(index: index)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .feature(let index):
            try container.encode(Kind.feature, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .sourceBody(let role, let index):
            try container.encode(Kind.sourceBody, forKey: .kind)
            try container.encode(role, forKey: .role)
            try container.encode(index, forKey: .index)
        case .sceneNode(let index):
            try container.encode(Kind.sceneNode, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .componentDefinition(let index):
            try container.encode(Kind.componentDefinition, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .componentInstance(let index):
            try container.encode(Kind.componentInstance, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .patternArraySource(let index):
            try container.encode(Kind.patternArraySource, forKey: .kind)
            try container.encode(index, forKey: .index)
        }
    }

    public var type: SemanticValueType {
        switch self {
        case .feature: return .feature
        case .sourceBody(let role, _): return .sourceBody(role: role)
        case .sceneNode: return .sceneNode
        case .componentDefinition: return .componentDefinition
        case .componentInstance: return .componentInstance
        case .patternArraySource: return .patternArraySource
        }
    }

    public var index: Int {
        switch self {
        case .feature(let index),
             .sourceBody(_, let index),
             .sceneNode(let index),
             .componentDefinition(let index),
             .componentInstance(let index),
             .patternArraySource(let index):
            return index
        }
    }

    func preparedSelector() -> PreparedAutomationOutputSelector {
        switch self {
        case .feature(let index): return .feature(index: index)
        case .sourceBody(let role, let index): return .sourceBody(role: role, index: index)
        case .sceneNode(let index): return .sceneNode(index: index)
        case .componentDefinition(let index): return .componentDefinition(index: index)
        case .componentInstance(let index): return .componentInstance(index: index)
        case .patternArraySource(let index): return .patternArraySource(index: index)
        }
    }
}
