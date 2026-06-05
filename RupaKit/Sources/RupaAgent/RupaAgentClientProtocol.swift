import Foundation

public protocol RupaAgentClientProtocol {
    func send(_ request: AgentRequest) throws -> AgentResponse
}
