import RupaDomainFoundation

public struct AgentSemanticAngle: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: AgentSemanticUnit

    private enum CodingKeys: String, CodingKey { case value, unit }

    public init(value: Double, unit: AgentSemanticUnit) {
        self.value = value
        self.unit = unit
    }

    public init(_ value: SemanticAngle) {
        self.init(value: value.value, unit: AgentSemanticUnit(value.unit))
    }

    public var semanticValue: SemanticAngle {
        SemanticAngle(value: value, unit: unit.semanticValue)
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["value", "unit"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            value: try container.decode(Double.self, forKey: .value),
            unit: try container.decode(AgentSemanticUnit.self, forKey: .unit)
        )
    }
}
