import RupaCore

public indirect enum SemanticValueType: Codable, Sendable, Equatable, Hashable {
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

    private enum CodingKeys: String, CodingKey {
        case kind
        case unit
        case element
        case role
    }

    private enum Kind: String, Codable {
        case text
        case boolean
        case integer
        case number
        case point
        case direction
        case plane
        case transform
        case array
        case object
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
        switch kind {
        case .text: self = .text
        case .boolean: self = .boolean
        case .integer: self = .integer
        case .number:
            self = .number(unit: try container.decode(SemanticUnit.self, forKey: .unit))
        case .point: self = .point
        case .direction: self = .direction
        case .plane: self = .plane
        case .transform: self = .transform
        case .array:
            self = .array(element: try container.decodeIfPresent(SemanticValueType.self, forKey: .element))
        case .object: self = .object
        case .feature: self = .feature
        case .sourceBody:
            self = .sourceBody(role: try container.decode(SourceBodyOutputRole.self, forKey: .role))
        case .sceneNode: self = .sceneNode
        case .componentDefinition: self = .componentDefinition
        case .componentInstance: self = .componentInstance
        case .patternArraySource: self = .patternArraySource
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text: try container.encode(Kind.text, forKey: .kind)
        case .boolean: try container.encode(Kind.boolean, forKey: .kind)
        case .integer: try container.encode(Kind.integer, forKey: .kind)
        case .number(let unit):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(unit, forKey: .unit)
        case .point: try container.encode(Kind.point, forKey: .kind)
        case .direction: try container.encode(Kind.direction, forKey: .kind)
        case .plane: try container.encode(Kind.plane, forKey: .kind)
        case .transform: try container.encode(Kind.transform, forKey: .kind)
        case .array(let element):
            try container.encode(Kind.array, forKey: .kind)
            try container.encodeIfPresent(element, forKey: .element)
        case .object: try container.encode(Kind.object, forKey: .kind)
        case .feature: try container.encode(Kind.feature, forKey: .kind)
        case .sourceBody(let role):
            try container.encode(Kind.sourceBody, forKey: .kind)
            try container.encode(role, forKey: .role)
        case .sceneNode: try container.encode(Kind.sceneNode, forKey: .kind)
        case .componentDefinition: try container.encode(Kind.componentDefinition, forKey: .kind)
        case .componentInstance: try container.encode(Kind.componentInstance, forKey: .kind)
        case .patternArraySource: try container.encode(Kind.patternArraySource, forKey: .kind)
        }
    }

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
