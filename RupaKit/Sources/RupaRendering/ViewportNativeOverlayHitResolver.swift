import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaViewportScene

/// Resolves the families the scene draws as overlays, from the same mounted
/// native frame the CAD sub-shape resolver reads.
///
/// The two resolvers split by family, not by projection: both answer through
/// `ViewportNativeFrameProbe` and both produce `ViewportNativeHitCandidate`, so
/// no two families can disagree about what the frame draws where. This one
/// keeps the occurrence and the surface handle displays, and, as their seams
/// land, the curve segment, sketch entity, sketch control point and sketch
/// region families.
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
            ViewportNativeHitCandidate(rank: .object, metric: 0)
        )
    }

    /// Whether a body carries any of the four surface handle display families.
    ///
    /// The caller asks this to decide whether the native path has a family to
    /// answer for at all, which is a different question from whether the
    /// pointer hit one. A scene whose bodies carry handles but no prepared
    /// topology is still a scene the `vertex` scope is answered natively on, so
    /// an empty pixel there is a miss and not an unsupported query.
    static func carriesSurfaceHandleDisplays(_ component: ViewportBodyComponent) -> Bool {
        component.surfaceTrimKnotDisplays.isEmpty == false
            || component.surfaceTrimSpanDisplays.isEmpty == false
            || component.surfaceKnotDisplays.isEmpty == false
            || component.surfaceSpanDisplays.isEmpty == false
    }

    /// The nearest surface handle display of one body within `tolerance` of the
    /// pointer.
    ///
    /// These four families — a surface knot, a surface span, a trim knot and a
    /// trim span — are the parametric handles a B-spline surface draws, and the
    /// identity each carries is a `SelectionReference` the preparation assigned,
    /// never a render-mesh element and never a `SelectionComponent`. They enter
    /// the viewport's comparison at vertex rank, which is the rank the `vertex`
    /// scope asks for and the rank that wins over the face beneath them.
    ///
    /// Admission is projection, tolerance and the section, and deliberately not
    /// occlusion. The frame draws these displays at annotation depth, which
    /// reads no depth buffer, so a handle on the far side of its own body is
    /// visible on screen and has to stay selectable; testing it against the
    /// drawn surface would refuse a handle the user can see. The section is a
    /// different question: the frame attaches these displays to the sectioned
    /// root, so a handle the section removed is not drawn and is not admitted.
    ///
    /// Ties are broken by the recorded order of the families — trim knots, trim
    /// spans, knots, then spans — which is the order the replaced CPU tester
    /// asked them in, so a pointer equidistant from two handles keeps the answer
    /// it had.
    static func surfaceHandle(
        at point: CGPoint,
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        tolerance: CGFloat,
        probe: some ViewportNativeFrameProbe
    ) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
        guard selectionHitPolicy.allowsVertexHits,
              let sceneNodeID = item.sceneNodeID else {
            return nil
        }
        var best: (reference: SelectionReference, distance: Double)?
        func admit(_ reference: SelectionReference, at modelPoint: Point3D) throws {
            let worldPoint = ViewportLayout.transformedPoint(
                modelPoint,
                by: item.modelTransform
            )
            guard let projected = try probe.projectedPointWithinDepthRange(worldPoint) else {
                return
            }
            let distance = Double(
                hypot(point.x - projected.point.x, point.y - projected.point.y)
            )
            guard distance <= Double(tolerance),
                  distance < (best?.distance ?? .infinity),
                  try probe.retainsSectionedPoint(worldPoint) else { return }
            best = (reference, distance)
        }
        for display in component.surfaceTrimKnotDisplays {
            try admit(display.selectionReference, at: display.point)
        }
        for display in component.surfaceTrimSpanDisplays {
            try admit(display.selectionReference, at: display.point)
        }
        for display in component.surfaceKnotDisplays {
            try admit(display.selectionReference, at: display.point)
        }
        for display in component.surfaceSpanDisplays {
            try admit(display.selectionReference, at: display.point)
        }
        guard let best else { return nil }
        return (
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                selectionReference: best.reference
            ),
            ViewportNativeHitCandidate(rank: .vertex, metric: best.distance)
        )
    }
}
