import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Curve section source transactions", .timeLimit(.minutes(1)))
struct CurveExtrudeCommandTests {
    @Test(arguments: [false, true])
    func curveSheetPreservesProvenanceHistoryAndFailureAtomicity(revolve: Bool) throws {
        let session = EditorSession()
        _ = try session.execute(.createLineSketch(name: "Section", plane: .xy,
            start: SketchPoint(x: .length(20, .millimeter), y: .length(0, .millimeter)),
            end: SketchPoint(x: .length(20, .millimeter), y: .length(20, .millimeter))))
        let original = session.document
        let source = try #require(original.cadDocument.designGraph.order.last)
        let section = SectionReference.curve(CurveSectionReference(featureID: source))
        #expect(try original.modelingSectionReference(for: source) == section)
        let command: EditorCommand = revolve
            ? .revolveSection(name: "Curve sheet", section: section,
                axis: RevolveAxis(origin: .origin, direction: .unitY), angle: .angle(180, .degree), resultKind: .sheet)
            : .extrudeSection(name: "Curve sheet", section: section,
                distance: .length(10, .millimeter), direction: .normal, resultKind: .sheet)
        #expect(try JSONDecoder().decode(EditorCommand.self, from: JSONEncoder().encode(command)) == command)
        _ = try session.execute(command)
        #expect(session.evaluationStatus == .valid)
        let feature = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference == .body(feature) })
        #expect(node.object?.geometryRole == .surface)
        #expect(session.document.cadDocument.designGraph.nodes[feature]?.inputs == [FeatureInput(featureID: source, role: .curve)])
        let created = session.document
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(created.cadDocument))
        let evaluated = try DocumentEvaluator.modelingDefault(for: created).evaluateExact(restored)
        #expect(evaluated.brep.faces.count == (revolve ? 2 : 1))
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        _ = try session.undo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == original.cadDocument.sourceFingerprint(tolerance: .standard))
        _ = try session.redo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == created.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(throws: (any Error).self) {
            try session.execute(revolve
                ? .revolveSection(name: "Invalid solid", section: section,
                    axis: RevolveAxis(origin: .origin, direction: .unitY), angle: .angle(180, .degree), resultKind: .solid)
                : .extrudeSection(name: "Invalid solid", section: section,
                    distance: .length(10, .millimeter), direction: .normal, resultKind: .solid))
        }
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == created.cadDocument.sourceFingerprint(tolerance: .standard))
        #expect(session.document.productMetadata == created.productMetadata)
    }
}
