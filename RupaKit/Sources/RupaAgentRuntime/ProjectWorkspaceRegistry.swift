import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaKit
import RupaProject
import Synchronization

final class ProjectWorkspaceRegistrationToken: Sendable {
    private struct State {
        var acceptsOperations = true
        var activeOperationIDs: Set<UUID> = []
        var invalidationWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func acquireOperation() throws -> ProjectWorkspaceRegistrationOperation {
        let operationID = UUID()
        let accepted = state.withLock { state in
            guard state.acceptsOperations else {
                return false
            }
            state.activeOperationIDs.insert(operationID)
            return true
        }
        guard accepted else {
            throw inactiveRegistrationError()
        }
        return ProjectWorkspaceRegistrationOperation(
            id: operationID,
            token: self
        )
    }

    func validate() throws {
        let registered = state.withLock { $0.acceptsOperations }
        guard registered else {
            throw inactiveRegistrationError()
        }
    }

    func validate(operationID: UUID) throws {
        let active = state.withLock { state in
            state.activeOperationIDs.contains(operationID)
        }
        guard active else {
            throw inactiveRegistrationError()
        }
    }

    func invalidateWhenInactive() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                state.acceptsOperations = false
                guard !state.activeOperationIDs.isEmpty else {
                    return true
                }
                state.invalidationWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    fileprivate func finish(operationID: UUID) {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.activeOperationIDs.remove(operationID)
            guard state.activeOperationIDs.isEmpty,
                  !state.acceptsOperations else {
                return []
            }
            defer { state.invalidationWaiters.removeAll(keepingCapacity: false) }
            return state.invalidationWaiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func inactiveRegistrationError() -> EditorError {
        EditorError(
            code: .sessionNotFound,
            message: "The project session registration is no longer active."
        )
    }
}

final class ProjectWorkspaceRegistrationOperation: Sendable {
    let id: UUID
    private let token: ProjectWorkspaceRegistrationToken
    private let isFinished = Mutex(false)

    init(id: UUID, token: ProjectWorkspaceRegistrationToken) {
        self.id = id
        self.token = token
    }

    deinit {
        finish()
    }

    func validate() throws {
        try token.validate(operationID: id)
    }

    func finish() {
        let shouldFinish = isFinished.withLock { finished in
            guard !finished else {
                return false
            }
            finished = true
            return true
        }
        if shouldFinish {
            token.finish(operationID: id)
        }
    }
}

struct ProjectWorkspaceRegistrationLease {
    let id: UUID
    let workspace: ProjectWorkspace
    let path: URL?
    let token: ProjectWorkspaceRegistrationToken
    let operation: ProjectWorkspaceRegistrationOperation

    var operationGuard: ProjectOperationGuard {
        let operation = operation
        return {
            try operation.validate()
        }
    }

    func validate() throws {
        try operation.validate()
    }

    func summary(view: ProjectViewSnapshot) -> WorkspaceSessionSummary {
        WorkspaceSessionSummary(
            id: id,
            path: path?.path,
            displayName: view.projectName,
            dirty: view.isDirty,
            generation: view.documentGeneration,
            workspaceRevision: view.workspaceState.revision
        )
    }
}

/// Retains shared project workspaces without copying their source state.
@MainActor
public final class ProjectWorkspaceRegistry {
    private struct Entry {
        let workspace: ProjectWorkspace
        var path: URL?
        let token: ProjectWorkspaceRegistrationToken
        var registeredProjectID: ProjectID
    }

    private var entries: [UUID: Entry] = [:]

    public init() {}

    @discardableResult
    public func register(
        workspace: ProjectWorkspace,
        path: URL? = nil,
        id: UUID = UUID()
    ) async throws -> UUID {
        for existingID in Array(entries.keys) {
            _ = try await reconciledEntry(id: existingID)
        }
        guard let view = workspace.view else {
            throw EditorError(
                code: .agentUnavailable,
                message: "A project must publish its initial view before Agent registration."
            )
        }
        let validatedProjectID = try await workspace.withValidatedAuthority(from: view) {
            view.projectID
        }
        guard entries[id] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Project session \(id.uuidString) is already registered."
            )
        }
        if let existingID = entries.first(where: { _, entry in
            entry.workspace.view?.projectID == validatedProjectID
        })?.key {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Project \(validatedProjectID.rawValue) is already registered as session \(existingID.uuidString)."
            )
        }
        let normalizedPath = path?.standardizedFileURL
        if let normalizedPath,
           let existingID = registeredSessionID(for: normalizedPath) {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Project \(normalizedPath.path) is already registered as session \(existingID.uuidString)."
            )
        }
        entries[id] = Entry(
            workspace: workspace,
            path: normalizedPath,
            token: ProjectWorkspaceRegistrationToken(),
            registeredProjectID: validatedProjectID
        )
        return id
    }

    public func unregister(id: UUID) async {
        guard let entry = entries[id] else {
            return
        }
        await entry.token.invalidateWhenInactive()
        if entries[id]?.token === entry.token {
            entries.removeValue(forKey: id)
        }
    }

    public func updatePath(id: UUID, path: URL?) async throws {
        var entry = try await reconciledEntry(id: id)
        let operation = try entry.token.acquireOperation()
        defer { operation.finish() }
        try operation.validate()

        let normalizedPath = path?.standardizedFileURL
        if let normalizedPath,
           let existingID = registeredSessionID(for: normalizedPath),
           existingID != id {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Project \(normalizedPath.path) is already registered as session \(existingID.uuidString)."
            )
        }
        guard let retained = entries[id], retained.token === entry.token else {
            throw EditorError(
                code: .sessionNotFound,
                message: "Project session \(id.uuidString) was unregistered before its path could be updated."
            )
        }
        entry.path = normalizedPath
        entries[id] = entry
    }

    func lease(id: UUID) async throws -> ProjectWorkspaceRegistrationLease {
        let entry = try await reconciledEntry(id: id)
        let operation = try entry.token.acquireOperation()
        return ProjectWorkspaceRegistrationLease(
            id: id,
            workspace: entry.workspace,
            path: entry.path,
            token: entry.token,
            operation: operation
        )
    }

    func recoveryLease(
        id: UUID,
        committedProjectID: ProjectID
    ) throws -> ProjectWorkspaceRegistrationLease {
        guard let entry = entries[id] else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No registered project session exists for \(id.uuidString)."
            )
        }
        guard entry.registeredProjectID == committedProjectID else {
            throw ProjectControllerError(
                code: .projectMismatch,
                message: "Committed view recovery does not match the registered project identity."
            )
        }
        let operation = try entry.token.acquireOperation()
        return ProjectWorkspaceRegistrationLease(
            id: id,
            workspace: entry.workspace,
            path: entry.path,
            token: entry.token,
            operation: operation
        )
    }

    public func summary(id: UUID) async throws -> WorkspaceSessionSummary {
        let lease = try await lease(id: id)
        guard let view = lease.workspace.view else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Registered project session \(id.uuidString) has no published view."
            )
        }
        let summary = lease.summary(view: view)
        return try await lease.workspace.withValidatedAuthority(
            from: view,
            operationGuard: lease.operationGuard
        ) {
            summary
        }
    }

    public func summaries() async throws -> [WorkspaceSessionSummary] {
        var summaries: [WorkspaceSessionSummary] = []
        for id in entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            summaries.append(try await summary(id: id))
        }
        return summaries.sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func reconciledCount() async throws -> Int {
        for id in Array(entries.keys) {
            _ = try await reconciledEntry(id: id)
        }
        return entries.count
    }

    public func registeredSessionID(for url: URL) -> UUID? {
        let normalizedPath = url.standardizedFileURL.path
        return entries.first { _, entry in
            entry.path?.standardizedFileURL.path == normalizedPath
        }?.key
    }

    private func reconciledEntry(id: UUID) async throws -> Entry {
        let validated = try await validatedIdentity(id: id)
        var entry = validated.entry
        let currentProjectID = validated.projectID
        guard currentProjectID != entry.registeredProjectID else {
            return entry
        }
        for candidateID in entries.keys where candidateID != id {
            let candidate = try await validatedIdentity(id: candidateID)
            guard candidate.projectID != currentProjectID else {
                throw EditorError(
                    code: .documentOpenInApp,
                    message: "Project \(currentProjectID.rawValue) is already registered as session \(candidateID.uuidString)."
                )
            }
        }
        guard let currentView = entry.workspace.view,
              Self.hasSameCoordinates(currentView, validated.view) else {
            throw ProjectControllerError(
                code: .publicationConflict,
                message: "The project session view changed while its registration identity was being reconciled."
            )
        }
        entry.registeredProjectID = currentProjectID
        entries[id] = entry
        return entry
    }

    private func validatedIdentity(id: UUID) async throws -> (
        entry: Entry,
        view: ProjectViewSnapshot,
        projectID: ProjectID
    ) {
        guard let entry = entries[id] else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No registered project session exists for \(id.uuidString)."
            )
        }
        try entry.token.validate()
        guard let view = entry.workspace.view else {
            throw EditorError(
                code: .agentUnavailable,
                message: "Registered project session \(id.uuidString) has no published view."
            )
        }
        let projectID = try await entry.workspace.withValidatedAuthority(
            from: view,
            operationGuard: {
                try entry.token.validate()
            }
        ) {
            view.projectID
        }
        guard let retained = entries[id], retained.token === entry.token else {
            throw EditorError(
                code: .sessionNotFound,
                message: "Project session \(id.uuidString) was unregistered during identity validation."
            )
        }
        guard let currentView = retained.workspace.view,
              Self.hasSameCoordinates(currentView, view) else {
            throw ProjectControllerError(
                code: .publicationConflict,
                message: "The project session view changed during identity validation."
            )
        }
        return (retained, view, projectID)
    }

    private static func hasSameCoordinates(
        _ lhs: ProjectViewSnapshot,
        _ rhs: ProjectViewSnapshot
    ) -> Bool {
        lhs.projectID == rhs.projectID
            && lhs.documentGeneration == rhs.documentGeneration
            && lhs.transactionRevision == rhs.transactionRevision
            && lhs.publicationSequence == rhs.publicationSequence
            && lhs.workspaceState.revision == rhs.workspaceState.revision
    }
}
