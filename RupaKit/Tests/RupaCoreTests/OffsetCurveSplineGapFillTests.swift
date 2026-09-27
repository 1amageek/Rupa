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

    @Test func naturalGapFillAtASplineCornerIsRefusedWithTheWayOut() throws {
        let (session, target) = try lSpline()
        let generation = session.generation
        do {
            _ = try session.execute(.offsetCurve(
                target: target, distance: mm(-5), options: OffsetCurveOptions(gapFill: .natural), vertexHandle: nil
            ))
            Issue.record("Natural gap fill at a spline corner is refused.")
        } catch let error as EditorError {
            #expect(error.message.contains("Round or Linear"))
        }
        #expect(session.generation == generation)
    }
}
