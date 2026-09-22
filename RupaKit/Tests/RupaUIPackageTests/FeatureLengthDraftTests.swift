import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Suite("Feature dimension drafts", .timeLimit(.minutes(1)))
struct FeatureLengthDraftTests {
    @Test func retainsIdentityAndExpressionReferences() throws {
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "wall_thickness", expression: .length(0.002, .meter), kind: .length)
        let expression = try ParameterExpressionParser().parse("wall_thickness * 2",
            parameters: document.cadDocument.parameters, targetKind: .length)
        let feature = FeatureNode(operation: .shell(.init(target: .init(featureID: FeatureID()), removedFaces: [], thickness: expression)))
        var draft = try #require(FeatureLengthDraft(feature: feature, parameters: document.cadDocument.parameters, unit: .millimeter))
        #expect(draft.id == feature.id)
        #expect(try draft.command(parameters: document.cadDocument.parameters) == .setFeatureLength(featureID: feature.id, expression: expression))
        draft.text = "3"
        #expect(try draft.command(parameters: document.cadDocument.parameters) == .setFeatureLength(featureID: feature.id, expression: .length(0.003, .meter)))
        draft.text = "unknown_parameter"
        #expect(throws: (any Error).self) { try draft.command(parameters: document.cadDocument.parameters) }
        draft.text = "2 deg"
        #expect(throws: (any Error).self) { try draft.command(parameters: document.cadDocument.parameters) }
    }
}
