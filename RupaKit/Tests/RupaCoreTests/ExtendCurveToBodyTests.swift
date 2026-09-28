import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Dependent Curve Extend to a solid: the end extends until it meets the body's faces.
@MainActor
@Suite struct ExtendCurveToBodyTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func scene(start: Double, end: Double) throws -> (DesignDocument, SelectionTarget, FeatureID, SketchEntityID, SceneNodeID) {
        var document = DesignDocument.empty()
        let boxID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: mm(10), height: mm(10), depth: mm(10), direction: .normal
        )
        let body = try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(boxID) }?.key)
        let plane = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.005), normal: .unitZ))
        let featureID = try document.createLineSketch(name: "Line", plane: plane,
                                                      start: SketchPoint(x: mm(start), y: mm(0)), end: SketchPoint(x: mm(end), y: mm(0)))
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return (document, SelectionTarget(sceneNodeID: node, component: .object), featureID, entityID, body)
    }

    private func line(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> (Double, Double) {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .line(let line) = sketch.entities[entityID] else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        return (try document.cadDocument.parameters.resolvedValue(for: line.start.x).value,
                try document.cadDocument.parameters.resolvedValue(for: line.end.x).value)
    }

    private func handle(_ node: SceneNodeID, _ featureID: FeatureID, _ entityID: SketchEntityID, _ handle: SketchEntityPointHandle) -> SelectionTarget {
        SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchPointHandle(featureID: featureID, entityID: entityID, handle: handle)))
    }

    @Test func eitherEndExtendsToTheBodysNearFace() throws {
        var (document, curve, featureID, entityID, body) = try scene(start: -20, end: -15)
        try document.extendSketchCurve(target: handle(curve.sceneNodeID, featureID, entityID, .lineEnd), until: SelectionTarget(sceneNodeID: body), shape: .natural)
        #expect(abs(try line(document, featureID, entityID).1 + 0.005) < 1.0e-9)

        var (reversed, reversedCurve, reversedFeature, reversedEntity, reversedBody) = try scene(start: -15, end: -20)
        try reversed.extendSketchCurve(target: handle(reversedCurve.sceneNodeID, reversedFeature, reversedEntity, .lineStart), until: SelectionTarget(sceneNodeID: reversedBody), shape: .natural)
        #expect(abs(try line(reversed, reversedFeature, reversedEntity).0 + 0.005) < 1.0e-9)
    }

    @Test func anExtensionAwayFromTheBodyIsRefused() throws {
        var (document, curve, featureID, entityID, body) = try scene(start: -15, end: -20)
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.extendSketchCurve(target: handle(curve.sceneNodeID, featureID, entityID, .lineEnd), until: SelectionTarget(sceneNodeID: body), shape: .natural)
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
