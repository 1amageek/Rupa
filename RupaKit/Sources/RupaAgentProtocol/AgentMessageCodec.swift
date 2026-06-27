import Foundation
import RupaCore

public struct AgentMessageCodec {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.encoder = encoder
        self.decoder = decoder
    }

    public func encode(_ request: AgentRequest, id: String = UUID().uuidString) throws -> Data {
        try encode(AgentRequestEnvelope(id: id, params: request))
    }

    public func encode(_ envelope: AgentRequestEnvelope) throws -> Data {
        try envelope.validate()
        return try encoder.encode(envelope)
    }

    public func encode(
        _ response: AgentResponse,
        id: String? = nil,
        method: String? = nil
    ) throws -> Data {
        try encode(AgentResponseEnvelope(id: id, response: response, method: method))
    }

    public func encode(_ envelope: AgentResponseEnvelope) throws -> Data {
        try envelope.validate()
        return try encoder.encode(envelope)
    }

    public func decodeRequestEnvelope(from data: Data) throws -> AgentRequestEnvelope {
        let envelope = try decoder.decode(AgentRequestEnvelope.self, from: data)
        try envelope.validate()
        return envelope
    }

    public func decodeRequest(from data: Data) throws -> AgentRequest {
        try decodeRequestEnvelope(from: data).params
    }

    public func decodeResponseEnvelope(from data: Data) throws -> AgentResponseEnvelope {
        let envelope = try decoder.decode(AgentResponseEnvelope.self, from: data)
        try envelope.validate()
        return envelope
    }

    public func decodeResponse(from data: Data) throws -> AgentResponse {
        try decodeResponseEnvelope(from: data).decodedResponse()
    }

    public func decodeResponse(from data: Data, expectedID: String) throws -> AgentResponse {
        try decodeResponse(from: data, expectedID: expectedID, expectedMethod: nil)
    }

    public func decodeResponse(
        from data: Data,
        expectedID: String,
        expectedMethod: String?
    ) throws -> AgentResponse {
        let envelope = try decodeResponseEnvelope(from: data)
        guard envelope.id == expectedID else {
            if envelope.error != nil {
                return try envelope.decodedResponse()
            }
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Agent response id mismatch. Expected \(expectedID), received \(envelope.id ?? "nil")."
            )
        }
        if let expectedMethod, envelope.method != expectedMethod {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Agent response method mismatch. Expected \(expectedMethod), received \(envelope.method ?? "nil")."
            )
        }
        return try envelope.decodedResponse()
    }
}
