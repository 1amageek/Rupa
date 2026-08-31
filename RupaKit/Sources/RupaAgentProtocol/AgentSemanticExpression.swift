import RupaDomainFoundation

public indirect enum AgentSemanticExpression: Codable, Equatable, Sendable {
    case literal(AgentSemanticTypedValue)
    case parameter(String)
    case add(AgentSemanticExpression, AgentSemanticExpression)
    case subtract(AgentSemanticExpression, AgentSemanticExpression)
    case multiply(AgentSemanticExpression, AgentSemanticExpression)
    case divide(AgentSemanticExpression, AgentSemanticExpression)
    case negate(AgentSemanticExpression)

    private enum Kind: String, Codable {
        case literal
        case parameter
        case add
        case subtract
        case multiply
        case divide
        case negate
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case literal
        case parameter
        case lhs
        case rhs
        case operand
    }

    public init(_ value: BoundedScalarExpression) {
        self = switch value {
        case .literal(let value): .literal(AgentSemanticTypedValue(value))
        case .parameter(let id): .parameter(id.rawValue)
        case .add(let lhs, let rhs): .add(Self(lhs), Self(rhs))
        case .subtract(let lhs, let rhs): .subtract(Self(lhs), Self(rhs))
        case .multiply(let lhs, let rhs): .multiply(Self(lhs), Self(rhs))
        case .divide(let lhs, let rhs): .divide(Self(lhs), Self(rhs))
        case .negate(let value): .negate(Self(value))
        }
    }

    public var semanticValue: BoundedScalarExpression {
        switch self {
        case .literal(let value): .literal(value.semanticValue)
        case .parameter(let name): .parameter(ProgramParameterID(name))
        case .add(let lhs, let rhs): .add(lhs.semanticValue, rhs.semanticValue)
        case .subtract(let lhs, let rhs): .subtract(lhs.semanticValue, rhs.semanticValue)
        case .multiply(let lhs, let rhs): .multiply(lhs.semanticValue, rhs.semanticValue)
        case .divide(let lhs, let rhs): .divide(lhs.semanticValue, rhs.semanticValue)
        case .negate(let value): .negate(value.semanticValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .literal: ["kind", "literal"]
        case .parameter: ["kind", "parameter"]
        case .add, .subtract, .multiply, .divide: ["kind", "lhs", "rhs"]
        case .negate: ["kind", "operand"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .literal:
            self = .literal(try container.decode(AgentSemanticTypedValue.self, forKey: .literal))
        case .parameter:
            self = .parameter(try container.decode(String.self, forKey: .parameter))
        case .add:
            self = .add(
                try container.decode(Self.self, forKey: .lhs),
                try container.decode(Self.self, forKey: .rhs)
            )
        case .subtract:
            self = .subtract(
                try container.decode(Self.self, forKey: .lhs),
                try container.decode(Self.self, forKey: .rhs)
            )
        case .multiply:
            self = .multiply(
                try container.decode(Self.self, forKey: .lhs),
                try container.decode(Self.self, forKey: .rhs)
            )
        case .divide:
            self = .divide(
                try container.decode(Self.self, forKey: .lhs),
                try container.decode(Self.self, forKey: .rhs)
            )
        case .negate:
            self = .negate(try container.decode(Self.self, forKey: .operand))
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
        case .add(let lhs, let rhs):
            try container.encode(Kind.add, forKey: .kind)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .subtract(let lhs, let rhs):
            try container.encode(Kind.subtract, forKey: .kind)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .multiply(let lhs, let rhs):
            try container.encode(Kind.multiply, forKey: .kind)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .divide(let lhs, let rhs):
            try container.encode(Kind.divide, forKey: .kind)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .negate(let value):
            try container.encode(Kind.negate, forKey: .kind)
            try container.encode(value, forKey: .operand)
        }
    }
}
