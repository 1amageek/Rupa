import RupaCoreTypes

public struct AgentSemanticPreviewReceipt: Codable, Equatable, Sendable {
    public let authority: AgentProjectAuthorityCoordinate
    public let proposedDocumentGeneration: DocumentGeneration
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let diagnostics: [AgentSemanticDiagnostic]
    public let telemetry: AgentSemanticTelemetry

    private enum CodingKeys: String, CodingKey {
        case authority
        case proposedDocumentGeneration
        case proposedTransactionRevision
        case diagnostics
        case telemetry
    }

    public init(
        authority: AgentProjectAuthorityCoordinate,
        proposedDocumentGeneration: DocumentGeneration,
        proposedTransactionRevision: DocumentTransactionRevision,
        diagnostics: [AgentSemanticDiagnostic],
        telemetry: AgentSemanticTelemetry
    ) {
        self.authority = authority
        self.proposedDocumentGeneration = proposedDocumentGeneration
        self.proposedTransactionRevision = proposedTransactionRevision
        self.diagnostics = diagnostics
        self.telemetry = telemetry
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [
                "authority", "proposedDocumentGeneration", "proposedTransactionRevision",
                "diagnostics", "telemetry",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            authority: try container.decode(AgentProjectAuthorityCoordinate.self, forKey: .authority),
            proposedDocumentGeneration: try container.decode(DocumentGeneration.self, forKey: .proposedDocumentGeneration),
            proposedTransactionRevision: try container.decode(DocumentTransactionRevision.self, forKey: .proposedTransactionRevision),
            diagnostics: try container.decode([AgentSemanticDiagnostic].self, forKey: .diagnostics),
            telemetry: try container.decode(AgentSemanticTelemetry.self, forKey: .telemetry)
        )
    }
}
