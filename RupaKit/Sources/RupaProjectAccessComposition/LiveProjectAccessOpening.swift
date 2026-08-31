import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaProjectAccess

/// Opens an existing App-owned session or launches the App for one project URL.
@MainActor
public final class LiveProjectAccessOpening: ProjectAccessOpening, LiveProjectAccessObserving {
    private let endpoint: UnixSocketEndpoint?
    private let launcher: any LiveProjectApplicationLaunching
    private let requestTimeout: Duration
    private let resolverOverride: LiveProjectSessionResolver?
    private let transportOverride: (any LiveProjectAccessTransport)?

    public init(
        endpoint: UnixSocketEndpoint,
        launcher: any LiveProjectApplicationLaunching,
        requestTimeout: Duration = .seconds(30)
    ) {
        self.endpoint = endpoint
        self.launcher = launcher
        self.requestTimeout = requestTimeout
        self.resolverOverride = nil
        self.transportOverride = nil
    }

    init(
        launcher: any LiveProjectApplicationLaunching,
        resolver: LiveProjectSessionResolver,
        transport: any LiveProjectAccessTransport
    ) {
        self.endpoint = nil
        self.launcher = launcher
        self.requestTimeout = .seconds(30)
        self.resolverOverride = resolver
        self.transportOverride = transport
    }

    public func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        try checkLiveProjectDeadline(deadline)
        let validatedTarget = try target.validated()
        let resolver = try makeResolver()

        let summary: WorkspaceSessionSummary
        switch validatedTarget {
        case .liveProject(let projectURL):
            let canonicalURL = canonicalLiveProjectURL(projectURL)
            // The application coordinator owns the open decision. It treats a
            // request for its current canonical URL as a no-op only after the
            // retained file authority validates; this adapter sends exactly
            // one open event and waits on the same outer deadline.
            try await launcher.launch(
                projectURL: canonicalURL,
                deadline: deadline
            )
            try checkLiveProjectDeadline(deadline)
            let initialSummaries = try await resolver.sessions(deadline: deadline)
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
        case .closedProject:
            throw ProjectAccessError.authorityUnavailable
        }

        try checkLiveProjectDeadline(deadline)
        if let transportOverride {
            return LiveProjectAccessSession(
                sessionID: summary.id,
                transport: transportOverride,
                deadline: deadline
            )
        }
        guard let endpoint else {
            throw ProjectAccessError.authorityUnavailable
        }
        return LiveProjectAccessSession(
            sessionID: summary.id,
            endpoint: endpoint,
            deadline: deadline,
            requestTimeout: requestTimeout
        )
    }

    public func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus {
        let resolver = try makeResolver()
        return try await resolver.status(deadline: deadline)
    }

    public func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        let resolver = try makeResolver()
        return try await resolver.sessions(deadline: deadline)
    }

    private func makeResolver() throws -> LiveProjectSessionResolver {
        if let resolverOverride {
            return resolverOverride
        }
        guard let endpoint else {
            throw ProjectAccessError.authorityUnavailable
        }
        return LiveProjectSessionResolver(
            endpoint: endpoint,
            requestTimeout: requestTimeout
        )
    }
}
