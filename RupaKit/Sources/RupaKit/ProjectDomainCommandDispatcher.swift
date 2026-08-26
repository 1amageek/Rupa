import RupaAutomation
import RupaCore
import RupaDomainFoundation

/// Lowers domain requests from one immutable view into the project operation boundary.
///
/// Query and read-only plans remain read plans. Only source and workspace effects
/// produce actions accepted by `ProjectWorkspace.perform`.
public struct ProjectDomainCommandDispatcher: Sendable {
    private let planResolver: any DomainCommandPlanResolving
    private let actionPlanner: any ProjectWorkspaceActionPlanning
    private let automationBatchPlanner: any AutomationBatchPlanning

    public init(
        registry: DomainRegistry,
        actionPlanner: any ProjectWorkspaceActionPlanning =
            DefaultProjectWorkspaceActionPlanner(),
        automationBatchPlanner: any AutomationBatchPlanning =
            DefaultAutomationBatchPlanner()
    ) {
        self.planResolver = DefaultDomainCommandPlanResolver(registry: registry)
        self.actionPlanner = actionPlanner
        self.automationBatchPlanner = automationBatchPlanner
    }

    public init(
        planResolver: any DomainCommandPlanResolving,
        actionPlanner: any ProjectWorkspaceActionPlanning =
            DefaultProjectWorkspaceActionPlanner(),
        automationBatchPlanner: any AutomationBatchPlanning =
            DefaultAutomationBatchPlanner()
    ) {
        self.planResolver = planResolver
        self.actionPlanner = actionPlanner
        self.automationBatchPlanner = automationBatchPlanner
    }

    public func dispatch(
        _ request: DomainCommandRequest,
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectDomainCommandPlan {
        let resolution = try planResolver.resolve(request)
        try validateSnapshotCoordinates(resolution, against: snapshot)

        switch resolution.plan {
        case .query:
            return .read(readPlan(resolution, from: snapshot))
        case .automationBatch(let batch):
            guard resolution.route != .readOnly else {
                let prepared = try automationBatchPlanner.prepare(
                    batch,
                    in: automationPlanningContext(from: snapshot)
                )
                return .read(
                    readPlan(
                        resolution,
                        from: snapshot,
                        preparedAutomation: prepared
                    )
                )
            }
            let action = try actionPlanner.automation(batch, from: snapshot)
            return try mutationPlan(
                action,
                resolution: resolution,
                snapshot: snapshot
            )
        case .documentTransaction(let transaction):
            let action = try actionPlanner.source(
                name: transaction.name,
                commands: transaction.executionEditorCommands(
                    namespace: resolution.request.namespace
                ),
                geometrySourceCommands: [],
                from: snapshot
            )
            return try mutationPlan(
                action,
                resolution: resolution,
                snapshot: snapshot
            )
        }
    }

    private func validateSnapshotCoordinates(
        _ resolution: DomainCommandPlanResolution,
        against snapshot: ProjectViewSnapshot
    ) throws {
        if let expectedGeneration = resolution.expectedGeneration,
           expectedGeneration != snapshot.documentGeneration {
            throw ProjectDomainCommandDispatchError(
                code: .generationMismatch,
                message: "Domain command expected generation \(expectedGeneration.value), but the project view is at generation \(snapshot.documentGeneration.value)."
            )
        }
        if let expectedTransactionRevision = resolution.expectedTransactionRevision,
           expectedTransactionRevision != snapshot.transactionRevision {
            throw ProjectDomainCommandDispatchError(
                code: .transactionRevisionMismatch,
                message: "Domain command expected transaction revision \(expectedTransactionRevision.value), but the project view is at revision \(snapshot.transactionRevision.value)."
            )
        }
        guard case .automationBatch(let batch) = resolution.plan,
              let expectedWorkspaceRevision = batch.expectedWorkspaceRevision else {
            return
        }
        guard expectedWorkspaceRevision == snapshot.workspaceState.revision else {
            throw ProjectDomainCommandDispatchError(
                code: .workspaceRevisionMismatch,
                message: "Domain command expected workspace revision \(expectedWorkspaceRevision.value), but the project view is at revision \(snapshot.workspaceState.revision.value)."
            )
        }
    }

    private func mutationPlan(
        _ action: ProjectWorkspaceAction,
        resolution: DomainCommandPlanResolution,
        snapshot: ProjectViewSnapshot
    ) throws -> ProjectDomainCommandPlan {
        try validateActionCoordinates(action, against: snapshot)
        switch resolution.route {
        case .source:
            guard case .source = action else {
                throw actionRouteMismatch(
                    expected: .source,
                    actual: action
                )
            }
            return .source(
                ProjectDomainCommandActionPlan(
                    action: action,
                    resolution: resolution,
                    baseProjectID: snapshot.projectID,
                    baseGeneration: snapshot.documentGeneration,
                    baseTransactionRevision: snapshot.transactionRevision,
                    basePublicationSequence: snapshot.publicationSequence,
                    baseWorkspaceRevision: snapshot.workspaceState.revision
                )
            )
        case .workspace:
            guard case .interaction = action else {
                throw actionRouteMismatch(
                    expected: .workspace,
                    actual: action
                )
            }
            return .interaction(
                ProjectDomainCommandActionPlan(
                    action: action,
                    resolution: resolution,
                    baseProjectID: snapshot.projectID,
                    baseGeneration: snapshot.documentGeneration,
                    baseTransactionRevision: snapshot.transactionRevision,
                    basePublicationSequence: snapshot.publicationSequence,
                    baseWorkspaceRevision: snapshot.workspaceState.revision
                )
            )
        case .readOnly, .query:
            throw ProjectDomainCommandDispatchError(
                code: .actionRouteMismatch,
                message: "Read-only domain plans cannot produce project mutation actions."
            )
        }
    }

    private func validateActionCoordinates(
        _ action: ProjectWorkspaceAction,
        against snapshot: ProjectViewSnapshot
    ) throws {
        switch action {
        case .source(let transaction):
            try validateTransactionCoordinates(
                projectID: transaction.expectedProjectID,
                transactionRevision: transaction.expectedTransactionRevision,
                publicationSequence: transaction.expectedPublicationSequence,
                against: snapshot
            )
            guard case .automation(let prepared) = transaction.mutation else {
                return
            }
            try validateAutomationCoordinates(prepared, against: snapshot)
        case .interaction(let transaction):
            try validateTransactionCoordinates(
                projectID: transaction.expectedProjectID,
                transactionRevision: transaction.expectedTransactionRevision,
                publicationSequence: transaction.expectedPublicationSequence,
                against: snapshot
            )
            guard case .automation(let prepared) = transaction.mutation else {
                return
            }
            try validateAutomationCoordinates(prepared, against: snapshot)
        }
    }

    private func validateTransactionCoordinates(
        projectID: ProjectID,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        against snapshot: ProjectViewSnapshot
    ) throws {
        guard projectID == snapshot.projectID else {
            throw ProjectDomainCommandDispatchError(
                code: .projectMismatch,
                message: "The planned project action belongs to a different project."
            )
        }
        guard transactionRevision == snapshot.transactionRevision else {
            throw ProjectDomainCommandDispatchError(
                code: .transactionRevisionMismatch,
                message: "The planned project action does not match the project view transaction revision."
            )
        }
        guard publicationSequence == snapshot.publicationSequence else {
            throw ProjectDomainCommandDispatchError(
                code: .publicationSequenceMismatch,
                message: "The planned project action does not match the project view publication sequence."
            )
        }
    }

    private func validateAutomationCoordinates(
        _ prepared: PreparedAutomationBatch,
        against snapshot: ProjectViewSnapshot
    ) throws {
        guard prepared.batch.expectedGeneration == snapshot.documentGeneration else {
            throw ProjectDomainCommandDispatchError(
                code: .generationMismatch,
                message: "The planned Automation action does not match the project view generation."
            )
        }
        guard prepared.batch.expectedTransactionRevision == snapshot.transactionRevision else {
            throw ProjectDomainCommandDispatchError(
                code: .transactionRevisionMismatch,
                message: "The planned Automation action does not match the project view transaction revision."
            )
        }
        guard prepared.batch.expectedWorkspaceRevision == snapshot.workspaceState.revision else {
            throw ProjectDomainCommandDispatchError(
                code: .workspaceRevisionMismatch,
                message: "The planned Automation action does not match the project view workspace revision."
            )
        }
    }

    private func readPlan(
        _ resolution: DomainCommandPlanResolution,
        from snapshot: ProjectViewSnapshot,
        preparedAutomation: PreparedAutomationBatch? = nil
    ) -> ProjectDomainCommandReadPlan {
        ProjectDomainCommandReadPlan(
            resolution: resolution,
            baseProjectID: snapshot.projectID,
            baseGeneration: snapshot.documentGeneration,
            baseTransactionRevision: snapshot.transactionRevision,
            basePublicationSequence: snapshot.publicationSequence,
            baseWorkspaceRevision: snapshot.workspaceState.revision,
            preparedAutomation: preparedAutomation
        )
    }

    private func automationPlanningContext(
        from snapshot: ProjectViewSnapshot
    ) -> AutomationPlanningContext {
        AutomationPlanningContext(
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
    }

    private func actionRouteMismatch(
        expected: DomainCommandRoute,
        actual: ProjectWorkspaceAction
    ) -> ProjectDomainCommandDispatchError {
        let actualRoute: String
        switch actual {
        case .source:
            actualRoute = DomainCommandRoute.source.rawValue
        case .interaction:
            actualRoute = DomainCommandRoute.workspace.rawValue
        }
        return ProjectDomainCommandDispatchError(
            code: .actionRouteMismatch,
            message: "Domain command route \(expected.rawValue) was lowered to incompatible project action route \(actualRoute)."
        )
    }
}
