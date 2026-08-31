import Darwin
import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import Synchronization
import Testing
@testable import RupaAgentTransport

@Suite(.serialized)
struct AgentTransportBoundaryTests {
    @Test(.timeLimit(.minutes(1)))
    func listenerAppliesOwnerOnlyDirectoryAndSocketPermissions() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let listener = AgentSocketListener(
            handler: ImmediateStatusHandler(),
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer()
        )

        try await listener.start()
        do {
            #expect(try permissionBits(at: fixture.directory) == 0o700)
            #expect(try permissionBits(at: fixture.endpoint.fileURL) == 0o600)
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectingPeerAuthorizerRunsBeforeDecodeAndHandlerDispatch() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let authorizer = RejectingPeerAuthorizer()
        let handler = CountingStatusHandler()
        let listener = AgentSocketListener(
            handler: handler,
            endpoint: fixture.endpoint,
            peerAuthorizer: authorizer
        )

        try await listener.start()
        let descriptor = try connectedDescriptor(to: fixture.endpoint)
        do {
            try await waitUntil { authorizer.authorizationCount == 1 }
            #expect(await handler.requestCount == 0)
            #expect(try await waitsForPeerClosure(descriptor))
            Darwin.close(descriptor)
            await listener.stop()
        } catch {
            Darwin.close(descriptor)
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func listenerRejectsTheThirtyThirdConcurrentConnection() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let listener = AgentSocketListener(
            handler: ImmediateStatusHandler(),
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer()
        )
        var descriptors: [Int32] = []

        try await listener.start()
        do {
            for _ in 1...AgentSocketListener.maximumConcurrentConnectionCount {
                descriptors.append(try connectedDescriptor(to: fixture.endpoint))
            }
            try await waitUntil {
                await listener.activeConnectionCount
                    == AgentSocketListener.maximumConcurrentConnectionCount
            }

            let rejectedDescriptor = try connectedDescriptor(to: fixture.endpoint)
            descriptors.append(rejectedDescriptor)
            #expect(try await waitsForPeerClosure(rejectedDescriptor))
            #expect(
                await listener.activeConnectionCount
                    == AgentSocketListener.maximumConcurrentConnectionCount
            )

            await listener.stop()
            descriptors.forEach { Darwin.close($0) }
        } catch {
            await listener.stop()
            descriptors.forEach { Darwin.close($0) }
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsAFrameAtTheSixteenMiBBoundary() async throws {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw testSocketError("create frame-boundary socket pair")
        }
        defer {
            Darwin.close(descriptors[0])
            Darwin.close(descriptors[1])
        }
        try AgentSocketIO.configure(descriptors[0])
        try AgentSocketIO.configure(descriptors[1])
        let payload = Data(
            repeating: 0xA5,
            count: AgentSocketIO.maximumFrameByteCount
        )
        let readDescriptor = descriptors[1]
        let readTask = Task.detached {
            try AgentSocketIO.readFrame(
                from: readDescriptor,
                deadline: AgentSocketDeadline.request(timeout: .seconds(10))
            )
        }

        try AgentSocketIO.writeFrame(
            payload,
            to: descriptors[0],
            deadline: AgentSocketDeadline.request(timeout: .seconds(10))
        )
        let received = try await readTask.value
        #expect(received.count == AgentSocketIO.maximumFrameByteCount)
        #expect(received.first == 0xA5)
        #expect(received.last == 0xA5)
    }

    @Test(.timeLimit(.minutes(1)))
    func clientRetriesUntilTheInjectedDeadlineBeyondTheFormerTwoSecondCeiling() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let listener = AgentSocketListener(
            handler: ImmediateStatusHandler(),
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer()
        )
        let startTask = Task {
            try await Task.sleep(for: .milliseconds(2_100))
            try await listener.start()
        }
        let clock = ContinuousClock()
        let started = clock.now
        let client = AgentClient(endpoint: fixture.endpoint)

        do {
            let response = try await client.send(
                .status,
                deadline: started.advanced(by: .seconds(4))
            )
            guard case .status(let status) = response else {
                Issue.record("Expected status after delayed listener readiness.")
                await listener.stop()
                return
            }
            #expect(status.running)
            #expect(started.duration(to: clock.now) >= .seconds(2))
            try await startTask.value
            await listener.stop()
        } catch {
            startTask.cancel()
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func absoluteDeadlineIsNotResetAfterDelayedConnection() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let listener = AgentSocketListener(
            handler: DelayedStatusHandler(delay: .milliseconds(200)),
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer()
        )
        let startTask = Task {
            try await Task.sleep(for: .milliseconds(200))
            try await listener.start()
        }
        let clock = ContinuousClock()
        let started = clock.now
        let client = AgentClient(endpoint: fixture.endpoint)

        var failure: AgentTransportFailure?
        do {
            _ = try await client.send(
                .status,
                deadline: started.advanced(by: .milliseconds(300))
            )
        } catch let error as AgentTransportFailure {
            failure = error
        }
        guard let failure else {
            Issue.record("Expected the shared absolute deadline to expire.")
            startTask.cancel()
            await listener.stop()
            return
        }
        guard case .outcomeUnknown = failure.disposition else {
            Issue.record("Expected a dispatched request with an unknown outcome.")
            startTask.cancel()
            await listener.stop()
            return
        }
        #expect(failure.cause == .deadlineExceeded)
        #expect(started.duration(to: clock.now) < .milliseconds(700))
        try await startTask.value
        await listener.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func unavailableEndpointFailsAsNotDispatchedAtTheAbsoluteDeadline() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let client = AgentClient(endpoint: fixture.endpoint)
        let deadline = ContinuousClock().now.advanced(by: .milliseconds(120))

        var failure: AgentTransportFailure?
        do {
            _ = try await client.send(.status, deadline: deadline)
        } catch let error as AgentTransportFailure {
            failure = error
        }
        #expect(failure?.disposition == .notDispatched)
        #expect(failure?.cause == .deadlineExceeded)
    }

    @Test(.timeLimit(.minutes(1)))
    func responseLossAfterRequestFrameReturnsOutcomeUnknownWithRequestID() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let serverTask = try makeResponseDroppingServer(endpoint: fixture.endpoint)
        let client = AgentClient(endpoint: fixture.endpoint)

        var failure: AgentTransportFailure?
        do {
            _ = try await client.send(
                .status,
                deadline: ContinuousClock().now.advanced(by: .seconds(2))
            )
        } catch let error as AgentTransportFailure {
            failure = error
        }
        try await serverTask.value
        guard case .outcomeUnknown(let requestID) = failure?.disposition else {
            Issue.record("Expected post-dispatch response loss.")
            return
        }
        #expect(requestID.uuidString.count == 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAfterDispatchPreservesOutcomeUnknown() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let handler = CancellationBlockingHandler()
        let listener = AgentSocketListener(
            handler: handler,
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer()
        )
        let client = AgentClient(endpoint: fixture.endpoint)

        try await listener.start()
        let sendTask = Task {
            try await client.send(.status)
        }
        do {
            try await waitUntil { await handler.didStart }
            sendTask.cancel()
            var failure: AgentTransportFailure?
            do {
                _ = try await sendTask.value
            } catch let error as AgentTransportFailure {
                failure = error
            }
            guard case .outcomeUnknown = failure?.disposition else {
                Issue.record("Expected cancellation after dispatch to remain unknown.")
                await listener.stop()
                return
            }
            #expect(failure?.cause == .cancelled)
            await listener.stop()
        } catch {
            sendTask.cancel()
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stopReturnsWithinBudgetWhenHandlerIgnoresCancellation() async throws {
        let fixture = try makeEndpointFixture()
        defer { removeFixture(fixture.directory) }
        let handler = TemporarilyUncooperativeHandler()
        let listener = AgentSocketListener(
            handler: handler,
            endpoint: fixture.endpoint,
            peerAuthorizer: sameUserAuthorizer(),
            shutdownTimeout: .milliseconds(100)
        )
        let client = AgentClient(endpoint: fixture.endpoint)

        try await listener.start()
        let sendTask = Task { try await client.send(.status) }
        try await waitUntil { handler.didStart }
        let clock = ContinuousClock()
        let started = clock.now
        await listener.stop()
        let elapsed = started.duration(to: clock.now)
        #expect(elapsed < .milliseconds(300))
        #expect(!(await listener.isRunning))
        #expect(await listener.activeConnectionCount == 0)
        sendTask.cancel()
    }
}

private struct EndpointFixture {
    let directory: URL
    let endpoint: UnixSocketEndpoint
}

private struct ImmediateStatusHandler: AgentRequestHandling {
    func handle(_ request: AgentRequest) async -> AgentResponse {
        .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private actor CountingStatusHandler: AgentRequestHandling {
    private(set) var requestCount = 0

    func handle(_ request: AgentRequest) async -> AgentResponse {
        requestCount += 1
        return .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private struct DelayedStatusHandler: AgentRequestHandling {
    let delay: Duration

    func handle(_ request: AgentRequest) async -> AgentResponse {
        do {
            try await Task.sleep(for: delay)
        } catch {
            return .failure(
                EditorError(
                    code: .commandFailed,
                    message: "Delayed status handler was cancelled."
                )
            )
        }
        return .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private actor CancellationBlockingHandler: AgentRequestHandling {
    private(set) var didStart = false

    func handle(_ request: AgentRequest) async -> AgentResponse {
        didStart = true
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            return .status(AgentStatus(running: true, sessionCount: 0))
        }
        return .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private final class TemporarilyUncooperativeHandler: AgentRequestHandling {
    private let state = Mutex(false)

    var didStart: Bool {
        state.withLock { $0 }
    }

    func handle(_ request: AgentRequest) async -> AgentResponse {
        state.withLock { $0 = true }
        usleep(500_000)
        return .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private final class RejectingPeerAuthorizer: AgentPeerAuthorizing {
    private let state = Mutex(0)

    var authorizationCount: Int {
        state.withLock { $0 }
    }

    func authorize(_ peer: UnixSocketPeerIdentity) throws {
        state.withLock { $0 += 1 }
        throw AgentPeerAuthorizationError.unauthorizedUser(
            actual: peer.userID,
            expected: peer.userID &+ 1
        )
    }
}

private func sameUserAuthorizer() -> SameUserAgentPeerAuthorizer {
    SameUserAgentPeerAuthorizer(expectedUserID: getuid())
}

private func makeEndpointFixture() throws -> EndpointFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return EndpointFixture(
        directory: directory,
        endpoint: try UnixSocketEndpoint(
            fileURL: directory.appendingPathComponent("rupa.sock")
        )
    )
}

private func removeFixture(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove transport fixture: \(error)")
    }
}

private func permissionBits(at url: URL) throws -> mode_t {
    var state = stat()
    guard lstat(url.path, &state) == 0 else {
        throw testSocketError("inspect permissions")
    }
    return state.st_mode & mode_t(0o777)
}

private func connectedDescriptor(to endpoint: UnixSocketEndpoint) throws -> Int32 {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw testSocketError("create client socket")
    }
    do {
        try AgentSocketIO.configure(descriptor)
        let deadline = try AgentSocketDeadline.request(timeout: .seconds(2))
        try AgentSocketAddress.withUnixAddress(path: endpoint.path) { address, length in
            let result = Darwin.connect(descriptor, address, length)
            if result == 0 || errno == EISCONN {
                return
            }
            guard errno == EINPROGRESS || errno == EALREADY || errno == EAGAIN else {
                throw testSocketError("connect client socket")
            }
            try AgentSocketIO.wait(
                for: Int16(POLLOUT),
                on: descriptor,
                deadline: deadline
            )
            var socketError: Int32 = 0
            var socketErrorLength = socklen_t(MemoryLayout.size(ofValue: socketError))
            guard getsockopt(
                descriptor,
                SOL_SOCKET,
                SO_ERROR,
                &socketError,
                &socketErrorLength
            ) == 0,
            socketError == 0 else {
                errno = socketError
                throw testSocketError("complete client socket connection")
            }
        }
        return descriptor
    } catch {
        Darwin.close(descriptor)
        throw error
    }
}

private func waitsForPeerClosure(_ descriptor: Int32) async throws -> Bool {
    for _ in 0..<200 {
        var byte: UInt8 = 0
        let count = Darwin.recv(descriptor, &byte, 1, MSG_DONTWAIT)
        if count == 0 || (count < 0 && (errno == ECONNRESET || errno == EPIPE)) {
            return true
        }
        if count < 0 && errno != EAGAIN {
            throw testSocketError("observe peer closure")
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    return false
}

private func waitUntil(
    _ condition: () async -> Bool
) async throws {
    for _ in 0..<400 {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw EditorError(
        code: .agentConnectionFailed,
        message: "Timed out waiting for the transport test condition."
    )
}

private func makeResponseDroppingServer(
    endpoint: UnixSocketEndpoint
) throws -> Task<Void, any Error> {
    let listenerDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard listenerDescriptor >= 0 else {
        throw testSocketError("create response-dropping listener")
    }
    do {
        try AgentSocketAddress.withUnixAddress(path: endpoint.path) { address, length in
            guard Darwin.bind(listenerDescriptor, address, length) == 0,
                  Darwin.listen(listenerDescriptor, 1) == 0 else {
                throw testSocketError("bind response-dropping listener")
            }
        }
    } catch {
        Darwin.close(listenerDescriptor)
        throw error
    }

    return Task.detached {
        defer {
            Darwin.close(listenerDescriptor)
        }
        let connection = Darwin.accept(listenerDescriptor, nil, nil)
        guard connection >= 0 else {
            throw testSocketError("accept response-dropping connection")
        }
        defer {
            Darwin.close(connection)
        }
        try AgentSocketIO.configure(connection)
        let requestData = try AgentSocketIO.readFrame(
            from: connection,
            deadline: AgentSocketDeadline.request(timeout: .seconds(2))
        )
        _ = try AgentMessageCodec().decodeRequestEnvelope(from: requestData)
    }
}

private func testSocketError(_ operation: String) -> EditorError {
    EditorError(
        code: .agentConnectionFailed,
        message: "Failed to \(operation). errno=\(errno)"
    )
}
