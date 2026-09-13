import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene

/// Resolves stable CAD sub-shape identity from prepared B-Rep topology through
/// the mounted native camera.
///
/// The resolver never derives a CAD identity from render-mesh identifiers: the
/// returned `SelectionComponent` always carries a `SelectionComponentID` that
/// evaluation prepared for the body. The native frame supplies only projection
/// and visibility, so CAD sub-selection shares one projection, one visibility
/// rule and one hit decision with the rest of the viewport input.
enum ViewportNativeCADTopologyResolver {
    /// Occlusion tolerance. A vertex or edge candidate is rejected only when
    /// the native frame draws a nearer surface at the candidate's own projected
    /// point, and `depthSlack` bounds how far behind that surface the candidate
    /// may still lie and be admitted.
    ///
    /// It is a fraction of the candidate's own camera depth so the rule is
    /// independent of model scale and zoom; it exists only to absorb the
    /// deviation between the exact B-Rep point and the tessellated collision
    /// surface that answers the native ray. Owner: this resolver. Changing it
    /// requires re-running the hidden-vertex and silhouette cases in the CAD
    /// topology resolver tests.
    static let depthSlack: Double = 1.0e-3

    /// The screen neighbourhood a point or curve family is tested in.
    ///
    /// It is one operational value with one owner, not a correctness constant,
    /// and the overlay resolver's point families are given this same value by
    /// the viewport so no two native families disagree about how near a pointer
    /// has to be. Owner: this resolver.
    static let pointTolerance: CGFloat = 8

    /// A nil result is a valid miss after projection and visibility run.
    /// Readiness, camera revision and projection failures stay typed and are
    /// propagated from the frame probe.
    ///
    /// `visibleSurface` is the render provenance of the native surface *this
    /// body* draws at the pointer — the hit triangle's mesh face identity and
    /// its camera depth — and nil when the frame draws no surface of this body
    /// there. It answers the face query alone. Vertices and edges are searched
    /// even when the pointer draws nothing or draws another body, because a
    /// silhouette vertex and an outline edge project within the point tolerance
    /// of pixels just outside the tessellated surface. Restricting the
    /// tolerance query to the drawn interior would leave those sub-shapes with
    /// no native input path, which is what sent them back to the legacy
    /// identity resolver.
    ///
    /// Projection, section retention, occlusion and the recovery of a world
    /// parameter all come from `probe`, which reads one mounted frame. The
    /// resolver owns no projection model and no clipping rule of its own: it
    /// asks the frame which interpolation its camera makes linear, and asks the
    /// frame whether a point survived the section.
    static func resolve(
        at point: CGPoint,
        topology: ViewportBodyTopology,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        visibleSurface: (faceID: MeshFaceID, depth: Double)?,
        tolerance: CGFloat = pointTolerance,
        probe: some ViewportNativeFrameProbe
    ) throws -> (component: SelectionComponent, candidate: ViewportNativeHitCandidate)? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology query coordinates or tolerance are invalid."
            )
        }

        if selectionHitPolicy.allowsVertexHits {
            var best: (component: SelectionComponent, candidate: ViewportNativeHitCandidate)?
            for vertex in topology.vertices {
                let worldPoint = world(vertex.point, modelTransform: modelTransform)
                guard let projected = try probe.projectedPointWithinDepthRange(worldPoint) else {
                    continue
                }
                let distance = Double(hypot(point.x - projected.point.x, point.y - projected.point.y))
                guard distance <= Double(tolerance),
                      distance < (best?.candidate.metric ?? .infinity),
                      try isVisible(worldPoint, projected, probe: probe) else { continue }
                best = (
                    .vertex(vertex.componentID),
                    ViewportNativeHitCandidate(rank: .vertex, metric: distance)
                )
            }
            if let best {
                return best
            }
        }

        if selectionHitPolicy.allowsEdgeHits {
            var best: (component: SelectionComponent, candidate: ViewportNativeHitCandidate)?
            for edge in topology.edges {
                guard let distance = try segmentCandidate(
                    at: point,
                    worldStart: world(edge.start, modelTransform: modelTransform),
                    worldEnd: world(edge.end, modelTransform: modelTransform),
                    tolerance: tolerance,
                    nearerThan: best?.candidate.metric ?? .infinity,
                    probe: probe
                ) else { continue }
                best = (
                    .edge(edge.componentID),
                    ViewportNativeHitCandidate(rank: .edge, metric: distance)
                )
            }
            if let best {
                return best
            }
        }

        // A face exists at this pixel only where the native frame draws this
        // body, so an empty pixel and an occluding body both end the face
        // query. The frame already decided which triangle it drew there, and
        // the prepared run list names the CAD face that generated it, so this
        // branch reads that answer instead of forming a second one.
        guard selectionHitPolicy.allowsFaceHits, let visibleSurface else {
            return nil
        }
        // The universal mesh source names a CAD body's triangles by their
        // emission index, so the raw value is that index. A value no `Int` can
        // hold is malformed provenance rather than a miss: reporting it as
        // "nothing was hit" would hand the query to the legacy resolver as if
        // the frame had answered.
        guard let triangleIndex = Int(exactly: visibleSurface.faceID.rawValue) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "A drawn CAD triangle reports an unrepresentable mesh face identity."
            )
        }
        guard let componentID = topology.componentID(forTriangle: triangleIndex) else {
            return nil
        }
        return (
            .face(componentID),
            ViewportNativeHitCandidate(rank: .face, metric: visibleSurface.depth)
        )
    }

    // MARK: - Region rectangle

    /// The prepared CAD face one drawn triangle names, or nil when the body's
    /// recorded runs name no face for that triangle.
    ///
    /// A drawn triangle's mesh face identity is the body's own triangle
    /// emission index, so it addresses the recorded runs directly. An index no
    /// run names is a truthful miss — a triangle the preparation recorded no
    /// face for — and never a reason to substitute a render-mesh identifier for
    /// a CAD one. An index that is not representable is malformed provenance
    /// and a typed failure.
    ///
    /// Which body the triangle belongs to is the caller's knowledge. Mesh face
    /// identities are numbered per body, so this lookup performs no ownership
    /// check of its own and must not be given another body's triangle.
    static func regionFaceComponentID(
        forTriangle triangle: MeshSourcePresentationTriangle,
        topology: ViewportBodyTopology
    ) throws -> SelectionComponentID? {
        guard let triangleIndex = Int(exactly: triangle.faceID.rawValue) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "A drawn CAD triangle reports an unrepresentable mesh face identity."
            )
        }
        return topology.componentID(forTriangle: triangleIndex)
    }

    /// Resolves the prepared CAD vertices and edges of one body that the
    /// mounted frame draws inside a screen rectangle.
    ///
    /// This is a set query over one region, not a nearest query, so
    /// `ViewportNativeHitCandidate` and its rank-then-metric order have no role
    /// here. The result follows the recorded topology order — vertices, then
    /// edges — and is de-duplicated by prepared identity.
    ///
    /// Faces are not resolved here. A face is admitted by the triangles the
    /// frame draws inside the rectangle, and the region raster reports those
    /// for the whole scene in one pass; asking it once per body would read the
    /// same raster once per body for the same answer. The caller harvests those
    /// triangles and resolves each one through
    /// `regionFaceComponentID(forTriangle:topology:)`, so `selectionHitPolicy`
    /// gates vertices and edges alone here.
    ///
    /// A vertex is admitted when the frame draws it inside the rectangle: its
    /// projected point is inside with no tolerance, its camera depth lies in
    /// the frame's depth interval, the section retains it, and the frame draws
    /// nothing nearer than `depthSlack` at its own device pixel. That pixel is
    /// read once. An empty pixel hides nothing, which is what keeps a
    /// silhouette vertex selectable, and the section query is what separates an
    /// empty pixel from a point the cut removed.
    ///
    /// An edge is narrowed in its own world parameter first, against the
    /// camera's depth interval and against the section's affine bound, so a
    /// part the frame does not draw never reaches the walk and a part it does
    /// draw is never dropped whole. What survives is projected and handed to
    /// the frame's segment probe, which clips it to the rectangle's device
    /// pixels and walks one pixel at a time along the major axis. The first
    /// accepted pixel ends the walk.
    ///
    /// The walk is bounded by the device pixels that clip produced, so it needs
    /// no query ceiling of its own: every round either answers or resumes
    /// strictly past the pixel it rejected. Nothing here reads a region it did
    /// not ask about as empty — every device pixel the rectangle holds along a
    /// candidate is reachable by the walk, and a vertex is asked at its own
    /// pixel.
    ///
    /// Readiness, camera revision, admission and projection failures stay typed
    /// and are propagated from the frame probe. A segment whose
    /// section scalar names no finite crossing is refused rather than reported
    /// as excluded, because those are different answers.
    static func resolveRegion(
        in rect: CGRect,
        topology: ViewportBodyTopology,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        depthInterval: ClosedRange<Double>,
        probe: some ViewportNativeFrameProbe
    ) throws -> [SelectionComponent] {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              rect.size.width > 0, rect.size.height > 0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology region rectangle query bounds are invalid."
            )
        }
        guard ViewportCameraDepthClip.canClip(against: depthInterval) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology region rectangle query camera depth bounds are invalid."
            )
        }

        var components: [SelectionComponent] = []
        var admitted: Set<SelectionComponentID> = []

        if selectionHitPolicy.allowsVertexHits {
            for vertex in topology.vertices where admitted.contains(vertex.componentID) == false {
                let worldPoint = world(vertex.point, modelTransform: modelTransform)
                let camera = try probe.projectedPointWithDepth(worldPoint)
                guard let projected = camera.point,
                      depthInterval.contains(camera.depth),
                      rect.contains(projected),
                      try probe.retainsSectionedPoint(worldPoint),
                      try isRegionVisible(
                          depth: camera.depth, at: projected, probe: probe
                      ) else { continue }
                admitted.insert(vertex.componentID)
                components.append(.vertex(vertex.componentID))
            }
        }

        guard selectionHitPolicy.allowsEdgeHits else { return components }
        for edge in topology.edges where admitted.contains(edge.componentID) == false {
            let worldStart = world(edge.start, modelTransform: modelTransform)
            let worldEnd = world(edge.end, modelTransform: modelTransform)
            let start = try probe.projectedPointWithDepth(worldStart)
            let end = try probe.projectedPointWithDepth(worldEnd)
            guard let drawn = ViewportCameraDepthClip.clippedParameterInterval(
                startDepth: start.depth, endDepth: end.depth, to: depthInterval
            ) else { continue }
            var retained = ViewportCameraDepthClip.ParameterInterval.whole
            if let bound = try probe.sectionParameterBound(from: worldStart, to: worldEnd) {
                guard retained.narrow(by: bound) else {
                    throw MeshSourcePresentationRenderError(
                        code: .invalidSceneItem,
                        message: "A CAD edge names no finite section crossing for the region rectangle."
                    )
                }
            }
            guard retained.isEmpty == false else { continue }
            let lower = max(drawn.lower, retained.lower)
            let upper = min(drawn.upper, retained.upper)
            guard lower <= upper else { continue }
            guard let drawnStart = ViewportCameraDepthClip.interpolated(
                      worldStart, worldEnd, lower
                  ),
                  let drawnEnd = ViewportCameraDepthClip.interpolated(
                      worldStart, worldEnd, upper
                  ) else { continue }
            let clippedStart = lower == 0 ? start : try probe.projectedPointWithDepth(drawnStart)
            let clippedEnd = upper == 1 ? end : try probe.projectedPointWithDepth(drawnEnd)
            guard let screenStart = clippedStart.point,
                  let screenEnd = clippedEnd.point else { continue }
            guard try regionSegmentAdmits(
                from: screenStart,
                to: screenEnd,
                worldStart: drawnStart,
                worldEnd: drawnEnd,
                startDepth: clippedStart.depth,
                endDepth: clippedEnd.depth,
                in: rect,
                probe: probe
            ) else { continue }
            admitted.insert(edge.componentID)
            components.append(.edge(edge.componentID))
        }
        return components
    }

    private static func world(_ point: Point3D, modelTransform: Transform3D) -> Point3D {
        ViewportLayout.transformedPoint(point, by: modelTransform)
    }

    /// The projected distance from `point` to the drawn segment between two
    /// world endpoints, or nil when this frame does not admit that segment.
    ///
    /// This is the edge family's whole admission rule in one place: measure
    /// against the segment the frame drew, recover the segment's own parameter
    /// under the frame's projection so the depth asked about is a depth the
    /// frame reports, then apply the shared section and occlusion rule. A CAD
    /// edge and a sketch entity's polyline are the same question asked of
    /// different geometry, so they ask it here rather than each carrying a copy
    /// that could drift into admitting what the other refuses.
    ///
    /// `bound` is the distance a nearer candidate already achieved. A segment
    /// that cannot beat it costs two projections and no visibility query, which
    /// is what keeps a polyline sampled into many segments from asking the frame
    /// once per segment.
    static func segmentCandidate(
        at point: CGPoint,
        worldStart: Point3D,
        worldEnd: Point3D,
        tolerance: CGFloat,
        nearerThan bound: Double,
        probe: some ViewportNativeFrameProbe
    ) throws -> Double? {
        guard let start = try probe.projectedPointWithinDepthRange(worldStart),
              let end = try probe.projectedPointWithinDepthRange(worldEnd) else {
            return nil
        }
        let parameter = segmentParameter(for: point, from: start.point, to: end.point)
        let nearest = CGPoint(
            x: start.point.x + (end.point.x - start.point.x) * parameter,
            y: start.point.y + (end.point.y - start.point.y) * parameter
        )
        let distance = Double(hypot(point.x - nearest.x, point.y - nearest.y))
        guard distance <= Double(tolerance), distance < bound else {
            return nil
        }
        // The nearest point is found on screen, but the section and occlusion
        // questions are about a point on the segment. Recover the segment's own
        // parameter under the frame's projection and let the native camera
        // report that point's depth, so no depth on this path is interpolated
        // by a rule the frame does not use.
        guard let worldParameter = probe.worldParameter(
            forScreenParameter: Double(parameter),
            startDepth: start.depth,
            endDepth: end.depth
        ) else {
            return nil
        }
        let worldPoint = Point3D(
            x: worldStart.x + (worldEnd.x - worldStart.x) * worldParameter,
            y: worldStart.y + (worldEnd.y - worldStart.y) * worldParameter,
            z: worldStart.z + (worldEnd.z - worldStart.z) * worldParameter
        )
        guard let projected = try probe.projectedPointWithinDepthRange(worldPoint),
              try isVisible(worldPoint, projected, probe: probe) else {
            return nil
        }
        return distance
    }

    /// Admits a sub-shape point only when the mounted frame still retains it
    /// through the active section, and then rejects it only when the frame
    /// draws a nearer surface at the point's own pixel.
    ///
    /// The section query runs first because an empty pixel is ambiguous on its
    /// own: a silhouette vertex and a vertex the section cut away both draw
    /// nothing. Asking the frame which of the two it is keeps the silhouette
    /// rescue from admitting geometry that is not in the frame at all. A pixel
    /// that draws nothing then hides nothing, which is what keeps silhouette
    /// vertices and outline edges selectable: their exact B-Rep point lands on
    /// the tessellated outline, where the native ray may pass either side of
    /// the boundary.
    ///
    /// The point query and the rectangle query share this rule verbatim, so a
    /// sub-shape cannot be visible to one and hidden to the other.
    private static func isVisible(
        _ worldPoint: Point3D,
        _ candidate: (point: CGPoint, depth: Double),
        probe: some ViewportNativeFrameProbe
    ) throws -> Bool {
        guard try probe.retainsSectionedPoint(worldPoint) else { return false }
        guard let surfaceDepth = try probe.drawnSurfaceDepth(at: candidate.point) else {
            return true
        }
        return candidate.depth - surfaceDepth <= abs(candidate.depth) * depthSlack
    }

    /// Whether the frame leaves a region candidate at `point` visible.
    ///
    /// The raster reports what the frame draws, which already carries the
    /// section, the back faces and every nearer solid, so this is one depth
    /// compare and nothing else. A pixel the frame draws nothing at hides
    /// nothing: a silhouette candidate lands on the tessellated outline, where
    /// the drawn fragment can fall on either side of the boundary. The section
    /// is asked separately, before this rule runs, because an empty pixel alone
    /// cannot tell a silhouette from a point the cut removed.
    private static func isRegionVisible(
        depth: Double,
        at point: CGPoint,
        probe: some ViewportNativeFrameProbe
    ) throws -> Bool {
        guard let fragmentDepth = try probe.drawnRegionFragmentDepth(at: point) else {
            return true
        }
        return depth - fragmentDepth <= abs(depth) * depthSlack
    }

    /// Walks a projected edge one device pixel at a time and reports whether
    /// the rectangle admits it.
    ///
    /// The frame's segment probe owns the walk's geometry. It clips the segment
    /// to the rectangle's device pixels and reports the first pixel of the
    /// remaining walk the frame draws at, with that pixel's parameter along the
    /// segment it was given. A walk that meets no pixel of the rectangle answers no,
    /// and a walk whose remaining pixels the frame draws nothing at answers
    /// yes, because nothing at those pixels can occlude the edge and the caller
    /// narrowed the segment against the section in world space before
    /// projecting it. A drawn pixel admits the edge when the edge's own point
    /// there is not behind the drawn fragment by more than `depthSlack`;
    /// otherwise the walk resumes strictly past that pixel, which is what
    /// bounds this loop by the pixels the clip produced.
    ///
    /// A pixel whose parameter names no world point is resumed past rather than
    /// admitted. The perspective recovery has a finite solution for every depth
    /// the mounted camera's interval admits, so the region path does not reach
    /// that refusal; it is not an approximation this rule accepts.
    private static func regionSegmentAdmits(
        from screenStart: CGPoint,
        to screenEnd: CGPoint,
        worldStart: Point3D,
        worldEnd: Point3D,
        startDepth: Double,
        endDepth: Double,
        in rect: CGRect,
        probe: some ViewportNativeFrameProbe
    ) throws -> Bool {
        var step = 0
        while true {
            let segment = try probe.regionSegmentProbe(
                from: screenStart, to: screenEnd, within: rect, startingAt: step
            )
            guard step < segment.stepCount else { return false }
            guard let drawn = segment.drawn else { return true }
            guard drawn.step == step else { return true }
            guard let parameter = probe.worldParameter(
                      forScreenParameter: drawn.fraction,
                      startDepth: startDepth,
                      endDepth: endDepth
                  ),
                  let worldPoint = ViewportCameraDepthClip.interpolated(
                      worldStart, worldEnd, parameter
                  ) else {
                step = drawn.step + 1
                continue
            }
            let depth = try probe.projectedPointWithDepth(worldPoint).depth
            if depth - drawn.depth <= abs(depth) * depthSlack { return true }
            step = drawn.step + 1
        }
    }

    private static func segmentParameter(
        for point: CGPoint,
        from start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return min(1, max(0, raw))
    }

}
