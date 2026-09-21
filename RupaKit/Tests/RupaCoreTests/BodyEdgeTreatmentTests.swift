import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Suite("Native body edge treatment")
struct BodyEdgeTreatmentTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func allBoxEdgeOrientationsUseNativeGeometry(chamfer: Bool) throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let original = session.document
        let topology = try TopologySnapshotService().snapshot(document: original, metricPolicy: .omit)
        let targets = try topology.entries.filter { $0.kind == .edge }.map { try #require($0.selectionTarget()) }
        #expect(targets.count == 12)
        for target in targets {
            let radius = CADExpression.length(0.001, .meter)
            let treatment: BodyEdgeTreatment = chamfer ? .chamfer(distance: radius) : .fillet(radius: radius)
            _ = try session.execute(.createBodyEdgeTreatment(name: "Native edge", target: target, treatment: treatment))
            #expect(session.evaluationStatus == .valid)
            for (id, feature) in original.cadDocument.designGraph.nodes {
                #expect(session.document.cadDocument.designGraph.nodes[id] == feature)
            }
            let evaluated = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
            try evaluated.brep.validate(level: .volumetric, tolerance: original.modelingSettings.tolerance)
            #expect(evaluated.brep.bodies.count == 1)
            #expect(evaluated.brep.faces.count == 7)
            if !chamfer {
                #expect(evaluated.brep.geometry.surfaces.values.contains { if case .cylinder = $0 { true } else { false } })
            }
            let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(session.document.cadDocument))
            let repeated = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(restored)
            #expect(repeated.brep == evaluated.brep)
            _ = try session.undo()
            #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
            #expect(session.document.productMetadata == original.productMetadata)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func g2BlendRetainsPlacementAndUsesNativeSurface() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let topology = try TopologySnapshotService().snapshot(document: session.document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        let transform = try Transform3D(matrix: Matrix4x4(values: [
            1, 0, 0, 0.1, 0, 1, 0, 0.2, 0, 0, 1, 0.3, 0, 0, 0, 1
        ]))
        _ = try session.execute(.setSceneNodeTransform(id: target.sceneNodeID, localTransform: transform))
        _ = try session.execute(.createBodyEdgeTreatment(name: "G2", target: target,
            treatment: .g2Blend(distance: .length(0.001, .meter))))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        #expect(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }?.localTransform == transform)
        let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.geometry.surfaces.values.contains { if case .bSpline = $0 { true } else { false } })
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidTreatmentDoesNotPublishSource() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let original = session.document
        let generation = session.generation
        let topology = try TopologySnapshotService().snapshot(document: original, metricPolicy: .omit)
        let edge = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        for amount in [0.0, -0.001, 100.0] {
            #expect(throws: (any Error).self) {
                try session.execute(.createBodyEdgeTreatment(name: "Invalid", target: edge,
                    treatment: .fillet(radius: .length(amount, .meter))))
            }
            #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
            #expect(session.document.productMetadata == original.productMetadata)
            #expect(session.generation == generation)
        }
        let wrongTarget = SelectionTarget(sceneNodeID: edge.sceneNodeID, component: .edge(.bodyEdgeRightTop))
        #expect(throws: EditorError.self) {
            try session.execute(.createBodyEdgeTreatment(name: "Invalid", target: wrongTarget,
                treatment: .chamfer(distance: .length(0.001, .meter))))
        }
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }
}
