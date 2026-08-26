import Foundation
import Observation
import RupaCore
import RupaKit
import RupaUI

@MainActor
@Observable
final class ApplicationProjectCoordinator {
    enum Lifecycle: Equatable {
        case preparing
        case ready
        case unavailable(ApplicationProjectFailure)
    }

    enum Operation: String, Equatable {
        case newProject
        case load
        case save
        case undo
        case redo
    }

    private(set) var lifecycle: Lifecycle
    private(set) var operation: Operation?
    private(set) var failure: ApplicationProjectFailure?
    let workspace: ProjectWorkspace?

    @ObservationIgnored
    private let agentRegistrar: any ApplicationAgentSessionRegistering
    @ObservationIgnored
    private let operationSequencer: ProjectWorkspaceOperationSequencer
    @ObservationIgnored
    private let launchArguments: [String]
    @ObservationIgnored
    private var pendingInitialURL: URL?
    @ObservationIgnored
    private var registeredSessionID: UUID?
    @ObservationIgnored
    private var fileAccess: SecurityScopedProjectURL?
    @ObservationIgnored
    private var activeTask: Task<Void, Never>?
    @ObservationIgnored
    private var launchStarted: Bool
    private var scheduledOperation: Operation?

    init(
        workspace: ProjectWorkspace,
        agentRegistrar: any ApplicationAgentSessionRegistering,
        operationSequencer: ProjectWorkspaceOperationSequencer =
            ProjectWorkspaceOperationSequencer(),
        initialURL: URL? = nil,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.workspace = workspace
        self.agentRegistrar = agentRegistrar
        self.operationSequencer = operationSequencer
        self.launchArguments = launchArguments
        self.pendingInitialURL = initialURL?.standardizedFileURL
        self.lifecycle = .preparing
        self.operation = nil
        self.failure = nil
        self.launchStarted = false
        self.scheduledOperation = nil
    }

    init(
        launchFailure: Error,
        agentRegistrar: any ApplicationAgentSessionRegistering,
        operationSequencer: ProjectWorkspaceOperationSequencer =
            ProjectWorkspaceOperationSequencer()
    ) {
        let failure = ApplicationProjectFailure(
            kind: .launch,
            message: "The project workspace could not be created: \(launchFailure.localizedDescription)"
        )
        self.workspace = nil
        self.agentRegistrar = agentRegistrar
        self.operationSequencer = operationSequencer
        self.launchArguments = []
        self.pendingInitialURL = nil
        self.lifecycle = .unavailable(failure)
        self.operation = nil
        self.failure = failure
        self.launchStarted = true
        self.scheduledOperation = nil
    }

    var currentFileURL: URL? {
        fileAccess?.url
    }

    var snapshot: ProjectViewSnapshot? {
        workspace?.view
    }

    var isDirty: Bool {
        snapshot?.isDirty ?? false
    }

    var canUndo: Bool {
        lifecycle == .ready && !isBusy && (snapshot?.canUndo ?? false)
    }

    var canRedo: Bool {
        lifecycle == .ready && !isBusy && (snapshot?.canRedo ?? false)
    }

    var canOpen: Bool {
        lifecycle == .ready && !isBusy && !isDirty
    }

    var canCreateNew: Bool {
        lifecycle == .ready && !isBusy && !isDirty
    }

    var canSave: Bool {
        lifecycle == .ready && !isBusy && snapshot != nil
    }

    var isBusy: Bool {
        operation != nil || scheduledOperation != nil
    }

    var canCancelOperation: Bool {
        guard let operation = operation ?? scheduledOperation else {
            return false
        }
        return operation != .save
    }

    func launch() async {
        guard lifecycle == .preparing,
              !launchStarted,
              let workspace else {
            return
        }
        launchStarted = true
        await Task.yield()
        var openedURL = pendingInitialURL
        var retainedAccess = openedURL.map(SecurityScopedProjectURL.init)
        do {
            if let openedURL {
                _ = try await workspace.load(
                    from: openedURL,
                    operationGuard: Self.cancellationGuard
                )
            } else {
                _ = try await workspace.evaluate()
                _ = try await WorkspaceLaunchProjectFixture.applyIfRequested(
                    arguments: launchArguments,
                    to: workspace
                )
            }
            let sessionID = try await agentRegistrar.register(
                workspace: workspace,
                path: openedURL,
                id: UUID()
            )
            registeredSessionID = sessionID
            while pendingInitialURL != openedURL {
                guard let requestedURL = pendingInitialURL else {
                    break
                }
                let requestedAccess = SecurityScopedProjectURL(requestedURL)
                _ = try await workspace.load(
                    from: requestedURL,
                    operationGuard: Self.cancellationGuard
                )
                try await updateAgentPath(requestedURL)
                openedURL = requestedURL
                retainedAccess = requestedAccess
            }
            fileAccess = retainedAccess
            lifecycle = .ready
            failure = nil
        } catch {
            if let registeredSessionID {
                await agentRegistrar.unregister(id: registeredSessionID)
                self.registeredSessionID = nil
            }
            let launchFailure = ApplicationProjectFailure(
                kind: .launch,
                message: "The project could not be opened: \(error.localizedDescription)"
            )
            lifecycle = .unavailable(launchFailure)
            failure = launchFailure
        }
    }

    func receiveOpenURL(_ url: URL) {
        if lifecycle == .preparing {
            pendingInitialURL = url.standardizedFileURL
            return
        }
        startLoad(from: url)
    }

    func startNewProject(named name: String = "Untitled") {
        startTask(.newProject) {
            await self.newProject(named: name)
        }
    }

    func startLoad(from url: URL) {
        startTask(.load) {
            await self.load(from: url)
        }
    }

    func startSave(to url: URL) {
        startTask(.save) {
            await self.save(to: url)
        }
    }

    func startUndo() {
        startTask(.undo) {
            await self.undo()
        }
    }

    func startRedo() {
        startTask(.redo) {
            await self.redo()
        }
    }

    func cancelCurrentOperation() {
        guard canCancelOperation else {
            return
        }
        activeTask?.cancel()
    }

    func clearFailure() {
        failure = nil
    }

    func newProject(named name: String = "Untitled") async {
        await sequence(.newProject) {
            await self.performNewProject(named: name)
        }
    }

    private func performNewProject(named name: String) async {
        guard !isDirty else {
            failure = ApplicationProjectFailure(
                kind: .unsavedChanges,
                message: "Save the current project before creating another project."
            )
            return
        }
        guard begin(.newProject), let workspace else {
            return
        }
        defer { endOperation() }
        do {
            _ = try await workspace.replace(
                with: .empty(named: name),
                operationGuard: Self.cancellationGuard
            )
            fileAccess = nil
            await updateAgentPathAfterCommit(nil)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            fileAccess = nil
            await handleCommittedPersistenceFailure(error, path: nil)
        } catch {
            report(kind: .newProject, error: error)
        }
    }

    func load(from url: URL) async {
        await sequence(.load) {
            await self.performLoad(from: url)
        }
    }

    private func performLoad(from url: URL) async {
        guard !isDirty else {
            failure = ApplicationProjectFailure(
                kind: .unsavedChanges,
                message: "Save the current project before opening another project."
            )
            return
        }
        guard begin(.load), let workspace else {
            return
        }
        defer { endOperation() }
        let normalizedURL = url.standardizedFileURL
        let candidateAccess = SecurityScopedProjectURL(normalizedURL)
        do {
            _ = try await workspace.load(
                from: normalizedURL,
                operationGuard: Self.cancellationGuard
            )
            fileAccess = candidateAccess
            await updateAgentPathAfterCommit(normalizedURL)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            fileAccess = candidateAccess
            await handleCommittedPersistenceFailure(error, path: normalizedURL)
        } catch {
            report(kind: .load, error: error)
        }
    }

    func save(to url: URL) async {
        await sequence(.save) {
            await self.performSave(to: url)
        }
    }

    private func performSave(to url: URL) async {
        guard begin(.save), let workspace else {
            return
        }
        defer { endOperation() }
        let normalizedURL = url.standardizedFileURL
        let reusesCurrentAccess = fileAccess?.url == normalizedURL
        let candidateAccess = reusesCurrentAccess
            ? fileAccess
            : SecurityScopedProjectURL(normalizedURL)
        do {
            _ = try await workspace.save(
                to: normalizedURL,
                operationGuard: Self.cancellationGuard
            )
            fileAccess = candidateAccess
            await updateAgentPathAfterCommit(normalizedURL)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            fileAccess = candidateAccess
            await handleCommittedPersistenceFailure(error, path: normalizedURL)
        } catch {
            report(kind: .save, error: error)
        }
    }

    func undo() async {
        await sequence(.undo) {
            await self.performUndo()
        }
    }

    private func performUndo() async {
        guard begin(.undo), let workspace else {
            return
        }
        defer { endOperation() }
        do {
            guard let snapshot = workspace.view else {
                throw ApplicationProjectFailure(
                    kind: .undo,
                    message: "The project view is unavailable."
                )
            }
            _ = try await workspace.undo(
                from: snapshot,
                operationGuard: Self.cancellationGuard
            )
            failure = nil
        } catch let error as ProjectWorkspacePostCommitError {
            await handleCommittedHistoryFailure(error, kind: .undo)
        } catch {
            report(kind: .undo, error: error)
        }
    }

    func redo() async {
        await sequence(.redo) {
            await self.performRedo()
        }
    }

    private func performRedo() async {
        guard begin(.redo), let workspace else {
            return
        }
        defer { endOperation() }
        do {
            guard let snapshot = workspace.view else {
                throw ApplicationProjectFailure(
                    kind: .redo,
                    message: "The project view is unavailable."
                )
            }
            _ = try await workspace.redo(
                from: snapshot,
                operationGuard: Self.cancellationGuard
            )
            failure = nil
        } catch let error as ProjectWorkspacePostCommitError {
            await handleCommittedHistoryFailure(error, kind: .redo)
        } catch {
            report(kind: .redo, error: error)
        }
    }

    private func begin(_ requestedOperation: Operation) -> Bool {
        guard lifecycle == .ready, workspace != nil else {
            let unavailable = ApplicationProjectFailure(
                kind: .launch,
                message: "The project workspace is unavailable."
            )
            failure = unavailable
            return false
        }
        guard operation == nil else {
            failure = ApplicationProjectFailure(
                kind: .operationInProgress,
                message: "Another project operation is already in progress."
            )
            return false
        }
        scheduledOperation = nil
        operation = requestedOperation
        return true
    }

    private func endOperation() {
        operation = nil
    }

    private func startTask(
        _ requestedOperation: Operation,
        _ body: @escaping @MainActor () async -> Void
    ) {
        guard activeTask == nil else {
            failure = ApplicationProjectFailure(
                kind: .operationInProgress,
                message: "Another project operation is already in progress."
            )
            return
        }
        scheduledOperation = requestedOperation
        activeTask = Task { @MainActor [weak self] in
            await body()
            self?.scheduledOperation = nil
            self?.activeTask = nil
        }
    }

    private func sequence(
        _ operation: Operation,
        _ body: @escaping @MainActor @Sendable () async -> Void
    ) async {
        do {
            try await operationSequencer.run {
                await body()
            }
        } catch {
            report(kind: failureKind(for: operation), error: error)
        }
    }

    private func updateAgentPath(_ path: URL?) async throws {
        guard let registeredSessionID else {
            throw ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "The project has no Agent session registration."
            )
        }
        try await agentRegistrar.updatePath(id: registeredSessionID, path: path)
    }

    private func updateAgentPathAfterCommit(_ path: URL?) async {
        do {
            try await updateAgentPath(path)
            failure = nil
        } catch {
            failure = ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "The project committed, but its Agent file path could not be updated: \(error.localizedDescription)",
                didCommit: true
            )
        }
    }

    private func handleCommittedPersistenceFailure(
        _ error: ProjectWorkspacePersistencePublicationError,
        path: URL?
    ) async {
        do {
            guard let workspace else {
                throw ApplicationProjectFailure(
                    kind: .viewRecovery,
                    message: "The committed project workspace is unavailable."
                )
            }
            _ = try await workspace.recoverCommittedView(
                error.state,
                operationGuard: Self.cancellationGuard
            )
        } catch {
            let recoveryFailure = ApplicationProjectFailure(
                kind: .viewRecovery,
                message: "The project operation committed, but its view could not be recovered: \(error.localizedDescription)",
                didCommit: true
            )
            lifecycle = .unavailable(recoveryFailure)
            failure = recoveryFailure
            return
        }
        do {
            try await updateAgentPath(path)
            failure = ApplicationProjectFailure(
                kind: failureKind(for: error.operation),
                message: error.message,
                didCommit: true
            )
        } catch {
            failure = ApplicationProjectFailure(
                kind: .agentRegistration,
                message: "The project and its recovered view committed, but the Agent file path could not be updated: \(error.localizedDescription)",
                didCommit: true
            )
        }
    }

    private func handleCommittedHistoryFailure(
        _ error: ProjectWorkspacePostCommitError,
        kind: ApplicationProjectFailure.Kind
    ) async {
        do {
            guard let workspace else {
                throw ApplicationProjectFailure(
                    kind: .viewRecovery,
                    message: "The committed project workspace is unavailable."
                )
            }
            _ = try await workspace.recoverCommittedView(
                error.commit.state,
                operationGuard: Self.cancellationGuard
            )
            failure = ApplicationProjectFailure(
                kind: kind,
                message: error.message,
                didCommit: true
            )
        } catch {
            let recoveryFailure = ApplicationProjectFailure(
                kind: .viewRecovery,
                message: "The history operation committed, but its view could not be recovered: \(error.localizedDescription)",
                didCommit: true
            )
            lifecycle = .unavailable(recoveryFailure)
            failure = recoveryFailure
        }
    }

    private func failureKind(
        for operation: ProjectWorkspacePersistencePublicationError.Operation
    ) -> ApplicationProjectFailure.Kind {
        switch operation {
        case .newProject:
            .newProject
        case .load:
            .load
        case .save:
            .save
        }
    }

    private func failureKind(
        for operation: Operation
    ) -> ApplicationProjectFailure.Kind {
        switch operation {
        case .newProject:
            .newProject
        case .load:
            .load
        case .save:
            .save
        case .undo:
            .undo
        case .redo:
            .redo
        }
    }

    private func report(kind: ApplicationProjectFailure.Kind, error: Error) {
        failure = ApplicationProjectFailure(
            kind: kind,
            message: error.localizedDescription
        )
    }

    private static let cancellationGuard: @Sendable () throws -> Void = {
        try Task.checkCancellation()
    }
}
