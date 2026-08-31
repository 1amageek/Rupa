import Darwin
import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAgentTransport
import RupaAutomation
import RupaCore
import RupaDomainFoundation
import RupaKit
import RupaUI
import Testing
@testable import RupaAgentUI

@MainActor
@Test(.timeLimit(.minutes(1))) func agentHostStartsSocketAndPublishesRegisteredSession() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let endpoint = try UnixSocketEndpoint(
        fileURL: temporaryDirectory.appendingPathComponent("rupa.sock")
    )
    let controller = ProjectAgentCommandController()
    let host = AgentHost(
        handler: controller,
        endpoint: endpoint,
        peerAuthorizer: SameUserAgentPeerAuthorizer(
            expectedUserID: getuid()
        )
    )
    let sessionID = UUID()
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: .empty(named: "Host Open")
    )
    _ = try await workspace.evaluate()
    try await controller.register(workspace: workspace, id: sessionID)

    await host.start()
    do {
        guard host.state == .running else {
            #expect(Bool(false))
            await host.stop()
            return
        }

        let status = try await sendThroughDetachedClient(.status, endpoint: endpoint)
        guard case .status(let agentStatus) = status else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(agentStatus.running)
        #expect(agentStatus.sessionCount == 1)

        let sessions = try await sendThroughDetachedClient(.sessions, endpoint: endpoint)
        guard case .sessions(let summaries) = sessions else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(summaries.first?.id == sessionID)
        #expect(summaries.first?.displayName == "Host Open")

        guard let initial = summaries.first else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        let sourceResponse = try await sendThroughDetachedClient(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Agent Renamed"),
                expectedGeneration: initial.generation
            ),
            endpoint: endpoint
        )
        guard case .command(let sourceResult) = sourceResponse else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(sourceResult.didMutate)

        let interactionResponse = try await sendThroughDetachedClient(
            .execute(
                sessionID: sessionID,
                command: .setDisplayUnit(.millimeter),
                expectedGeneration: sourceResult.generation,
                expectedWorkspaceRevision: sourceResult.workspaceRevision
            ),
            endpoint: endpoint
        )
        guard case .command(let interactionResult) = interactionResponse else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(interactionResult.workspaceRevision != sourceResult.workspaceRevision)

        let readResponse = try await sendThroughDetachedClient(
            .measure(
                sessionID: sessionID,
                expectedGeneration: sourceResult.generation
            ),
            endpoint: endpoint
        )
        guard case .measurement(let measurement) = readResponse else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(measurement.displayUnit == .millimeter)

        let renamedSessions = try await sendThroughDetachedClient(
            .sessions,
            endpoint: endpoint
        )
        guard case .sessions(let renamedSummaries) = renamedSessions else {
            #expect(Bool(false))
            await host.stop()
            return
        }
        #expect(renamedSummaries.first?.displayName == "Agent Renamed")

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

    let endpoint = try UnixSocketEndpoint(
        fileURL: temporaryDirectory.appendingPathComponent("rupa-domain.sock")
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
    let controller = ProjectAgentCommandController(
        domainRegistry: domainRegistry
    )
    let host = AgentHost(
        handler: controller,
        endpoint: endpoint,
        peerAuthorizer: SameUserAgentPeerAuthorizer(
            expectedUserID: getuid()
        )
    )

    await host.start()
    do {
        let response = try await sendThroughDetachedClient(.capabilities, endpoint: endpoint)
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
    let listener = BlockingAgentHostListener()
    let host = AgentHost(listener: listener)

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
    endpoint: UnixSocketEndpoint
) async throws -> AgentResponse {
    let client = AgentClient(endpoint: endpoint)
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
