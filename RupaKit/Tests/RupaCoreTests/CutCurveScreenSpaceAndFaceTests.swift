import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Cut Curve in Screen space cuts along the view instead of the sketch normal, and a face cuts a
/// curve where the curve crosses it inside its trim.
@MainActor
@Suite struct CutCurveScreenSpaceAndFaceTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func line(_ document: inout DesignDocument, _ plane: SketchPlane, _ a: (Double, Double), _ b: (Double, Double)) throws -> (SelectionTarget, FeatureID, SketchEntityID) {
        let id = try document.createLineSketch(name: "Line", plane: plane, start: SketchPoint(x: mm(a.0), y: mm(a.1)), end: SketchPoint(x: mm(b.0), y: mm(b.1)))
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation,
              let entity = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        let node = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == id }?.key)
        return (SelectionTarget(sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: id, entityID: entity))), id, entity)
    }

    private func lineEnd(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> Double {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .line(let line) = sketch.entities[entityID] else { throw EditorError(code: .referenceUnresolved, message: "missing") }
        return try document.cadDocument.parameters.resolvedValue(for: line.end.x).value
    }

    @Test func screenSpaceCutsAlongTheView() throws {
        var document = DesignDocument.empty()
        let (target, featureID, entityID) = try line(&document, .xy, (0, 0), (10, 0))
        let raised = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.005), normal: .unitZ))
        let (cutter, _, _) = try line(&document, raised, (5, -5), (5, 5))
        // Not coplanar: refused without Screen space.
        var refused = document
        #expect(throws: EditorError.self) { try refused.cutSketchCurves(targets: [target], cutters: [cutter]) }
        // Looking down and a little along x, the cutter lands 1 mm further on.
        _ = try document.cutSketchCurves(
            targets: [target], cutters: [cutter],
            options: CutCurveOptions(usesScreenSpaceDirection: true, screenDirection: Vector3D(x: 0.2, y: 0, z: -1))
        )
        #expect(abs(try lineEnd(document, featureID, entityID) - 0.006) < 1.0e-9)
    }

    @Test func aFaceCutsWhereTheCurvePiercesIt() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: mm(10), height: mm(10), depth: mm(10), direction: .normal
        )
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
        let side = try #require(faces.first { ($0.normal?.x ?? 0) < -0.5 })
        let sideX = try #require(side.center).x
        let mid = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.005), normal: .unitZ))
        let (target, featureID, entityID) = try line(&document, mid, (sideX * 1000 - 15, 0), (sideX * 1000 + 5, 0))
        let created = try document.cutSketchCurves(targets: [target], cutters: [try #require(side.selectionTarget())])
        #expect(created.count == 1)
        #expect(abs(try lineEnd(document, featureID, entityID) - sideX) < 1.0e-9)
        // The top face's plane is never reached: nothing to cut.
        let top = try #require(faces.first { ($0.normal?.z ?? 0) > 0.5 })
        #expect(throws: EditorError.self) {
            try document.cutSketchCurves(targets: [target], cutters: [try #require(top.selectionTarget())])
        }
    }
}
