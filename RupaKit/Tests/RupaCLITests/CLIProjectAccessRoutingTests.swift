import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func cliServiceSelectsExactLiveAndFileTargets() async throws {
    let sessionID = UUID()
    let liveProjectSession = StubProjectAccessSession(
        sessionID: sessionID,
        steps: [.response(.status(AgentStatus(running: true, sessionCount: 1)))]
    )
    let liveSession = StubProjectAccessSession(
        sessionID: sessionID,
        steps: [.response(.status(AgentStatus(running: true, sessionCount: 1)))]
    )
    let fileSession = StubProjectAccessSession(
        sessionID: sessionID,
        steps: [.response(.status(AgentStatus(running: true, sessionCount: 1)))]
    )
    let liveProjectOpener = StubProjectAccessOpener(session: liveProjectSession)
    let liveSessionOpener = StubProjectAccessOpener(session: liveSession)
    let fileOpener = StubProjectAccessOpener(session: fileSession)
    let observer = await makeStubProjectAccessObserver()
    let projectURL = URL(fileURLWithPath: "/tmp/target.rupa")

    try await withStubProjectAccess(opener: liveProjectOpener, observer: observer) {
        _ = try await CLIService().send(
            target: CLIDocumentTarget(fileURL: projectURL),
            mode: .live,
            request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
        )
    }
    try await withStubProjectAccess(opener: liveSessionOpener, observer: observer) {
        _ = try await CLIService().send(
            target: CLIDocumentTarget(sessionID: sessionID),
            mode: .live,
            request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
        )
    }
    try await withStubProjectAccess(opener: fileOpener, observer: observer) {
        _ = try await CLIService().send(
            target: CLIDocumentTarget(fileURL: projectURL),
            mode: .file,
            request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
        )
    }

    #expect(await liveProjectOpener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await liveSessionOpener.recordedTargets() == [.liveSession(sessionID)])
    #expect(await fileOpener.recordedTargets() == [
        .closedProject(input: projectURL, output: nil),
    ])
    #expect(await liveProjectSession.recordedFinishCount() == 1)
    #expect(await liveSession.recordedFinishCount() == 1)
    #expect(await fileSession.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func cliRejectsLegacyProjectBeforeOpeningAccess() async {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let legacyURL = URL(fileURLWithPath: "/tmp/legacy.swcad")

    await #expect(throws: ProjectAccessError.unsupportedProjectFormat(legacyURL)) {
        try await withStubProjectAccess(opener: opener, observer: observer) {
            _ = try await CLIService().send(
                target: CLIDocumentTarget(fileURL: legacyURL),
                mode: .file,
                request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
            )
        }
    }

    #expect(await opener.recordedTargets().isEmpty)
    #expect(await session.recordedRequests().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func oneCLICommandReusesOneSessionAndFinishesItOnce() async throws {
    let session = StubProjectAccessSession(
        steps: [
            .response(.status(AgentStatus(running: true, sessionCount: 1))),
            .response(.status(AgentStatus(running: true, sessionCount: 1))),
        ]
    )
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    let projectURL = URL(fileURLWithPath: "/tmp/one-command.rupa")

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            for _ in 0..<2 {
                _ = try await CLIService().send(
                    target: CLIDocumentTarget(fileURL: projectURL),
                    mode: .live,
                    request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
                )
            }
        }
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await opener.recordedDeadlines().count == 1)
    #expect(await session.recordedRequests().count == 2)
    #expect(await session.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func concurrentWorkInOneCLICommandSharesOneOpeningTaskAndSession() async throws {
    let session = StubProjectAccessSession(
        steps: [
            .response(.status(AgentStatus(running: true, sessionCount: 1))),
            .response(.status(AgentStatus(running: true, sessionCount: 1))),
        ]
    )
    let opener = StubProjectAccessOpener(
        session: session,
        openDelay: .milliseconds(20)
    )
    let observer = await makeStubProjectAccessObserver()
    let projectURL = URL(fileURLWithPath: "/tmp/concurrent-command.rupa")

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            async let first = CLIService().send(
                target: CLIDocumentTarget(fileURL: projectURL),
                mode: .live,
                request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
            )
            async let second = CLIService().send(
                target: CLIDocumentTarget(fileURL: projectURL),
                mode: .live,
                request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
            )
            _ = try await (first, second)
        }
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await opener.recordedDeadlines().count == 1)
    #expect(await session.recordedRequests().count == 2)
    #expect(await session.recordedFinishCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func selectedCLIOpenerFailureDoesNotRetryAnotherRoute() async {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(
        session: session,
        error: .sessionUnavailable(nil)
    )
    let observer = await makeStubProjectAccessObserver()
    let projectURL = URL(fileURLWithPath: "/tmp/unavailable.rupa")

    await #expect(throws: ProjectAccessError.sessionUnavailable(nil)) {
        try await withStubProjectAccess(opener: opener, observer: observer) {
            _ = try await CLIService().send(
                target: CLIDocumentTarget(fileURL: projectURL),
                mode: .live,
                request: { .evaluate(sessionID: $0, expectedGeneration: nil) }
            )
        }
    }

    #expect(await opener.recordedTargets() == [.liveProject(projectURL)])
    #expect(await session.recordedRequests().isEmpty)
    #expect(await session.recordedFinishCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func statusSessionsAndAttachObserveWithoutOpeningAProject() async throws {
    let sessionID = UUID()
    let summary = WorkspaceSessionSummary(
        id: sessionID,
        path: "/tmp/open.rupa",
        displayName: "Open",
        dirty: true,
        generation: DocumentGeneration(4),
        workspaceRevision: WorkspaceRevision(7)
    )
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver(
        status: AgentStatus(running: true, sessionCount: 1),
        sessions: [summary]
    )

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            let status = try await CLIService().agentStatus()
            let sessions = try await CLIService().sessions()
            let attachment = try await CLIService().attach(
                target: CLIDocumentTarget(sessionID: sessionID)
            )
            #expect(status.sessionCount == 1)
            #expect(sessions.sessions == [summary])
            #expect(attachment.sessionID == sessionID)
        }
    }

    let observationCounts = await MainActor.run {
        (
            status: observer.statusCallCount,
            sessions: observer.sessionsCallCount,
            deadlineCount: Set(observer.statusDeadlines + observer.sessionsDeadlines).count
        )
    }
    #expect(observationCounts.status == 1)
    #expect(observationCounts.sessions == 2)
    #expect(observationCounts.deadlineCount == 1)
    #expect(await opener.recordedTargets().isEmpty)
    #expect(await session.recordedFinishCount() == 0)
}

@Test(.timeLimit(.minutes(1)))
func capabilitiesCommandUsesOneObserverCallAndNeverOpensAProject() async throws {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver()
    await MainActor.run {
        observer.capabilitiesResult = [
            stubCapability(name: "document.evaluate"),
            stubCapability(name: "document.export"),
        ]
    }
    let command = try Capabilities.parse([])

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await command.run()
    }

    let capabilityObservation = await MainActor.run {
        (observer.capabilitiesCallCount, observer.capabilitiesDeadlines.count)
    }
    #expect(capabilityObservation.0 == 1)
    #expect(capabilityObservation.1 == 1)
    #expect(await opener.recordedTargets().isEmpty)
    #expect(await session.recordedRequests().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func capabilitiesPreserveObserverOrderAndTheCommandsSingleDeadline() async throws {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver(
        status: AgentStatus(running: true, sessionCount: 0)
    )
    await MainActor.run {
        observer.capabilitiesResult = [
            stubCapability(name: "z.last"),
            stubCapability(name: "a.first"),
        ]
    }

    try await withStubProjectAccess(opener: opener, observer: observer) {
        try await CLIProjectAccessRunner.withCommandScope {
            let capabilities = try await CLIService().capabilities()
            #expect(capabilities == ["z.last", "a.first"])
            _ = try await CLIService().agentStatus()
        }
    }

    let deadlineObservation = await MainActor.run {
        (
            capabilities: observer.capabilitiesCallCount,
            status: observer.statusCallCount,
            sameDeadline: observer.capabilitiesDeadlines == observer.statusDeadlines
        )
    }
    #expect(deadlineObservation.capabilities == 1)
    #expect(deadlineObservation.status == 1)
    #expect(deadlineObservation.sameDeadline)
    #expect(await opener.recordedTargets().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func capabilitiesObserverFailureIsTypedAndHasNoProjectFallback() async {
    let session = StubProjectAccessSession(steps: [])
    let opener = StubProjectAccessOpener(session: session)
    let observer = await makeStubProjectAccessObserver(error: .authorityUnavailable)

    await #expect(throws: ProjectAccessError.authorityUnavailable) {
        try await withStubProjectAccess(opener: opener, observer: observer) {
            _ = try await CLIService().capabilities()
        }
    }

    let capabilitiesCallCount = await observer.capabilitiesCallCount
    #expect(capabilitiesCallCount == 1)
    #expect(await opener.recordedTargets().isEmpty)
    #expect(await session.recordedRequests().isEmpty)
}

private func stubCapability(name: String) -> AgentCapabilityDescriptor {
    AgentCapabilityDescriptor(
        name: name,
        category: .read,
        summary: "CLI access contract probe.",
        access: .agentRequest,
        stateEffect: .readOnly,
        requiresSession: false,
        requiresExpectedSourceGeneration: false,
        failureMode: "Returns a typed project access failure."
    )
}
