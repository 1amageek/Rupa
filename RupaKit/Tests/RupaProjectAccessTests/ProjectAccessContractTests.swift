import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaProjectAccess
import Testing

@Test
func projectAccessTargetAcceptsOnlyRupaProjectURLs() throws {
    let input = URL(fileURLWithPath: "/tmp/input.rupa")

    #expect(try ProjectAccessTarget.liveProject(input).validated() == .liveProject(input))
    let sessionID = UUID()
    #expect(try ProjectAccessTarget.liveSession(sessionID).validated() == .liveSession(sessionID))

    let unsupported = URL(fileURLWithPath: "/tmp/input.json")
    #expect(throws: ProjectAccessError.unsupportedProjectFormat(unsupported)) {
        try ProjectAccessTarget.liveProject(unsupported).validated()
    }

    let remote = URL(string: "https://example.invalid/project.rupa")!
    #expect(throws: ProjectAccessError.invalidTarget(remote)) {
        try ProjectAccessTarget.liveProject(remote).validated()
    }
}

@Test
func projectAccessSessionRejectsMismatchedRequestIdentity() async throws {
    let sessionID = UUID()
    let otherSessionID = UUID()
    let session = RecordingProjectAccessSession(sessionID: sessionID)

    await #expect(throws: ProjectAccessError.sessionMismatch(
        expected: sessionID,
        actual: otherSessionID
    )) {
        try await session.send(
            .evaluate(sessionID: otherSessionID, expectedGeneration: nil)
        )
    }

    let response = try await session.send(
        .evaluate(sessionID: sessionID, expectedGeneration: nil)
    )
    #expect(response == .status(AgentStatus(running: true, sessionCount: 0)))
}

@Test
func projectAccessSessionAllowsSessionNeutralObservation() async throws {
    let session = RecordingProjectAccessSession(sessionID: UUID())
    let response = try await session.send(.capabilities)
    #expect(response == .status(AgentStatus(running: true, sessionCount: 0)))
}

@Test
func projectAccessSessionSaveIsExplicitAndFinishIsTerminal() async throws {
    let session = RecordingProjectAccessSession(sessionID: UUID())
    let save = try await session.save(expectedGeneration: DocumentGeneration(3))
    #expect(save.generation == DocumentGeneration(3))
    #expect(await session.saveCount() == 1)

    await session.finish()
    #expect(await session.didFinish())
    await #expect(throws: ProjectAccessError.finished) {
        try await session.send(.capabilities)
    }
}

@Test
func projectAccessOpeningReceivesTheCallersMonotonicDeadline() async throws {
    let session = RecordingProjectAccessSession(sessionID: UUID())
    let opener = RecordingProjectAccessOpener(session: session)
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))

    _ = try await opener.open(.liveSession(session.sessionID), deadline: deadline)
    #expect(await opener.recordedDeadline() == deadline)
}

@Test
func projectAccessOutcomeUnknownRetainsRequestIdentity() {
    let requestID = UUID()
    #expect(
        ProjectAccessError.outcomeUnknown(requestID: requestID)
            == .outcomeUnknown(requestID: requestID)
    )
}

private actor RecordingProjectAccessSession: ProjectAccessSession {
    nonisolated let sessionID: UUID
    private var isFinished = false
    private var explicitSaveCount = 0

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        guard !isFinished else {
            throw ProjectAccessError.finished
        }
        try validateSessionIdentity(of: request)
        return .status(AgentStatus(running: true, sessionCount: 0))
    }

    func save(expectedGeneration: DocumentGeneration?) async throws -> SaveResult {
        guard !isFinished else {
            throw ProjectAccessError.finished
        }
        explicitSaveCount += 1
        return SaveResult(
            message: "Saved.",
            path: "/tmp/project.rupa",
            generation: expectedGeneration ?? DocumentGeneration(),
            dirty: false,
            diagnostics: []
        )
    }

    func finish() async {
        isFinished = true
    }

    func saveCount() -> Int {
        explicitSaveCount
    }

    func didFinish() -> Bool {
        isFinished
    }
}

private actor RecordingProjectAccessOpener: ProjectAccessOpening {
    private let session: RecordingProjectAccessSession
    private var deadline: ContinuousClock.Instant?

    init(session: RecordingProjectAccessSession) {
        self.session = session
    }

    func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        _ = try target.validated()
        self.deadline = deadline
        return session
    }

    func recordedDeadline() -> ContinuousClock.Instant? {
        deadline
    }
}
