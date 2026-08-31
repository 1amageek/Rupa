import Darwin
import Foundation
import Testing
import RupaAgentProtocol
import RupaCoreTypes
@testable import RupaAgentTransport

@Suite(.serialized)
struct AgentHTTPTransportTests {
    @Test(.timeLimit(.minutes(1)))
    func authenticatedRoundTripUsesOneConnection() async throws {
        let key = Data(repeating: 0x2A, count: AgentHTTPAuthentication.keyByteCount)
        let handler = StatusHandler()
        let listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: 7,
            requestTimeout: .seconds(5),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        do {
            #expect(endpoint.host == AgentHTTPEndpoint.loopbackHost)
            #expect(endpoint.port != 0)
            #expect(await listener.isRunning)
            let client = AgentHTTPClient(
                endpoint: endpoint,
                key: key,
                generation: 7,
                requestTimeout: .seconds(5)
            )
            let response = try await client.send(.status)
            #expect(response == .status(AgentStatus(running: true, sessionCount: 1)))
            #expect(await handler.requestCount == 1)
            #expect(await listener.activeConnectionCount == 0)
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func wrongGenerationFailsBeforeSemanticDispatch() async throws {
        let key = Data(repeating: 0x19, count: AgentHTTPAuthentication.keyByteCount)
        let handler = StatusHandler()
        let listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: 9,
            requestTimeout: .seconds(5),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        let client = AgentHTTPClient(
            endpoint: endpoint,
            key: key,
            generation: 10,
            requestTimeout: .seconds(5)
        )
        do {
            _ = try await client.send(.status)
            Issue.record("A stale launch generation was accepted.")
        } catch let failure as AgentTransportFailure {
            #expect(failure.disposition == .notDispatched)
            #expect(await handler.requestCount == 0)
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func forgedChallengeProofDoesNotReceiveRpcBody() async throws {
        let key = Data(repeating: 0x31, count: AgentHTTPAuthentication.keyByteCount)
        let handler = StatusHandler()
        let listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: 11,
            requestTimeout: .seconds(5),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()

        let forgedKey = Data(repeating: 0x32, count: key.count)
        let client = AgentHTTPClient(
            endpoint: endpoint,
            key: forgedKey,
            generation: 11,
            requestTimeout: .seconds(5)
        )
        do {
            _ = try await client.send(.status)
            Issue.record("A forged authentication key was accepted.")
        } catch let failure as AgentTransportFailure {
            #expect(failure.disposition == .notDispatched)
            #expect(await handler.requestCount == 0)
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proofComparisonRejectsDifferentLengths() {
        let proof = Data(repeating: 0xA5, count: 32)
        #expect(!AgentHTTPAuthentication.constantTimeEqual(proof, Data(repeating: 0xA5, count: 31)))
        #expect(AgentHTTPAuthentication.constantTimeEqual(proof, proof))
    }

    @Test(.timeLimit(.minutes(1)))
    func framingRequiresContentLengthAndHonorsBodyLimit() throws {
        let request = try AgentHTTPWire.makeRequest(
            method: "POST",
            path: "/v1/challenge",
            headers: ["X-Test": "ok"],
            body: Data()
        )
        #expect(String(decoding: request, as: UTF8.self).contains("Content-Length: 0"))
        #expect(throws: AgentHTTPError.bodyTooLarge(AgentHTTPWire.maximumBodyByteCount + 1)) {
            _ = try AgentHTTPWire.makeRequest(
                method: "POST",
                path: "/v1/rpc",
                headers: [:],
                body: Data(repeating: 0, count: AgentHTTPWire.maximumBodyByteCount + 1)
            )
        }
        let maximumBody = Data(repeating: 0x5A, count: AgentHTTPWire.maximumBodyByteCount)
        let maximumRequest = try AgentHTTPWire.makeRequest(
            method: "POST",
            path: "/v1/rpc",
            headers: [:],
            body: maximumBody
        )
        #expect(maximumRequest.count > maximumBody.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func endpointAndContentTypeBoundariesAreExact() throws {
        #expect(throws: AgentHTTPError.invalidEndpoint) {
            _ = try AgentHTTPEndpoint(host: "localhost", port: 80)
        }
        #expect(throws: AgentHTTPError.invalidEndpoint) {
            _ = try AgentHTTPEndpoint(port: 0)
        }
        #expect(AgentHTTPWire.isJSONContentType("application/json"))
        #expect(AgentHTTPWire.isJSONContentType("Application/JSON; charset=utf-8"))
        #expect(!AgentHTTPWire.isJSONContentType("text/plain"))
    }

    @Test(.timeLimit(.minutes(1)))
    func staleForgedServerSeesChallengeOnlyAndCannotTriggerReconnect() async throws {
        let key = Data(repeating: 0x41, count: AgentHTTPAuthentication.keyByteCount)
        let forgedKey = Data(repeating: 0x42, count: AgentHTTPAuthentication.keyByteCount)
        let generation: UInt64 = 21
        let server = try RawAgentHTTPTestFixture.start { listener, connection, endpoint, deadline in
            var pending = Data()
            let challenge = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            _ = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: challenge,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: forgedKey,
                deadline: deadline
            )
            let rpc = try RawAgentHTTPTestFixture.readOptionalNextMessage(
                from: connection,
                pending: &pending
            )
            let reconnected = try RawAgentHTTPTestFixture.acceptsAdditionalConnection(
                on: listener
            )
            return FakeServerObservation(
                challenge: challenge,
                rpc: rpc,
                acceptedAdditionalConnection: reconnected
            )
        }
        let client = AgentHTTPClient(
            endpoint: server.endpoint,
            key: key,
            generation: generation,
            requestTimeout: .seconds(2)
        )
        await expectFailure(client: client, disposition: .notDispatched)
        let observation = try await server.result.value
        #expect(observation.challenge.body.isEmpty)
        #expect(observation.rpc == nil)
        #expect(!observation.acceptedAdditionalConnection)
        let encodedKey = AgentHTTPAuthentication.encode(key)
        #expect(!observation.challenge.headers.values.contains(encodedKey))
    }

    @Test(.timeLimit(.minutes(1)))
    func validProofThenAbortedConnectionDoesNotDispatchOrRetry() async throws {
        let key = Data(repeating: 0x51, count: AgentHTTPAuthentication.keyByteCount)
        let generation: UInt64 = 22
        let server = try RawAgentHTTPTestFixture.startAbortingConnectionAfterOperation {
            connection, endpoint, deadline in
            var pending = Data()
            let challenge = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            _ = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: challenge,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                connection: "keep-alive",
                deadline: deadline
            )
            return ChallengeBeforeAbortObservation(
                challenge: challenge,
                bytesReceivedBeforeAbort: pending
            )
        }
        let client = AgentHTTPClient(
            endpoint: server.endpoint,
            key: key,
            generation: generation,
            requestTimeout: .seconds(2)
        )
        await expectFailure(client: client, disposition: .notDispatched)
        let observation = try await server.result.value
        #expect(observation.operationResult.challenge.body.isEmpty)
        #expect(observation.operationResult.bytesReceivedBeforeAbort.isEmpty)
        #expect(!observation.acceptedAdditionalConnection)
    }

    @Test(.timeLimit(.minutes(1)))
    func completeRPCThenResponseLossIsOutcomeUnknownWithoutReplay() async throws {
        let key = Data(repeating: 0x61, count: AgentHTTPAuthentication.keyByteCount)
        let generation: UInt64 = 23
        let server = try RawAgentHTTPTestFixture.start { listener, connection, endpoint, deadline in
            var pending = Data()
            let challengeMessage = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            let challenge = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: challengeMessage,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                deadline: deadline
            )
            let rpc = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            return FakeServerObservation(
                challenge: challenge.message,
                rpc: rpc,
                acceptedAdditionalConnection: try RawAgentHTTPTestFixture.acceptsAdditionalConnection(
                    on: listener
                )
            )
        }
        let client = AgentHTTPClient(
            endpoint: server.endpoint,
            key: key,
            generation: generation,
            requestTimeout: .seconds(2)
        )
        let failure = await capturedFailure(client: client)
        guard case .outcomeUnknown = failure?.disposition else {
            Issue.record("A complete semantic request was not classified as outcome unknown.")
            _ = try await server.result.value
            return
        }
        let observation = try await server.result.value
        #expect(observation.rpc?.path == "/v1/rpc")
        #expect(!observation.acceptedAdditionalConnection)
    }

    @Test(.timeLimit(.minutes(1)))
    func forgedAuthenticatedResponseIsRejectedWithoutReplay() async throws {
        let key = Data(repeating: 0x71, count: AgentHTTPAuthentication.keyByteCount)
        let forgedKey = Data(repeating: 0x72, count: AgentHTTPAuthentication.keyByteCount)
        let generation: UInt64 = 24
        let server = try RawAgentHTTPTestFixture.start { listener, connection, endpoint, deadline in
            var pending = Data()
            let challengeMessage = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            let challenge = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: challengeMessage,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                deadline: deadline
            )
            let rpc = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            try RawAgentHTTPTestFixture.sendSemanticResponse(
                .status(AgentStatus(running: true, sessionCount: 1)),
                for: challenge,
                request: rpc,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: forgedKey,
                deadline: deadline
            )
            return FakeServerObservation(
                challenge: challenge.message,
                rpc: rpc,
                acceptedAdditionalConnection: try RawAgentHTTPTestFixture.acceptsAdditionalConnection(
                    on: listener
                )
            )
        }
        let client = AgentHTTPClient(
            endpoint: server.endpoint,
            key: key,
            generation: generation,
            requestTimeout: .seconds(2)
        )
        let failure = await capturedFailure(client: client)
        guard case .outcomeUnknown = failure?.disposition else {
            Issue.record("A forged post-dispatch response was not classified as outcome unknown.")
            _ = try await server.result.value
            return
        }
        let observation = try await server.result.value
        #expect(observation.rpc != nil)
        #expect(!observation.acceptedAdditionalConnection)
    }

    @Test(.timeLimit(.minutes(1)))
    func clientRequiresJSONOnAuthenticatedChallengeAndResponse() async throws {
        let key = Data(repeating: 0x73, count: AgentHTTPAuthentication.keyByteCount)
        let generation: UInt64 = 25
        let challengeServer = try RawAgentHTTPTestFixture.start { _, connection, endpoint, deadline in
            var pending = Data()
            let message = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            _ = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: message,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                contentType: "text/plain",
                deadline: deadline
            )
            return try RawAgentHTTPTestFixture.readOptionalNextMessage(
                from: connection,
                pending: &pending
            )
        }
        await expectFailure(
            client: AgentHTTPClient(
                endpoint: challengeServer.endpoint,
                key: key,
                generation: generation,
                requestTimeout: .seconds(2)
            ),
            disposition: .notDispatched
        )
        #expect(try await challengeServer.result.value == nil)

        let responseServer = try RawAgentHTTPTestFixture.start { _, connection, endpoint, deadline in
            var pending = Data()
            let challengeMessage = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            let challenge = try RawAgentHTTPTestFixture.sendChallengeResponse(
                for: challengeMessage,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                deadline: deadline
            )
            let rpc = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            try RawAgentHTTPTestFixture.sendSemanticResponse(
                .status(AgentStatus(running: true, sessionCount: 1)),
                for: challenge,
                request: rpc,
                to: connection,
                endpoint: endpoint,
                generation: generation,
                proofKey: key,
                contentType: "text/plain",
                deadline: deadline
            )
            return rpc
        }
        let responseFailure = await capturedFailure(
            client: AgentHTTPClient(
                endpoint: responseServer.endpoint,
                key: key,
                generation: generation,
                requestTimeout: .seconds(2)
            )
        )
        guard case .outcomeUnknown = responseFailure?.disposition else {
            Issue.record("A non-JSON semantic response was not rejected after dispatch.")
            _ = try await responseServer.result.value
            return
        }
        #expect(try await responseServer.result.value.path == "/v1/rpc")
    }

    @Test(.timeLimit(.minutes(1)))
    func wireRejectsAmbiguousAndOversizedFraming() async throws {
        await expectRawFailure(
            Data("POST / HTTP/1.1\r\n\r\n".utf8),
            matching: { $0 == .missingContentLength }
        )
        await expectRawFailure(
            Data("POST / HTTP/1.1\r\nContent-Length: 0\r\ncontent-length: 0\r\n\r\n".utf8),
            matching: { if case .malformedMessage = $0 { true } else { false } }
        )
        await expectRawFailure(
            Data("POST / HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n".utf8),
            matching: { if case .malformedMessage = $0 { true } else { false } }
        )

        let exact = RawAgentHTTPTestFixture.exactSizeHeaderRequest(
            byteCount: AgentHTTPWire.maximumHeaderByteCount
        )
        let exactMessage = try await RawAgentHTTPTestFixture.parseRawMessage(exact)
        #expect(exactMessage.body.isEmpty)
        await expectRawFailure(
            RawAgentHTTPTestFixture.exactSizeHeaderRequest(
                byteCount: AgentHTTPWire.maximumHeaderByteCount + 1
            ),
            matching: { if case .malformedMessage = $0 { true } else { false } }
        )

        let oversizedLength = Data(
            "POST / HTTP/1.1\r\nContent-Length: \(AgentHTTPWire.maximumBodyByteCount + 1)\r\n\r\n".utf8
        )
        await expectRawFailure(
            oversizedLength,
            matching: { $0 == .bodyTooLarge(AgentHTTPWire.maximumBodyByteCount + 1) }
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func challengeIsFreshSingleUseAndExpires() async throws {
        let first = try AgentHTTPAuthentication.nonce()
        let second = try AgentHTTPAuthentication.nonce()
        #expect(first.count == AgentHTTPAuthentication.nonceByteCount)
        #expect(second.count == AgentHTTPAuthentication.nonceByteCount)
        #expect(first != second)

        let key = Data(repeating: 0x81, count: AgentHTTPAuthentication.keyByteCount)
        let handler = StatusHandler()
        let listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: 31,
            requestTimeout: .seconds(2),
            challengeTimeout: .milliseconds(40),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        do {
            let firstServerNonce = try rawChallenge(
                endpoint: endpoint,
                requestID: UUID().uuidString,
                clientNonce: first,
                repeatChallenge: false,
                expectSecondStatus: 401
            )
            let secondServerNonce = try rawChallenge(
                endpoint: endpoint,
                requestID: UUID().uuidString,
                clientNonce: second,
                repeatChallenge: true,
                expectSecondStatus: 404
            )
            #expect(firstServerNonce != secondServerNonce)
            #expect(await handler.requestCount == 0)
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func listenerEnforcesThirtyTwoConnectionAdmissionLimit() async throws {
        let listener = AgentHTTPListener(
            handler: StatusHandler(),
            key: Data(repeating: 0x91, count: AgentHTTPAuthentication.keyByteCount),
            generation: 41,
            requestTimeout: .seconds(30),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        var descriptors: [Int32] = []
        do {
            for index in 0..<AgentHTTPListener.maximumConcurrentConnectionCount {
                let deadline = try AgentHTTPDeadline.request(timeout: .seconds(2))
                descriptors.append(
                    try AgentHTTPWire.connect(to: endpoint, deadline: deadline)
                )
                #expect(await eventually {
                    await listener.activeConnectionCount == index + 1
                })
            }
            let deadline = try AgentHTTPDeadline.request(timeout: .seconds(2))
            let rejected = try AgentHTTPWire.connect(to: endpoint, deadline: deadline)
            descriptors.append(rejected)
            #expect(await eventually {
                await listener.activeConnectionCount == AgentHTTPListener.maximumConcurrentConnectionCount
            })
            try AgentHTTPWire.wait(for: Int16(POLLIN), on: rejected, deadline: deadline)
            var byte: UInt8 = 0
            let count = Darwin.read(rejected, &byte, 1)
            #expect(count == 0)
            for descriptor in descriptors {
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
            }
            descriptors.removeAll()
            await listener.stop()
            #expect(await listener.activeConnectionCount == 0)
        } catch {
            for descriptor in descriptors {
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
            }
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func semanticDeadlineCancelsCooperativeHandlerAndRejectsLateResponse() async throws {
        let handler = CooperativeSuspendingHandler()
        let listener = AgentHTTPListener(
            handler: handler,
            key: Data(repeating: 0xA1, count: AgentHTTPAuthentication.keyByteCount),
            generation: 51,
            requestTimeout: .milliseconds(120),
            challengeTimeout: .seconds(1),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        let client = AgentHTTPClient(
            endpoint: endpoint,
            key: Data(repeating: 0xA1, count: AgentHTTPAuthentication.keyByteCount),
            generation: 51,
            requestTimeout: .seconds(2)
        )
        let failure = await capturedFailure(client: client)
        guard case .outcomeUnknown = failure?.disposition else {
            Issue.record("A semantic deadline after dispatch was not outcome unknown.")
            await listener.stop()
            return
        }
        #expect(await eventually { await handler.cancellationCount == 1 })
        #expect(await eventually { await listener.activeConnectionCount == 0 })
        await listener.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopCancelsAndDrainsCooperativeAcceptedWork() async throws {
        let handler = CooperativeSuspendingHandler()
        let key = Data(repeating: 0xB1, count: AgentHTTPAuthentication.keyByteCount)
        let listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: 61,
            requestTimeout: .seconds(5),
            shutdownTimeout: .seconds(1)
        )
        let endpoint = try await listener.start()
        let clientTask = Task {
            try await AgentHTTPClient(
                endpoint: endpoint,
                key: key,
                generation: 61,
                requestTimeout: .seconds(5)
            ).send(.status)
        }
        #expect(await eventually { await handler.startedCount == 1 })
        await listener.stop()
        #expect(await eventually { await handler.cancellationCount == 1 })
        #expect(await listener.activeConnectionCount == 0)
        do {
            _ = try await clientTask.value
            Issue.record("A stopped transport published a late semantic response.")
        } catch let failure as AgentTransportFailure {
            guard case .outcomeUnknown = failure.disposition else {
                Issue.record("Stopping after semantic dispatch was not outcome unknown.")
                return
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clientCancellationBeforeChallengeProofIsNotDispatched() async throws {
        let key = Data(repeating: 0xC1, count: AgentHTTPAuthentication.keyByteCount)
        let server = try RawAgentHTTPTestFixture.start { _, connection, _, deadline in
            var pending = Data()
            let challenge = try RawAgentHTTPTestFixture.readMessage(
                from: connection,
                deadline: deadline,
                pending: &pending
            )
            _ = try RawAgentHTTPTestFixture.readOptionalNextMessage(
                from: connection,
                timeout: .seconds(1),
                pending: &pending
            )
            return challenge
        }
        let clientTask = Task {
            try await AgentHTTPClient(
                endpoint: server.endpoint,
                key: key,
                generation: 71,
                requestTimeout: .seconds(2)
            ).send(.status)
        }
        try await Task.sleep(for: .milliseconds(50))
        clientTask.cancel()
        do {
            _ = try await clientTask.value
            Issue.record("A cancelled pre-dispatch request succeeded.")
        } catch let failure as AgentTransportFailure {
            #expect(failure.disposition == .notDispatched)
            #expect(failure.cause == .cancelled)
        }
        #expect(try await server.result.value.body.isEmpty)
    }
}

private struct FakeServerObservation: Sendable {
    let challenge: AgentHTTPWire.Message
    let rpc: AgentHTTPWire.Message?
    let acceptedAdditionalConnection: Bool
}

private struct ChallengeBeforeAbortObservation: Sendable {
    let challenge: AgentHTTPWire.Message
    let bytesReceivedBeforeAbort: Data
}

private func capturedFailure(client: AgentHTTPClient) async -> AgentTransportFailure? {
    do {
        _ = try await client.send(.status)
        Issue.record("The transport request unexpectedly succeeded.")
        return nil
    } catch let failure as AgentTransportFailure {
        return failure
    } catch {
        Issue.record("The transport returned an unexpected error type: \(error)")
        return nil
    }
}

private func expectFailure(
    client: AgentHTTPClient,
    disposition: AgentTransportFailure.DispatchDisposition
) async {
    let failure = await capturedFailure(client: client)
    #expect(failure?.disposition == disposition)
}

private func expectRawFailure(
    _ raw: Data,
    matching predicate: (AgentHTTPError) -> Bool
) async {
    do {
        _ = try await RawAgentHTTPTestFixture.parseRawMessage(raw)
        Issue.record("Malformed HTTP framing was accepted.")
    } catch let error as AgentHTTPError {
        #expect(predicate(error))
    } catch {
        Issue.record("Raw framing returned an unexpected error type: \(error)")
    }
}

private func rawChallenge(
    endpoint: AgentHTTPEndpoint,
    requestID: String,
    clientNonce: Data,
    repeatChallenge: Bool,
    expectSecondStatus: Int
) throws -> Data {
    let deadline = try AgentHTTPDeadline.request(timeout: .seconds(2))
    let descriptor = try AgentHTTPWire.connect(to: endpoint, deadline: deadline)
    defer {
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }
    let challenge = try AgentHTTPWire.makeRequest(
        method: "POST",
        path: "/v1/challenge",
        headers: [
            AgentHTTPHeaders.version: AgentHTTPAuthentication.protocolVersion,
            AgentHTTPHeaders.requestID: requestID,
            AgentHTTPHeaders.clientNonce: AgentHTTPAuthentication.encode(clientNonce),
            AgentHTTPHeaders.contentType: "application/json",
            AgentHTTPHeaders.connection: "keep-alive",
        ],
        body: Data()
    )
    try AgentHTTPWire.writeAll(challenge, to: descriptor, deadline: deadline)
    var pending = Data()
    let response = try AgentHTTPWire.readMessage(
        from: descriptor,
        pending: &pending,
        deadline: deadline
    )
    guard response.status == 200,
          let nonceText = response.headers[AgentHTTPHeaders.serverNonce.lowercased()],
          let serverNonce = AgentHTTPAuthentication.decode(nonceText) else {
        throw AgentHTTPError.malformedMessage("The real listener did not return a challenge nonce.")
    }
    if repeatChallenge {
        try AgentHTTPWire.writeAll(challenge, to: descriptor, deadline: deadline)
    }
    let second = try AgentHTTPWire.readMessage(
        from: descriptor,
        pending: &pending,
        deadline: deadline
    )
    #expect(second.status == expectSecondStatus)
    return serverNonce
}

private func eventually(
    timeout: Duration = .seconds(2),
    predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await predicate() { return true }
        do {
            try await Task.sleep(for: .milliseconds(5))
        } catch {
            return false
        }
    }
    return await predicate()
}

private actor StatusHandler: AgentRequestHandling {
    private(set) var requestCount = 0

    func handle(_ request: AgentRequest) async -> AgentResponse {
        requestCount += 1
        return .status(AgentStatus(running: true, sessionCount: 1))
    }
}

private actor CooperativeSuspendingHandler: AgentRequestHandling {
    private(set) var startedCount = 0
    private(set) var cancellationCount = 0

    func handle(_ request: AgentRequest) async -> AgentResponse {
        startedCount += 1
        do {
            try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
            cancellationCount += 1
        } catch {
            Issue.record("The cooperative handler received an unexpected error: \(error)")
        }
        return .status(AgentStatus(running: true, sessionCount: 1))
    }
}
