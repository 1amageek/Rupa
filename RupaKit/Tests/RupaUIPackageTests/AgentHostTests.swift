import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaCore
import RupaUI
import Testing
@testable import RupaAgentUI

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

@MainActor
@Test(.timeLimit(.minutes(1))) func agentHostDoesNotReturnToRunningAfterStopDuringStart() async throws {
    let socketPath = AgentSocketPath("/tmp/rupa-host-race-\(UUID().uuidString).sock")
    let listener = BlockingAgentHostListener()
    let host = AgentHost(socketPath: socketPath, listener: listener)

    let startTask = Task { @MainActor in
        await host.start()
    }
    var didReachStarting = false
    for _ in 0..<20 {
        if host.state == .starting,
           await listener.hasPendingStart() {
            didReachStarting = true
            break
        }
        await Task.yield()
    }
    #expect(didReachStarting)

    let stopTask = Task { @MainActor in
        await host.stop()
    }
    await stopTask.value
    await startTask.value

    #expect(host.state == .stopped)
    #expect(await listener.stopCallCount() == 1)
}

private func sendThroughDetachedClient(
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

private actor BlockingAgentHostListener: AgentHostListening {
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var didStop = false
    private var stopCount = 0

    func start() async throws {
        guard !didStop else {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            if didStop {
                continuation.resume()
            } else {
                startContinuation = continuation
            }
        }
    }

    func stop() async {
        stopCount += 1
        didStop = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func hasPendingStart() -> Bool {
        startContinuation != nil
    }

    func stopCallCount() -> Int {
        stopCount
    }
}
