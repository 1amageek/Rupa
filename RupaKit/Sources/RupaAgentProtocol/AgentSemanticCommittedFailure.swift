public struct AgentSemanticCommittedFailure: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case cancelled
        case viewProjectionFailed
        case resultProjectionFailed
        case evaluatedBodyUnavailable
        case authorityValidationFailed
    }

    public enum RetryDisposition: String, Codable, Equatable, Sendable {
        case mustNotRetry
    }

    public let code: Code
    public let authority: AgentProjectAuthorityCoordinate
    public let retryDisposition: RetryDisposition

    private enum CodingKeys: String, CodingKey { case code, authority, retryDisposition }

    public init(code: Code, authority: AgentProjectAuthorityCoordinate) {
        self.code = code
        self.authority = authority
        self.retryDisposition = .mustNotRetry
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["code", "authority", "retryDisposition"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let retryDisposition = try container.decode(RetryDisposition.self, forKey: .retryDisposition)
        self.init(
            code: try container.decode(Code.self, forKey: .code),
            authority: try container.decode(AgentProjectAuthorityCoordinate.self, forKey: .authority)
        )
        guard retryDisposition == self.retryDisposition else {
            throw DecodingError.dataCorruptedError(
                forKey: .retryDisposition,
                in: container,
                debugDescription: "Committed semantic failure retry disposition is fixed."
            )
        }
    }
}
