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
}
