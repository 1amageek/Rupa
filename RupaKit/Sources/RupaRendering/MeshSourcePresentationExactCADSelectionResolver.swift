import RupaCore
import RupaCoreTypes

public struct MeshSourcePresentationExactCADSelectionResolver {
    public let availableSceneNodeIDs: Set<SceneNodeID>
    public let availableOccurrenceIDs: Set<SceneOccurrenceID>

    public init(availableSceneNodeIDs: Set<SceneNodeID>, availableOccurrenceIDs: Set<SceneOccurrenceID> = []) {
        self.availableSceneNodeIDs = availableSceneNodeIDs
        self.availableOccurrenceIDs = availableOccurrenceIDs
    }

    public func hasExactContext(for selection: SelectionModel) -> Bool {
        let selectedTargets = selection.selectedTargets
        return selectedTargets.isEmpty == false
            && selectedTargets.allSatisfy { target in
                if let occurrence = target.occurrenceID { return availableOccurrenceIDs.contains(occurrence) }
                return availableSceneNodeIDs.contains(target.sceneNodeID)
            }
    }
}
