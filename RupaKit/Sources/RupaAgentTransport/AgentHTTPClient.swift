import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes

/// Authenticated client for the live loopback agent HTTP adapter.
public final class AgentHTTPClient: Sendable {
    public let endpoint: AgentHTTPEndpoint
    public let generation: UInt64
    public let requestTimeout: Duration

    private let key: Data

    public init(
        endpoint: AgentHTTPEndpoint,
        key: Data,
        generation: UInt64,
        requestTimeout: Duration = .seconds(30)
    ) {
        self.endpoint = endpoint
        self.key = key
        self.generation = generation
        self.requestTimeout = requestTimeout
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        let deadline: AgentHTTPDeadline
        do {
            deadline = try AgentHTTPDeadline.request(timeout: requestTimeout)
        } catch {
            throw Self.failure(error, disposition: .notDispatched)
        }
        return try await send(request, deadline: deadline.instant)
    }

    public func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        let transportDeadline: AgentHTTPDeadline
        do {
            transportDeadline = try AgentHTTPDeadline.absolute(deadline)
        } catch {
            throw Self.failure(error, disposition: .notDispatched)
        }

        let endpoint = endpoint
        let key = key
        let generation = generation
        let task = Task.detached {
            try await Self.perform(
                request,
                endpoint: endpoint,
                key: key,
                generation: generation,
                deadline: transportDeadline
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func perform(
        _ request: AgentRequest,
        endpoint: AgentHTTPEndpoint,
        key: Data,
        generation: UInt64,
        deadline: AgentHTTPDeadline
    ) async throws -> AgentResponse {
        let requestID = UUID()
        let requestIDString = requestID.uuidString
        var semanticBodyWritten = false
        var pendingData = Data()

        do {
            guard key.count == AgentHTTPAuthentication.keyByteCount else {
                throw AgentHTTPError.invalidKey
            }
            guard generation != 0 else {
                throw AgentHTTPError.invalidGeneration
            }
            let codec = AgentMessageCodec()
            let body = try codec.encode(request, id: requestIDString)
            let clientNonce = try AgentHTTPAuthentication.nonce()
            let connection = try await AgentHTTPBlockingIO.connect(
                to: endpoint,
                deadline: deadline
            )
            defer { Darwin.close(connection) }

            let challengeRequest = try AgentHTTPWire.makeRequest(
                method: "POST",
                path: "/v1/challenge",
                headers: [
                    AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                    AgentHTTPHeaders.requestID: requestIDString,
                    AgentHTTPHeaders.clientNonce: AgentHTTPAuthentication.encode(clientNonce),
                    AgentHTTPHeaders.contentType: "application/json",
                    "Connection": "keep-alive",
                ],
                body: Data()
            )
            try await AgentHTTPBlockingIO.writeAll(
                challengeRequest,
                to: connection,
                deadline: deadline
            )
            let challengeRead = try await AgentHTTPBlockingIO.readMessage(
                from: connection,
                pending: pendingData,
                deadline: deadline
            )
            let challenge = challengeRead.message
            pendingData = challengeRead.pending
            guard challenge.kind == .response,
                  challenge.status == 200,
                  challenge.body.isEmpty else {
                throw challengeError(for: challenge.status)
            }
            let serverNonce = try nonceHeader(AgentHTTPHeaders.serverNonce, in: challenge)
            let challengeGeneration = try uint64Header(AgentHTTPHeaders.generation, in: challenge)
            let challengePort = try uint16Header(AgentHTTPHeaders.port, in: challenge)
            let challengeVersion = try requiredHeader(AgentHTTPHeaders.version, in: challenge)
            let challengeID = try requiredHeader(AgentHTTPHeaders.requestID, in: challenge)
            let serverProof = try proofHeader(AgentHTTPHeaders.serverProof, in: challenge)
            guard challengeGeneration == generation,
                  challengePort == endpoint.port,
                  challengeVersion == AgentHTTPAuthentication.protocolVersion,
                  challengeID == requestIDString else {
                throw AgentHTTPError.authenticationFailed
            }
            let expectedChallengeProof = AgentHTTPAuthentication.challengeProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestIDString
            )
            guard AgentHTTPAuthentication.constantTimeEqual(serverProof, expectedChallengeProof) else {
                throw AgentHTTPError.authenticationFailed
            }
            try requireJSONContentType(in: challenge)
            let challengeConnection = try requiredHeader(AgentHTTPHeaders.connection, in: challenge)
            guard challengeConnection.caseInsensitiveCompare("keep-alive") == .orderedSame else {
                throw AgentHTTPError.connectionFailed(
                    "The authenticated challenge connection cannot continue to semantic dispatch."
                )
            }

            let bodyDigest = AgentHTTPAuthentication.digest(body)
            let clientProof = AgentHTTPAuthentication.clientProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestIDString,
                bodyDigest: bodyDigest
            )
            let rpcRequest = try AgentHTTPWire.makeRequest(
                method: "POST",
                path: "/v1/rpc",
                headers: [
                    AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
                    AgentHTTPHeaders.requestID: requestIDString,
                    AgentHTTPHeaders.generation: String(generation),
                    AgentHTTPHeaders.port: String(endpoint.port),
                    AgentHTTPHeaders.clientNonce: AgentHTTPAuthentication.encode(clientNonce),
                    AgentHTTPHeaders.serverNonce: AgentHTTPAuthentication.encode(serverNonce),
                    AgentHTTPHeaders.bodyDigest: AgentHTTPAuthentication.encode(bodyDigest),
                    AgentHTTPHeaders.clientProof: AgentHTTPAuthentication.encode(clientProof),
                    AgentHTTPHeaders.contentType: "application/json",
                    "Connection": "close",
                ],
                body: body
            )
            try await AgentHTTPBlockingIO.writeSemanticRequest(
                rpcRequest,
                to: connection,
                deadline: deadline
            )
            semanticBodyWritten = true
            try Task.checkCancellation()

            let responseRead = try await AgentHTTPBlockingIO.readMessage(
                from: connection,
                pending: pendingData,
                deadline: deadline
            )
            let response = responseRead.message
            guard response.kind == .response,
                  response.status == 200 else {
                throw challengeError(for: response.status)
            }
            let responseGeneration = try uint64Header(AgentHTTPHeaders.generation, in: response)
            let responsePort = try uint16Header(AgentHTTPHeaders.port, in: response)
            let responseVersion = try requiredHeader(AgentHTTPHeaders.version, in: response)
            let responseID = try requiredHeader(AgentHTTPHeaders.requestID, in: response)
            let responseDigest = try proofHeader(AgentHTTPHeaders.responseDigest, in: response)
            let responseProof = try proofHeader(AgentHTTPHeaders.responseProof, in: response)
            guard responseGeneration == generation,
                  responsePort == endpoint.port,
                  responseVersion == AgentHTTPAuthentication.protocolVersion,
                  responseID == requestIDString,
                  AgentHTTPAuthentication.constantTimeEqual(
                    responseDigest,
                    AgentHTTPAuthentication.digest(response.body)
                  ) else {
                throw AgentHTTPError.authenticationFailed
            }
            let expectedResponseProof = AgentHTTPAuthentication.responseProof(
                key: key,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                generation: generation,
                port: endpoint.port,
                requestID: requestIDString,
                status: response.status ?? 0,
                responseDigest: responseDigest
            )
            guard AgentHTTPAuthentication.constantTimeEqual(responseProof, expectedResponseProof) else {
                throw AgentHTTPError.authenticationFailed
            }
            try requireJSONContentType(in: response)
            return try codec.decodeResponse(
                from: response.body,
                expectedID: requestIDString,
                expectedMethod: request.methodName
            )
        } catch {
            let disposition: AgentTransportFailure.DispatchDisposition = semanticBodyWritten
                ? .outcomeUnknown(requestID: requestID)
                : .notDispatched
            throw Self.failure(error, disposition: disposition)
        }
    }

    private static func requiredHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> String {
        guard let value = message.headers[name.lowercased()], !value.isEmpty else {
            throw AgentHTTPError.authenticationFailed
        }
        return value
    }

    private static func nonceHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> Data {
        let value = try requiredHeader(name, in: message)
        guard let nonce = AgentHTTPAuthentication.decode(value),
              nonce.count == AgentHTTPAuthentication.nonceByteCount else {
            throw AgentHTTPError.authenticationFailed
        }
        return nonce
    }

    private static func proofHeader(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> Data {
        let value = try requiredHeader(name, in: message)
        guard let proof = AgentHTTPAuthentication.decode(value),
              proof.count == 32 else {
            throw AgentHTTPError.authenticationFailed
        }
        return proof
    }

    private static func requireJSONContentType(
        in message: AgentHTTPWire.Message
    ) throws {
        let value = try requiredHeader(AgentHTTPHeaders.contentType, in: message)
        guard AgentHTTPWire.isJSONContentType(value) else {
            throw AgentHTTPError.malformedMessage(
                "The authenticated agent response must use application/json."
            )
        }
    }

    private static func uint64Header(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> UInt64 {
        let value = try requiredHeader(name, in: message)
        guard let number = UInt64(value) else {
            throw AgentHTTPError.authenticationFailed
        }
        return number
    }

    private static func uint16Header(
        _ name: String,
        in message: AgentHTTPWire.Message
    ) throws -> UInt16 {
        let value = try requiredHeader(name, in: message)
        guard let number = UInt16(value) else {
            throw AgentHTTPError.authenticationFailed
        }
        return number
    }

    private static func challengeError(for status: Int?) -> AgentHTTPError {
        if let status { return .unexpectedStatus(status) }
        return .malformedMessage("The agent HTTP response is invalid.")
    }

    private static func failure(
        _ error: Error,
        disposition: AgentTransportFailure.DispatchDisposition
    ) -> AgentTransportFailure {
        let cause: AgentTransportFailure.Cause
        if error is CancellationError || (error as? AgentHTTPError) == .cancelled {
            cause = .cancelled
        } else if (error as? AgentHTTPError) == .deadlineExceeded {
            cause = .deadlineExceeded
        } else if let editorError = error as? EditorError {
            cause = .transport(editorError)
        } else if let httpError = error as? AgentHTTPError {
            cause = .transport(
                EditorError(
                    code: .agentConnectionFailed,
                    message: httpError.localizedDescription
                )
            )
        } else {
            cause = .transport(
                EditorError(
                    code: .agentConnectionFailed,
                    message: error.localizedDescription
                )
            )
        }
        return AgentTransportFailure(disposition: disposition, cause: cause)
    }

}
