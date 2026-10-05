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
    var selectedOccurrenceIDs: Set<SceneOccurrenceID> = []
    var previewOccurrenceIDs: Set<SceneOccurrenceID> = []
    var hoveredOccurrenceID: SceneOccurrenceID? = nil
    var hoveredBodyID: String? = nil

    func state(for occurrenceID: SceneOccurrenceID, sourceBodyID: String? = nil) -> State {
        guard let sceneNodeID = sceneNodeIDByOccurrenceID[occurrenceID] else {
            return .normal
        }
        if selectedOccurrenceIDs.contains(occurrenceID) || selectedSceneNodeIDs.contains(sceneNodeID) {
            return .selected
        }
        if previewOccurrenceIDs.contains(occurrenceID) || previewSceneNodeIDs.contains(sceneNodeID) || (hoveredOccurrenceID == occurrenceID && (hoveredBodyID == nil || hoveredBodyID == sourceBodyID)) || hoveredSceneNodeID == sceneNodeID {
            return .hovered
        }
        return .normal
    }
}
