public struct AgentSemanticCommitReceipt: Codable, Equatable, Sendable {
    public let authority: AgentProjectAuthorityCoordinate
    public let outputs: [AgentSemanticOutputBinding]
    public let diagnostics: [AgentSemanticDiagnostic]
    public let telemetry: AgentSemanticTelemetry

    private enum CodingKeys: String, CodingKey { case authority, outputs, diagnostics, telemetry }

    public init(
        authority: AgentProjectAuthorityCoordinate,
        outputs: [AgentSemanticOutputBinding],
        diagnostics: [AgentSemanticDiagnostic],
        telemetry: AgentSemanticTelemetry
    ) {
        self.authority = authority
        self.outputs = outputs
        self.diagnostics = diagnostics
        self.telemetry = telemetry
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["authority", "outputs", "diagnostics", "telemetry"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            authority: try container.decode(AgentProjectAuthorityCoordinate.self, forKey: .authority),
            outputs: try container.decode([AgentSemanticOutputBinding].self, forKey: .outputs),
            diagnostics: try container.decode([AgentSemanticDiagnostic].self, forKey: .diagnostics),
            telemetry: try container.decode(AgentSemanticTelemetry.self, forKey: .telemetry)
        )
    }
}
