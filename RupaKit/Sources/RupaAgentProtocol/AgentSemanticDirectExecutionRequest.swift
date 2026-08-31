import Foundation

public struct AgentSemanticDirectExecutionRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let authority: AgentProjectAuthorityCoordinate
    public let dryRun: Bool
    public let request: AgentSemanticDirectRequest

    private enum CodingKeys: String, CodingKey { case sessionID, authority, dryRun, request }

    public init(
        sessionID: UUID,
        authority: AgentProjectAuthorityCoordinate,
        dryRun: Bool,
        request: AgentSemanticDirectRequest
    ) {
        self.sessionID = sessionID
        self.authority = authority
        self.dryRun = dryRun
        self.request = request
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["sessionID", "authority", "dryRun", "request"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            authority: try container.decode(AgentProjectAuthorityCoordinate.self, forKey: .authority),
            dryRun: try container.decode(Bool.self, forKey: .dryRun),
            request: try container.decode(AgentSemanticDirectRequest.self, forKey: .request)
        )
    }
}
