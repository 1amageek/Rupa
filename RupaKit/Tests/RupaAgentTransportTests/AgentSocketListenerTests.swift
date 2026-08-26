import Darwin
import Foundation
import Testing
import RupaAgentProtocol
import RupaAgentIntegrationTestFixtures
import RupaCore
@testable import RupaAgent
@testable import RupaAgentTransport

@Suite(.serialized)
struct AgentSocketListenerTests {
    @MainActor
    @Test(.timeLimit(.minutes(1))) func routesCommandThroughMainActorBridge() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let socketPath = AgentSocketPath(socketURL.path)
        let bridge = MainActorAgentBridge()
        let sessionID = UUID()
        let session = EditorSession()
        bridge.register(session: session, id: sessionID)
        let listener = AgentSocketListener(
            handler: bridge,
            socketPath: socketPath
        )

        try await listener.start()
        do {
            let request = AgentRequest.execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Socket Main Actor"),
                expectedGeneration: DocumentGeneration(0)
            )
            let response = try await sendThroughClient(request, socketPath: socketPath)

            guard case .command(let result) = response else {
                #expect(Bool(false))
                await listener.stop()
                return
            }
            #expect(result.didMutate)
            #expect(result.generation == DocumentGeneration(1))
            #expect(session.document.cadDocument.metadata.name == "Socket Main Actor")
            await listener.stop()
        } catch {
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1))) func roundTripsStatusThroughClient() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let server = AgentCommandController()
        server.register(session: EditorSession(document: .empty(named: "Open")))

        try await withRunningListener(controller: server, socketURL: socketURL) { listener, client in
            let response = try await client.send(.status)

            guard case .status(let status) = response else {
                #expect(Bool(false))
                return
            }
            #expect(await listener.isRunning)
            #expect(status.running)
            #expect(status.socketPath == socketURL.path)
            #expect(status.sessionCount == 1)
        }
    }

    @Test(.timeLimit(.minutes(1))) func routesCommandThroughClient() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let sessionID = UUID()
        let server = AgentCommandController()
        server.register(session: EditorSession(), id: sessionID)

        try await withRunningListener(controller: server, socketURL: socketURL) { _, client in
            let response = try await client.send(
                .execute(
                    sessionID: sessionID,
                    command: .renameDocument(name: "Socket Live"),
                    expectedGeneration: DocumentGeneration(0)
                )
            )

            guard case .command(let result) = response else {
                #expect(Bool(false))
                return
            }
            #expect(result.didMutate)
            #expect(result.generation == DocumentGeneration(1))

            let sessionsResponse = try await client.send(.sessions)
            guard case .sessions(let sessions) = sessionsResponse else {
                #expect(Bool(false))
                return
            }
            #expect(sessions.first?.displayName == "Socket Live")
        }
    }

    @Test(.timeLimit(.minutes(1))) func routesDocumentLifecycleAndHistoryThroughClient() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let documentURL = temporaryDirectory.appendingPathComponent("Socket Lifecycle.rupa")

        try await withRunningListener(
            controller: AgentCommandController(),
            socketURL: socketURL
        ) { _, client in
            let createResult = try requireSessionOperation(
                await client.send(
                    .createDocument(name: "Socket Lifecycle", outputPath: documentURL.path)
                ),
                operation: .create
            )
            let sessionID = createResult.session.id

            guard case .command = try await client.send(
                .execute(
                    sessionID: sessionID,
                    command: .renameDocument(name: "Socket Renamed"),
                    expectedGeneration: DocumentGeneration(0)
                )
            ) else {
                Issue.record("Expected socket rename command result.")
                return
            }

            let undoResult = try requireSessionOperation(
                await client.send(
                    .undo(
                        sessionID: sessionID,
                        expectedGeneration: DocumentGeneration(1)
                    )
                ),
                operation: .undo
            )
            #expect(undoResult.session.displayName == "Socket Lifecycle")

            let redoResult = try requireSessionOperation(
                await client.send(
                    .redo(
                        sessionID: sessionID,
                        expectedGeneration: DocumentGeneration(2)
                    )
                ),
                operation: .redo
            )
            #expect(redoResult.session.displayName == "Socket Renamed")

            let resetResult = try requireSessionOperation(
                await client.send(
                    .resetDocument(
                        sessionID: sessionID,
                        name: "Socket Reset",
                        expectedGeneration: DocumentGeneration(3)
                    )
                ),
                operation: .reset
            )
            #expect(resetResult.session.displayName == "Socket Reset")

            guard case .save = try await client.send(
                .save(
                    sessionID: sessionID,
                    expectedGeneration: DocumentGeneration(4)
                )
            ) else {
                Issue.record("Expected socket save result.")
                return
            }

            _ = try requireSessionOperation(
                await client.send(
                    .closeDocument(
                        sessionID: sessionID,
                        expectedGeneration: DocumentGeneration(4),
                        discardUnsavedChanges: false
                    )
                ),
                operation: .close
            )
            let openResult = try requireSessionOperation(
                await client.send(.openDocument(path: documentURL.path)),
                operation: .open
            )
            #expect(openResult.session.displayName == "Socket Reset")
            #expect(openResult.session.id != sessionID)
        }
    }

    @Test(.timeLimit(.minutes(1))) func stopRemovesSocketAndRejectsClient() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let listener = AgentSocketListener(
            handler: AgentCommandHandler(),
            socketPath: AgentSocketPath(socketURL.path)
        )
        let client = AgentClient(socketPath: AgentSocketPath(socketURL.path))

        try await listener.start()
        #expect(FileManager.default.fileExists(atPath: socketURL.path))
        await listener.stop()
        #expect(!FileManager.default.fileExists(atPath: socketURL.path))

        var caught: EditorError?
        do {
            _ = try await client.send(.status)
        } catch let error as EditorError {
            caught = error
        }
        #expect(caught?.code == .agentConnectionFailed)
    }

    @Test(.timeLimit(.minutes(1))) func replacesStaleSocketFile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        try Data("stale".utf8).write(to: socketURL)

        try await withRunningListener(
            controller: AgentCommandController(),
            socketURL: socketURL
        ) { _, client in
            let response = try await client.send(.status)
            guard case .status(let status) = response else {
                #expect(Bool(false))
                return
            }
            #expect(status.socketPath == socketURL.path)
        }
    }

    @Test(.timeLimit(.minutes(1))) func survivesMalformedRequest() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")

        try await withRunningListener(
            controller: AgentCommandController(),
            socketURL: socketURL
        ) { _, client in
            let malformedResponseData = try sendRaw(
                Data("not-json".utf8),
                to: socketURL
            )
            let malformedResponse = try AgentMessageCodec()
                .decodeResponse(from: malformedResponseData)

            guard case .failure(let error) = malformedResponse else {
                #expect(Bool(false))
                return
            }
            #expect(error.code == .commandInvalid)

            let response = try await client.send(.status)
            guard case .status(let status) = response else {
                #expect(Bool(false))
                return
            }
            #expect(status.running)
        }
    }

    @Test(.timeLimit(.minutes(1))) func halfOpenClientDoesNotBlockAnotherRequest() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let listener = AgentSocketListener(
            handler: AgentCommandHandler(),
            socketPath: AgentSocketPath(socketURL.path)
        )
        let client = AgentClient(socketPath: AgentSocketPath(socketURL.path))

        try await listener.start()
        let halfOpenDescriptor = try connectedDescriptor(to: socketURL)
        do {
            try await waitForActiveConnection(in: listener)
            let response = try await client.send(.status)
            guard case .status(let status) = response else {
                Issue.record("Expected a status response while another client is half-open.")
                Darwin.close(halfOpenDescriptor)
                await listener.stop()
                return
            }
            #expect(status.running)
            Darwin.close(halfOpenDescriptor)
            await listener.stop()
        } catch {
            Darwin.close(halfOpenDescriptor)
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1))) func stopTerminatesHalfOpenConnections() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let listener = AgentSocketListener(
            handler: AgentCommandHandler(),
            socketPath: AgentSocketPath(socketURL.path)
        )

        try await listener.start()
        let halfOpenDescriptor = try connectedDescriptor(to: socketURL)
        do {
            try await waitForActiveConnection(in: listener)
            await listener.stop()
            #expect(!(await listener.isRunning))
            #expect(await listener.activeConnectionCount == 0)
            Darwin.close(halfOpenDescriptor)
        } catch {
            Darwin.close(halfOpenDescriptor)
            await listener.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1))) func rejectsOversizedFrameAndContinuesServing() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")

        try await withRunningListener(
            controller: AgentCommandController(),
            socketURL: socketURL
        ) { _, client in
            let descriptor = try connectedDescriptor(to: socketURL)
            defer {
                Darwin.close(descriptor)
            }
            let oversizedLength = UInt64(AgentSocketIO.maximumFrameByteCount + 1)
            try writeRaw(
                Data([
                    UInt8(truncatingIfNeeded: oversizedLength >> 56),
                    UInt8(truncatingIfNeeded: oversizedLength >> 48),
                    UInt8(truncatingIfNeeded: oversizedLength >> 40),
                    UInt8(truncatingIfNeeded: oversizedLength >> 32),
                    UInt8(truncatingIfNeeded: oversizedLength >> 24),
                    UInt8(truncatingIfNeeded: oversizedLength >> 16),
                    UInt8(truncatingIfNeeded: oversizedLength >> 8),
                    UInt8(truncatingIfNeeded: oversizedLength),
                ]),
                to: descriptor
            )
            let failureData = try AgentSocketIO.readFrame(from: descriptor)
            let failure = try AgentMessageCodec().decodeResponse(from: failureData)
            guard case .failure(let error) = failure else {
                Issue.record("Expected an oversized frame failure.")
                return
            }
            #expect(error.code == .commandInvalid)

            guard case .status(let status) = try await client.send(.status) else {
                Issue.record("Expected the listener to survive an oversized frame.")
                return
            }
            #expect(status.running)
        }
    }

    private func withRunningListener<T>(
        controller: sending AgentCommandController,
        socketURL: URL,
        operation: (AgentSocketListener, AgentClient) async throws -> T
    ) async throws -> T {
        let socketPath = AgentSocketPath(socketURL.path)
        let listener = AgentSocketListener(
            handler: AgentCommandHandler(controller: controller),
            socketPath: socketPath
        )
        let client = AgentClient(socketPath: socketPath)

        try await listener.start()
        do {
            let result = try await operation(listener, client)
            await listener.stop()
            return result
        } catch {
            await listener.stop()
            throw error
        }
    }

    private func sendRaw(_ data: Data, to socketURL: URL) throws -> Data {
        let descriptor = try connectedDescriptor(to: socketURL)
        defer {
            Darwin.close(descriptor)
        }

        try AgentSocketIO.writeFrame(data, to: descriptor)
        return try AgentSocketIO.readFrame(from: descriptor)
    }

    private func connectedDescriptor(to socketURL: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to create test socket. errno=\(errno)"
            )
        }
        do {
            try AgentSocketIO.configure(descriptor)
            try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(descriptor, address, length) == 0 else {
                    throw EditorError(
                        code: .agentConnectionFailed,
                        message: "Failed to connect test socket. errno=\(errno)"
                    )
                }
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func waitForActiveConnection(
        in listener: AgentSocketListener
    ) async throws {
        for _ in 0..<200 {
            if await listener.activeConnectionCount > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EditorError(
            code: .agentConnectionFailed,
            message: "Listener did not accept the test connection."
        )
    }

    private func writeRaw(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written == -1 && errno == EINTR {
                    continue
                } else {
                    throw EditorError(
                        code: .agentConnectionFailed,
                        message: "Failed to write raw test frame. errno=\(errno)"
                    )
                }
            }
        }
    }

    private func sendThroughClient(
        _ request: AgentRequest,
        socketPath: AgentSocketPath
    ) async throws -> AgentResponse {
        let client = AgentClient(socketPath: socketPath)
        return try await client.send(request)
    }

    private func requireSessionOperation(
        _ response: AgentResponse,
        operation: AgentSessionOperationResult.Operation
    ) throws -> AgentSessionOperationResult {
        guard case .sessionOperation(let result) = response else {
            Issue.record("Expected session operation result for \(operation.rawValue).")
            throw EditorError(
                code: .commandFailed,
                message: "Expected session operation result."
            )
        }
        #expect(result.operation == operation)
        return result
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        return temporaryDirectory
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }
}
