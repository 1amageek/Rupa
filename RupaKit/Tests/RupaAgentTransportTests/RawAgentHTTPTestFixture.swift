import Darwin
import Foundation
import RupaAgentProtocol
@testable import RupaAgentTransport

struct RunningRawAgentHTTPServer<Result: Sendable>: Sendable {
    let endpoint: AgentHTTPEndpoint
    let result: Task<Result, any Error>
}

struct AbortedRawAgentHTTPServerResult<Result: Sendable>: Sendable {
    let operationResult: Result
    let acceptedAdditionalConnection: Bool
}

struct RawAgentHTTPChallenge: Sendable {
    let message: AgentHTTPWire.Message
    let requestID: String
    let clientNonce: Data
    let serverNonce: Data
}

enum RawAgentHTTPTestFixture {
    static func start<Result: Sendable>(
        timeout: Duration = .seconds(2),
        operation: @escaping @Sendable (
            _ listenerDescriptor: Int32,
            _ connectionDescriptor: Int32,
            _ endpoint: AgentHTTPEndpoint,
            _ deadline: AgentHTTPDeadline
        ) throws -> Result
    ) throws -> RunningRawAgentHTTPServer<Result> {
        let listener = try AgentHTTPWire.makeListener(requestedPort: 0)
        let task = Task.detached {
            defer {
                Darwin.shutdown(listener.descriptor, SHUT_RDWR)
                Darwin.close(listener.descriptor)
            }
            let deadline = try AgentHTTPDeadline.request(timeout: timeout)
            let connection = try acceptConnection(
                from: listener.descriptor,
                deadline: deadline
            )
            defer {
                Darwin.shutdown(connection, SHUT_RDWR)
                Darwin.close(connection)
            }
            return try operation(
                listener.descriptor,
                connection,
                listener.endpoint,
                deadline
            )
        }
        return RunningRawAgentHTTPServer(endpoint: listener.endpoint, result: task)
    }

    static func startAbortingConnectionAfterOperation<Result: Sendable>(
        timeout: Duration = .seconds(2),
        operation: @escaping @Sendable (
            _ connectionDescriptor: Int32,
            _ endpoint: AgentHTTPEndpoint,
            _ deadline: AgentHTTPDeadline
        ) throws -> Result
    ) throws -> RunningRawAgentHTTPServer<AbortedRawAgentHTTPServerResult<Result>> {
        let listener = try AgentHTTPWire.makeListener(requestedPort: 0)
        let task = Task.detached {
            defer {
                Darwin.shutdown(listener.descriptor, SHUT_RDWR)
                Darwin.close(listener.descriptor)
            }
            let deadline = try AgentHTTPDeadline.request(timeout: timeout)
            let connection = try acceptConnection(
                from: listener.descriptor,
                deadline: deadline
            )
            let operationResult: Result
            do {
                operationResult = try operation(
                    connection,
                    listener.endpoint,
                    deadline
                )
            } catch {
                Darwin.shutdown(connection, SHUT_RDWR)
                Darwin.close(connection)
                throw error
            }
            try abortAndClose(connection)
            return AbortedRawAgentHTTPServerResult(
                operationResult: operationResult,
                acceptedAdditionalConnection: try acceptsAdditionalConnection(
                    on: listener.descriptor
                )
            )
        }
        return RunningRawAgentHTTPServer(endpoint: listener.endpoint, result: task)
    }

    private static func abortAndClose(_ descriptor: Int32) throws {
        var option = linger(l_onoff: 1, l_linger: 0)
        let configured = withUnsafePointer(to: &option) { pointer in
            Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_LINGER,
                pointer,
                socklen_t(MemoryLayout<linger>.size)
            )
        }
        guard configured == 0 else {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            throw AgentHTTPError.connectionFailed(
                "The raw test server could not configure an abortive connection close."
            )
        }
        guard Darwin.close(descriptor) == 0 else {
            throw AgentHTTPError.connectionFailed(
                "The raw test server could not abort the connection."
            )
        }
    }

    static func acceptConnection(
        from listenerDescriptor: Int32,
        deadline: AgentHTTPDeadline
    ) throws -> Int32 {
        try AgentHTTPWire.wait(
            for: Int16(POLLIN),
            on: listenerDescriptor,
            deadline: deadline
        )
        let descriptor = Darwin.accept(listenerDescriptor, nil, nil)
        guard descriptor >= 0 else {
            throw AgentHTTPError.connectionFailed("The raw test server could not accept a connection.")
        }
        do {
            try AgentHTTPWire.configure(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func readMessage(
        from descriptor: Int32,
        deadline: AgentHTTPDeadline,
        pending: inout Data
    ) throws -> AgentHTTPWire.Message {
        try AgentHTTPWire.readMessage(
            from: descriptor,
            pending: &pending,
            deadline: deadline
        )
    }

    static func sendChallengeResponse(
        for challenge: AgentHTTPWire.Message,
        to descriptor: Int32,
        endpoint: AgentHTTPEndpoint,
        generation: UInt64,
        proofKey: Data,
        contentType: String = "application/json",
        connection: String = "keep-alive",
        deadline: AgentHTTPDeadline
    ) throws -> RawAgentHTTPChallenge {
        guard let requestID = challenge.headers[AgentHTTPHeaders.requestID.lowercased()],
              let clientNonceText = challenge.headers[AgentHTTPHeaders.clientNonce.lowercased()],
              let clientNonce = AgentHTTPAuthentication.decode(clientNonceText) else {
            throw AgentHTTPError.malformedMessage("The raw challenge fixture is missing authentication headers.")
        }
        let serverNonce = try AgentHTTPAuthentication.nonce()
        let serverProof = AgentHTTPAuthentication.challengeProof(
            key: proofKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            generation: generation,
            port: endpoint.port,
            requestID: requestID
        )
        let response = try AgentHTTPWire.makeResponse(
            status: 200,
            headers: [
                AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                AgentHTTPHeaders.requestID: requestID,
                AgentHTTPHeaders.generation: String(generation),
                AgentHTTPHeaders.port: String(endpoint.port),
                AgentHTTPHeaders.serverNonce: AgentHTTPAuthentication.encode(serverNonce),
                AgentHTTPHeaders.serverProof: AgentHTTPAuthentication.encode(serverProof),
                AgentHTTPHeaders.contentType: contentType,
                AgentHTTPHeaders.connection: connection,
            ],
            body: Data()
        )
        try AgentHTTPWire.writeAll(response, to: descriptor, deadline: deadline)
        return RawAgentHTTPChallenge(
            message: challenge,
            requestID: requestID,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
    }

    static func sendSemanticResponse(
        _ response: AgentResponse,
        for challenge: RawAgentHTTPChallenge,
        request rpc: AgentHTTPWire.Message,
        to descriptor: Int32,
        endpoint: AgentHTTPEndpoint,
        generation: UInt64,
        proofKey: Data,
        contentType: String = "application/json",
        deadline: AgentHTTPDeadline
    ) throws {
        let codec = AgentMessageCodec()
        let requestEnvelope = try codec.decodeRequestEnvelope(from: rpc.body)
        let responseBody = try codec.encode(
            response,
            id: challenge.requestID,
            method: requestEnvelope.method
        )
        let responseDigest = AgentHTTPAuthentication.digest(responseBody)
        let responseProof = AgentHTTPAuthentication.responseProof(
            key: proofKey,
            clientNonce: challenge.clientNonce,
            serverNonce: challenge.serverNonce,
            generation: generation,
            port: endpoint.port,
            requestID: challenge.requestID,
            status: 200,
            responseDigest: responseDigest
        )
        let message = try AgentHTTPWire.makeResponse(
            status: 200,
            headers: [
                AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                AgentHTTPHeaders.requestID: challenge.requestID,
                AgentHTTPHeaders.generation: String(generation),
                AgentHTTPHeaders.port: String(endpoint.port),
                AgentHTTPHeaders.responseDigest: AgentHTTPAuthentication.encode(responseDigest),
                AgentHTTPHeaders.responseProof: AgentHTTPAuthentication.encode(responseProof),
                AgentHTTPHeaders.contentType: contentType,
                AgentHTTPHeaders.connection: "close",
            ],
            body: responseBody
        )
        try AgentHTTPWire.writeAll(message, to: descriptor, deadline: deadline)
    }

    static func readOptionalNextMessage(
        from descriptor: Int32,
        timeout: Duration = .milliseconds(250),
        pending: inout Data
    ) throws -> AgentHTTPWire.Message? {
        let deadline = try AgentHTTPDeadline.request(timeout: timeout)
        do {
            return try readMessage(
                from: descriptor,
                deadline: deadline,
                pending: &pending
            )
        } catch AgentHTTPError.connectionFailed {
            return nil
        } catch AgentHTTPError.deadlineExceeded {
            return nil
        }
    }

    static func acceptsAdditionalConnection(
        on listenerDescriptor: Int32,
        timeout: Duration = .milliseconds(150)
    ) throws -> Bool {
        let deadline = try AgentHTTPDeadline.request(timeout: timeout)
        do {
            let descriptor = try acceptConnection(
                from: listenerDescriptor,
                deadline: deadline
            )
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            return true
        } catch AgentHTTPError.deadlineExceeded {
            return false
        }
    }

    static func parseRawMessage(_ raw: Data) async throws -> AgentHTTPWire.Message {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw AgentHTTPError.connectionFailed("The raw framing fixture could not create a socket pair.")
        }
        let reader = descriptors[0]
        let writer = descriptors[1]
        do {
            try AgentHTTPWire.configure(reader)
            try AgentHTTPWire.configure(writer)
        } catch {
            Darwin.close(reader)
            Darwin.close(writer)
            throw error
        }
        let writerTask = Task.detached {
            defer {
                Darwin.shutdown(writer, SHUT_RDWR)
                Darwin.close(writer)
            }
            let deadline = try AgentHTTPDeadline.request(timeout: .seconds(2))
            try AgentHTTPWire.writeAll(raw, to: writer, deadline: deadline)
        }
        defer {
            Darwin.shutdown(reader, SHUT_RDWR)
            Darwin.close(reader)
            writerTask.cancel()
        }
        var pending = Data()
        let deadline = try AgentHTTPDeadline.request(timeout: .seconds(2))
        let message = try AgentHTTPWire.readMessage(
            from: reader,
            pending: &pending,
            deadline: deadline
        )
        try await writerTask.value
        return message
    }

    static func exactSizeHeaderRequest(byteCount: Int) -> Data {
        let prefix = Data("POST /v1/challenge HTTP/1.1\r\nX-Fill: ".utf8)
        let suffix = Data("\r\nContent-Length: 0\r\n\r\n".utf8)
        precondition(byteCount >= prefix.count + suffix.count)
        var raw = prefix
        raw.append(Data(repeating: 0x61, count: byteCount - prefix.count - suffix.count))
        raw.append(suffix)
        return raw
    }
}
