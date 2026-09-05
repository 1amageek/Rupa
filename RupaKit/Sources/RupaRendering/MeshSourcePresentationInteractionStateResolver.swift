import RupaCore
import RupaCoreTypes

struct MeshSourcePresentationInteractionStateResolver {
    /// The resolver names the state it produces; the batch key itself is the
    /// module's public `MeshSourcePresentationVisualState`.
    typealias State = MeshSourcePresentationVisualState

    let sceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    let selectedSceneNodeIDs: Set<SceneNodeID>
    let previewSceneNodeIDs: Set<SceneNodeID>
    let hoveredSceneNodeID: SceneNodeID?

    func state(for occurrenceID: SceneOccurrenceID) -> State {
        guard let sceneNodeID = sceneNodeIDByOccurrenceID[occurrenceID] else {
            return .normal
        }
        if selectedSceneNodeIDs.contains(sceneNodeID) {
            return .selected
        }
        if previewSceneNodeIDs.contains(sceneNodeID) || hoveredSceneNodeID == sceneNodeID {
            return .hovered
        }
        return .normal
    }
}
