import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Covers authored extrusion Booleans: creation, source replacement, target supersession and measurement.
@Suite struct ExtrudeBooleanCommandTests {
    private let tolerance = 1.0e-9

    /// A 1 m cube and the section it was extruded from.
    @MainActor
    private func cubeSession() throws -> (EditorSession, FeatureID, SectionReference) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Target", plane: .xy,
            width: .length(1, .meter), height: .length(1, .meter),
            depth: .length(1, .meter), direction: .normal
        ))
        let targetID = try #require(session.document.cadDocument.designGraph.order.last)
        guard case .extrude(let target) = session.document.cadDocument.designGraph.nodes[targetID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The fixture cube is not an extrusion.")
        }
        return (session, targetID, target.section)
    }

    private func tool(
        section: SectionReference,
        operation: SolidOperation,
        targetID: FeatureID,
        keepTools: Bool = false
    ) -> ExtrudeFeature {
        ExtrudeFeature(
            section: section,
            distance: .length(2, .meter),
            direction: .normal,
            operation: operation,
            targets: [BooleanTargetReference(featureID: targetID)],
            keepTools: keepTools,
            resultKind: .solid
        )
    }

    @MainActor
    @Test func aBooleanExtrusionReplacesItsTargetAndMeasuresTheEvaluatedResult() throws {
        let (session, targetID, section) = try cubeSession()

        _ = try session.execute(.createExtrusion(
            name: "Tool", source: tool(section: section, operation: .union, targetID: targetID)
        ))
        let toolID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.cadDocument.designGraph.nodes[toolID])
        #expect(node.inputs.contains(FeatureInput(featureID: targetID, role: .target)))
        #expect(node.operation.supersededBodyFeatureIDs == [targetID])

        let measurement = try MeasurementService().measure(
            document: session.document,
            ruler: .standard(for: .meter)
        )
        #expect(measurement.counts.solids == 1)
        #expect(measurement.solids.first?.featureID == toolID.description)
        #expect(measurement.solids.first?.volumeMethod == .exactBRep)
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 2.0) < tolerance)
    }

    @MainActor
    @Test func replacingTheExtrusionKeepsItsSectionAndIsUndoable() throws {
        let (session, targetID, section) = try cubeSession()
        _ = try session.execute(.createExtrusion(
            name: "Tool", source: tool(section: section, operation: .union, targetID: targetID)
        ))
        let toolID = try #require(session.document.cadDocument.designGraph.order.last)

        _ = try session.execute(.setExtrusion(
            featureID: toolID, source: tool(section: section, operation: .intersect, targetID: targetID)
        ))
        let intersected = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        #expect(abs(intersected.totals.solidVolumeCubicMeters - 1.0) < tolerance)

        _ = try session.undo()
        let restored = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        #expect(abs(restored.totals.solidVolumeCubicMeters - 2.0) < tolerance)

        var changedSection = tool(section: section, operation: .union, targetID: targetID)
        changedSection.resultKind = .sheet
        #expect(throws: (any Error).self) {
            _ = try session.execute(.setExtrusion(featureID: toolID, source: changedSection))
        }
    }

    @MainActor
    @Test func invalidBooleanSourcesAreRejectedAndKeepToolsStillReplacesTheTarget() throws {
        let (session, targetID, section) = try cubeSession()
        let before = session.document

        var newBodyWithTargets = tool(section: section, operation: .newBody, targetID: targetID)
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createExtrusion(name: "Invalid", source: newBodyWithTargets))
        }
        newBodyWithTargets = tool(section: section, operation: .union, targetID: targetID)
        newBodyWithTargets.targets = []
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createExtrusion(name: "Invalid", source: newBodyWithTargets))
        }
        #expect(session.document.cadDocument.designGraph.order == before.cadDocument.designGraph.order)
        #expect(session.document.cadDocument.designGraph.nodes == before.cadDocument.designGraph.nodes)

        // Keep Tools keeps the extruded tool, not the target the result replaces.
        let kept = FeatureOperation.extrude(tool(section: section, operation: .union, targetID: targetID, keepTools: true))
        #expect(kept.supersededBodyFeatureIDs == [targetID])
    }

    @MainActor
    @Test func aBooleanExtrusionCombinesItsTargetWhereItIsShownAndTakesItsObjectAway() throws {
        let (session, targetID, section) = try cubeSession()
        let targetNode = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == targetID }).id
        // The cube is shown half a meter along X, so the 2 m tool overlaps half of it.
        _ = try session.execute(.setSceneNodeTransform(id: targetNode, localTransform: try .translation(Vector3D(x: 0.5, y: 0, z: 0))))
        _ = try session.execute(.createExtrusion(
            name: "Tool", source: tool(section: section, operation: .union, targetID: targetID)
        ))
        let toolID = try #require(session.document.cadDocument.designGraph.order.last)
        guard case .extrude(let placed) = session.document.cadDocument.designGraph.nodes[toolID]?.operation else {
            Issue.record("Expected the extrusion.")
            return
        }
        #expect(placed.targets.first?.placement != nil)
        #expect(session.document.productMetadata.sceneNodes.values.contains { $0.reference?.featureID == targetID } == false)
        #expect(session.document.productMetadata.sceneNodes.values.filter { $0.reference?.featureID == toolID }.count == 1)
        let measurement = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        #expect(abs(measurement.totals.solidVolumeCubicMeters - 2.5) < tolerance)

        // An edit may change how the targets combine, not which they are.
        _ = try session.execute(.setExtrusion(featureID: toolID, source: tool(section: section, operation: .intersect, targetID: targetID)))
        let intersected = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        #expect(abs(intersected.totals.solidVolumeCubicMeters - 0.5) < tolerance)
        var newBody = tool(section: section, operation: .newBody, targetID: targetID)
        newBody.targets = []
        #expect(throws: (any Error).self) {
            _ = try session.execute(.setExtrusion(featureID: toolID, source: newBody))
        }
    }

    @MainActor
    @Test func aDraftedExtrusionIsMeasuredAsTheBodyItEvaluatesTo() throws {
        let (session, _, section) = try cubeSession()
        let drafted = ExtrudeFeature(
            section: section, distance: .length(1, .meter), direction: .normal, resultKind: .solid,
            draftAngle: .angle(10, .degree)
        )
        _ = try session.execute(.createExtrusion(name: "Drafted", source: drafted))
        #expect(session.evaluationStatus == .valid)
        let measurement = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        // The 1 m square narrows by 2·tan 10° per meter: ∫₀¹ (1 − 2ht)² dh beside the 1 m cube.
        let t = tan(10 * Double.pi / 180)
        let frustum = 1 - 2 * t + 4.0 / 3.0 * t * t
        #expect(abs(measurement.totals.solidVolumeCubicMeters - (1 + frustum)) < tolerance)
    }
}
