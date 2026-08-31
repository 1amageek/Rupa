import RupaCore

public indirect enum SemanticValueType: Sendable, Equatable, Hashable {
    case text
    case boolean
    case integer
    case number(unit: SemanticUnit)
    case point
    case direction
    case plane
    case transform
    case array(element: SemanticValueType?)
    case object
    case feature
    case sourceBody(role: SourceBodyOutputRole)
    case sceneNode
    case componentDefinition
    case componentInstance
    case patternArraySource

    public var isSourceIdentity: Bool {
        switch self {
        case .feature, .sourceBody, .sceneNode, .componentDefinition,
             .componentInstance, .patternArraySource:
            return true
        case .text, .boolean, .integer, .number, .point, .direction, .plane,
             .transform, .array, .object:
            return false
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .integer, .number:
            return true
        case .text, .boolean, .point, .direction, .plane, .transform, .array,
             .object, .feature, .sourceBody, .sceneNode,
             .componentDefinition, .componentInstance, .patternArraySource:
            return false
        }
    }

    public var isStructured: Bool {
        switch self {
        case .array, .object:
            return true
        case .text, .boolean, .integer, .number, .point, .direction, .plane,
             .transform, .feature, .sourceBody, .sceneNode, .componentDefinition,
             .componentInstance, .patternArraySource:
            return false
        }
    }
}

public typealias SemanticReferenceKind = SemanticValueType
