import Foundation
import RupaCore
import RupaProject
import SwiftCAD
import Testing
@testable import RupaKit

/// Complete Edge through the project workspace, the path the app's Edit menu takes.
@MainActor
@Test func completeEdgeCommitsThroughTheProjectWorkspace() async throws {
    func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: .length(x, .meter), y: .length(y, .meter)) }
    var document = DesignDocument.empty()
    let short = try document.createLineSketch(name: "Short", plane: .xy, start: point(0, 0.3), end: point(0.1, 0.3))
    _ = try document.createLineSketch(name: "Wall", plane: .xy, start: point(0.3, 0.2), end: point(0.3, 0.4))
    guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[short]?.operation,
          let entityID = sketch.entityOrder.first else {
        Issue.record("Expected the line sketch.")
        return
    }
    let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == short }).id
    let workspace = ProjectWorkspace(project: try ProjectController(
        document: document, evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge()
    ))
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "Complete Edge",
        commands: [.completeSketchCurve(target: SelectionTarget(
            sceneNodeID: node, component: .sketchEntity(.sketchEntity(featureID: short, entityID: entityID))
        ))],
        from: snapshot
    )
    _ = try await workspace.perform(action)
    let after = try #require(workspace.view?.document.document)
    guard case .sketch(let updated) = after.cadDocument.designGraph.nodes[short]?.operation,
          case .line(let line) = updated.entities[entityID] else {
        Issue.record("Expected the line.")
        return
    }
    #expect(abs(try after.cadDocument.parameters.resolvedValue(for: line.end.x).value - 0.3) < 1e-9)
}
