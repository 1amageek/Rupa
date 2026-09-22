import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Native feature length editing", .timeLimit(.minutes(1)))
struct FeatureLengthEditingTests {
    @Test func dimensionEditRetainsIncrementalValidation() throws {
        let store = CADDocumentStore()
        _ = try store.apply(.createExtrudedRectangle(name: "Box", plane: .xy,
            width: .length(40, .millimeter), height: .length(20, .millimeter),
            depth: .length(10, .millimeter), direction: .normal))
        let id = try #require(store.document.cadDocument.designGraph.order.last)
        _ = try store.apply(.setFeatureLength(featureID: id, expression: .length(15, .millimeter)))
        let metrics = try #require(store.currentModelingEvaluationMetrics)
        #expect(metrics.rebuiltFeatureCount == 1)
        #expect(metrics.reusedFeatureCount == 1)
        #expect(metrics.replayFallbackCount == 0)

        var document = store.document
        let stale = try document.validate()
        try document.upsertParameter(name: "height", expression: .length(20, .millimeter), kind: .length)
        let original = document.cadDocument
        #expect(throws: EditorError.self) {
            try document.setFeatureLength(featureID: id, expression: .length(20, .millimeter), validatedDocument: stale)
        }
        #expect(document.cadDocument.designGraph == original.designGraph)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(document.cadDocument) == encoder.encode(original))
    }

    @Test(arguments: Array(0...6))
    func replacesOnlyLengthAndReevaluates(kind: Int) throws {
        let session = try fixture(kind: kind)
        let original = session.document
        let id = try #require(original.cadDocument.designGraph.order.last)
        let feature = try #require(original.cadDocument.designGraph.nodes[id])
        let editor = NativeFeatureLengthEditor()
        let before = try DocumentEvaluator.modelingDefault(for: original).evaluateExact(original.cadDocument)
        _ = try session.execute(.setFeatureLength(featureID: id, expression: .length(0.004, .meter)))
        let updated = try #require(session.document.cadDocument.designGraph.nodes[id])
        #expect(updated.id == feature.id && updated.inputs == feature.inputs && updated.outputs == feature.outputs)
        #expect(updated.name == feature.name && updated.isSuppressed == feature.isSuppressed)
        #expect(editor.length(in: updated.operation)?.expression == .length(0.004, .meter))
        #expect(session.document.productMetadata == original.productMetadata)
        #expect(session.document.cadDocument.designGraph.order == original.cadDocument.designGraph.order)
        let evaluated = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
        if kind == 5 {
            #expect(evaluated.brep.vertices.values.allSatisfy { abs($0.point.z - 0.004) < 1e-10 })
        } else {
            let tolerance = original.modelingSettings.tolerance
            #expect(abs(try evaluated.brep.volume(tolerance: tolerance) - before.brep.volume(tolerance: tolerance)) > 1e-12)
        }
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(session.document.cadDocument))
        #expect(try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(restored).brep == evaluated.brep)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }

    @Test func shellRebindsParametersAndRefusesInvalidReplacement() throws {
        let session = try fixture(kind: 4)
        let id = try #require(session.document.cadDocument.designGraph.order.last)
        _ = try session.execute(.upsertParameter(name: "wall", expression: .length(0.003, .meter), kind: .length))
        let expression = try ParameterExpressionParser().parse("wall", parameters: session.document.cadDocument.parameters, targetKind: .length)
        _ = try session.execute(.setFeatureLength(featureID: id, expression: expression))
        _ = try session.execute(.upsertParameter(name: "wall", expression: .length(0.005, .meter), kind: .length))
        let original = session.document
        let result = try DocumentEvaluator.modelingDefault(for: original).evaluateExact(original.cadDocument)
        #expect(abs(try result.brep.volume(tolerance: original.modelingSettings.tolerance)
            - (0.001 - 0.09 * 0.09 * 0.095)) < 1e-12)
        for invalid in [CADExpression.length(0, .meter), .length(0.2, .meter), .angle(2, .degree)] {
            #expect(throws: (any Error).self) { try session.execute(.setFeatureLength(featureID: id, expression: invalid)) }
            #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
            #expect(session.document.productMetadata == original.productMetadata)
        }
        #expect(throws: (any Error).self) {
            try session.execute(.setFeatureLength(featureID: FeatureID(), expression: .length(0.002, .meter)))
        }
        let sketchID = try #require(original.cadDocument.designGraph.order.first)
        #expect(throws: (any Error).self) {
            try session.execute(.setFeatureLength(featureID: sketchID, expression: .length(0.002, .meter)))
        }
    }

    private func fixture(kind: Int) throws -> EditorSession {
        var document = DesignDocument.empty()
        if kind >= 5 {
            let source = try document.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
                bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
                topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0)))
            if kind == 6 {
                let feature = try FeatureNodeFactory.make(operation: .thicken(.init(target: .init(featureID: source),
                    thickness: .length(0.002, .meter))), id: FeatureID(), in: document.cadDocument,
                    tolerance: document.modelingSettings.tolerance)
                _ = try document.appendFeatureGraph(.init(features: [feature], primaryFeatureID: feature.id))
                return EditorSession(document: document)
            }
        } else {
            _ = try document.createExtrudedRectangle(name: "Box", plane: .xy, width: .length(0.1, .meter),
                height: .length(0.1, .meter), depth: .length(0.1, .meter), direction: .normal)
        }
        let session = EditorSession(document: document)
        if kind == 0 { return session }
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == (kind >= 4 ? .face : .edge) }?.selectionTarget())
        switch kind {
        case 4: _ = try session.execute(.createBodyShell(name: "Shell", target: target, thickness: .length(0.002, .meter)))
        case 5: _ = try session.execute(.createSheetSurfaceEdit(name: "Offset", target: target, edit: .offset(distance: .length(0.002, .meter))))
        default:
            let treatment: BodyEdgeTreatment = kind == 1 ? .fillet(radius: .length(0.002, .meter))
                : kind == 2 ? .chamfer(distance: .length(0.002, .meter)) : .g2Blend(distance: .length(0.002, .meter))
            _ = try session.execute(.createBodyEdgeTreatment(name: "Edge", target: target, treatment: treatment))
        }
        return session
    }
}
