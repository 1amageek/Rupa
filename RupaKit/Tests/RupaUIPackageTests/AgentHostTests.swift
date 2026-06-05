import Foundation
import RupaAgent
import RupaCore
import RupaUI
import Testing

@MainActor
@Test(.timeLimit(.minutes(1))) func agentHostStartsSocketAndPublishesRegisteredSession() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let socketPath = AgentSocketPath(
        temporaryDirectory
            .appendingPathComponent("rupa.sock")
            .path
    )
    let host = AgentHost(socketPath: socketPath)
    let sessionID = UUID()
    host.register(
        session: EditorSession(document: .empty(named: "Host Open")),
        id: sessionID
    )

    await host.start()
    do {
        guard case .running(let path) = host.state else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(path == socketPath.value)

        let status = try await sendThroughDetachedClient(.status, socketPath: socketPath)
        guard case .status(let agentStatus) = status else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(agentStatus.running)
        #expect(agentStatus.sessionCount == 1)

        let sessions = try await sendThroughDetachedClient(.sessions, socketPath: socketPath)
        guard case .sessions(let summaries) = sessions else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(summaries.first?.id == sessionID)
        #expect(summaries.first?.displayName == "Host Open")

        await host.stop()
        #expect(host.state == .stopped)
    } catch {
        await host.stop()
        throw error
    }
}

private func sendThroughDetachedClient(
    _ request: AgentRequest,
    socketPath: AgentSocketPath
) async throws -> AgentResponse {
    try await Task.detached {
        let client = AgentClient(socketPath: socketPath)
        return try client.send(request)
    }.value
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
