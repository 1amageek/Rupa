import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Dimension edits a sphere's diameter, a solid fillet's radius and a rectangle's width and height.
@MainActor
@Suite struct FeatureDimensionTests {
    @Test func aSphereIsDimensionedByItsDiameter() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createAnalyticSphere(name: "Ball", center: .origin, radius: 0.05)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })
        let target = SelectionTarget(sceneNodeID: node.id)
        let snapshot = try ObjectDimensionSnapshotService().snapshot(document: document, targets: [target])
        #expect(snapshot.entries.map(\.label) == ["Diameter", "Radius"])
        #expect(snapshot.entries.first?.isPrimaryForTarget == true)
        #expect(abs((snapshot.entries.first?.resolvedMeters ?? 0) - 0.1) < 1e-12)

        try document.setObjectDimension(target: target, kind: .diameter, value: .length(0.4, .meter))
        guard case .primitive(let primitive) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .sphere(let sphere) = primitive.definition else {
            Issue.record("Expected the sphere primitive.")
            return
        }
        #expect(sphere.radius == .length(0.2, .meter))
        #expect(document.productMetadata.sceneNodes[node.id]?.object?.properties["radius"] == .length(0.2))
    }

    @Test func aFilletFaceIsDimensionedByTheFilletRadius() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let topology = try TopologySnapshotService().snapshot(document: session.document, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        _ = try session.execute(.createBodyEdgeTreatment(name: "Round", target: edge, treatment: .fillet(radius: .length(0.001, .meter))))
        let document = session.document
        let filleted = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        var blends: [(target: SelectionTarget, featureID: FeatureID)] = []
        var otherFaceCount = 0
        for entry in filleted.entries where entry.kind == .face {
            let target = try #require(entry.selectionTarget())
            if case .fillet(let featureID, _, _) = try ObjectFeatureDimension.resolve(target: target, in: document, topology: { filleted }) {
                blends.append((target, featureID))
            } else {
                otherFaceCount += 1
            }
        }
        #expect(blends.count == 1, "Only the face the fillet generated carries the fillet radius.")
        #expect(otherFaceCount == 6)
        let (blend, filletID) = try #require(blends.first)

        let snapshot = try ObjectDimensionSnapshotService().snapshot(document: document, targets: [blend])
        #expect(snapshot.entries.map(\.label) == ["Fillet Radius"])
        #expect(abs((snapshot.entries.first?.resolvedMeters ?? 0) - 0.001) < 1e-12)

        var edited = document
        try edited.setObjectDimension(target: blend, kind: .radius, value: .length(0.002, .meter))
        guard case .fillet(let fillet) = edited.cadDocument.designGraph.nodes[filletID]?.operation else {
            Issue.record("Expected the fillet feature.")
            return
        }
        #expect(fillet.radius == .length(0.002, .meter))
    }

    @Test func aRectangleSideOffersTheRectanglesWidthAndHeight() throws {
        var document = DesignDocument.empty()
        let sketchID = try document.createRectangleSketch(
            name: "Rect", plane: .xy, width: .length(0.3, .meter), height: .length(0.2, .meter)
        )
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[sketchID]?.operation,
              let lines = try document.rectangleLineIDs(in: sketch),
              let node = document.productMetadata.sceneNodes.values.first(where: { $0.reference?.featureID == sketchID }) else {
            Issue.record("Expected a rectangle sketch.")
            return
        }
        let side = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: sketchID, entityID: lines.left)))
        let snapshot = try SketchDimensionSnapshotService().snapshot(document: document, targets: [side])
        #expect(snapshot.entries.map(\.label) == ["Width", "Height"])
        #expect(snapshot.entries.map(\.isPrimaryForTarget) == [false, true])
        #expect(abs(snapshot.entries[0].resolvedValue - 0.3) < 1e-12)
        #expect(abs(snapshot.entries[1].resolvedValue - 0.2) < 1e-12)
    }
}
