import Foundation

public extension AgentRequest {
    var projectSessionID: UUID? {
        switch self {
        case .capabilities,
             .capabilityRegistry,
             .status,
             .sessions,
             .createDocument,
             .openDocument,
             .cadInteractionQualityAssessment:
            nil
        case .closeDocument(let id, _, _),
             .resetDocument(let id, _, _),
             .execute(let id, _, _, _),
             .invokeCapability(let id, _, _),
             .setParameterExpression(let id, _, _, _, _, _),
             .setObjectDimensionExpression(let id, _, _, _, _, _),
             .setSketchEntityDimensionExpression(let id, _, _, _, _, _),
             .setSelectionDimensionTargetExpression(let id, _, _, _, _),
             .setSurfaceFrameDisplay(let id, _, _, _),
             .movePolySplineSurfaceVertex(let id, _, _, _, _, _),
             .selectionMeasurement(let id, _, _),
             .resolveSnap(let id, _, _, _),
             .polySplineMeshAnalysis(let id, _, _, _),
             .sketchDimensionSummary(let id, _, _),
             .selectionDimensionEvaluation(let id, _, _),
             .sweepEvaluationPlan(let id, _, _, _, _, _, _),
             .booleanEvaluationPlan(let id, _, _, _, _, _),
             .objectDimensionSummary(let id, _, _),
             .surfaceAnalysis(let id, _, _),
             .surfaceFrames(let id, _, _),
             .surfaceBoundaryContinuityCompatibility(let id, _, _, _),
             .selectTargets(let id, _, _),
             .selectReferences(let id, _, _),
             .export(let id, _, _, _, _):
            id
        case .meshCatalog(let request):
            request.sessionID
        case .meshPage(let request):
            request.sessionID
        case .meshNeighborhood(let request):
            request.sessionID
        case .meshEdit(let request):
            request.sessionID
        case .makeEditable(let request):
            request.sessionID
        case .undo(let id, _),
             .redo(let id, _),
             .executeBatch(let id, _),
             .executeDomain(let id, _),
             .parameters(let id, _),
             .evaluate(let id, _),
             .measure(let id, _),
             .constructionPlaneSummary(let id, _),
             .sceneGraphSnapshot(let id, _),
             .designDisplaySnapshot(let id, _),
             .patternArraySummary(let id, _),
             .meshSummary(let id, _),
             .sketchEntitySummary(let id, _),
             .curveAnalysis(let id, _),
             .topologySummary(let id, _),
             .surfaceSourceSummary(let id, _),
             .surfaceContinuitySummary(let id, _),
             .save(let id, _):
            id
        }
    }
}
