import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public final class AgentClient: AgentClientProtocol, Sendable {
    private struct ConnectionEstablishmentError: Error, Sendable {
        let editorError: EditorError
    }

    private static let asynchronousConnectionRetryDelay = Duration.milliseconds(20)

    public let endpoint: UnixSocketEndpoint
    public let requestTimeout: Duration

    public init(
        endpoint: UnixSocketEndpoint,
        requestTimeout: Duration = .seconds(30)
    ) {
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        do {
            let deadline = try AgentSocketDeadline.request(timeout: requestTimeout)
            return try Self.sendOnce(
                request,
                endpoint: endpoint,
                deadline: deadline,
                codec: AgentMessageCodec()
            )
        } catch let failure as AgentTransportFailure {
            throw failure
        } catch let error as ConnectionEstablishmentError {
            throw Self.failure(
                error.editorError,
                disposition: .notDispatched
            )
        } catch {
            throw Self.failure(error, disposition: .notDispatched)
        }
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        let deadline: AgentSocketDeadline
        do {
            deadline = try AgentSocketDeadline.request(timeout: requestTimeout)
        } catch {
            throw Self.failure(error, disposition: .notDispatched)
        }
        return try await send(request, deadline: deadline)
    }

    public func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        let transportDeadline: AgentSocketDeadline
        do {
            transportDeadline = try AgentSocketDeadline.absolute(deadline)
        } catch {
            throw Self.failure(error, disposition: .notDispatched)
        }
        return try await send(request, deadline: transportDeadline)
    }

    private func send(
        _ request: AgentRequest,
        deadline: AgentSocketDeadline
    ) async throws -> AgentResponse {
        let endpoint = endpoint
        let transportTask = Task.detached {
            do {
                return try await Self.sendWithConnectionRetries(
                    request,
                    endpoint: endpoint,
                    deadline: deadline
                )
            } catch let failure as AgentTransportFailure {
                throw failure
            } catch {
                throw Self.failure(error, disposition: .notDispatched)
            }
        }
        return try await withTaskCancellationHandler {
            try await transportTask.value
        } onCancel: {
            transportTask.cancel()
        }
    }

    private static func sendWithConnectionRetries(
        _ request: AgentRequest,
        endpoint: UnixSocketEndpoint,
        deadline: AgentSocketDeadline
    ) async throws -> AgentResponse {
        while true {
            try Task.checkCancellation()
            do {
                return try sendOnce(
                    request,
                    endpoint: endpoint,
                    deadline: deadline,
                    codec: AgentMessageCodec()
                )
            } catch is ConnectionEstablishmentError {
                let remainingMilliseconds = try deadline.remainingMilliseconds()
                let retryDelay = min(
                    asynchronousConnectionRetryDelay,
                    .milliseconds(Int64(remainingMilliseconds))
                )
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    private static func sendOnce(
        _ request: AgentRequest,
        endpoint: UnixSocketEndpoint,
        deadline: AgentSocketDeadline,
        codec: AgentMessageCodec
    ) throws -> AgentResponse {
        let descriptor = try makeConnectedSocket(
            endpoint: endpoint,
            deadline: deadline
        )
        defer {
            Darwin.close(descriptor)
        }

        let requestID = UUID()
        let requestIDString = requestID.uuidString
        let requestData = try codec.encode(request, id: requestIDString)
        try AgentSocketIO.writeFrame(
            requestData,
            to: descriptor,
            deadline: deadline
        )

        do {
            let responseData = try AgentSocketIO.readFrame(
                from: descriptor,
                deadline: deadline
            )
            return try codec.decodeResponse(
                from: responseData,
                expectedID: requestIDString,
                expectedMethod: request.methodName
            )
        } catch {
            throw failure(
                error,
                disposition: .outcomeUnknown(requestID: requestID)
            )
        }
    }

    private static func makeConnectedSocket(
        endpoint: UnixSocketEndpoint,
        deadline: AgentSocketDeadline
    ) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw socketError(
                code: .agentUnavailable,
                message: "Failed to create agent socket."
            )
        }

        do {
            try AgentSocketIO.configure(descriptor)
            try connect(
                descriptor,
                endpoint: endpoint,
                deadline: deadline
            )
            return descriptor
        } catch let error as EditorError {
            Darwin.close(descriptor)
            throw ConnectionEstablishmentError(editorError: error)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func connect(
        _ descriptor: Int32,
        endpoint: UnixSocketEndpoint,
        deadline: AgentSocketDeadline
    ) throws {
        try AgentSocketAddress.withUnixAddress(path: endpoint.path) { address, length in
            let result = Darwin.connect(descriptor, address, length)
            if result == 0 || errno == EISCONN {
                return
            }
            guard errno == EINPROGRESS || errno == EALREADY || errno == EAGAIN else {
                throw socketError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect to the injected Rupa agent endpoint."
                )
            }

            try AgentSocketIO.wait(
                for: Int16(POLLOUT),
                on: descriptor,
                deadline: deadline
            )
            var connectionError: Int32 = 0
            var connectionErrorLength = socklen_t(
                MemoryLayout.size(ofValue: connectionError)
            )
            guard getsockopt(
                descriptor,
                SOL_SOCKET,
                SO_ERROR,
                &connectionError,
                &connectionErrorLength
            ) == 0,
            connectionError == 0 else {
                let resolvedError = connectionError == 0 ? errno : connectionError
                throw EditorError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect to the injected Rupa agent endpoint. errno=\(resolvedError)"
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

    private static func failure(
        _ error: Error,
        disposition: AgentTransportFailure.DispatchDisposition
    ) -> AgentTransportFailure {
        let cause: AgentTransportFailure.Cause
        if error is CancellationError {
            cause = .cancelled
        } else if error is AgentSocketDeadlineError {
            cause = .deadlineExceeded
        } else if let editorError = error as? EditorError {
            cause = .transport(editorError)
        } else {
            cause = .transport(
                EditorError(
                    code: .agentConnectionFailed,
                    message: error.localizedDescription
                )
            )
        }
        return AgentTransportFailure(
            disposition: disposition,
            cause: cause
        )
    }
}
