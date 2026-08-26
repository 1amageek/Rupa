import RupaCore
import RupaCoreTypes
import RupaViewportScene

struct MeshSourcePresentationLegacyHitFilter {
    func hit(
        _ hit: ViewportHit?,
        presentationOccurrenceID: SceneOccurrenceID?,
        navigation: [SceneOccurrenceID: SceneNodeID],
        exactCADSceneNodeIDs: Set<SceneNodeID>
    ) -> ViewportHit? {
        guard let hit,
              hit.kind == .body else {
            return hit
        }
        guard let presentationOccurrenceID,
              let presentationSceneNodeID = navigation[presentationOccurrenceID],
              exactCADSceneNodeIDs.contains(presentationSceneNodeID),
              hit.sceneNodeID == presentationSceneNodeID else {
            return nil
        }
        return hit
    }

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
