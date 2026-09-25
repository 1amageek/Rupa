import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Surface Creation foundation", .timeLimit(.minutes(1)))
struct SurfaceCreationFoundationTests {
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
