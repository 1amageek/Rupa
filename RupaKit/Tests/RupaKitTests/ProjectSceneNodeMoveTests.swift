import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceMoveSceneNodePreservesEvaluatedOccurrenceWorldTransform() async throws {
    let fixture = try projectSceneNodeMoveDocument(named: "Workspace scene move")
    let controller = try ProjectController(
        document: fixture.document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let initialOccurrenceID = try #require(
        initial.sceneNodeIDByOccurrenceID.first(where: { $0.value == fixture.meshNodeID })?.key
    )
    let initialItem = try #require(initial.viewport.items.first { $0.id == initialOccurrenceID })
    let transaction = try ProjectSourceTransaction(
        name: "scene.move.mesh",
        commands: [
            .moveSceneNodes(
                ids: [fixture.meshNodeID],
                parentID: fixture.destinationNodeID,
                beforeSiblingID: nil
            ),
        ],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )

    let committed = try await workspace.commit(transaction)
    let occurrenceID = try #require(
        committed.sceneNodeIDByOccurrenceID.first(where: { $0.value == fixture.meshNodeID })?.key
    )
    let evaluated = try await controller.currentEvaluation()
    let occurrence = try #require(evaluated.occurrences[occurrenceID])
    let viewportItem = try #require(
        committed.viewport.items.first(where: { $0.id == occurrenceID })
    )

    #expect(committed.document.document.productMetadata.sceneNodes[fixture.destinationNodeID]?.childIDs == [fixture.meshNodeID])
    #expect(occurrence.reference == .authoredMesh(fixture.assetID))
    #expect(occurrence.worldTransform.values.count == 16)
    #expect(occurrence.worldTransform.values[3] == 12.0)
    #expect(occurrence.worldTransform.values[7] == 0.0)
    #expect(occurrence.worldTransform.values[11] == 0.0)
    #expect(viewportItem.worldTransform == occurrence.worldTransform)
    #expect(viewportItem.worldTransform == initialItem.worldTransform)
    #expect(committed.transactionRevision == DocumentTransactionRevision(
        initial.transactionRevision.value + 1
    ))
    await #expect(throws: Error.self) { _ = try await workspace.commit(transaction) }
    let afterRefusal = await workspace.view
    #expect(afterRefusal?.publicationSequence == committed.publicationSequence)
    let undone = try await workspace.undo()
    #expect(undone.document.document.productMetadata == initial.document.document.productMetadata)
    #expect(!undone.canUndo)
    let redone = try await workspace.redo()
    #expect(redone.document.document.productMetadata == committed.document.document.productMetadata)
}

private struct ProjectSceneNodeMoveFixture {
    let document: DesignDocument
    let assetID: GeometrySourceID
    let meshNodeID: SceneNodeID
    let destinationNodeID: SceneNodeID
}

private func projectSceneNodeMoveDocument(
    named name: String
) throws -> ProjectSceneNodeMoveFixture {
    var document = DesignDocument.empty(named: name)
    let mesh = try projectSceneNodeMoveTriangleMesh(identity: "scene.move.mesh")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    document.authoredMeshAssets[asset.id] = asset
    let representationID: GeometryRepresentationID = "representation.scene-move"
    let meshNode = SceneNode(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: GeometryRepresentationSet(
                representations: [
                    representationID: GeometryRepresentation(
                        id: representationID,
                        source: .authoredMesh(asset.id)
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: representationID,
                    presentation: representationID
                )
            )
        ),
        localTransform: try projectSceneNodeMoveTranslation(2.0)
    )
    let parent = SceneNode(
        name: "Source parent",
        childIDs: [meshNode.id],
        localTransform: try projectSceneNodeMoveTranslation(10.0)
    )
    let destination = SceneNode(
        name: "Destination",
        localTransform: try projectSceneNodeMoveTranslation(-5.0)
    )
    document.authoredMeshAssets[asset.id] = asset
    document.productMetadata.sceneNodes[meshNode.id] = meshNode
    document.productMetadata.sceneNodes[parent.id] = parent
    document.productMetadata.sceneNodes[destination.id] = destination
    let rootID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    var root = try #require(document.productMetadata.sceneNodes[rootID])
    root.childIDs = [parent.id, destination.id]
    document.productMetadata.sceneNodes[rootID] = root
    try document.productMetadata.validate(
        against: document.cadDocument,
        objectRegistry: .builtIn
    )
    return ProjectSceneNodeMoveFixture(
        document: document,
        assetID: asset.id,
        meshNodeID: meshNode.id,
        destinationNodeID: destination.id
    )
}

private func projectSceneNodeMoveTriangleMesh(
    identity: GeometrySourceID
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func projectSceneNodeMoveTranslation(_ x: Double) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(values: [
            1.0, 0.0, 0.0, x,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
}
