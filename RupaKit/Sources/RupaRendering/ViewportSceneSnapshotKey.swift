import RupaCore
import SwiftCAD

struct ViewportSceneSnapshotKey: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case document(id: DocumentID, generation: DocumentGeneration)
        case presentation(EvaluationSnapshotID)
        case dragPreview(documentID: DocumentID, revision: UInt64)
    }

    var source: Source
    var currentEvaluationGeneration: DocumentGeneration?
    var evaluationCacheGeneration: DocumentGeneration?
    var workspaceRenderState: ViewportWorkspaceRenderState
    var renderInvalidation: RenderInvalidation
    var sectionClippingPlan: SectionAnalysisClippingPlan?
    var objectDefinitions: [ObjectTypeDefinition]
}
