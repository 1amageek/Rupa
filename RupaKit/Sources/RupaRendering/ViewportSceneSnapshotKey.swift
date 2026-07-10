import RupaCore
import SwiftCAD

struct ViewportSceneSnapshotKey: Equatable {
    enum Source: Equatable {
        case document(id: DocumentID, generation: DocumentGeneration)
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
