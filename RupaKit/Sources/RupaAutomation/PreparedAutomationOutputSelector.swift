import RupaCore

/// Selects one generated source identity by kind and stable result order.
public enum PreparedAutomationOutputSelector: Sendable, Equatable, Hashable {
    case feature(index: Int)
    case sourceBody(role: SourceBodyOutputRole, index: Int)
    case sceneNode(index: Int)
    case componentDefinition(index: Int)
    case componentInstance(index: Int)
    case patternArraySource(index: Int)

    public var kind: PreparedAutomationIdentityKind {
        switch self {
        case .feature:
            .feature
        case .sourceBody(let role, _):
            .sourceBody(role: role)
        case .sceneNode:
            .sceneNode
        case .componentDefinition:
            .componentDefinition
        case .componentInstance:
            .componentInstance
        case .patternArraySource:
            .patternArraySource
        }
    }

    var index: Int {
        switch self {
        case .feature(let index),
             .sourceBody(_, let index),
             .sceneNode(let index),
             .componentDefinition(let index),
             .componentInstance(let index),
             .patternArraySource(let index):
            index
        }
    }
}
