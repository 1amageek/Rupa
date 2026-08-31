import RupaCore

/// The source identity kinds that can cross a prepared-program step boundary.
public enum PreparedAutomationIdentityKind: Sendable, Equatable, Hashable {
    case feature
    case sourceBody(role: SourceBodyOutputRole)
    case sceneNode
    case componentDefinition
    case componentInstance
    case patternArraySource
}
