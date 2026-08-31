import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
import RupaProjectAccessComposition
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func defaultProjectAccessRoutesEveryTargetToExactlyOneOpener() async throws {
    let liveSession = ProjectAccessSessionProbe()
    let closedSession = ProjectAccessSessionProbe()
    let live = ProjectAccessOpeningProbe(session: liveSession)
    let closed = ProjectAccessOpeningProbe(session: closedSession)
    let observer = ProjectAccessObserverProbe()
    let access = DefaultProjectAccess(
        liveOpening: live,
        liveObserver: observer,
        closedOpening: closed
    )
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    let projectURL = URL(fileURLWithPath: "/tmp/router.rupa")
    let liveID = UUID()

    let project = try await access.open(
        .liveProject(projectURL),
        deadline: deadline
    )
    let attached = try await access.open(
        .liveSession(liveID),
        deadline: deadline
    )
    let file = try await access.open(
        .closedProject(input: projectURL, output: nil),
        deadline: deadline
    )

    #expect(project.sessionID == liveSession.sessionID)
    #expect(attached.sessionID == liveSession.sessionID)
    #expect(file.sessionID == closedSession.sessionID)
    #expect(live.targets == [.liveProject(projectURL), .liveSession(liveID)])
    #expect(closed.targets == [.closedProject(input: projectURL, output: nil)])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func defaultProjectAccessNeverFallsBackAfterSelectedOpenerFailure() async {
    let liveFailure = ProjectAccessOpeningProbe(error: ProjectAccessRouteProbeError.live)
    let closedAfterLive = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let liveAccess = DefaultProjectAccess(
        liveOpening: liveFailure,
        liveObserver: ProjectAccessObserverProbe(),
        closedOpening: closedAfterLive
    )
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))

    await #expect(throws: ProjectAccessRouteProbeError.live) {
        _ = try await liveAccess.open(
            .liveSession(UUID()),
            deadline: deadline
        )
    }
    #expect(liveFailure.targets.count == 1)
    #expect(closedAfterLive.targets.isEmpty)

    let liveAfterClosed = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let closedFailure = ProjectAccessOpeningProbe(error: ProjectAccessRouteProbeError.closed)
    let closedAccess = DefaultProjectAccess(
        liveOpening: liveAfterClosed,
        liveObserver: ProjectAccessObserverProbe(),
        closedOpening: closedFailure
    )
    let input = URL(fileURLWithPath: "/tmp/no-fallback.rupa")

    await #expect(throws: ProjectAccessRouteProbeError.closed) {
        _ = try await closedAccess.open(
            .closedProject(input: input, output: nil),
            deadline: deadline
        )
    }
    #expect(closedFailure.targets == [.closedProject(input: input, output: nil)])
    #expect(liveAfterClosed.targets.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func defaultProjectAccessRejectsLegacyFormatBeforeSelectingAnOpener() async {
    let live = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let closed = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let access = DefaultProjectAccess(
        liveOpening: live,
        liveObserver: ProjectAccessObserverProbe(),
        closedOpening: closed
    )
    let legacy = URL(fileURLWithPath: "/tmp/legacy.swcad")

    await #expect(throws: ProjectAccessError.unsupportedProjectFormat(legacy)) {
        _ = try await access.open(
            .closedProject(input: legacy, output: nil),
            deadline: ContinuousClock.now.advanced(by: .seconds(1))
        )
    }
    #expect(live.targets.isEmpty)
    #expect(closed.targets.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func defaultProjectAccessObservationsUseOnlyTheLiveObserver() async throws {
    let summary = WorkspaceSessionSummary(
        id: UUID(),
        path: "/tmp/observed.rupa",
        displayName: "Observed",
        dirty: false,
        generation: DocumentGeneration(2),
        workspaceRevision: WorkspaceRevision(3)
    )
    let observer = ProjectAccessObserverProbe(
        status: AgentStatus(running: true, sessionCount: 1),
        sessions: [summary]
    )
    let live = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let closed = ProjectAccessOpeningProbe(session: ProjectAccessSessionProbe())
    let access = DefaultProjectAccess(
        liveOpening: live,
        liveObserver: observer,
        closedOpening: closed
    )
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))

    #expect(try await access.capabilities(deadline: deadline).isEmpty)
    #expect(try await access.status(deadline: deadline) == observer.resultStatus)
    #expect(try await access.sessions(deadline: deadline) == [summary])
    #expect(observer.capabilitiesDeadlines == [deadline])
    #expect(observer.statusDeadlines == [deadline])
    #expect(observer.sessionsDeadlines == [deadline])
    #expect(live.targets.isEmpty)
    #expect(closed.targets.isEmpty)
}

private enum ProjectAccessRouteProbeError: Error, Equatable {
    case live
    case closed
}

@MainActor
private final class ProjectAccessOpeningProbe: ProjectAccessOpening {
    private let session: (any ProjectAccessSession)?
    private let error: Error?
    private(set) var targets: [ProjectAccessTarget] = []

    init(session: any ProjectAccessSession) {
        self.session = session
        self.error = nil
    }

    init(error: Error) {
        self.session = nil
        self.error = error
    }

    func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        targets.append(target)
        if let error {
            throw error
        }
        guard let session else {
            throw ProjectAccessError.authorityUnavailable
        }
        return session
    }
}

@MainActor
private final class ProjectAccessObserverProbe: ProjectAccessObserving {
    let resultStatus: AgentStatus
    private let resultSessions: [WorkspaceSessionSummary]
    private(set) var capabilitiesDeadlines: [ContinuousClock.Instant] = []
    private(set) var statusDeadlines: [ContinuousClock.Instant] = []
    private(set) var sessionsDeadlines: [ContinuousClock.Instant] = []

    init(
        status: AgentStatus = AgentStatus(running: false, sessionCount: 0),
        sessions: [WorkspaceSessionSummary] = []
    ) {
        self.resultStatus = status
        self.resultSessions = sessions
    }

    func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor] {
        capabilitiesDeadlines.append(deadline)
        return []
    }

    func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus {
        statusDeadlines.append(deadline)
        return resultStatus
    }

    func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        sessionsDeadlines.append(deadline)
        return resultSessions
    }
}

private actor ProjectAccessSessionProbe: ProjectAccessSession {
    nonisolated let sessionID = UUID()

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        .capabilities([])
    }

    func save(expectedGeneration: DocumentGeneration?) async throws -> SaveResult {
        throw ProjectAccessError.saveUnavailable
    }

    func finish() async {}
}
