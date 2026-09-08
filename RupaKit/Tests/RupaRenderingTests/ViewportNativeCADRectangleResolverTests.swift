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
/// `unprojectablePoints` reproduces a point the mounted camera declines to
/// answer for — a point outside the frame's depth range — without making the
/// projection non-affine anywhere else. `section` is the frame's retained
/// half-space, and `drawnByThisBody` is the render provenance the production
/// query derives from the drawn triangle's occurrence.
private struct RectangleFrame {
    static let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.cad.body")

    /// The mesh face identity of the drawn triangle, which is the triangle's
    /// own index in the CAD body's emission order.
    var surfaceFaceID: MeshFaceID = MeshFaceID(0)
    var drawnByThisBody: Bool = true
    var unprojectablePoints: Set<Point3D> = []
    /// The retained half-space, in the same world space as the topology:
    /// `dot(point, normal) - offset >= 0`.
    var section: (normal: Vector3D, offset: Double)?
    let log = RectangleFrameLog()

    func project(_ point: Point3D) throws -> (point: CGPoint, depth: Double)? {
        log.recordProjection(of: point)
        guard unprojectablePoints.contains(point) == false else { return nil }
        return (
            point: CGPoint(x: 200 + point.x * 100, y: 200 - point.z * 100),
            depth: point.y + 10
        )
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
        return (
            triangle: frameTriangle(faceID: surfaceFaceID),
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

private func frameTriangle(faceID: MeshFaceID) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: RectangleFrame.occurrenceID,
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
        project: frame.project,
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
    /// endpoints both lie outside the rectangle still crosses it, and the
    /// midpoint of the surviving interval is the point the frame is asked about.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAnEdgeCrossingItWithBothEndpointsOutside() throws {
        let frame = RectangleFrame()
        let components = try resolve(frame: frame)

        // The edge projects to (200, 150)...(300, 150), so the rectangle keeps
        // the screen interval 0.1...0.7 and its midpoint 0.4 maps back to the
        // edge's own parameter 0.4 under an orthographic camera.
        let sampled = frame.log.surfaceQueries.contains { point in
            abs(point.x - 240) < 0.001 && abs(point.y - 150) < 0.001
        }

        #expect(components.contains(.edge(crossingEdgeComponentID)))
        #expect(components.contains(.edge(outsideEdgeComponentID)) == false)
        #expect(sampled)
    }

    /// The face branch asks the frame one question, at a point inside both the
    /// triangle and the rectangle, and reads the answer's mesh face identity
    /// back through the run list. Nothing about the face is decided by a depth
    /// compare of the resolver's own.
    @Test(.timeLimit(.minutes(1)))
    func rectangleConfirmsAFaceAtAPointInsideBothTheTriangleAndTheRectangle() throws {
        let frame = RectangleFrame()
        let components = try resolve(frame: frame)
        let representative = try #require(frame.log.surfaceQueries.last)

        #expect(components.contains(.face(frontFaceComponentID)))
        #expect(queryRect.contains(representative))
        // Triangle 0 projects to (200, 200), (300, 200), (300, 100), so its
        // interior is bounded by the hypotenuse `y = 400 - x`.
        #expect(Double(representative.y) >= 400 - Double(representative.x))
        #expect(representative.y <= 200)
        #expect(representative.x <= 300)
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

    /// Mesh face identities are numbered per body, so a triangle another body
    /// drew can carry an index that also names a run of this body. Admitting it
    /// would select a face standing behind another solid.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAFaceAnotherBodyDrewAtTheRepresentativePoint() throws {
        var frame = RectangleFrame()
        frame.drawnByThisBody = false

        let components = try resolve(frame: frame)

        #expect(components.contains(.face(frontFaceComponentID)) == false)
        #expect(components.contains(.face(sideFaceComponentID)) == false)
    }

    /// The drawn triangle at the representative point must belong to the run
    /// being tested. A triangle of another face of the same body means this run
    /// is not what the frame draws there.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsARepresentativePointOwnedByAnotherRun() throws {
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
