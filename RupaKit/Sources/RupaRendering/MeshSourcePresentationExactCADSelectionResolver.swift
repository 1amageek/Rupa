import RupaCore

public struct MeshSourcePresentationExactCADSelectionResolver {
    public let availableSceneNodeIDs: Set<SceneNodeID>

    public init(availableSceneNodeIDs: Set<SceneNodeID>) {
        self.availableSceneNodeIDs = availableSceneNodeIDs
    }

    public func hasExactContext(for selection: SelectionModel) -> Bool {
        let selectedTargets = selection.selectedTargets
        return selectedTargets.isEmpty == false
            && selectedTargets.allSatisfy { target in
                availableSceneNodeIDs.contains(target.sceneNodeID)
            }
    }
}
