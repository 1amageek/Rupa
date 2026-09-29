import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Suite("Involute gear drafts", .timeLimit(.minutes(1)))
struct InvoluteGearDraftTests {
    @Test func editingRetainsSourceIdentityOriginAndParameterExpressions() throws {
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "gear_width", expression: .length(0.01, .meter), kind: .length)
        let parameters = document.cadDocument.parameters
        var draft = InvoluteGearDraft(parameters: parameters, unit: .millimeter)
        draft.text[.width] = "gear_width * 2"
        draft.text[.twistAngle] = "-12 deg"
        draft.doubleHelical = true
        draft.origin = Point3D(x: 1, y: 2, z: 3)
        guard case let .createInvoluteGear(name, gear) = try draft.command(parameters: parameters, tolerance: .standard) else {
            Issue.record("A creation draft must produce the native gear command.")
            return
        }
        let feature = FeatureNode(name: name, operation: .involuteGear(gear))
        var editing = InvoluteGearDraft(feature: feature, parameters: parameters, unit: .millimeter)
        #expect(try editing.command(parameters: parameters, tolerance: .standard) == .setInvoluteGear(featureID: feature.id, gear: gear))
        editing.text[.width] = "25"
        guard case let .setInvoluteGear(id, updated) = try editing.command(parameters: parameters, tolerance: .standard) else {
            Issue.record("An editing draft must replace its original gear source.")
            return
        }
        #expect(id == feature.id)
        #expect(updated.origin == gear.origin)
        #expect(updated.doubleHelical)
        #expect(updated.dimensions[.width] == .length(0.025, .meter))
        for dimension in InvoluteGearFeature.Dimension.allCases where dimension != .width {
            #expect(updated.dimensions[dimension] == gear.dimensions[dimension])
        }
    }

    @Test func invalidDimensionsDoNotProduceCommands() throws {
        let parameters = ParameterTable()
        for source in ["unknown_parameter", "2 deg", "0 mm", "-1 mm"] {
            var draft = InvoluteGearDraft(parameters: parameters, unit: .millimeter)
            draft.text[.width] = source
            #expect(throws: (any Error).self) { try draft.command(parameters: parameters, tolerance: .standard) }
        }
        var draft = InvoluteGearDraft(parameters: parameters, unit: .millimeter)
        draft.toothCount = "3.5"
        #expect(throws: (any Error).self) { try draft.command(parameters: parameters, tolerance: .standard) }
        draft.toothCount = "32"
        draft.maximumSegments = "5"
        #expect(throws: (any Error).self) { try draft.command(parameters: parameters, tolerance: .standard) }
    }

    @Test func planningUsesDocumentTolerance() throws {
        let parameters = ParameterTable()
        let draft = InvoluteGearDraft(parameters: parameters, unit: .millimeter)
        let tolerance = SwiftCAD.ModelingTolerance(distance: 1e-8, angle: 1e-10)
        _ = try draft.command(parameters: parameters, tolerance: tolerance)
        var invalid = tolerance
        invalid.distance = .nan
        #expect(throws: GeometryError.self) {
            try draft.command(parameters: parameters, tolerance: invalid)
        }
    }
}
