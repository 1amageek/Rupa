import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Delete Redundant Topology removes a spline's joints that one cubic spans and keeps the others.
@MainActor
@Suite struct SplineRedundantJointsTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private let cubic = [(0.0, 0.0), (10.0, 20.0), (30.0, 20.0), (40.0, 0.0)]

    /// The cubic split at 0.25, as seven millimeter points.
    private func halves() -> [(Double, Double)] {
        let t = 0.25
        func lerp(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t) }
        let a = lerp(cubic[0], cubic[1]), b = lerp(cubic[1], cubic[2]), c = lerp(cubic[2], cubic[3])
        let d = lerp(a, b), e = lerp(b, c)
        return [cubic[0], a, d, lerp(d, e), e, c, cubic[3]]
    }

    private func session(_ points: [(Double, Double)], constraints: (SketchEntityID) -> [SketchConstraint] = { _ in [] }) throws -> (EditorSession, SelectionTarget, SketchEntityID, FeatureID) {
        let splineID = SketchEntityID()
        let session = EditorSession()
        var sketch = Sketch(plane: .xy, entities: [
            splineID: .spline(SketchSpline(controlPoints: points.map { SketchPoint(x: mm($0.0), y: mm($0.1)) })),
        ])
        sketch.constraints = constraints(splineID)
        _ = try session.execute(.createSketch(name: "Spline", sketch: sketch, geometryRole: .curve))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let entry = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first)
        return (session, try #require(entry.selectionTarget()), splineID, featureID)
    }

    private func controlPoints(_ session: EditorSession, _ featureID: FeatureID, _ splineID: SketchEntityID) throws -> [(Double, Double)] {
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = sketch.entities[splineID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is gone.")
        }
        return try spline.controlPoints.map { point in
            (try session.document.resolvedLengthValue(point.x, owner: "x") * 1000,
             try session.document.resolvedLengthValue(point.y, owner: "y") * 1000)
        }
    }

    @Test func theHalvesOfOneCubicBecomeThatCubic() throws {
        let (session, target, splineID, featureID) = try session(halves())
        _ = try session.execute(.deleteRedundantSketchSplineJoints(target: target))
        let points = try controlPoints(session, featureID, splineID)
        #expect(points.count == 4)
        for (point, expected) in zip(points, cubic) {
            #expect(abs(point.0 - expected.0) < 1e-6 && abs(point.1 - expected.1) < 1e-6)
        }
    }

    @Test func referencesPastARemovedJointMoveBackAndAConstrainedJointStays() throws {
        // Spans 1 and 2 are one cubic; span 3 turns away. The spline's end is fixed.
        let points = halves() + [(50.0, -30.0), (60.0, -30.0), (70.0, 0.0)]
        let (session, target, splineID, featureID) = try session(points) { id in
            [.fixed(.splineControlPoint(entity: id, index: 9))]
        }
        _ = try session.execute(.deleteRedundantSketchSplineJoints(target: target))
        #expect(try controlPoints(session, featureID, splineID).count == 7)
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("The sketch is present.")
            return
        }
        #expect(sketch.constraints.contains(.fixed(.splineControlPoint(entity: splineID, index: 6))))

        // A constraint on a joint's point keeps that joint, and with nothing else to remove the
        // command is refused.
        let (pinned, pinnedTarget, _, _) = try self.session(halves()) { id in
            [.fixed(.splineControlPoint(entity: id, index: 3))]
        }
        let generation = pinned.generation
        #expect(throws: EditorError.self) { _ = try pinned.execute(.deleteRedundantSketchSplineJoints(target: pinnedTarget)) }
        #expect(pinned.generation == generation)
    }
}
