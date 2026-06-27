import Darwin
import Foundation
import RupaAgentProtocol
import RupaCore

public final class AgentClient: AgentClientProtocol {
    private static let connectionAttemptLimit = 100
    private static let connectionRetryDelayMicroseconds: useconds_t = 20_000

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
        let descriptor = try makeConnectedSocket()
        defer {
            Darwin.close(descriptor)
        }

        let requestID = UUID().uuidString
        let requestData = try codec.encode(request, id: requestID)
        try AgentSocketIO.writeAll(requestData, to: descriptor)
        Darwin.shutdown(descriptor, SHUT_WR)

        let responseData = try AgentSocketIO.readAll(from: descriptor)
        return try codec.decodeResponse(
            from: responseData,
            expectedID: requestID,
            expectedMethod: request.methodName
        )
    }

    private func makeConnectedSocket() throws -> Int32 {
        var lastError: EditorError?
        for attempt in 0..<Self.connectionAttemptLimit {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw socketError(
                    code: .agentUnavailable,
                    message: "Failed to create agent socket."
                )
            }

            do {
                try connect(descriptor)
                return descriptor
            } catch let error as EditorError {
                lastError = error
                Darwin.close(descriptor)
                if attempt + 1 < Self.connectionAttemptLimit {
                    Darwin.usleep(Self.connectionRetryDelayMicroseconds)
                }
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        throw lastError ?? EditorError(
            code: .agentConnectionFailed,
            message: "Failed to connect to Rupa agent at \(socketPath.value)."
        )
    }

    private func connect(_ descriptor: Int32) throws {
        try AgentSocketAddress.withUnixAddress(path: socketPath.value) { address, length in
            guard Darwin.connect(descriptor, address, length) == 0 else {
                throw socketError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect to Rupa agent at \(socketPath.value)."
                )
            }
        }
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
