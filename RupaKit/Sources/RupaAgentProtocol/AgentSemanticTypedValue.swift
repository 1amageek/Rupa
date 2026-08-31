import Foundation
import RupaDomainFoundation

public indirect enum AgentSemanticTypedValue: Codable, Equatable, Sendable {
    case text(String)
    case boolean(Bool)
    case integer(Int64)
    case number(Double, unit: AgentSemanticUnit)
    case point(AgentSemanticPoint3D)
    case direction(AgentSemanticDirection3D)
    case plane(AgentSemanticPlane)
    case transform(AgentSemanticTransform)
    case array([AgentSemanticTypedValue])
    case object([ObjectEntry])

    public struct ObjectEntry: Codable, Equatable, Sendable {
        public let name: String
        public let value: AgentSemanticTypedValue

        private enum CodingKeys: String, CodingKey { case name, value }

        public init(name: String, value: AgentSemanticTypedValue) {
            self.name = name
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["name", "value"])
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(AgentSemanticTypedValue.self, forKey: .value)
            )
        }
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
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case boolean
        case integer
        case number
        case unit
        case point
        case direction
        case plane
        case transform
        case values
        case entries
    }

    public init(_ value: SemanticTypedValue) {
        self = switch value {
        case .text(let value): .text(value)
        case .boolean(let value): .boolean(value)
        case .integer(let value): .integer(value)
        case .number(let value, let unit): .number(value, unit: AgentSemanticUnit(unit))
        case .point(let value): .point(AgentSemanticPoint3D(value))
        case .direction(let value): .direction(AgentSemanticDirection3D(value))
        case .plane(let value): .plane(AgentSemanticPlane(value))
        case .transform(let value): .transform(AgentSemanticTransform(value))
        case .array(let values): .array(values.map(AgentSemanticTypedValue.init))
        case .object(let entries):
            .object(entries.map { ObjectEntry(name: $0.key, value: AgentSemanticTypedValue($0.value)) })
        }
    }

    public var semanticValue: SemanticTypedValue {
        switch self {
        case .text(let value): .text(value)
        case .boolean(let value): .boolean(value)
        case .integer(let value): .integer(value)
        case .number(let value, let unit): .number(value, unit: unit.semanticValue)
        case .point(let value): .point(value.semanticValue)
        case .direction(let value): .direction(value.semanticValue)
        case .plane(let value): .plane(value.semanticValue)
        case .transform(let value): .transform(value.semanticValue)
        case .array(let values): .array(values.map(\.semanticValue))
        case .object(let entries):
            .object(entries.map { SemanticObjectEntry(key: $0.name, value: $0.value.semanticValue) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> = switch kind {
        case .text: ["kind", "text"]
        case .boolean: ["kind", "boolean"]
        case .integer: ["kind", "integer"]
        case .number: ["kind", "number", "unit"]
        case .point: ["kind", "point"]
        case .direction: ["kind", "direction"]
        case .plane: ["kind", "plane"]
        case .transform: ["kind", "transform"]
        case .array: ["kind", "values"]
        case .object: ["kind", "entries"]
        }
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .integer:
            self = .integer(try container.decode(Int64.self, forKey: .integer))
        case .number:
            self = .number(
                try container.decode(Double.self, forKey: .number),
                unit: try container.decode(AgentSemanticUnit.self, forKey: .unit)
            )
        case .point:
            self = .point(try container.decode(AgentSemanticPoint3D.self, forKey: .point))
        case .direction:
            self = .direction(try container.decode(AgentSemanticDirection3D.self, forKey: .direction))
        case .plane:
            self = .plane(try container.decode(AgentSemanticPlane.self, forKey: .plane))
        case .transform:
            self = .transform(try container.decode(AgentSemanticTransform.self, forKey: .transform))
        case .array:
            self = .array(try container.decode([AgentSemanticTypedValue].self, forKey: .values))
        case .object:
            self = .object(try container.decode([ObjectEntry].self, forKey: .entries))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .boolean)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .integer)
        case .number(let value, let unit):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .number)
            try container.encode(unit, forKey: .unit)
        case .point(let value):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode(value, forKey: .point)
        case .direction(let value):
            try container.encode(Kind.direction, forKey: .kind)
            try container.encode(value, forKey: .direction)
        case .plane(let value):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(value, forKey: .plane)
        case .transform(let value):
            try container.encode(Kind.transform, forKey: .kind)
            try container.encode(value, forKey: .transform)
        case .array(let values):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(values, forKey: .values)
        case .object(let entries):
            try container.encode(Kind.object, forKey: .kind)
            try container.encode(entries, forKey: .entries)
        }
    }
}
