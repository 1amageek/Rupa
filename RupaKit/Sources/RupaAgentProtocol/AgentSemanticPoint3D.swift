import RupaDomainFoundation

public struct AgentSemanticPoint3D: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: AgentSemanticUnit

    private enum CodingKeys: String, CodingKey { case x, y, z, unit }

    public init(x: Double, y: Double, z: Double, unit: AgentSemanticUnit) {
        self.x = x
        self.y = y
        self.z = z
        self.unit = unit
    }

    public init(_ value: SemanticPoint3D) {
        self.init(x: value.x, y: value.y, z: value.z, unit: AgentSemanticUnit(value.unit))
    }

    public var semanticValue: SemanticPoint3D {
        SemanticPoint3D(x: x, y: y, z: z, unit: unit.semanticValue)
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["x", "y", "z", "unit"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y),
            z: try container.decode(Double.self, forKey: .z),
            unit: try container.decode(AgentSemanticUnit.self, forKey: .unit)
        )
    }
}
