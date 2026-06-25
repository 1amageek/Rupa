import Darwin
import Foundation
import RupaCore

public final class AgentClient: AgentClientProtocol {
    public var socketPath: AgentSocketPath
    private let codec: AgentMessageCodec

    public init(
        socketPath: AgentSocketPath = AgentSocketPath(),
        codec: AgentMessageCodec = AgentMessageCodec()
    ) {
        self.socketPath = socketPath
        self.codec = codec
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw socketError(
                code: .agentUnavailable,
                message: "Failed to create agent socket."
            )
        }
        defer {
            Darwin.close(descriptor)
        }

        try AgentSocketAddress.withUnixAddress(path: socketPath.value) { address, length in
            guard Darwin.connect(descriptor, address, length) == 0 else {
                throw socketError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect to Rupa agent at \(socketPath.value)."
                )
            }
        }

        let requestID = UUID().uuidString
        let requestData = try codec.encode(request, id: requestID)
        try AgentSocketIO.writeAll(requestData, to: descriptor)
        Darwin.shutdown(descriptor, SHUT_WR)

        let responseData = try AgentSocketIO.readAll(from: descriptor)
        return try codec.decodeResponse(from: responseData, expectedID: requestID)
    }

    private func socketError(
        code: EditorError.Code,
        message: String
    ) -> EditorError {
        EditorError(
            code: code,
            message: "\(message) errno=\(errno)"
        )
    }
}
