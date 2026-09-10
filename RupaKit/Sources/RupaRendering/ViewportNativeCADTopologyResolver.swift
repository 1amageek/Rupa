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

    /// Resolves every prepared CAD sub-shape of one body that meets a screen
    /// rectangle.
    ///
    /// This is a set query, not a nearest query: a rectangle asks which
    /// sub-shapes lie inside a region, so `Candidate` and its rank-then-metric
    /// order have no role here and nothing precedes anything else. The result
    /// follows the recorded topology order — vertices, then edges, then the
    /// recorded runs — and is de-duplicated by prepared identity, because one
    /// CAD face can own more than one recorded run.
    ///
    /// Vertices and edges reuse the point query's visibility rule verbatim, so
    /// a sub-shape cannot be visible to one query and hidden to the other. A
    /// vertex is inside when its projected point is, with no tolerance.
    ///
    /// Edges and faces are first clipped against the mounted camera's own depth
    /// interval in world space, so a primitive crossing a clip plane
    /// contributes the part the camera draws instead of being dropped whole.
    /// A vertex that clip creates carries no projection, because screen
    /// position is not affine under a perspective camera, so it is projected
    /// again rather than interpolated.
    ///
    /// What survives is then sampled on `ViewportRectangleSampleGrid`, which
    /// divides the rectangle into cells and keeps, per cell, the largest
    /// fragment the candidate contributed there. A candidate is admitted when
    /// the frame confirms it at any one of those samples. Two properties of
    /// that rule are the reason it replaced a single representative point:
    /// the per-cell maximum is a function of the fragment set and not of the
    /// order the tessellator emitted its triangles, and a candidate showing an
    /// axis-aligned window at least two cells wide inside the rectangle always
    /// has a sample inside that window, so a section cut or a nearer solid
    /// covering part of a face no longer loses the rest of it. The samples cost
    /// at most `maxRectangleSurfaceQueryCountPerCandidate` native queries per
    /// sub-shape, and the frame is asked in the grid's query order only until
    /// one sample is confirmed.
    ///
    /// A face's samples ask the frame which triangle it draws there. That one
    /// answer carries occlusion and section at once, because the frame draws
    /// only what survived the section and only what nothing nearer covers, so
    /// this branch forms no depth compare and no world point of its own.
    /// `bodyDrawsTriangle` is not redundant with the run lookup: mesh face
    /// identities are numbered per body, so another body's triangle can carry an
    /// index that also names a run of this body, and admitting it would select a
    /// face standing behind another solid.
    ///
    /// A run whose projected bounds miss the rectangle, a primitive the camera
    /// draws none of, and samples the frame answers with another body's
    /// triangle are all valid misses. Readiness, camera revision and projection
    /// failures stay typed and are propagated from the injected native queries,
    /// and a `mesh` that does not hold a prepared run's triangles is malformed
    /// preparation rather than a body whose faces are silently skipped.
    static func resolve(
        in rect: CGRect,
        topology: ViewportBodyTopology,
        mesh: ViewportBodyMesh,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        usesPerspectiveProjection: Bool,
        depthInterval: ClosedRange<Double>,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double),
        surfaceHit: (CGPoint) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        retainsSectionedPoint: (Point3D) throws -> Bool,
        bodyDrawsTriangle: (MeshSourcePresentationTriangle) throws -> Bool
    ) throws -> [SelectionComponent] {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              rect.size.width > 0, rect.size.height > 0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology rectangle query bounds are invalid."
            )
        }
        guard ViewportCameraDepthClip.canClip(against: depthInterval) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "CAD topology rectangle query camera depth bounds are invalid."
            )
        }
        let grid = ViewportRectangleSampleGrid(rect: rect)

        var components: [SelectionComponent] = []
        var admitted: Set<SelectionComponentID> = []

        if selectionHitPolicy.allowsVertexHits {
            for vertex in topology.vertices where admitted.contains(vertex.componentID) == false {
                let worldPoint = world(vertex.point, modelTransform: modelTransform)
                guard let projected = try project(worldPoint),
                      rect.contains(projected.point),
                      try isVisible(
                          worldPoint,
                          projected,
                          project: project,
                          surfaceHit: surfaceHit,
                          retainsSectionedPoint: retainsSectionedPoint
                      ) else { continue }
                admitted.insert(vertex.componentID)
                components.append(.vertex(vertex.componentID))
            }
        }

        if selectionHitPolicy.allowsEdgeHits {
            for edge in topology.edges where admitted.contains(edge.componentID) == false {
                let worldStart = world(edge.start, modelTransform: modelTransform)
                let worldEnd = world(edge.end, modelTransform: modelTransform)
                let start = try projectWithDepth(worldStart)
                let end = try projectWithDepth(worldEnd)
                guard let drawn = ViewportCameraDepthClip.clippedParameterInterval(
                    startDepth: start.depth, endDepth: end.depth, to: depthInterval
                ) else { continue }
                guard let drawnStart = ViewportCameraDepthClip.interpolated(
                          worldStart, worldEnd, drawn.lower
                      ),
                      let drawnEnd = ViewportCameraDepthClip.interpolated(
                          worldStart, worldEnd, drawn.upper
                      ) else { continue }
                let clippedStart = drawn.lower == 0 ? start : try projectWithDepth(drawnStart)
                let clippedEnd = drawn.upper == 1 ? end : try projectWithDepth(drawnEnd)
                guard let screenStart = clippedStart.point,
                      let screenEnd = clippedEnd.point else { continue }
                var isAdmitted = false
                for sample in grid.segmentSamples(from: screenStart, to: screenEnd) {
                    guard let edgeParameter = worldParameter(
                        forScreenParameter: sample,
                        startDepth: clippedStart.depth,
                        endDepth: clippedEnd.depth,
                        usesPerspectiveProjection: usesPerspectiveProjection
                    ) else { continue }
                    guard let worldPoint = ViewportCameraDepthClip.interpolated(
                        drawnStart, drawnEnd, edgeParameter
                    ) else { continue }
                    guard let projected = try project(worldPoint),
                          try isVisible(
                              worldPoint,
                              projected,
                              project: project,
                              surfaceHit: surfaceHit,
                              retainsSectionedPoint: retainsSectionedPoint
                          ) else { continue }
                    isAdmitted = true
                    break
                }
                guard isAdmitted else { continue }
                admitted.insert(edge.componentID)
                components.append(.edge(edge.componentID))
            }
        }

        guard selectionHitPolicy.allowsFaceHits else {
            return components
        }
        // The mesh positions belong to the whole body, so a position two runs
        // share is projected once and indexed twice. The table is allocated on
        // the first position a surviving run asks for and never before, so a
        // run the bounds test skips projects none of its positions and a body
        // the rectangle misses entirely costs nothing here.
        var bodyPositions: [ProjectedPosition?] = []
        func projectedPosition(at index: Int) throws -> ProjectedPosition {
            if bodyPositions.isEmpty {
                bodyPositions = [ProjectedPosition?](
                    repeating: nil, count: mesh.positions.count
                )
            }
            if let cached = bodyPositions[index] { return cached }
            let worldPoint = world(mesh.positions[index], modelTransform: modelTransform)
            let camera = try projectWithDepth(worldPoint)
            let projected = ProjectedPosition(
                world: worldPoint, point: camera.point, depth: camera.depth
            )
            bodyPositions[index] = projected
            return projected
        }

        for run in topology.meshFaceRuns where admitted.contains(run.componentID) == false {
            guard try runMayMeetRectangle(
                triangleRange: run.triangleRange,
                mesh: mesh,
                modelTransform: modelTransform,
                rect: rect,
                depthInterval: depthInterval,
                projectWithDepth: projectWithDepth
            ) else { continue }
            var sampler = grid.polygonSampler()
            for triangleIndex in run.triangleRange {
                let corners = try triangleVertexIndices(mesh: mesh, triangleIndex: triangleIndex)
                var cornerVertices: [ViewportCameraDepthClip.Vertex] = []
                cornerVertices.reserveCapacity(3)
                for index in [corners.0, corners.1, corners.2] {
                    let position = try projectedPosition(at: index)
                    cornerVertices.append(
                        ViewportCameraDepthClip.Vertex(
                            point: position.world,
                            depth: position.depth,
                            projected: position.point
                        )
                    )
                }
                let drawn = ViewportCameraDepthClip.clipped(cornerVertices, to: depthInterval)
                guard drawn.count >= 3 else { continue }
                var screen: [CGPoint] = []
                screen.reserveCapacity(drawn.count)
                for vertex in drawn {
                    if let projected = vertex.projected {
                        screen.append(projected)
                        continue
                    }
                    // A vertex the clip created has no projection yet, and a
                    // vertex the camera does not answer for is dropped rather
                    // than guessed: the remaining vertices still span a convex
                    // subset of the drawn fragment, so the sample stays inside
                    // it.
                    guard let projected = try projectWithDepth(vertex.point).point else { continue }
                    screen.append(projected)
                }
                guard screen.count >= 3 else { continue }
                sampler.admit(screen)
            }
            for sample in sampler.samples() {
                guard let surface = try surfaceHit(sample),
                      try bodyDrawsTriangle(surface.triangle) else { continue }
                guard let triangleIndex = Int(exactly: surface.triangle.faceID.rawValue) else {
                    throw MeshSourcePresentationRenderError(
                        code: .invalidSceneItem,
                        message: "A drawn CAD triangle reports an unrepresentable mesh face identity."
                    )
                }
                guard topology.componentID(forTriangle: triangleIndex) == run.componentID else {
                    continue
                }
                admitted.insert(run.componentID)
                components.append(.face(run.componentID))
                break
            }
        }
        return components
    }

    /// One body mesh position as the rectangle's face path holds it: the world
    /// point, the mounted camera's depth for it, and its projection wherever the
    /// camera answers for one.
    private struct ProjectedPosition {
        let world: Point3D
        let point: CGPoint?
        let depth: Double
    }

    /// Whether a recorded run can still meet the rectangle.
    ///
    /// The model transform is affine, so the convex hull of the eight
    /// transformed corners of the run's body-local bounding box contains the
    /// run, and their projected bounds contain its projection whenever the
    /// camera answers for all eight and draws all eight. A corner the camera
    /// cannot project, a corner outside the camera's depth interval, and a box
    /// no finite bound describes therefore widen the search instead of losing
    /// the face: the box may still straddle a clip plane and be drawn in part.
    /// The box itself is CPU arithmetic over the prepared mesh; only the eight
    /// corners reach the frame, which is what keeps a rectangle update in the
    /// cost class of the pointer query rather than of the triangle count.
    private static func runMayMeetRectangle(
        triangleRange: Range<Int>,
        mesh: ViewportBodyMesh,
        modelTransform: Transform3D,
        rect: CGRect,
        depthInterval: ClosedRange<Double>,
        projectWithDepth: (Point3D) throws -> (point: CGPoint?, depth: Double)
    ) throws -> Bool {
        guard let bounds = try localBounds(mesh: mesh, triangleRange: triangleRange) else {
            return true
        }
        var minimum = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        var maximum = CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)
        for corner in 0..<8 {
            let point = Point3D(
                x: corner & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
                y: corner & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
                z: corner & 4 == 0 ? bounds.minimum.z : bounds.maximum.z
            )
            let camera = try projectWithDepth(world(point, modelTransform: modelTransform))
            guard depthInterval.contains(camera.depth) else { return true }
            guard let projected = camera.point,
                  projected.x.isFinite, projected.y.isFinite else {
                return true
            }
            minimum = CGPoint(
                x: min(minimum.x, projected.x),
                y: min(minimum.y, projected.y)
            )
            maximum = CGPoint(
                x: max(maximum.x, projected.x),
                y: max(maximum.y, projected.y)
            )
        }
        return maximum.x >= rect.minX && minimum.x <= rect.maxX
            && maximum.y >= rect.minY && minimum.y <= rect.maxY
    }

    /// The body-local bounding box of a run's triangles, or nil when no finite
    /// box describes them.
    ///
    /// A run naming a triangle or a vertex the prepared mesh does not hold is
    /// malformed preparation: the run list and the mesh are written from one
    /// body display snapshot, so they cannot legitimately disagree, and
    /// reporting the disagreement as an empty box would silently drop the face.
    private static func localBounds(
        mesh: ViewportBodyMesh,
        triangleRange: Range<Int>
    ) throws -> (minimum: Point3D, maximum: Point3D)? {
        let positions = mesh.positions
        let indices = mesh.indices
        var minimum = Point3D(x: .infinity, y: .infinity, z: .infinity)
        var maximum = Point3D(x: -.infinity, y: -.infinity, z: -.infinity)
        for triangleIndex in triangleRange {
            let base = try triangleIndexBase(triangleIndex, indexCount: indices.count)
            for offset in 0..<3 {
                let index = try vertexIndex(
                    indices[base + offset], positionCount: positions.count
                )
                let position = positions[index]
                minimum = Point3D(
                    x: min(minimum.x, position.x),
                    y: min(minimum.y, position.y),
                    z: min(minimum.z, position.z)
                )
                maximum = Point3D(
                    x: max(maximum.x, position.x),
                    y: max(maximum.y, position.y),
                    z: max(maximum.z, position.z)
                )
            }
        }
        guard minimum.x.isFinite, minimum.y.isFinite, minimum.z.isFinite,
              maximum.x.isFinite, maximum.y.isFinite, maximum.z.isFinite else {
            return nil
        }
        return (minimum, maximum)
    }

    /// The three body mesh position indices of one triangle.
    ///
    /// The face path memoizes one projection per position it references, so it
    /// needs the indices to look those up rather than the points themselves.
    private static func triangleVertexIndices(
        mesh: ViewportBodyMesh,
        triangleIndex: Int
    ) throws -> (Int, Int, Int) {
        let positionCount = mesh.positions.count
        let indices = mesh.indices
        let base = try triangleIndexBase(triangleIndex, indexCount: indices.count)
        return (
            try vertexIndex(indices[base], positionCount: positionCount),
            try vertexIndex(indices[base + 1], positionCount: positionCount),
            try vertexIndex(indices[base + 2], positionCount: positionCount)
        )
    }

    private static func triangleIndexBase(
        _ triangleIndex: Int,
        indexCount: Int
    ) throws -> Int {
        let base = triangleIndex * 3
        guard triangleIndex >= 0, base >= 0, base + 2 < indexCount else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "A prepared CAD face run names a triangle the body mesh does not hold."
            )
        }
        return base
    }

    private static func vertexIndex(
        _ rawValue: UInt32,
        positionCount: Int
    ) throws -> Int {
        guard let index = Int(exactly: rawValue), index >= 0, index < positionCount else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "A prepared CAD face run names a mesh vertex the body mesh does not hold."
            )
        }
        return index
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
