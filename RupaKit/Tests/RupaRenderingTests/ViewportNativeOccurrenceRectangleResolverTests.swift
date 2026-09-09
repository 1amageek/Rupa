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
/// cover it, or nil where the frame drew nothing. `unprojectablePoints`
/// reproduces a point the mounted camera declines to answer for without making
/// the projection non-affine anywhere else.
private struct OccurrenceRectangleFrame {
    var unprojectablePoints: Set<Point3D> = []
    /// The occurrence the frame draws at a screen point, by the screen x range
    /// each occurrence's projection occupies.
    var drawn: [(range: ClosedRange<CGFloat>, occurrenceID: SceneOccurrenceID?)] = []
    let log = OccurrenceRectangleFrameLog()

    func project(_ point: Point3D) throws -> (point: CGPoint, depth: Double)? {
        log.recordProjection(of: point)
        guard unprojectablePoints.contains(point) == false else { return nil }
        return (
            point: CGPoint(x: 200 + point.x * 100, y: 200 - point.z * 100),
            depth: point.y + 10
        )
    }

    func drawnOccurrenceID(at point: CGPoint) throws -> SceneOccurrenceID? {
        log.recordSurfaceQuery(at: point)
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
        project: frame.project,
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
        // answer it gets, not skipped before it is asked.
        #expect(frame.log.surfaceQueries.count == 2)
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
        // The covered candidate is asked; the occurrence its answer named is not.
        #expect(frame.log.surfaceQueries.count == 1)
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

    /// Every candidate that reaches the frame is asked exactly once. The cost
    /// of a rectangle is one surface query per candidate, never one per
    /// triangle, and a drag re-runs the whole query on every pointer move.
    @Test(.timeLimit(.minutes(1)))
    func rectangleSpendsExactlyOneSurfaceQueryPerCandidateThatReachesTheFrame() throws {
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
        // Two triangles per square, and one query each: the scan stops at the
        // first triangle that meets the rectangle.
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
        #expect(frame.log.surfaceQueries.count == 1)
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
