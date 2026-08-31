import RupaCoreTypes

public struct AgentSemanticDiagnostic: Codable, Equatable, Sendable {
    public let severity: EditorDiagnostic.Severity
    public let code: EditorDiagnostic.Code?
    public let message: String

    private enum CodingKeys: String, CodingKey { case severity, code, message }

    public init(
        severity: EditorDiagnostic.Severity,
        code: EditorDiagnostic.Code?,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["severity", "code", "message"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            severity: try container.decode(EditorDiagnostic.Severity.self, forKey: .severity),
            code: try container.decodeIfPresent(EditorDiagnostic.Code.self, forKey: .code),
            message: try container.decode(String.self, forKey: .message)
        )
    }
}
