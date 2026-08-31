import RupaDomainFoundation

public struct AgentSemanticDirection3D: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    private enum CodingKeys: String, CodingKey { case x, y, z }

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ value: SemanticDirection3D) {
        self.init(x: value.x, y: value.y, z: value.z)
    }

    public var semanticValue: SemanticDirection3D {
        SemanticDirection3D(x: x, y: y, z: z)
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["x", "y", "z"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y),
            z: try container.decode(Double.self, forKey: .z)
        )
    }
}
