import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Surface Creation foundation", .timeLimit(.minutes(1)))
struct SurfaceCreationFoundationTests {
    @Test(arguments: [(-0.01, 0.03), (0.01, 0.03), (-0.03, -0.01), (0.0, -0.02)])
    func signedExtentsAgreeAcrossCreationMeasurementEditingAndReplay(endpoints: (Double, Double)) throws {
        let session = EditorSession()
        _ = try session.execute(.createRectangleSketch(name: "Section", plane: .xy,
            width: .length(8, .millimeter), height: .length(4, .millimeter)))
        let profile = try #require(session.document.cadDocument.designGraph.order.first)
        let command = EditorCommand.extrudeSection(name: "Signed extent", section: .profile(.init(featureID: profile)),
            distance: .length(endpoints.1, .meter), startDistance: .length(endpoints.0, .meter),
            direction: .normal, resultKind: .solid)
        #expect(try JSONDecoder().decode(EditorCommand.self, from: JSONEncoder().encode(command)) == command)
        _ = try session.execute(command)
        #expect(session.evaluationStatus == .valid)
        let id = try #require(session.document.cadDocument.designGraph.order.last)
        let before = session.document
        _ = try ValidatedDesignDocument(before)
        let measured = try MeasurementService().measure(document: before, ruler: .standard(for: .millimeter))
        let solid = try #require(measured.solids.first { $0.featureID == id.description })
        #expect(abs(solid.bounds.minZ - min(endpoints.0, endpoints.1)) < 1e-8)
        #expect(abs(solid.bounds.maxZ - max(endpoints.0, endpoints.1)) < 1e-8)
        #expect(abs(solid.volumeCubicMeters - 0.008 * 0.004 * abs(endpoints.1 - endpoints.0)) < 1e-12)
        let edit = EditorCommand.setExtrudeExtents(featureID: id,
            start: .length(-0.04, .meter), end: .length(0.05, .meter))
        _ = try session.execute(edit)
        #expect(session.evaluationStatus == .valid)
        let edited = session.document
        _ = try session.undo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == before.cadDocument.sourceFingerprint(tolerance: .standard))
        _ = try session.redo()
        var reopened = edited
        reopened.cadDocument = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(edited.cadDocument))
        _ = try ValidatedDesignDocument(reopened)
        let result = try DocumentEvaluator.modelingDefault(for: reopened).evaluateExact(reopened.cadDocument)
        #expect(abs(try #require(result.brep.vertices.values.map(\.point.z).min()) + 0.04) < 1e-8)
        #expect(abs(try #require(result.brep.vertices.values.map(\.point.z).max()) - 0.05) < 1e-8)
        #expect(throws: (any Error).self) {
            try session.execute(.setExtrudeExtents(featureID: id, start: .length(1, .meter), end: .length(1, .meter)))
        }
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == edited.cadDocument.sourceFingerprint(tolerance: .standard))
    }

    @Test(arguments: [false, true])
    func signedExtentFaceOffsetAndSizeEditsPreserveTheOtherEndpoint(reverse: Bool) throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let id = try #require(session.document.cadDocument.designGraph.order.last)
        _ = try session.execute(.setExtrudeExtents(featureID: id,
            start: .length(reverse ? 0.03 : -0.01, .meter), end: .length(reverse ? -0.01 : 0.03, .meter)))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference == .body(id) })
        let component = try #require(try GeneratedTopologySelectionResolver().componentID(
            for: node.id, bodyFace: .front, in: session.document))
        _ = try session.execute(.offsetBodyFace(target: .init(sceneNodeID: node.id, component: .face(component)),
            distance: .length(0.002, .meter)))
        let measured = try MeasurementService().measure(document: session.document, ruler: .standard(for: .millimeter))
        let body = try #require(measured.solids.first { $0.featureID == id.description })
        #expect(abs(body.bounds.minZ + 0.012) < 1e-8)
        #expect(abs(body.bounds.maxZ - 0.03) < 1e-8)
        #expect(session.document.productMetadata.sceneNodes[node.id]?.localTransform == node.localTransform)
        var resized = session.document
        try resized.setCubeDimensions(featureID: id, sizeX: .length(0.02, .meter),
            sizeY: .length(0.05, .meter), sizeZ: .length(0.01, .meter))
        let sizes = try resized.resolvedExtrudedBodyDimensions(featureID: id)
        #expect(abs(sizes.sizeY - 0.05) < 1e-8)
        let evaluation = try DocumentEvaluator.modelingDefault(for: resized).evaluateExact(resized.cadDocument)
        let z = evaluation.brep.vertices.values.map(\.point.z)
        #expect(abs(try #require(z.min()) - (reverse ? -0.02 : -0.012)) < 1e-8)
        #expect(abs(try #require(z.max()) - (reverse ? 0.03 : 0.038)) < 1e-8)
    }

    @Test(arguments: [false, true])
    func extrusionPreservesSheetContractThroughHistoryAndPersistence(sheet: Bool) throws {
        let session = EditorSession()
        _ = try session.execute(.createRectangleSketch(name: "Section", plane: .xy,
            width: .length(8, .millimeter), height: .length(4, .millimeter)))
        let original = session.document
        let profile = try #require(original.cadDocument.designGraph.order.first)
        let command = EditorCommand.extrudeProfile(name: "Extrusion",
            profile: ProfileReference(featureID: profile), distance: .length(2, .millimeter),
            direction: .normal, resultKind: sheet ? .sheet : .solid)
        #expect(try JSONDecoder().decode(EditorCommand.self, from: JSONEncoder().encode(command)) == command)
        _ = try session.execute(command)
        #expect(session.evaluationStatus == .valid)
        let id = try #require(session.document.cadDocument.designGraph.order.last)
        let feature = try #require(session.document.cadDocument.designGraph.nodes[id])
        #expect(feature.outputs == [FeatureOutput(role: sheet ? .sheet : .body)])
        #expect(session.document.cadDocument.designGraph.nodes[profile] == original.cadDocument.designGraph.nodes[profile])
        let node = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference == .body(id) })
        #expect(node.object?.geometryRole == (sheet ? .surface : .solid))
        var reopened = session.document
        reopened.cadDocument = try JSONDecoder().decode(CADDocument.self,
            from: JSONEncoder().encode(session.document.cadDocument))
        reopened.productMetadata = try JSONDecoder().decode(ProductMetadata.self,
            from: JSONEncoder().encode(session.document.productMetadata))
        try reopened.productMetadata.validate(against: reopened.cadDocument, objectRegistry: .builtIn)
        let evaluated = try DocumentEvaluator.modelingDefault(for: reopened).evaluateExact(reopened.cadDocument)
        try evaluated.brep.validate(level: .exact, tolerance: reopened.modelingSettings.tolerance)
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.kind == (sheet ? .sheet : .solid) })
        #expect(evaluated.brep.faces.count == (sheet ? 4 : 6))
        _ = try session.undo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == original.cadDocument.sourceFingerprint(tolerance: .standard))
        _ = try session.redo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == reopened.cadDocument.sourceFingerprint(tolerance: .standard))
        let beforeFailure = session.document
        #expect(throws: (any Error).self) {
            try session.execute(.extrudeProfile(name: "Invalid", profile: ProfileReference(featureID: FeatureID()),
                distance: .length(2, .millimeter), direction: .normal, resultKind: .sheet))
        }
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == beforeFailure.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(session.document.productMetadata == beforeFailure.productMetadata)
    }
}
