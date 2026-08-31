import RupaCore
import RupaDomainFoundation

public enum AgentSemanticSourceReference: Codable, Equatable, Sendable {
    case feature(FeatureID)
    case sourceBody(featureID: FeatureID, role: SourceBodyOutputRole)
    case sceneNode(SceneNodeID)
    case componentDefinition(ComponentDefinitionID)
    case componentInstance(ComponentInstanceID)
    case patternArraySource(PatternArraySourceID)

    private enum Kind: String, Codable {
        case feature
        case sourceBody
        case sceneNode
        case componentDefinition
        case componentInstance
        case patternArraySource
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case featureID
        case role
        case sceneNodeID
        case componentDefinitionID
        case componentInstanceID
        case patternArraySourceID
    }

    public init(_ value: SemanticSourceReference) {
        self = switch value {
        case .feature(let id): .feature(id)
        case .sourceBody(let featureID, let role): .sourceBody(featureID: featureID, role: role)
        case .sceneNode(let id): .sceneNode(id)
        case .componentDefinition(let id): .componentDefinition(id)
        case .componentInstance(let id): .componentInstance(id)
        case .patternArraySource(let id): .patternArraySource(id)
        }
    }

    public var semanticValue: SemanticSourceReference {
        switch self {
        case .feature(let id): .feature(id)
        case .sourceBody(let featureID, let role): .sourceBody(featureID: featureID, role: role)
        case .sceneNode(let id): .sceneNode(id)
        case .componentDefinition(let id): .componentDefinition(id)
        case .componentInstance(let id): .componentInstance(id)
        case .patternArraySource(let id): .patternArraySource(id)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .feature: ["kind", "featureID"]
        case .sourceBody: ["kind", "featureID", "role"]
        case .sceneNode: ["kind", "sceneNodeID"]
        case .componentDefinition: ["kind", "componentDefinitionID"]
        case .componentInstance: ["kind", "componentInstanceID"]
        case .patternArraySource: ["kind", "patternArraySourceID"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .feature:
            self = .feature(try container.decode(FeatureID.self, forKey: .featureID))
        case .sourceBody:
            self = .sourceBody(
                featureID: try container.decode(FeatureID.self, forKey: .featureID),
                role: try container.decode(SourceBodyOutputRole.self, forKey: .role)
            )
        case .sceneNode:
            self = .sceneNode(try container.decode(SceneNodeID.self, forKey: .sceneNodeID))
        case .componentDefinition:
            self = .componentDefinition(
                try container.decode(ComponentDefinitionID.self, forKey: .componentDefinitionID)
            )
        case .componentInstance:
            self = .componentInstance(
                try container.decode(ComponentInstanceID.self, forKey: .componentInstanceID)
            )
        case .patternArraySource:
            self = .patternArraySource(
                try container.decode(PatternArraySourceID.self, forKey: .patternArraySourceID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .feature(let id):
            try container.encode(Kind.feature, forKey: .kind)
            try container.encode(id, forKey: .featureID)
        case .sourceBody(let featureID, let role):
            try container.encode(Kind.sourceBody, forKey: .kind)
            try container.encode(featureID, forKey: .featureID)
            try container.encode(role, forKey: .role)
        case .sceneNode(let id):
            try container.encode(Kind.sceneNode, forKey: .kind)
            try container.encode(id, forKey: .sceneNodeID)
        case .componentDefinition(let id):
            try container.encode(Kind.componentDefinition, forKey: .kind)
            try container.encode(id, forKey: .componentDefinitionID)
        case .componentInstance(let id):
            try container.encode(Kind.componentInstance, forKey: .kind)
            try container.encode(id, forKey: .componentInstanceID)
        case .patternArraySource(let id):
            try container.encode(Kind.patternArraySource, forKey: .kind)
            try container.encode(id, forKey: .patternArraySourceID)
        }
    }
}
