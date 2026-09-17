import RupaCore
import RupaKit
import RupaProject
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaUI

@MainActor
@Suite("Inspector property transactions", .serialized, .timeLimit(.minutes(1)))
struct WorkspaceInspectorPropertyBatchTests {
    @Test func pickerBindingsCommitOnceAndUndoAllSelectedNodes() async throws {
        let nodes = [SceneNode(name: "First"), SceneNode(name: "Second")]
        let material = Material(name: "Blue", baseColor: ColorRGBA(r: 0, g: 0, b: 1, a: 1),
                                metallic: 0, roughness: 0.5, opacity: 1)
        var document = DesignDocument.empty(named: "Inspector Batch")
        document.productMetadata = ProductMetadata(
            sceneNodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }),
            rootSceneNodeIDs: nodes.map(\.id)
        )
        document.productMetadata.materialLibrary = MaterialLibrary(materials: [material.id: material])
        let controller = try ProjectController(document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
        let workspace = ProjectWorkspace(project: controller)
        _ = try await workspace.evaluate()
        var submissions: [([EditorCommand], String)] = []
        var view = WorkspaceObjectTransformInspectorView(nodes: nodes, displayUnit: .meter,
            positionSliderMetersRange: -10...10,
            materialOptions: [.init(id: material.id, name: material.name)],
            onCommitProperties: { submissions.append(($0, $1)) }, isBusy: false,
            hasMatchingPreview: false, onDraftChanged: {}, onPreview: { _ in }, onApply: {}, onCancel: {})
        for identifier in ["Visible", "Locked", "material"] {
            func choose() {
                switch identifier {
                case "Visible":
                    view.boolBinding("Visible", keyPath: \.isVisible, command: {
                        .setSceneNodeVisibility(id: $0, isVisible: $1)
                    }).wrappedValue = .off
                case "Locked":
                    view.boolBinding("Locked", keyPath: \.isLocked, command: {
                        .setSceneNodeLock(id: $0, isLocked: $1)
                    }).wrappedValue = .on
                default: view.materialBinding.wrappedValue = .material(material.id)
                }
            }
            view.isBusy = true
            choose()
            #expect(submissions.isEmpty)
            view.isBusy = false
            choose()
            #expect(submissions.count == 1)
            let submission = try #require(submissions.first)
            #expect(submission.0.count == nodes.count)
            let base = try #require(workspace.view)
            let action = try DefaultProjectWorkspaceActionPlanner().source(name: submission.1, commands: submission.0, from: base)
            _ = try await workspace.perform(action)
            let applied = try #require(workspace.view)
            for node in nodes {
                let result = try #require(applied.document.document.productMetadata.sceneNodes[node.id])
                switch identifier {
                case "Visible": #expect(!result.isVisible)
                case "Locked": #expect(result.isLocked)
                default: #expect(result.materialID == material.id)
                }
            }
            let undone = try await workspace.undo()
            #expect(undone.document.document.productMetadata == document.productMetadata)
            #expect(!undone.canUndo)
            let redone = try await workspace.redo()
            #expect(redone.document.document.productMetadata == applied.document.document.productMetadata)
            _ = try await workspace.undo()
            let invalid = submission.0 + [.setSceneNodeVisibility(id: SceneNodeID(), isVisible: false)]
            let beforeFailure = try #require(workspace.view)
            let rejected = try DefaultProjectWorkspaceActionPlanner().source(name: submission.1, commands: invalid, from: beforeFailure)
            await #expect(throws: Error.self) { _ = try await workspace.perform(rejected) }
            #expect(workspace.view?.authorityCoordinate == beforeFailure.authorityCoordinate)
            #expect(workspace.view?.document.document.productMetadata == document.productMetadata)
            submissions.removeAll()
        }
    }
}
