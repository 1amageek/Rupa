import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func viewportCanvasGhostIsRestrictedToTheExplicitPreviewOrEdit() {
    let target = SelectionTarget(sceneNodeID: SceneNodeID(), component: .edge(.bodyEdgeRightTop))
    let request = ViewportEdgeTreatmentPreviewRequest.chamfer(target: target, distance: 0.001)
    #expect(request.target == target)
    #expect(Viewport.drawsTransientBody(sceneNodeID: target.sceneNodeID, previewSceneNodeID: request.target.sceneNodeID, isEdited: false))
    #expect(!Viewport.drawsTransientBody(sceneNodeID: SceneNodeID(), previewSceneNodeID: request.target.sceneNodeID, isEdited: false))
    #expect(!Viewport.drawsTransientBody(sceneNodeID: nil, previewSceneNodeID: nil, isEdited: false))
    #expect(Viewport.drawsTransientBody(sceneNodeID: nil, previewSceneNodeID: nil, isEdited: true))
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func viewportEdgeTreatmentPreviewMatchesNativeCommit(chamfer: Bool) throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let original = session.document
    let topology = try TopologySnapshotService().snapshot(document: original, metricPolicy: .omit)
    let target = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
    let request: ViewportEdgeTreatmentPreviewRequest = chamfer
        ? .chamfer(target: target, distance: 0.001) : .fillet(target: target, radius: 0.001)
    let preview = try ViewportEdgeTreatmentPreviewDocumentBuilder().previewDocument(for: request, in: original)
    let featureID = try #require(preview.cadDocument.designGraph.order.last)
    #expect(preview.productMetadata.sceneNodes[target.sceneNodeID]?.reference == .body(featureID))
    for (id, feature) in original.cadDocument.designGraph.nodes {
        #expect(preview.cadDocument.designGraph.nodes[id] == feature)
    }
    let evaluated = try DocumentEvaluator.modelingDefault(for: preview).evaluateExact(preview.cadDocument)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.faces.count == 7)
    let treatment: BodyEdgeTreatment = chamfer ? .chamfer(distance: .length(0.001, .meter)) : .fillet(radius: .length(0.001, .meter))
    _ = try session.execute(.createBodyEdgeTreatment(name: "Edge treatment", target: target, treatment: treatment))
    let committedID = try #require(session.document.cadDocument.designGraph.order.last)
    #expect(preview.cadDocument.designGraph.nodes[featureID]?.operation == session.document.cadDocument.designGraph.nodes[committedID]?.operation)
    #expect(session.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference == .body(committedID))
}
