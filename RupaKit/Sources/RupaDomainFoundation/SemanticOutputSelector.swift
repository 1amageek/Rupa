import RupaAutomation
import RupaCore

public enum SemanticOutputSelector: Sendable, Equatable, Hashable {
    case feature(index: Int)
    case sourceBody(role: SourceBodyOutputRole, index: Int)
    case sceneNode(index: Int)
    case componentDefinition(index: Int)
    case componentInstance(index: Int)
    case patternArraySource(index: Int)

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
