import RupaCore
import RupaCoreTypes
import RupaViewportScene

/// Resolves the families the scene draws as overlays, from the same mounted
/// native frame the CAD sub-shape resolver reads.
///
/// The two resolvers split by family, not by projection: both answer through
/// `ViewportNativeFrameProbe` and both produce `ViewportNativeHitCandidate`, so
/// no two families can disagree about what the frame draws where. This one
/// keeps the occurrence and, as their seams land, the curve segment, sketch
/// entity, sketch control point, sketch region and surface handle displays.
enum ViewportNativeOverlayHitResolver {
    /// The occurrence the mounted frame draws at the pointer's own pixel.
    ///
    /// This family has no geometry of its own to project. The frame already
    /// answered which occurrence covers the pointer, and `drawnTriangle` is that
    /// answer, so the admission rule is the surface hit itself and nothing here
    /// projects a candidate's bounds to test containment. A pointer the frame
    /// draws nothing at never reaches this function, which is how an occurrence
    /// stops being admitted over empty space its bounding box happened to cover.
    ///
    /// The occurrence is not restricted to the bodies that carry prepared CAD
    /// topology. An occurrence is what the frame drew, whatever geometry it
    /// drew, which is the same set the rectangle's occurrence query harvests at
    /// every pixel it covers; requiring prepared topology here would make the
    /// point and rectangle paths name different occurrences on one frame.
    ///
    /// A drawn occurrence that scene navigation does not name, or that no scene
    /// item carries, is a miss rather than a substituted identity: the CAD
    /// identity of a selection is never derived from what the renderer happened
    /// to name the thing it drew.
    static func occurrence(
        drawnBy drawnTriangle: MeshSourcePresentationTriangle,
        navigation: [SceneOccurrenceID: SceneNodeID],
        items: [ViewportSceneItem],
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
        guard selectionHitPolicy.allowsObjectHits,
              let sceneNodeID = navigation[drawnTriangle.occurrenceID],
              let item = items.first(where: { $0.sceneNodeID == sceneNodeID }) else {
            return nil
        }
        return (
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                selectionComponent: .object
            ),
            ViewportNativeHitCandidate(component: .object, rank: .object, metric: 0)
        )
    }
}
