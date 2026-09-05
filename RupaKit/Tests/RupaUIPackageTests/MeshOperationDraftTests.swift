import Testing
import RupaCore
import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshOperationDraftMovesExactSourceElementsAndRejectsStaleReuse() async throws {
    let workspace = try await makeMeshDraftWorkspace()
    let initial = try #require(workspace.view)
    let item = try #require(initial.viewport.items.first)
    let asset = try #require(initial.document.document.authoredMeshAssets[item.mesh.identity])
    let vertex = asset.source.vertexIDs[0]
    var draft = MeshOperationDraft(sourceID: asset.id, contentIdentity: asset.contentIdentity, occurrenceID: item.id, unit: .millimeter)
    try draft.select(.vertex(vertex), toggle: false)
    draft.coordinates = ["10 mm", "0", "1 cm"]
    let request = try draft.request(from: initial)
    let preview = try await workspace.previewRenderPayload(request)
    let candidate = try #require(preview.document.authoredMeshAssets[asset.id])
    let index = try #require(candidate.source.vertexIDs.firstIndex(of: vertex))
    #expect(candidate.source.vertexPositions[index] == GeometryPoint3D(x: 0.01, y: 0, z: 0.01))
    #expect(workspace.view?.transactionRevision == initial.transactionRevision)
    let committed = try await workspace.commit(request)
    #expect(throws: EditorError.self) { try draft.request(from: committed.view) }
    #expect(committed.view.document.document.authoredMeshAssets[asset.id]?.source == candidate.source)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshOperationDraftValidatesDomainInputAndPreservesFaceBoundaryOrder() async throws {
    let workspace = try await makeMeshDraftWorkspace()
    let snapshot = try #require(workspace.view)
    let item = try #require(snapshot.viewport.items.first)
    let asset = try #require(snapshot.document.document.authoredMeshAssets[item.mesh.identity])
    var draft = MeshOperationDraft(sourceID: asset.id, contentIdentity: asset.contentIdentity, occurrenceID: item.id, unit: .millimeter)
    draft.kind = .extrude
    draft.coordinates = ["0", "0", "2 mm"]
    try draft.select(.face(asset.source.faceIDs[0]), toggle: false)
    let result = try await workspace.previewRenderPayload(draft.request(from: snapshot))
    #expect(try #require(result.document.authoredMeshAssets[asset.id]).source.faceIDs.count > asset.source.faceIDs.count)
    draft.coordinates[2] = "not a length"
    #expect(throws: EditorError.self) { try draft.request(from: snapshot) }
    draft.coordinates[2] = "1"
    draft.kind = .delete
    try draft.select(.vertex(asset.source.vertexIDs[0]), toggle: false)
    #expect(throws: (any Error).self) { try draft.request(from: snapshot) }
    draft.kind = .addFace
    draft.elements = asset.source.vertexIDs.reversed().map { .vertex($0) }
    let request = try draft.request(from: snapshot)
    guard case .primitive(.addFace(let ids)) = request.plan.steps[0].operation else {
        Issue.record("Expected an ordered face boundary"); return
    }
    #expect(ids == Array(asset.source.vertexIDs.reversed()))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshOperationDraftDelegatesMembershipValidationToWorkspace() async throws {
    let workspace = try await makeMeshDraftWorkspace()
    let snapshot = try #require(workspace.view)
    let item = try #require(snapshot.viewport.items.first)
    let asset = try #require(snapshot.document.document.authoredMeshAssets[item.mesh.identity])
    var draft = MeshOperationDraft(sourceID: asset.id, contentIdentity: asset.contentIdentity, occurrenceID: item.id, unit: .millimeter)
    draft.elements = [.vertex(MeshVertexID(UInt64.max))]
    draft.coordinates = ["1", "0", "0"]
    let request = try draft.request(from: snapshot)
    await #expect(throws: (any Error).self) {
        _ = try await workspace.previewRenderPayload(request)
    }
    #expect(workspace.view?.transactionRevision == snapshot.transactionRevision)
    #expect(workspace.view?.document.document.authoredMeshAssets[asset.id]?.source == asset.source)
    draft.elements = Array(repeating: .vertex(asset.source.vertexIDs[0]), count: MeshEditLimits.standard.maxSelectedIDs + 1)
    #expect(throws: EditorError.self) { try draft.request(from: snapshot) }
}

@MainActor
private func makeMeshDraftWorkspace() async throws -> ProjectWorkspace {
    var builder = MeshSourceBuilder()
    let a = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let b = try builder.addVertex(GeometryPoint3D(x: 0.01, y: 0, z: 0))
    let c = try builder.addVertex(GeometryPoint3D(x: 0, y: 0.01, z: 0))
    _ = try builder.addFace(vertexIDs: [a, b, c])
    let asset = try AuthoredMeshAsset(source: builder.build(), provenance: .created)
    var document = DesignDocument.empty()
    document.authoredMeshAssets[asset.id] = asset
    let representationID = GeometryRepresentationID()
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh", reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(category: .body, geometryRole: .mesh, geometryRepresentations: GeometryRepresentationSet(
            representations: [representationID: GeometryRepresentation(id: representationID, source: .authoredMesh(asset.id))],
            selection: GeometryRepresentationSelection(modeling: representationID, presentation: representationID)
        ))
    )
    let controller = try ProjectController(document: document, evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
    let workspace = ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    return workspace
}
