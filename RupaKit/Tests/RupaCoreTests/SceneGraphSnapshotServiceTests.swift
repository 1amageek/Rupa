import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func sceneGraphSnapshotProjectsExactProductPlacementWithoutGeometry() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first { node in
            node.reference?.kind == .body && node.reference?.featureID == bodyFeatureID
        }?.id
    )
    let transform = Transform3D(matrix: try Matrix4x4(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        1.25, -0.5, 0.125, 1,
    ]))
    _ = try session.execute(
        .setSceneNodeTransform(id: bodySceneNodeID, localTransform: transform)
    )
    _ = try session.execute(
        .setSceneNodeVisibility(id: bodySceneNodeID, isVisible: false)
    )

    let result = SceneGraphSnapshotService().result(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let bodyNode = try #require(result.nodes.first { $0.id == bodySceneNodeID })

    #expect(result.generation == session.generation)
    #expect(result.dirty)
    #expect(result.rootSceneNodeIDs == session.document.productMetadata.rootSceneNodeIDs)
    #expect(result.nodes.map(\.id) == result.nodes.map(\.id).sorted())
    #expect(bodyNode.reference?.kind == .body)
    #expect(bodyNode.reference?.featureID == bodyFeatureID)
    #expect(bodyNode.sourceFeatureID == bodyFeatureID)
    #expect(bodyNode.localTransform == transform)
    #expect(!bodyNode.isVisible)
    #expect(try JSONEncoder().encode(result).count > 0)
}
