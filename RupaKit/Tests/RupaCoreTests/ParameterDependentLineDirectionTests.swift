import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Geometry placed along a line's direction or normal keeps following the line when the line's
/// ends change through their parameters.
@MainActor
@Suite struct ParameterDependentLineDirectionTests {
    private func mm(_ v: Double) -> CADExpression { .length(v, .millimeter) }

    private func sketch(_ document: inout DesignDocument, end: SketchPoint) throws -> (FeatureID, SketchEntityID, SceneNodeID) {
        let featureID = try document.createLineSketch(name: "L", plane: .xy, start: SketchPoint(x: mm(0), y: mm(0)), end: end)
        guard case .sketch(let s) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let id = s.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return (featureID, id, node)
    }

    private func height(_ document: inout DesignDocument, _ millimeters: Double) throws -> CADExpression {
        try document.upsertParameter(name: "h", expression: .length(millimeters / 1000, .meter), kind: .length)
        return try ParameterExpressionParser().parse("h", parameters: document.cadDocument.parameters, targetKind: .length)
    }

    private func value(_ document: DesignDocument, _ expression: CADExpression) throws -> Double {
        try document.cadDocument.parameters.resolvedValue(for: expression).value
    }

    /// A horizontal line offset by 2 mm stays 2 mm away when the line turns to 45 degrees.
    @Test func aLineOffsetKeepsItsDistanceWhenTheLineTurns() throws {
        var document = DesignDocument.empty()
        let h = try height(&document, 0)
        let (featureID, id, node) = try sketch(&document, end: SketchPoint(x: mm(10), y: h))
        let ids = try document.offsetCurve(
            target: SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: id))),
            distance: mm(2), options: OffsetCurveOptions()
        )
        _ = try height(&document, 10)
        guard case .sketch(let offsetSketch) = document.cadDocument.designGraph.nodes[try #require(ids.first)]?.operation,
              case .line(let offset) = try #require(offsetSketch.entities.values.first) else {
            Issue.record("The offset is not a line.")
            return
        }
        // Distance from each offset end to the source line y = x, on its left.
        for point in [offset.start, offset.end] {
            let x = try value(document, point.x), y = try value(document, point.y)
            #expect(abs((y - x) / 2.0.squareRoot() - 0.002) < 1.0e-12)
        }
    }

    /// Offset Vertex's new vertex stays on its line when the line's far end moves.
    @Test func anOffsetVertexStaysOnItsLineWhenTheLineTurns() throws {
        var document = DesignDocument.empty()
        let h = try height(&document, 0)
        let firstID = SketchEntityID(), secondID = SketchEntityID()
        let featureID = try document.createLineSketch(name: "Corner", plane: .xy, start: SketchPoint(x: mm(-40), y: mm(-40)), end: SketchPoint(x: mm(-39), y: mm(-40)))
        guard var feature = document.cadDocument.designGraph.nodes[featureID], case var .sketch(corner) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "missing")
        }
        corner.entities = [
            firstID: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(20), y: h))),
            secondID: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(0), y: mm(20)))),
        ]
        corner.constraints = [.coincident(.lineStart(firstID), .lineStart(secondID))]
        feature.operation = .sketch(corner)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        try document.offsetSketchVertex(
            target: SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: firstID))),
            handle: .lineStart, distance: mm(5)
        )
        _ = try height(&document, 20)
        guard case .sketch(let result) = document.cadDocument.designGraph.nodes[featureID]?.operation else { return }
        // Every line now lies on y = x (the first line) or x = 0 (the second): the vertex moved
        // with the first line's turn.
        let starts = try result.entities.values.compactMap { entity -> (Double, Double)? in
            guard case .line(let line) = entity else { return nil }
            return (try value(document, line.start.x), try value(document, line.start.y))
        }
        #expect(starts.contains { abs($0.0 - 0.005 / 2.0.squareRoot()) < 1.0e-12 && abs($0.1 - 0.005 / 2.0.squareRoot()) < 1.0e-12 })
    }
}
