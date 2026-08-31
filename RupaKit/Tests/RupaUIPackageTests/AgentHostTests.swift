import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAgentTransport
import RupaKit
import Testing
@testable import RupaAgentUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentHostStartsAuthenticatedHTTPAndRoutesToRegisteredWorkspace() async throws {
    let key = Data(repeating: 0x42, count: 32)
    let generation: UInt64 = 41
    let controller = ProjectAgentCommandController()
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Host Open")
    )
    _ = try await workspace.evaluate()
    let sessionID = UUID()
    try await controller.register(workspace: workspace, id: sessionID)

    let host = AgentHost(
        handler: controller,
        key: key,
        generation: generation,
        requestTimeout: .seconds(5),
        shutdownTimeout: .seconds(1)
    )
    let endpoint = try await host.start()
    do {
        #expect(host.state == .running)
        let client = AgentHTTPClient(
            endpoint: endpoint,
            key: key,
            generation: generation,
            requestTimeout: .seconds(5)
        )
        let response = try await client.send(.sessions)
        guard case .sessions(let sessions) = response else {
            Issue.record("Expected the App-owned workspace session.")
            await host.stop()
            return
        }
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == sessionID)
        #expect(sessions.first?.displayName == "Host Open")
        await host.stop()
        #expect(host.state == .stopped)
    } catch {
        await host.stop()
        throw error
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentHostCannotRestartAnEndedListenerLifetime() async throws {
    let host = AgentHost(
        handler: StatusAgentRequestHandler(),
        key: Data(repeating: 0x24, count: 32),
        generation: 42,
        requestTimeout: .seconds(5),
        shutdownTimeout: .seconds(1)
    )

    _ = try await host.start()
    await host.stop()

    await #expect(throws: AgentHostError.listenerLifetimeEnded) {
        _ = try await host.start()
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func agentHostDoesNotPublishRunningAfterStopDuringStart() async throws {
    let listener = BlockingAgentHostListener()
    let host = AgentHost(listener: listener)

    let startTask = Task { @MainActor in
        try await host.start()
    }
    for _ in 0..<100 where !(await listener.hasPendingStart()) {
        await Task.yield()
    }
    #expect(host.state == .starting)
    #expect(await listener.hasPendingStart())

    await host.stop()
    await #expect(throws: CancellationError.self) {
        _ = try await startTask.value
    }
    #expect(host.state == .stopped)
    #expect(await listener.stopCallCount() >= 1)
}

private struct StatusAgentRequestHandler: AgentRequestHandling {
    func handle(_ request: AgentRequest) async -> AgentResponse {
        .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private actor BlockingAgentHostListener: AgentHostListening {
    private var startContinuation:
        CheckedContinuation<AgentHTTPEndpoint, any Error>?
    private var stopCount = 0

    func start() async throws -> AgentHTTPEndpoint {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func stop() async {
        stopCount += 1
        guard let startContinuation else {
            return
        }
        self.startContinuation = nil
        do {
            startContinuation.resume(returning: try AgentHTTPEndpoint(port: 9_999))
        } catch {
            startContinuation.resume(throwing: error)
        }
    }

    func hasPendingStart() -> Bool {
        startContinuation != nil
    }

    func stopCallCount() -> Int {
        stopCount
    }
}
