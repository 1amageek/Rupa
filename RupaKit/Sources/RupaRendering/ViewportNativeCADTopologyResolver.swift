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
    /// vertex is inside when its projected point is, with no tolerance. An edge
    /// is clipped rather than sampled at a fixed pitch, because a pitch would
    /// make a short edge's admission depend on zoom; the midpoint of the
    /// surviving screen interval is mapped back to the edge's own world
    /// parameter under the frame's projection rule, so no depth on this path is
    /// interpolated by a rule the frame does not use. One sample per edge
    /// bounds the cost and rejects an edge occluded at that point even when an
    /// unoccluded part of it lies inside the rectangle.
    ///
    /// A face asks the frame one question at a representative point inside both
    /// the triangle and the rectangle: which triangle it draws there. That one
    /// answer carries occlusion and section at once, because the frame draws
    /// only what survived the section and only what nothing nearer covers, so
    /// this branch forms no depth compare and no world point of its own.
    /// `bodyDrawsTriangle` is not redundant with the run lookup: mesh face
    /// identities are numbered per body, so another body's triangle can carry an
    /// index that also names a run of this body, and admitting it would select a
    /// face standing behind another solid.
    ///
    /// A run whose projected bounds miss the rectangle, a triangle the camera
    /// cannot project, and a representative point the frame answers with another
    /// body's triangle are all valid misses. Readiness, camera revision and
    /// projection failures stay typed and are propagated from the injected
    /// native queries, and a `mesh` that does not hold a prepared run's
    /// triangles is malformed preparation rather than a body whose faces are
    /// silently skipped.
    static func resolve(
        in rect: CGRect,
        topology: ViewportBodyTopology,
        mesh: ViewportBodyMesh,
        modelTransform: Transform3D,
        selectionHitPolicy: ViewportSelectionHitPolicy,
        usesPerspectiveProjection: Bool,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?,
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
                guard let start = try project(worldStart),
                      let end = try project(worldEnd),
                      let interval = clippedParameterInterval(
                          from: start.point, to: end.point, in: rect
                      ) else { continue }
                guard let edgeParameter = worldParameter(
                    forScreenParameter: (interval.lower + interval.upper) / 2,
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
                admitted.insert(edge.componentID)
                components.append(.edge(edge.componentID))
            }
        }

        guard selectionHitPolicy.allowsFaceHits else {
            return components
        }
        for run in topology.meshFaceRuns where admitted.contains(run.componentID) == false {
            guard try runMayMeetRectangle(
                triangleRange: run.triangleRange,
                mesh: mesh,
                modelTransform: modelTransform,
                rect: rect,
                project: project
            ) else { continue }
            guard let representative = try representativePoint(
                triangleRange: run.triangleRange,
                mesh: mesh,
                modelTransform: modelTransform,
                rect: rect,
                project: project
            ) else { continue }
            guard let surface = try surfaceHit(representative),
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
        }
        return components
    }

    /// Whether a recorded run can still meet the rectangle.
    ///
    /// The model transform is affine, so the convex hull of the eight
    /// transformed corners of the run's body-local bounding box contains the
    /// run, and their projected bounds contain its projection whenever the
    /// camera answers for all eight. A corner the camera cannot project, and a
    /// box no finite bound describes, therefore widen the search instead of
    /// losing the face. The box itself is CPU arithmetic over the prepared
    /// mesh; only the eight corners reach the frame, which is what keeps a
    /// rectangle update in the cost class of the pointer query rather than of
    /// the triangle count.
    private static func runMayMeetRectangle(
        triangleRange: Range<Int>,
        mesh: ViewportBodyMesh,
        modelTransform: Transform3D,
        rect: CGRect,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?
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
            guard let projected = try project(world(point, modelTransform: modelTransform)),
                  projected.point.x.isFinite, projected.point.y.isFinite else {
                return true
            }
            minimum = CGPoint(
                x: min(minimum.x, projected.point.x),
                y: min(minimum.y, projected.point.y)
            )
            maximum = CGPoint(
                x: max(maximum.x, projected.point.x),
                y: max(maximum.y, projected.point.y)
            )
        }
        return maximum.x >= rect.minX && minimum.x <= rect.maxX
            && maximum.y >= rect.minY && minimum.y <= rect.maxY
    }

    /// The first triangle of the run whose projection meets the rectangle,
    /// reported as a point inside both.
    ///
    /// The scan follows emission order and stops at the first such triangle:
    /// one point of the overlap is enough to ask the frame whether it draws this
    /// face there, and scanning further would cost a native projection per
    /// triangle. That the answer is taken at this one point is what makes a face
    /// occluded there a miss even when a later triangle of the same face is
    /// visible.
    private static func representativePoint(
        triangleRange: Range<Int>,
        mesh: ViewportBodyMesh,
        modelTransform: Transform3D,
        rect: CGRect,
        project: (Point3D) throws -> (point: CGPoint, depth: Double)?
    ) throws -> CGPoint? {
        for triangleIndex in triangleRange {
            let vertices = try triangleVertices(mesh: mesh, triangleIndex: triangleIndex)
            guard let first = try project(world(vertices.0, modelTransform: modelTransform)),
                  let second = try project(world(vertices.1, modelTransform: modelTransform)),
                  let third = try project(world(vertices.2, modelTransform: modelTransform)) else {
                continue
            }
            if let centroid = clippedCentroid(
                first.point, second.point, third.point, in: rect
            ) {
                return centroid
            }
        }
        return nil
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

    private static func triangleVertices(
        mesh: ViewportBodyMesh,
        triangleIndex: Int
    ) throws -> (Point3D, Point3D, Point3D) {
        let positions = mesh.positions
        let indices = mesh.indices
        let base = try triangleIndexBase(triangleIndex, indexCount: indices.count)
        let first = try vertexIndex(indices[base], positionCount: positions.count)
        let second = try vertexIndex(indices[base + 1], positionCount: positions.count)
        let third = try vertexIndex(indices[base + 2], positionCount: positions.count)
        return (positions[first], positions[second], positions[third])
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

    /// The parameter interval of a projected segment that lies inside the
    /// rectangle, or nil when the segment misses it.
    ///
    /// Liang–Barsky in the segment's own screen parameter, so an edge whose two
    /// endpoints both lie outside still reports the interval it crosses.
    private static func clippedParameterInterval(
        from start: CGPoint,
        to end: CGPoint,
        in rect: CGRect
    ) -> (lower: Double, upper: Double)? {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            return nil
        }
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        var lower = 0.0
        var upper = 1.0
        for (denominator, numerator) in [
            (-dx, Double(start.x - rect.minX)),
            (dx, Double(rect.maxX - start.x)),
            (-dy, Double(start.y - rect.minY)),
            (dy, Double(rect.maxY - start.y)),
        ] {
            guard denominator != 0 else {
                if numerator < 0 { return nil }
                continue
            }
            let parameter = numerator / denominator
            guard parameter.isFinite else { return nil }
            if denominator < 0 {
                if parameter > upper { return nil }
                if parameter > lower { lower = parameter }
            } else {
                if parameter < lower { return nil }
                if parameter < upper { upper = parameter }
            }
        }
        guard lower <= upper else { return nil }
        return (lower, upper)
    }

    /// A point inside both a projected triangle and the rectangle, or nil when
    /// they do not meet.
    ///
    /// The triangle is clipped against the rectangle's four half-planes, so the
    /// surviving polygon is convex and lies inside both. The mean of a convex
    /// polygon's vertices lies inside it, which is what lets one native surface
    /// query at that point stand for the whole overlap.
    private static func clippedCentroid(
        _ first: CGPoint,
        _ second: CGPoint,
        _ third: CGPoint,
        in rect: CGRect
    ) -> CGPoint? {
        var polygon = [first, second, third]
        guard polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        for boundary in RectangleBoundary.allCases {
            guard polygon.isEmpty == false else { return nil }
            var clipped: [CGPoint] = []
            clipped.reserveCapacity(polygon.count + 1)
            for index in polygon.indices {
                let current = polygon[index]
                let previous = polygon[(index + polygon.count - 1) % polygon.count]
                let retainsCurrent = boundary.retains(current, in: rect)
                let retainsPrevious = boundary.retains(previous, in: rect)
                if retainsCurrent {
                    if retainsPrevious == false {
                        clipped.append(boundary.intersection(from: previous, to: current, in: rect))
                    }
                    clipped.append(current)
                } else if retainsPrevious {
                    clipped.append(boundary.intersection(from: previous, to: current, in: rect))
                }
            }
            polygon = clipped
        }
        guard polygon.isEmpty == false else { return nil }
        var sumX = 0.0
        var sumY = 0.0
        for point in polygon {
            sumX += Double(point.x)
            sumY += Double(point.y)
        }
        let count = Double(polygon.count)
        let centroid = CGPoint(x: CGFloat(sumX / count), y: CGFloat(sumY / count))
        guard centroid.x.isFinite, centroid.y.isFinite else { return nil }
        return centroid
    }

    private enum RectangleBoundary: CaseIterable {
        case minX
        case maxX
        case minY
        case maxY

        func retains(_ point: CGPoint, in rect: CGRect) -> Bool {
            switch self {
            case .minX: point.x >= rect.minX
            case .maxX: point.x <= rect.maxX
            case .minY: point.y >= rect.minY
            case .maxY: point.y <= rect.maxY
            }
        }

        /// The crossing of a segment with this boundary.
        ///
        /// The caller forms it only for a segment with one retained and one
        /// rejected endpoint, so the denominator below is non-zero there; the
        /// guard keeps the function total rather than describing a reachable
        /// case.
        func intersection(from start: CGPoint, to end: CGPoint, in rect: CGRect) -> CGPoint {
            switch self {
            case .minX, .maxX:
                let bound = self == .minX ? rect.minX : rect.maxX
                let dx = end.x - start.x
                guard dx != 0 else { return CGPoint(x: bound, y: start.y) }
                let parameter = (bound - start.x) / dx
                return CGPoint(x: bound, y: start.y + (end.y - start.y) * parameter)
            case .minY, .maxY:
                let bound = self == .minY ? rect.minY : rect.maxY
                let dy = end.y - start.y
                guard dy != 0 else { return CGPoint(x: start.x, y: bound) }
                let parameter = (bound - start.y) / dy
                return CGPoint(x: start.x + (end.x - start.x) * parameter, y: bound)
            }
        }
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
