import RupaDomainFoundation

public struct AgentSemanticPrepublicationFailure: Codable, Equatable, Sendable {
    public static let dispatchUnavailableCode: DomainCapabilityErrorCode = "dispatchUnavailable"

    public enum Stage: String, Codable, Equatable, Sendable {
        case dispatchUnavailable
        case compilationRejected
        case responsePlanRejected
        case authorityRejected
        case executionRejected
        case evaluationRejected
        case cancelled
    }

    public enum PublicationDisposition: String, Codable, Equatable, Sendable {
        case notPublished
    }

    public enum RetryDisposition: String, Codable, Equatable, Sendable {
        case retryPermitted
    }

    public let stage: Stage
    public let code: DomainCapabilityErrorCode
    public let publicationDisposition: PublicationDisposition
    public let retryDisposition: RetryDisposition

    private enum CodingKeys: String, CodingKey {
        case stage
        case code
        case publicationDisposition
        case retryDisposition
    }

    public init(stage: Stage, code: DomainCapabilityErrorCode) {
        self.stage = stage
        self.code = code
        self.publicationDisposition = .notPublished
        self.retryDisposition = .retryPermitted
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["stage", "code", "publicationDisposition", "retryDisposition"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let publicationDisposition = try container.decode(
            PublicationDisposition.self,
            forKey: .publicationDisposition
        )
        let retryDisposition = try container.decode(RetryDisposition.self, forKey: .retryDisposition)
        self.init(
            stage: try container.decode(Stage.self, forKey: .stage),
            code: DomainCapabilityErrorCode(
                rawValue: try container.decode(String.self, forKey: .code)
            )
        )
        guard publicationDisposition == self.publicationDisposition,
              retryDisposition == self.retryDisposition else {
            throw DecodingError.dataCorruptedError(
                forKey: .retryDisposition,
                in: container,
                debugDescription: "Prepublication semantic failure dispositions are fixed."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage, forKey: .stage)
        try container.encode(code.rawValue, forKey: .code)
        try container.encode(publicationDisposition, forKey: .publicationDisposition)
        try container.encode(retryDisposition, forKey: .retryDisposition)
    }
}
