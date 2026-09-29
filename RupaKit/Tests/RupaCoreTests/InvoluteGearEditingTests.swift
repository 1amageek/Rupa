import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Native gear source editing")
struct InvoluteGearEditingTests {
    @Test(.timeLimit(.minutes(3)))
    func creationParameterRegenerationAndUndoRetainOneGear() throws {
        let clock = ContinuousClock()
        var checkpoint = clock.now
        func record(_ operation: String) {
            let now = clock.now
            print("Gear \(operation): \(checkpoint.duration(to: now))")
            checkpoint = now
        }
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "gear_width", expression: .length(0.01, .meter), kind: .length)
        var gear = source()
        gear.dimensions[.width] = try ParameterExpressionParser().parse("gear_width",
            parameters: document.cadDocument.parameters, targetKind: .length)
        gear.dimensions[.twistAngle] = .angle(0, .radian)
        let session = EditorSession(document: document)
        _ = try session.execute(.createInvoluteGear(name: "Gear", gear: gear))
        record("creation")
        let id = try #require(session.document.cadDocument.designGraph.order.first)
        let product = session.document.productMetadata
        func expectWidth(_ width: Double) throws {
            let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
            #expect(evaluation.brep.bodies.count == 1)
            let heights = evaluation.brep.vertices.values.map { $0.point.z }
            #expect(abs(try #require(heights.min())) < 1e-9)
            #expect(abs(try #require(heights.max()) - width) < 1e-9)
            #expect(session.document.cadDocument.designGraph.order == [id])
            #expect(session.document.productMetadata == product)
        }
        try expectWidth(0.01)
        _ = try session.execute(.upsertParameter(name: "gear_width", expression: .length(0.02, .meter), kind: .length))
        record("parameter regeneration")
        try expectWidth(0.02)
        let parameterized = session.document.cadDocument.designGraph
        gear.dimensions[.width] = .length(0.015, .meter)
        _ = try session.execute(.setInvoluteGear(featureID: id, gear: gear))
        record("dimension replacement")
        try expectWidth(0.015)
        _ = try session.undo()
        record("undo")
        #expect(session.document.cadDocument.designGraph == parameterized)
        try expectWidth(0.02)
        _ = try session.redo()
        record("redo")
        try expectWidth(0.015)
        let before = session.document.cadDocument.designGraph
        let historyCount = session.commandStack.undoEntries.count
        gear.dimensions[.filletRadius] = .length(0.00001, .meter)
        #expect(throws: (any Error).self) {
            try session.execute(.setInvoluteGear(featureID: id, gear: gear))
        }
        #expect(session.document.cadDocument.designGraph == before)
        #expect(session.commandStack.undoEntries.count == historyCount)
        try expectWidth(0.015)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceEditingPreservesProductIdentityAndRejectsStaleValidation() throws {
        var document = DesignDocument.empty()
        var gear = source()
        let id = try document.createInvoluteGear(name: "Gear", gear: gear)
        let product = document.productMetadata
        #expect(document.cadDocument.designGraph.order == [id])
        #expect(product.sceneNodes.values.filter { $0.reference == .body(id) }.count == 1)
        let stale = try document.validate()
        try document.upsertParameter(name: "gear_width", expression: .length(0.02, .meter), kind: .length)
        gear.dimensions[.width] = try ParameterExpressionParser().parse("gear_width",
            parameters: document.cadDocument.parameters, targetKind: .length)
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.setInvoluteGear(featureID: id, gear: gear, validatedDocument: stale)
        }
        #expect(document.cadDocument.designGraph == before)
        try document.setInvoluteGear(featureID: id, gear: gear)
        #expect(document.productMetadata == product)
        #expect(document.cadDocument.designGraph.order == [id])
        #expect(document.cadDocument.designGraph.nodes[id]?.operation == .involuteGear(gear))
        let restored = try JSONDecoder().decode(CADDocument.self,
            from: JSONEncoder().encode(document.cadDocument))
        try restored.validate(tolerance: document.modelingSettings.tolerance)
        #expect(restored.designGraph == document.cadDocument.designGraph)
        let usages = ParameterSourceUsageService().usageMap(in: restored)
        let width = try #require(restored.parameters.parameters.values.first { $0.name == "gear_width" })
        #expect(usages[width.id]?.contains { $0.expressionPath == "involuteGear.width" } == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func geometricRefusalDoesNotCommitSourceOrHistory() throws {
        let session = EditorSession(document: .empty())
        let before = session.document
        var gear = source()
        gear.dimensions[.filletRadius] = .length(0.00001, .meter)
        #expect(throws: (any Error).self) {
            try session.execute(.createInvoluteGear(name: "Invalid Gear", gear: gear))
        }
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(session.document.productMetadata == before.productMetadata)
        #expect(session.commandStack.undoEntries.isEmpty)
    }

    private func source() -> InvoluteGearFeature {
        InvoluteGearFeature(toothCount: 32, dimensions: [
            .baseRadius: .length(0.032 * cos(.pi / 9), .meter),
            .pitchRadius: .length(0.032, .meter), .tipRadius: .length(0.034, .meter),
            .rootRadius: .length(0.0295, .meter), .filletRadius: .length(0.00076, .meter),
            .pitchToothAngle: .angle(.pi / 32, .radian), .width: .length(0.01, .meter),
            .twistAngle: .angle(0.1, .radian), .profileError: .length(1e-7, .meter),
            .sweepError: .length(1e-6, .meter)
        ], doubleHelical: true)
    }
}
