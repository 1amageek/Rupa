import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Box Corner source")
struct BoxCornerTests {
    @Test(.timeLimit(.minutes(1)))
    func cornerEditsPreserveIdentityDimensionsAndRestoreSource() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.08, .meter),
            depth: .length(0.06, .meter), direction: .normal)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body })
        let id = try #require(node.reference?.featureID)
        let original = document.cadDocument.designGraph.nodes[id]
        try document.setSceneNodeObjectProperty(id: node.id, propertyID: .init(rawValue: "corner.radius"), value: .length(0.01))
        #expect(try document.boxCornerRadius(id) == 0.01)
        #expect(document.productMetadata.sceneNodes[node.id]?.reference == node.reference)
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document.cadDocument)
        #expect(rounded.brep.faces.count == 26)
        let beforeFailure = document
        #expect(throws: EditorError.self) {
            try document.setSceneNodeObjectProperty(id: node.id, propertyID: .init(rawValue: "corner.radius"), value: .length(1))
        }
        #expect(try document.cadDocument.sourceFingerprint(tolerance: .standard)
            == beforeFailure.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(document.productMetadata == beforeFailure.productMetadata)
        try document.setCubeDimensions(featureID: id, sizeX: .length(0.12, .meter),
            sizeY: .length(0.06, .meter), sizeZ: .length(0.08, .meter))
        let dimensions = try ObjectDimensionSourceResolver().resolve(target: .init(sceneNodeID: node.id, component: .object), in: document)
        #expect(abs(dimensions.sizeX - 0.12) < 1e-12)
        #expect(try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document.cadDocument).brep.faces.count == 26)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".rupa")
        defer { do { try FileManager.default.removeItem(at: url) } catch { Issue.record(error) } }
        try DocumentFileService().save(document, to: url)
        document = try DocumentFileService().load(from: url).document
        #expect(try document.boxCornerRadius(id) == 0.01)
        try document.setSceneNodeObjectProperty(id: node.id, propertyID: .init(rawValue: "corner.radius"), value: .length(0))
        #expect(document.cadDocument.designGraph.nodes[id]?.operation == original?.operation)
        #expect(try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document.cadDocument).brep.faces.count == 6)
    }

    @MainActor @Test(.timeLimit(.minutes(1)))
    func propertyCommandSupportsUndo() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let node = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body })
        let id = try #require(node.reference?.featureID)
        _ = try session.execute(.setSceneNodeObjectProperty(id: node.id,
            propertyID: "corner.radius", value: .length(0.001)))
        #expect(try session.document.boxCornerRadius(id) == 0.001)
        _ = try session.undo()
        #expect(try session.document.boxCornerRadius(id) == 0)
        _ = try session.redo()
        #expect(try session.document.boxCornerRadius(id) == 0.001)
    }
}
