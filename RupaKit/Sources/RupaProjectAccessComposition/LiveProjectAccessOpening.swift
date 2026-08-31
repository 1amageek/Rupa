import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaCoreTypes
import RupaProjectAccess
import RupaProjectAccessPlatform

/// Opens an existing App-owned session or launches the App for one project URL.
@MainActor
public final class LiveProjectAccessOpening: ProjectAccessOpening, ProjectAccessObserving {
    private let discoveryReader: (any AgentDiscoveryRecordReading)?
    private let launcher: any LiveProjectApplicationLaunching
    private let requestTimeout: Duration
    private let resolverOverride: LiveProjectSessionResolver?
    private let transportOverride: (any LiveProjectAccessTransport)?
    private let transportFactory: @MainActor (
        AgentDiscoveryRecord,
        Duration
    ) throws -> any LiveProjectAccessTransport

    public init(
        discoveryReader: any AgentDiscoveryRecordReading,
        launcher: any LiveProjectApplicationLaunching,
        requestTimeout: Duration = .seconds(30)
    ) {
        self.discoveryReader = discoveryReader
        self.launcher = launcher
        self.requestTimeout = requestTimeout
        self.resolverOverride = nil
        self.transportOverride = nil
        self.transportFactory = { record, requestTimeout in
            try LiveProjectAgentClient(
                record: record,
                requestTimeout: requestTimeout
            )
        }
    }

    init(
        discoveryReader: any AgentDiscoveryRecordReading,
        launcher: any LiveProjectApplicationLaunching,
        requestTimeout: Duration = .seconds(30),
        transportFactory: @escaping @MainActor (
            AgentDiscoveryRecord,
            Duration
        ) throws -> any LiveProjectAccessTransport
    ) {
        self.discoveryReader = discoveryReader
        self.launcher = launcher
        self.requestTimeout = requestTimeout
        self.resolverOverride = nil
        self.transportOverride = nil
        self.transportFactory = transportFactory
    }

    init(
        launcher: any LiveProjectApplicationLaunching,
        resolver: LiveProjectSessionResolver,
        transport: any LiveProjectAccessTransport
    ) {
        self.discoveryReader = nil
        self.launcher = launcher
        self.requestTimeout = .seconds(30)
        self.resolverOverride = resolver
        self.transportOverride = transport
        self.transportFactory = { _, _ in transport }
    }

    public func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        try checkLiveProjectDeadline(deadline)
        let validatedTarget = try target.validated()

        if case .liveProject(let projectURL) = validatedTarget {
            try await launcher.launch(
                projectURL: canonicalLiveProjectURL(projectURL),
                deadline: deadline
            )
            try checkLiveProjectDeadline(deadline)
        }

        let connection: LiveConnection
        let initialSummaries: [WorkspaceSessionSummary]?
        switch validatedTarget {
        case .liveProject:
            let ready = try await makeReadyConnection(deadline: deadline)
            connection = ready.connection
            initialSummaries = ready.sessions
        case .liveSession:
            connection = try await makeConnection(
                waitingForAvailability: false,
                deadline: deadline
            )
            initialSummaries = nil
        }
        let resolver = connection.resolver

        let summary: WorkspaceSessionSummary
        switch validatedTarget {
        case .liveProject(let projectURL):
            let canonicalURL = canonicalLiveProjectURL(projectURL)
            guard let initialSummaries else {
                throw ProjectAccessError.authorityUnavailable
            }
            var exactMatches: [WorkspaceSessionSummary] = []
            for summary in initialSummaries where
                try canonicalLiveSessionPath(summary.path) == canonicalURL {
                exactMatches.append(summary)
            }
            if exactMatches.count > 1 {
                throw LiveProjectAccessError.multipleMatchingSessions(canonicalURL)
            }
            if let exactMatch = exactMatches.first {
                summary = exactMatch
            } else {
                if initialSummaries.contains(where: { $0.dirty }) {
                    throw LiveProjectAccessError.dirtyProjectConflict(canonicalURL)
                }
                summary = try await resolver.resolve(
                    projectURL: canonicalURL,
                    deadline: deadline
                )
            }
        case .liveSession(let sessionID):
            summary = try await resolver.resolve(
                sessionID: sessionID,
                deadline: deadline
            )
        }

        try checkLiveProjectDeadline(deadline)
        return LiveProjectAccessSession(
            sessionID: summary.id,
            transport: connection.transport,
            deadline: deadline
        )
    }

    public func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus {
        let resolver = try await makeConnection(
            waitingForAvailability: false,
            deadline: deadline
        ).resolver
        return try await resolver.status(deadline: deadline)
    }

    public func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor] {
        let resolver = try await makeConnection(
            waitingForAvailability: false,
            deadline: deadline
        ).resolver
        return try await resolver.capabilities(deadline: deadline)
    }

    public func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        let resolver = try await makeConnection(
            waitingForAvailability: false,
            deadline: deadline
        ).resolver
        return try await resolver.sessions(deadline: deadline)
    }

    private func makeConnection(
        waitingForAvailability: Bool,
        excludingGenerations: Set<UInt64> = [],
        deadline: ContinuousClock.Instant
    ) async throws -> LiveConnection {
        if let resolverOverride, let transportOverride {
            return LiveConnection(
                resolver: resolverOverride,
                transport: transportOverride
            )
        }
        guard resolverOverride == nil, transportOverride == nil,
              let discoveryReader else {
            throw ProjectAccessError.authorityUnavailable
        }
        let record = try await LiveAgentDiscoveryRecordResolver(
            reader: discoveryReader
        ).resolve(
            waitingForAvailability: waitingForAvailability,
            excludingGenerations: excludingGenerations,
            deadline: deadline
        )
        let transport = try transportFactory(record, requestTimeout)
        return LiveConnection(
            resolver: LiveProjectSessionResolver(transport: transport),
            transport: transport,
            discoveryGeneration: record.generation
        )
    }

    private func makeReadyConnection(
        deadline: ContinuousClock.Instant
    ) async throws -> (
        connection: LiveConnection,
        sessions: [WorkspaceSessionSummary]
    ) {
        var rejectedGenerations: Set<UInt64> = []
        while true {
            let connection = try await makeConnection(
                waitingForAvailability: true,
                excludingGenerations: rejectedGenerations,
                deadline: deadline
            )
            let readinessResolver = LiveProjectSessionResolver(
                transport: LiveProjectReadinessAttemptTransport(
                    transport: connection.transport
                )
            )
            do {
                return (
                    connection,
                    try await readinessResolver.sessions(deadline: deadline)
                )
            } catch let failure as LiveProjectReadinessConnectionFailure {
                guard let generation = connection.discoveryGeneration else {
                    throw mapLiveProjectTransportError(failure.transportFailure)
                }
                rejectedGenerations.insert(generation)
                try checkLiveProjectDeadline(deadline)
            }
        }
    }

    private struct LiveConnection {
        let resolver: LiveProjectSessionResolver
        let transport: any LiveProjectAccessTransport
        let discoveryGeneration: UInt64?

        init(
            resolver: LiveProjectSessionResolver,
            transport: any LiveProjectAccessTransport,
            discoveryGeneration: UInt64? = nil
        ) {
            self.resolver = resolver
            self.transport = transport
            self.discoveryGeneration = discoveryGeneration
        }
    }
}

private struct LiveProjectReadinessConnectionFailure: Error {
    let transportFailure: AgentTransportFailure
}

@MainActor
private final class LiveProjectReadinessAttemptTransport:
    LiveProjectAccessTransport {
    private let transport: any LiveProjectAccessTransport

    init(transport: any LiveProjectAccessTransport) {
        self.transport = transport
    }

    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        do {
            return try await transport.send(request, deadline: deadline)
        } catch let failure as AgentTransportFailure {
            guard case .notDispatched = failure.disposition,
                  case .transport(let editorError) = failure.cause,
                  editorError.code == .agentConnectionFailed else {
                throw failure
            }
            throw LiveProjectReadinessConnectionFailure(
                transportFailure: failure
            )
        }
    }
}
