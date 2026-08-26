import RupaCore
import RupaCoreTypes

struct MeshSourcePresentationInteractionStateResolver {
    enum State: Equatable {
        case normal
        case hovered
        case selected
    }

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
