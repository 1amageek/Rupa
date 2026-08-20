import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public final class AgentClient: AgentClientProtocol {
    private struct ConnectionEstablishmentError: Error, Sendable {
        let editorError: EditorError
    }

    private static let asynchronousConnectionAttemptLimit = 100
    private static let asynchronousConnectionRetryDelay = Duration.milliseconds(20)

    public let socketPath: AgentSocketPath

    public init(socketPath: AgentSocketPath = AgentSocketPath()) {
        self.socketPath = socketPath
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        do {
            return try Self.sendOnce(
                request,
                socketPath: socketPath,
                codec: AgentMessageCodec()
            )
        } catch let error as ConnectionEstablishmentError {
            throw error.editorError
        }
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        let socketPath = socketPath
        var lastError: EditorError?
        for attempt in 0..<Self.asynchronousConnectionAttemptLimit {
            do {
                return try await Self.sendOnceInBackground(
                    request,
                    socketPath: socketPath
                )
            } catch let error as ConnectionEstablishmentError {
                lastError = error.editorError
                guard attempt + 1 < Self.asynchronousConnectionAttemptLimit else {
                    break
                }
                try await Task.sleep(for: Self.asynchronousConnectionRetryDelay)
            }
        }

        throw lastError ?? EditorError(
            code: .agentConnectionFailed,
            message: "Failed to connect to Rupa agent at \(socketPath.value)."
        )
    }

    private static func sendOnceInBackground(
        _ request: AgentRequest,
        socketPath: AgentSocketPath
    ) async throws -> AgentResponse {
        try await Task.detached {
            try sendOnce(
                request,
                socketPath: socketPath,
                codec: AgentMessageCodec()
            )
        }.value
    }

    private static func sendOnce(
        _ request: AgentRequest,
        socketPath: AgentSocketPath,
        codec: AgentMessageCodec
    ) throws -> AgentResponse {
        let descriptor = try makeConnectedSocket(socketPath: socketPath)
        defer {
            Darwin.close(descriptor)
        }

        let requestID = UUID().uuidString
        let requestData = try codec.encode(request, id: requestID)
        try AgentSocketIO.writeFrame(requestData, to: descriptor)

        let responseData = try AgentSocketIO.readFrame(from: descriptor)
        return try codec.decodeResponse(
            from: responseData,
            expectedID: requestID,
            expectedMethod: request.methodName
        )
    }

    private static func makeConnectedSocket(socketPath: AgentSocketPath) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw socketError(
                code: .agentUnavailable,
                message: "Failed to create agent socket."
            )
        }

        do {
            try AgentSocketIO.configure(descriptor)
            try connect(descriptor, socketPath: socketPath)
            return descriptor
        } catch let error as EditorError where error.code == .agentConnectionFailed {
            Darwin.close(descriptor)
            throw ConnectionEstablishmentError(editorError: error)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func connect(
        _ descriptor: Int32,
        socketPath: AgentSocketPath
    ) throws {
        try AgentSocketAddress.withUnixAddress(path: socketPath.value) { address, length in
            guard Darwin.connect(descriptor, address, length) == 0 else {
                throw socketError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect to Rupa agent at \(socketPath.value)."
                )
            }
        }
    }

    private static func socketError(
        code: EditorError.Code,
        message: String
    ) -> EditorError {
        EditorError(
            code: code,
            message: "\(message) errno=\(errno)"
        )
    }
}
