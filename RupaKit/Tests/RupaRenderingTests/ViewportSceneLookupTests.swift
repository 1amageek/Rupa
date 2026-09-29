import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing

/// A scene answers "the first item of this node or feature" from its index exactly as a scan
/// of its items would, and keeps answering so after its items change.
@Test func sceneLookupAnswersAsAScanOfItsItems() {
    let shared = FeatureID()
    let node = SceneNodeID()
    func item(_ id: String, feature: FeatureID, node: SceneNodeID?) -> ViewportSceneItem {
        ViewportSceneItem(id: id, featureID: feature, sceneNodeID: node,
            modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            kind: .body(component: ViewportBodyComponent(sizeXMeters: 1, sizeYMeters: 1,
                sizeZMeters: 1, yMinMeters: 0, yMaxMeters: 1)))
    }
    var scene = ViewportScene(items: [
        item("a", feature: FeatureID(), node: nil),
        item("b", feature: shared, node: node),
        item("c", feature: shared, node: node),
    ])
    #expect(scene.firstItem(sceneNodeID: node)?.id == "b")
    #expect(scene.firstItem(featureID: shared)?.id == "b")
    #expect(scene.firstItem(sceneNodeID: SceneNodeID()) == nil)
    scene.items.removeFirst(2)
    #expect(scene.firstItem(sceneNodeID: node)?.id == "c")
    #expect(scene.firstItem(featureID: shared)?.id == "c")
    #expect(scene == ViewportScene(items: scene.items))
}
