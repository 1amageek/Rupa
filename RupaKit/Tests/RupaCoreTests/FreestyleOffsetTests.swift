import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Freestyle Offset's distance puts the offset through the clicked point, with the side
/// `offsetCurve` reads from the distance's sign.
@MainActor
@Suite struct FreestyleOffsetTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func sketch(_ entities: [SketchEntityID: SketchEntity]) throws -> (DesignDocument, FeatureID, SceneNodeID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Base", plane: .xy, start: SketchPoint(x: mm(-50), y: mm(-50)), end: SketchPoint(x: mm(-49), y: mm(-50)))
        guard var feature = document.cadDocument.designGraph.nodes[featureID], case var .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "missing")
        }
        sketch.entities.merge(entities) { _, new in new }
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return (document, featureID, node)
    }

    private func target(_ node: SceneNodeID, _ featureID: FeatureID, _ entityID: SketchEntityID) -> SelectionTarget {
        SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID)))
    }

    @Test func aLineIsPositiveOnItsLeftAndAnArcOutside() throws {
        let lineID = SketchEntityID(), arcID = SketchEntityID()
        let (document, featureID, node) = try sketch([
            lineID: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(10), y: mm(0)))),
            arcID: .arc(SketchArc(center: SketchPoint(x: mm(30), y: mm(0)), radius: mm(5), startAngle: .angle(0, .radian), endAngle: .angle(Double.pi, .radian))),
        ])
        let left = try document.freestyleOffsetDistance(target: target(node, featureID, lineID), through: Point3D(x: 0.004, y: 0.003, z: 0))
        #expect(abs(left - 0.003) < 1.0e-9)
        let right = try document.freestyleOffsetDistance(target: target(node, featureID, lineID), through: Point3D(x: 0.004, y: -0.002, z: 0))
        #expect(abs(right + 0.002) < 1.0e-9)
        let outside = try document.freestyleOffsetDistance(target: target(node, featureID, arcID), through: Point3D(x: 0.03, y: 0.008, z: 0))
        #expect(abs(outside - 0.003) < 1.0e-9)
    }

    /// In a joined chain whose second line runs backwards, the side is the chain's own left.
    @Test func aJoinedChainMeasuresOnTheChainsLeft() throws {
        let session = EditorSession()
        let firstID = SketchEntityID(), secondID = SketchEntityID()
        _ = try session.execute(.createSketch(name: "Chain", sketch: Sketch(plane: .xy, entities: [
            firstID: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(30), y: mm(0)))),
            secondID: .line(SketchLine(start: SketchPoint(x: mm(30), y: mm(30)), end: SketchPoint(x: mm(30), y: mm(0)))),
        ]), geometryRole: .curve))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        _ = try session.execute(.joinSketchCurveChain(targets: [target(node, featureID, firstID), target(node, featureID, secondID)]))
        // The chain runs right then up: (35, 15) mm is 5 mm to its right.
        let distance = try session.document.freestyleOffsetDistance(target: target(node, featureID, secondID), through: Point3D(x: 0.035, y: 0.015, z: 0))
        #expect(abs(distance + 0.005) < 1.0e-9)
    }
}
