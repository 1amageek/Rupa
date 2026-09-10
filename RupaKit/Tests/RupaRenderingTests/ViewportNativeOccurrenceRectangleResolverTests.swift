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

/// A deterministic stand-in for the mounted frame's projection and its drawn
/// pixels, for the occurrence rectangle.
///
/// The camera looks along +Y from `y = -10`, so camera depth is `y + 10` and
/// one world unit maps to 100 screen points, giving the orthographic screen map
/// `(200 + 100x, 200 - 100z)`. `drawn` answers what the frame draws at a screen
/// point the way the mounted surface query does: the occurrence whose pixels
/// cover it, or nil where the frame drew nothing, and `covered` is a screen
/// region one occurrence draws in front of all of them.
///
/// `depthInterval` is the mounted camera's own clip range, and
/// `projectWithDepth` answers it the way the mounted camera does: a depth for
/// every point the scene can represent, including one the interval excludes,
/// because the rectangle clips a candidate against the interval in world space.
/// `unprojectablePoints` reproduces a point the mounted camera declines to
/// project without making the projection non-affine anywhere else.
private struct OccurrenceRectangleFrame {
    var unprojectablePoints: Set<Point3D> = []
    /// The mounted camera's near and far planes, in the depth `y + 10` reports.
    var depthInterval: ClosedRange<Double> = 0.5 ... 100
    /// The occurrence the frame draws at a screen point, by the screen x range
    /// each occurrence's projection occupies.
    var drawn: [(range: ClosedRange<CGFloat>, occurrenceID: SceneOccurrenceID?)] = []
    /// A screen region one occurrence draws in front of every entry of `drawn`.
    var covered: (rect: CGRect, occurrenceID: SceneOccurrenceID)?
    let log = OccurrenceRectangleFrameLog()

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

    func drawnOccurrenceID(at point: CGPoint) throws -> SceneOccurrenceID? {
        log.recordSurfaceQuery(at: point)
        if let covered, covered.rect.contains(point) {
            return covered.occurrenceID
        }
        for entry in drawn where entry.range.contains(point.x) {
            return entry.occurrenceID
        }
        return nil
    }
}

/// What the frame was asked, so a test can state the cost contract — which
/// candidates were projected and how many surface queries a rectangle drag
/// costs — instead of only the occurrences it returned.
private final class OccurrenceRectangleFrameLog: Sendable {
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

// MARK: - Plan under test

private let frontOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.front")
private let behindOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.behind")
private let slantedOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.slanted")
private let middleOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.middle")
private let trailingOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.trailing")
private let nearPlaneOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.near-plane")
private let coveringOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.covering")

/// The rectangle most tests drag, in screen points: `x` in 210...270 and `y` in
/// 110...170, which is world `x` in 0.1...0.7 and `z` in 0.3...0.9.
private let queryRect = CGRect(x: 210, y: 110, width: 60, height: 60)

/// A rectangle wide enough to meet every occurrence in the ordering plan.
private let wideRect = CGRect(x: 210, y: 110, width: 660, height: 60)

/// A unit square at `y = depth`, offset along +X, whose projection covers
/// `x` in `200 + 100 * offset` ... `300 + 100 * offset` and `y` in 100...200.
private func squareSource(
    named name: String,
    offsetX: Double,
    depth: Double
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: name))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: offsetX, y: depth, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: offsetX + 1, y: depth, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: offsetX + 1, y: depth, z: 1))
    let fourth = try builder.addVertex(GeometryPoint3D(x: offsetX, y: depth, z: 1))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

/// A triangle standing clear of `queryRect`, whose corners are deliberately not
/// axis-aligned with its own bounding box, so a bounding corner can be made
/// unanswerable without also removing one of its drawn vertices.
private func slantedSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.occurrence-slanted"))
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 3.1, y: 0, z: 0.2))
    let second = try builder.addVertex(GeometryPoint3D(x: 3.9, y: 0, z: 0.3))
    let third = try builder.addVertex(GeometryPoint3D(x: 3.5, y: 0.4, z: 0.8))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

/// The bounding corner of the slanted triangle that no drawn vertex occupies.
private let slantedBoundingCorner = Point3D(x: 3.1, y: 0, z: 0.8)

/// A triangle the camera's near plane cuts.
///
/// Two corners stand at camera depth -9, behind the near plane at 0.5, and the
/// third stands at depth 10, so the camera draws the triangle `(230, 140)`,
/// `(250, 100)`, `(270, 140)` between them, which meets `queryRect`.
private func nearPlaneCrossingSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(
        identity: GeometrySourceID(rawValue: "mesh.occurrence-near-crossing")
    )
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 0.1, y: -19, z: 0.2))
    let second = try builder.addVertex(GeometryPoint3D(x: 0.9, y: -19, z: 0.2))
    let third = try builder.addVertex(GeometryPoint3D(x: 0.5, y: 0, z: 1.0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

/// A triangle whose projection meets `queryRect` only where the near plane cut
/// it away: unclipped it covers the rectangle's middle, and the part the camera
/// draws projects to `y` in 90...99, above it.
private func nearPlaneRejectedSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(
        identity: GeometrySourceID(rawValue: "mesh.occurrence-near-rejected")
    )
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 0.1, y: -95, z: 0.2))
    let second = try builder.addVertex(GeometryPoint3D(x: 0.9, y: -95, z: 0.2))
    let third = try builder.addVertex(GeometryPoint3D(x: 0.5, y: 0, z: 1.1))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

/// A square one world unit nearer the camera than the plane at `y = 0`, whose
/// projection covers exactly `screenRect`.
private func coveringSource(named name: String, screenRect: CGRect) throws -> MeshSource {
    let minimumX = Double(screenRect.minX - 200) / 100
    let maximumX = Double(screenRect.maxX - 200) / 100
    let minimumZ = Double(200 - screenRect.maxY) / 100
    let maximumZ = Double(200 - screenRect.minY) / 100
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: name))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: minimumX, y: -1, z: minimumZ))
    let second = try builder.addVertex(GeometryPoint3D(x: maximumX, y: -1, z: minimumZ))
    let third = try builder.addVertex(GeometryPoint3D(x: maximumX, y: -1, z: maximumZ))
    let fourth = try builder.addVertex(GeometryPoint3D(x: minimumX, y: -1, z: maximumZ))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

private func planItem(
    occurrenceID: SceneOccurrenceID,
    source: MeshSource
) throws -> UniversalViewportSceneItem {
    UniversalViewportSceneItem(
        id: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.\(occurrenceID.rawValue)"),
        displayName: occurrenceID.rawValue,
        representationID: GeometryRepresentationID(rawValue: "representation.\(occurrenceID.rawValue)"),
        reference: .authoredMesh(source.identity),
        mesh: source,
        worldTransform: .identity,
        worldBounds: try source.bounds()
    )
}

/// The plan's occurrence views, in the plan's own emission order.
private func occurrenceViews(
    _ items: [UniversalViewportSceneItem]
) throws -> [MeshSourcePresentationOccurrenceView] {
    let projectID = ProjectID(rawValue: "project.occurrence-rectangle")
    let scene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: items
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)
    var views: [MeshSourcePresentationOccurrenceView] = []
    plan.forEachOccurrence { views.append($0) }
    return views
}

private func resolve(
    in rect: CGRect = queryRect,
    occurrences: [MeshSourcePresentationOccurrenceView],
    frame: OccurrenceRectangleFrame
) throws -> [SceneOccurrenceID] {
    try ViewportNativeOccurrenceRectangleResolver.occurrenceIDs(
        intersecting: rect,
        occurrences: occurrences,
        depthInterval: frame.depthInterval,
        projectWithDepth: frame.projectWithDepth,
        drawnOccurrenceID: frame.drawnOccurrenceID
    )
}

// MARK: - Tests

@Suite struct ViewportNativeOccurrenceRectangleResolverTests {
    /// The frame draws the occurrence inside the rectangle, so the rectangle
    /// selects it. Nothing else is consulted: no depth compare, no section
    /// predicate and no culling filter of the resolver's own.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsTheOccurrenceTheFrameDrawsInsideIt() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, frontOccurrenceID)])

        #expect(try resolve(occurrences: views, frame: frame) == [frontOccurrenceID])
    }

    /// Occlusion is the frame's answer, not a comparison this resolver makes.
    /// An occurrence standing directly behind another meets the same rectangle
    /// and projects into it, and is still rejected because the frame draws the
    /// nearer occurrence at the point it is asked about.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAnOccurrenceTheNearerOneCovers() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
            try planItem(
                occurrenceID: behindOccurrenceID,
                source: try squareSource(named: "mesh.behind", offsetX: 0, depth: 5)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, frontOccurrenceID)])

        let result = try resolve(occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID])
        // Both candidates reach the frame: the covered one is rejected by the
        // answers it gets, not skipped before it is asked. The nearer one stops
        // at its first confirmed sample; the covered one is never confirmed and
        // spends its whole per-candidate budget being refused.
        #expect(
            frame.log.surfaceQueries.count
                == 1 + MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate
        )
    }

    /// A candidate whose screen bounds miss the rectangle cannot be drawn
    /// inside it, so it is skipped before any pixel is sampled. The surface
    /// query is the bounded cost this rule protects.
    @Test(.timeLimit(.minutes(1)))
    func rectangleSkipsACandidateWhoseBoundsMissItWithoutSpendingASurfaceQuery() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
            try planItem(occurrenceID: slantedOccurrenceID, source: try slantedSource()),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, frontOccurrenceID)])

        let result = try resolve(occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID])
        #expect(frame.log.surfaceQueries.count == 1)
        // The skipped candidate cost its eight bounding corners and nothing more.
        #expect(frame.log.projections.contains(Point3D(x: 3.5, y: 0.4, z: 0.8)) == false)
    }

    /// A corner the camera declines to answer for widens the search instead of
    /// losing the occurrence: the same candidate that is skipped when all eight
    /// corners project is carried on to its own geometry when one does not.
    @Test(.timeLimit(.minutes(1)))
    func rectangleDoesNotSkipACandidateWithACornerTheCameraCannotProject() throws {
        let views = try occurrenceViews([
            try planItem(occurrenceID: slantedOccurrenceID, source: try slantedSource()),
        ])
        let slantedVertex = Point3D(x: 3.5, y: 0.4, z: 0.8)

        let projectable = OccurrenceRectangleFrame()
        _ = try resolve(occurrences: views, frame: projectable)

        let unprojectable = OccurrenceRectangleFrame(
            unprojectablePoints: [slantedBoundingCorner]
        )
        _ = try resolve(occurrences: views, frame: unprojectable)

        #expect(projectable.log.projections.contains(slantedVertex) == false)
        #expect(unprojectable.log.projections.contains(slantedVertex))
    }

    /// The camera's near plane cuts a candidate rather than removing it. Two of
    /// this triangle's corners stand behind the near plane, and the part the
    /// camera draws between them meets the rectangle, so the occurrence is
    /// reported from a sample inside that part.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAnOccurrenceTheNearPlaneCutsWhereTheCameraDrawsIt() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: nearPlaneOccurrenceID,
                source: try nearPlaneCrossingSource()
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200 ... 300, nearPlaneOccurrenceID)])

        let result = try resolve(occurrences: views, frame: frame)

        #expect(result == [nearPlaneOccurrenceID])
        #expect(frame.log.surfaceQueries.count == 1)
        // The drawn part is the triangle (230, 140), (250, 100), (270, 140),
        // and the sample stands inside it and inside the rectangle.
        let query = try #require(frame.log.surfaceQueries.first)
        #expect(queryRect.contains(query))
        #expect(query.y <= 140)
        #expect(query.x >= 230 + (140 - query.y) / 2)
        #expect(query.x <= 270 - (140 - query.y) / 2)
    }

    /// A candidate the near plane cut away where it met the rectangle is not
    /// reported and costs no surface query. Only the part the camera draws is
    /// sampled, and that part stands clear of the rectangle even though the
    /// whole triangle would have covered its middle.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsAnOccurrenceTheNearPlaneCutAwayWhereItMetTheRectangle() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: nearPlaneOccurrenceID,
                source: try nearPlaneRejectedSource()
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200 ... 300, nearPlaneOccurrenceID)])

        #expect(try resolve(occurrences: views, frame: frame).isEmpty)
        #expect(frame.log.surfaceQueries.isEmpty)
    }

    /// An occurrence a nearer solid covers in the middle stays selectable by
    /// the part of it the frame still draws.
    ///
    /// The covered region holds the point a single representative would name —
    /// the centre of the candidate's first triangle inside the rectangle — so
    /// an answer taken from one point would report only the covering solid and
    /// lose an occurrence the frame plainly draws.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAnOccurrenceCoveredWhereItsFirstTriangleWouldBeSampled() throws {
        let covered = CGRect(x: 230, y: 130, width: 28, height: 28)
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
            try planItem(
                occurrenceID: coveringOccurrenceID,
                source: try coveringSource(named: "mesh.covering", screenRect: covered)
            ),
        ])
        // The front square's first triangle meets the rectangle in the triangle
        // (270, 130), (270, 170), (230, 170), whose centre the covered region
        // holds.
        #expect(covered.contains(CGPoint(x: 770.0 / 3.0, y: 470.0 / 3.0)))
        let frame = OccurrenceRectangleFrame(
            drawn: [(200 ... 300, frontOccurrenceID)],
            covered: (rect: covered, occurrenceID: coveringOccurrenceID)
        )

        let result = try resolve(occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID, coveringOccurrenceID])
        let queries = frame.log.surfaceQueries
        let first = try #require(queries.first)
        let last = try #require(queries.last)
        #expect(covered.contains(first))
        #expect(covered.contains(last) == false)
        #expect(queries.count > 1)
        #expect(
            queries.count
                <= MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate
        )
    }

    /// The frame answering with an occurrence is admission evidence for that
    /// occurrence, whether or not it is the candidate that was asked about: the
    /// frame drew its pixels inside the rectangle. Asking it again could only
    /// repeat the answer, so it is never asked.
    @Test(.timeLimit(.minutes(1)))
    func rectangleAdmitsTheOccurrenceAQueryNamesWithoutAskingItAgain() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: behindOccurrenceID,
                source: try squareSource(named: "mesh.behind", offsetX: 0, depth: 5)
            ),
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, frontOccurrenceID)])

        let result = try resolve(occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID])
        // The covered candidate is asked on every sample it has, because none
        // of them confirms it; the occurrence its answers named is never asked.
        #expect(
            frame.log.surfaceQueries.count
                == MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate
        )
    }

    /// The output is the plan's order, not the order admission happened in, so
    /// a rectangle drag reports a stable set while the pointer moves.
    @Test(.timeLimit(.minutes(1)))
    func rectangleReportsAdmittedOccurrencesInPlanOrder() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
            try planItem(
                occurrenceID: middleOccurrenceID,
                source: try squareSource(named: "mesh.middle", offsetX: 3, depth: 0)
            ),
            try planItem(
                occurrenceID: trailingOccurrenceID,
                source: try squareSource(named: "mesh.trailing", offsetX: 5, depth: 0)
            ),
        ])
        #expect(views.map(\.occurrenceID) == [
            frontOccurrenceID, middleOccurrenceID, trailingOccurrenceID,
        ])
        // The first candidate's pixels belong to the middle occurrence and the
        // last candidate's to the first, so admission order is middle then
        // front while plan order is front then middle.
        let frame = OccurrenceRectangleFrame(drawn: [
            (200...300, middleOccurrenceID),
            (500...600, middleOccurrenceID),
            (700...800, frontOccurrenceID),
        ])

        let result = try resolve(in: wideRect, occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID, middleOccurrenceID])
    }

    /// A candidate stops at the first sample the frame confirms for it, so a
    /// rectangle whose candidates each keep their own pixels costs one query
    /// each. The cost is bounded by the sample grid and never by the triangle
    /// count, and a drag re-runs the whole query on every pointer move.
    @Test(.timeLimit(.minutes(1)))
    func rectangleStopsAtTheFirstSampleTheFrameConfirms() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
            try planItem(
                occurrenceID: middleOccurrenceID,
                source: try squareSource(named: "mesh.middle", offsetX: 3, depth: 0)
            ),
            try planItem(
                occurrenceID: trailingOccurrenceID,
                source: try squareSource(named: "mesh.trailing", offsetX: 5, depth: 0)
            ),
        ])
        // Each candidate keeps its own pixels, so no answer stands in for
        // another and every candidate is asked on its own behalf.
        let frame = OccurrenceRectangleFrame(drawn: [
            (200...300, frontOccurrenceID),
            (500...600, middleOccurrenceID),
            (700...800, trailingOccurrenceID),
        ])

        let result = try resolve(in: wideRect, occurrences: views, frame: frame)

        #expect(result == [frontOccurrenceID, middleOccurrenceID, trailingOccurrenceID])
        #expect(frame.log.surfaceQueries.count == 3)
        // Two triangles per square, and one query each: the scan samples the
        // grid, not the triangles, and stops at the first sample confirmed.
        #expect(views.map(\.triangleCount) == [2, 2, 2])
    }

    /// An empty result is a valid answer. The frame drawing nothing inside the
    /// rectangle is not a failure and is not fallen back on.
    @Test(.timeLimit(.minutes(1)))
    func rectangleRejectsACandidateTheFrameAnswersWithNothing() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, nil)])

        #expect(try resolve(occurrences: views, frame: frame).isEmpty)
        // Nothing confirms the candidate, so it is refused on every sample it
        // has rather than on one representative point.
        #expect(
            frame.log.surfaceQueries.count
                == MeshSourcePresentationPlanLimits.maxRectangleSurfaceQueryCountPerCandidate
        )
    }

    /// A rectangle without finite, non-empty bounds is a typed failure, not an
    /// empty selection: the caller publishes nothing rather than replacing the
    /// selection with a rectangle the frame never judged.
    @Test(.timeLimit(.minutes(1)))
    func rectangleWithoutFiniteNonEmptyBoundsIsATypedFailure() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [(200...300, frontOccurrenceID)])

        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(
                in: CGRect(x: 210, y: 110, width: 0, height: 60),
                occurrences: views,
                frame: frame
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(
                in: CGRect(x: CGFloat.nan, y: 110, width: 60, height: 60),
                occurrences: views,
                frame: frame
            )
        }
    }

    /// A query naming an occurrence the candidate list does not hold would mean
    /// the answering frame and the projected geometry came from two different
    /// plans, so it is a typed failure rather than a silently dropped answer.
    @Test(.timeLimit(.minutes(1)))
    func anOccurrenceOutsideTheQueriedPlanIsATypedFailure() throws {
        let views = try occurrenceViews([
            try planItem(
                occurrenceID: frontOccurrenceID,
                source: try squareSource(named: "mesh.front", offsetX: 0, depth: 0)
            ),
        ])
        let frame = OccurrenceRectangleFrame(drawn: [
            (200...300, SceneOccurrenceID(rawValue: "occurrence.other-plan")),
        ])

        #expect(throws: MeshSourcePresentationRenderError.self) {
            try resolve(occurrences: views, frame: frame)
        }
    }
}
