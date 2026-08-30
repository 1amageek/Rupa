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
    private var fileAccess: (any SecurityScopedProjectAccess)?
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
        var openedURL: URL?
        var retainedAccess: (any SecurityScopedProjectAccess)?
        do {
            if let requestedURL = pendingInitialURL {
                let validatedURL = try Self.validatedProjectURL(requestedURL)
                let candidateAccess = securityScopedAccessOpener.open(validatedURL)
                do {
                    _ = try await workspace.load(
                        from: validatedURL,
                        operationGuard: Self.cancellationGuard
                    )
                } catch {
                    throw Self.initialFileActivationFailure(
                        for: validatedURL,
                        error: error
                    )
                }
                openedURL = validatedURL
                retainedAccess = candidateAccess
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
                let validatedURL: URL
                do {
                    validatedURL = try Self.validatedProjectURL(requestedURL)
                    guard workspace.view?.isDirty != true else {
                        throw Self.unsavedReplacementFailure(for: validatedURL)
                    }
                    let candidateAccess = securityScopedAccessOpener.open(validatedURL)
                    do {
                        _ = try await workspace.load(
                            from: validatedURL,
                            operationGuard: Self.cancellationGuard
                        )
                    } catch let error as ProjectWorkspacePersistencePublicationError {
                        let didRecover = await handleCommittedPersistenceFailure(
                            error,
                            path: validatedURL,
                            fileAccessAfterRecovery: candidateAccess
                        )
                        if didRecover {
                            openedURL = validatedURL
                            retainedAccess = candidateAccess
                            lifecycle = .ready
                        }
                        return
                    }
                    openedURL = validatedURL
                    retainedAccess = candidateAccess
                    fileAccess = candidateAccess
                    lifecycle = .ready
                    await updateAgentPathAfterCommit(validatedURL)
                    if failure != nil {
                        return
                    }
                } catch {
                    fileAccess = retainedAccess
                    lifecycle = .ready
                    failure = Self.fileActivationFailure(
                        for: requestedURL,
                        error: error
                    )
                    return
                }
            }
            fileAccess = retainedAccess
            lifecycle = .ready
            failure = nil
        } catch {
            if let registeredSessionID {
                await agentRegistrar.unregister(id: registeredSessionID)
                self.registeredSessionID = nil
            }
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
            _ = try await workspace.replace(
                with: .empty(named: name),
                operationGuard: Self.cancellationGuard
            )
            fileAccess = nil
            await updateAgentPathAfterCommit(nil)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            _ = await handleCommittedPersistenceFailure(
                error,
                path: nil,
                fileAccessAfterRecovery: nil
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
        guard !isDirty else {
            failure = Self.unsavedReplacementFailure(for: normalizedURL)
            return
        }
        guard begin(.load), let workspace else {
            return
        }
        defer { endOperation() }
        let candidateAccess = securityScopedAccessOpener.open(normalizedURL)
        do {
            _ = try await workspace.load(
                from: normalizedURL,
                operationGuard: Self.cancellationGuard
            )
            fileAccess = candidateAccess
            await updateAgentPathAfterCommit(normalizedURL)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            _ = await handleCommittedPersistenceFailure(
                error,
                path: normalizedURL,
                fileAccessAfterRecovery: candidateAccess
            )
        } catch {
            failure = Self.fileActivationFailure(
                for: normalizedURL,
                error: error
            )
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
        let normalizedURL = url.standardizedFileURL
        let reusesCurrentAccess = fileAccess?.url == normalizedURL
        let candidateAccess = reusesCurrentAccess
            ? fileAccess
            : securityScopedAccessOpener.open(normalizedURL)
        do {
            _ = try await workspace.save(
                to: normalizedURL,
                operationGuard: Self.cancellationGuard
            )
            fileAccess = candidateAccess
            await updateAgentPathAfterCommit(normalizedURL)
        } catch let error as ProjectWorkspacePersistencePublicationError {
            _ = await handleCommittedPersistenceFailure(
                error,
                path: normalizedURL,
                fileAccessAfterRecovery: candidateAccess
            )
        } catch {
            report(kind: .save, error: error)
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
        guard let currentView = workspace.view else {
            throw EditorError(
                code: .agentUnavailable,
                message: "The application project has no published view."
            )
        }
        guard expectedGeneration == currentView.documentGeneration else {
            throw EditorError(
                code: .documentGenerationMismatch,
                message: "Agent save expected generation \(expectedGeneration.value), but the project is at generation \(currentView.documentGeneration.value)."
            )
        }

        operation = .save
        defer { endOperation() }
        do {
            let savedView = try await workspace.save(
                to: currentFileURL,
                operationGuard: Self.cancellationGuard
            )
            failure = nil
            return .saved(
                SaveResult(
                    message: "Project saved.",
                    path: currentFileURL.path,
                    generation: savedView.documentGeneration,
                    dirty: savedView.isDirty,
                    diagnostics: savedView.evaluationSnapshot.diagnostics
                )
            )
        } catch let error as ProjectWorkspacePersistencePublicationError {
            return .committed(
                await committedAgentSaveOutcome(
                    error,
                    requestMethod: "document.save"
                )
            )
        } catch {
            failure = ApplicationProjectFailure(
                kind: .save,
                message: error.localizedDescription
            )
            throw error
        }
    }

    private func committedAgentSaveOutcome(
        _ error: ProjectWorkspacePersistencePublicationError,
        requestMethod: String
    ) async -> AgentCommittedMutationOutcome {
        var message = error.message
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
            failure = ApplicationProjectFailure(
                kind: .save,
                message: error.message,
                didCommit: true
            )
        } catch {
            message += " Automatic view recovery also failed: \(error.localizedDescription)"
            let recoveryFailure = ApplicationProjectFailure(
                kind: .viewRecovery,
                message: message,
                didCommit: true
            )
            lifecycle = .unavailable(recoveryFailure)
            failure = recoveryFailure
        }

        let state = error.state
        return AgentCommittedMutationOutcome(
            stage: .viewProjection,
            mutation: .save,
            requestMethod: requestMethod,
            projectID: state.document.projectID,
            documentGeneration: state.documentGeneration,
            transactionRevision: state.transactionRevision,
            publicationSequence: state.publicationSequence,
            workspaceRevision: state.workspaceState.revision,
            message: message
        )
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

    @discardableResult
    private func handleCommittedPersistenceFailure(
        _ error: ProjectWorkspacePersistencePublicationError,
        path: URL?,
        fileAccessAfterRecovery: (any SecurityScopedProjectAccess)?
    ) async -> Bool {
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
            return false
        }
        fileAccess = fileAccessAfterRecovery
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
