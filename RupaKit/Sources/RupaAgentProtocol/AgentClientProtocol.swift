import Foundation

public protocol AgentClientProtocol {
    func send(_ request: AgentRequest) throws -> AgentResponse
    func send(_ request: AgentRequest) async throws -> AgentResponse
}
