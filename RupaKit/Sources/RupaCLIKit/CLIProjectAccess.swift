import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore
import RupaProjectAccess

public struct CLIProjectAccessDependencies: Sendable {
    public let opener: any ProjectAccessOpening
    public let observer: any ProjectAccessObserving

    public init(
        opener: any ProjectAccessOpening,
        observer: any ProjectAccessObserving
    ) {
        self.opener = opener
        self.observer = observer
    }
}

public enum CLIProjectAccessContext {
    @TaskLocal public static var current: CLIProjectAccessDependencies?
}

public enum CLIEditMode: String, Codable, Equatable, Sendable, CaseIterable {
    case live
    case file
}

public struct CLIDocumentTarget: Equatable, Sendable {
    public var fileURL: URL?
    public var sessionID: UUID?

    public init(
        fileURL: URL? = nil,
        sessionID: UUID? = nil
    ) {
        self.fileURL = fileURL
        self.sessionID = sessionID
    }
}

public enum CLIDocumentWritePolicy: Equatable, Sendable {
    case inPlace
    case output(URL)

    var outputURL: URL? {
        switch self {
        case .inPlace:
            nil
        case .output(let url):
            url
        }
    }
}

enum CLIProjectAccessRunner {
    private static let accessTimeout = Duration.seconds(30)
    @TaskLocal private static var commandScope: CLIProjectAccessCommandScope?

    static func withCommandScope<Result>(
        _ operation: () async throws -> Result
    ) async throws -> Result {
        if commandScope != nil {
            return try await operation()
        }
        let scope = CLIProjectAccessCommandScope(
            deadline: ContinuousClock.now.advanced(by: accessTimeout)
        )
        do {
            let result = try await $commandScope.withValue(scope) {
                try await operation()
            }
            await scope.finish()
            return result
        } catch {
            await scope.finish()
            throw error
        }
    }

    static func withSession<Result>(
        target: CLIDocumentTarget,
        mode: CLIEditMode,
        outputURL: URL? = nil,
        _ operation: (any ProjectAccessSession) async throws -> Result
    ) async throws -> Result {
        let dependencies = try dependencies()
        let accessTarget = try projectAccessTarget(
            target: target,
            mode: mode,
            outputURL: outputURL
        )
        if let commandScope {
            let session = try await commandScope.session(
                target: accessTarget,
                opener: dependencies.opener,
                deadline: commandScope.deadline
            )
            return try await operation(session)
        }
        let deadline = ContinuousClock.now.advanced(by: accessTimeout)
        let session = try await dependencies.opener.open(
            accessTarget,
            deadline: deadline
        )

        do {
            let result = try await operation(session)
            await session.finish()
            return result
        } catch {
            await session.finish()
            throw error
        }
    }

    @MainActor
    static func capabilities() async throws -> [AgentCapabilityDescriptor] {
        try await dependencies().observer.capabilities(
            deadline: commandScope?.deadline
                ?? ContinuousClock.now.advanced(by: accessTimeout)
        )
    }

    @MainActor
    static func status() async throws -> AgentStatus {
        try await dependencies().observer.status(
            deadline: commandScope?.deadline
                ?? ContinuousClock.now.advanced(by: accessTimeout)
        )
    }

    @MainActor
    static func sessions() async throws -> [WorkspaceSessionSummary] {
        try await dependencies().observer.sessions(
            deadline: commandScope?.deadline
                ?? ContinuousClock.now.advanced(by: accessTimeout)
        )
    }

    static func projectAccessTarget(
        target: CLIDocumentTarget,
        mode: CLIEditMode,
        outputURL: URL?
    ) throws -> ProjectAccessTarget {
        switch mode {
        case .live:
            guard outputURL == nil else {
                throw ValidationError("--output can only be used with --mode file.")
            }
            guard !(target.fileURL != nil && target.sessionID != nil) else {
                throw ValidationError("Live access accepts either a project path or --session-id, not both.")
            }
            if let sessionID = target.sessionID {
                return .liveSession(sessionID)
            }
            guard let fileURL = target.fileURL else {
                throw ValidationError("Live access requires a .rupa project path or --session-id.")
            }
            return try ProjectAccessTarget.liveProject(fileURL).validated()

        case .file:
            guard target.sessionID == nil else {
                throw ValidationError("File access cannot be combined with --session-id.")
            }
            guard let fileURL = target.fileURL else {
                throw ValidationError("File access requires a .rupa project path.")
            }
            return try ProjectAccessTarget.closedProject(
                input: fileURL,
                output: outputURL
            ).validated()
        }
    }

    private static func dependencies() throws -> CLIProjectAccessDependencies {
        guard let dependencies = CLIProjectAccessContext.current else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Rupa project access was not configured for this command."
            )
        }
        return dependencies
    }
}

private actor CLIProjectAccessCommandScope {
    nonisolated let deadline: ContinuousClock.Instant
    private var openedTarget: ProjectAccessTarget?
    private var openingTask: Task<any ProjectAccessSession, Error>?
    private var openedSession: (any ProjectAccessSession)?

    init(deadline: ContinuousClock.Instant) {
        self.deadline = deadline
    }

    func session(
        target: ProjectAccessTarget,
        opener: any ProjectAccessOpening,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        if let openedTarget, let openedSession {
            guard openedTarget == target else {
                throw ValidationError(
                    "One CLI command cannot open more than one project access target."
                )
            }
            return openedSession
        }
        if let openedTarget {
            guard openedTarget == target else {
                throw ValidationError(
                    "One CLI command cannot open more than one project access target."
                )
            }
        } else {
            openedTarget = target
            openingTask = Task {
                try await opener.open(target, deadline: deadline)
            }
        }
        guard let openingTask else {
            throw ProjectAccessError.authorityUnavailable
        }
        let session = try await withTaskCancellationHandler {
            try await openingTask.value
        } onCancel: {
            openingTask.cancel()
        }
        if let openedSession {
            return openedSession
        }
        openedSession = session
        return session
    }

    func finish() async {
        let session: (any ProjectAccessSession)?
        if let openedSession {
            session = openedSession
        } else if let openingTask {
            do {
                session = try await openingTask.value
            } catch {
                self.openingTask = nil
                openedTarget = nil
                return
            }
        } else {
            return
        }
        openingTask = nil
        self.openedSession = nil
        openedTarget = nil
        await session?.finish()
    }
}
