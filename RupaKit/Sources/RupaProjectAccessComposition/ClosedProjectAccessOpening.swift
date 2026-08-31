import Foundation
import RupaAgentRuntime
import RupaKit
import RupaProjectAccess

/// Composes closed `.rupa` access through a temporary ProjectWorkspace.
@MainActor
public final class ClosedProjectAccessOpening: ProjectAccessOpening {
    private let leaseStore: ProjectFileAuthorityLeaseStore
    private let workspaceMaker: any ProjectWorkspaceMaking
    private let afterRegistration: @MainActor @Sendable () async throws -> Void

    public init(
        leaseStore: ProjectFileAuthorityLeaseStore,
        workspaceFactory: DefaultProjectWorkspaceFactory = DefaultProjectWorkspaceFactory()
    ) {
        self.leaseStore = leaseStore
        self.workspaceMaker = DefaultProjectWorkspaceMaker(factory: workspaceFactory)
        self.afterRegistration = {}
    }

    public init(
        leaseStore: ProjectFileAuthorityLeaseStore,
        workspaceMaker: any ProjectWorkspaceMaking
    ) {
        self.leaseStore = leaseStore
        self.workspaceMaker = workspaceMaker
        self.afterRegistration = {}
    }

    /// Internal registration boundary used to deterministically exercise
    /// cancellation and deadline cleanup in the composition tests.
    init(
        leaseStore: ProjectFileAuthorityLeaseStore,
        workspaceMaker: any ProjectWorkspaceMaking,
        afterRegistration: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        self.leaseStore = leaseStore
        self.workspaceMaker = workspaceMaker
        self.afterRegistration = afterRegistration
    }

    public func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw ProjectAccessError.deadlineExceeded
        }
        let validatedTarget = try target.validated()
        guard case .closedProject(let input, let output) = validatedTarget else {
            throw ProjectAccessError.authorityUnavailable
        }

        let canonicalInput = try canonicalInputURL(input)
        let canonicalOutput = try canonicalOutputURL(output)
        let leasePaths = [canonicalInput] + (canonicalOutput.map { [$0] } ?? [])
        let lease = try await leaseStore.acquire(
            paths: leasePaths,
            requiredPaths: [canonicalInput],
            deadline: deadline
        )

        let handler = ProjectAgentCommandController()
        var registeredSessionID: UUID?
        do {
            // Validate immediately before the URL-based workspace load. The
            // lease retains the original descriptor, but ProjectWorkspace's
            // public load contract accepts a URL, so a raced inode replacement
            // must be rejected before that boundary and again after I/O.
            try await lease.validate()
            let workspace = try workspaceMaker.makeWorkspace()
            _ = try await workspace.load(
                from: canonicalInput,
                operationGuard: {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else {
                        throw ProjectAccessError.deadlineExceeded
                    }
                }
            )
            try await lease.validate()
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw ProjectAccessError.deadlineExceeded
            }
            let sessionID = UUID()
            try await handler.register(
                workspace: workspace,
                path: canonicalInput,
                id: sessionID
            )
            registeredSessionID = sessionID
            try await afterRegistration()
            // Registration suspends through the runtime registry. Recheck
            // cancellation and the single opening deadline after it returns;
            // a caller must never receive a session whose lifetime already
            // exceeded the opening contract.
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw ProjectAccessError.deadlineExceeded
            }
            return ClosedProjectAccessSession(
                sessionID: sessionID,
                workspace: workspace,
                handler: handler,
                lease: lease,
                inputURL: canonicalInput,
                outputURL: canonicalOutput,
                deadline: deadline
            )
        } catch {
            if let registeredSessionID {
                await handler.unregister(id: registeredSessionID)
            }
            await lease.release()
            throw error
        }
    }

    private func canonicalInputURL(_ url: URL) throws -> URL {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: canonical.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw ProjectAccessError.invalidTarget(url)
        }
        guard isRegularFile(at: canonical) else {
            throw ProjectAccessError.invalidTarget(url)
        }
        return canonical
    }

    private func canonicalOutputURL(_ url: URL?) throws -> URL? {
        guard let url else {
            return nil
        }
        let standardized = url.standardizedFileURL
        let parent = standardized
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: parent.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ProjectAccessError.invalidTarget(url)
        }
        let canonical = parent
            .appendingPathComponent(standardized.lastPathComponent)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: canonical.path) {
            guard isRegularFile(at: canonical) else {
                throw ProjectAccessError.invalidTarget(url)
            }
        }
        return canonical
    }

    private func isRegularFile(at url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        } catch {
            return false
        }
    }
}
