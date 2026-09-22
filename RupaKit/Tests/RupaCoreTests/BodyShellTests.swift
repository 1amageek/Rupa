import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Native Shell editing")
struct BodyShellTests {
    @Test(.timeLimit(.minutes(1)))
    func thicknessParameterReevaluatesAndRejectsInvalidChanges() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(name: "Case", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal)
        try document.upsertParameter(name: "wall_thickness", expression: .length(0.002, .meter), kind: .length)
        let expression = try ParameterExpressionParser().parse("wall_thickness",
            parameters: document.cadDocument.parameters, targetKind: .length)
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let face = try #require(topology.entries.first { $0.kind == .face }?.selectionTarget())
        let session = EditorSession(document: document,
            selection: SelectionModel(selectedTargets: [face], hoveredTarget: face))
        _ = try session.execute(.createBodyShell(name: "Shell", target: face, thickness: expression))
        #expect(session.selection.selectedTargets.isEmpty)
        #expect(session.selection.hoveredTarget == nil)
        let before = session.document
        _ = try session.execute(.upsertParameter(name: "wall_thickness", expression: .length(0.004, .meter), kind: .length))
        let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
        #expect(abs(try result.brep.volume(tolerance: document.modelingSettings.tolerance)
            - (0.001 - 0.092 * 0.092 * 0.096)) < 1e-12)
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
        #expect(session.document.productMetadata == before.productMetadata)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(session.document.cadDocument))
        #expect(try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(restored).brep == result.brep)
        let fingerprint = try session.document.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance)
        #expect(throws: (any Error).self) {
            _ = try session.execute(.upsertParameter(name: "wall_thickness", expression: .length(0.06, .meter), kind: .length))
        }
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance) == fingerprint)
        _ = try session.undo()
        #expect(try session.document.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance)
            == before.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance))
    }

    @Test(.timeLimit(.minutes(1)))
    func everyBoxOpeningPreservesSourceAndUndo() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(name: "Case", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal)
        let session = EditorSession(document: document)
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let faces = try topology.entries.filter { $0.kind == .face }.map { try #require($0.selectionTarget()) }
        #expect(faces.count == 6)
        for face in faces {
            _ = try session.execute(.createBodyShell(name: "Shell", target: face, thickness: .length(0.002, .meter)))
            let result = try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(session.document.cadDocument)
            try result.brep.validate(level: .volumetric, tolerance: document.modelingSettings.tolerance)
            #expect(result.brep.bodies.count == 1)
            #expect(result.brep.faces.count == 14)
            #expect(abs(try result.brep.volume(tolerance: document.modelingSettings.tolerance)
                - (0.001 - 0.096 * 0.096 * 0.098)) < 1e-12)
            for (id, feature) in document.cadDocument.designGraph.nodes {
                #expect(session.document.cadDocument.designGraph.nodes[id] == feature)
            }
            #expect(session.document.productMetadata.sceneNodes[face.sceneNodeID]?.object?.geometryRepresentations.selection
                == document.productMetadata.sceneNodes[face.sceneNodeID]?.object?.geometryRepresentations.selection)
            let restored = try JSONDecoder().decode(CADDocument.self,
                from: JSONEncoder().encode(session.document.cadDocument))
            #expect(try DocumentEvaluator.modelingDefault(for: session.document).evaluateExact(restored).brep == result.brep)
            let edited = session.document
            #expect(throws: (any Error).self) {
                _ = try session.execute(.createBodyShell(name: "Stale", target: face, thickness: .length(0.002, .meter)))
            }
            #expect(try session.document.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance)
                == edited.cadDocument.sourceFingerprint(tolerance: document.modelingSettings.tolerance))
            #expect(session.document.productMetadata == edited.productMetadata)
            #expect(session.document.authoredMeshAssets == edited.authoredMeshAssets)
            _ = try session.undo()
            #expect(session.document.cadDocument.designGraph == document.cadDocument.designGraph)
            #expect(session.document.productMetadata == document.productMetadata)
        }
        for thickness in [0.0, -0.001, 0.051] {
            #expect(throws: (any Error).self) {
                _ = try session.execute(.createBodyShell(name: "Invalid", target: faces[0],
                    thickness: .length(thickness, .meter)))
            }
            #expect(session.document.cadDocument.designGraph == document.cadDocument.designGraph)
            #expect(session.document.productMetadata == document.productMetadata)
        }
    }
}
