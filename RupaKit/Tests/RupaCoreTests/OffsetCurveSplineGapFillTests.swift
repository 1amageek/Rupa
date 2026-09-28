import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Offset Planar Curve on a spline with a corner joins the corner by the chosen gap fill.
@MainActor
@Suite struct OffsetCurveSplineGapFillTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    /// An L of two straight spans turning left at (30, 0).
    private func lSpline() throws -> (EditorSession, SelectionTarget) {
        let points = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (30.0, 0.0), (30.0, 10.0), (30.0, 20.0), (30.0, 30.0)]
        let session = EditorSession()
        _ = try session.execute(.createSplineSketch(
            name: "L", plane: .xy,
            spline: SketchSpline(controlPoints: points.map { SketchPoint(x: mm($0.0), y: mm($0.1)) })
        ))
        let entry = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first)
        return (session, try #require(entry.selectionTarget()))
    }

    private func newestSpline(_ session: EditorSession) throws -> [(Double, Double)] {
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = try #require(sketch.entities.values.first) else {
            throw EditorError(code: .referenceUnresolved, message: "The offset spline is missing.")
        }
        return try spline.controlPoints.map {
            (try session.document.resolvedLengthValue($0.x, owner: "x") * 1000, try session.document.resolvedLengthValue($0.y, owner: "y") * 1000)
        }
    }

    @Test func theOutsideCornerIsFilledLinearlyAndTheInsideTrimmed() throws {
        let (outside, target) = try lSpline()
        _ = try outside.execute(.offsetCurve(
            target: target, distance: mm(-5), options: OffsetCurveOptions(gapFill: .linear), vertexHandle: nil
        ))
        #expect(try newestSpline(outside).contains { abs($0.0 - 35) < 1e-6 && abs($0.1 + 5) < 1e-6 })

        let (inside, insideTarget) = try lSpline()
        _ = try inside.execute(.offsetCurve(
            target: insideTarget, distance: mm(5), options: OffsetCurveOptions(gapFill: .round), vertexHandle: nil
        ))
        #expect(try newestSpline(inside).contains { abs($0.0 - 25) < 1e-6 && abs($0.1 - 5) < 1e-6 })
    }

    /// Straight spans continue straight: the natural fill meets where the linear one does.
    @Test func naturalGapFillAtAStraightSplineCornerMeetsLikeLinear() throws {
        let (session, target) = try lSpline()
        _ = try session.execute(.offsetCurve(
            target: target, distance: mm(-5), options: OffsetCurveOptions(gapFill: .natural), vertexHandle: nil
        ))
        #expect(try newestSpline(session).contains { abs($0.0 - 35) < 1e-6 && abs($0.1 + 5) < 1e-6 })
    }

    /// Two lines joined at a corner offset as one curve through the corner's fill.
    @Test func aJoinedChainOffsetsAsOneCurve() throws {
        let session = EditorSession()
        let firstID = SketchEntityID(), secondID = SketchEntityID()
        _ = try session.execute(.createSketch(name: "Chain", sketch: Sketch(plane: .xy, entities: [
            firstID: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(30), y: mm(0)))),
            secondID: .line(SketchLine(start: SketchPoint(x: mm(30), y: mm(30)), end: SketchPoint(x: mm(30), y: mm(0)))),
        ]), geometryRole: .curve))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        func curve(_ id: SketchEntityID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: id)))
        }
        _ = try session.execute(.joinSketchCurveChain(targets: [curve(firstID), curve(secondID)]))
        // The second line runs down into the corner: the chain turns it to run on from the first.
        _ = try session.execute(.offsetCurve(
            target: curve(secondID), distance: mm(-5), options: OffsetCurveOptions(gapFill: .natural), vertexHandle: nil
        ))
        let points = try newestSpline(session)
        #expect(points.contains { abs($0.0 - 35) < 1e-6 && abs($0.1 + 5) < 1e-6 })
        #expect(abs(points[0].0) < 1e-6 && abs(points[0].1 + 5) < 1e-6)
        #expect(abs(points[points.count - 1].0 - 35) < 1e-6 && abs(points[points.count - 1].1 - 30) < 1e-6)
    }
}
