import RupaCore

public enum SemanticSourceReference: Sendable, Equatable, Hashable {
    case feature(FeatureID)
    case sourceBody(featureID: FeatureID, role: SourceBodyOutputRole)
    case sceneNode(SceneNodeID)
    case componentDefinition(ComponentDefinitionID)
    case componentInstance(ComponentInstanceID)
    case patternArraySource(PatternArraySourceID)

    public var type: SemanticValueType {
        switch self {
        case .feature: return .feature
        case .sourceBody(_, let role): return .sourceBody(role: role)
        case .sceneNode: return .sceneNode
        case .componentDefinition: return .componentDefinition
        case .componentInstance: return .componentInstance
        case .patternArraySource: return .patternArraySource
        }
    }
}
