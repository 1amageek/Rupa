import Foundation
import RupaCapabilities
import RupaAutomation
import RupaCore
import RupaDomainFoundation

public enum AgentRequest: Codable, Equatable, Sendable {
    case capabilities
    case capabilityRegistry
    case status
    case sessions
    case cadInteractionQualityAssessment
    case execute(
        sessionID: UUID,
        command: AutomationCommand,
        expectedGeneration: DocumentGeneration?,
        expectedWorkspaceRevision: WorkspaceRevision? = nil
    )
    case executeBatch(
        sessionID: UUID,
        batch: AutomationBatch
    )
    case executeDomain(
        sessionID: UUID,
        request: DomainCommandRequest
    )
    case parameters(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case setParameterExpression(
        sessionID: UUID,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: ParameterExpressionDefaults?,
        expectedGeneration: DocumentGeneration?
    )
    case setObjectDimensionExpression(
        sessionID: UUID,
        target: SelectionTarget,
        kind: ObjectDimensionKind,
        expression: String,
        defaults: ParameterExpressionDefaults?,
        expectedGeneration: DocumentGeneration?
    )
    case setSketchEntityDimensionExpression(
        sessionID: UUID,
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        expression: String,
        defaults: ParameterExpressionDefaults?,
        expectedGeneration: DocumentGeneration?
    )
    case setSelectionDimensionTargetExpression(
        sessionID: UUID,
        id: SelectionDimensionID,
        expression: String,
        defaults: ParameterExpressionDefaults?,
        expectedGeneration: DocumentGeneration?
    )
    case setSurfaceFrameDisplay(
        sessionID: UUID,
        query: SurfaceFrameQuery,
        isVisible: Bool?,
        expectedGeneration: DocumentGeneration?
    )
    case movePolySplineSurfaceVertex(
        sessionID: UUID,
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        expectedGeneration: DocumentGeneration?
    )
    case evaluate(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case measure(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case selectionMeasurement(
        sessionID: UUID,
        query: CADAgentMeasurementQuery,
        expectedGeneration: DocumentGeneration?
    )
    case resolveSnap(
        sessionID: UUID,
        point: Point2D,
        options: SnapResolutionOptions,
        expectedGeneration: DocumentGeneration?
    )
    case constructionPlaneSummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case designDisplaySnapshot(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case patternArraySummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case meshSummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case polySplineMeshAnalysis(
        sessionID: UUID,
        sourceMesh: Mesh,
        options: PolySplineOptions,
        expectedGeneration: DocumentGeneration?
    )
    case sketchEntitySummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case sketchDimensionSummary(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration?
    )
    case selectionDimensionEvaluation(
        sessionID: UUID,
        dimensionID: SelectionDimensionID?,
        expectedGeneration: DocumentGeneration?
    )
    case curveAnalysis(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case topologySummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case sweepEvaluationPlan(
        sessionID: UUID,
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference],
        targets: [SweepTargetReference],
        options: SweepOptions,
        expectedGeneration: DocumentGeneration?
    )
    case booleanEvaluationPlan(
        sessionID: UUID,
        targets: [BooleanTargetReference],
        tool: BooleanToolReference,
        operation: BooleanOperation,
        keepTools: Bool,
        expectedGeneration: DocumentGeneration?
    )
    case objectDimensionSummary(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration?
    )
    case surfaceSourceSummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case surfaceAnalysis(
        sessionID: UUID,
        options: SurfaceAnalysisOptions,
        expectedGeneration: DocumentGeneration?
    )
    case surfaceFrames(
        sessionID: UUID,
        queries: [SurfaceFrameQuery],
        expectedGeneration: DocumentGeneration?
    )
    case surfaceContinuitySummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case surfaceBoundaryContinuityCompatibility(
        sessionID: UUID,
        target: SelectionReference,
        reference: SelectionReference,
        expectedGeneration: DocumentGeneration?
    )
    case selectTargets(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration?
    )
    case selectReferences(
        sessionID: UUID,
        references: [SelectionReference],
        expectedGeneration: DocumentGeneration?
    )
    case save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case export(
        sessionID: UUID,
        outputPath: String,
        expectedGeneration: DocumentGeneration?,
        options: ExportOptions,
        dryRun: Bool
    )
}

public enum AgentResponse: Codable, Equatable, Sendable {
    case capabilities([AgentCapabilityDescriptor])
    case capabilityRegistry([CapabilityDescriptor])
    case status(AgentStatus)
    case sessions([WorkspaceSessionSummary])
    case cadInteractionQualityAssessment(CADInteractionQualityAssessmentResult)
    case command(AutomationResult)
    case batch(AgentBatchResult)
    case domainExecution(DomainExecutionResult)
    case parameters(ParameterListResult)
    case evaluation(EvaluationSnapshot)
    case measurement(MeasurementResult)
    case selectionMeasurement(SelectionMeasurementResult)
    case snapResolution(SnapResolutionResult)
    case constructionPlaneSummary(ConstructionPlaneSummaryResult)
    case designDisplaySnapshot(DesignDisplaySnapshotResult)
    case patternArraySummary(PatternArraySummaryResult)
    case meshSummary(MeshSummaryResult)
    case polySplineMeshAnalysis(PolySplineMeshAnalysisResult)
    case sketchEntitySummary(SketchEntitySummaryResult)
    case sketchDimensionSummary(SketchDimensionSummaryResult)
    case selectionDimensionEvaluation(SelectionDimensionEvaluationResult)
    case curveAnalysis(CurveAnalysisResult)
    case topologySummary(TopologySummaryResult)
    case sweepEvaluationPlan(SweepEvaluationPlanResult)
    case booleanEvaluationPlan(BooleanEvaluationPlanResult)
    case objectDimensionSummary(ObjectDimensionSummaryResult)
    case surfaceSourceSummary(SurfaceSourceSummaryResult)
    case surfaceAnalysis(SurfaceAnalysisResult)
    case surfaceFrames(SurfaceFrameResult)
    case surfaceContinuitySummary(RupaCore.SurfaceContinuityResult)
    case surfaceBoundaryContinuityCompatibility(SurfaceBoundaryContinuityCompatibilityResult)
    case selection(SelectionStateResult)
    case save(SaveResult)
    case export(ExportResult)
    case failure(EditorError)
}

public extension AgentRequest {
    var methodName: String {
        switch self {
        case .capabilities:
            "agent.capabilities"
        case .capabilityRegistry:
            "agent.capabilityRegistry"
        case .status:
            "agent.status"
        case .sessions:
            "sessions.list"
        case .cadInteractionQualityAssessment:
            "agent.cadInteractionQualityAssessment"
        case .execute:
            "command.apply"
        case .executeBatch:
            "command.applyBatch"
        case .executeDomain:
            "domain.execute"
        case .parameters:
            "document.parameters"
        case .setParameterExpression:
            "parameter.setExpression"
        case .setObjectDimensionExpression:
            "objectDimension.setExpression"
        case .setSketchEntityDimensionExpression:
            "sketchEntityDimension.setExpression"
        case .setSelectionDimensionTargetExpression:
            "selectionDimension.setTargetExpression"
        case .setSurfaceFrameDisplay:
            "document.setSurfaceFrameDisplay"
        case .movePolySplineSurfaceVertex:
            "document.movePolySplineSurfaceVertex"
        case .evaluate:
            "document.evaluate"
        case .measure:
            "document.measure"
        case .selectionMeasurement:
            "selection.measure"
        case .resolveSnap:
            "snap.resolve"
        case .constructionPlaneSummary:
            "document.constructionPlaneSummary"
        case .designDisplaySnapshot:
            "document.designDisplaySnapshot"
        case .patternArraySummary:
            "document.patternArraySummary"
        case .meshSummary:
            "document.meshSummary"
        case .polySplineMeshAnalysis:
            "document.polySplineMeshAnalysis"
        case .sketchEntitySummary:
            "document.sketchEntitySummary"
        case .sketchDimensionSummary:
            "document.sketchDimensionSummary"
        case .selectionDimensionEvaluation:
            "selection.dimensionEvaluation"
        case .curveAnalysis:
            "document.curveAnalysis"
        case .topologySummary:
            "document.topologySummary"
        case .sweepEvaluationPlan:
            "document.sweepEvaluationPlan"
        case .booleanEvaluationPlan:
            "document.booleanEvaluationPlan"
        case .objectDimensionSummary:
            "document.objectDimensionSummary"
        case .surfaceSourceSummary:
            "document.surfaceSourceSummary"
        case .surfaceAnalysis:
            "document.surfaceAnalysis"
        case .surfaceFrames:
            "document.surfaceFrames"
        case .surfaceContinuitySummary:
            "document.surfaceContinuitySummary"
        case .surfaceBoundaryContinuityCompatibility:
            "document.surfaceBoundaryContinuityCompatibility"
        case .selectTargets:
            "selection.selectTargets"
        case .selectReferences:
            "selection.selectReferences"
        case .save:
            "document.save"
        case .export:
            "document.export"
        }
    }
}

public struct AgentStatus: Codable, Equatable, Sendable {
    public var running: Bool
    public var socketPath: String?
    public var sessionCount: Int

    public init(
        running: Bool,
        socketPath: String?,
        sessionCount: Int
    ) {
        self.running = running
        self.socketPath = socketPath
        self.sessionCount = sessionCount
    }
}
