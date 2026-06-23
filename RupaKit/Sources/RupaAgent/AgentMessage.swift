import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD

public enum AgentRequest: Codable, Equatable, Sendable {
    case capabilities
    case status
    case sessions
    case cadInteractionQualityAssessment
    case execute(
        sessionID: UUID,
        command: AutomationCommand,
        expectedGeneration: DocumentGeneration?
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
        defaults: ParameterExpressionDefaults,
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
    case curveAnalysis(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case topologySummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case objectDimensionSummary(
        sessionID: UUID,
        targets: [SelectionTarget],
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
    case selectTargets(
        sessionID: UUID,
        targets: [SelectionTarget],
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
    case status(AgentStatus)
    case sessions([WorkspaceSessionSummary])
    case cadInteractionQualityAssessment(CADInteractionQualityAssessmentResult)
    case command(AutomationResult)
    case parameters(ParameterListResult)
    case evaluation(EvaluationSnapshot)
    case measurement(MeasurementResult)
    case snapResolution(SnapResolutionResult)
    case constructionPlaneSummary(ConstructionPlaneSummaryResult)
    case meshSummary(MeshSummaryResult)
    case polySplineMeshAnalysis(PolySplineMeshAnalysisResult)
    case sketchEntitySummary(SketchEntitySummaryResult)
    case sketchDimensionSummary(SketchDimensionSummaryResult)
    case curveAnalysis(CurveAnalysisResult)
    case topologySummary(TopologySummaryResult)
    case objectDimensionSummary(ObjectDimensionSummaryResult)
    case surfaceAnalysis(SurfaceAnalysisResult)
    case surfaceFrames(SurfaceFrameResult)
    case surfaceContinuitySummary(SurfaceContinuityResult)
    case selection(SelectionStateResult)
    case save(SaveResult)
    case export(ExportResult)
    case failure(EditorError)
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
