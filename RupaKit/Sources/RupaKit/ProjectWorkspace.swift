import Foundation
import Observation
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaProject

/// Main-actor observation adapter for one project-operation owner.
@MainActor
@Observable
public final class ProjectWorkspace {
    public private(set) var view: ProjectViewSnapshot?

    @ObservationIgnored
    private let project: any ProjectOperating
    @ObservationIgnored
    private let viewBuilder: any ProjectViewSnapshotBuilding
    @ObservationIgnored
    private let domainResultProjector: any DomainCommandResultProjecting
    @ObservationIgnored
    private let automationBatchPlanner: any AutomationBatchPlanning

    public init(
        project: any ProjectOperating,
        viewBuilder: any ProjectViewSnapshotBuilding = ProjectViewSnapshotBuilder(),
        domainResultProjector: any DomainCommandResultProjecting =
            DefaultDomainCommandResultProjector(),
        automationBatchPlanner: any AutomationBatchPlanning = DefaultAutomationBatchPlanner()
    ) {
        self.project = project
        self.viewBuilder = viewBuilder
        self.domainResultProjector = domainResultProjector
        self.automationBatchPlanner = automationBatchPlanner
    }

    @discardableResult
    public func refresh() async throws -> ProjectViewSnapshot {
        try await publish(try await project.currentState())
    }

    /// Linearizes a read or external publication against project authority.
    public func withValidatedAuthority<Result: Sendable>(
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {},
        _ body: @Sendable () throws -> Result
    ) async throws -> Result {
        try await project.withValidatedCoordinates(
            expectedProjectID: snapshot.projectID,
            expectedDocumentGeneration: snapshot.documentGeneration,
            expectedTransactionRevision: snapshot.transactionRevision,
            expectedPublicationSequence: snapshot.publicationSequence,
            expectedWorkspaceRevision: snapshot.workspaceState.revision,
            operationGuard: operationGuard,
            body
        )
    }

    /// Rebuilds presentation from an already committed authority state without
    /// replaying its mutation.
    public func recoverCommittedView(
        _ state: ProjectStateSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectViewSnapshot {
        try operationGuard()
        let builder = viewBuilder
        let candidate = try await Task.detached(priority: nil) {
            try builder.build(from: state)
        }.value
        _ = try await project.withValidatedCoordinates(
            expectedProjectID: state.document.projectID,
            expectedDocumentGeneration: state.documentGeneration,
            expectedTransactionRevision: state.transactionRevision,
            expectedPublicationSequence: state.publicationSequence,
            expectedWorkspaceRevision: state.workspaceState.revision,
            operationGuard: operationGuard
        ) {
            true
        }
        if let view {
            if candidate.publicationSequence > view.publicationSequence {
                self.view = candidate
            }
        } else {
            view = candidate
        }
        return candidate
    }

    @discardableResult
    public func evaluate() async throws -> ProjectViewSnapshot {
        guard view != nil else {
            return try await publish(
                try await project.evaluateCurrent(operationGuard: {})
            )
        }
        return try await evaluate(from: try currentInteractionCoordinates())
    }

    @discardableResult
    public func evaluate(
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectViewSnapshot {
        let state = try await project.evaluateCurrent(
            expectedProjectID: snapshot.projectID,
            expectedTransactionRevision: snapshot.transactionRevision,
            expectedPublicationSequence: snapshot.publicationSequence,
            operationGuard: operationGuard
        )
        do {
            return try await buildExactViewAndPublishIfNewer(state)
        } catch {
            throw ProjectWorkspacePostCommitError(
                stage: .viewProjection,
                commit: .evaluation(state),
                message: "The evaluation published, but its project view could not be built: \(error)."
            )
        }
    }

    @discardableResult
    public func commit(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectViewSnapshot {
        let result = try await perform(.source(transaction))
        guard case .source(_, let view) = result else {
            throw ProjectWorkspaceActionError(
                code: .actionResultMismatch,
                message: "A source action returned an interaction result."
            )
        }
        return view
    }

    @discardableResult
    public func applyInteraction(
        _ transaction: ProjectInteractionTransaction
    ) async throws -> ProjectViewSnapshot {
        let result = try await perform(.interaction(transaction))
        guard case .interaction(_, let view) = result else {
            throw ProjectWorkspaceActionError(
                code: .actionResultMismatch,
                message: "An interaction action returned a source result."
            )
        }
        return view
    }

    @discardableResult
    public func perform(
        _ action: ProjectWorkspaceAction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectWorkspaceActionResult {
        switch action {
        case .source(let transaction):
            let commit = try await project.commit(
                transaction,
                operationGuard: operationGuard
            )
            let exactView: ProjectViewSnapshot
            do {
                exactView = try await buildExactViewAndPublishIfNewer(commit.state)
            } catch {
                throw ProjectWorkspacePostCommitError(
                    stage: .viewProjection,
                    commit: .source(commit),
                    message: "The source mutation committed, but its project view could not be built: \(error)."
                )
            }
            return .source(commit: commit, view: exactView)
        case .interaction(let transaction):
            let commit = try await project.applyInteraction(
                transaction,
                operationGuard: operationGuard
            )
            let exactView: ProjectViewSnapshot
            do {
                exactView = try await buildExactViewAndPublishIfNewer(commit.state)
            } catch {
                throw ProjectWorkspacePostCommitError(
                    stage: .viewProjection,
                    commit: .interaction(commit),
                    message: "The interaction mutation committed, but its project view could not be built: \(error)."
                )
            }
            return .interaction(commit: commit, view: exactView)
        }
    }

    /// Executes full project staging without publishing authority or a view snapshot.
    public func preview(
        _ action: ProjectWorkspaceAction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectWorkspacePreviewResult {
        switch action {
        case .source(let transaction):
            return .source(
                try await project.previewSource(
                    transaction,
                    operationGuard: operationGuard
                )
            )
        case .interaction(let transaction):
            return .interaction(
                try await project.previewInteraction(
                    transaction,
                    operationGuard: operationGuard
                )
            )
        }
    }

    /// Executes one previously dispatched domain plan through the project authority.
    public func execute(
        _ plan: ProjectDomainCommandPlan,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> DomainExecutionResult {
        switch plan {
        case .source(let action), .interaction(let action):
            return try await executeDomainMutation(
                action,
                operationGuard: operationGuard
            )
        case .read(let read):
            return try await executeDomainRead(
                read,
                operationGuard: operationGuard
            )
        }
    }

    /// Executes Automation through the same project authority used by UI actions.
    public func executeAutomation(
        _ batch: AutomationBatch,
        dryRun: Bool = false
    ) async throws -> ProjectWorkspaceAutomationResult {
        try await executeAutomation(
            batch,
            from: try currentInteractionCoordinates(),
            dryRun: dryRun
        )
    }

    /// Executes from the exact project coordinates captured by the caller.
    public func executeAutomation(
        _ batch: AutomationBatch,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {},
        dryRun: Bool = false
    ) async throws -> ProjectWorkspaceAutomationResult {
        try operationGuard()
        let prepared = try automationBatchPlanner.prepare(
            batch,
            in: AutomationPlanningContext(
                document: snapshot.document.document,
                generation: snapshot.documentGeneration,
                transactionRevision: snapshot.transactionRevision,
                publicationSequence: snapshot.publicationSequence,
                selection: snapshot.selection,
                workspaceState: snapshot.workspaceState,
                objectRegistry: snapshot.objectRegistry,
                evaluationSnapshot: snapshot.evaluationSnapshot,
                currentEvaluation: snapshot.cadInteraction
            )
        )
        switch prepared.effect {
        case .sourceMutation:
            let action = ProjectWorkspaceAction.source(
                try ProjectSourceTransaction(
                    name: "automationBatch.source",
                    automation: prepared,
                    expectedProjectID: snapshot.projectID,
                    expectedTransactionRevision: snapshot.transactionRevision,
                    expectedPublicationSequence: snapshot.publicationSequence
                )
            )
            if dryRun {
                guard case .source(let preview) = try await self.preview(
                    action,
                    operationGuard: operationGuard
                ),
                      let execution = preview.automationExecution else {
                    throw automationResultMismatch()
                }
                return ProjectWorkspaceAutomationResult(
                    execution: execution,
                    view: snapshot,
                    didPublish: false
                )
            }
            guard case .source(let commit, let view) = try await perform(
                action,
                operationGuard: operationGuard
            ),
                  let execution = commit.automationExecution else {
                throw automationResultMismatch()
            }
            return ProjectWorkspaceAutomationResult(
                execution: execution,
                view: view,
                didPublish: true
            )
        case .workspaceMutation:
            let action = ProjectWorkspaceAction.interaction(
                try ProjectInteractionTransaction(
                    automation: prepared,
                    expectedProjectID: snapshot.projectID,
                    expectedTransactionRevision: snapshot.transactionRevision,
                    expectedPublicationSequence: snapshot.publicationSequence
                )
            )
            if dryRun {
                guard case .interaction(let preview) = try await self.preview(
                    action,
                    operationGuard: operationGuard
                ),
                      let execution = preview.automationExecution else {
                    throw automationResultMismatch()
                }
                return ProjectWorkspaceAutomationResult(
                    execution: execution,
                    view: snapshot,
                    didPublish: false
                )
            }
            guard case .interaction(let commit, let view) = try await perform(
                action,
                operationGuard: operationGuard
            ),
                  let execution = commit.automationExecution else {
                throw automationResultMismatch()
            }
            return ProjectWorkspaceAutomationResult(
                execution: execution,
                view: view,
                didPublish: true
            )
        case .readOnly:
            let execution = try await project.executeReadOnlyAutomation(
                prepared,
                expectedProjectID: snapshot.projectID,
                expectedPublicationSequence: snapshot.publicationSequence,
                operationGuard: operationGuard
            )
            return ProjectWorkspaceAutomationResult(
                execution: execution,
                view: snapshot,
                didPublish: false
            )
        }
    }

    @discardableResult
    public func applySelection(
        _ operation: ProjectSelectionOperation
    ) async throws -> ProjectViewSnapshot {
        try await applySelection(
            operation,
            from: try currentInteractionCoordinates()
        )
    }

    @discardableResult
    public func applySelection(
        _ operation: ProjectSelectionOperation,
        from expected: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectViewSnapshot {
        let transaction = try ProjectInteractionTransaction(
            selection: operation,
            expectedProjectID: expected.projectID,
            expectedTransactionRevision: expected.transactionRevision,
            expectedPublicationSequence: expected.publicationSequence
        )
        let result = try await perform(
            .interaction(transaction),
            operationGuard: operationGuard
        )
        guard case .interaction(_, let view) = result else {
            throw ProjectWorkspaceActionError(
                code: .actionResultMismatch,
                message: "A selection action returned a source result."
            )
        }
        return view
    }

    @discardableResult
    public func applyWorkspace(
        _ commands: [WorkspaceCommand]
    ) async throws -> ProjectViewSnapshot {
        let expected = try currentInteractionCoordinates()
        let transaction = try ProjectInteractionTransaction(
            workspaceCommands: commands,
            expectedProjectID: expected.projectID,
            expectedTransactionRevision: expected.transactionRevision,
            expectedPublicationSequence: expected.publicationSequence
        )
        return try await applyInteraction(transaction)
    }

    @discardableResult
    public func applyWorkspace(
        _ command: WorkspaceCommand
    ) async throws -> ProjectViewSnapshot {
        try await applyWorkspace([command])
    }

    @discardableResult
    public func undo() async throws -> ProjectViewSnapshot {
        try await undo(from: try currentInteractionCoordinates())
    }

    @discardableResult
    public func undo(
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectViewSnapshot {
        let state = try await project.undo(
                expectedProjectID: snapshot.projectID,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedPublicationSequence: snapshot.publicationSequence,
                operationGuard: operationGuard
            )
        do {
            return try await buildExactViewAndPublishIfNewer(state)
        } catch {
            throw ProjectWorkspacePostCommitError(
                stage: .viewProjection,
                commit: .undo(state),
                message: "Undo committed, but its project view could not be built: \(error)."
            )
        }
    }

    @discardableResult
    public func redo() async throws -> ProjectViewSnapshot {
        try await redo(from: try currentInteractionCoordinates())
    }

    @discardableResult
    public func redo(
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectViewSnapshot {
        let state = try await project.redo(
                expectedProjectID: snapshot.projectID,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedPublicationSequence: snapshot.publicationSequence,
                operationGuard: operationGuard
            )
        do {
            return try await buildExactViewAndPublishIfNewer(state)
        } catch {
            throw ProjectWorkspacePostCommitError(
                stage: .viewProjection,
                commit: .redo(state),
                message: "Redo committed, but its project view could not be built: \(error)."
            )
        }
    }

    @discardableResult
    public func load(from url: URL) async throws -> ProjectViewSnapshot {
        let revision: DocumentTransactionRevision
        if let view {
            revision = view.transactionRevision
        } else {
            revision = await project.currentTransactionRevision()
        }
        return try await publish(
            try await project.load(
                from: url,
                expectedTransactionRevision: revision
            )
        )
    }

    @discardableResult
    public func save(to url: URL) async throws -> ProjectViewSnapshot {
        let revision = try currentTransactionRevision()
        _ = try await project.save(
            to: url,
            expectedTransactionRevision: revision
        )
        return try await publish(try await project.currentState())
    }

    @discardableResult
    func publish(_ state: ProjectStateSnapshot) async throws -> ProjectViewSnapshot {
        try await buildExactViewAndPublishIfNewer(state)
    }

    private func buildExactViewAndPublishIfNewer(
        _ state: ProjectStateSnapshot
    ) async throws -> ProjectViewSnapshot {
        let builder = viewBuilder
        let candidate = try await Task.detached(priority: nil) {
            try builder.build(from: state)
        }.value
        if let view {
            if candidate.publicationSequence > view.publicationSequence {
                self.view = candidate
            }
        } else {
            self.view = candidate
        }
        return candidate
    }

    private func currentInteractionCoordinates() throws -> ProjectViewSnapshot {
        guard let view else {
            throw ProjectWorkspaceActionError(
                code: .snapshotUnavailable,
                message: "The project workspace has no published view snapshot."
            )
        }
        return view
    }

    private func currentTransactionRevision() throws -> DocumentTransactionRevision {
        guard let view else {
            throw ProjectWorkspaceActionError(
                code: .snapshotUnavailable,
                message: "The project workspace has no published view snapshot."
            )
        }
        return view.transactionRevision
    }

    private func automationResultMismatch() -> ProjectWorkspaceActionError {
        ProjectWorkspaceActionError(
            code: .actionResultMismatch,
            message: "A project Automation action did not return its staged execution result."
        )
    }

    private func executeDomainMutation(
        _ plan: ProjectDomainCommandActionPlan,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> DomainExecutionResult {
        try requireDomainMutationRoute(plan)
        let record: DomainCommandExecutionRecord
        let currentGeneration: DocumentGeneration
        let currentTransactionRevision: DocumentTransactionRevision
        if plan.dryRun {
            let result = try await preview(
                plan.action,
                operationGuard: operationGuard
            )
            record = domainRecord(for: result, plan: plan)
            currentGeneration = plan.baseGeneration
            currentTransactionRevision = plan.baseTransactionRevision
        } else {
            let result = try await perform(
                plan.action,
                operationGuard: operationGuard
            )
            record = domainRecord(for: result, plan: plan)
            currentGeneration = result.view.documentGeneration
            currentTransactionRevision = result.view.transactionRevision
            do {
                return try domainResultProjector.project(
                    resolution: plan.resolution,
                    record: record,
                    currentGeneration: currentGeneration,
                    currentTransactionRevision: currentTransactionRevision
                )
            } catch {
                throw ProjectWorkspacePostCommitError(
                    stage: .domainResultProjection,
                    commit: result.commit,
                    message: "The domain mutation committed, but its result could not be projected: \(error)."
                )
            }
        }
        return try domainResultProjector.project(
            resolution: plan.resolution,
            record: record,
            currentGeneration: currentGeneration,
            currentTransactionRevision: currentTransactionRevision
        )
    }

    private func executeDomainRead(
        _ plan: ProjectDomainCommandReadPlan,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> DomainExecutionResult {
        try operationGuard()
        let initialState = try await project.currentState()
        try requireDomainReadCoordinates(plan, state: initialState)
        try Task.checkCancellation()
        let record: DomainCommandExecutionRecord
        switch plan.resolution.plan {
        case .query(let query):
            let request = plan.resolution.request
            let context = DomainQueryContext(
                document: initialState.document,
                generation: initialState.documentGeneration,
                objectRegistry: initialState.objectRegistry,
                currentEvaluation: initialState.cadInteraction,
                evaluationSnapshot: initialState.evaluationSnapshot
            )
            let queryTask = Task.detached(priority: nil) {
                try Task.checkCancellation()
                let result = try query.execute(request, in: context)
                try result.validate()
                try Task.checkCancellation()
                return result
            }
            let result = try await withTaskCancellationHandler {
                try await queryTask.value
            } onCancel: {
                queryTask.cancel()
            }
            try Task.checkCancellation()
            let currentState = try await project.currentState()
            try operationGuard()
            try requireDomainReadCoordinates(plan, state: currentState)
            record = DomainCommandExecutionRecord(
                message: result.message,
                baseGeneration: plan.baseGeneration,
                generation: plan.baseGeneration,
                proposedGeneration: plan.baseGeneration,
                baseTransactionRevision: plan.baseTransactionRevision,
                transactionRevision: plan.baseTransactionRevision,
                proposedTransactionRevision: plan.baseTransactionRevision,
                didMutate: false,
                wouldMutate: false,
                diagnostics: result.diagnostics,
                validationFindings: result.validationFindings,
                validationRegions: result.validationRegions,
                payload: result.payload
            )
        case .automationBatch:
            guard let automation = plan.preparedAutomation else {
                throw ProjectDomainCommandDispatchError(
                    code: .actionRouteMismatch,
                    message: "A read-only Automation domain plan is missing its prepared batch."
                )
            }
            let execution = try await project.executeReadOnlyAutomation(
                automation,
                expectedProjectID: plan.baseProjectID,
                expectedPublicationSequence: plan.basePublicationSequence,
                operationGuard: operationGuard
            )
            record = DomainCommandExecutionRecord(
                baseGeneration: execution.baseGeneration,
                generation: execution.baseGeneration,
                proposedGeneration: execution.baseGeneration,
                baseTransactionRevision: execution.baseTransactionRevision,
                transactionRevision: execution.baseTransactionRevision,
                proposedTransactionRevision: execution.baseTransactionRevision,
                didMutate: false,
                wouldMutate: false,
                diagnostics: execution.diagnostics,
                automationResults: execution.results
            )
        case .documentTransaction:
            throw ProjectDomainCommandDispatchError(
                code: .actionRouteMismatch,
                message: "A domain document transaction cannot execute through the read route."
            )
        }
        try operationGuard()
        return try domainResultProjector.project(
            resolution: plan.resolution,
            record: record,
            currentGeneration: plan.baseGeneration,
            currentTransactionRevision: plan.baseTransactionRevision
        )
    }

    private func domainRecord(
        for result: ProjectWorkspaceActionResult,
        plan: ProjectDomainCommandActionPlan
    ) -> DomainCommandExecutionRecord {
        switch result {
        case .source(let commit, let view):
            return sourceDomainRecord(
                proposedGeneration: view.documentGeneration,
                proposedTransactionRevision: view.transactionRevision,
                didMutate: view.documentGeneration != plan.baseGeneration,
                commandResults: commit.commandResults,
                automationExecution: commit.automationExecution,
                finalDiagnostics: commit.diagnostics,
                plan: plan
            )
        case .interaction(let commit, _):
            return interactionDomainRecord(
                wouldMutate: commit.automationExecution?.results.contains(where: \.didMutate)
                    ?? false,
                didMutate: commit.automationExecution?.didCommit == true,
                automationExecution: commit.automationExecution,
                plan: plan
            )
        }
    }

    private func domainRecord(
        for result: ProjectWorkspacePreviewResult,
        plan: ProjectDomainCommandActionPlan
    ) -> DomainCommandExecutionRecord {
        switch result {
        case .source(let preview):
            return sourceDomainRecord(
                proposedGeneration: preview.proposedDocumentGeneration,
                proposedTransactionRevision: preview.proposedTransactionRevision,
                didMutate: false,
                commandResults: preview.commandResults,
                automationExecution: preview.automationExecution,
                finalDiagnostics: preview.diagnostics,
                plan: plan
            )
        case .interaction(let preview):
            return interactionDomainRecord(
                wouldMutate: preview.wouldPublish,
                didMutate: false,
                automationExecution: preview.automationExecution,
                plan: plan
            )
        }
    }

    private func sourceDomainRecord(
        proposedGeneration: DocumentGeneration,
        proposedTransactionRevision: DocumentTransactionRevision,
        didMutate: Bool,
        commandResults: [CommandExecutionResult],
        automationExecution: AutomationBatchExecution?,
        finalDiagnostics: [EditorDiagnostic],
        plan: ProjectDomainCommandActionPlan
    ) -> DomainCommandExecutionRecord {
        let domainTransaction: DomainDocumentTransaction?
        if case .documentTransaction(let transaction) = plan.resolution.plan {
            domainTransaction = transaction
        } else {
            domainTransaction = nil
        }
        let visibleCommandResults = domainTransaction.map { transaction in
            Array(commandResults.prefix(transaction.sourceCommands.count))
        } ?? commandResults
        let automationResults = automationExecution?.results ?? []
        let wouldMutate = automationExecution?.results.contains(where: \.didMutate)
            ?? (proposedGeneration != plan.baseGeneration)
        return DomainCommandExecutionRecord(
            baseGeneration: plan.baseGeneration,
            generation: didMutate ? proposedGeneration : plan.baseGeneration,
            proposedGeneration: proposedGeneration,
            baseTransactionRevision: plan.baseTransactionRevision,
            transactionRevision: didMutate
                ? proposedTransactionRevision
                : plan.baseTransactionRevision,
            proposedTransactionRevision: proposedTransactionRevision,
            didMutate: didMutate,
            wouldMutate: wouldMutate,
            diagnostics: EditorDiagnostic.stableMerged([
                visibleCommandResults.flatMap(\.diagnostics),
                automationExecution?.diagnostics ?? [],
                finalDiagnostics,
            ]),
            automationResults: automationResults,
            sourceCommandResults: visibleCommandResults,
            commandName: domainTransaction?.name,
            payload: domainTransaction?.resultPayload
        )
    }

    private func interactionDomainRecord(
        wouldMutate: Bool,
        didMutate: Bool,
        automationExecution: AutomationBatchExecution?,
        plan: ProjectDomainCommandActionPlan
    ) -> DomainCommandExecutionRecord {
        DomainCommandExecutionRecord(
            baseGeneration: plan.baseGeneration,
            generation: plan.baseGeneration,
            proposedGeneration: plan.baseGeneration,
            baseTransactionRevision: plan.baseTransactionRevision,
            transactionRevision: plan.baseTransactionRevision,
            proposedTransactionRevision: plan.baseTransactionRevision,
            didMutate: didMutate,
            wouldMutate: wouldMutate,
            diagnostics: automationExecution?.diagnostics ?? [],
            automationResults: automationExecution?.results ?? []
        )
    }

    private func requireDomainReadCoordinates(
        _ plan: ProjectDomainCommandReadPlan,
        state: ProjectStateSnapshot
    ) throws {
        guard state.document.projectID == plan.baseProjectID else {
            throw ProjectDomainCommandDispatchError(
                code: .projectMismatch,
                message: "The domain read plan belongs to a different project."
            )
        }
        guard state.documentGeneration == plan.baseGeneration else {
            throw ProjectDomainCommandDispatchError(
                code: .generationMismatch,
                message: "The domain read plan no longer matches the project generation."
            )
        }
        guard state.transactionRevision == plan.baseTransactionRevision else {
            throw ProjectDomainCommandDispatchError(
                code: .transactionRevisionMismatch,
                message: "The domain read plan no longer matches the project transaction revision."
            )
        }
        guard state.publicationSequence == plan.basePublicationSequence else {
            throw ProjectDomainCommandDispatchError(
                code: .publicationSequenceMismatch,
                message: "The domain read plan no longer matches the project publication sequence."
            )
        }
        guard state.workspaceState.revision == plan.baseWorkspaceRevision else {
            throw ProjectDomainCommandDispatchError(
                code: .workspaceRevisionMismatch,
                message: "The domain read plan no longer matches the project workspace revision."
            )
        }
    }

    private func requireDomainMutationRoute(
        _ plan: ProjectDomainCommandActionPlan
    ) throws {
        switch (plan.route, plan.action) {
        case (.source, .source), (.workspace, .interaction):
            return
        case (.source, .interaction), (.workspace, .source),
             (.readOnly, _), (.query, _):
            throw ProjectDomainCommandDispatchError(
                code: .actionRouteMismatch,
                message: "The domain command route does not match its project mutation action."
            )
        }
    }
}
