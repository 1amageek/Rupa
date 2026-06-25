import Foundation
import RupaCore

public struct AgentResponseEnvelope: Codable, Equatable, Sendable {
    public static let protocolVersion = "2.0"

    public var jsonrpc: String
    public var id: String?
    public var result: AgentResponse?
    public var error: AgentErrorEnvelope?

    public init(
        id: String?,
        response: AgentResponse,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        switch response {
        case .failure(let editorError):
            self.result = nil
            self.error = AgentErrorEnvelope(error: editorError)
        default:
            self.result = response
            self.error = nil
        }
    }

    public init(
        id: String?,
        result: AgentResponse?,
        error: AgentErrorEnvelope?,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }

    public func decodedResponse() throws -> AgentResponse {
        try validate()
        if let result {
            return result
        }
        if let error {
            return .failure(error.editorError)
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Agent response envelope has no result or error."
        )
    }

    public func validate() throws {
        guard jsonrpc == Self.protocolVersion else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent protocol version: \(jsonrpc)."
            )
        }
        let hasResult = result != nil
        let hasError = error != nil
        guard hasResult != hasError else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent response envelope must contain exactly one result or error."
            )
        }
        if let result, case .failure = result {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent failure responses must be encoded as response errors."
            )
        }
    }
}
