import RupaDomainFoundation

public struct AgentSemanticPlane: Codable, Equatable, Sendable {
    public let origin: AgentSemanticPoint3D
    public let normal: AgentSemanticDirection3D

    private enum CodingKeys: String, CodingKey { case origin, normal }

    public init(origin: AgentSemanticPoint3D, normal: AgentSemanticDirection3D) {
        self.origin = origin
        self.normal = normal
    }

    public init(_ value: SemanticPlane) {
        self.init(
            origin: AgentSemanticPoint3D(value.origin),
            normal: AgentSemanticDirection3D(value.normal)
        )
    }

    public var semanticValue: SemanticPlane {
        SemanticPlane(origin: origin.semanticValue, normal: normal.semanticValue)
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["origin", "normal"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            origin: try container.decode(AgentSemanticPoint3D.self, forKey: .origin),
            normal: try container.decode(AgentSemanticDirection3D.self, forKey: .normal)
        )
    }
}
