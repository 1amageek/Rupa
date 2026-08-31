import Foundation
import Observation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaKit
import RupaProject
import RupaUI

@MainActor
@Observable
final class ApplicationProjectCoordinator: ApplicationAgentProjectLifecycle {
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
    private let securityScopedAccessOpener: any SecurityScopedProjectAccessOpening
    @ObservationIgnored
    private let launchArguments: [String]
    @ObservationIgnored
    private var pendingInitialURL: URL?
    @ObservationIgnored
    private var registeredSessionID: UUID?
    @ObservationIgnored
    private var projectFileAccess: ApplicationProjectFileAccess?
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
        securityScopedAccessOpener: any SecurityScopedProjectAccessOpening =
            DefaultSecurityScopedProjectAccessOpener(),
        initialURL: URL? = nil,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.workspace = workspace
        self.agentRegistrar = agentRegistrar
        self.operationSequencer = operationSequencer
        self.securityScopedAccessOpener = securityScopedAccessOpener
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
            ProjectWorkspaceOperationSequencer(),
        securityScopedAccessOpener: any SecurityScopedProjectAccessOpening =
            DefaultSecurityScopedProjectAccessOpener()
    ) {
        let failureKind: ApplicationProjectFailure.Kind =
            launchFailure is ApplicationAuthorityLeaseError
                ? .applicationAuthority
                : .launch
        let failure = ApplicationProjectFailure(
            kind: failureKind,
            message: "The project workspace could not be created: \(launchFailure.localizedDescription)"
        )
        self.workspace = nil
        self.agentRegistrar = agentRegistrar
        self.operationSequencer = operationSequencer
        self.securityScopedAccessOpener = securityScopedAccessOpener
        self.launchArguments = []
        self.pendingInitialURL = nil
        self.lifecycle = .unavailable(failure)
        self.operation = nil
        self.failure = failure
        self.launchStarted = true
        self.scheduledOperation = nil
    }

    var currentFileURL: URL? {
        projectFileAccess?.url
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

    var hasRegisteredAgentSession: Bool {
        lifecycle == .ready && registeredSessionID != nil
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
        var launchWarning: ApplicationProjectFailure?
        do {
            if let requestedURL = pendingInitialURL {
                let validatedURL = try Self.validatedProjectURL(requestedURL)
                do {
                    let result = try await executeLoad(
                        from: validatedURL,
                        workspace: workspace
                    )
                    launchWarning = result.warning
                } catch {
                    throw Self.initialFileActivationFailure(
                        for: validatedURL,
                        error: error
                    )
                }
            } else {
                _ = try await workspace.evaluate()
                _ = try await WorkspaceLaunchProjectFixture.applyIfRequested(
                    arguments: launchArguments,
                    to: workspace
                )
            }
            let sessionID = try await agentRegistrar.register(
                workspace: workspace,
                path: currentFileURL,
                id: UUID()
            )
            registeredSessionID = sessionID
            while pendingInitialURL?.standardizedFileURL
                    != currentFileURL?.standardizedFileURL {
                guard let requestedURL = pendingInitialURL else {
                    break
                }
                let validatedURL: URL
                do {
                    validatedURL = try Self.validatedProjectURL(requestedURL)
                    guard workspace.view?.isDirty != true else {
                        throw Self.unsavedReplacementFailure(for: validatedURL)
                    }
                    let result = try await executeLoad(
                        from: validatedURL,
                        workspace: workspace
                    )
                    lifecycle = .ready
                    _ = await synchronizeAgentPathAfterCommittedView(
                        currentFileURL,
                        view: result.view,
                        mutation: .source,
                        requestMethod: "project.open",
                        successFailure: result.warning,
                        failureMessage: "The project committed, but its Agent file path could not be updated"
                    )
                    return
                } catch {
                    let activationFailure = Self.fileActivationFailure(
                        for: requestedURL,
                        error: error
                    )
                    if activationFailure.didCommit {
                        await terminateProjectAccess(with: activationFailure)
                    } else {
                        lifecycle = .ready
                        failure = activationFailure
                    }
                    return
                }
            }
            lifecycle = .ready
            failure = launchWarning
        } catch {
            await revokeAgentSession()
            let launchFailure = if let failure = error as? ApplicationProjectFailure {
                failure
            } else {
                ApplicationProjectFailure(
                    kind: .launch,
                    message: "The project could not be opened: \(error.localizedDescription)"
                )
            }
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
            let replaced = try await workspace.replace(
                with: .empty(named: name),
                operationGuard: Self.cancellationGuard
            )
            clearProjectFileAccess()
            _ = await synchronizeAgentPathAfterCommittedView(
                nil,
                view: replaced,
                mutation: .source,
                requestMethod: "project.new",
                successFailure: nil,
                failureMessage: "The new project committed, but its Agent file path could not be cleared"
            )
        } catch let error as ProjectWorkspacePersistencePublicationError {
            clearProjectFileAccess()
            _ = await handleCommittedPersistenceFailure(
                error,
                path: nil
            )
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
        let normalizedURL: URL
        do {
            normalizedURL = try Self.validatedProjectURL(url)
        } catch {
            failure = Self.fileActivationFailure(for: url, error: error)
            return
        }
        if let currentFileURL,
           Self.canonicalProjectURL(currentFileURL)
                == Self.canonicalProjectURL(normalizedURL) {
            // Reopening the current canonical project is an idempotent App
            // lifecycle request. The retained security-scoped access remains
            // alive for the current document and no filesystem lease is used.
            failure = nil
            return
        }
        guard !isDirty else {
            failure = Self.unsavedReplacementFailure(for: normalizedURL)
            return
        }
        guard begin(.load), let workspace else {
            return
        }
        defer { endOperation() }
        do {
            let result = try await executeLoad(
                from: normalizedURL,
                workspace: workspace
            )
            _ = await synchronizeAgentPathAfterCommittedView(
                currentFileURL,
                view: result.view,
                mutation: .source,
                requestMethod: "project.open",
                successFailure: result.warning,
                failureMessage: "The project committed, but its Agent file path could not be updated"
            )
        } catch {
            let activationFailure = Self.fileActivationFailure(
                for: normalizedURL,
                error: error
            )
            if activationFailure.didCommit {
                await terminateProjectAccess(with: activationFailure)
            } else {
                failure = activationFailure
            }
        }
    }

    func save(to url: URL) async {
        await sequence(.save) {
            await self.performSave(to: url)
        }
    }

    func save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    ) async throws -> ApplicationAgentSaveOutcome {
        try await operationSequencer.run {
            try await self.performAgentSave(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        }
    }

    private func performSave(to url: URL) async {
        guard begin(.save), let workspace else {
            return
        }
        defer { endOperation() }
        let normalizedURL: URL
        do {
            normalizedURL = try Self.validatedProjectURL(url)
        } catch {
            failure = Self.fileActivationFailure(for: url, error: error)
            return
        }
        do {
            switch try await executeSave(
                to: normalizedURL,
                workspace: workspace,
                expectedGeneration: nil,
                requestMethod: "project.save"
            ) {
            case .saved(let savedView):
                _ = await synchronizeAgentPathAfterCommittedView(
                    currentFileURL,
                    view: savedView,
                    mutation: .save,
                    requestMethod: "project.save",
                    successFailure: nil,
                    failureMessage: "The project saved, but its Agent file path could not be updated"
                )
            case .committed(
                let initialOutcome,
                let viewIsAvailable
            ):
                let synchronization = await synchronizeAgentPath(
                    currentFileURL,
                    committedOutcome: initialOutcome
                )
                let outcome = synchronization.outcome
                guard synchronization.didSynchronize else {
                    return
                }
                let committedFailure = ApplicationProjectFailure(
                    kind: viewIsAvailable ? .save : .viewRecovery,
                    message: outcome.message,
                    didCommit: true,
                    committedMutation: outcome
                )
                failure = committedFailure
                if !viewIsAvailable {
                    await terminateProjectAccess(with: committedFailure)
                }
            }
        } catch {
            if case .unavailable(let terminalFailure) = lifecycle {
                failure = terminalFailure
            } else {
                report(kind: .save, error: error)
            }
        }
    }

    private func performAgentSave(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    ) async throws -> ApplicationAgentSaveOutcome {
        guard registeredSessionID == sessionID else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No registered application project session exists for \(sessionID.uuidString)."
            )
        }
        guard let expectedGeneration else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent save requires an expected source generation."
            )
        }
        guard lifecycle == .ready, let workspace else {
            throw EditorError(
                code: .agentUnavailable,
                message: "The application project workspace is unavailable."
            )
        }
        guard operation == nil, scheduledOperation == nil else {
            throw EditorError(
                code: .commandFailed,
                message: "Another application project operation is already in progress."
            )
        }
        guard let currentFileURL else {
            throw EditorError(
                code: .documentSaveFailed,
                message: "Agent save requires an existing current .rupa project URL."
            )
        }
        operation = .save
        defer { endOperation() }
        do {
            switch try await executeSave(
                to: currentFileURL,
                workspace: workspace,
                expectedGeneration: expectedGeneration,
                requestMethod: "document.save"
            ) {
            case .saved(let savedView):
                failure = nil
                return .saved(SaveResult(
                    message: "Project saved.",
                    path: currentFileURL.path,
                    generation: savedView.documentGeneration,
                    dirty: savedView.isDirty,
                    diagnostics: savedView.evaluationSnapshot.diagnostics
                ))
            case .committed(
                let initialOutcome,
                let viewIsAvailable
            ):
                let synchronization = await synchronizeAgentPath(
                    currentFileURL,
                    committedOutcome: initialOutcome
                )
                let outcome = synchronization.outcome
                guard synchronization.didSynchronize else {
                    return .committed(outcome)
                }
                let committedFailure = ApplicationProjectFailure(
                    kind: viewIsAvailable ? .save : .viewRecovery,
                    message: outcome.message,
                    didCommit: true,
                    committedMutation: outcome
                )
                failure = committedFailure
                if !viewIsAvailable {
                    await terminateProjectAccess(with: committedFailure)
                }
                return .committed(outcome)
            }
        } catch {
            if case .unavailable(let terminalFailure) = lifecycle {
                failure = terminalFailure
                throw terminalFailure
            }
            let saveFailure = ApplicationProjectFailure(
                kind: .save,
                message: error.localizedDescription
            )
            failure = saveFailure
            throw error
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

    private func revokeAgentSession() async {
        guard let registeredSessionID else {
            return
        }
        self.registeredSessionID = nil
        await agentRegistrar.unregister(id: registeredSessionID)
    }

    private func synchronizeAgentPath(
        _ path: URL?,
        committedOutcome: AgentCommittedMutationOutcome
    ) async -> (
        outcome: AgentCommittedMutationOutcome,
        didSynchronize: Bool
    ) {
        do {
            try await updateAgentPath(path)
            return (committedOutcome, true)
        } catch {
            let outcome = AgentCommittedMutationOutcome(
                stage: committedOutcome.stage,
                mutation: committedOutcome.mutation,
                requestMethod: committedOutcome.requestMethod,
                projectID: committedOutcome.projectID,
                documentGeneration: committedOutcome.documentGeneration,
                transactionRevision: committedOutcome.transactionRevision,
                publicationSequence: committedOutcome.publicationSequence,
                workspaceRevision: committedOutcome.workspaceRevision,
                retryDisposition: committedOutcome.retryDisposition,
                message: committedOutcome.message
                    + " The Agent path also could not be synchronized: "
                    + error.localizedDescription
            )
            let pathFailure = ApplicationProjectFailure(
                kind: .agentRegistration,
                message: outcome.message,
                didCommit: true,
                committedMutation: outcome
            )
            await terminateProjectAccess(with: pathFailure)
            return (outcome, false)
        }
    }

    @discardableResult
    private func synchronizeAgentPathAfterCommittedView(
        _ path: URL?,
        view: ProjectViewSnapshot,
        mutation: AgentCommittedMutationOutcome.Mutation,
        requestMethod: String,
        successFailure: ApplicationProjectFailure?,
        failureMessage: String
    ) async -> Bool {
        do {
            try await updateAgentPath(path)
            failure = successFailure
            return true
        } catch {
            let message = failureMessage + ": " + error.localizedDescription
            let outcome = Self.committedMutationOutcome(
                view: view,
                mutation: mutation,
                requestMethod: requestMethod,
                message: message
            )
            let pathFailure = ApplicationProjectFailure(
                kind: .agentRegistration,
                message: message,
                didCommit: true,
                committedMutation: outcome
            )
            await terminateProjectAccess(with: pathFailure)
            return false
        }
    }

    @discardableResult
    private func handleCommittedPersistenceFailure(
        _ persistenceError: ProjectWorkspacePersistencePublicationError,
        path: URL?
    ) async -> Bool {
        do {
            guard let workspace else {
                throw ApplicationProjectFailure(
                    kind: .viewRecovery,
                    message: "The committed project workspace is unavailable."
                )
            }
            _ = try await workspace.recoverCommittedView(
                persistenceError.state,
                operationGuard: Self.cancellationGuard
            )
        } catch let recoveryError {
            let recoveryFailure = ApplicationProjectFailure(
                kind: .viewRecovery,
                message: "The project operation committed, but its view could not be recovered: \(recoveryError.localizedDescription)",
                didCommit: true,
                committedMutation: Self.committedMutationOutcome(
                    state: persistenceError.state,
                    mutation: .source,
                    requestMethod: "project.new",
                    message: persistenceError.message
                )
            )
            await terminateProjectAccess(with: recoveryFailure)
            return false
        }
        do {
            try await updateAgentPath(path)
            failure = ApplicationProjectFailure(
                kind: failureKind(for: persistenceError.operation),
                message: persistenceError.message,
                didCommit: true,
                committedMutation: Self.committedMutationOutcome(
                    state: persistenceError.state,
                    mutation: .source,
                    requestMethod: "project.new",
                    message: persistenceError.message
                )
            )
        } catch let registrationError {
            let message = persistenceError.message
                + " The Agent path also could not be synchronized: "
                + registrationError.localizedDescription
            let outcome = Self.committedMutationOutcome(
                state: persistenceError.state,
                mutation: .source,
                requestMethod: "project.new",
                message: message
            )
            let pathFailure = ApplicationProjectFailure(
                kind: .agentRegistration,
                message: message,
                didCommit: true,
                committedMutation: outcome
            )
            await terminateProjectAccess(with: pathFailure)
            return false
        }
        return true
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

    private struct LoadExecutionResult {
        let view: ProjectViewSnapshot
        let warning: ApplicationProjectFailure?
    }

    private enum SaveExecutionResult {
        case saved(ProjectViewSnapshot)
        case committed(
            outcome: AgentCommittedMutationOutcome,
            viewIsAvailable: Bool
        )
    }

    private func executeLoad(
        from url: URL,
        workspace: ProjectWorkspace
    ) async throws -> LoadExecutionResult {
        let candidate = projectFileAccessCandidate(for: url)
        let loaded: ProjectViewSnapshot
        do {
            loaded = try await workspace.load(
                from: url,
                operationGuard: Self.cancellationGuard
            )
        } catch let publicationError as ProjectWorkspacePersistencePublicationError
            where publicationError.operation == .load {
            installProjectFileAccess(candidate)
            do {
                let recovered = try await workspace.recoverCommittedView(
                    publicationError.state,
                    operationGuard: Self.cancellationGuard
                )
                return LoadExecutionResult(
                    view: recovered,
                    warning: Self.committedApplicationFailure(
                        kind: .load,
                        state: publicationError.state,
                        mutation: .source,
                        requestMethod: "project.open",
                        message: publicationError.message
                    )
                )
            } catch let recoveryError {
                throw Self.committedApplicationFailure(
                    kind: .viewRecovery,
                    state: publicationError.state,
                    mutation: .source,
                    requestMethod: "project.open",
                    message: publicationError.message
                        + " Automatic view recovery also failed: "
                        + String(describing: recoveryError)
                )
            }
        }
        installProjectFileAccess(candidate)
        return LoadExecutionResult(view: loaded, warning: nil)
    }

    private func executeSave(
        to url: URL,
        workspace: ProjectWorkspace,
        expectedGeneration: DocumentGeneration?,
        requestMethod: String
    ) async throws -> SaveExecutionResult {
        if let expectedGeneration {
            guard let view = workspace.view else {
                throw EditorError(
                    code: .agentUnavailable,
                    message: "The application project has no published view."
                )
            }
            guard expectedGeneration == view.documentGeneration else {
                throw EditorError(
                    code: .documentGenerationMismatch,
                    message: "Agent save expected generation \(expectedGeneration.value), but the project is at generation \(view.documentGeneration.value)."
                )
            }
        }

        let candidate = projectFileAccessCandidate(for: url)
        do {
            let saved = try await workspace.save(
                to: url,
                operationGuard: Self.cancellationGuard
            )
            installProjectFileAccess(candidate)
            return .saved(saved)
        } catch let publicationError as ProjectWorkspacePersistencePublicationError
            where publicationError.operation == .save {
            installProjectFileAccess(candidate)
            do {
                _ = try await workspace.recoverCommittedView(
                    publicationError.state,
                    operationGuard: Self.cancellationGuard
                )
                return .committed(
                    outcome: Self.committedMutationOutcome(
                        state: publicationError.state,
                        mutation: .save,
                        requestMethod: requestMethod,
                        message: publicationError.message
                    ),
                    viewIsAvailable: true
                )
            } catch let recoveryError {
                return .committed(
                    outcome: Self.committedMutationOutcome(
                        state: publicationError.state,
                        mutation: .save,
                        requestMethod: requestMethod,
                        message: publicationError.message
                            + " Automatic view recovery also failed: "
                            + String(describing: recoveryError)
                    ),
                    viewIsAvailable: false
                )
            }
        }
    }

    private func projectFileAccessCandidate(
        for url: URL
    ) -> ApplicationProjectFileAccess {
        if let projectFileAccess, projectFileAccess.owns(url) {
            return projectFileAccess
        }
        return ApplicationProjectFileAccess(
            access: securityScopedAccessOpener.open(url)
        )
    }

    private func installProjectFileAccess(
        _ candidate: ApplicationProjectFileAccess
    ) {
        projectFileAccess = candidate
    }

    private func clearProjectFileAccess() {
        projectFileAccess = nil
    }

    private func terminateProjectAccess(
        with terminalFailure: ApplicationProjectFailure
    ) async {
        lifecycle = .unavailable(terminalFailure)
        failure = terminalFailure
        await revokeAgentSession()
    }

    private static func committedApplicationFailure(
        kind: ApplicationProjectFailure.Kind,
        state: ProjectStateSnapshot,
        mutation: AgentCommittedMutationOutcome.Mutation,
        requestMethod: String,
        message: String
    ) -> ApplicationProjectFailure {
        let outcome = committedMutationOutcome(
            state: state,
            mutation: mutation,
            requestMethod: requestMethod,
            message: message
        )
        return ApplicationProjectFailure(
            kind: kind,
            message: message,
            didCommit: true,
            committedMutation: outcome
        )
    }

    private static func committedMutationOutcome(
        view: ProjectViewSnapshot,
        mutation: AgentCommittedMutationOutcome.Mutation,
        requestMethod: String,
        message: String
    ) -> AgentCommittedMutationOutcome {
        AgentCommittedMutationOutcome(
            stage: .viewProjection,
            mutation: mutation,
            requestMethod: requestMethod,
            projectID: view.projectID,
            documentGeneration: view.documentGeneration,
            transactionRevision: view.transactionRevision,
            publicationSequence: view.publicationSequence,
            workspaceRevision: view.workspaceState.revision,
            message: message
        )
    }

    private static func committedMutationOutcome(
        state: ProjectStateSnapshot,
        mutation: AgentCommittedMutationOutcome.Mutation,
        requestMethod: String,
        message: String
    ) -> AgentCommittedMutationOutcome {
        AgentCommittedMutationOutcome(
            stage: .viewProjection,
            mutation: mutation,
            requestMethod: requestMethod,
            projectID: state.document.projectID,
            documentGeneration: state.documentGeneration,
            transactionRevision: state.transactionRevision,
            publicationSequence: state.publicationSequence,
            workspaceRevision: state.workspaceState.revision,
            message: message
        )
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

    private static func validatedProjectURL(_ url: URL) throws -> URL {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.isFileURL,
              normalizedURL.pathExtension.lowercased() == "rupa" else {
            throw ApplicationProjectFailure(
                kind: .unsupportedProjectFormat,
                message: "Rupa can open schema-v3 .rupa projects only. Requested file: \(normalizedURL.path)"
            )
        }
        return normalizedURL
    }

    private static func canonicalProjectURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func unsavedReplacementFailure(
        for requestedURL: URL
    ) -> ApplicationProjectFailure {
        ApplicationProjectFailure(
            kind: .unsavedChanges,
            message: "Save the current project before opening the requested file: \(requestedURL.standardizedFileURL.path)"
        )
    }

    private static func fileActivationFailure(
        for requestedURL: URL,
        error: Error
    ) -> ApplicationProjectFailure {
        if let failure = error as? ApplicationProjectFailure {
            return failure
        }
        return ApplicationProjectFailure(
            kind: .load,
            message: "The requested project could not be opened at \(requestedURL.standardizedFileURL.path): \(error.localizedDescription)"
        )
    }

    private static func initialFileActivationFailure(
        for requestedURL: URL,
        error: Error
    ) -> ApplicationProjectFailure {
        if let failure = error as? ApplicationProjectFailure {
            return failure
        }
        return ApplicationProjectFailure(
            kind: .launch,
            message: "The requested project could not be opened at \(requestedURL.standardizedFileURL.path): \(error.localizedDescription)"
        )
    }

    private static let cancellationGuard: @Sendable () throws -> Void = {
        try Task.checkCancellation()
    }
}
