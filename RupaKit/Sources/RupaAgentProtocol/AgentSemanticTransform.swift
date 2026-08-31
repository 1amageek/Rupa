import RupaDomainFoundation

public struct AgentSemanticTransform: Codable, Equatable, Sendable {
    public let translation: AgentSemanticPoint3D
    public let axisPoint: AgentSemanticPoint3D
    public let rotationAxis: AgentSemanticDirection3D
    public let rotation: AgentSemanticAngle

    private enum CodingKeys: String, CodingKey {
        case translation
        case axisPoint
        case rotationAxis
        case rotation
    }

    public init(
        translation: AgentSemanticPoint3D,
        axisPoint: AgentSemanticPoint3D,
        rotationAxis: AgentSemanticDirection3D,
        rotation: AgentSemanticAngle
    ) {
        self.translation = translation
        self.axisPoint = axisPoint
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    public init(_ value: SemanticTransform) {
        self.init(
            translation: AgentSemanticPoint3D(value.translation),
            axisPoint: AgentSemanticPoint3D(value.axisPoint),
            rotationAxis: AgentSemanticDirection3D(value.rotationAxis),
            rotation: AgentSemanticAngle(value.rotation)
        )
    }

    public var semanticValue: SemanticTransform {
        SemanticTransform(
            translation: translation.semanticValue,
            axisPoint: axisPoint.semanticValue,
            rotationAxis: rotationAxis.semanticValue,
            rotation: rotation.semanticValue
        )
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["translation", "axisPoint", "rotationAxis", "rotation"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            translation: try container.decode(AgentSemanticPoint3D.self, forKey: .translation),
            axisPoint: try container.decode(AgentSemanticPoint3D.self, forKey: .axisPoint),
            rotationAxis: try container.decode(AgentSemanticDirection3D.self, forKey: .rotationAxis),
            rotation: try container.decode(AgentSemanticAngle.self, forKey: .rotation)
        )
    }
}
