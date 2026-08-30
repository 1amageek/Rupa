import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public actor AgentSocketService {
    private let handler: any AgentRequestHandling
    private let codec: AgentMessageCodec

    public init(
        handler: any AgentRequestHandling,
        codec: AgentMessageCodec = AgentMessageCodec()
    ) {
        self.handler = handler
        self.codec = codec
    }

    public func responseData(for requestData: Data) async throws -> Data {
        let requestEnvelope: AgentRequestEnvelope
        do {
            requestEnvelope = try codec.decodeRequestEnvelope(from: requestData)
        } catch {
            return try failureResponseData(for: error)
        }
        let response = await handler.handle(requestEnvelope.params)
        return try codec.encode(
            response,
            id: requestEnvelope.id,
            method: requestEnvelope.method
        )
    }

    public func failureResponseData(for error: Error) throws -> Data {
        let response: AgentResponse
        if let error = error as? EditorError {
            response = .failure(error)
        } else {
            response = .failure(
                EditorError(
                    code: .commandInvalid,
                    message: error.localizedDescription
                )
            )
        }
        return try codec.encode(response, id: nil)
    }
}
