import Foundation
import RupaCore

public struct AgentRequestEnvelope: Codable, Equatable, Sendable {
    public static let protocolVersion = "2.0"

    public var jsonrpc: String
    public var id: String
    public var method: String
    public var params: AgentRequest

    public init(
        id: String,
        method: String? = nil,
        params: AgentRequest,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method ?? params.methodName
        self.params = params
    }

    public func validate() throws {
        guard jsonrpc == Self.protocolVersion else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent protocol version: \(jsonrpc)."
            )
        }
        guard method == params.methodName else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent request method \(method) does not match payload method \(params.methodName)."
            )
        }
    }
}
