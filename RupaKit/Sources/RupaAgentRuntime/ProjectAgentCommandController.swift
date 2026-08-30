import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaKit
import RupaProject

/// Routes Agent requests through the same project authority observed by the UI.
@MainActor
public final class ProjectAgentCommandController: AgentRequestHandling {
    public var name: String

    private let registry: ProjectWorkspaceRegistry
    private let domainRegistry: DomainRegistry
    private let snapshotReadExecutor: ProjectAgentSnapshotReadExecutor
    private let exportExecutor: ProjectAgentExportExecutor
    private let errorMapper: ProjectAgentErrorMapper

    public init(
        name: String = "Rupa Agent",
        registry: ProjectWorkspaceRegistry = ProjectWorkspaceRegistry(),
        domainRegistry: DomainRegistry = DomainRegistry(),
        snapshotReadExecutor: ProjectAgentSnapshotReadExecutor =
            ProjectAgentSnapshotReadExecutor(),
        exportExecutor: ProjectAgentExportExecutor = ProjectAgentExportExecutor(),
        errorMapper: ProjectAgentErrorMapper = ProjectAgentErrorMapper()
    ) {
        self.name = name
        self.registry = registry
        self.domainRegistry = domainRegistry
        self.snapshotReadExecutor = snapshotReadExecutor
        self.exportExecutor = exportExecutor
        self.errorMapper = errorMapper
    }

    public func capabilityDescriptors() -> [AgentCapabilityDescriptor] {
        AgentCapabilityCatalog.descriptors(domainRegistry: domainRegistry)
    }

    public func capabilityRegistry() throws -> CapabilityRegistry {
        try AgentCapabilityCatalog.capabilityRegistry(domainRegistry: domainRegistry)
    }

    @discardableResult
    public func register(
        workspace: ProjectWorkspace,
        path: URL? = nil,
        id: UUID = UUID()
    ) async throws -> UUID {
        try await registry.register(workspace: workspace, path: path, id: id)
    }

    public func unregister(id: UUID) async {
        await registry.unregister(id: id)
    }

    public func updatePath(id: UUID, path: URL?) async throws {
        try await registry.updatePath(id: id, path: path)
    }

    public func handle(_ request: AgentRequest) async -> AgentResponse {
        do {
            return try await execute(request)
        } catch let error as ProjectWorkspacePostCommitError {
            let recoveryFailure = await recoverCommittedView(
                for: request,
                error: error
            )
            return .committedMutation(
                committedMutationOutcome(
                    for: error,
                    request: request,
                    recoveryFailure: recoveryFailure
                )
            )
        } catch {
            return .failure(errorMapper.editorError(for: error))
        }
    }

    private func committedMutationOutcome(
        for error: ProjectWorkspacePostCommitError,
        request: AgentRequest,
        recoveryFailure: String?
    ) -> AgentCommittedMutationOutcome {
        let state = error.commit.state
        let mutation: AgentCommittedMutationOutcome.Mutation
        switch error.commit {
        case .source:
            mutation = .source
        case .interaction:
            mutation = .interaction
        case .undo:
            mutation = .undo
        case .redo:
            mutation = .redo
        case .evaluation:
            mutation = .evaluation
        }
        let stage: AgentCommittedMutationOutcome.Stage
        switch error.stage {
        case .viewProjection:
            stage = .viewProjection
        case .domainResultProjection:
            stage = .domainResultProjection
        }
        let message: String
        if let recoveryFailure {
            message = "\(error.message) Automatic view recovery also failed: \(recoveryFailure)"
        } else {
            message = error.message
        }
        return AgentCommittedMutationOutcome(
            stage: stage,
            mutation: mutation,
            requestMethod: request.methodName,
            projectID: state.document.projectID,
            documentGeneration: state.documentGeneration,
            transactionRevision: state.transactionRevision,
            publicationSequence: state.publicationSequence,
            workspaceRevision: state.workspaceState.revision,
            message: message
        )
    }

    private func recoverCommittedView(
        for request: AgentRequest,
        error: ProjectWorkspacePostCommitError
    ) async -> String? {
        guard let sessionID = request.projectSessionID else {
            return "The committed request has no project session ID."
        }
        do {
            let lease = try registry.recoveryLease(
                id: sessionID,
                committedProjectID: error.commit.state.document.projectID
            )
            _ = try await lease.workspace.recoverCommittedView(
                error.commit.state,
                operationGuard: lease.operationGuard
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func execute(_ request: AgentRequest) async throws -> AgentResponse {
        switch request {
        case .capabilities:
            return .capabilities(capabilityDescriptors())
        case .capabilityRegistry:
            do {
                return .capabilityRegistry(try capabilityRegistry().sortedDescriptors())
            } catch let error as CapabilityRegistryError {
                throw EditorError(code: .commandFailed, message: error.message)
            }
        case .status:
            return .status(
                AgentStatus(
                    running: true,
                    sessionCount: try await registry.reconciledCount()
                )
            )
        case .sessions:
            return .sessions(try await registry.summaries())
        case .cadInteractionQualityAssessment:
            return .cadInteractionQualityAssessment(
                CADInteractionQualityAssessmentService().assess()
            )

        case .createDocument, .openDocument, .closeDocument, .save:
            throw EditorError(
                code: .commandUnsupported,
                message: "Application-owned file and window lifecycle is outside the Agent project route."
            )

        case .parameters,
             .measure,
             .selectionMeasurement,
             .resolveSnap,
             .constructionPlaneSummary,
             .sceneGraphSnapshot,
             .designDisplaySnapshot,
             .patternArraySummary,
             .meshSummary,
             .polySplineMeshAnalysis,
             .sketchEntitySummary,
             .sketchDimensionSummary,
             .selectionDimensionEvaluation,
             .curveAnalysis,
             .topologySummary,
             .sweepEvaluationPlan,
             .booleanEvaluationPlan,
             .objectDimensionSummary,
             .surfaceSourceSummary,
             .surfaceAnalysis,
             .surfaceFrames,
             .surfaceContinuitySummary,
             .surfaceBoundaryContinuityCompatibility:
            return try await executeSnapshotRead(request)

        case .meshCatalog(let request):
            return try await executeMeshCatalog(request)

        case .meshPage(let request):
            return try await executeMeshPage(request)

        case .meshNeighborhood(let request):
            return try await executeMeshNeighborhood(request)

        case .meshEdit(let request):
            return try await executeMeshEdit(request)

        case .makeEditable(let request):
            return try await executeMakeEditable(request)

        case .execute(
            let sessionID,
            let command,
            let expectedGeneration,
            let expectedWorkspaceRevision
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Agent command",
                snapshot: snapshot
            )
            if command.effect == .workspaceMutation {
                try requireWorkspaceRevision(
                    expectedWorkspaceRevision,
                    operation: "Workspace mutation",
                    snapshot: snapshot
                )
            }
            let result = try await workspace.executeAutomation(
                AutomationBatch(
                    commands: [command],
                    expectedGeneration: expectedGeneration,
                    expectedTransactionRevision: snapshot.transactionRevision,
                    expectedWorkspaceRevision: expectedWorkspaceRevision
                ),
                from: snapshot,
                operationGuard: lease.operationGuard
            )
            guard var commandResult = result.execution.results.first else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Agent command produced no result."
                )
            }
            commandResult.executionMetrics = result.execution.metrics
            return .command(commandResult)

        case .executeBatch(let sessionID, let batch):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                batch.expectedGeneration,
                operation: "Agent batch",
                snapshot: snapshot
            )
            let effect = try batch.validatedEffect()
            if effect == .workspaceMutation {
                try requireWorkspaceRevision(
                    batch.expectedWorkspaceRevision,
                    operation: "Workspace mutation batch",
                    snapshot: snapshot
                )
            }
            var coordinatedBatch = batch
            if coordinatedBatch.expectedTransactionRevision == nil {
                coordinatedBatch.expectedTransactionRevision = snapshot.transactionRevision
            }
            let result = try await workspace.executeAutomation(
                coordinatedBatch,
                from: snapshot,
                operationGuard: lease.operationGuard
            )
            return .batch(
                AgentBatchResult(
                    results: result.execution.results,
                    generation: result.view.documentGeneration,
                    workspaceRevision: result.view.workspaceState.revision,
                    dirty: result.view.isDirty,
                    metrics: result.execution.metrics
                )
            )

        case .executeDomain(let sessionID, let request):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            let plan = try ProjectDomainCommandDispatcher(registry: domainRegistry)
                .dispatch(request, from: snapshot)
            return .domainExecution(
                try await workspace.execute(
                    plan,
                    operationGuard: lease.operationGuard
                )
            )

        case .invokeCapability(
            let sessionID,
            let invocation,
            let expectedWorkspaceRevision
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            let descriptor = try capabilityRegistry().descriptor(
                for: invocation.capabilityID,
                version: invocation.version
            )
            let agentName = String(
                invocation.capabilityID.rawValue.dropFirst("agent.".count)
            )
            guard invocation.capabilityID.rawValue.hasPrefix("agent."),
                  let agentDescriptor = capabilityDescriptors().first(where: {
                      $0.name == agentName
                  }) else {
                throw AgentCapabilityExecutionError(
                    code: .unsupportedRoute,
                    message: "Capability \(invocation.capabilityID.rawValue) is not an Agent capability."
                )
            }
            return .capabilityExecution(
                try await ProjectAgentCapabilityInvocationExecutor(
                    domainRegistry: domainRegistry
                ).execute(
                    invocation,
                    descriptor: descriptor,
                    agentDescriptor: agentDescriptor,
                    sessionID: sessionID,
                    expectedWorkspaceRevision: expectedWorkspaceRevision,
                    workspace: workspace,
                    snapshot: snapshot,
                    operationGuard: lease.operationGuard
                )
            )

        case .resetDocument:
            throw EditorError(
                code: .commandUnsupported,
                message: "Project reset is unavailable until reset preserves the registered project identity."
            )

        case .setParameterExpression(
            let sessionID,
            let name,
            let expression,
            let kind,
            let defaults,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Parameter expression",
                snapshot: snapshot
            )
            let parsed = try ParameterExpressionParser().parseForUpsert(
                expression,
                parameterName: name,
                parameters: snapshot.document.document.cadDocument.parameters,
                targetKind: kind,
                defaults: expressionDefaults(defaults, snapshot: snapshot)
            )
            return try await executeSingleCommand(
                .upsertParameter(name: name, expression: parsed, kind: kind),
                expectedGeneration: expectedGeneration,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .setObjectDimensionExpression(
            let sessionID,
            let target,
            let kind,
            let expression,
            let defaults,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Object dimension expression",
                snapshot: snapshot
            )
            let parsed = try parseDimensionExpression(
                expression,
                targetKind: .length,
                defaults: defaults,
                snapshot: snapshot
            )
            return try await executeSingleCommand(
                .setObjectDimension(target: target, kind: kind, value: parsed),
                expectedGeneration: expectedGeneration,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .setSketchEntityDimensionExpression(
            let sessionID,
            let target,
            let kind,
            let expression,
            let defaults,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Sketch dimension expression",
                snapshot: snapshot
            )
            let parsed = try parseDimensionExpression(
                expression,
                targetKind: kind.quantityKind,
                defaults: defaults,
                snapshot: snapshot
            )
            return try await executeSingleCommand(
                .setSketchEntityDimension(target: target, kind: kind, value: parsed),
                expectedGeneration: expectedGeneration,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .setSelectionDimensionTargetExpression(
            let sessionID,
            let id,
            let expression,
            let defaults,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Selection dimension expression",
                snapshot: snapshot
            )
            guard let selectionDimension = snapshot.document.document.cadDocument
                .selectionDimensions.first(where: { $0.id == id }) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selection dimension target expression requires an existing selection dimension."
                )
            }
            let parsed = try parseDimensionExpression(
                expression,
                targetKind: selectionDimension.kind.quantityKind,
                defaults: defaults,
                snapshot: snapshot
            )
            return try await executeSingleCommand(
                .setSelectionDimensionTarget(id: id, target: parsed),
                expectedGeneration: expectedGeneration,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .movePolySplineSurfaceVertex(
            let sessionID,
            let target,
            let deltaX,
            let deltaY,
            let deltaZ,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Poly-spline surface vertex move",
                snapshot: snapshot
            )
            return try await executeSingleCommand(
                .movePolySplineSurfaceVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaZ: deltaZ
                ),
                expectedGeneration: expectedGeneration,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .setSurfaceFrameDisplay(
            let sessionID,
            let query,
            let isVisible,
            let expectedGeneration
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Surface frame display",
                snapshot: snapshot
            )
            return try await executeSingleCommand(
                .setSurfaceFrameDisplay(query: query, isVisible: isVisible),
                expectedGeneration: expectedGeneration,
                expectedWorkspaceRevision: snapshot.workspaceState.revision,
                workspace: workspace,
                snapshot: snapshot,
                operationGuard: lease.operationGuard
            )

        case .selectTargets(let sessionID, let targets, let expectedGeneration):
            return try await replaceSelection(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            ) { selection, document in
                try selection.selectTargets(targets, in: document)
            }

        case .selectReferences(let sessionID, let references, let expectedGeneration):
            return try await replaceSelection(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            ) { selection, document in
                try selection.selectReferences(references, in: document)
            }

        case .undo(let sessionID, let expectedGeneration):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Undo",
                snapshot: snapshot
            )
            let view = try await workspace.undo(
                from: snapshot,
                operationGuard: lease.operationGuard
            )
            return .sessionOperation(
                try sessionOperationResult(
                    operation: .undo,
                    lease: lease,
                    view: view
                )
            )

        case .redo(let sessionID, let expectedGeneration):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireMutationGeneration(
                expectedGeneration,
                operation: "Redo",
                snapshot: snapshot
            )
            let view = try await workspace.redo(
                from: snapshot,
                operationGuard: lease.operationGuard
            )
            return .sessionOperation(
                try sessionOperationResult(
                    operation: .redo,
                    lease: lease,
                    view: view
                )
            )

        case .evaluate(let sessionID, let expectedGeneration):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            try requireGeneration(expectedGeneration, snapshot: snapshot)
            let view = try await workspace.evaluate(
                from: snapshot,
                operationGuard: lease.operationGuard
            )
            return .evaluation(view.evaluationSnapshot)

        case .export(
            let sessionID,
            let outputPath,
            let expectedGeneration,
            let options,
            let dryRun
        ):
            let lease = try await registry.lease(id: sessionID)
            let workspace = lease.workspace
            let snapshot = try currentView(workspace)
            let executor = exportExecutor
            let prepared = try await Task.detached(priority: nil) {
                try executor.prepare(
                    outputPath: outputPath,
                    expectedGeneration: expectedGeneration,
                    options: options,
                    dryRun: dryRun,
                    snapshot: snapshot
                )
            }.value
            do {
                try Task.checkCancellation()
                return .export(
                    try await workspace.withValidatedAuthority(
                        from: snapshot,
                        operationGuard: lease.operationGuard
                    ) {
                        try prepared.publish()
                    }
                )
            } catch {
                do {
                    try prepared.discard()
                } catch let cleanupError {
                    throw errorMapper.editorError(
                        preserving: error,
                        cleanupFailure: cleanupError
                    )
                }
                throw error
            }
        }
    }

    private func executeMeshCatalog(
        _ request: AgentMeshCatalogRequest
    ) async throws -> AgentResponse {
        try request.validate()
        let lease = try await registry.lease(id: request.sessionID)
        let snapshot = try currentView(lease.workspace)
        try requireGeneration(
            request.expectedGeneration,
            snapshot: snapshot
        )
        let catalog = try await lease.workspace.catalog(
            from: snapshot,
            limits: request.limits,
            operationGuard: lease.operationGuard
        )
        return .meshCatalog(
            ProjectAgentGeometryProjection.catalog(
                catalog,
                sessionID: request.sessionID,
                view: snapshot
            )
        )
    }

    private func executeMeshPage(
        _ request: AgentMeshPageRequest
    ) async throws -> AgentResponse {
        try request.validate()
        let lease = try await registry.lease(id: request.sessionID)
        let snapshot = try currentView(lease.workspace)
        try requireGeneration(
            request.expectedGeneration,
            snapshot: snapshot
        )
        try requireMeshHandleCoordinate(request.handle, snapshot: snapshot)
        let page = try await lease.workspace.page(
            ProjectMeshElementPageRequest(
                handle: request.handle,
                domain: request.domain,
                cursor: request.cursor,
                limits: request.limits
            ),
            from: snapshot,
            operationGuard: lease.operationGuard
        )
        return .meshPage(
            ProjectAgentGeometryProjection.page(
                page,
                sessionID: request.sessionID,
                view: snapshot
            )
        )
    }

    private func executeMeshNeighborhood(
        _ request: AgentMeshNeighborhoodRequest
    ) async throws -> AgentResponse {
        try request.validate()
        let lease = try await registry.lease(id: request.sessionID)
        let snapshot = try currentView(lease.workspace)
        try requireGeneration(
            request.expectedGeneration,
            snapshot: snapshot
        )
        try requireMeshHandleCoordinate(request.handle, snapshot: snapshot)
        let neighborhood = try await lease.workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: request.handle,
                origin: request.origin,
                depth: request.depth,
                limits: request.limits
            ),
            from: snapshot,
            operationGuard: lease.operationGuard
        )
        return .meshNeighborhood(
            ProjectAgentGeometryProjection.neighborhood(
                neighborhood,
                sessionID: request.sessionID,
                view: snapshot
            )
        )
    }

    private func executeMeshEdit(
        _ request: AgentMeshEditRequest
    ) async throws -> AgentResponse {
        try request.validate()
        let lease = try await registry.lease(id: request.sessionID)
        let snapshot = try currentView(lease.workspace)
        try requireGeneration(
            request.expectedGeneration,
            snapshot: snapshot
        )
        try requireMeshHandleCoordinate(request.handle, snapshot: snapshot)
        let projectRequest = ProjectMeshEditRequest(
            handle: request.handle,
            plan: request.plan,
            snapshot: snapshot,
            name: request.name
        )
        switch request.mode {
        case .preview:
            let result = try await lease.workspace.preview(
                projectRequest,
                operationGuard: lease.operationGuard
            )
            return .meshEditPreview(
                ProjectAgentGeometryProjection.preview(
                    result,
                    sessionID: request.sessionID
                )
            )
        case .commit:
            let result = try await lease.workspace.commit(
                projectRequest,
                operationGuard: lease.operationGuard
            )
            return .meshEditCommit(
                ProjectAgentGeometryProjection.commit(
                    result,
                    sessionID: request.sessionID
                )
            )
        }
    }

    private func executeMakeEditable(
        _ request: AgentMakeEditableRequest
    ) async throws -> AgentResponse {
        try request.validate()
        let lease = try await registry.lease(id: request.sessionID)
        let snapshot = try currentView(lease.workspace)
        try requireGeneration(
            request.expectedGeneration,
            snapshot: snapshot
        )
        let projectRequest = ProjectMakeEditableRequest(
            snapshot: snapshot,
            sceneNodeID: request.sceneNodeID,
            authoredMeshSourceID: request.authoredMeshSourceID,
            authoredMeshRepresentationID: request.authoredMeshRepresentationID,
            switchesPresentationSelection: request.switchesPresentationSelection,
            name: request.name
        )
        let result = try await lease.workspace.makeEditable(
            projectRequest,
            operationGuard: lease.operationGuard
        )
        return .makeEditable(
            ProjectAgentGeometryProjection.makeEditable(
                result,
                sessionID: request.sessionID
            )
        )
    }

    private func executeSnapshotRead(_ request: AgentRequest) async throws -> AgentResponse {
        guard let sessionID = request.projectSessionID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Snapshot read request has no project session ID."
            )
        }
        let lease = try await registry.lease(id: sessionID)
        let workspace = lease.workspace
        let snapshot = try currentView(workspace)
        let executor = snapshotReadExecutor
        let response = try await Task.detached(priority: nil) {
            try executor.execute(request, from: snapshot)
        }.value
        return try await workspace.withValidatedAuthority(
            from: snapshot,
            operationGuard: lease.operationGuard
        ) {
            response
        }
    }

    private func executeSingleCommand(
        _ command: AutomationCommand,
        expectedGeneration: DocumentGeneration?,
        expectedWorkspaceRevision: WorkspaceRevision? = nil,
        workspace: ProjectWorkspace,
        snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> AgentResponse {
        let result = try await workspace.executeAutomation(
            AutomationBatch(
                commands: [command],
                expectedGeneration: expectedGeneration,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedWorkspaceRevision: expectedWorkspaceRevision
            ),
            from: snapshot,
            operationGuard: operationGuard
        )
        guard var commandResult = result.execution.results.first else {
            throw EditorError(
                code: .commandFailed,
                message: "Agent command produced no result."
            )
        }
        commandResult.executionMetrics = result.execution.metrics
        return .command(commandResult)
    }

    private func replaceSelection(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?,
        update: (inout SelectionModel, DesignDocument) throws -> Void
    ) async throws -> AgentResponse {
        let lease = try await registry.lease(id: sessionID)
        let workspace = lease.workspace
        let snapshot = try currentView(workspace)
        try requireMutationGeneration(
            expectedGeneration,
            operation: "Selection mutation",
            snapshot: snapshot
        )
        var selection = snapshot.selection
        try update(&selection, snapshot.document.document)
        let view = try await workspace.applySelection(
            .replace(selection),
            from: snapshot,
            operationGuard: lease.operationGuard
        )
        return .selection(selectionResult(from: view))
    }

    private func selectionResult(from view: ProjectViewSnapshot) -> SelectionStateResult {
        let selection = view.selection
        return SelectionStateResult(
            message: "\(selection.selectedTargets.count) target(s), \(selection.selectedReferences.count) reference(s) selected.",
            generation: view.documentGeneration,
            dirty: view.isDirty,
            selectedTargets: selection.selectedTargets,
            selectedReferences: selection.selectedReferences,
            hoveredTarget: selection.hoveredTarget,
            hoveredReference: selection.hoveredReference,
            diagnostics: view.evaluationSnapshot.diagnostics
        )
    }

    private func sessionOperationResult(
        operation: AgentSessionOperationResult.Operation,
        lease: ProjectWorkspaceRegistrationLease,
        view: ProjectViewSnapshot,
        commandName: String? = nil
    ) throws -> AgentSessionOperationResult {
        AgentSessionOperationResult(
            operation: operation,
            session: lease.summary(view: view),
            commandName: commandName,
            canUndo: view.canUndo,
            canRedo: view.canRedo
        )
    }

    private func currentView(_ workspace: ProjectWorkspace) throws -> ProjectViewSnapshot {
        guard let view = workspace.view else {
            throw EditorError(
                code: .agentUnavailable,
                message: "The registered project has no published view."
            )
        }
        return view
    }

    private func requireGeneration(
        _ expected: DocumentGeneration?,
        snapshot: ProjectViewSnapshot
    ) throws {
        guard let expected, expected != snapshot.documentGeneration else {
            return
        }
        throw EditorError(
            code: .documentGenerationMismatch,
            message: "Expected generation \(expected.value), but the project is at generation \(snapshot.documentGeneration.value)."
        )
    }

    private func requireMutationGeneration(
        _ expected: DocumentGeneration?,
        operation: String,
        snapshot: ProjectViewSnapshot
    ) throws {
        guard let expected else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operation) requires an expected source generation."
            )
        }
        try requireGeneration(expected, snapshot: snapshot)
    }

    private func requireWorkspaceRevision(
        _ expected: WorkspaceRevision?,
        operation: String,
        snapshot: ProjectViewSnapshot
    ) throws {
        guard let expected else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operation) requires an expected workspace revision."
            )
        }
        guard expected == snapshot.workspaceState.revision else {
            throw EditorError(
                code: .workspaceRevisionMismatch,
                message: "\(operation) expected workspace revision \(expected.value), but the project is at revision \(snapshot.workspaceState.revision.value)."
            )
        }
    }

    private func requireMeshHandleCoordinate(
        _ handle: ProjectMeshSourceHandle,
        snapshot: ProjectViewSnapshot
    ) throws {
        let coordinate = handle.projectAuthorityCoordinate
        guard coordinate.projectID == snapshot.projectID else {
            throw EditorError(
                code: .projectMismatch,
                message: "The Mesh handle belongs to a different project."
            )
        }
        guard coordinate.transactionRevision == snapshot.transactionRevision else {
            throw EditorError(
                code: .documentTransactionRevisionMismatch,
                message: "The Mesh handle belongs to a different transaction revision."
            )
        }
        guard coordinate.publicationSequence == snapshot.publicationSequence else {
            throw EditorError(
                code: .projectPublicationMismatch,
                message: "The Mesh handle belongs to a different publication sequence."
            )
        }
    }

    private func normalizedDocumentName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Document name must not be empty."
            )
        }
        return normalized
    }

    private func parseDimensionExpression(
        _ expression: String,
        targetKind: QuantityKind,
        defaults: ParameterExpressionDefaults?,
        snapshot: ProjectViewSnapshot
    ) throws -> CADExpression {
        let resolvedDefaults = expressionDefaults(defaults, snapshot: snapshot)
        switch targetKind {
        case .length:
            return try LengthInputParser().parseExpression(
                from: expression,
                defaultUnit: resolvedDefaults.lengthUnit,
                parameters: snapshot.document.document.cadDocument.parameters
            )
        case .angle, .scalar:
            return try ParameterExpressionParser().parse(
                expression,
                parameters: snapshot.document.document.cadDocument.parameters,
                targetKind: targetKind,
                defaults: resolvedDefaults
            )
        }
    }

    private func expressionDefaults(
        _ defaults: ParameterExpressionDefaults?,
        snapshot: ProjectViewSnapshot
    ) -> ParameterExpressionDefaults {
        defaults ?? ParameterExpressionDefaults(
            lengthUnit: snapshot.workspaceState.displayUnit,
            angleUnit: .degree
        )
    }
}


private extension SketchEntityDimensionKind {
    var quantityKind: QuantityKind {
        switch self {
        case .length, .radius, .diameter:
            .length
        case .angle:
            .angle
        }
    }
}
