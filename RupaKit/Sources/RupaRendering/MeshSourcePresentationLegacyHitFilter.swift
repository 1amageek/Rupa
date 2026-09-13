import RupaCore
import RupaCoreTypes
import RupaViewportScene

struct MeshSourcePresentationLegacyHitFilter {
    func selectionHits(
        _ hits: [ViewportHit],
        visiblePresentationOccurrenceIDs: [SceneOccurrenceID],
        navigation: [SceneOccurrenceID: SceneNodeID],
        exactCADSceneNodeIDs: Set<SceneNodeID>,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> [ViewportHit] {
        let visibleCADSceneNodeIDs = Set(
            visiblePresentationOccurrenceIDs.compactMap { navigation[$0] }
        ).intersection(exactCADSceneNodeIDs)
        return hits.filter { hit in
            guard hit.kind == .body else {
                return true
            }
            guard selectionHitPolicy.allowsObjectHits == false,
                  let sceneNodeID = hit.sceneNodeID else {
                return false
            }
            return visibleCADSceneNodeIDs.contains(sceneNodeID)
        }
    }
}
