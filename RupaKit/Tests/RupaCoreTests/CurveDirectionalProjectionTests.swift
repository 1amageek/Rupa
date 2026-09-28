import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Project Curve Body along a direction moves each curve point along it to the face: onto a
/// curved face as a spatial path, onto a planar face met square on as a sketch on its plane.
@MainActor
@Suite struct CurveDirectionalProjectionTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func sceneTarget(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
        return SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID)))
    }

    private func lineSketch(_ document: inout DesignDocument, from start: (Double, Double), to end: (Double, Double), plane: SketchPlane = .xy)
        throws -> (FeatureID, SketchEntityID) {
        let featureID = try document.createLineSketch(
            name: "Curve", plane: plane,
            start: SketchPoint(x: .length(start.0, .meter), y: .length(start.1, .meter)),
            end: SketchPoint(x: .length(end.0, .meter), y: .length(end.1, .meter))
        )
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return (featureID, entityID)
    }

    @Test func aLineProjectsOntoASphereAlongTheDirection() throws {
        var document = DesignDocument.empty()
        let radius = 0.02
        _ = try document.createAnalyticSphere(name: "Sphere", center: .origin, radius: radius)
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
        // The octant face over +x, +y, +z.
        let face = try #require(faces.first { entry in
            guard let c = entry.center else { return false }
            return c.x > 0 && c.y > 0 && c.z > 0
        })
        // A short line above the octant, projected straight down.
        var sketchDocument = document
        let (featureID, entityID) = try lineSketch(&sketchDocument, from: (0.004, 0.006), to: (0.009, 0.004))
        document = sketchDocument
        let target = try sceneTarget(document, featureID, entityID)
        // The sketch lies on z = 0, below the octant: straight down finds nothing; up does.
        let before = document.cadDocument.designGraph
        #expect(throws: (any Error).self) {
            try document.projectCurvesAlongDirection(
                targets: [target], face: try #require(face.selectionTarget()),
                direction: Vector3D(x: 0, y: 0, z: -1), bidirectional: false
            )
        }
        #expect(document.cadDocument.designGraph == before)
        let ids = try document.projectCurvesAlongDirection(
            targets: [target], face: try #require(face.selectionTarget()),
            direction: Vector3D(x: 0, y: 0, z: -1), bidirectional: true
        )
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[try #require(ids.first)]?.operation else {
            Issue.record("The projection is not a spatial path.")
            return
        }
        let curve = try path.exactCurve(tolerance: .standard)
        let domain = curve.knots.last! - curve.knots.first!
        for i in 0...40 {
            let p = try curve.point(at: domain * Double(i) / 40, tolerance: .standard)
            // On the sphere, above the line's own x and y.
            #expect(abs((p - .origin).length - radius) < 1.0e-5)
            #expect(p.z > 0)
        }
        #expect(abs(path.knots.first!.position.x - 0.004) < 1.0e-9 && abs(path.knots.first!.position.y - 0.006) < 1.0e-9)
        // The source stays: projecting copies.
        #expect(document.cadDocument.designGraph.nodes[featureID] != nil)
    }

    @Test func aPlanarFaceMetSquareOnTakesASketch() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        var document = session.document
        let top = try #require(try TopologySnapshotService().snapshot(document: document).entries.first {
            $0.kind == .face && ($0.normal?.z ?? 0) > 0.5
        })
        let center = try #require(top.center)
        let (featureID, entityID) = try lineSketch(&document, from: (center.x, center.y), to: (center.x + 0.001, center.y))
        let ids = try document.projectCurvesAlongDirection(
            targets: [try sceneTarget(document, featureID, entityID)], face: try #require(top.selectionTarget()),
            direction: Vector3D(x: 0, y: 0, z: -1), bidirectional: false
        )
        guard case .sketch = document.cadDocument.designGraph.nodes[try #require(ids.first)]?.operation else {
            Issue.record("A square-on planar projection should be a sketch.")
            return
        }
        #expect(throws: EditorError.self) {
            try document.projectCurvesAlongDirection(
                targets: [try sceneTarget(document, featureID, entityID)], face: try #require(top.selectionTarget()),
                direction: Vector3D(x: 0, y: 0, z: 0), bidirectional: false
            )
        }
    }
}
