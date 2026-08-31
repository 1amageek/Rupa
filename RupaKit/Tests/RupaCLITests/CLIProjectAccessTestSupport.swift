import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaCLIKit
import RupaProjectAccess

enum StubProjectAccessStep: Sendable {
    case response(AgentResponse)
    case error(ProjectAccessError)
}

actor StubProjectAccessSession: ProjectAccessSession {
    nonisolated let sessionID: UUID

    private var steps: [StubProjectAccessStep]
    private var requests: [AgentRequest] = []
    private var saveGenerations: [DocumentGeneration?] = []
    private var finishCount = 0
    private let saveError: ProjectAccessError?

    init(
        sessionID: UUID = UUID(),
        steps: [StubProjectAccessStep],
        saveError: ProjectAccessError? = nil
    ) {
        self.sessionID = sessionID
        self.steps = steps
        self.saveError = saveError
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        try validateSessionIdentity(of: request)
        requests.append(request)
        guard !steps.isEmpty else {
            throw ProjectAccessError.authorityUnavailable
        }

        switch steps.removeFirst() {
        case .response(let response):
            return response
        case .error(let error):
            throw error
        }
    }

    func save(expectedGeneration: DocumentGeneration?) async throws -> SaveResult {
        saveGenerations.append(expectedGeneration)
        if let saveError {
            throw saveError
        }
        return SaveResult(
            message: "Saved.",
            path: "/tmp/stub.rupa",
            generation: expectedGeneration ?? DocumentGeneration(),
            dirty: false,
            diagnostics: []
        )
    }

    func finish() async {
        finishCount += 1
    }

    func recordedRequests() -> [AgentRequest] {
        requests
    }

    func recordedSaveGenerations() -> [DocumentGeneration?] {
        saveGenerations
    }

    func recordedFinishCount() -> Int {
        finishCount
    }
}

actor StubProjectAccessOpener: ProjectAccessOpening {
    private let session: any ProjectAccessSession
    private let error: ProjectAccessError?
    private let openDelay: Duration?
    private var targets: [ProjectAccessTarget] = []
    private var deadlines: [ContinuousClock.Instant] = []

    init(
        session: any ProjectAccessSession,
        error: ProjectAccessError? = nil,
        openDelay: Duration? = nil
    ) {
        self.session = session
        self.error = error
        self.openDelay = openDelay
    }

    func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        targets.append(target)
        deadlines.append(deadline)
        if let openDelay {
            try await Task.sleep(for: openDelay)
        }
        if let error {
            throw error
        }
        return session
    }

    func recordedTargets() -> [ProjectAccessTarget] {
        targets
    }

    func recordedDeadlines() -> [ContinuousClock.Instant] {
        deadlines
    }
}

@MainActor
final class StubProjectAccessObserver: ProjectAccessObserving {
    private(set) var capabilitiesCallCount = 0
    private(set) var capabilitiesDeadlines: [ContinuousClock.Instant] = []
    private(set) var statusCallCount = 0
    private(set) var sessionsCallCount = 0
    private(set) var statusDeadlines: [ContinuousClock.Instant] = []
    private(set) var sessionsDeadlines: [ContinuousClock.Instant] = []

    var capabilitiesResult: [AgentCapabilityDescriptor] = []
    var statusResult: AgentStatus
    var sessionsResult: [WorkspaceSessionSummary]
    var error: ProjectAccessError?

    init(
        status: AgentStatus = AgentStatus(running: true, sessionCount: 0),
        sessions: [WorkspaceSessionSummary] = [],
        error: ProjectAccessError? = nil
    ) {
        self.statusResult = status
        self.sessionsResult = sessions
        self.error = error
    }

    func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor] {
        capabilitiesCallCount += 1
        capabilitiesDeadlines.append(deadline)
        if let error {
            throw error
        }
        return capabilitiesResult
    }

    func status(deadline: ContinuousClock.Instant) async throws -> AgentStatus {
        statusCallCount += 1
        statusDeadlines.append(deadline)
        if let error {
            throw error
        }
        return statusResult
    }

    func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        sessionsCallCount += 1
        sessionsDeadlines.append(deadline)
        if let error {
            throw error
        }
        return sessionsResult
    }
}

func withStubProjectAccess<Result>(
    opener: any ProjectAccessOpening,
    observer: any ProjectAccessObserving,
    operation: () async throws -> Result
) async rethrows -> Result {
    try await CLIProjectAccessContext.$current.withValue(
        CLIProjectAccessDependencies(opener: opener, observer: observer)
    ) {
        try await operation()
    }
}

func makeStubProjectAccessObserver(
    status: AgentStatus = AgentStatus(running: true, sessionCount: 0),
    sessions: [WorkspaceSessionSummary] = [],
    error: ProjectAccessError? = nil
) async -> StubProjectAccessObserver {
    await MainActor.run {
        StubProjectAccessObserver(
            status: status,
            sessions: sessions,
            error: error
        )
    }
}

func stubAutomationResult(
    message: String = "Completed.",
    effect: AutomationCommandEffect = .sourceMutation,
    generation: DocumentGeneration = DocumentGeneration(1),
    sourceDirty: Bool = true,
    workspaceRevision: WorkspaceRevision = WorkspaceRevision(1),
    didMutate: Bool = true,
    workspaceScale: WorkspaceScaleSnapshot? = nil
) -> AutomationResult {
    AutomationResult(
        message: message,
        effect: effect,
        generation: generation,
        sourceDirty: sourceDirty,
        workspaceRevision: workspaceRevision,
        didMutate: didMutate,
        workspaceScale: workspaceScale
    )
}

func stubWorkspaceScale(
    displayUnit: LengthDisplayUnit = .millimeter
) -> WorkspaceScaleSnapshot {
    WorkspaceScaleSnapshot(
        displayUnit: displayUnit,
        displayUnitSymbol: displayUnit.symbol,
        minorTickMeters: 0.001,
        majorTickMeters: 0.01,
        visibleSpanMeters: 1,
        matchedPreset: nil,
        matchedPresetTitle: nil
    )
}
