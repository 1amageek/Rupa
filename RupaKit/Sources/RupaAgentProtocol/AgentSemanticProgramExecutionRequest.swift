import Foundation

public struct AgentSemanticProgramExecutionRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let authority: AgentProjectAuthorityCoordinate
    public let dryRun: Bool
    public let program: AgentSemanticProgramRequest

    private enum CodingKeys: String, CodingKey { case sessionID, authority, dryRun, program }

    public init(
        sessionID: UUID,
        authority: AgentProjectAuthorityCoordinate,
        dryRun: Bool,
        program: AgentSemanticProgramRequest
    ) {
        self.sessionID = sessionID
        self.authority = authority
        self.dryRun = dryRun
        self.program = program
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["sessionID", "authority", "dryRun", "program"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            authority: try container.decode(AgentProjectAuthorityCoordinate.self, forKey: .authority),
            dryRun: try container.decode(Bool.self, forKey: .dryRun),
            program: try container.decode(AgentSemanticProgramRequest.self, forKey: .program)
        )
    }
}
