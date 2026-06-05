import Foundation

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

    public func encode(_ request: AgentRequest) throws -> Data {
        try encoder.encode(request)
    }

    public func encode(_ response: AgentResponse) throws -> Data {
        try encoder.encode(response)
    }

    public func decodeRequest(from data: Data) throws -> AgentRequest {
        try decoder.decode(AgentRequest.self, from: data)
    }

    public func decodeResponse(from data: Data) throws -> AgentResponse {
        try decoder.decode(AgentResponse.self, from: data)
    }
}
