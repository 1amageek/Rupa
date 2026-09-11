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

    /// A ranked sub-shape candidate.
    ///
    /// `rank` keeps the scope order the viewport asks for — a vertex wins over
    /// an edge, and an edge over a face — and `metric` orders candidates of the
    /// same rank: projected point distance for a vertex or edge, and the camera
    /// depth of the drawn surface for a face. The caller compares candidates
    /// from different bodies through this order, so the nearest projected
    /// sub-shape wins across the scene instead of the first body that happens
    /// to answer. Only the one body the native frame draws at the pointer is
    /// given a surface hit, so at most one face candidate exists per query and
    /// the face metric never has to order two bodies against each other.
    struct Candidate {
        enum Rank: Int {
            case vertex
            case edge
            case face
        }

        let component: SelectionComponent
        let rank: Rank
        let metric: Double

        func precedes(_ other: Candidate) -> Bool {
            rank == other.rank ? metric < other.metric : rank.rawValue < other.rank.rawValue
        }
    }

    /// A nil result is a valid miss after projection and visibility run.
    /// Readiness, camera revision and projection failures stay typed and are
    /// propagated from the injected native queries.
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
    /// `usesPerspectiveProjection` and `retainsSectionedPoint` come from the
    /// same mounted frame as `project` and `surfaceHit`. The resolver owns no
    /// projection model and no clipping rule of its own: it asks the frame
    /// which interpolation its camera makes linear, and asks the frame whether
    /// a point survived the section.
    static func resolve(
        at point: CGPoint,
        topology: ViewportBodyTopology,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        visibleSurface: (faceID: MeshFaceID, depth: Double)?,
        usesPerspectiveProjection: Bool,
        tolerance: CGFloat = 8,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?,
        surfaceHit: (CGPoint) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        retainsSectionedPoint: (Point3D) throws -> Bool
    ) throws -> Candidate? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology query coordinates or tolerance are invalid."
            )
        }

        if selectionHitPolicy.allowsVertexHits {
            var best: Candidate?
            for vertex in topology.vertices {
                let worldPoint = world(vertex.point, modelTransform: modelTransform)
                guard let projected = try project(worldPoint) else { continue }
                let distance = Double(hypot(point.x - projected.point.x, point.y - projected.point.y))
                guard distance <= Double(tolerance), distance < (best?.metric ?? .infinity),
                      try isVisible(
                          worldPoint,
                          projected,
                          project: project,
                          surfaceHit: surfaceHit,
                          retainsSectionedPoint: retainsSectionedPoint
                      ) else { continue }
                best = Candidate(
                    component: .vertex(vertex.componentID),
                    rank: .vertex,
                    metric: distance
                )
            }
            if let best {
                return best
            }
        }

        if selectionHitPolicy.allowsEdgeHits {
            var best: Candidate?
            for edge in topology.edges {
                let worldStart = world(edge.start, modelTransform: modelTransform)
                let worldEnd = world(edge.end, modelTransform: modelTransform)
                guard let start = try project(worldStart),
                      let end = try project(worldEnd) else { continue }
                let parameter = segmentParameter(for: point, from: start.point, to: end.point)
                let nearest = CGPoint(
                    x: start.point.x + (end.point.x - start.point.x) * parameter,
                    y: start.point.y + (end.point.y - start.point.y) * parameter
                )
                let distance = Double(hypot(point.x - nearest.x, point.y - nearest.y))
                guard distance <= Double(tolerance), distance < (best?.metric ?? .infinity) else {
                    continue
                }
                // The nearest point is found on screen, but the section and
                // occlusion questions are about a point on the edge. Recover
                // the edge's own parameter under the frame's projection and let
                // the native camera report that point's depth, so no depth on
                // this path is interpolated by a rule the frame does not use.
                guard let edgeParameter = worldParameter(
                    forScreenParameter: Double(parameter),
                    startDepth: start.depth,
                    endDepth: end.depth,
                    usesPerspectiveProjection: usesPerspectiveProjection
                ) else { continue }
                let worldPoint = Point3D(
                    x: worldStart.x + (worldEnd.x - worldStart.x) * edgeParameter,
                    y: worldStart.y + (worldEnd.y - worldStart.y) * edgeParameter,
                    z: worldStart.z + (worldEnd.z - worldStart.z) * edgeParameter
                )
                guard let projected = try project(worldPoint),
                      try isVisible(
                          worldPoint,
                          projected,
                          project: project,
                          surfaceHit: surfaceHit,
                          retainsSectionedPoint: retainsSectionedPoint
                      ) else { continue }
                best = Candidate(
                    component: .edge(edge.componentID),
                    rank: .edge,
                    metric: distance
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
        return Candidate(
            component: .face(componentID),
            rank: .face,
            metric: visibleSurface.depth
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
    /// This is a set query over one region, not a nearest query, so `Candidate`
    /// and its rank-then-metric order have no role here. The result follows the
    /// recorded topology order — vertices, then edges — and is de-duplicated by
    /// prepared identity.
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
    /// and are propagated from the injected native queries. A segment whose
    /// section scalar names no finite crossing is refused rather than reported
    /// as excluded, because those are different answers.
    static func resolveRegion(
        in rect: CGRect,
        topology: ViewportBodyTopology,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        usesPerspectiveProjection: Bool,
        depthInterval: ClosedRange<Double>,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double),
        retainsSectionedPoint: (Point3D) throws -> Bool,
        sectionParameterBound: (Point3D, Point3D) throws -> ViewportCameraDepthClip.AffineScalarBound?,
        regionFragmentDepth: (CGPoint) throws -> Double?,
        regionSegmentProbe: (CGPoint, CGPoint, Int) throws -> RealityViewportRegionSegmentProbe
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
                let camera = try projectWithDepth(worldPoint)
                guard let projected = camera.point,
                      depthInterval.contains(camera.depth),
                      rect.contains(projected),
                      try retainsSectionedPoint(worldPoint),
                      try isRegionVisible(
                          depth: camera.depth,
                          at: projected,
                          regionFragmentDepth: regionFragmentDepth
                      ) else { continue }
                admitted.insert(vertex.componentID)
                components.append(.vertex(vertex.componentID))
            }
        }

        guard selectionHitPolicy.allowsEdgeHits else { return components }
        for edge in topology.edges where admitted.contains(edge.componentID) == false {
            let worldStart = world(edge.start, modelTransform: modelTransform)
            let worldEnd = world(edge.end, modelTransform: modelTransform)
            let start = try projectWithDepth(worldStart)
            let end = try projectWithDepth(worldEnd)
            guard let drawn = ViewportCameraDepthClip.clippedParameterInterval(
                startDepth: start.depth, endDepth: end.depth, to: depthInterval
            ) else { continue }
            var retained = ViewportCameraDepthClip.ParameterInterval.whole
            if let bound = try sectionParameterBound(worldStart, worldEnd) {
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
            let clippedStart = lower == 0 ? start : try projectWithDepth(drawnStart)
            let clippedEnd = upper == 1 ? end : try projectWithDepth(drawnEnd)
            guard let screenStart = clippedStart.point,
                  let screenEnd = clippedEnd.point else { continue }
            guard try regionSegmentAdmits(
                from: screenStart,
                to: screenEnd,
                worldStart: drawnStart,
                worldEnd: drawnEnd,
                startDepth: clippedStart.depth,
                endDepth: clippedEnd.depth,
                usesPerspectiveProjection: usesPerspectiveProjection,
                projectWithDepth: projectWithDepth,
                regionSegmentProbe: regionSegmentProbe
            ) else { continue }
            admitted.insert(edge.componentID)
            components.append(.edge(edge.componentID))
        }
        return components
    }

    private static func world(_ point: Point3D, modelTransform: Transform3D) -> Point3D {
        ViewportLayout.transformedPoint(point, by: modelTransform)
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
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?,
        surfaceHit: (CGPoint) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        retainsSectionedPoint: (Point3D) throws -> Bool
    ) throws -> Bool {
        guard try retainsSectionedPoint(worldPoint) else { return false }
        guard let surface = try surfaceHit(candidate.point),
              let surfaceDepth = try project(surface.point)?.depth else {
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
        regionFragmentDepth: (CGPoint) throws -> Double?
    ) throws -> Bool {
        guard let fragmentDepth = try regionFragmentDepth(point) else { return true }
        return depth - fragmentDepth <= abs(depth) * depthSlack
    }

    /// Walks a projected edge one device pixel at a time and reports whether
    /// the rectangle admits it.
    ///
    /// The probe owns the walk's geometry. It clips the segment to the
    /// rectangle's device pixels and reports the first pixel of the remaining
    /// walk the frame draws at, with that pixel's parameter along the segment
    /// it was given. A walk that meets no pixel of the rectangle answers no,
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
        usesPerspectiveProjection: Bool,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double),
        regionSegmentProbe: (CGPoint, CGPoint, Int) throws -> RealityViewportRegionSegmentProbe
    ) throws -> Bool {
        var step = 0
        while true {
            let probe = try regionSegmentProbe(screenStart, screenEnd, step)
            guard step < probe.stepCount else { return false }
            guard let drawn = probe.drawn else { return true }
            guard drawn.step == step else { return true }
            guard let parameter = worldParameter(
                      forScreenParameter: drawn.fraction,
                      startDepth: startDepth,
                      endDepth: endDepth,
                      usesPerspectiveProjection: usesPerspectiveProjection
                  ),
                  let worldPoint = ViewportCameraDepthClip.interpolated(
                      worldStart, worldEnd, parameter
                  ) else {
                step = drawn.step + 1
                continue
            }
            let depth = try projectWithDepth(worldPoint).depth
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

    /// Maps a parameter along a *projected* segment back to the segment's own
    /// parameter in world space.
    ///
    /// An orthographic camera projects the segment affinely, so the two
    /// parameters are the same. A perspective camera makes reciprocal depth —
    /// not depth — linear on screen, so the world parameter is recovered from
    /// the endpoint depths. Which of the two applies is a property of the
    /// mounted camera, never of the sign of the sampled depths: with an
    /// orthographic camera both depths are positive and the perspective rule
    /// would still report the wrong point. Returns nil when the perspective
    /// recovery has no finite solution, which drops the candidate rather than
    /// substituting the other camera's rule.
    private static func worldParameter(
        forScreenParameter parameter: Double,
        startDepth: Double,
        endDepth: Double,
        usesPerspectiveProjection: Bool
    ) -> Double? {
        guard parameter.isFinite else { return nil }
        guard usesPerspectiveProjection else { return parameter }
        guard startDepth > 0, endDepth > 0 else { return nil }
        let reciprocal = (1.0 - parameter) / startDepth + parameter / endDepth
        guard reciprocal.isFinite, reciprocal > 0 else { return nil }
        let world = (parameter / endDepth) / reciprocal
        guard world.isFinite else { return nil }
        return world
    }
}
