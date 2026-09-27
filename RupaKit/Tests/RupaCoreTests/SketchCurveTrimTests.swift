import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Trim removes the segment a point lands in, bounded by the curve's ends, its crossings with the
/// sketch's other curves and a spline's span joints; Split Segment splits a curve at a point's foot.
@MainActor
@Suite struct SketchCurveTrimTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }
    private func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> SketchEntity {
        .line(SketchLine(start: point(x0, y0), end: point(x1, y1)))
    }

    /// A session holding one sketch of `entities`, with the id of the first one listed.
    private func session(_ entities: [(SketchEntityID, SketchEntity)]) throws -> (EditorSession, FeatureID) {
        let session = EditorSession()
        _ = try session.execute(.createSketch(
            name: "Trim", sketch: Sketch(plane: .xy, entities: Dictionary(uniqueKeysWithValues: entities)),
            geometryRole: .curve
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        return (session, featureID)
    }

    private func sketch(_ session: EditorSession, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The trimmed sketch is gone.")
        }
        return sketch
    }

    private func target(_ session: EditorSession, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SelectionTarget {
        let entry = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first {
            $0.entityID == entityID.description
        })
        return try #require(entry.selectionTarget())
    }

    /// Each line's x extent in millimeters, sorted.
    private func lineSpans(_ session: EditorSession, _ sketch: Sketch, excluding: Set<SketchEntityID>) throws -> [[Double]] {
        try sketch.entities.filter { !excluding.contains($0.key) }.compactMap { _, entity -> [Double]? in
            guard case .line(let line) = entity else { return nil }
            let xs = try [line.start.x, line.end.x].map {
                (try session.document.resolvedLengthValue($0, owner: "test") * 1000).rounded() / 1
            }
            return xs.sorted()
        }.sorted { $0[0] < $1[0] }
    }

    @Test func aLineLosesTheSegmentBetweenTheTwoCrossingsAroundTheClick() throws {
        let (base, left, right) = (SketchEntityID(), SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (base, line(0, 0, 10, 0)), (left, line(3, -2, 3, 2)), (right, line(7, -2, 7, 2)),
        ])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, base), point: Point2D(x: 0.005, y: 0.0005)
        ))
        let spans = try lineSpans(session, try sketch(session, featureID), excluding: [left, right])
        #expect(spans == [[0, 3], [7, 10]])
    }

    @Test func aLineEndSegmentGoesUpToTheFirstCrossing() throws {
        let (base, left, right) = (SketchEntityID(), SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (base, line(0, 0, 10, 0)), (left, line(3, -2, 3, 2)), (right, line(7, -2, 7, 2)),
        ])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, base), point: Point2D(x: 0.001, y: 0)
        ))
        let spans = try lineSpans(session, try sketch(session, featureID), excluding: [left, right])
        #expect(spans == [[3, 10]])
    }

    @Test func anUncrossedLineIsRemovedWhole() throws {
        let (base, other) = (SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([(base, line(0, 0, 10, 0)), (other, line(0, 5, 10, 5))])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, base), point: Point2D(x: 0.004, y: 0)
        ))
        let remaining = try sketch(session, featureID)
        #expect(remaining.entities[base] == nil)
        #expect(remaining.entities.count == 1)
    }

    @Test func aCircleCutByADiameterKeepsTheHalfAwayFromTheClick() throws {
        let (circle, diameter) = (SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (circle, .circle(SketchCircle(center: point(0, 0), radius: mm(5)))),
            (diameter, line(-10, 0, 10, 0)),
        ])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, circle), point: Point2D(x: 0, y: 0.005)
        ))
        guard case .arc(let arc) = try sketch(session, featureID).entities[circle] else {
            Issue.record("The trimmed circle must become an arc.")
            return
        }
        let start = try session.document.resolvedAngleValue(arc.startAngle, owner: "test")
        let end = try session.document.resolvedAngleValue(arc.endAngle, owner: "test")
        // The kept arc runs from π round through 3π/2 to 0: the lower half.
        #expect(abs(abs(start) - .pi) < 1e-9)
        #expect(abs(sin(end)) < 1e-9 && cos(end) > 0)
    }

    @Test func anUncrossedCircleIsRemoved() throws {
        let (circle, far) = (SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (circle, .circle(SketchCircle(center: point(0, 0), radius: mm(5)))),
            (far, line(20, 0, 30, 0)),
        ])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, circle), point: Point2D(x: 0.005, y: 0)
        ))
        #expect(try sketch(session, featureID).entities[circle] == nil)
    }

    @Test func aSplineLosesTheSpanTheClickLandsInAtItsJoint() throws {
        let (spline, far) = (SketchEntityID(), SketchEntityID())
        let controls = [(0.0, 0.0), (1, 2), (2, 2), (3, 0), (4, -2), (5, -2), (6, 0)].map { point($0.0, $0.1) }
        let (session, featureID) = try session([
            (spline, .spline(SketchSpline(controlPoints: controls))),
            (far, line(0, 20, 6, 20)),
        ])
        _ = try session.execute(.trimSketchCurve(
            target: try target(session, featureID, spline), point: Point2D(x: 0.0045, y: -0.0015)
        ))
        guard case .spline(let kept) = try sketch(session, featureID).entities[spline] else {
            Issue.record("The first span must remain a spline.")
            return
        }
        #expect(kept.controlPoints.count == 4)
        let lastX = try session.document.resolvedLengthValue(kept.controlPoints[3].x, owner: "test")
        #expect(abs(lastX - 0.003) < 1e-12)
        #expect(try sketch(session, featureID).entities.count == 2)
    }

    @Test func splitSegmentInsertsAVertexAtTheClickedLinePoint() throws {
        let base = SketchEntityID()
        let (session, featureID) = try session([(base, line(0, 0, 10, 0))])
        _ = try session.execute(.splitSketchCurveAtPoint(
            target: try target(session, featureID, base), point: Point2D(x: 0.003, y: 0.001)
        ))
        let spans = try lineSpans(session, try sketch(session, featureID), excluding: [])
        #expect(spans == [[0, 3], [3, 10]])
    }

    @Test func splitSegmentOnASplineSplitsAtTheProjectedFoot() throws {
        let spline = SketchEntityID()
        let controls = [(0.0, 0.0), (1, 2), (2, 2), (3, 0)].map { point($0.0, $0.1) }
        let (session, featureID) = try session([(spline, .spline(SketchSpline(controlPoints: controls)))])
        // Above the symmetric span's middle, whose foot is B(1/2) = (1.5, 1.5) mm.
        _ = try session.execute(.splitSketchCurveAtPoint(
            target: try target(session, featureID, spline), point: Point2D(x: 0.0015, y: 0.005)
        ))
        guard case .spline(let first) = try sketch(session, featureID).entities[spline] else {
            Issue.record("The split spline must remain a spline.")
            return
        }
        let end = try #require(first.controlPoints.last)
        #expect(abs(try session.document.resolvedLengthValue(end.x, owner: "test") - 0.0015) < 1e-12)
        #expect(abs(try session.document.resolvedLengthValue(end.y, owner: "test") - 0.0015) < 1e-12)
        #expect(try sketch(session, featureID).entities.count == 2)
    }

    @Test func splitSegmentRefusesACircleAndAnEnd() throws {
        let (circle, base) = (SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (circle, .circle(SketchCircle(center: point(0, 0), radius: mm(5)))), (base, line(20, 0, 30, 0)),
        ])
        let before = session.document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            _ = try session.execute(.splitSketchCurveAtPoint(
                target: try target(session, featureID, circle), point: Point2D(x: 0.005, y: 0)
            ))
        }
        #expect(throws: EditorError.self) {
            _ = try session.execute(.splitSketchCurveAtPoint(
                target: try target(session, featureID, base), point: Point2D(x: 0.019, y: 0)
            ))
        }
        #expect(session.document.cadDocument.designGraph == before)
    }

    @Test func insertKnotAddsAControlPointAtTheProjectedFootAndKeepsTheShape() throws {
        let spline = SketchEntityID()
        let controls = [(0.0, 0.0), (1, 2), (2, 2), (3, 0)].map { point($0.0, $0.1) }
        let (session, featureID) = try session([(spline, .spline(SketchSpline(controlPoints: controls)))])
        _ = try session.execute(.insertSketchSplineControlPointAtPoint(
            target: try target(session, featureID, spline), point: Point2D(x: 0.0015, y: 0.005)
        ))
        guard case .spline(let refined) = try sketch(session, featureID).entities[spline] else {
            Issue.record("Insert Knot keeps the spline.")
            return
        }
        #expect(refined.controlPoints.count == 7)
        #expect(abs(try session.document.resolvedLengthValue(refined.controlPoints[3].x, owner: "test") - 0.0015) < 1e-12)
        #expect(abs(try session.document.resolvedLengthValue(refined.controlPoints[3].y, owner: "test") - 0.0015) < 1e-12)
    }

    @Test func aPointTargetIsRefusedAndTheDocumentIsUnchanged() throws {
        let (base, dot) = (SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([(base, line(0, 0, 10, 0)), (dot, .point(point(5, 5)))])
        let before = session.document.cadDocument.designGraph
        let generation = session.generation
        #expect(throws: EditorError.self) {
            _ = try session.execute(.trimSketchCurve(
                target: try target(session, featureID, dot), point: Point2D(x: 0.005, y: 0.005)
            ))
        }
        #expect(session.document.cadDocument.designGraph == before)
        #expect(session.generation == generation)
    }

    @Test func aClickRayMeetsTheClickedCurvesPlaneWhereItsNodePlacesIt() throws {
        let base = SketchEntityID()
        let (session, featureID) = try session([(base, line(0, 0, 10, 0))])
        let curve = try target(session, featureID, base)
        _ = try session.execute(.transformSceneNodes(
            ids: [curve.sceneNodeID], worldDelta: try Transform3D.translation(Vector3D(x: 0.1, y: 0, z: 0.05)),
            compensatingInstances: false
        ))
        let document = session.document
        let straight = try document.sketchPlanePoint(
            alongRay: Point3D(x: 0.103, y: 0.004, z: 1), direction: Vector3D(x: 0, y: 0, z: -1), on: curve
        )
        #expect(abs(straight.x - 0.003) < 1e-12 && abs(straight.y - 0.004) < 1e-12)
        // An oblique ray lands where it crosses the placed plane, not below its origin.
        let oblique = try document.sketchPlanePoint(
            alongRay: Point3D(x: 0.1, y: 0, z: 1.05), direction: Vector3D(x: 0.003, y: 0.004, z: -1), on: curve
        )
        #expect(abs(oblique.x - 0.003) < 1e-12 && abs(oblique.y - 0.004) < 1e-12)

        #expect(throws: EditorError.self) {
            _ = try document.sketchPlanePoint(
                alongRay: Point3D(x: 0, y: 0, z: 1), direction: Vector3D(x: 1, y: 0, z: 0), on: curve
            )
        }
        #expect(throws: EditorError.self) {
            _ = try document.sketchPlanePoint(
                alongRay: Point3D(x: 0, y: 0, z: -1), direction: Vector3D(x: 0, y: 0, z: -1), on: curve
            )
        }
    }

    @Test func cutCurveCutsEveryTargetWhereverACutterCrossesIt() throws {
        let (low, high, left, right) = (SketchEntityID(), SketchEntityID(), SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (low, line(0, 0, 10, 0)), (high, line(0, 5, 10, 5)),
            (left, line(3, -5, 3, 10)), (right, line(7, -5, 7, 10)),
        ])
        let targets = try [low, high].map { try target(session, featureID, $0) }
        let cutters = try [left, right].map { try target(session, featureID, $0) }
        _ = try session.execute(.cutSketchCurves(targets: targets, cutters: cutters, options: CutCurveOptions()))
        let cut = try sketch(session, featureID)
        // Each target is now three pieces: 0-3, 3-7 and 7-10.
        #expect(try lineSpans(session, cut, excluding: [left, right]) == [[0, 3], [0, 3], [3, 7], [3, 7], [7, 10], [7, 10]])
    }

    @Test func cutCurveRefusesATargetNoCutterCrossesAndACurveInBothLists() throws {
        let (base, far, cutter) = (SketchEntityID(), SketchEntityID(), SketchEntityID())
        let (session, featureID) = try session([
            (base, line(0, 0, 10, 0)), (far, line(0, 50, 10, 50)), (cutter, line(5, -5, 5, 5)),
        ])
        let before = session.document.cadDocument.designGraph
        let targets = try [base, far].map { try target(session, featureID, $0) }
        let cutterTarget = try target(session, featureID, cutter)
        #expect(throws: EditorError.self) {
            _ = try session.execute(.cutSketchCurves(targets: targets, cutters: [cutterTarget], options: CutCurveOptions()))
        }
        #expect(session.document.cadDocument.designGraph == before)
        #expect(throws: EditorError.self) {
            _ = try session.execute(.cutSketchCurves(
                targets: [targets[0], cutterTarget], cutters: [cutterTarget], options: CutCurveOptions()
            ))
        }
    }

    /// A closed spline split at a point opens there: one span more, starting and ending at the
    /// point, with references following its control points around the loop.
    @Test func splitSegmentOpensAClosedSplineWhereItIsClicked() throws {
        let loop = SketchEntityID()
        // A closed loop of four spans around (0, 0), each a quarter turn.
        let k = 5.5228
        let controls = [(10.0, 0.0), (10.0, k), (k, 10.0), (0.0, 10.0), (-k, 10.0), (-10.0, k), (-10.0, 0.0),
                        (-10.0, -k), (-k, -10.0), (0.0, -10.0), (k, -10.0), (10.0, -k), (10.0, 0.0)]
            .map { point($0.0, $0.1) }
        let (session, featureID) = try session([(loop, .spline(SketchSpline(controlPoints: controls, isClosed: true)))])
        guard case .sketch(var sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("The loop's sketch is present.")
            return
        }
        // A fixed constraint on joint 2, the point (-10, 0).
        sketch.constraints = [.fixed(.splineControlPoint(entity: loop, index: 6))]
        var document = session.document
        var feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        let target = try self.target(session, featureID, loop)

        // Click beside the middle of the first span, near (7.07, 7.07).
        try document.splitSketchCurve(target: target, at: Point2D(x: 0.0075, y: 0.0075))
        guard case .sketch(let opened) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = opened.entities[loop] else {
            Issue.record("The loop is present.")
            return
        }
        #expect(!spline.isClosed)
        #expect(spline.controlPoints.count == 16)
        let first = try document.resolvedSketchPoint(spline.controlPoints[0], owner: "first")
        let last = try document.resolvedSketchPoint(try #require(spline.controlPoints.last), owner: "last")
        #expect(abs(first.x - last.x) < 1e-12 && abs(first.y - last.y) < 1e-12)
        #expect(abs(hypot(first.x, first.y) - 0.01) < 1e-4)
        // Joint 2 (-10, 0) is now after the right half of span 0 and all of span 1: index 6.
        let fixed = try #require(opened.constraints.first)
        guard case .fixed(.splineControlPoint(_, let index)) = fixed else {
            Issue.record("The fixed constraint follows its control point.")
            return
        }
        let moved = try document.resolvedSketchPoint(spline.controlPoints[index], owner: "fixed")
        #expect(abs(moved.x + 0.01) < 1e-12 && abs(moved.y) < 1e-12)

        // A click on a joint opens the loop there without a new span: joint 1 at (0, 10).
        var atJoint = session.document
        try atJoint.splitSketchCurve(target: target, at: Point2D(x: 0, y: 0.0101))
        guard case .sketch(let jointOpened) = atJoint.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let jointSpline) = jointOpened.entities[loop] else {
            Issue.record("The loop is present.")
            return
        }
        #expect(!jointSpline.isClosed && jointSpline.controlPoints.count == 13)
        let start = try atJoint.resolvedSketchPoint(jointSpline.controlPoints[0], owner: "start")
        #expect(abs(start.x) < 1e-12 && abs(start.y - 0.01) < 1e-12)
    }
}
