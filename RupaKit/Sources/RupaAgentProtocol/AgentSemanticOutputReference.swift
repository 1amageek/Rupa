import RupaDomainFoundation

public struct AgentSemanticOutputReference: Codable, Equatable, Sendable {
    public let node: String
    public let output: String
    public let kind: AgentSemanticReferenceKind

    private enum CodingKeys: String, CodingKey { case node, output, kind }

    public init(node: String, output: String, kind: AgentSemanticReferenceKind) {
        self.node = node
        self.output = output
        self.kind = kind
    }

    public init(_ value: SemanticOutputReference) {
        self.init(
            node: value.node.rawValue,
            output: value.output.rawValue,
            kind: AgentSemanticReferenceKind(value.kind)
        )
    }

    public var semanticValue: SemanticOutputReference {
        SemanticOutputReference(
            node: ProgramNodeSymbol(node),
            output: SemanticOutputID(output),
            kind: kind.semanticValue
        )
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["node", "output", "kind"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            node: try container.decode(String.self, forKey: .node),
            output: try container.decode(String.self, forKey: .output),
            kind: try container.decode(AgentSemanticReferenceKind.self, forKey: .kind)
        )
    }
}
