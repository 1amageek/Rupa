import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Extend Curve's shapes: one rule, per curve kind, which Core enforces and the dialog offers.
@Suite struct ExtendCurveShapeTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    @Test func eachCurveKindTakesTheShapesItsContinuationHas() {
        let line = SketchEntity.line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(1), y: mm(0))))
        let arc = SketchEntity.arc(SketchArc(
            center: SketchPoint(x: mm(0), y: mm(0)), radius: mm(1),
            startAngle: .angle(0, .radian), endAngle: .angle(1, .radian)
        ))
        let points = [(0.0, 0.0), (1, 1), (2, 1), (3, 0)].map { SketchPoint(x: mm($0.0), y: mm($0.1)) }
        #expect(ExtendCurveShape.supported(for: line) == [.natural, .linear, .soft, .reflective])
        #expect(ExtendCurveShape.supported(for: arc) == [.natural, .soft, .reflective, .arc])
        #expect(ExtendCurveShape.supported(for: .spline(SketchSpline(controlPoints: points))) == [.natural, .linear, .soft, .reflective, .arc])
        #expect(ExtendCurveShape.supported(for: .circle(SketchCircle(center: SketchPoint(x: mm(0), y: mm(0)), radius: mm(1)))).isEmpty)
    }

    @MainActor
    @Test func aShapeTheCurveDoesNotTakeIsRefusedAndNothingChanges() throws {
        let session = EditorSession()
        _ = try session.execute(.createSketch(
            name: "Line",
            sketch: Sketch(plane: .xy, entities: [
                SketchEntityID(): .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(10), y: mm(0)))),
            ]),
            geometryRole: .curve
        ))
        let line = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first)
        let whole = try #require(line.selectionTarget())
        guard case .sketchEntity(let componentID) = whole.component,
              let reference = componentID.sketchEntityReference else {
            Issue.record("The line's target names its sketch entity.")
            return
        }
        let target = SelectionTarget(sceneNodeID: whole.sceneNodeID, component: .sketchEntity(
            .sketchPointHandle(featureID: reference.featureID, entityID: reference.entityID, handle: .lineEnd)
        ))
        let generation = session.generation
        #expect(throws: EditorError.self) {
            _ = try session.execute(.extendSketchCurve(target: target, distance: mm(2), shape: .arc))
        }
        #expect(session.generation == generation)
        _ = try session.execute(.extendSketchCurve(target: target, distance: mm(2), shape: .natural))
        #expect(session.generation != generation)
    }

    /// A spline's Natural extension continues its end span's own cubic: the extended chain's new
    /// span and its old end span are the two halves of one cubic.
    @MainActor
    @Test func aSplineExtendsNaturallyAlongItsOwnCubic() throws {
        let session = EditorSession()
        let points = [(0.0, 0.0), (10.0, 20.0), (30.0, 20.0), (40.0, 0.0)].map { SketchPoint(x: mm($0.0), y: mm($0.1)) }
        let splineID = SketchEntityID()
        _ = try session.execute(.createSketch(
            name: "Spline", sketch: Sketch(plane: .xy, entities: [splineID: .spline(SketchSpline(controlPoints: points))]),
            geometryRole: .curve
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let whole = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first?.selectionTarget())
        let end = SelectionTarget(sceneNodeID: whole.sceneNodeID, component: .sketchEntity(
            .sketchControlPoint(featureID: featureID, entityID: splineID, index: 3)
        ))
        _ = try session.execute(.extendSketchCurve(target: end, distance: mm(5), shape: .natural))
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = sketch.entities[splineID] else {
            Issue.record("The spline is present.")
            return
        }
        #expect(spline.controlPoints.count == 7)
        let resolved = try spline.controlPoints.map { point in
            Point2D(
                x: try session.document.resolvedLengthValue(point.x, owner: "x"),
                y: try session.document.resolvedLengthValue(point.y, owner: "y")
            )
        }
        #expect(try CubicBezierChainJoints(tolerance: .standard).mergedSpan(of: resolved, atJoint: 1) != nil)
    }
}
