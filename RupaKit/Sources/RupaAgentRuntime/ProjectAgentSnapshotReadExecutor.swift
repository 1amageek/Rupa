import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaKit
import RupaProject

/// Executes pure Agent reads from one immutable published project view.
public struct ProjectAgentSnapshotReadExecutor: Sendable {
    public init() {}

    public func execute(
        _ request: AgentRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {
            try Task.checkCancellation()
        }
    ) throws -> AgentResponse {
        try operationGuard()
        switch request {
        case .parameters(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .parameters(
                ParameterListResult(
                    document: snapshot.document.document,
                    generation: snapshot.documentGeneration,
                    dirty: snapshot.isDirty,
                    diagnostics: snapshot.evaluationSnapshot.diagnostics
                )
            )
        case .measure(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .measurement(
                try MeasurementService().measure(
                    document: snapshot.document.document,
                    selection: snapshot.selection,
                    ruler: snapshot.workspaceState.ruler,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .selectionMeasurement(_, let query, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .selectionMeasurement(
                try SelectionMeasurementService().measure(
                    query: query,
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .resolveSnap(_, let point, let options, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            var workspaceOptions = options
            if workspaceOptions.constructionPlane == nil,
               let planeID = snapshot.workspaceState.activeConstructionPlaneID {
                workspaceOptions.constructionPlane = snapshot.document.document
                    .productMetadata.constructionPlanes[planeID]?.plane
            }
            return .snapResolution(
                try SnapResolver().resolve(
                    point: point,
                    in: snapshot.document.document,
                    ruler: snapshot.workspaceState.ruler,
                    options: workspaceOptions,
                    surfaceFrameDisplays: snapshot.workspaceState.surfaceFrameDisplays
                )
            )
        case .constructionPlaneSummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .constructionPlaneSummary(
                ConstructionPlaneSummaryService().summarize(
                    document: snapshot.document.document,
                    activePlaneID: snapshot.workspaceState.activeConstructionPlaneID
                )
            )
        case .sceneGraphSnapshot(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .sceneGraphSnapshot(
                SceneGraphSnapshotService().result(
                    document: snapshot.document.document,
                    generation: snapshot.documentGeneration,
                    dirty: snapshot.isDirty
                )
            )
        case .viewportSnapshot(let sessionID, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .viewportSnapshot(
                try ProjectAgentGeometryProjection.viewportSnapshot(
                    sessionID: sessionID,
                    view: snapshot,
                    operationGuard: operationGuard
                )
            )
        case .designDisplaySnapshot(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .designDisplaySnapshot(
                try DesignDisplaySnapshotService().result(
                    document: snapshot.document.document,
                    workspaceState: snapshot.workspaceState,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    generation: snapshot.documentGeneration,
                    dirty: snapshot.isDirty
                )
            )
        case .patternArraySummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .patternArraySummary(
                PatternArraySummaryService().summarize(
                    document: snapshot.document.document,
                    generation: snapshot.documentGeneration,
                    dirty: snapshot.isDirty
                )
            )
        case .meshSummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .meshSummary(
                try MeshSummaryService().summarize(
                    document: snapshot.document.document,
                    ruler: snapshot.workspaceState.ruler,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .polySplineMeshAnalysis(
            _,
            let sourceMesh,
            let options,
            let expectedGeneration
        ):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .polySplineMeshAnalysis(
                PolySplineMeshAnalysisService().analyze(
                    sourceMesh: sourceMesh,
                    options: options,
                    tolerance: snapshot.document.document.modelingSettings.tolerance
                )
            )
        case .sketchEntitySummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .sketchEntitySummary(
                try SketchEntitySummaryService().summarize(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry
                )
            )
        case .sketchDimensionSummary(_, let targets, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            let resolvedTargets = targets.isEmpty
                ? snapshot.selection.selectedTargets
                : targets
            return .sketchDimensionSummary(
                try SketchDimensionSummaryService().summarize(
                    document: snapshot.document.document,
                    targets: resolvedTargets,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry
                )
            )
        case .selectionDimensionEvaluation(
            _,
            let dimensionID,
            let expectedGeneration
        ):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .selectionDimensionEvaluation(
                try SelectionDimensionService().evaluate(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    dimensionID: dimensionID,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .curveAnalysis(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .curveAnalysis(
                try CurveAnalysisService().analyze(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry
                )
            )
        case .topologySummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .topologySummary(
                try TopologySummaryService().summarize(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .sweepEvaluationPlan(
            _,
            let sections,
            let path,
            let guides,
            let targets,
            let options,
            let expectedGeneration
        ):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .sweepEvaluationPlan(
                try SweepEvaluationPlanService().plan(
                    document: snapshot.document.document.cadDocument,
                    sections: sections,
                    path: path,
                    guides: guides,
                    targets: targets,
                    options: options,
                    tolerance: snapshot.document.document.modelingSettings.tolerance
                )
            )
        case .booleanEvaluationPlan(
            _,
            let targets,
            let tool,
            let operation,
            let keepTools,
            let expectedGeneration
        ):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .booleanEvaluationPlan(
                try BooleanEvaluationPlanService().plan(
                    document: snapshot.document.document.cadDocument,
                    targets: targets,
                    tool: tool,
                    operation: operation,
                    keepTools: keepTools,
                    tolerance: snapshot.document.document.modelingSettings.tolerance
                )
            )
        case .objectDimensionSummary(_, let targets, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            let resolvedTargets = targets.isEmpty
                ? snapshot.selection.selectedTargets
                : targets
            return .objectDimensionSummary(
                try ObjectDimensionSummaryService().summarize(
                    document: snapshot.document.document,
                    targets: resolvedTargets,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry
                )
            )
        case .surfaceSourceSummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .surfaceSourceSummary(
                try SurfaceSourceSummaryService().summarize(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    surfaceControlPointDisplays: snapshot.workspaceState
                        .surfaceControlPointDisplays,
                    surfaceFrameDisplays: snapshot.workspaceState.surfaceFrameDisplays,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .surfaceAnalysis(_, let options, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .surfaceAnalysis(
                try SurfaceAnalysisService(options: options).analyze(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .surfaceFrames(_, let queries, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .surfaceFrames(
                try SurfaceFrameService().resolve(
                    document: snapshot.document.document,
                    queries: queries,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .surfaceContinuitySummary(_, let expectedGeneration):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .surfaceContinuitySummary(
                try SurfaceContinuityService().summarize(
                    document: snapshot.document.document,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: snapshot.objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
            )
        case .surfaceBoundaryContinuityCompatibility(
            _,
            let target,
            let reference,
            let expectedGeneration
        ):
            try requireGeneration(expectedGeneration, in: snapshot)
            return .surfaceBoundaryContinuityCompatibility(
                try snapshot.document.document.surfaceBoundaryContinuityCompatibility(
                    target: target,
                    reference: reference
                )
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Agent request \(request.methodName) is not an immutable snapshot read."
            )
        }
    }

    private func requireGeneration(
        _ expected: DocumentGeneration?,
        in snapshot: ProjectViewSnapshot
    ) throws {
        guard let expected, expected != snapshot.documentGeneration else {
            return
        }
        throw EditorError(
            code: .documentGenerationMismatch,
            message: "Expected generation \(expected.value), but the project is at generation \(snapshot.documentGeneration.value)."
        )
    }
}
