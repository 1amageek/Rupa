import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Synchronization
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceMeshRenderPreviewUsesStagedMeshAndDoesNotPublish() async throws {
    let probe = MeshRenderPreviewEvaluationProbe()
    let document = try meshRenderPreviewDocument(named: "Mesh Preview")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try ProjectController(
        document: document,
        evaluatorPreparer: MeshRenderPreviewEvaluatorPreparer(probe: probe),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let evaluationsBeforePreview = probe.evaluationCount
    let request = try meshRenderPreviewRequest(asset: asset, snapshot: initial, z: 2)
    let expected = try DefaultMeshEditPlanExecutor().execute(
        plan: request.plan,
        source: asset.source
    )

    let payload = try await workspace.previewRenderPayload(request)
    let item = try #require(payload.presentationScene.items.first)
    let retained = try await controller.currentState()
    let published = try #require(await workspace.view)

    #expect(item.reference == .authoredMesh(asset.id))
    #expect(item.mesh == expected.source)
    #expect(payload.document.authoredMeshAssets[asset.id]?.source == expected.source)
    #expect(payload.presentationScene.snapshotID.purpose == .presentation)
    #expect(payload.presentationScene.snapshotID.sourceRevision
        == DocumentTransactionRevision(initial.transactionRevision.value + 1))
    #expect(probe.evaluationCount == evaluationsBeforePreview + 1)
    #expect(retained.document.authoredMeshAssets[asset.id] == asset)
    #expect(retained.transactionRevision == initial.transactionRevision)
    #expect(retained.publicationSequence == initial.publicationSequence)
    #expect(published.viewport.items.isEmpty == false)
    #expect(published.transactionRevision == initial.transactionRevision)
    #expect(published.publicationSequence == initial.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceMeshRenderPreviewRejectsStaleReplacement() async throws {
    let gate = MeshRenderPreviewGate()
    defer { gate.release() }
    let document = try meshRenderPreviewDocument(named: "Mesh Preview Stale")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try meshRenderPreviewController(document: document)
    let workspace = await ProjectWorkspace(
        project: controller,
        previewRenderPayloadBuilder: BlockingMeshRenderPreviewBuilder(gate: gate)
    )
    let initial = try await workspace.evaluate()
    let request = try meshRenderPreviewRequest(asset: asset, snapshot: initial, z: 3)
    let preview = Task {
        try await workspace.previewRenderPayload(request)
    }
    try await gate.waitUntilStarted()

    let replacement = try ProjectSourceTransaction(
        name: "mesh.preview.replacement",
        commands: [.renameDocument(name: "Committed")],
        expectedProjectID: initial.projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )
    let committed = try await workspace.commit(replacement)
    gate.release()

    var staleCode: ProjectMeshEditError.Code?
    do {
        _ = try await preview.value
    } catch let error as ProjectMeshEditError {
        staleCode = error.code
    }

    #expect(staleCode == .transactionRevisionMismatch)
    #expect(committed.document.name == "Committed")
    #expect(await workspace.view?.document.name == "Committed")
    #expect(await workspace.view?.publicationSequence == committed.publicationSequence)
    #expect(await controller.currentTransactionRevision() == committed.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceMeshRenderPreviewCancellationDoesNotPublish() async throws {
    let gate = MeshRenderPreviewGate()
    defer { gate.release() }
    let document = try meshRenderPreviewDocument(named: "Mesh Preview Cancel")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try meshRenderPreviewController(document: document)
    let workspace = await ProjectWorkspace(
        project: controller,
        previewRenderPayloadBuilder: BlockingMeshRenderPreviewBuilder(gate: gate)
    )
    let initial = try await workspace.evaluate()
    let request = try meshRenderPreviewRequest(asset: asset, snapshot: initial, z: 4)
    let preview = Task {
        try await workspace.previewRenderPayload(request)
    }
    try await gate.waitUntilStarted()
    preview.cancel()
    gate.release()

    var cancellationCode: ProjectMeshEditError.Code?
    do {
        _ = try await preview.value
    } catch let error as ProjectMeshEditError {
        cancellationCode = error.code
    }

    #expect(cancellationCode == .cancelled)
    #expect(await workspace.view?.transactionRevision == initial.transactionRevision)
    #expect(await workspace.view?.publicationSequence == initial.publicationSequence)
    #expect(await controller.currentTransactionRevision() == initial.transactionRevision)
    #expect(try await controller.currentState().document.authoredMeshAssets[asset.id] == asset)
}

private func meshRenderPreviewController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func meshRenderPreviewDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try meshRenderPreviewTriangleMesh(identity: "mesh.render-preview")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: GeometryRepresentationSet(
                representations: [
                    "representation.render-preview": GeometryRepresentation(
                        id: "representation.render-preview",
                        source: .authoredMesh(asset.id)
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: "representation.render-preview",
                    presentation: "representation.render-preview"
                )
            )
        )
    )
    try document.validate()
    return document
}

private func meshRenderPreviewTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func meshRenderPreviewRequest(
    asset: AuthoredMeshAsset,
    snapshot: ProjectViewSnapshot,
    z: Double
) throws -> ProjectMeshEditRequest {
    let vertexID = asset.source.vertexIDs[0]
    let plan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("mesh-render-preview-position"),
                operation: .primitive(
                    .setVertexPositions([
                        try MeshVertexPositionEdit(
                            vertexID: vertexID,
                            position: GeometryPoint3D(x: 0, y: 0, z: z)
                        ),
                    ])
                )
            ),
        ]
    )
    return ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: snapshot.authorityCoordinate,
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity
        ),
        plan: plan,
        snapshot: snapshot,
        name: "mesh.render-preview"
    )
}

private final class MeshRenderPreviewGate: Sendable {
    private struct State {
        var didStart = false
        var isReleased = false
    }

    private let state = Mutex(State())

    func markStarted() {
        state.withLock { $0.didStart = true }
    }

    func waitUntilStarted() async throws {
        for _ in 0..<2_000 {
            try Task.checkCancellation()
            if state.withLock({ $0.didStart }) {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw MeshRenderPreviewTestError.builderDidNotStart
    }

    func waitUntilReleased() {
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private struct BlockingMeshRenderPreviewBuilder:
    ProjectPreviewRenderPayloadBuilding,
    Sendable
{
    let gate: MeshRenderPreviewGate

    func build(
        from payload: ProjectSourcePreviewRenderPayload
    ) throws -> ProjectPreviewRenderPayload {
        gate.markStarted()
        gate.waitUntilReleased()
        return try ProjectViewSnapshotBuilder().build(from: payload)
    }
}

private final class MeshRenderPreviewEvaluationProbe: Sendable {
    private let count = Mutex(0)

    var evaluationCount: Int {
        count.withLock { $0 }
    }

    func recordEvaluation() {
        count.withLock { $0 += 1 }
    }
}

private struct MeshRenderPreviewEvaluatorPreparer: ProjectEvaluatorPreparing {
    let probe: MeshRenderPreviewEvaluationProbe
    private let base = DefaultDesignDocumentProjectEvaluatorFactory()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        let evaluator = try base.makeEvaluator(
            for: document,
            reusing: currentEvaluation
        )
        return MeshRenderPreviewEvaluator(base: evaluator, probe: probe)
    }
}

private struct MeshRenderPreviewEvaluator: ProjectEvaluating {
    let base: any ProjectEvaluating
    let probe: MeshRenderPreviewEvaluationProbe

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        probe.recordEvaluation()
        return try base.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private enum MeshRenderPreviewTestError: Error {
    case builderDidNotStart
}
