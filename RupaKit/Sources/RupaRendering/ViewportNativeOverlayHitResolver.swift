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
/// keeps the occurrence, the curve segment, the surface handle displays, the
/// sketch entity, the sketch control point and the sketch region families.
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

    /// Every surface handle display of one body the mounted frame draws inside
    /// the rectangle.
    ///
    /// This is a set query, so nothing here ranks or compares candidates: the
    /// four families are read in their recorded order and each admitted display
    /// contributes one hit. Admission is
    /// `ViewportNativeCADTopologyResolver.regionMarkerCandidate` with no depth
    /// compare after it, which is the pointer answer's own rule — the frame
    /// draws these displays at annotation depth, so a handle on the far side of
    /// its own body is visible on screen and stays selectable, while a handle
    /// the section removed is not drawn and is not admitted.
    ///
    /// The caller decides whether a body contributes at all. A rectangle whose
    /// scope admits object hits reports no body-derived family, and that rule
    /// is stated once where the families are dispatched rather than repeated in
    /// each of them.
    static func surfaceHandles(
        in rect: CGRect,
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [ViewportHit] {
        guard selectionHitPolicy.allowsVertexHits,
              let sceneNodeID = item.sceneNodeID else {
            return []
        }
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionReference> = []
        func admit(_ reference: SelectionReference, at modelPoint: Point3D) throws {
            guard admitted.contains(reference) == false else { return }
            let worldPoint = ViewportLayout.transformedPoint(
                modelPoint,
                by: item.modelTransform
            )
            guard try ViewportNativeCADTopologyResolver.regionMarkerCandidate(
                worldPoint,
                in: rect,
                depthInterval: depthInterval,
                probe: probe
            ) != nil else { return }
            admitted.insert(reference)
            hits.append(
                ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: sceneNodeID,
                    kind: item.kind.selectableKind,
                    pickingBackend: .native,
                    selectionReference: reference
                )
            )
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
        return hits
    }

    /// The nearest sketch entity or spline control point of one sketch item
    /// within `tolerance` of the pointer.
    ///
    /// A sketch entity is answered as the polyline the frame drew, segment by
    /// segment, through `ViewportNativeCADTopologyResolver.segmentCandidate`,
    /// so the section and occlusion rule here is the CAD edge family's and not
    /// a second copy of it. The points come from the overlay producer that
    /// emitted that polyline, because between two of its samples an idealised
    /// curve deviates further than the hit tolerance and the answer has to be
    /// about the curve on screen. The frame draws the polyline at scene depth,
    /// so a body in front of it hides it — which the replaced identity buffer
    /// did not do, having recorded sketch geometry with no depth at all.
    ///
    /// A sketch entity that is a single point is drawn as a marker at
    /// annotation depth, and a spline's control points are too, so those are
    /// admitted by projection, tolerance and the section alone. Control point
    /// admission reads `sketchControlPointHitPolicy`, the gate the replaced
    /// pick index was built with, and never whether a control point is drawn at
    /// this moment: the frame draws them only for a selected or hovered entity,
    /// so reading that would make selecting one depend on having selected it.
    ///
    /// The endpoint handle of a line, arc or circle is not answered. No pick
    /// index ever recorded one, so no healthy production frame ever selected
    /// one, and this path does not invent one.
    ///
    /// The two scopes are separate gates. `sketchEntity` admits a control
    /// point, and either it or `object` admits an entity, which is exactly the
    /// gate `ViewportSelectionHitPolicy` states, so the scope that reaches a
    /// sketch is unchanged by moving the query onto the frame.
    static func sketchEntity(
        at point: CGPoint,
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive],
        selectionHitPolicy: ViewportSelectionHitPolicy,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy,
        tolerance: CGFloat,
        probe: some ViewportNativeFrameProbe
    ) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
        let admitsEntities = selectionHitPolicy.allowsObjectHits
            || selectionHitPolicy.allowsSketchEntityHits
        let admitsControlPoints = selectionHitPolicy.allowsSketchEntityHits
        guard admitsEntities || admitsControlPoints else { return nil }
        var best: (hit: ViewportHit, candidate: ViewportNativeHitCandidate)?
        func hit(_ entityID: SketchEntityID, controlPointIndex: Int?) -> ViewportHit {
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: item.sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                sketchEntityID: entityID,
                sketchControlPointIndex: controlPointIndex
            )
        }
        func admit(_ candidate: ViewportNativeHitCandidate, _ hit: @autoclosure () -> ViewportHit) {
            guard best.map({ candidate.precedes($0.candidate) }) ?? true else { return }
            best = (hit(), candidate)
        }
        /// Projected distance to a world point the frame draws at annotation
        /// depth, or nil when the pointer is outside the tolerance or the
        /// section removed the point.
        func markerDistance(_ worldPoint: Point3D) throws -> Double? {
            guard let projected = try probe.projectedPointWithinDepthRange(worldPoint) else {
                return nil
            }
            let distance = Double(
                hypot(point.x - projected.point.x, point.y - projected.point.y)
            )
            guard distance <= Double(tolerance),
                  try probe.retainsSectionedPoint(worldPoint) else { return nil }
            return distance
        }
        for primitive in primitives {
            let entityID = primitive.entityID
            if admitsControlPoints,
               case .spline(_, _, let controlPoints, _) = primitive,
               sketchControlPointHitPolicy.allows(
                   featureID: item.featureID,
                   entityID: entityID
               ) {
                for (index, controlPoint) in controlPoints.enumerated() {
                    // The affordance producer draws the control net through the
                    // item's model transform, so the query maps them the same
                    // way it maps them on screen.
                    let worldPoint = ViewportLayout.transformedPoint(
                        Point3D(
                            x: Double(controlPoint.x),
                            y: 0.0,
                            z: Double(controlPoint.y)
                        ),
                        by: item.modelTransform
                    )
                    guard let distance = try markerDistance(worldPoint) else { continue }
                    admit(
                        ViewportNativeHitCandidate(rank: .vertex, metric: distance),
                        hit(entityID, controlPointIndex: index)
                    )
                }
            }
            guard admitsEntities else { continue }
            let points = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(primitive)
            guard let first = points.first else { continue }
            if points.count == 1 {
                guard let distance = try markerDistance(first) else { continue }
                admit(
                    ViewportNativeHitCandidate(rank: .edge, metric: distance),
                    hit(entityID, controlPointIndex: nil)
                )
                continue
            }
            var nearest = Double.infinity
            for index in points.indices.dropLast() {
                guard let distance = try ViewportNativeCADTopologyResolver.segmentCandidate(
                    at: point,
                    worldStart: points[index],
                    worldEnd: points[index + 1],
                    tolerance: tolerance,
                    nearerThan: nearest,
                    probe: probe
                ) else { continue }
                nearest = distance
            }
            guard nearest.isFinite else { continue }
            admit(
                ViewportNativeHitCandidate(rank: .edge, metric: nearest),
                hit(entityID, controlPointIndex: nil)
            )
        }
        return best
    }

    /// Every sketch entity and spline control point of one sketch item the
    /// mounted frame draws inside the rectangle.
    ///
    /// The families, their inputs and their two scope gates are the pointer
    /// answer's above; only the admission rule differs, because a rectangle
    /// asks whether the frame draws something inside it and a pointer asks
    /// which drawn thing is nearest. A control point and a single-point entity
    /// are markers drawn at annotation depth and are admitted by
    /// `regionMarkerCandidate` with no depth compare. A multi-point entity is
    /// the polyline the overlay producer emitted, and each of its segments is
    /// asked of `regionSegmentAdmits`, which carries the occlusion test because
    /// the frame draws that polyline at scene depth.
    ///
    /// An entity is named once. The first segment the rectangle admits ends the
    /// walk over that entity, because a hit says the operator enclosed a drawn
    /// part of it and a second segment would repeat the same identity.
    static func sketchEntities(
        in rect: CGRect,
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive],
        selectionHitPolicy: ViewportSelectionHitPolicy,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [ViewportHit] {
        let admitsEntities = selectionHitPolicy.allowsObjectHits
            || selectionHitPolicy.allowsSketchEntityHits
        let admitsControlPoints = selectionHitPolicy.allowsSketchEntityHits
        guard admitsEntities || admitsControlPoints else { return [] }
        var hits: [ViewportHit] = []
        func hit(_ entityID: SketchEntityID, controlPointIndex: Int?) -> ViewportHit {
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: item.sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                sketchEntityID: entityID,
                sketchControlPointIndex: controlPointIndex
            )
        }
        func drawsMarker(_ worldPoint: Point3D) throws -> Bool {
            try ViewportNativeCADTopologyResolver.regionMarkerCandidate(
                worldPoint,
                in: rect,
                depthInterval: depthInterval,
                probe: probe
            ) != nil
        }
        for primitive in primitives {
            let entityID = primitive.entityID
            if admitsControlPoints,
               case .spline(_, _, let controlPoints, _) = primitive,
               sketchControlPointHitPolicy.allows(
                   featureID: item.featureID,
                   entityID: entityID
               ) {
                for (index, controlPoint) in controlPoints.enumerated() {
                    // The affordance producer draws the control net through the
                    // item's model transform, so the query maps them the same
                    // way it maps them on screen.
                    let worldPoint = ViewportLayout.transformedPoint(
                        Point3D(
                            x: Double(controlPoint.x),
                            y: 0.0,
                            z: Double(controlPoint.y)
                        ),
                        by: item.modelTransform
                    )
                    guard try drawsMarker(worldPoint) else { continue }
                    hits.append(hit(entityID, controlPointIndex: index))
                }
            }
            guard admitsEntities else { continue }
            let points = try ViewportSpatialOverlayProducer.sketchPrimitiveWorldPoints(primitive)
            guard let first = points.first else { continue }
            if points.count == 1 {
                guard try drawsMarker(first) else { continue }
                hits.append(hit(entityID, controlPointIndex: nil))
                continue
            }
            for index in points.indices.dropLast() {
                guard try ViewportNativeCADTopologyResolver.regionSegmentAdmits(
                    worldStart: points[index],
                    worldEnd: points[index + 1],
                    in: rect,
                    depthInterval: depthInterval,
                    probe: probe
                ) else { continue }
                hits.append(hit(entityID, controlPointIndex: nil))
                break
            }
        }
        return hits
    }

    /// The sketch region of one sketch item whose drawn boundary contains the
    /// pointer.
    ///
    /// The polygon is `drawnRegionBoundary`, which owns how a region is
    /// clipped and projected. The query here is exact containment of the
    /// pointer in that polygon and carries no tolerance, which is why no
    /// `tolerance` reaches this function.
    ///
    /// Two regions can both contain one pointer, because one profile's
    /// boundary can lie inside another's, so the nearer projected centroid
    /// wins — the tiebreak the replaced CPU rule resolved that with.
    static func sketchRegion(
        at point: CGPoint,
        item: ViewportSceneItem,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        probe: some ViewportNativeFrameProbe
    ) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
        guard selectionHitPolicy.allowsRegionHits, item.sketchRegions.isEmpty == false else {
            return nil
        }
        let depthInterval = try probe.cameraDepthInterval()
        var best: (componentID: SelectionComponentID, distance: Double)?
        for region in item.sketchRegions {
            guard let boundary = try drawnRegionBoundary(
                      region,
                      depthInterval: depthInterval,
                      probe: probe
                  ),
                  contains(point, in: boundary) else { continue }
            let center = centroid(of: boundary)
            let distance = Double(hypot(point.x - center.x, point.y - center.y))
            guard distance < (best?.distance ?? .infinity) else { continue }
            best = (region.componentID, distance)
        }
        guard let best else { return nil }
        return (
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: item.sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                selectionComponent: .region(best.componentID)
            ),
            ViewportNativeHitCandidate(rank: .region, metric: best.distance)
        )
    }

    /// Every sketch region of one sketch item whose drawn boundary meets the
    /// rectangle.
    ///
    /// A rectangle names a region wherever the frame draws part of it inside
    /// the rectangle, which is intersection and not containment: requiring the
    /// whole of a region to be enclosed would refuse a profile larger than the
    /// gesture, and the pointer answer above is this same test taken at one
    /// pixel. `intersects` reads the polygon `drawnRegionBoundary` returned, so
    /// a concave region is refused where the rectangle covers only the part of
    /// its bounding box the frame draws nothing in.
    ///
    /// Regions do not tiebreak here. Two regions whose drawn boundaries overlap
    /// are two answers, because a rectangle asks which regions the operator
    /// enclosed and the nearest-centroid rule the pointer needs has nothing to
    /// resolve over a set.
    static func sketchRegions(
        in rect: CGRect,
        item: ViewportSceneItem,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [ViewportHit] {
        guard selectionHitPolicy.allowsRegionHits, item.sketchRegions.isEmpty == false else {
            return []
        }
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionComponentID> = []
        for region in item.sketchRegions where admitted.contains(region.componentID) == false {
            guard let boundary = try drawnRegionBoundary(
                      region,
                      depthInterval: depthInterval,
                      probe: probe
                  ),
                  intersects(rect, boundary: boundary) else { continue }
            admitted.insert(region.componentID)
            hits.append(
                ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: item.kind.selectableKind,
                    pickingBackend: .native,
                    selectionComponent: .region(region.componentID)
                )
            )
        }
        return hits
    }

    /// The nearest segment of one curve item's drawn polylines within
    /// `tolerance` of the pointer.
    ///
    /// A curve is drawn as each of its segments' evaluated polylines, mapped
    /// through the scene item's model transform, and this asks the frame about
    /// exactly those points: a pointer between two samples is measured against
    /// the segment the frame drew and never against an ideal curve no frame
    /// drew.
    ///
    /// Admission is `ViewportNativeCADTopologyResolver.segmentCandidate`, the
    /// CAD edge family's own rule, so the section and the occlusion test are
    /// one implementation and not two. The frame emits a curve at scene depth,
    /// so a body in front of it hides it — which the replaced identity resolver
    /// did not test at all, having recorded curve geometry with no depth and
    /// never applying the section.
    ///
    /// The scope gate is `allowsObjectHits`. A curve carries a whole-curve
    /// `SelectionReference` and no sub-shape component, so the sub-shape scopes
    /// admit none of it, which is the gate `ViewportSelectionHitPolicy` already
    /// states for this family and is unchanged by moving the query onto the
    /// frame.
    static func curveSegment(
        at point: CGPoint,
        item: ViewportSceneItem,
        component: ViewportCurveComponent,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        tolerance: CGFloat,
        probe: some ViewportNativeFrameProbe
    ) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
        guard selectionHitPolicy.allowsObjectHits else { return nil }
        var best: (reference: SelectionReference, distance: Double)?
        for segment in component.segments {
            let points = segment.points.map {
                ViewportLayout.transformedPoint($0, by: item.modelTransform)
            }
            guard points.count >= 2 else { continue }
            // The bound starts at the best distance found so far, so a segment
            // is recorded only where it is nearer than every segment before it,
            // across the whole curve and not only within one polyline.
            var nearest = best?.distance ?? .infinity
            var admitted = false
            for index in points.indices.dropLast() {
                guard let distance = try ViewportNativeCADTopologyResolver.segmentCandidate(
                    at: point,
                    worldStart: points[index],
                    worldEnd: points[index + 1],
                    tolerance: tolerance,
                    nearerThan: nearest,
                    probe: probe
                ) else { continue }
                nearest = distance
                admitted = true
            }
            guard admitted else { continue }
            best = (segment.selectionReference, nearest)
        }
        guard let best else { return nil }
        return (
            ViewportHit(
                featureID: item.featureID,
                sceneNodeID: item.sceneNodeID,
                kind: item.kind.selectableKind,
                pickingBackend: .native,
                selectionReference: best.reference
            ),
            ViewportNativeHitCandidate(rank: .edge, metric: best.distance)
        )
    }

    /// Every curve segment identity of one curve item the mounted frame draws
    /// inside the rectangle.
    ///
    /// The geometry, the model transform and the scope gate are the pointer
    /// answer's above. Admission is `regionSegmentAdmits`, the CAD edge
    /// family's rectangle rule, so a curve drawn behind a body and a curve the
    /// section removed are both refused by the implementation that decides
    /// those for an edge, and neither family can drift from the other.
    ///
    /// An identity is named once. The first polyline span the rectangle admits
    /// ends the walk over that segment, and a `SelectionReference` already
    /// admitted is not walked again, because one identity can span several of a
    /// curve's segments.
    static func curveSegments(
        in rect: CGRect,
        item: ViewportSceneItem,
        component: ViewportCurveComponent,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [ViewportHit] {
        guard selectionHitPolicy.allowsObjectHits else { return [] }
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionReference> = []
        for segment in component.segments
        where admitted.contains(segment.selectionReference) == false {
            let points = segment.points.map {
                ViewportLayout.transformedPoint($0, by: item.modelTransform)
            }
            guard points.count >= 2 else { continue }
            for index in points.indices.dropLast() {
                guard try ViewportNativeCADTopologyResolver.regionSegmentAdmits(
                    worldStart: points[index],
                    worldEnd: points[index + 1],
                    in: rect,
                    depthInterval: depthInterval,
                    probe: probe
                ) else { continue }
                admitted.insert(segment.selectionReference)
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        pickingBackend: .native,
                        selectionReference: segment.selectionReference
                    )
                )
                break
            }
        }
        return hits
    }

    /// The active section's signed distance at every boundary point, with the
    /// half-space those distances are read against, or nil when the frame has
    /// no section.
    ///
    /// The frame answers a segment, and a segment's two endpoints are two
    /// boundary points, so the distances are asked two at a time rather than
    /// one query per point.
    private static func sectionHalfSpace(
        over points: [Point3D],
        probe: some ViewportNativeFrameProbe
    ) throws -> (scalars: [Double], bound: Double, retainsValuesAtLeastBound: Bool)? {
        var scalars: [Double] = []
        scalars.reserveCapacity(points.count)
        var halfSpace: ViewportCameraDepthClip.AffineScalarBound?
        var index = points.startIndex
        while index < points.endIndex {
            let next = min(index + 1, points.endIndex - 1)
            guard let bound = try probe.sectionParameterBound(
                from: points[index],
                to: points[next]
            ) else { return nil }
            scalars.append(bound.start)
            if next > index {
                scalars.append(bound.end)
            }
            halfSpace = bound
            index += 2
        }
        guard let halfSpace else { return nil }
        return (scalars, halfSpace.bound, halfSpace.retainsValuesAtLeastBound)
    }

    /// The polygon the mounted frame draws for one sketch region, or nil when
    /// the frame draws no area for it.
    ///
    /// This family clips before it projects. A region's boundary is a planar
    /// polygon in world space, so the whole polygon is narrowed against the
    /// frame's section and then against the frame's camera depth interval, and
    /// only what survives is projected. Clipping a planar polygon by a
    /// half-space leaves it planar and projection preserves containment, so
    /// what this returns is exact and carries no tolerance.
    ///
    /// Both clips are `ViewportCameraDepthClip`, the owner the CAD families
    /// narrow every candidate edge with, so no two families can disagree about
    /// where the cut removes geometry or where the camera stops drawing. That
    /// owner names no plane of its own, so the perspective camera's infinite
    /// far plane contributes nothing and nothing here asks which projection
    /// drew the frame.
    ///
    /// The boundary is not assumed convex: one extracted profile's boundary
    /// can be concave, and clipping a concave polygon against a single
    /// half-space leaves collinear vertices along the bound rather than
    /// splitting it, which both readers below handle. A boundary either clip
    /// leaves with fewer than three vertices bounds no area, and neither
    /// gesture answers over one.
    ///
    /// A boundary vertex the clip retained and the frame cannot project is a
    /// typed refusal and never a skipped edge, because dropping one would
    /// silently shrink the region the answer is computed over.
    ///
    /// No depth compare follows for either gesture. A region is drawn wherever
    /// these two clips leave it, so they are the whole visibility test this
    /// family has.
    private static func drawnRegionBoundary(
        _ region: ViewportSketchRegion,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [CGPoint]? {
        guard region.points.count >= 3 else { return nil }
        // The overlay producer maps a region's boundary to world space this
        // way, so the query is asked about the polygon on screen.
        let worldPoints = region.points.map { ViewportSpatialOverlayProducer.point($0) }
        var boundary: [ViewportCameraDepthClip.Vertex] = []
        boundary.reserveCapacity(worldPoints.count)
        for worldPoint in worldPoints {
            let projected = try probe.projectedPointWithDepth(worldPoint)
            boundary.append(
                ViewportCameraDepthClip.Vertex(
                    point: worldPoint,
                    depth: projected.depth,
                    projected: projected.point
                )
            )
        }
        if let section = try sectionHalfSpace(over: worldPoints, probe: probe) {
            guard let retained = ViewportCameraDepthClip.clipped(
                boundary,
                againstHalfSpaceOf: section.scalars,
                bound: section.bound,
                retainingValuesAtLeastBound: section.retainsValuesAtLeastBound
            ) else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidSceneItem,
                    message: "Sketch region boundary section distances are invalid."
                )
            }
            boundary = retained
        }
        guard let visible = ViewportCameraDepthClip.clipped(boundary, to: depthInterval) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "Sketch region boundary camera depths are invalid."
            )
        }
        guard visible.count >= 3 else { return nil }
        var projectedBoundary: [CGPoint] = []
        projectedBoundary.reserveCapacity(visible.count)
        for vertex in visible {
            if let projected = vertex.projected {
                projectedBoundary.append(projected)
                continue
            }
            guard let projected = try probe.projectedPointWithDepth(vertex.point).point else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidSceneItem,
                    message: "Sketch region boundary vertex the clip retained cannot be projected."
                )
            }
            projectedBoundary.append(projected)
        }
        return projectedBoundary
    }

    /// Even-odd containment of a point in a projected polygon.
    ///
    /// This is the rule the replaced CPU tester used, kept because the clip
    /// above can leave a concave boundary and a winding rule would read a
    /// self-touching one differently.
    private static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[(index + polygon.count - 1) % polygon.count]
            // The two vertices straddle the pointer's row, so their ordinates
            // differ and the crossing below has a finite denominator.
            guard (current.y > point.y) != (previous.y > point.y) else { continue }
            let crossingX = (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y)
                + current.x
            if point.x < crossingX {
                isInside.toggle()
            }
        }
        return isInside
    }

    /// Whether a rectangle meets a projected polygon, by area and not only by
    /// boundary.
    ///
    /// Two shapes in the plane meet in exactly one of three ways, and each is
    /// read once here. Their boundaries cross, which `segmentMeets` finds on
    /// the edge it happens on. The polygon lies wholly inside the rectangle,
    /// which the same walk finds, because every one of its edges then lies
    /// inside. Or the rectangle lies wholly inside the polygon, where no edges
    /// cross at all and the rectangle's own centre is the point tested for
    /// containment. A polygon whose bounding box covers the rectangle while its
    /// area does not falls through all three and is refused, which is what a
    /// concave profile requires.
    private static func intersects(_ rect: CGRect, boundary: [CGPoint]) -> Bool {
        guard boundary.count >= 3 else { return false }
        for index in boundary.indices {
            let start = boundary[index]
            let end = boundary[(index + 1) % boundary.count]
            if segmentMeets(rect, from: start, to: end) { return true }
        }
        return contains(CGPoint(x: rect.midX, y: rect.midY), in: boundary)
    }

    /// Whether a screen segment meets a rectangle, by Liang-Barsky parameter
    /// narrowing.
    ///
    /// The segment is carried as the parameter interval that survives the four
    /// half-planes of the rectangle, so a segment crossing a corner is admitted
    /// on the interval both bounds leave rather than on either bound alone. A
    /// degenerate segment has a zero delta on both axes and is read as a point,
    /// which the `p == 0` branch admits exactly where that point lies inside
    /// the rectangle.
    private static func segmentMeets(
        _ rect: CGRect,
        from start: CGPoint,
        to end: CGPoint
    ) -> Bool {
        var lower = 0.0
        var upper = 1.0
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        func narrow(_ p: Double, _ q: Double) -> Bool {
            guard p != 0 else { return q >= 0 }
            let parameter = q / p
            if p < 0 {
                lower = max(lower, parameter)
            } else {
                upper = min(upper, parameter)
            }
            return lower <= upper
        }
        return narrow(-dx, Double(start.x - rect.minX))
            && narrow(dx, Double(rect.maxX - start.x))
            && narrow(-dy, Double(start.y - rect.minY))
            && narrow(dy, Double(rect.maxY - start.y))
    }

    /// The mean of a projected polygon's vertices.
    ///
    /// It is the same centre the replaced CPU rule broke a tie between two
    /// containing regions with, so a pointer inside two nested profiles keeps
    /// the answer it had.
    private static func centroid(of polygon: [CGPoint]) -> CGPoint {
        var x: CGFloat = 0
        var y: CGFloat = 0
        for vertex in polygon {
            x += vertex.x
            y += vertex.y
        }
        let count = CGFloat(polygon.count)
        return CGPoint(x: x / count, y: y / count)
    }
}
