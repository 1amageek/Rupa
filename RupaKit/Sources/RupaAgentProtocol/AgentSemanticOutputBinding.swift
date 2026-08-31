import RupaCore

public struct AgentSemanticOutputBinding: Codable, Equatable, Sendable {
    public enum Value: Codable, Equatable, Sendable {
        case feature(FeatureID)
        case body(
            featureID: FeatureID,
            role: SourceBodyOutputRole,
            evaluatedBodyID: BodyID
        )
        case sceneNode(SceneNodeID)
        case componentDefinition(ComponentDefinitionID)
        case componentInstance(ComponentInstanceID)
        case patternArraySource(PatternArraySourceID)

        private enum Kind: String, Codable {
            case feature
            case body
            case sceneNode
            case componentDefinition
            case componentInstance
            case patternArraySource
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case featureID
            case role
            case evaluatedBodyID
            case sceneNodeID
            case componentDefinitionID
            case componentInstanceID
            case patternArraySourceID
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            let allowedKeys: Set<String> = switch kind {
            case .feature: ["kind", "featureID"]
            case .body: ["kind", "featureID", "role", "evaluatedBodyID"]
            case .sceneNode: ["kind", "sceneNodeID"]
            case .componentDefinition: ["kind", "componentDefinitionID"]
            case .componentInstance: ["kind", "componentInstanceID"]
            case .patternArraySource: ["kind", "patternArraySourceID"]
            }
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
            switch kind {
            case .feature:
                self = .feature(try container.decode(FeatureID.self, forKey: .featureID))
            case .body:
                self = .body(
                    featureID: try container.decode(FeatureID.self, forKey: .featureID),
                    role: try container.decode(SourceBodyOutputRole.self, forKey: .role),
                    evaluatedBodyID: try container.decode(BodyID.self, forKey: .evaluatedBodyID)
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
            case .body(let featureID, let role, let evaluatedBodyID):
                try container.encode(Kind.body, forKey: .kind)
                try container.encode(featureID, forKey: .featureID)
                try container.encode(role, forKey: .role)
                try container.encode(evaluatedBodyID, forKey: .evaluatedBodyID)
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

    public let output: AgentSemanticOutputReference
    public let value: Value

    private enum CodingKeys: String, CodingKey { case output, value }

    public init(output: AgentSemanticOutputReference, value: Value) {
        self.output = output
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["output", "value"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            output: try container.decode(AgentSemanticOutputReference.self, forKey: .output),
            value: try container.decode(Value.self, forKey: .value)
        )
    }
}
