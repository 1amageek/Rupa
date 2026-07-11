import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaDomainFoundation

public final class AgentCommandController: AgentClientProtocol {
    public var name: String
    public var socketPath: String?
    private let registry: WorkspaceRegistry
    private let runner: AutomationRunner
    private let exportService: DocumentExportService
    private let fileService: DocumentFileService
    private let domainRegistry: DomainRegistry

    public init(
        name: String = "Rupa Agent",
        socketPath: String? = nil,
        registry: WorkspaceRegistry = WorkspaceRegistry(),
        runner: AutomationRunner = AutomationRunner(),
        exportService: DocumentExportService = DocumentExportService(),
        fileService: DocumentFileService = DocumentFileService(),
        domainRegistry: DomainRegistry = DomainRegistry()
    ) {
        self.name = name
        self.socketPath = socketPath
        self.registry = registry
        self.runner = runner
        self.exportService = exportService
        self.fileService = fileService
        self.domainRegistry = domainRegistry
    }

    public func capabilities() -> [String] {
        capabilityDescriptors().map(\.name)
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        handle(request)
    }

    public func capabilityDescriptors() -> [AgentCapabilityDescriptor] {
        AgentCapabilityCatalog.descriptors(domainRegistry: domainRegistry)
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        registry.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        registry.unregister(id: id)
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        do {
            switch request {
            case .capabilities:
                return .capabilities(capabilityDescriptors())
            case .status:
                return .status(
                    AgentStatus(
                        running: true,
                        socketPath: socketPath,
                        sessionCount: registry.summaries().count
                    )
                )
            case .sessions:
                return .sessions(registry.summaries())
            case .cadInteractionQualityAssessment:
                return .cadInteractionQualityAssessment(
                    CADInteractionQualityAssessmentService().assess()
                )
            case let .execute(sessionID, command, expectedGeneration, expectedWorkspaceRevision):
                let session = try registry.session(id: sessionID)
                try requireCommandPreconditions(
                    command: command,
                    expectedGeneration: expectedGeneration,
                    expectedWorkspaceRevision: expectedWorkspaceRevision,
                    session: session
                )
                let execution = try runner.executeBatchTransaction(
                    AutomationBatch(
                        commands: [command],
                        expectedGeneration: expectedGeneration,
                        expectedWorkspaceRevision: expectedWorkspaceRevision
                    ),
                    in: session,
                    commits: true
                )
                guard var commandResult = execution.results.first else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent command produced no result."
                    )
                }
                commandResult.executionMetrics = execution.metrics
                return .command(commandResult)
            case let .executeBatch(sessionID, batch):
                let session = try registry.session(id: sessionID)
                try requireBatchPreconditions(batch, session: session)
                let execution = try runner.executeBatchTransaction(
                    batch,
                    in: session,
                    commits: true
                )
                return .batch(
                    AgentBatchResult(
                        results: execution.results,
                        generation: session.generation,
                        workspaceRevision: session.workspaceState.revision,
                        dirty: session.isDirty,
                        metrics: execution.metrics
                    )
                )
            case let .executeDomain(sessionID, request):
                let session = try registry.session(id: sessionID)
                let result = try DomainCommandExecutor(
                    registry: domainRegistry,
                    automationRunner: runner
                ).execute(request, in: session)
                return .domainExecution(result)
            case let .parameters(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .parameters(
                    ParameterListResult(
                        document: session.document,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .setParameterExpression(sessionID, name, expression, kind, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let parsedExpression = try ParameterExpressionParser().parseForUpsert(
                    expression,
                    parameterName: name,
                    parameters: session.document.cadDocument.parameters,
                    targetKind: kind,
                    defaults: expressionDefaults(defaults, session: session)
                )
                let result = try runner.execute(
                    .upsertParameter(
                        name: name,
                        expression: parsedExpression,
                        kind: kind
                    ),
                    in: session
                )
                return .command(result)
            case let .setObjectDimensionExpression(sessionID, target, kind, expression, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let parsedExpression = try parseDimensionExpression(
                    expression,
                    targetKind: .length,
                    defaults: defaults,
                    session: session
                )
                let result = try runner.execute(
                    .setObjectDimension(
                        target: target,
                        kind: kind,
                        value: parsedExpression
                    ),
                    in: session
                )
                return .command(result)
            case let .setSketchEntityDimensionExpression(sessionID, target, kind, expression, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let parsedExpression = try parseDimensionExpression(
                    expression,
                    targetKind: kind.quantityKind,
                    defaults: defaults,
                    session: session
                )
                let result = try runner.execute(
                    .setSketchEntityDimension(
                        target: target,
                        kind: kind,
                        value: parsedExpression
                    ),
                    in: session
                )
                return .command(result)
            case let .setSelectionDimensionTargetExpression(sessionID, id, expression, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let targetKind = try selectionDimensionQuantityKind(id: id, session: session)
                let parsedExpression = try parseDimensionExpression(
                    expression,
                    targetKind: targetKind,
                    defaults: defaults,
                    session: session
                )
                let result = try runner.execute(
                    .setSelectionDimensionTarget(
                        id: id,
                        target: parsedExpression
                    ),
                    in: session
                )
                return .command(result)
            case let .setSurfaceFrameDisplay(sessionID, query, isVisible, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let result = try runner.execute(
                    .setSurfaceFrameDisplay(
                        query: query,
                        isVisible: isVisible
                    ),
                    in: session
                )
                return .command(result)
            case let .movePolySplineSurfaceVertex(sessionID, target, deltaX, deltaY, deltaZ, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let result = try runner.execute(
                    .movePolySplineSurfaceVertex(
                        target: target,
                        deltaX: deltaX,
                        deltaY: deltaY,
                        deltaZ: deltaZ
                    ),
                    in: session
                )
                return .command(result)
            case let .evaluate(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                let result = try runner.executeBatch(
                    AutomationBatch(
                        commands: [.validateDocument],
                        expectedGeneration: expectedGeneration
                    ),
                    in: session
                )
                guard result.first != nil else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent evaluation produced no result."
                    )
                }
                return .evaluation(session.evaluationSnapshot)
            case let .measure(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .measurement(
                    try MeasurementService().measure(
                        document: session.document,
                        selection: session.selection,
                        ruler: session.workspaceState.ruler,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .selectionMeasurement(sessionID, query, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .selectionMeasurement(
                    try SelectionMeasurementService().measure(
                        query: query,
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .resolveSnap(sessionID, point, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                var workspaceOptions = options
                if workspaceOptions.constructionPlane == nil {
                    workspaceOptions.constructionPlane = session.activeConstructionPlane?.plane
                }
                return .snapResolution(
                    try SnapResolver().resolve(
                        point: point,
                        in: session.document,
                        ruler: session.workspaceState.ruler,
                        options: workspaceOptions,
                        surfaceFrameDisplays: session.workspaceState.surfaceFrameDisplays
                    )
                )
            case let .constructionPlaneSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .constructionPlaneSummary(
                    ConstructionPlaneSummaryService().summarize(
                        document: session.document,
                        activePlaneID: session.workspaceState.activeConstructionPlaneID
                    )
                )
            case let .designDisplaySnapshot(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .designDisplaySnapshot(
                    try DesignDisplaySnapshotService().result(
                        document: session.document,
                        workspaceState: session.workspaceState,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        generation: session.generation,
                        dirty: session.isDirty
                    )
                )
            case let .patternArraySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .patternArraySummary(
                    PatternArraySummaryService().summarize(
                        document: session.document,
                        generation: session.generation,
                        dirty: session.isDirty
                    )
                )
            case let .meshSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .meshSummary(
                    try MeshSummaryService().summarize(
                        document: session.document,
                        ruler: session.workspaceState.ruler,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .polySplineMeshAnalysis(sessionID, sourceMesh, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .polySplineMeshAnalysis(
                    PolySplineMeshAnalysisService().analyze(
                        sourceMesh: sourceMesh,
                        options: options
                    )
                )
            case let .sketchEntitySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .sketchEntitySummary(
                    try SketchEntitySummaryService().summarize(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .sketchDimensionSummary(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let resolvedTargets = targets.isEmpty ? session.selection.selectedTargets : targets
                return .sketchDimensionSummary(
                    try SketchDimensionSummaryService().summarize(
                        document: session.document,
                        targets: resolvedTargets,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .selectionDimensionEvaluation(sessionID, dimensionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .selectionDimensionEvaluation(
                    try SelectionDimensionService().evaluate(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        dimensionID: dimensionID,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .curveAnalysis(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .curveAnalysis(
                    try CurveAnalysisService().analyze(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .topologySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .topologySummary(
                    try TopologySummaryService().summarize(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .sweepEvaluationPlan(
                sessionID,
                sections,
                path,
                guides,
                targets,
                options,
                expectedGeneration
            ):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .sweepEvaluationPlan(
                    try SweepEvaluationPlanService().plan(
                        document: session.document.cadDocument,
                        sections: sections,
                        path: path,
                        guides: guides,
                        targets: targets,
                        options: options
                    )
                )
            case let .booleanEvaluationPlan(
                sessionID,
                targets,
                tool,
                operation,
                keepTools,
                expectedGeneration
            ):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .booleanEvaluationPlan(
                    try BooleanEvaluationPlanService().plan(
                        document: session.document.cadDocument,
                        targets: targets,
                        tool: tool,
                        operation: operation,
                        keepTools: keepTools
                    )
                )
            case let .objectDimensionSummary(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let resolvedTargets = targets.isEmpty ? session.selection.selectedTargets : targets
                return .objectDimensionSummary(
                    try ObjectDimensionSummaryService().summarize(
                        document: session.document,
                        targets: resolvedTargets,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .surfaceSourceSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceSourceSummary(
                    try SurfaceSourceSummaryService().summarize(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        surfaceControlPointDisplays: session.workspaceState.surfaceControlPointDisplays,
                        surfaceFrameDisplays: session.workspaceState.surfaceFrameDisplays,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceAnalysis(sessionID, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceAnalysis(
                    try SurfaceAnalysisService(options: options).analyze(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceFrames(sessionID, queries, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceFrames(
                    try SurfaceFrameService().resolve(
                        document: session.document,
                        queries: queries,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceContinuitySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceContinuitySummary(
                    try SurfaceContinuityService().summarize(
                        document: session.document,
                        displayUnit: session.workspaceState.displayUnit,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceBoundaryContinuityCompatibility(sessionID, target, reference, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceBoundaryContinuityCompatibility(
                    try session.document.surfaceBoundaryContinuityCompatibility(
                        target: target,
                        reference: reference
                    )
                )
            case let .selectTargets(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                guard session.selectTargets(targets) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Agent selection target is not compatible with the current document."
                    )
                }
                return .selection(
                    SelectionStateResult(
                        message: "\(session.selection.selectedTargets.count) target(s), \(session.selection.selectedReferences.count) reference(s) selected.",
                        generation: session.generation,
                        dirty: session.isDirty,
                        selectedTargets: session.selection.selectedTargets,
                        selectedReferences: session.selection.selectedReferences,
                        hoveredTarget: session.selection.hoveredTarget,
                        hoveredReference: session.selection.hoveredReference,
                        diagnostics: session.diagnostics
                    )
                )
            case let .selectReferences(sessionID, references, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                guard session.selectReferences(references) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Agent selection reference is not compatible with the current document."
                    )
                }
                return .selection(
                    SelectionStateResult(
                        message: "\(session.selection.selectedTargets.count) target(s), \(session.selection.selectedReferences.count) reference(s) selected.",
                        generation: session.generation,
                        dirty: session.isDirty,
                        selectedTargets: session.selection.selectedTargets,
                        selectedReferences: session.selection.selectedReferences,
                        hoveredTarget: session.selection.hoveredTarget,
                        hoveredReference: session.selection.hoveredReference,
                        diagnostics: session.diagnostics
                    )
                )
            case let .save(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let url = try registry.documentURL(id: sessionID)
                try fileService.save(session.document, to: url)
                session.markClean()
                return .save(
                    SaveResult(
                        message: "Document saved to \(url.path).",
                        path: url.path,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .export(sessionID, outputPath, expectedGeneration, options, dryRun):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let result = try exportService.export(
                    document: session.document,
                    generation: session.generation,
                    to: URL(fileURLWithPath: outputPath),
                    options: options,
                    dryRun: dryRun,
                    objectRegistry: session.objectRegistry
                )
                return .export(result)
            }
        } catch let error as EditorError {
            return .failure(error)
        } catch {
            return .failure(
                EditorError(
                    code: .commandFailed,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func requireCommandPreconditions(
        command: AutomationCommand,
        expectedGeneration: DocumentGeneration?,
        expectedWorkspaceRevision: WorkspaceRevision?,
        session: EditorSession
    ) throws {
        guard let expectedGeneration else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent command execution requires an expected source generation."
            )
        }
        try session.store.requireGeneration(expectedGeneration)

        if command.effect == .workspaceMutation {
            guard let expectedWorkspaceRevision else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Workspace mutation commands require an expected workspace revision."
                )
            }
            try session.workspaceState.requireRevision(expectedWorkspaceRevision)
        }
    }

    private func requireBatchPreconditions(
        _ batch: AutomationBatch,
        session: EditorSession
    ) throws {
        guard batch.expectedGeneration != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent batch execution requires an expected source generation."
            )
        }
        let effect = try batch.validatedEffect()
        if effect == .workspaceMutation, batch.expectedWorkspaceRevision == nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Workspace mutation batches require an expected workspace revision."
            )
        }
    }

    private func parseDimensionExpression(
        _ expression: String,
        targetKind: QuantityKind,
        defaults: ParameterExpressionDefaults?,
        session: EditorSession
    ) throws -> CADExpression {
        let resolvedDefaults = expressionDefaults(defaults, session: session)
        switch targetKind {
        case .length:
            return try LengthInputParser().parseExpression(
                from: expression,
                defaultUnit: resolvedDefaults.lengthUnit,
                parameters: session.document.cadDocument.parameters
            )
        case .angle, .scalar:
            return try ParameterExpressionParser().parse(
                expression,
                parameters: session.document.cadDocument.parameters,
                targetKind: targetKind,
                defaults: resolvedDefaults
            )
        }
    }

    private func expressionDefaults(
        _ defaults: ParameterExpressionDefaults?,
        session: EditorSession
    ) -> ParameterExpressionDefaults {
        defaults ?? ParameterExpressionDefaults(
            lengthUnit: session.workspaceState.displayUnit,
            angleUnit: .degree
        )
    }

    private func selectionDimensionQuantityKind(
        id: SelectionDimensionID,
        session: EditorSession
    ) throws -> QuantityKind {
        guard let kind = session.document.cadDocument.selectionDimensions.first(where: { $0.id == id })?.kind else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension target expression requires an existing selection dimension."
            )
        }
        return kind.quantityKind
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        handle(request)
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
