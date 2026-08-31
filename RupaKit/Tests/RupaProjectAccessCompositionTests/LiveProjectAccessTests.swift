import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
@testable import RupaProjectAccessComposition
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveSessionOpeningDoesNotLaunchAndUsesTheResolvedSession() async throws {
    let sessionID = UUID()
    let summary = liveSummary(
        id: sessionID,
        path: "/tmp/live-session.rupa"
    )
    let transport = LiveAccessRecordingTransport(
        responses: [
            .sessions([summary]),
            .capabilities([]),
        ]
    )
    let resolver = LiveProjectSessionResolver(transport: transport)
    let launcher = LiveAccessRecordingLauncher()
    let opening = LiveProjectAccessOpening(
        launcher: launcher,
        resolver: resolver,
        transport: transport
    )

    let session = try await opening.open(
        .liveSession(sessionID),
        deadline: liveDeadline()
    )
    #expect(session.sessionID == sessionID)
    #expect(launcher.calls.isEmpty)

    let response = try await session.send(.capabilities)
    guard case .capabilities = response else {
        Issue.record("The live session must forward the request through the Agent transport.")
        await session.finish()
        return
    }
    #expect(transport.requests.count == 2)
    await session.finish()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveProjectOpeningUsesOneLaunchAndRejectsDirtyReplacement() async throws {
    let directory = try makeLiveAccessTemporaryDirectory()
    defer { removeLiveAccessTemporaryDirectory(directory) }
    let target = directory.appendingPathComponent("target.rupa")
    let alias = directory.appendingPathComponent("alias.rupa")
    try Data().write(to: target)
    try FileManager.default.createSymbolicLink(
        at: alias,
        withDestinationURL: target
    )

    let attached = liveSummary(
        id: UUID(),
        path: target.path,
        dirty: true
    )
    let attachedTransport = LiveAccessRecordingTransport(
        responses: [.sessions([attached])]
    )
    let attachedLauncher = LiveAccessRecordingLauncher()
    let attachedOpening = LiveProjectAccessOpening(
        launcher: attachedLauncher,
        resolver: LiveProjectSessionResolver(transport: attachedTransport),
        transport: attachedTransport
    )
    let attachedSession = try await attachedOpening.open(
        .liveProject(alias),
        deadline: liveDeadline()
    )
    #expect(attachedSession.sessionID == attached.id)
    #expect(attachedLauncher.calls == [target.standardizedFileURL])
    await attachedSession.finish()

    let different = liveSummary(
        id: UUID(),
        path: directory.appendingPathComponent("other.rupa").path,
        dirty: true
    )
    let dirtyTransport = LiveAccessRecordingTransport(
        responses: [.sessions([different])]
    )
    let dirtyLauncher = LiveAccessRecordingLauncher()
    let dirtyOpening = LiveProjectAccessOpening(
        launcher: dirtyLauncher,
        resolver: LiveProjectSessionResolver(transport: dirtyTransport),
        transport: dirtyTransport
    )
    do {
        _ = try await dirtyOpening.open(
            .liveProject(target),
            deadline: liveDeadline()
        )
        Issue.record("A dirty different project must be rejected without replacement.")
    } catch let error as LiveProjectAccessError {
        #expect(error == .dirtyProjectConflict(target.standardizedFileURL))
    }
    #expect(dirtyLauncher.calls == [target.standardizedFileURL])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveProjectOpeningLaunchesOnceWhenTargetIsNotAttached() async throws {
    let target = URL(fileURLWithPath: "/tmp/live-project-launch.rupa")
    let sessionID = UUID()
    let summary = liveSummary(id: sessionID, path: target.path)
    let transport = LiveAccessRecordingTransport(
        responses: [
            .sessions([]),
            .sessions([summary]),
        ]
    )
    let launcher = LiveAccessRecordingLauncher()
    let opening = LiveProjectAccessOpening(
        launcher: launcher,
        resolver: LiveProjectSessionResolver(transport: transport),
        transport: transport
    )

    let session = try await opening.open(
        .liveProject(target),
        deadline: liveDeadline()
    )
    #expect(session.sessionID == sessionID)
    #expect(launcher.calls == [target.standardizedFileURL])
    await session.finish()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveObservationStatusAndSessionsNeverLaunch() async throws {
    let summary = liveSummary(
        id: UUID(),
        path: "/tmp/observation.rupa"
    )
    let transport = LiveAccessRecordingTransport(
        responses: [
            .status(AgentStatus(running: true, sessionCount: 1)),
            .sessions([summary]),
        ]
    )
    let launcher = LiveAccessRecordingLauncher()
    let opening = LiveProjectAccessOpening(
        launcher: launcher,
        resolver: LiveProjectSessionResolver(transport: transport),
        transport: transport
    )

    let status = try await opening.status(deadline: liveDeadline())
    let sessions = try await opening.sessions(deadline: liveDeadline())
    #expect(status == AgentStatus(running: true, sessionCount: 1))
    #expect(sessions == [summary])
    #expect(launcher.calls.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveSessionSaveIsTheOnlyPersistenceDispatchAndFinishedWins() async throws {
    let sessionID = UUID()
    let saveResult = SaveResult(
        message: "saved",
        path: "/tmp/live-save.rupa",
        generation: DocumentGeneration(4),
        dirty: false,
        diagnostics: []
    )
    let transport = LiveAccessRecordingTransport(
        responses: [
            .save(saveResult),
        ]
    )
    let session = LiveProjectAccessSession(
        sessionID: sessionID,
        transport: transport,
        deadline: liveDeadline()
    )

    do {
        _ = try await session.send(
            .save(sessionID: sessionID, expectedGeneration: nil)
        )
        Issue.record("Generic send must not expose persistence.")
    } catch let error as ProjectAccessError {
        #expect(error == .saveUnavailable)
    }
    #expect(transport.requests.isEmpty)

    let saved = try await session.save(expectedGeneration: DocumentGeneration(4))
    #expect(saved == saveResult)
    #expect(transport.requests.count == 1)

    await session.finish()
    do {
        _ = try await session.send(.capabilities)
        Issue.record("A finished live session must reject requests.")
    } catch let error as ProjectAccessError {
        #expect(error == .finished)
    }
    #expect(transport.requests.count == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveSessionFinishWaitsForAnAcceptedRequestAndThenRejectsNewWork() async throws {
    let sessionID = UUID()
    let transport = LiveAccessSuspendingTransport()
    let session = LiveProjectAccessSession(
        sessionID: sessionID,
        transport: transport,
        deadline: liveDeadline()
    )

    let requestTask = Task { @MainActor in
        try await session.send(.capabilities)
    }
    try await waitForLiveAccessCondition { transport.didStart }

    var finishDidReturn = false
    let finishTask = Task { @MainActor in
        await session.finish()
        finishDidReturn = true
    }
    await Task.yield()
    #expect(!finishDidReturn)

    transport.resume()
    guard case .capabilities = try await requestTask.value else {
        Issue.record("The accepted request must complete before finish returns.")
        await finishTask.value
        return
    }
    await finishTask.value
    #expect(finishDidReturn)

    do {
        _ = try await session.send(.capabilities)
        Issue.record("Finish must make the live access session terminal.")
    } catch let error as ProjectAccessError {
        #expect(error == .finished)
    }
    #expect(transport.requestCount == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveSessionMismatchAndUnknownOutcomeAreTerminalBeforeRetry() async throws {
    let sessionID = UUID()
    let transport = LiveAccessRecordingTransport(
        responses: [],
        failure: AgentTransportFailure(
            disposition: .outcomeUnknown(requestID: UUID()),
            cause: .transport(
                EditorError(
                    code: .agentConnectionFailed,
                    message: "response lost"
                )
            )
        )
    )
    let session = LiveProjectAccessSession(
        sessionID: sessionID,
        transport: transport,
        deadline: liveDeadline()
    )

    do {
        _ = try await session.send(
            .capabilities
        )
        Issue.record("The injected transport failure must be surfaced.")
    } catch let error as ProjectAccessError {
        guard case .outcomeUnknown = error else {
            Issue.record("The response-loss failure must be outcomeUnknown.")
            await session.finish()
            return
        }
    }
    #expect(transport.requests.count == 1)

    do {
        _ = try await session.send(
            .execute(
                sessionID: UUID(),
                command: .renameDocument(name: "wrong"),
                expectedGeneration: nil
            )
        )
        Issue.record("A mismatched session must be rejected before transport.")
    } catch let error as ProjectAccessError {
        guard case .sessionMismatch = error else {
            Issue.record("The wrong session returned the wrong failure.")
            await session.finish()
            return
        }
    }
    #expect(transport.requests.count == 1)
    await session.finish()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func liveSessionPathMustBeAbsoluteAndCanonical() async throws {
    let transport = LiveAccessRecordingTransport(
        responses: [
            .sessions([
                liveSummary(id: UUID(), path: "relative.rupa"),
            ]),
        ]
    )
    let resolver = LiveProjectSessionResolver(transport: transport)
    do {
        _ = try await resolver.sessions(deadline: liveDeadline())
        Issue.record("A relative session path must be rejected.")
    } catch let error as LiveProjectAccessError {
        #expect(error == .invalidSessionPath("relative.rupa"))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func launchServicesLauncherTargetsTheExactRupaApplication() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/exact-rupa-launch.rupa")
    let applicationURL = URL(fileURLWithPath: "/Applications/Rupa.app")
    let workspace = ProjectApplicationWorkspaceOpeningProbe(
        applicationURL: applicationURL
    )
    let launcher = LaunchServicesProjectApplicationLauncher(
        applicationBundleIdentifier: "team.stamp.Rupa",
        workspace: workspace
    )

    try await launcher.launch(
        projectURL: projectURL,
        deadline: liveDeadline()
    )

    #expect(workspace.requestedBundleIdentifiers == ["team.stamp.Rupa"])
    #expect(workspace.openedProjects == [projectURL])
    #expect(workspace.openedApplications == [applicationURL])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func launchServicesLauncherRejectsAnUnavailableRupaApplication() async throws {
    let workspace = ProjectApplicationWorkspaceOpeningProbe(
        applicationURL: nil
    )
    let launcher = LaunchServicesProjectApplicationLauncher(
        applicationBundleIdentifier: "team.stamp.Rupa",
        workspace: workspace
    )

    do {
        try await launcher.launch(
            projectURL: URL(fileURLWithPath: "/tmp/missing-rupa.rupa"),
            deadline: liveDeadline()
        )
        Issue.record("A missing Rupa application must be a typed failure.")
    } catch let error as LiveProjectAccessError {
        #expect(
            error == .applicationUnavailable(
                bundleIdentifier: "team.stamp.Rupa"
            )
        )
    }
    #expect(workspace.openedProjects.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func launchServicesLauncherSurfacesTheLaunchCompletionFailure() async throws {
    let projectURL = URL(fileURLWithPath: "/tmp/launch-failure.rupa")
    let workspace = ProjectApplicationWorkspaceOpeningProbe(
        applicationURL: URL(fileURLWithPath: "/Applications/Rupa.app"),
        openResult: .failed(
            errorDomain: NSCocoaErrorDomain,
            errorCode: 4097,
            message: "LaunchServices rejected the document."
        )
    )
    let launcher = LaunchServicesProjectApplicationLauncher(
        applicationBundleIdentifier: "team.stamp.Rupa",
        workspace: workspace
    )

    do {
        try await launcher.launch(
            projectURL: projectURL,
            deadline: liveDeadline()
        )
        Issue.record("A LaunchServices completion failure must be typed.")
    } catch let error as LiveProjectAccessError {
        #expect(
            error == .applicationLaunchFailed(
                bundleIdentifier: "team.stamp.Rupa",
                projectURL: projectURL,
                errorDomain: NSCocoaErrorDomain,
                errorCode: 4097,
                message: "LaunchServices rejected the document."
            )
        )
    }
    #expect(workspace.openedProjects == [projectURL])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func launchServicesLauncherUsesTheCallerAbsoluteDeadlineWhileAwaitingCompletion() async throws {
    let workspace = ProjectApplicationWorkspaceOpeningProbe(
        applicationURL: URL(fileURLWithPath: "/Applications/Rupa.app"),
        openResult: nil
    )
    let launcher = LaunchServicesProjectApplicationLauncher(
        applicationBundleIdentifier: "team.stamp.Rupa",
        workspace: workspace
    )
    let projectURL = URL(fileURLWithPath: "/tmp/launch-timeout.rupa")
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(50))

    do {
        try await launcher.launch(
            projectURL: projectURL,
            deadline: deadline
        )
        Issue.record("An uncompleted LaunchServices request must reach the caller deadline.")
    } catch let error as ProjectAccessError {
        #expect(error == .deadlineExceeded)
    }
    #expect(workspace.openedProjects == [projectURL])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func launchServicesLauncherCancellationWinsWhileAwaitingCompletion() async throws {
    let workspace = ProjectApplicationWorkspaceOpeningProbe(
        applicationURL: URL(fileURLWithPath: "/Applications/Rupa.app"),
        openResult: nil
    )
    let launcher = LaunchServicesProjectApplicationLauncher(
        applicationBundleIdentifier: "team.stamp.Rupa",
        workspace: workspace
    )
    let projectURL = URL(fileURLWithPath: "/tmp/launch-cancel.rupa")
    let task = Task { @MainActor in
        try await launcher.launch(
            projectURL: projectURL,
            deadline: liveDeadline()
        )
    }
    await Task.yield()
    task.cancel()

    do {
        try await task.value
        Issue.record("Cancelling a pending LaunchServices request must be terminal.")
    } catch is CancellationError {
        // Expected.
    }
    #expect(workspace.openedProjects == [projectURL])
}

@MainActor
private final class LiveAccessRecordingLauncher: LiveProjectApplicationLaunching {
    private(set) var calls: [URL] = []

    func launch(
        projectURL: URL,
        deadline: ContinuousClock.Instant
    ) async throws {
        try checkLiveProjectDeadline(deadline)
        calls.append(projectURL)
    }
}

@MainActor
private final class LiveAccessRecordingTransport: LiveProjectAccessTransport {
    private(set) var requests: [AgentRequest] = []
    private var responses: [AgentResponse]
    private let failure: Error?

    init(
        responses: [AgentResponse],
        failure: Error? = nil
    ) {
        self.responses = responses
        self.failure = failure
    }

    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        try checkLiveProjectDeadline(deadline)
        requests.append(request)
        if let failure {
            throw failure
        }
        guard !responses.isEmpty else {
            throw EditorError(
                code: .agentUnavailable,
                message: "The live test transport has no response fixture."
            )
        }
        return responses.removeFirst()
    }
}

@MainActor
private final class LiveAccessSuspendingTransport: LiveProjectAccessTransport {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var didStart = false
    private(set) var requestCount = 0

    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        try checkLiveProjectDeadline(deadline)
        requestCount += 1
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .capabilities([])
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class ProjectApplicationWorkspaceOpeningProbe:
    ProjectApplicationWorkspaceOpening {
    private let applicationURL: URL?
    private let openResult: ProjectApplicationOpenResult?
    private(set) var requestedBundleIdentifiers: [String] = []
    private(set) var openedProjects: [URL] = []
    private(set) var openedApplications: [URL] = []

    init(
        applicationURL: URL?,
        openResult: ProjectApplicationOpenResult? = .opened
    ) {
        self.applicationURL = applicationURL
        self.openResult = openResult
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return applicationURL
    }

    func open(
        projectURL: URL,
        withApplicationAt applicationURL: URL,
        completionHandler: @escaping @Sendable (ProjectApplicationOpenResult) -> Void
    ) {
        openedProjects.append(projectURL)
        openedApplications.append(applicationURL)
        if let openResult {
            completionHandler(openResult)
        }
    }
}

@MainActor
private func liveSummary(
    id: UUID,
    path: String?,
    dirty: Bool = false
) -> WorkspaceSessionSummary {
    WorkspaceSessionSummary(
        id: id,
        path: path,
        displayName: "Live Project",
        dirty: dirty,
        generation: DocumentGeneration(1),
        workspaceRevision: WorkspaceRevision(1)
    )
}

@MainActor
private func liveDeadline() -> ContinuousClock.Instant {
    ContinuousClock.now.advanced(by: .seconds(2))
}

@MainActor
private func waitForLiveAccessCondition(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw ProjectAccessError.deadlineExceeded
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private func makeLiveAccessTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rupa-live-access-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}

@MainActor
private func removeLiveAccessTemporaryDirectory(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        // The fixture is isolated and cleanup must not hide the test result.
    }
}
