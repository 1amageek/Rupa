public extension ProductMetadata {
    /// Returns scene nodes whose own visibility and every ancestor visibility
    /// are enabled. Valid Product metadata guarantees a rooted acyclic graph;
    /// the visited set keeps this read bounded for malformed caller-owned values.
    func effectivelyVisibleSceneNodeIDs() -> Set<SceneNodeID> {
        var visibleIDs: Set<SceneNodeID> = []
        var visitedIDs: Set<SceneNodeID> = []
        for rootSceneNodeID in rootSceneNodeIDs {
            appendEffectivelyVisibleSceneNodeIDs(
                rootSceneNodeID,
                parentIsVisible: true,
                visibleIDs: &visibleIDs,
                visitedIDs: &visitedIDs
            )
        }
        return visibleIDs
    }

    private func appendEffectivelyVisibleSceneNodeIDs(
        _ sceneNodeID: SceneNodeID,
        parentIsVisible: Bool,
        visibleIDs: inout Set<SceneNodeID>,
        visitedIDs: inout Set<SceneNodeID>
    ) {
        guard visitedIDs.insert(sceneNodeID).inserted,
              let sceneNode = sceneNodes[sceneNodeID] else {
            return
        }
        let isVisible = parentIsVisible && sceneNode.isVisible
        if isVisible {
            visibleIDs.insert(sceneNodeID)
        }
        for childID in sceneNode.childIDs {
            appendEffectivelyVisibleSceneNodeIDs(
                childID,
                parentIsVisible: isVisible,
                visibleIDs: &visibleIDs,
                visitedIDs: &visitedIDs
            )
        }
    }
}
