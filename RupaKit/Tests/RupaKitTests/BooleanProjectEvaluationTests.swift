import Foundation
import RupaCADIntegration
import RupaCore
@testable import RupaKit
import RupaProject
import SwiftCAD
import Testing

/// A project evaluates every object, so after a Boolean or a Cut the objects of the bodies they
/// consumed must be gone: the project, not only the result, still evaluates.
@MainActor
@Suite(.timeLimit(.minutes(2)))
struct BooleanProjectEvaluationTests {
    private func projectEvaluates(_ document: DesignDocument) async throws {
        let workspace = ProjectWorkspace(project: try ProjectController(
            document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
            projector: DesignDocumentProjectBridge()
        ))
        _ = try await workspace.evaluate()
    }

    /// A 100 mm box and a second operand named "Other"; their body features and scene nodes.
    private func boxAnd(_ other: EditorCommand) throws -> (EditorSession, box: FeatureID, other: FeatureID, nodes: (SceneNodeID, SceneNodeID)) {
        let editor = EditorSession()
        _ = try editor.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        _ = try editor.execute(other)
        let nodes = editor.document.productMetadata.sceneNodes.values
        let box = try #require(nodes.first { $0.name.hasPrefix("Box") && $0.reference?.kind == .body })
        let second = try #require(nodes.first { $0.name.hasPrefix("Other") })
        return (editor, try #require(box.reference?.featureID), try #require(second.reference?.featureID), (box.id, second.id))
    }

    private let sheet = EditorCommand.createBSplineSurface(name: "Other", surface: .bilinearPatch(
        bottomLeft: Point3D(x: -1, y: -1, z: 0.025), bottomRight: Point3D(x: 1, y: -1, z: 0.025),
        topRight: Point3D(x: 1, y: 1, z: 0.025), topLeft: Point3D(x: -1, y: 1, z: 0.025)
    ))

    @Test func aBooleanOfTwoSolidsEvaluatesInTheProject() async throws {
        let (editor, box, other, nodes) = try boxAnd(.createAnalyticSphere(name: "Other", center: .origin, radius: 0.03))
        let result = try editor.execute(.createBoolean(
            name: "Boolean", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: other)], operation: .difference, keepTools: false
        ))
        let boolean = try #require(result.generatedIdentities.featureIDs.last)
        // The result takes over the target's object; the tool's object is gone.
        #expect(editor.document.productMetadata.sceneNodes[nodes.0]?.reference == .body(boolean))
        #expect(editor.document.productMetadata.sceneNodes[nodes.1] == nil)
        try await projectEvaluates(editor.document)
    }

    @Test func aBooleanWithASheetToolEvaluatesInTheProject() async throws {
        let (editor, box, other, _) = try boxAnd(sheet)
        _ = try editor.execute(.createBoolean(
            name: "Boolean", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: other)], operation: .difference, keepTools: false
        ))
        try await projectEvaluates(editor.document)
    }

    @Test func keptToolsKeepTheirObjects() async throws {
        let (editor, box, other, nodes) = try boxAnd(.createAnalyticSphere(name: "Other", center: .origin, radius: 0.03))
        _ = try editor.execute(.createBoolean(
            name: "Boolean", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: other)], operation: .difference, keepTools: true
        ))
        #expect(editor.document.productMetadata.sceneNodes[nodes.1]?.reference == .body(other))
        try await projectEvaluates(editor.document)
    }

    @Test func slicePiecesEvaluateInTheProject() async throws {
        let (editor, box, other, nodes) = try boxAnd(sheet)
        _ = try editor.execute(.createBoolean(
            name: "Slice", targets: [BooleanTargetReference(featureID: box)],
            tools: [BooleanToolReference(featureID: other)], operation: .slice, keepTools: false
        ))
        #expect(editor.document.productMetadata.sceneNodes[nodes.0] == nil)
        try await projectEvaluates(editor.document)
    }

    @Test func aCutEvaluatesInTheProject() async throws {
        let (editor, _, _, nodes) = try boxAnd(sheet)
        let face = try #require(try TopologySnapshotService().snapshot(document: editor.document).entries.first {
            $0.kind == .face && $0.sceneNodeID == nodes.1.description
        }?.selectionTarget())
        _ = try editor.execute(.cut(name: "Cut", targets: [nodes.0], cutters: [.face(face)], options: CutOptions()))
        try await projectEvaluates(editor.document)
    }
}
