import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaDomainFoundation

public final class AgentCommandController: AgentClientProtocol {
    public var name: String
    private let registry: WorkspaceRegistry
    private let runner: AutomationRunner
    private let exportService: DocumentExportService
    private let fileService: DocumentFileService
    private let domainRegistry: DomainRegistry

    public init(
        name: String = "Rupa Agent",
        registry: WorkspaceRegistry = WorkspaceRegistry(),
        runner: AutomationRunner = AutomationRunner(),
        exportService: DocumentExportService = DocumentExportService(),
        fileService: DocumentFileService = DocumentFileService(),
        domainRegistry: DomainRegistry = DomainRegistry()
    ) {
        self.name = name
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

    public func capabilityRegistry() throws -> CapabilityRegistry {
        try AgentCapabilityCatalog.capabilityRegistry(domainRegistry: domainRegistry)
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
                func run() throws -> AgentResponse {
                    return .capabilities(capabilityDescriptors())
                }
                return try run()
            case .capabilityRegistry:
                func run() throws -> AgentResponse {
                    do {
                        return .capabilityRegistry(try capabilityRegistry().sortedDescriptors())
                    } catch let error as CapabilityRegistryError {
                        throw EditorError(code: .commandFailed, message: error.message)
                    }
                }
                return try run()
            case .status:
                func run() throws -> AgentResponse {
                    return .status(
                        AgentStatus(
                            running: true,
                            sessionCount: registry.summaries().count
                        )
                    )
                }
                return try run()
            case .sessions:
                func run() throws -> AgentResponse {
                    return .sessions(registry.summaries())
                }
                return try run()
            case .createDocument:
                func run() throws -> AgentResponse {
                    guard case let .createDocument(name, outputPath) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let documentName = try normalizedDocumentName(name)
                    let outputURL = try outputPath.map(documentURL(for:))
                    if let outputURL {
                        try requireAvailableDocumentURL(outputURL, rejectsExistingFile: true)
                    }
                    let session = EditorSession(document: .empty(named: documentName))
                    if let outputURL {
                        try fileService.create(session.document, at: outputURL)
                        session.markClean()
                    }
                    let sessionID = try registry.registerNew(session: session, path: outputURL)
                    return .sessionOperation(
                        try sessionOperationResult(
                            operation: .create,
                            sessionID: sessionID,
                            session: session
                        )
                    )
                }
                return try run()
            case .openDocument:
                func run() throws -> AgentResponse {
                    guard case let .openDocument(path) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let url = try documentURL(for: path)
                    try requireAvailableDocumentURL(url, rejectsExistingFile: false)
                    let session = EditorSession(document: try fileService.load(from: url))
                    session.markClean()
                    let sessionID = try registry.registerNew(session: session, path: url)
                    return .sessionOperation(
                        try sessionOperationResult(
                            operation: .open,
                            sessionID: sessionID,
                            session: session
                        )
                    )
                }
                return try run()
            case .closeDocument:
                func run() throws -> AgentResponse {
                    guard case let .closeDocument(sessionID, expectedGeneration, discardUnsavedChanges) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try requireExpectedGeneration(
                        expectedGeneration,
                        operation: "Document close",
                        session: session
                    )
                    guard !session.isDirty || discardUnsavedChanges else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Document close requires discardUnsavedChanges for a dirty session."
                        )
                    }
                    let result = try sessionOperationResult(
                        operation: .close,
                        sessionID: sessionID,
                        session: session
                    )
                    registry.unregister(id: sessionID)
                    return .sessionOperation(result)
                }
                return try run()
            case .resetDocument:
                func run() throws -> AgentResponse {
                    guard case let .resetDocument(sessionID, name, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    let generation = try requireExpectedGeneration(
                        expectedGeneration,
                        operation: "Document reset",
                        session: session
                    )
                    let commandResult = try session.execute(
                        .resetDocument(name: try normalizedDocumentName(name)),
                        expectedGeneration: generation
                    )
                    session.activateTool(.select)
                    session.clearSelection()
                    return .sessionOperation(
                        try sessionOperationResult(
                            operation: .reset,
                            sessionID: sessionID,
                            session: session,
                            commandName: commandResult.commandName
                        )
                    )
                }
                return try run()
            case .undo:
                func run() throws -> AgentResponse {
                    guard case let .undo(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try requireExpectedGeneration(
                        expectedGeneration,
                        operation: "Undo",
                        session: session
                    )
                    let commandResult = try session.undo()
                    return .sessionOperation(
                        try sessionOperationResult(
                            operation: .undo,
                            sessionID: sessionID,
                            session: session,
                            commandName: commandResult.commandName
                        )
                    )
                }
                return try run()
            case .redo:
                func run() throws -> AgentResponse {
                    guard case let .redo(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try requireExpectedGeneration(
                        expectedGeneration,
                        operation: "Redo",
                        session: session
                    )
                    let commandResult = try session.redo()
                    return .sessionOperation(
                        try sessionOperationResult(
                            operation: .redo,
                            sessionID: sessionID,
                            session: session,
                            commandName: commandResult.commandName
                        )
                    )
                }
                return try run()
            case .cadInteractionQualityAssessment:
                func run() throws -> AgentResponse {
                    return .cadInteractionQualityAssessment(
                        CADInteractionQualityAssessmentService().assess()
                    )
                }
                return try run()
            case .execute:
                func run() throws -> AgentResponse {
                    guard case let .execute(sessionID, command, expectedGeneration, expectedWorkspaceRevision) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .executeBatch:
                func run() throws -> AgentResponse {
                    guard case let .executeBatch(sessionID, batch) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .executeDomain:
                func run() throws -> AgentResponse {
                    guard case let .executeDomain(sessionID, request) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    let result = try DomainCommandExecutor(
                        registry: domainRegistry,
                        automationRunner: runner
                    ).execute(request, in: session)
                    return .domainExecution(result)
                }
                return try run()
            case .invokeCapability:
                func run() throws -> AgentResponse {
                    guard case let .invokeCapability(sessionID, invocation, expectedWorkspaceRevision) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    let capabilityDescriptor = try capabilityRegistry().descriptor(
                        for: invocation.capabilityID,
                        version: invocation.version
                    )
                    let agentName = String(
                        invocation.capabilityID.rawValue.dropFirst("agent.".count)
                    )
                    guard invocation.capabilityID.rawValue.hasPrefix("agent."),
                          let agentDescriptor = AgentCapabilityCatalog.descriptors(
                            domainRegistry: domainRegistry
                          ).first(where: { $0.name == agentName }) else {
                        throw AgentCapabilityExecutionError(
                            code: .unsupportedRoute,
                            message: "Capability \(invocation.capabilityID.rawValue) is not an Agent capability."
                        )
                    }
                    return .capabilityExecution(
                        try AgentCapabilityInvocationExecutor(
                            runner: runner,
                            domainRegistry: domainRegistry
                        ).execute(
                            invocation,
                            descriptor: capabilityDescriptor,
                            agentDescriptor: agentDescriptor,
                            sessionID: sessionID,
                            expectedWorkspaceRevision: expectedWorkspaceRevision,
                            in: session
                        )
                    )
                }
                return try run()
            case .parameters:
                func run() throws -> AgentResponse {
                    guard case let .parameters(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .setParameterExpression:
                func run() throws -> AgentResponse {
                    guard case let .setParameterExpression(sessionID, name, expression, kind, defaults, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .setObjectDimensionExpression:
                func run() throws -> AgentResponse {
                    guard case let .setObjectDimensionExpression(sessionID, target, kind, expression, defaults, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .setSketchEntityDimensionExpression:
                func run() throws -> AgentResponse {
                    guard case let .setSketchEntityDimensionExpression(sessionID, target, kind, expression, defaults, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .setSelectionDimensionTargetExpression:
                func run() throws -> AgentResponse {
                    guard case let .setSelectionDimensionTargetExpression(sessionID, id, expression, defaults, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .setSurfaceFrameDisplay:
                func run() throws -> AgentResponse {
                    guard case let .setSurfaceFrameDisplay(sessionID, query, isVisible, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .movePolySplineSurfaceVertex:
                func run() throws -> AgentResponse {
                    guard case let .movePolySplineSurfaceVertex(sessionID, target, deltaX, deltaY, deltaZ, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .evaluate:
                func run() throws -> AgentResponse {
                    guard case let .evaluate(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .measure:
                func run() throws -> AgentResponse {
                    guard case let .measure(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .selectionMeasurement:
                func run() throws -> AgentResponse {
                    guard case let .selectionMeasurement(sessionID, query, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .resolveSnap:
                func run() throws -> AgentResponse {
                    guard case let .resolveSnap(sessionID, point, options, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .constructionPlaneSummary:
                func run() throws -> AgentResponse {
                    guard case let .constructionPlaneSummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .constructionPlaneSummary(
                        ConstructionPlaneSummaryService().summarize(
                            document: session.document,
                            activePlaneID: session.workspaceState.activeConstructionPlaneID
                        )
                    )
                }
                return try run()
            case .sceneGraphSnapshot:
                func run() throws -> AgentResponse {
                    guard case let .sceneGraphSnapshot(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .sceneGraphSnapshot(
                        SceneGraphSnapshotService().result(
                            document: session.document,
                            generation: session.generation,
                            dirty: session.isDirty
                        )
                    )
                }
                return try run()
            case .viewportSnapshot:
                throw EditorError(
                    code: .commandUnsupported,
                    message: "The EditorSession test fixture does not own a published ProjectViewSnapshot."
                )
            case .designDisplaySnapshot:
                func run() throws -> AgentResponse {
                    guard case let .designDisplaySnapshot(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .patternArraySummary:
                func run() throws -> AgentResponse {
                    guard case let .patternArraySummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .patternArraySummary(
                        PatternArraySummaryService().summarize(
                            document: session.document,
                            generation: session.generation,
                            dirty: session.isDirty
                        )
                    )
                }
                return try run()
            case .meshSummary:
                func run() throws -> AgentResponse {
                    guard case let .meshSummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .meshCatalog,
                 .meshPage,
                 .meshNeighborhood,
                 .meshEdit,
                 .makeEditable:
                throw EditorError(
                    code: .commandUnsupported,
                    message: "Geometry project routes require the registered ProjectWorkspace runtime controller."
                )
            case .polySplineMeshAnalysis:
                func run() throws -> AgentResponse {
                    guard case let .polySplineMeshAnalysis(sessionID, sourceMesh, options, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .polySplineMeshAnalysis(
                        PolySplineMeshAnalysisService().analyze(
                            sourceMesh: sourceMesh,
                            options: options,
                            tolerance: session.document.modelingSettings.tolerance
                        )
                    )
                }
                return try run()
            case .sketchEntitySummary:
                func run() throws -> AgentResponse {
                    guard case let .sketchEntitySummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .sketchEntitySummary(
                        try SketchEntitySummaryService().summarize(
                            document: session.document,
                            displayUnit: session.workspaceState.displayUnit,
                            objectRegistry: session.objectRegistry
                        )
                    )
                }
                return try run()
            case .sketchDimensionSummary:
                func run() throws -> AgentResponse {
                    guard case let .sketchDimensionSummary(sessionID, targets, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .selectionDimensionEvaluation:
                func run() throws -> AgentResponse {
                    guard case let .selectionDimensionEvaluation(sessionID, dimensionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .curveAnalysis:
                func run() throws -> AgentResponse {
                    guard case let .curveAnalysis(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .curveAnalysis(
                        try CurveAnalysisService().analyze(
                            document: session.document,
                            displayUnit: session.workspaceState.displayUnit,
                            objectRegistry: session.objectRegistry
                        )
                    )
                }
                return try run()
            case .topologySummary:
                func run() throws -> AgentResponse {
                    guard case let .topologySummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .sweepEvaluationPlan:
                func run() throws -> AgentResponse {
                    guard case let .sweepEvaluationPlan( sessionID, sections, path, guides, targets, options, expectedGeneration ) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .sweepEvaluationPlan(
                        try SweepEvaluationPlanService().plan(
                            document: session.document.cadDocument,
                            sections: sections,
                            path: path,
                            guides: guides,
                            targets: targets,
                            options: options,
                            tolerance: session.document.modelingSettings.tolerance
                        )
                    )
                }
                return try run()
            case .booleanEvaluationPlan:
                func run() throws -> AgentResponse {
                    guard case let .booleanEvaluationPlan( sessionID, targets, tool, operation, keepTools, expectedGeneration ) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .booleanEvaluationPlan(
                        try BooleanEvaluationPlanService().plan(
                            document: session.document.cadDocument,
                            targets: targets,
                            tool: tool,
                            operation: operation,
                            keepTools: keepTools,
                            tolerance: session.document.modelingSettings.tolerance
                        )
                    )
                }
                return try run()
            case .objectDimensionSummary:
                func run() throws -> AgentResponse {
                    guard case let .objectDimensionSummary(sessionID, targets, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .surfaceSourceSummary:
                func run() throws -> AgentResponse {
                    guard case let .surfaceSourceSummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .surfaceAnalysis:
                func run() throws -> AgentResponse {
                    guard case let .surfaceAnalysis(sessionID, options, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .surfaceFrames:
                func run() throws -> AgentResponse {
                    guard case let .surfaceFrames(sessionID, queries, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .surfaceContinuitySummary:
                func run() throws -> AgentResponse {
                    guard case let .surfaceContinuitySummary(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .surfaceBoundaryContinuityCompatibility:
                func run() throws -> AgentResponse {
                    guard case let .surfaceBoundaryContinuityCompatibility(sessionID, target, reference, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
                    let session = try registry.session(id: sessionID)
                    try session.store.requireGeneration(expectedGeneration)
                    return .surfaceBoundaryContinuityCompatibility(
                        try session.document.surfaceBoundaryContinuityCompatibility(
                            target: target,
                            reference: reference
                        )
                    )
                }
                return try run()
            case .selectTargets:
                func run() throws -> AgentResponse {
                    guard case let .selectTargets(sessionID, targets, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .selectReferences:
                func run() throws -> AgentResponse {
                    guard case let .selectReferences(sessionID, references, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .save:
                func run() throws -> AgentResponse {
                    guard case let .save(sessionID, expectedGeneration) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                }
                return try run()
            case .export:
                func run() throws -> AgentResponse {
                    guard case let .export(sessionID, outputPath, expectedGeneration, options, dryRun) = request else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Agent request dispatch expected a different request payload."
                        )
                    }
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
                return try run()
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

    @discardableResult
    private func requireExpectedGeneration(
        _ expectedGeneration: DocumentGeneration?,
        operation: String,
        session: EditorSession
    ) throws -> DocumentGeneration {
        guard let expectedGeneration else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operation) requires an expected source generation."
            )
        }
        try session.store.requireGeneration(expectedGeneration)
        return expectedGeneration
    }

    private func normalizedDocumentName(_ name: String) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Document name must not be empty."
            )
        }
        return normalizedName
    }

    private func documentURL(for path: String) throws -> URL {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Document path must not be empty."
            )
        }
        let expandedPath = (normalizedPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private func requireAvailableDocumentURL(
        _ url: URL,
        rejectsExistingFile: Bool
    ) throws {
        if let existingID = registry.registeredSessionID(for: url) {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Document \(url.path) is already open in session \(existingID.uuidString)."
            )
        }
        guard !rejectsExistingFile || !FileManager.default.fileExists(atPath: url.path) else {
            throw EditorError(
                code: .documentSaveFailed,
                message: "Document create will not overwrite the existing path \(url.path)."
            )
        }
    }

    private func sessionOperationResult(
        operation: AgentSessionOperationResult.Operation,
        sessionID: UUID,
        session: EditorSession,
        commandName: String? = nil
    ) throws -> AgentSessionOperationResult {
        AgentSessionOperationResult(
            operation: operation,
            session: try registry.summary(id: sessionID),
            commandName: commandName,
            canUndo: session.commandStack.canUndo,
            canRedo: session.commandStack.canRedo
        )
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
