import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Loft source editing", .timeLimit(.minutes(1)))
struct LoftEditingTests {
    @Test func replacementRetainsIdentitySupportsUndoAndRejectsInvalidGeometry() throws {
        var document = DesignDocument.empty()
        var sourceIDs: [FeatureID] = []
        for z in [0.0, 0.02] {
            sourceIDs.append(try document.createLineSketch(name: "Section",
                plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: z), normal: .unitZ)),
                start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                end: SketchPoint(x: .length(0.04, .meter), y: .length(0, .meter))))
        }
        let session = EditorSession(document: document)
        let original = LoftFeature(sections: sourceIDs.map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0)))
        }, options: LoftOptions(resultKind: .sheet))
        _ = try session.execute(.createLoft(name: "Loft", sections: original.sections, options: original.options))
        let id = try #require(session.document.cadDocument.designGraph.order.last)
        let before = session.document
        var edited = original
        edited.sections = sourceIDs.reversed().map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0,
                parameterDomain: .closed(0.01, 0.03), isReversed: true)), smoothTangentScale: 0.5)
        }
        edited.options.surfaceMode = .smooth
        _ = try session.execute(.setLoft(featureID: id, loft: edited))
        let after = session.document
        #expect(after.cadDocument.designGraph.order == before.cadDocument.designGraph.order)
        #expect(after.cadDocument.designGraph.nodes[id]?.operation == .loft(edited))
        #expect(after.cadDocument.designGraph.nodes[id]?.inputs.map(\.featureID) == Array(sourceIDs.reversed()))
        #expect(Set(after.productMetadata.sceneNodes.keys) == Set(before.productMetadata.sceneNodes.keys))
        let body = try #require(after.productMetadata.sceneNodes.values.first { $0.object?.sourceFeatureID == id })
        #expect(body.object?.sourceSection?.featureID == sourceIDs.last)
        try expectRestrictedGeometry(session)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(session.document.productMetadata == before.productMetadata)
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph == after.cadDocument.designGraph)
        try expectRestrictedGeometry(session)

        let historyCount = session.commandStack.undoEntries.count
        var invalid = edited
        invalid.sections[0].section = .curve(CurveSectionReference(featureID: sourceIDs[1], parameterDomain: .closed(10, 20)))
        #expect(throws: (any Error).self) { try session.execute(.setLoft(featureID: id, loft: invalid)) }
        #expect(session.document.cadDocument.designGraph == after.cadDocument.designGraph)
        #expect(session.document.productMetadata == after.productMetadata)
        #expect(session.commandStack.undoEntries.count == historyCount)
        try expectRestrictedGeometry(session)

        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: session.document.modelingSettings.tolerance)
        try store.writePackage(for: session.document.cadDocument, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes[id]?.operation == .loft(edited))
        let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(restored)
        #expect(result.brep.faces.count == 1)
    }

    private func expectRestrictedGeometry(_ session: EditorSession) throws {
        let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        #expect(evaluation.brep.bodies.count == 1)
        #expect(evaluation.brep.faces.count == 1)
        #expect(evaluation.brep.vertices.values.allSatisfy {
            abs($0.point.x - 0.01) < 1e-10 || abs($0.point.x - 0.03) < 1e-10
        })
    }
}
