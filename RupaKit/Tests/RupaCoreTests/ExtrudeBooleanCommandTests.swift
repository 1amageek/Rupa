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
    @Test func invalidBooleanSourcesAreRejectedAndKeepToolsRetainsTheTarget() throws {
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

        let kept = FeatureOperation.extrude(tool(section: section, operation: .union, targetID: targetID, keepTools: true))
        #expect(kept.supersededBodyFeatureIDs.isEmpty)
    }
}
