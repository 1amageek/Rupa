import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Join Curves' endpoint feedback: each end of a selected curve is aligned when it meets an end
/// of another selected curve as Join requires.
@MainActor
@Suite struct SketchCurveJoinEndpointFeedbackTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    @Test func endsThatMeetAnotherSelectedCurveAreAligned() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Join", plane: .xy, start: point(0, 0), end: point(10, 0))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        let splineID = SketchEntityID(), apartID = SketchEntityID(), circleID = SketchEntityID()
        sketch.entities[splineID] = .spline(SketchSpline(controlPoints: [point(10, 0), point(14, 2), point(16, 6), point(20, 10)]))
        // Close to the spline's end but not on it: Join would refuse this pair.
        sketch.entities[apartID] = .line(SketchLine(start: point(20.5, 10), end: point(30, 10)))
        sketch.entities[circleID] = .circle(SketchCircle(center: point(0, 0), radius: mm(3)))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        func curve(_ entityID: SketchEntityID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID)))
        }

        let feedback = try document.sketchCurveJoinEndpointFeedback(targets: [firstID, splineID, apartID, circleID].map(curve))
        func aligned(_ entityID: SketchEntityID, _ end: SketchCurveJoinEndpointFeedback.End) -> Bool? {
            feedback.first { $0.entityID == entityID && $0.end == end }?.isAligned
        }
        #expect(feedback.count == 6)
        #expect(aligned(firstID, .handle(.lineStart)) == false)
        #expect(aligned(firstID, .handle(.lineEnd)) == true)
        #expect(aligned(splineID, .controlPoint(0)) == true)
        #expect(aligned(splineID, .controlPoint(3)) == false)
        #expect(aligned(apartID, .handle(.lineStart)) == false)
        #expect(!feedback.contains { $0.entityID == circleID })

        // One curve cannot be joined: no feedback.
        #expect(try document.sketchCurveJoinEndpointFeedback(targets: [curve(firstID)]).isEmpty)
    }
}
