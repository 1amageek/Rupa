import Darwin
import Foundation
import RupaAgentProtocol

/// Owns the loopback listener for one App launch generation.
public actor AgentHTTPListener {
    public static let maximumConcurrentConnectionCount = 32

    private struct ActiveConnection: Sendable {
        var descriptor: Int32?
        let task: Task<Void, Never>
    }

    private let handler: any AgentRequestHandling
    private let key: Data
    private let generation: UInt64
    private let requestedPort: UInt16
    private let requestTimeout: Duration
    private let challengeTimeout: Duration
    private let shutdownTimeout: Duration
    private var listenDescriptor: Int32?
    private var acceptTask: Task<Void, Never>?
    private var activeConnections: [UInt64: ActiveConnection] = [:]
    private var nextConnectionID: UInt64 = 0
    private var stopping = false
    private var stopped = false
    private var endpoint: AgentHTTPEndpoint?

    public init(
        handler: any AgentRequestHandling,
        key: Data,
        generation: UInt64,
        requestedPort: UInt16 = 0,
        requestTimeout: Duration = .seconds(30),
        challengeTimeout: Duration = .seconds(5),
        shutdownTimeout: Duration = .seconds(5)
    ) {
        self.handler = handler
        self.key = key
        self.generation = generation
        self.requestedPort = requestedPort
        self.requestTimeout = requestTimeout
        self.challengeTimeout = challengeTimeout
        self.shutdownTimeout = shutdownTimeout
    }

    public var isRunning: Bool {
        listenDescriptor != nil && !stopping
    }

    public var currentEndpoint: AgentHTTPEndpoint? {
        endpoint
    }

    public var activeConnectionCount: Int {
        activeConnections.count
    }

    /// Binds the loopback listener and returns the actual dynamic port.
    public func start() async throws -> AgentHTTPEndpoint {
        guard !stopping, !stopped else {
            throw AgentHTTPError.listenerFailed("The Rupa agent listener is stopping.")
        }
        guard listenDescriptor == nil else {
            guard let endpoint else {
                throw AgentHTTPError.listenerFailed("The Rupa agent listener endpoint is unavailable.")
            }
            return endpoint
        }
        guard key.count == AgentHTTPAuthentication.keyByteCount else {
            throw AgentHTTPError.invalidKey
        }
        guard generation != 0 else {
            throw AgentHTTPError.invalidGeneration
        }
        let created = try AgentHTTPWire.makeListener(requestedPort: requestedPort)
        listenDescriptor = created.descriptor
        endpoint = created.endpoint
        let descriptor = created.descriptor
        acceptTask = Task.detached {
            await Self.acceptLoop(descriptor: descriptor, listener: self)
        }
        return created.endpoint
    }

    /// Stops accepting and drains active connections within the bounded timeout.
    public func stop() async {
        if stopping {
            while stopping { await Task.yield() }
            return
        }
        guard listenDescriptor != nil || acceptTask != nil || !activeConnections.isEmpty else {
            endpoint = nil
            stopped = true
            return
        }

        stopping = true
        let descriptor = listenDescriptor
        let task = acceptTask
        listenDescriptor = nil
        acceptTask = nil
        endpoint = nil
        task?.cancel()
        if let descriptor {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        for connection in activeConnections.values {
            connection.task.cancel()
            if let descriptor = connection.descriptor {
                Darwin.shutdown(descriptor, SHUT_RDWR)
            }
        }

        do {
            let deadline = try AgentHTTPDeadline.request(timeout: shutdownTimeout)
            while !activeConnections.isEmpty {
                _ = try deadline.remainingMilliseconds()
                try await Task.sleep(for: .milliseconds(5))
            }
        } catch {
            // An exhausted or invalid drain budget proceeds to forced descriptor closure.
        }
        for connectionID in activeConnections.keys {
            guard let descriptor = activeConnections[connectionID]?.descriptor else { continue }
            Darwin.close(descriptor)
            activeConnections[connectionID]?.descriptor = nil
        }
        stopping = false
        stopped = true
    }

    private func acceptConnection(_ descriptor: Int32) {
        guard listenDescriptor != nil,
              !stopping,
              activeConnections.count < Self.maximumConcurrentConnectionCount,
              let endpoint else {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            return
        }
        do {
            try AgentHTTPWire.configure(descriptor)
        } catch {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            return
        }

        let connectionID = nextConnectionID
        nextConnectionID += 1
        let handler = handler
        let key = key
        let generation = generation
        let requestTimeout = requestTimeout
        let challengeTimeout = challengeTimeout
        let task = Task.detached {
            await Self.runConnection(
                descriptor: descriptor,
                endpoint: endpoint,
                key: key,
                generation: generation,
                requestTimeout: requestTimeout,
                challengeTimeout: challengeTimeout,
                handler: handler
            )
            await self.connectionDidFinish(connectionID)
        }
        activeConnections[connectionID] = ActiveConnection(
            descriptor: descriptor,
            task: task
        )
    }

    private func connectionDidFinish(_ connectionID: UInt64) {
        guard let connection = activeConnections.removeValue(forKey: connectionID) else { return }
        if let descriptor = connection.descriptor {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }

    private nonisolated static func acceptLoop(
        descriptor: Int32,
        listener: AgentHTTPListener
    ) async {
        while !Task.isCancelled {
            let connection = Darwin.accept(descriptor, nil, nil)
            if connection >= 0 {
                await listener.acceptConnection(connection)
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                do {
                    try await Task.sleep(for: .milliseconds(5))
                } catch {
                    return
                }
            } else {
                return
            }
        }
    }

    private nonisolated static func runConnection(
        descriptor: Int32,
        endpoint: AgentHTTPEndpoint,
        key: Data,
        generation: UInt64,
        requestTimeout: Duration,
        challengeTimeout: Duration,
        handler: any AgentRequestHandling
    ) async {
        let deadline: AgentHTTPDeadline
        do {
            deadline = try AgentHTTPDeadline.request(timeout: requestTimeout)
        } catch {
            return
        }
        var pending = Data()
        do {
            let challengeRead = try await AgentHTTPBlockingIO.readMessage(
                from: descriptor,
                pending: pending,
                deadline: deadline
            )
            let challenge = challengeRead.message
            pending = challengeRead.pending
            guard challenge.kind == .request,
                  challenge.method == "POST",
                  challenge.path == "/v1/challenge",
                  challenge.body.isEmpty,
                  try isJSONContentType(in: challenge) else {
                throw AgentHTTPError.unsupportedRoute
            }
            let version = try requiredHeader(AgentHTTPHeaders.version, in: challenge)
            let requestID = try requiredHeader(AgentHTTPHeaders.requestID, in: challenge)
            guard UUID(uuidString: requestID) != nil,
                  version == AgentHTTPAuthentication.protocolVersion else {
                throw AgentHTTPError.authenticationFailed
            }
            let clientNonce = try nonceHeader(AgentHTTPHeaders.clientNonce, in: challenge)
            let serverNonce = try AgentHTTPAuthentication.nonce()
            let serverProof = AgentHTTPAuthentication.challengeProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestID
            )
            let challengeResponse = try AgentHTTPWire.makeResponse(
                status: 200,
                headers: [
                    AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                    AgentHTTPHeaders.requestID: requestID,
                    AgentHTTPHeaders.generation: String(generation),
                    AgentHTTPHeaders.port: String(endpoint.port),
                    AgentHTTPHeaders.serverNonce: AgentHTTPAuthentication.encode(serverNonce),
                    AgentHTTPHeaders.serverProof: AgentHTTPAuthentication.encode(serverProof),
                    AgentHTTPHeaders.contentType: "application/json",
                    "Connection": "keep-alive",
                ],
                body: Data()
            )
            try await AgentHTTPBlockingIO.writeAll(
                challengeResponse,
                to: descriptor,
                deadline: deadline
            )

            let challengeExpiry = min(
                deadline.instant,
                ContinuousClock().now.advanced(by: challengeTimeout)
            )
            let rpcDeadline = try AgentHTTPDeadline.absolute(challengeExpiry)
            let rpc: AgentHTTPWire.Message
            do {
                let rpcRead = try await AgentHTTPBlockingIO.readMessage(
                    from: descriptor,
                    pending: pending,
                    deadline: rpcDeadline
                )
                rpc = rpcRead.message
                pending = rpcRead.pending
            } catch AgentHTTPError.deadlineExceeded {
                throw AgentHTTPError.challengeExpired
            }
            guard ContinuousClock().now < challengeExpiry else {
                throw AgentHTTPError.challengeExpired
            }
            guard rpc.kind == .request,
                  rpc.method == "POST",
                  rpc.path == "/v1/rpc",
                  try isJSONContentType(in: rpc) else {
                throw AgentHTTPError.unsupportedRoute
            }
            let rpcVersion = try requiredHeader(AgentHTTPHeaders.version, in: rpc)
            let rpcID = try requiredHeader(AgentHTTPHeaders.requestID, in: rpc)
            let rpcGeneration = try uint64Header(AgentHTTPHeaders.generation, in: rpc)
            let rpcPort = try uint16Header(AgentHTTPHeaders.port, in: rpc)
            let rpcClientNonce = try nonceHeader(AgentHTTPHeaders.clientNonce, in: rpc)
            let rpcServerNonce = try nonceHeader(AgentHTTPHeaders.serverNonce, in: rpc)
            let bodyDigest = try proofHeader(AgentHTTPHeaders.bodyDigest, in: rpc)
            let clientProof = try proofHeader(AgentHTTPHeaders.clientProof, in: rpc)
            guard rpcVersion == AgentHTTPAuthentication.protocolVersion,
                  rpcID == requestID,
                  rpcGeneration == generation,
                  rpcPort == endpoint.port,
                  AgentHTTPAuthentication.constantTimeEqual(rpcClientNonce, clientNonce),
                  AgentHTTPAuthentication.constantTimeEqual(rpcServerNonce, serverNonce),
                  AgentHTTPAuthentication.constantTimeEqual(
                    bodyDigest,
                    AgentHTTPAuthentication.digest(rpc.body)
                  ) else {
                throw AgentHTTPError.authenticationFailed
            }
            let expectedClientProof = AgentHTTPAuthentication.clientProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestID,
                bodyDigest: bodyDigest
            )
            guard AgentHTTPAuthentication.constantTimeEqual(clientProof, expectedClientProof) else {
                throw AgentHTTPError.authenticationFailed
            }

            let codec = AgentMessageCodec()
            let requestEnvelope = try codec.decodeRequestEnvelope(from: rpc.body)
            guard requestEnvelope.id == requestID else {
                throw AgentHTTPError.authenticationFailed
            }
            let response = try await dispatch(
                requestEnvelope.params,
                to: handler,
                deadline: deadline
            )
            let responseBody = try codec.encode(
                response,
                id: requestID,
                method: requestEnvelope.method
            )
            let responseDigest = AgentHTTPAuthentication.digest(responseBody)
            let responseProof = AgentHTTPAuthentication.responseProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestID,
                status: 200,
                responseDigest: responseDigest
            )
            let responseMessage = try AgentHTTPWire.makeResponse(
                status: 200,
                headers: [
                    AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                    AgentHTTPHeaders.requestID: requestID,
                    AgentHTTPHeaders.generation: String(generation),
                    AgentHTTPHeaders.port: String(endpoint.port),
                    AgentHTTPHeaders.responseDigest: AgentHTTPAuthentication.encode(responseDigest),
                    AgentHTTPHeaders.responseProof: AgentHTTPAuthentication.encode(responseProof),
                    AgentHTTPHeaders.contentType: "application/json",
                    "Connection": "close",
                ],
                body: responseBody
            )
            try await AgentHTTPBlockingIO.writeAll(
                responseMessage,
                to: descriptor,
                deadline: deadline
            )
        } catch is CancellationError {
            return
        } catch {
            await sendFailure(
                error,
                to: descriptor,
                deadline: deadline
            )
        }
    }

    private nonisolated static func sendFailure(
        _ error: Error,
        to descriptor: Int32,
        deadline: AgentHTTPDeadline
    ) async {
        let status: Int
        if let error = error as? AgentHTTPError {
            switch error {
            case .authenticationFailed, .challengeExpired:
                status = 401
            case .bodyTooLarge:
                status = 413
            case .unsupportedRoute:
                status = 404
            default:
                status = 400
            }
        } else {
            status = 400
        }
        let message = Data((error.localizedDescription).utf8)
        do {
            let response = try AgentHTTPWire.makeResponse(
                status: status,
                headers: [
                    AgentHTTPHeaders.contentType: "text/plain; charset=utf-8",
                    "Connection": "close",
                ],
                body: message
            )
            try await AgentHTTPBlockingIO.writeAll(
                response,
                to: descriptor,
                deadline: deadline
            )
        } catch {
            return
        }
    }

    private nonisolated static func requiredHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> String {
        guard let value = message.headers[name.lowercased()], !value.isEmpty else {
            throw AgentHTTPError.authenticationFailed
        }
        return value
    }

    private nonisolated static func isJSONContentType(
        in message: AgentHTTPWire.Message
    ) throws -> Bool {
        AgentHTTPWire.isJSONContentType(
            try requiredHeader(AgentHTTPHeaders.contentType, in: message)
        )
    }

    /// Races cooperative semantic work against the connection deadline without
    /// waiting for a non-cooperative handler after the transport has terminated.
    private nonisolated static func dispatch(
        _ request: AgentRequest,
        to handler: any AgentRequestHandling,
        deadline: AgentHTTPDeadline
    ) async throws -> AgentResponse {
        let (stream, continuation) = AsyncThrowingStream<AgentResponse, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let handlerTask = Task {
            let response = await handler.handle(request)
            guard !Task.isCancelled else { return }
            continuation.yield(response)
            continuation.finish()
        }
        let deadlineTask = Task {
            do {
                try await Task.sleep(until: deadline.instant, clock: .continuous)
            } catch {
                return
            }
            handlerTask.cancel()
            continuation.finish(throwing: AgentHTTPError.deadlineExceeded)
        }

        return try await withTaskCancellationHandler {
            defer {
                handlerTask.cancel()
                deadlineTask.cancel()
                continuation.finish()
            }
            var iterator = stream.makeAsyncIterator()
            guard let response = try await iterator.next() else {
                try Task.checkCancellation()
                throw AgentHTTPError.cancelled
            }
            return response
        } onCancel: {
            handlerTask.cancel()
            deadlineTask.cancel()
            continuation.finish(throwing: CancellationError())
        }
    }

    private nonisolated static func nonceHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> Data {
        let value = try requiredHeader(name, in: message)
        guard let data = AgentHTTPAuthentication.decode(value),
              data.count == AgentHTTPAuthentication.nonceByteCount else {
            throw AgentHTTPError.authenticationFailed
        }
        return data
    }

    private nonisolated static func proofHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> Data {
        let value = try requiredHeader(name, in: message)
        guard let data = AgentHTTPAuthentication.decode(value), data.count == 32 else {
            throw AgentHTTPError.authenticationFailed
        }
        return data
    }

    private nonisolated static func uint64Header(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> UInt64 {
        guard let value = message.headers[name.lowercased()], let number = UInt64(value) else {
            throw AgentHTTPError.authenticationFailed
        }
        return number
    }

    private nonisolated static func uint16Header(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> UInt16 {
        guard let value = message.headers[name.lowercased()], let number = UInt16(value) else {
            throw AgentHTTPError.authenticationFailed
        }
        return number
    }
}
