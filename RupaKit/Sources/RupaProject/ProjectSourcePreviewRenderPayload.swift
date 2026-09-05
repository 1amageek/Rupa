import RupaCore
import RupaEvaluation
import RupaProjectModel

/// Immutable render inputs for one staged source preview.
///
/// This value is a candidate observation, not project authority. It contains
/// no package, publication, workspace, or history state and is discarded with
/// the preview response.
public struct ProjectSourcePreviewRenderPayload: Sendable {
    public let document: DesignDocument
    public let evaluationSource: ProjectSourceModel
    public let evaluation: EvaluatedProjectSnapshot

    public init(
        document: DesignDocument,
        evaluationSource: ProjectSourceModel,
        evaluation: EvaluatedProjectSnapshot
    ) {
        self.document = document
        self.evaluationSource = evaluationSource
        self.evaluation = evaluation
    }
}
