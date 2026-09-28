import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Core names the corner Fillet would treat, for its viewport handle, without changing the
/// document.
@MainActor
@Suite struct SketchCornerTreatmentEndsTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    @Test func aSelectedEndOrTwoCurvesNameTheirCorner() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Corner", plane: .xy, start: point(20, 0), end: point(0, 0))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        let secondID = SketchEntityID(), looseID = SketchEntityID()
        sketch.entities[secondID] = .line(SketchLine(start: point(0, 0), end: point(0, 20)))
        sketch.entities[looseID] = .line(SketchLine(start: point(40, 40), end: point(50, 40)))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        func target(_ component: SelectionComponentID) -> SelectionTarget {
            SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(component))
        }
        let before = document.cadDocument.designGraph

        let fromEnd = try document.sketchCornerTreatmentEnds(
            target: target(.sketchPointHandle(featureID: featureID, entityID: firstID, handle: .lineEnd))
        )
        #expect(fromEnd == SketchCornerTreatmentEnds(
            featureID: featureID,
            selected: .init(entityID: firstID, handle: .lineEnd),
            adjacent: .init(entityID: secondID, handle: .lineStart)
        ))
        let fromCurves = try document.sketchCornerTreatmentEnds(
            target: target(.sketchEntity(featureID: featureID, entityID: secondID)),
            adjacentTarget: target(.sketchEntity(featureID: featureID, entityID: firstID))
        )
        #expect(fromCurves.selected == .init(entityID: secondID, handle: .lineStart))
        #expect(fromCurves.adjacent == .init(entityID: firstID, handle: .lineEnd))
        #expect(throws: EditorError.self) {
            try document.sketchCornerTreatmentEnds(
                target: target(.sketchPointHandle(featureID: featureID, entityID: looseID, handle: .lineStart))
            )
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
