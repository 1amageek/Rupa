import RupaDomainFoundation

public indirect enum AgentSemanticDirectArgument: Codable, Equatable, Sendable {
    case literal(AgentSemanticTypedValue)
    case parameter(String)
    case existing(AgentSemanticSourceReference)
    case expression(AgentSemanticExpression)
    case array([AgentSemanticDirectArgument])
    case object([ObjectEntry])

    private enum Kind: String, Codable {
        case literal
        case parameter
        case existing
        case expression
        case array
        case object
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case literal
        case parameter
        case existing
        case expression
        case values
        case entries
    }

    public struct ObjectEntry: Codable, Equatable, Sendable {
        public let name: String
        public let value: AgentSemanticDirectArgument

        private enum CodingKeys: String, CodingKey { case name, value }

        public init(name: String, value: AgentSemanticDirectArgument) {
            self.name = name
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["name", "value"])
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(AgentSemanticDirectArgument.self, forKey: .value)
            )
        }
    }

    public init(_ value: SemanticArgument) throws {
        switch value {
        case .literal(let value): self = .literal(AgentSemanticTypedValue(value))
        case .parameter(let id): self = .parameter(id.rawValue)
        case .existing(let reference): self = .existing(AgentSemanticSourceReference(reference))
        case .local(let reference):
            throw AgentSemanticRequestError(
                code: .directLocalReference,
                name: "\(reference.node.rawValue).\(reference.output.rawValue)"
            )
        case .expression(let expression): self = .expression(AgentSemanticExpression(expression))
        case .array(let values): self = .array(try values.map(Self.init))
        case .object(let entries):
            self = .object(try entries.map { ObjectEntry(name: $0.key, value: try Self($0.value)) })
        }
    }

    public var semanticValue: SemanticArgument {
        switch self {
        case .literal(let value): .literal(value.semanticValue)
        case .parameter(let name): .parameter(ProgramParameterID(name))
        case .existing(let reference): .existing(reference.semanticValue)
        case .expression(let expression): .expression(expression.semanticValue)
        case .array(let values): .array(values.map(\.semanticValue))
        case .object(let entries):
            .object(entries.map { SemanticArgumentObjectEntry(key: $0.name, value: $0.value.semanticValue) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .literal: ["kind", "literal"]
        case .parameter: ["kind", "parameter"]
        case .existing: ["kind", "existing"]
        case .expression: ["kind", "expression"]
        case .array: ["kind", "values"]
        case .object: ["kind", "entries"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .literal:
            self = .literal(try container.decode(AgentSemanticTypedValue.self, forKey: .literal))
        case .parameter:
            self = .parameter(try container.decode(String.self, forKey: .parameter))
        case .existing:
            self = .existing(try container.decode(AgentSemanticSourceReference.self, forKey: .existing))
        case .expression:
            self = .expression(try container.decode(AgentSemanticExpression.self, forKey: .expression))
        case .array:
            self = .array(try container.decode([Self].self, forKey: .values))
        case .object:
            self = .object(try container.decode([ObjectEntry].self, forKey: .entries))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let value):
            try container.encode(Kind.literal, forKey: .kind)
            try container.encode(value, forKey: .literal)
        case .parameter(let name):
            try container.encode(Kind.parameter, forKey: .kind)
            try container.encode(name, forKey: .parameter)
        case .existing(let reference):
            try container.encode(Kind.existing, forKey: .kind)
            try container.encode(reference, forKey: .existing)
        case .expression(let expression):
            try container.encode(Kind.expression, forKey: .kind)
            try container.encode(expression, forKey: .expression)
        case .array(let values):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(values, forKey: .values)
        case .object(let entries):
            try container.encode(Kind.object, forKey: .kind)
            try container.encode(entries, forKey: .entries)
        }
    }
}
