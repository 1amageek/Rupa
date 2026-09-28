import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Fillet on curves that were drawn to touch: their ends meet within the modeling distance but
/// no coincident constraint holds them.
@MainActor
@Suite struct SketchCornerTreatmentTouchingCurvesTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    /// Two unconstrained lines meeting at (20, 0) mm, or with `gap` mm between them.
    private func lines(gap: Double = 0) throws -> (EditorSession, FeatureID, SceneNodeID, SketchEntityID, SketchEntityID) {
        func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Touching", plane: .xy, start: point(0, 0), end: point(20, 0))
        let first = SketchEntityID()
        let second = SketchEntityID()
        var feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        feature.operation = .sketch(Sketch(plane: .xy, entities: [
            first: .line(SketchLine(start: point(0, 0), end: point(20, 0))),
            second: .line(SketchLine(start: point(20 + gap, 0), end: point(20 + gap, 20))),
        ], constraints: []))
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let session = EditorSession(document: document)
        let entry = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first)
        let sceneNodeID = try #require(entry.selectionTarget()).sceneNodeID
        return (session, featureID, sceneNodeID, first, second)
    }

    private func arcCount(_ session: EditorSession, _ featureID: FeatureID) throws -> Int {
        guard case .sketch(let sketch) = session.document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch.entities.values.filter { if case .arc = $0 { return true }; return false }.count
    }

    @Test func twoTouchingCurvesTakeFilletCurve() throws {
        let (session, featureID, node, first, second) = try lines()
        func curve(_ id: SketchEntityID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: id)))
        }
        _ = try session.execute(.applySketchCornerTreatment(
            target: curve(first), adjacentTarget: curve(second), distance: mm(3), treatment: .fillet
        ))
        #expect(try arcCount(session, featureID) == 1)
        #expect(session.evaluationStatus == .valid)
    }

    @Test func aTouchingCurveEndTakesFilletVertex() throws {
        let (session, featureID, node, first, _) = try lines()
        let end = SelectionTarget(sceneNodeID: node, component: .sketchEntity(
            .sketchPointHandle(featureID: featureID, entityID: first, handle: .lineEnd)
        ))
        _ = try session.execute(.applySketchCornerTreatment(
            target: end, adjacentTarget: nil, distance: mm(3), treatment: .chamfer
        ))
        #expect(try session.document.cadDocument.designGraph.nodes[featureID].map { node -> Int in
            guard case .sketch(let sketch) = node.operation else { return 0 }
            return sketch.entities.count
        } == 3)
    }

    @Test func curvesWithAGapAreNotACorner() throws {
        let (session, featureID, node, first, second) = try lines(gap: 1)
        func curve(_ id: SketchEntityID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: id)))
        }
        let before = session.generation
        do {
            _ = try session.execute(.applySketchCornerTreatment(
                target: curve(first), adjacentTarget: curve(second), distance: mm(3), treatment: .fillet
            ))
            Issue.record("Curves with a gap between their ends must refuse Fillet Curve.")
        } catch let error as EditorError {
            #expect(error.message == "Sketch corner treatment curve-pair targets must share exactly one connected line or arc endpoint.")
        }
        #expect(session.generation == before)
    }
}
