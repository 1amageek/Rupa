import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public protocol ProjectAccessSession: Sendable {
    var sessionID: UUID { get }
    /// The exact five-part authority coordinate captured when this session opened.
    var initialAuthority: AgentProjectAuthorityCoordinate { get }

    func send(_ request: AgentRequest) async throws -> AgentResponse

    func save(
        expectedGeneration: DocumentGeneration?
    ) async throws -> SaveResult

    func finish() async
}

public extension ProjectAccessSession {
    func validateSessionIdentity(of request: AgentRequest) throws {
        guard let requestSessionID = request.projectSessionID else {
            return
        }
        guard requestSessionID == sessionID else {
            throw ProjectAccessError.sessionMismatch(
                expected: sessionID,
                actual: requestSessionID
            )
        }
    }
}
