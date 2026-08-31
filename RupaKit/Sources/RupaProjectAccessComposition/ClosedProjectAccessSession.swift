import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaCoreTypes
import RupaKit
import RupaProjectAccess
import RupaProjectAccessPlatform

@MainActor
private final class ClosedProjectAccessOperationSequencer {
    private var tail: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var acceptsOperations = true

    func enqueue<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        guard acceptsOperations else {
            throw ProjectAccessError.finished
        }
        try Task.checkCancellation()
        let predecessor = tail
        let current = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { @MainActor in
            _ = await current.result
        }
        return try await withTaskCancellationHandler {
            try await current.value
        } onCancel: {
            current.cancel()
        }
    }

    func finish(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        if let finishTask {
            await finishTask.value
            return
        }
        acceptsOperations = false
        let predecessor = tail
        let completion = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            await operation()
        }
        finishTask = completion
        tail = completion
        await completion.value
    }
}

/// A closed-file access session backed by one temporary workspace and handler.
@MainActor
public final class ClosedProjectAccessSession: ProjectAccessSession {
    public nonisolated let sessionID: UUID

    private let workspace: ProjectWorkspace
    private let handler: ProjectAgentCommandController
    private let lease: ProjectFileAuthorityLease
    private let inputURL: URL
    private let outputURL: URL?
    private let deadline: ContinuousClock.Instant
    private let sequencer = ClosedProjectAccessOperationSequencer()

    init(
        sessionID: UUID,
        workspace: ProjectWorkspace,
        handler: ProjectAgentCommandController,
        lease: ProjectFileAuthorityLease,
        inputURL: URL,
        outputURL: URL?,
        deadline: ContinuousClock.Instant
    ) {
        self.sessionID = sessionID
        self.workspace = workspace
        self.handler = handler
        self.lease = lease
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.deadline = deadline
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        try await sequencer.enqueue { [self] in
            try ensureActive()
            try validateSessionIdentity(of: request)
            try await lease.validate()
            return await handler.handle(request)
        }
    }

    public func save(
        expectedGeneration: DocumentGeneration?
    ) async throws -> SaveResult {
        try await sequencer.enqueue { [self] in
            try ensureActive()
            try await lease.validate()
            guard let view = workspace.view else {
                throw ProjectAccessError.saveUnavailable
            }
            if let expectedGeneration,
               expectedGeneration != view.documentGeneration {
                throw EditorError(
                    code: .documentGenerationMismatch,
                    message: "The project generation changed before the closed-file save began."
                )
            }
            let destination = outputURL ?? inputURL
            let deadline = self.deadline
            do {
                let saved = try await workspace.save(
                    to: destination,
                    operationGuard: {
                        try Self.validateDeadline(deadline)
                    }
                )
                do {
                    try await lease.adoptPublished(destination)
                } catch {
                    throw Self.committedMutationError(
                        view: saved,
                        message: "The project saved, but the published file authority could not be rebound: " + String(describing: error)
                    )
                }
                return Self.saveResult(from: saved, destination: destination)
            } catch let error as ProjectWorkspacePersistencePublicationError
                where error.operation == .save {
                let committedState = error.state
                let publicationMessage = error.message
                do {
                    try await lease.adoptPublished(destination)
                    let recovered = try await workspace.recoverCommittedView(error.state)
                    return Self.saveResult(from: recovered, destination: destination)
                } catch {
                    throw Self.committedMutationError(
                        projectID: committedState.document.projectID,
                        generation: committedState.documentGeneration,
                        transactionRevision: committedState.transactionRevision,
                        publicationSequence: committedState.publicationSequence,
                        workspaceRevision: committedState.workspaceState.revision,
                        message: publicationMessage + " Committed-view recovery failed: " + String(describing: error)
                    )
                }
            }
        }
    }

    public func finish() async {
        await sequencer.finish { [handler, lease, sessionID] in
            await handler.unregister(id: sessionID)
            await lease.release()
        }
    }

    private func ensureActive() throws {
        try Self.validateDeadline(deadline)
    }

    nonisolated private static func validateDeadline(
        _ deadline: ContinuousClock.Instant
    ) throws {
        guard ContinuousClock.now < deadline else {
            throw ProjectAccessError.deadlineExceeded
        }
    }

    private static func saveResult(
        from view: ProjectViewSnapshot,
        destination: URL
    ) -> SaveResult {
        SaveResult(
            message: "Project saved.",
            path: destination.path,
            generation: view.documentGeneration,
            dirty: view.isDirty,
            diagnostics: view.evaluationSnapshot.diagnostics
        )
    }

    private static func committedMutationError(
        view: ProjectViewSnapshot,
        message: String
    ) -> ProjectAccessError {
        committedMutationError(
            projectID: view.projectID,
            generation: view.documentGeneration,
            transactionRevision: view.transactionRevision,
            publicationSequence: view.publicationSequence,
            workspaceRevision: view.workspaceState.revision,
            message: message
        )
    }

    private static func committedMutationError(
        projectID: ProjectID,
        generation: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        workspaceRevision: WorkspaceRevision,
        message: String
    ) -> ProjectAccessError {
        .committedMutation(
            AgentCommittedMutationOutcome(
                stage: .viewProjection,
                mutation: .save,
                requestMethod: "document.save",
                projectID: projectID,
                documentGeneration: generation,
                transactionRevision: transactionRevision,
                publicationSequence: publicationSequence,
                workspaceRevision: workspaceRevision,
                message: message
            )
        )
    }
}
