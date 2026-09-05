import RupaCore
import RupaCoreTypes
import RupaViewportScene

/// Immutable render inputs projected from one source-preview candidate.
///
/// This is a transient observation. It is not a `ProjectViewSnapshot` and does
/// not carry a project authority coordinate or publication state.
public struct ProjectPreviewRenderPayload: Sendable {
    public let document: DesignDocument
    public let presentationScene: UniversalViewportScene
    public let presentationSceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]

    public init(
        document: DesignDocument,
        presentationScene: UniversalViewportScene,
        presentationSceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    ) {
        self.document = document
        self.presentationScene = presentationScene
        self.presentationSceneNodeIDByOccurrenceID = presentationSceneNodeIDByOccurrenceID
    }
}
