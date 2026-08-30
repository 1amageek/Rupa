import RupaCore
import Testing

@Test(.timeLimit(.minutes(1)))
func productMetadataResolvesEffectiveVisibilityThroughTheRootHierarchy() {
    let visibleChild = SceneNode(name: "Visible Child")
    let hiddenDescendant = SceneNode(name: "Hidden Descendant")
    let hiddenParent = SceneNode(
        name: "Hidden Parent",
        childIDs: [hiddenDescendant.id],
        isVisible: false
    )
    let root = SceneNode(
        name: "Root",
        childIDs: [visibleChild.id, hiddenParent.id]
    )
    var metadata = ProductMetadata(
        sceneNodes: [
            root.id: root,
            visibleChild.id: visibleChild,
            hiddenParent.id: hiddenParent,
            hiddenDescendant.id: hiddenDescendant,
        ],
        rootSceneNodeIDs: [root.id]
    )

    #expect(
        metadata.effectivelyVisibleSceneNodeIDs()
            == Set([root.id, visibleChild.id])
    )

    metadata.sceneNodes[root.id]?.isVisible = false
    #expect(metadata.effectivelyVisibleSceneNodeIDs().isEmpty)
}
