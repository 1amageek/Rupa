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
    /// same rank: projected point distance for a vertex or edge, and depth
    /// offset from the native visible surface for a face. The caller compares
    /// candidates from different bodies through this order, so the nearest
    /// projected sub-shape wins across the scene instead of the first body that
    /// happens to answer.
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
    /// `visibleSurfaceDepth` is the camera depth of the native surface *this
    /// body* draws at the pointer, and nil when the frame draws no surface of
    /// this body there. It ranks faces only. Vertices and edges are searched
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
        visibleSurfaceDepth: Double?,
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

        func world(_ point: Point3D) -> Point3D {
            ViewportLayout.transformedPoint(point, by: modelTransform)
        }

        /// Admits a sub-shape point only when the mounted frame still retains
        /// it through the active section, and then rejects it only when the
        /// frame draws a nearer surface at the point's own pixel.
        ///
        /// The section query runs first because an empty pixel is ambiguous on
        /// its own: a silhouette vertex and a vertex the section cut away both
        /// draw nothing. Asking the frame which of the two it is keeps the
        /// silhouette rescue below from admitting geometry that is not in the
        /// frame at all. A pixel that draws nothing then hides nothing, which
        /// is what keeps silhouette vertices and outline edges selectable:
        /// their exact B-Rep point lands on the tessellated outline, where the
        /// native ray may pass either side of the boundary.
        func isVisible(
            _ worldPoint: Point3D,
            _ candidate: (point: CGPoint, depth: Double)
        ) throws -> Bool {
            guard try retainsSectionedPoint(worldPoint) else { return false }
            guard let surface = try surfaceHit(candidate.point),
                  let surfaceDepth = try project(surface.point)?.depth else {
                return true
            }
            return candidate.depth - surfaceDepth <= abs(candidate.depth) * depthSlack
        }

        if selectionHitPolicy.allowsVertexHits {
            var best: Candidate?
            for vertex in topology.vertices {
                let worldPoint = world(vertex.point)
                guard let projected = try project(worldPoint) else { continue }
                let distance = Double(hypot(point.x - projected.point.x, point.y - projected.point.y))
                guard distance <= Double(tolerance), distance < (best?.metric ?? .infinity),
                      try isVisible(worldPoint, projected) else { continue }
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
                let worldStart = world(edge.start)
                let worldEnd = world(edge.end)
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
                      try isVisible(worldPoint, projected) else { continue }
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
        // query. The drawn depth then fixes the front-most face and no
        // additional occlusion threshold is required.
        //
        // FIXME(INCOMPLETE_IMPLEMENTATION): The branch below re-estimates which
        // CAD face a pixel belongs to by projecting every face loop on the CPU
        // and comparing its interpolated depth against the drawn surface. That
        // is a second face-selection rule, not the prepared CAD identity of the
        // triangle the native frame actually hit, so it can disagree with the
        // drawn frame wherever the two rules differ.
        //
        // Production path: `Viewport.presentationCADSubshapeHit(at:visibleSurface:in:)`
        // reaches it for every `.face` and `.all` pointer query over a body
        // with prepared topology, so hover and click already pick faces here.
        //
        // Do not treat CAD face selection as migrated until the native hit
        // triangle carries prepared CAD face provenance — a
        // `MeshSourcePresentationTriangle.faceID` that maps to the topology's
        // `SelectionComponentID` — and this branch becomes that table lookup,
        // deleting `containedDepth`, `fanDepth`, `contains`, the weighted
        // `interpolatedDepth` and the `visibleSurfaceDepth` parameter. The
        // mapping does not exist yet: the tessellator discards the kernel
        // `FaceID` while compacting a mesh, so establishing it starts there.
        guard selectionHitPolicy.allowsFaceHits, let visibleSurfaceDepth else {
            return nil
        }
        var best: Candidate?
        for face in topology.faces {
            var polygon: [(point: CGPoint, depth: Double)] = []
            polygon.reserveCapacity(face.points.count)
            for facePoint in face.points {
                guard let projected = try project(world(facePoint)) else {
                    polygon.removeAll()
                    break
                }
                polygon.append(projected)
            }
            guard polygon.count == face.points.count, polygon.count >= 3,
                  let depth = containedDepth(
                      of: point,
                      in: polygon,
                      tolerance: tolerance,
                      usesPerspectiveProjection: usesPerspectiveProjection
                  ) else {
                continue
            }
            let offset = abs(depth - visibleSurfaceDepth)
            guard offset < (best?.metric ?? .infinity) else { continue }
            best = Candidate(
                component: .face(face.componentID),
                rank: .face,
                metric: offset
            )
        }
        return best
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

    /// Interpolates camera depth along a projected segment under the mounted
    /// camera's own projection: depth is linear on screen under an orthographic
    /// camera, and reciprocal depth is linear on screen under a perspective
    /// camera.
    private static func interpolatedDepth(
        _ start: Double,
        _ end: Double,
        parameter: Double,
        usesPerspectiveProjection: Bool
    ) -> Double {
        guard usesPerspectiveProjection, start > 0, end > 0 else {
            return start + (end - start) * parameter
        }
        let reciprocal = 1.0 / start + (1.0 / end - 1.0 / start) * parameter
        guard reciprocal.isFinite, reciprocal != 0 else { return .nan }
        return 1.0 / reciprocal
    }

    /// Returns the camera depth of the face at `point`, or nil when the
    /// projected outer loop does not contain it.
    ///
    /// Containment uses even-odd ray casting, so a non-convex outer loop — the
    /// face of an L-shaped extrusion, for example — is admitted exactly. A fan
    /// triangulation would both miss its reflex interior and cover area outside
    /// it, and this path has to keep the containment rule of the projected
    /// topology tester it replaces.
    private static func containedDepth(
        of point: CGPoint,
        in polygon: [(point: CGPoint, depth: Double)],
        tolerance: CGFloat,
        usesPerspectiveProjection: Bool
    ) -> Double? {
        if contains(point, in: polygon),
           let depth = fanDepth(
               of: point, in: polygon, usesPerspectiveProjection: usesPerspectiveProjection
           ) {
            return depth
        }
        guard tolerance > 0 else { return nil }
        // Boundary tolerance: admit the loop edge nearest the query point.
        var best: (distance: CGFloat, depth: Double)?
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let parameter = segmentParameter(for: point, from: start.point, to: end.point)
            let nearest = CGPoint(
                x: start.point.x + (end.point.x - start.point.x) * parameter,
                y: start.point.y + (end.point.y - start.point.y) * parameter
            )
            let distance = hypot(point.x - nearest.x, point.y - nearest.y)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity) else { continue }
            best = (
                distance,
                interpolatedDepth(
                    start.depth,
                    end.depth,
                    parameter: Double(parameter),
                    usesPerspectiveProjection: usesPerspectiveProjection
                )
            )
        }
        return best?.depth
    }

    /// Even-odd containment of a projected outer loop, matching the rule the
    /// projected topology tester applies to the same loop.
    private static func contains(
        _ point: CGPoint,
        in polygon: [(point: CGPoint, depth: Double)]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        for index in polygon.indices {
            let current = polygon[index].point
            let previous = polygon[(index + polygon.count - 1) % polygon.count].point
            guard (current.y > point.y) != (previous.y > point.y) else { continue }
            let crossing = (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y) + current.x
            if point.x < crossing { isInside.toggle() }
        }
        return isInside
    }

    /// Interpolates depth over the loop's fan triangulation. For a convex loop
    /// the containing triangle has no barycentric violation and this is exact.
    /// For a reflex loop the nearest fan cell is used with clamped weights, so
    /// the reported depth stays on the loop's own surface instead of being
    /// extrapolated outside it.
    private static func fanDepth(
        of point: CGPoint,
        in polygon: [(point: CGPoint, depth: Double)],
        usesPerspectiveProjection: Bool
    ) -> Double? {
        var best: (violation: Double, depth: Double)?
        for index in 1 ..< polygon.count - 1 {
            let a = polygon[0], b = polygon[index], c = polygon[index + 1]
            guard let weights = barycentricWeights(
                of: point, a: a.point, b: b.point, c: c.point
            ) else { continue }
            let violation = max(0, -min(weights.a, min(weights.b, weights.c)))
            guard violation < (best?.violation ?? .infinity) else { continue }
            let depth = interpolatedDepth(
                a.depth,
                b.depth,
                c.depth,
                weights: normalizedWeights(weights),
                usesPerspectiveProjection: usesPerspectiveProjection
            )
            guard depth.isFinite else { continue }
            best = (violation, depth)
        }
        return best?.depth
    }

    private static func normalizedWeights(
        _ weights: (a: Double, b: Double, c: Double)
    ) -> (a: Double, b: Double, c: Double) {
        let a = max(0, weights.a)
        let b = max(0, weights.b)
        let c = max(0, weights.c)
        let sum = a + b + c
        guard sum > 0 else { return (a: 1, b: 0, c: 0) }
        return (a: a / sum, b: b / sum, c: c / sum)
    }

    private static func barycentricWeights(
        of point: CGPoint,
        a: CGPoint,
        b: CGPoint,
        c: CGPoint
    ) -> (a: Double, b: Double, c: Double)? {
        let v0 = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let v1 = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let v2 = CGPoint(x: point.x - a.x, y: point.y - a.y)
        let denominator = v0.x * v1.y - v1.x * v0.y
        guard denominator.isFinite, abs(denominator) > 1.0e-12 else { return nil }
        let beta = (v2.x * v1.y - v1.x * v2.y) / denominator
        let gamma = (v0.x * v2.y - v2.x * v0.y) / denominator
        let alpha = 1.0 - beta - gamma
        guard alpha.isFinite, beta.isFinite, gamma.isFinite else { return nil }
        return (Double(alpha), Double(beta), Double(gamma))
    }

    private static func interpolatedDepth(
        _ first: Double,
        _ second: Double,
        _ third: Double,
        weights: (a: Double, b: Double, c: Double),
        usesPerspectiveProjection: Bool
    ) -> Double {
        guard usesPerspectiveProjection, first > 0, second > 0, third > 0 else {
            return first * weights.a + second * weights.b + third * weights.c
        }
        let reciprocal = weights.a / first + weights.b / second + weights.c / third
        guard reciprocal.isFinite, reciprocal != 0 else { return .nan }
        return 1.0 / reciprocal
    }
}
