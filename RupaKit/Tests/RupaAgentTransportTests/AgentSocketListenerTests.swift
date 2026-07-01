import Darwin
import Foundation
import Testing
import RupaAgentProtocol
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
            mainActorBridge: bridge,
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

    @Test(.timeLimit(.minutes(1))) func stopRemovesSocketAndRejectsClient() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
        let listener = AgentSocketListener(
            controller: AgentCommandController(),
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

    private func withRunningListener<T>(
        controller: sending AgentCommandController,
        socketURL: URL,
        operation: (AgentSocketListener, AgentClient) async throws -> T
    ) async throws -> T {
        let socketPath = AgentSocketPath(socketURL.path)
        let listener = AgentSocketListener(
            controller: controller,
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
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Failed to create test socket. errno=\(errno)"
            )
        }
        defer {
            Darwin.close(descriptor)
        }

        try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
            guard Darwin.connect(descriptor, address, length) == 0 else {
                throw EditorError(
                    code: .agentConnectionFailed,
                    message: "Failed to connect test socket. errno=\(errno)"
                )
            }
        }
        try AgentSocketIO.writeAll(data, to: descriptor)
        Darwin.shutdown(descriptor, SHUT_WR)
        return try AgentSocketIO.readAll(from: descriptor)
    }

    private func sendThroughClient(
        _ request: AgentRequest,
        socketPath: AgentSocketPath
    ) async throws -> AgentResponse {
        let client = AgentClient(socketPath: socketPath)
        return try await client.send(request)
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
