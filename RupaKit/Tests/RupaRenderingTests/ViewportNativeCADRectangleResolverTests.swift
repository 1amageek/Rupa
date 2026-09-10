import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Synchronization
import Testing
@testable import RupaRendering

// MARK: - Synthetic native frame

/// A deterministic stand-in for the mounted native camera, its surface hit and
/// its render provenance, for the rectangle query.
///
/// The camera looks along +Y from `y = -10`, so camera depth is `y + 10` and
/// one world unit maps to 100 screen points, giving the orthographic screen map
/// `(200 + 100x, 200 - 100z)`. The only surface in the frame is the body's
/// front face, the unit square `x, z in [0, 1]` at camera depth 10.
///
/// `depthInterval` is the mounted camera's own clip range, and the two
/// projection entry points answer it the way the mounted camera does:
/// `projectWithDepth` reports a depth for every point the scene can represent,
/// including one the interval excludes, while `project` admits a point only
/// inside the interval. `unprojectablePoints` reproduces a point the mounted
/// camera declines to project, without making the projection non-affine
/// anywhere else. `coveredScreenRect` is a region another solid stands in front
/// of, so a surface query there answers with a triangle this body did not draw.
/// `section` is the frame's retained half-space, and `drawnByThisBody` is the
/// render provenance the production query derives from the drawn triangle's
/// occurrence.
private struct RectangleFrame {
    static let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.cad.body")
    /// The occurrence of the solid standing in front of `coveredScreenRect`.
    static let coveringOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.cad.covering")

    /// The mesh face identity of the drawn triangle, which is the triangle's
    /// own index in the CAD body's emission order.
    var surfaceFaceID: MeshFaceID = MeshFaceID(0)
    var drawnByThisBody: Bool = true
    var unprojectablePoints: Set<Point3D> = []
    /// The mounted camera's near and far planes, in the depth `y + 10` reports.
    var depthInterval: ClosedRange<Double> = 0.5 ... 100
    /// The screen region another solid draws in front of this body.
    var coveredScreenRect: CGRect?
    /// The retained half-space, in the same world space as the topology:
    /// `dot(point, normal) - offset >= 0`.
    var section: (normal: Vector3D, offset: Double)?
    let log = RectangleFrameLog()

    func projectWithDepth(_ point: Point3D) throws -> (point: CGPoint?, depth: Double) {
        log.recordProjection(of: point)
        let depth = point.y + 10
        guard unprojectablePoints.contains(point) == false else {
            return (point: nil, depth: depth)
        }
        return (
            point: CGPoint(x: 200 + point.x * 100, y: 200 - point.z * 100),
            depth: depth
        )
    }

    func project(_ point: Point3D) throws -> (point: CGPoint, depth: Double)? {
        let camera = try projectWithDepth(point)
        guard depthInterval.contains(camera.depth), let projected = camera.point else {
            return nil
        }
        return (point: projected, depth: camera.depth)
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        log.recordSurfaceQuery(at: point)
        let x = Double(point.x - 200) / 100
        let z = Double(200 - point.y) / 100
        guard x >= 0, x <= 1, z >= 0, z <= 1 else { return nil }
        let surfacePoint = Point3D(x: x, y: 0, z: z)
        // The frame draws nothing where the section removed geometry, so a cut
        // pixel is empty in exactly the same way a silhouette pixel is.
        guard try retainsSectionedPoint(surfacePoint) else { return nil }
        let occurrenceID = coveredScreenRect?.contains(point) == true
            ? RectangleFrame.coveringOccurrenceID
            : RectangleFrame.occurrenceID
        return (
            triangle: frameTriangle(faceID: surfaceFaceID, occurrenceID: occurrenceID),
            point: surfacePoint
        )
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        guard let section else { return true }
        let distance = point.x * section.normal.x
            + point.y * section.normal.y
            + point.z * section.normal.z
        return distance - section.offset >= 0
    }

    func bodyDrawsTriangle(_ triangle: MeshSourcePresentationTriangle) throws -> Bool {
        guard case .cad = triangle.sourceReference else { return false }
        return drawnByThisBody && triangle.occurrenceID == RectangleFrame.occurrenceID
    }
}

/// What the frame was asked, so a test can state the cost contract — which runs
/// were scanned and how many surface queries a rectangle drag costs — instead of
/// only the components it returned.
private final class RectangleFrameLog: Sendable {
    private struct State {
        var projections: [Point3D] = []
        var surfaceQueries: [CGPoint] = []
    }

    private let state = Mutex(State())

    func recordProjection(of point: Point3D) {
        state.withLock { $0.projections.append(point) }
    }

    func recordSurfaceQuery(at point: CGPoint) {
        state.withLock { $0.surfaceQueries.append(point) }
    }

    var projections: [Point3D] {
        state.withLock { $0.projections }
    }

    var surfaceQueries: [CGPoint] {
        state.withLock { $0.surfaceQueries }
    }
}

private func frameTriangle(
    faceID: MeshFaceID,
    occurrenceID: SceneOccurrenceID = RectangleFrame.occurrenceID
) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.cad"),
        representationID: GeometryRepresentationID(rawValue: "representation.cad"),
        sourceReference: .cad(sourceID: "cad.source", outputID: "cad.output"),
        faceID: faceID,
        firstVertexID: MeshVertexID(0),
        secondVertexID: MeshVertexID(1),
        thirdVertexID: MeshVertexID(2),
        firstPosition: GeometryPoint3D(x: 0, y: 0, z: 0),
        secondPosition: GeometryPoint3D(x: 1, y: 0, z: 0),
        thirdPosition: GeometryPoint3D(x: 1, y: 0, z: 1)
    )
}

// MARK: - Prepared CAD identity

private let topologyFeatureID = FeatureID()

private func preparedComponentID(role: String, ordinal: Int) -> SelectionComponentID {
    .generatedTopology(SubshapeID(featureID: topologyFeatureID, role: role, ordinal: ordinal))
}

private let frontFaceComponentID = preparedComponentID(role: "face", ordinal: 3)
private let sideFaceComponentID = preparedComponentID(role: "face", ordinal: 4)
private let insideVertexComponentID = preparedComponentID(role: "vertex", ordinal: 5)
private let nearOutsideVertexComponentID = preparedComponentID(role: "vertex", ordinal: 6)
private let crossingEdgeComponentID = preparedComponentID(role: "edge", ordinal: 11)
private let outsideEdgeComponentID = preparedComponentID(role: "edge", ordinal: 12)

/// The rectangle every test drags, in screen points: `x` in 210...270 and `y`
/// in 110...170.
private let queryRect = CGRect(x: 210, y: 110, width: 60, height: 60)

/// The drawn mesh of the body under test.
///
/// Triangles 0 and 1 are the front face, the unit square at `y = 0` whose
/// projection covers `x` in 200...300 and `y` in 100...200 and therefore meets
/// the rectangle. Triangle 2 is a second face standing at `x` in 2.1...2.9,
/// which projects clear of the rectangle. Its corners are deliberately not
/// axis-aligned with its own bounding box, so a bounding corner can be made
/// unanswerable without also removing one of its drawn vertices.
private func bodyMesh() -> ViewportBodyMesh {
    ViewportBodyMesh(
        positions: [
            Point3D(x: 0, y: 0, z: 0),
            Point3D(x: 1, y: 0, z: 0),
            Point3D(x: 1, y: 0, z: 1),
            Point3D(x: 0, y: 0, z: 1),
            Point3D(x: 2.1, y: 0, z: 0.2),
            Point3D(x: 2.9, y: 0, z: 0.3),
            Point3D(x: 2.5, y: 0.4, z: 0.8),
        ],
        indices: [0, 1, 2, 0, 2, 3, 4, 5, 6]
    )
}

/// The bounding corner of the second face's run that no drawn vertex occupies.
private let sideRunBoundingCorner = Point3D(x: 2.1, y: 0, z: 0.8)

/// A vertex inside the rectangle, a vertex four points outside it, an edge that
/// crosses the rectangle with both endpoints outside, an edge that misses it,
/// and the two prepared runs of `bodyMesh()`.
private func bodyTopology(
    meshFaceRuns: [ViewportBodyTopology.MeshFaceRun]? = nil
) -> ViewportBodyTopology {
    ViewportBodyTopology(
        faces: [],
        edges: [
            .init(
                componentID: crossingEdgeComponentID,
                start: Point3D(x: 0, y: 0, z: 0.5),
                end: Point3D(x: 1, y: 0, z: 0.5)
            ),
            .init(
                componentID: outsideEdgeComponentID,
                start: Point3D(x: 0, y: 0, z: 0.95),
                end: Point3D(x: 1, y: 0, z: 0.95)
            ),
        ],
        vertices: [
            .init(componentID: insideVertexComponentID, point: Point3D(x: 0.5, y: 0, z: 0.5)),
            .init(componentID: nearOutsideVertexComponentID, point: Point3D(x: 0.06, y: 0, z: 0.5)),
        ],
        meshFaceRuns: meshFaceRuns ?? [
            .init(componentID: frontFaceComponentID, triangleRange: 0 ..< 2),
            .init(componentID: sideFaceComponentID, triangleRange: 2 ..< 3),
        ]
    )
}

/// A face the camera's near plane cuts.
///
/// Two corners stand at camera depth -9, behind the near plane at 0.5, and the
/// third stands at depth 10. The camera draws the part between them, the
/// triangle `(230, 140)`, `(250, 100)`, `(270, 140)`, which meets the
/// rectangle.
private func nearPlaneCrossingMesh() -> ViewportBodyMesh {
    ViewportBodyMesh(
        positions: [
            Point3D(x: 0.1, y: -19, z: 0.2),
            Point3D(x: 0.9, y: -19, z: 0.2),
            Point3D(x: 0.5, y: 0, z: 1.0),
        ],
        indices: [0, 1, 2]
    )
}

/// A face whose projection meets the rectangle only where the near plane cut it
/// away.
///
/// Unclipped it covers the middle of the rectangle; the part the camera draws
/// projects to `y` in 90...99, clear of it.
private func nearPlaneRejectedMesh() -> ViewportBodyMesh {
    ViewportBodyMesh(
        positions: [
            Point3D(x: 0.1, y: -95, z: 0.2),
            Point3D(x: 0.9, y: -95, z: 0.2),
            Point3D(x: 0.5, y: 0, z: 1.1),
        ],
        indices: [0, 1, 2]
    )
}

/// One triangle far larger than the rectangle, so every point the grid can name
/// inside the rectangle lies inside the triangle.
private func giantMesh() -> ViewportBodyMesh {
    ViewportBodyMesh(
        positions: [
            Point3D(x: -1, y: 0, z: -1),
            Point3D(x: 3, y: 0, z: -1),
            Point3D(x: -1, y: 0, z: 3),
        ],
        indices: [0, 1, 2]
    )
}

/// The single run each one-triangle mesh above carries.
private let singleTriangleRun: [ViewportBodyTopology.MeshFaceRun] = [
    .init(componentID: frontFaceComponentID, triangleRange: 0 ..< 1)
]

private func resolve(
    in rect: CGRect = queryRect,
    frame: RectangleFrame = RectangleFrame(),
    topology: ViewportBodyTopology? = nil,
    mesh: ViewportBodyMesh? = nil,
    modelTransform: Transform3D = .identity,
    policy: ViewportSelectionHitPolicy = .all
) throws -> [SelectionComponent] {
    try ViewportNativeCADTopologyResolver.resolve(
        in: rect,
        topology: topology ?? bodyTopology(),
        mesh: mesh ?? bodyMesh(),
        modelTransform: modelTransform,
        selectionHitPolicy: policy,
        usesPerspectiveProjection: false,
        depthInterval: frame.depthInterval,
        project: frame.project,
        projectWithDepth: frame.projectWithDepth,
        surfaceHit: frame.surfaceHit,
        retainsSectionedPoint: frame.retainsSectionedPoint,
        bodyDrawsTriangle: frame.bodyDrawsTriangle
    )
}

// MARK: - Tests

@Suite struct ViewportNativeCADRectangleResolverTests {
    /// A rectangle is a set query. Every visible sub-shape it meets is reported,
    /// in the order evaluation recorded them — vertices, then edges, then runs —
    /// with no rank promoting one scope over another and no metric ordering
    /// within a scope.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsEveryVisibleSubshapeInRecordedOrderWithoutRank() throws {
        let components = try resolve()

        #expect(
            components == [
                .vertex(insideVertexComponentID),
                .edge(crossingEdgeComponentID),
                .face(frontFaceComponentID),
            ]
        )
    }

    /// Containment is exact. The pointer query admits a vertex within eight
    /// points because a click has to forgive aim; a rectangle states its own
    /// bounds, so a vertex four points outside is outside.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAVertexOutsideItsBoundsWithoutTolerance() throws {
        let components = try resolve()

        #expect(components.contains(.vertex(nearOutsideVertexComponentID)) == false)
    }

    /// An edge is clipped, not sampled at a fixed pitch: an edge whose two
    /// endpoints both lie outside the rectangle still crosses it, and the frame
    /// is asked about a point on the surviving interval.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAnEdgeCrossingItWithBothEndpointsOutside() throws {
        let frame = RectangleFrame()
        let components = try resolve(frame: frame)

        // The edge projects to (200, 150)...(300, 150), so every point the grid
        // can name on it lies on `y = 150` inside the rectangle. Which cell of
        // the grid answers first is the grid's order, not the edge's own
        // parameter, so the test states the place and not the pitch.
        let sampled = frame.log.surfaceQueries.contains { point in
            abs(point.y - 150) < 0.001 && queryRect.contains(point)
        }

        #expect(components.contains(.edge(crossingEdgeComponentID)))
        #expect(components.contains(.edge(outsideEdgeComponentID)) == false)
        #expect(sampled)
    }

    /// The face branch asks the frame about a point inside both the run's drawn
    /// projection and the rectangle, and reads the answer's mesh face identity
    /// back through the run list. Which triangle of the run covers that point is
    /// the grid's business, so the contract names the run's projection and not
    /// one triangle of it, and nothing about the face is decided by a depth
    /// compare of the resolver's own.
    @Test(.timeLimit(.minutes(1)))
    func rectangleConfirmsAFaceAtAPointInsideBothItsProjectionAndTheRectangle() throws {
        let frame = RectangleFrame()
        let components = try resolve(frame: frame)
        let sample = try #require(frame.log.surfaceQueries.last)

        #expect(components.contains(.face(frontFaceComponentID)))
        #expect(queryRect.contains(sample))
        // The front face projects to the square 200...300 by 100...200, which
        // its two triangles tile between them.
        #expect(sample.x >= 200)
        #expect(sample.x <= 300)
        #expect(sample.y >= 100)
        #expect(sample.y <= 200)
    }

    /// A run whose projected bounds miss the rectangle costs the eight corner
    /// projections and nothing else. A rectangle drag re-runs this on every
    /// pointer move, so the pre-filter is a correctness contract, not a
    /// convenience.
    @Test(.timeLimit(.minutes(1)))
    func rectangleSkipsARunWhoseProjectedBoundsMissIt() throws {
        let frame = RectangleFrame()
        let components = try resolve(frame: frame)

        #expect(components.contains(.face(sideFaceComponentID)) == false)
        #expect(frame.log.projections.contains(Point3D(x: 2.5, y: 0.4, z: 0.8)) == false)
        #expect(frame.log.surfaceQueries.count == 3)
    }

    /// A bounding corner the camera declines to answer for widens the search.
    /// The eight corners bound the run's projection only when the camera answers
    /// for all eight, so treating an unanswered corner as "outside" would lose
    /// the face instead of the corner.
    @Test(.timeLimit(.minutes(1)))
    func rectangleScansARunWhoseBoundingCornerTheCameraCannotProject() throws {
        var frame = RectangleFrame()
        frame.unprojectablePoints = [sideRunBoundingCorner]

        _ = try resolve(frame: frame)

        #expect(frame.log.projections.contains(Point3D(x: 2.5, y: 0.4, z: 0.8)))
    }

    /// The mounted camera's clip region decides what is drawn, so the rectangle
    /// intersects candidates with it instead of dropping a triangle that has a
    /// corner behind a clip plane. A face the near plane cuts is still drawn
    /// where the camera kept it, and the rectangle selects it there.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAFaceTheNearPlaneCutsWhereTheCameraDrawsIt() throws {
        let frame = RectangleFrame()
        let components = try resolve(
            frame: frame,
            topology: bodyTopology(meshFaceRuns: singleTriangleRun),
            mesh: nearPlaneCrossingMesh(),
            policy: .face
        )

        #expect(components == [.face(frontFaceComponentID)])
        #expect(frame.log.surfaceQueries.count == 1)
        // The near plane cuts the two corners behind it away along `y = 140`,
        // leaving the triangle (230, 140), (250, 100), (270, 140). Every
        // question the frame is asked is inside it, never on the side the
        // camera removed.
        for query in frame.log.surfaceQueries {
            #expect(queryRect.contains(query))
            #expect(query.y <= 140)
            #expect(Double(query.y) >= 600 - 2 * Double(query.x))
            #expect(Double(query.y) >= 2 * Double(query.x) - 400)
        }
    }

    /// Clipping is not a widening the resolver may skip. A face whose only part
    /// inside the rectangle is the part the near plane removed is not in the
    /// rectangle, and the run's projected bounds do not say so — they widen the
    /// search precisely because the box straddles the plane.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAFaceTheNearPlaneCutAwayWhereItMetTheRectangle() throws {
        let frame = RectangleFrame()
        let components = try resolve(
            frame: frame,
            topology: bodyTopology(meshFaceRuns: singleTriangleRun),
            mesh: nearPlaneRejectedMesh(),
            policy: .face
        )

        // Unclipped the triangle covers (232.5, 132.5) in the rectangle's
        // middle; the part the camera draws projects to `y` in 90...99.
        #expect(components.isEmpty)
        #expect(frame.log.surfaceQueries.isEmpty)
    }

    /// A candidate is a region, not a point. When another solid stands in front
    /// of the middle of the rectangle, the grid keeps asking about the cells
    /// around it, so a face the camera still draws inside the rectangle is
    /// selected — and the scan stays inside the per-candidate query ceiling.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAFaceCoveredAtItsMiddleAndDrawnAtItsEdge() throws {
        var frame = RectangleFrame()
        frame.coveredScreenRect = CGRect(x: 222, y: 122, width: 36, height: 36)
        let covered = try #require(frame.coveredScreenRect)

        let components = try resolve(
            frame: frame,
            topology: bodyTopology(meshFaceRuns: singleTriangleRun),
            mesh: giantMesh(),
            policy: .face
        )
        let queries = frame.log.surfaceQueries
        let first = try #require(queries.first)
        let last = try #require(queries.last)

        #expect(components == [.face(frontFaceComponentID)])
        #expect(covered.contains(first))
        #expect(covered.contains(last) == false)
        #expect(queries.count > 1)
        #expect(
            queries.count
                <= MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate
        )
    }

    /// A run's first triangle is not the run. Covering the part of that triangle
    /// which meets the rectangle must not lose the face, because the run's other
    /// triangle still draws inside the rectangle. Deciding a face by one
    /// representative point derived from the first intersecting triangle would
    /// make the selection depend on the run's internal triangle order.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAFaceWhoseFirstTriangleIsCoveredInsideTheRectangle() throws {
        var frame = RectangleFrame()
        frame.coveredScreenRect = CGRect(x: 250, y: 150, width: 22, height: 22)
        let covered = try #require(frame.coveredScreenRect)

        let components = try resolve(frame: frame, policy: .face)
        let queries = frame.log.surfaceQueries

        // Triangle 0 meets the rectangle only where `x + y >= 400`, and the
        // covered region holds the centre of that intersection.
        #expect(components == [.face(frontFaceComponentID)])
        #expect(queries.count == 1)
        for query in queries {
            #expect(covered.contains(query) == false)
        }
    }

    /// Mesh face identities are numbered per body, so a triangle another body
    /// drew can carry an index that also names a run of this body. Admitting it
    /// would select a face standing behind another solid.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAFaceAnotherBodyDrewAtTheSampledPoint() throws {
        var frame = RectangleFrame()
        frame.drawnByThisBody = false

        let components = try resolve(frame: frame)

        #expect(components.contains(.face(frontFaceComponentID)) == false)
        #expect(components.contains(.face(sideFaceComponentID)) == false)
    }

    /// The drawn triangle at the sampled point must belong to the run
    /// being tested. A triangle of another face of the same body means this run
    /// is not what the frame draws there.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsASampledPointOwnedByAnotherRun() throws {
        var frame = RectangleFrame()
        frame.surfaceFaceID = MeshFaceID(2)

        let components = try resolve(frame: frame)

        #expect(components.contains(.face(frontFaceComponentID)) == false)
        #expect(components.contains(.face(sideFaceComponentID)) == false)
    }

    /// Section clipping is part of visibility, not a separate filter the
    /// rectangle may skip: a sub-shape the section removed is not in the
    /// rectangle even though its projection is.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsEverySubshapeTheSectionRemoved() throws {
        var frame = RectangleFrame()
        frame.section = (normal: Vector3D(x: 0, y: 0, z: 1), offset: 1.5)

        let components = try resolve(frame: frame)

        #expect(components.isEmpty)
    }

    /// One CAD face can generate more than one contiguous run. The rectangle
    /// names the face once.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsOneComponentNamedByTwoRuns() throws {
        let components = try resolve(
            topology: bodyTopology(
                meshFaceRuns: [
                    .init(componentID: frontFaceComponentID, triangleRange: 0 ..< 1),
                    .init(componentID: frontFaceComponentID, triangleRange: 1 ..< 2),
                ]
            )
        )

        #expect(components.filter { $0 == .face(frontFaceComponentID) }.count == 1)
    }

    /// A drawn CAD triangle whose mesh face identity no index can represent is a
    /// broken frame, not a body the rectangle missed.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAnUnrepresentableMeshFaceIdentityAsATypedFailure() throws {
        var frame = RectangleFrame()
        frame.surfaceFaceID = MeshFaceID(UInt64.max)

        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try resolve(frame: frame)
        }
    }

    /// A run naming a triangle the prepared mesh does not hold is malformed
    /// preparation. Reporting it as a body with no faces would lose the face
    /// silently.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsARunOutsideThePreparedMeshAsATypedFailure() throws {
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try resolve(
                topology: bodyTopology(
                    meshFaceRuns: [
                        .init(componentID: frontFaceComponentID, triangleRange: 0 ..< 9)
                    ]
                )
            )
        }
    }

    /// Bounds no rectangle describes are a caller defect, and answering them
    /// with an empty selection would report "nothing was in the rectangle".
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsInvalidBoundsAsATypedFailure() throws {
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try resolve(in: CGRect(x: 210, y: 110, width: 0, height: 60))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try resolve(in: CGRect(x: CGFloat.nan, y: 110, width: 60, height: 60))
        }
    }

    /// The scope gate is the caller's, and each scope is answered independently.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsOnlyTheScopeThePolicyAllows() throws {
        #expect(try resolve(policy: .vertex) == [.vertex(insideVertexComponentID)])
        #expect(try resolve(policy: .edge) == [.edge(crossingEdgeComponentID)])
        #expect(try resolve(policy: .face) == [.face(frontFaceComponentID)])
    }
}
