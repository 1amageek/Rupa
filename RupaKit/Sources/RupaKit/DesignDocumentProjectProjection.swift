import RupaCoreTypes
import RupaProjectModel

/// One immutable evaluation projection and its explicit editor-navigation index.
public struct DesignDocumentProjectProjection: Sendable {
    public let source: ProjectSourceModel
    public let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
}
