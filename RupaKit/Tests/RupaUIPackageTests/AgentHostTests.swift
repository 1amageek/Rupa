import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaAutomation
import RupaCore
import RupaDomainFoundation
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
@Test(.timeLimit(.minutes(1))) func agentHostPublishesInjectedDomainCapabilitiesThroughSocket() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let socketPath = AgentSocketPath(
        temporaryDirectory
            .appendingPathComponent("rupa-domain.sock")
            .path
    )
    let capabilityID: DomainCapabilityID = "manufacturing.validatePrintability"
    let domainRegistry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: "manufacturing",
                name: "Validate Printability",
                summary: "Checks manufacturing constraints.",
                effect: .query,
                resultKind: .semanticPayload,
                supportsDryRun: true,
                targetKinds: ["document"],
                failureMode: "Reports manufacturing diagnostics without mutation."
            ),
        ],
        commandLowerings: [
            AgentHostFixtureDomainLowering(capabilityID: capabilityID),
        ]
    )
    let host = AgentHost(
        socketPath: socketPath,
        domainRegistry: domainRegistry
    )

    await host.start()
    do {
        let response = try await sendThroughDetachedClient(.capabilities, socketPath: socketPath)
        guard case .capabilities(let descriptors) = response else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(descriptors.contains { $0.name == capabilityID.rawValue })
        await host.stop()
    } catch {
        await host.stop()
        throw error
    }
}

private struct AgentHostFixtureDomainLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Agent Host Fixture")],
                expectedGeneration: request.expectedGeneration
            )
        )
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
