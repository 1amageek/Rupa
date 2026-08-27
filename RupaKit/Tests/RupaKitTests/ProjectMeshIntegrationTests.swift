import Foundation
import RupaCore
import RupaCoreTypes
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func projectMeshMeshOnlySupportsCompleteAgentWorkflow() async throws {
    try await withProjectMeshIntegrationTemporaryDirectory { directory in
        let sourceDocument = try projectMeshIntegrationMeshOnlyDocument(named: "Mesh Only")
        let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
        let controller = try projectMeshIntegrationController(document: sourceDocument)
        let workspace = await ProjectWorkspace(project: controller)
        let initial = try await workspace.evaluate()
        let initialSource = try #require(initial.document.document.authoredMeshAssets[sourceAsset.id])

        let catalog = try await workspace.catalog(from: initial)
        let catalogSource = try #require(catalog.source(for: sourceAsset.id))
        let page = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: catalogSource.handle,
                domain: .vertex,
                limits: ProjectMeshReadLimits(maxPageRecords: 1)
            ),
            from: initial
        )
        let neighborhood = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: catalogSource.handle,
                origin: .vertex(sourceAsset.source.vertexIDs[0]),
                depth: 1,
                limits: ProjectMeshReadLimits(maxOutputRecords: 4)
            ),
            from: initial
        )
        #expect(page.records.count == 1)
        #expect(neighborhood.records.isEmpty == false)
        #expect(catalogSource.references.count == 1)

        let plan = try projectMeshIntegrationExtrudeTranslatePlan(
            faceID: sourceAsset.source.faceIDs[0]
        )
        let expectedExecution = try DefaultMeshEditPlanExecutor().execute(
            plan: plan,
            source: initialSource.source
        )
        let request = ProjectMeshEditRequest(
            handle: catalogSource.handle,
            plan: plan,
            snapshot: initial,
            name: "integration.mesh-only.extrude-translate"
        )
        let preview = try await workspace.preview(request)
        #expect(preview.didMutate)
        #expect(preview.receipt.stepReceipts.map(\.stepID) == [
            MeshEditStepID("extrude"),
            MeshEditStepID("translate-created"),
        ])
        #expect(preview.receipt.stepReceipts[1].outputs[.affectedVertices]?.count == 3)
        #expect(preview.receipt.telemetry == expectedExecution.receipt.telemetry)
        #expect(preview.copyTelemetry == expectedExecution.receipt.telemetry)
        #expect(preview.copyTelemetry.didCopy)
        #expect(preview.copyTelemetry.events.allSatisfy { $0.reason == .sourceEdit })
        #expect((try await controller.currentState()).document.authoredMeshAssets[sourceAsset.id] == initialSource)

        let committed = try await workspace.commit(request)
        let committedAsset = try #require(
            committed.view.document.document.authoredMeshAssets[sourceAsset.id]
        )
        #expect(committed.receipt.stepReceipts.count == 2)
        #expect(committed.receipt.stepReceipts[0].outputs[.createdVertices]?.count == 3)
        #expect(committed.receipt.telemetry == expectedExecution.receipt.telemetry)
        #expect(committed.copyTelemetry == expectedExecution.receipt.telemetry)
        #expect(committed.receipt.didChange)
        #expect(committedAsset.source.vertexIDs.count == 6)
        #expect(committedAsset.source.faceIDs.count == 4)
        #expect(try committedAsset.source.position(of: MeshVertexID(3))
            == GeometryPoint3D(x: 1, y: 0, z: 1))
        #expect(committed.view.viewport.items.count == 1)
        #expect(committed.view.viewport.items[0].reference == .authoredMesh(sourceAsset.id))
        #expect(committed.view.viewport.items[0].copyTelemetry.didCopy == false)

        let presentation = try await workspace.evaluate(from: committed.view)
        let evaluated = try await controller.currentEvaluation()
        #expect(presentation.viewport.items[0].reference == .authoredMesh(sourceAsset.id))
        #expect(evaluated.id.purpose == .presentation)
        #expect(evaluated.occurrences.values.first?.reference == .authoredMesh(sourceAsset.id))
        #expect(evaluated.copyTelemetry.didCopy == false)
        #expect(evaluated.occurrences.values.first?.copyTelemetry.didCopy == false)

        let undone = try await workspace.undo(from: presentation)
        let restored = try #require(
            undone.document.document.authoredMeshAssets[sourceAsset.id]
        )
        #expect(restored == sourceAsset)
        #expect(undone.canRedo)
        let redone = try await workspace.redo(from: undone)
        let redoneAsset = try #require(
            redone.document.document.authoredMeshAssets[sourceAsset.id]
        )
        #expect(redoneAsset == committedAsset)
        #expect(redone.canUndo)

        let firstSaveURL = directory.appendingPathComponent("mesh-only-first.rupa")
        let secondSaveURL = directory.appendingPathComponent("mesh-only-second.rupa")
        let saved = try await workspace.save(to: firstSaveURL)
        _ = try await workspace.save(to: secondSaveURL)
        #expect(saved.isDirty == false)
        #expect(try Data(contentsOf: firstSaveURL) == Data(contentsOf: secondSaveURL))

        let loaded = try await workspace.load(from: firstSaveURL)
        let loadedAsset = try #require(
            loaded.document.document.authoredMeshAssets[sourceAsset.id]
        )
        let loadedViewportMesh = try #require(loaded.viewport.items.first?.mesh)
        let loadedEvaluation = try await controller.currentEvaluation()
        let loadedEvaluationMesh = try #require(loadedEvaluation.occurrences.values.first?.mesh)
        #expect(loaded.document.document.hasAuthoritativeCADSource == false)
        #expect(loadedAsset == committedAsset)
        #expect(loadedViewportMesh == loadedAsset.source)
        #expect(loadedEvaluationMesh == loadedAsset.source)
        #expect(loadedViewportMesh.vertexPositions.storage.chunkIdentities
            == loadedAsset.source.vertexPositions.storage.chunkIdentities)
        #expect(loadedViewportMesh.cornerVertexIDs.storage.chunkIdentities
            == loadedAsset.source.cornerVertexIDs.storage.chunkIdentities)
        #expect(loadedEvaluationMesh.vertexPositions.storage.chunkIdentities
            == loadedAsset.source.vertexPositions.storage.chunkIdentities)
        #expect(loaded.viewport.copyTelemetry.didCopy == false)
        #expect(loadedViewportMesh.identity == loadedEvaluationMesh.identity)
        #expect(loadedEvaluation.id.purpose == .presentation)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCADAndSharedAuthoredMeshSupportsCompleteAgentWorkflow() async throws {
    try await withProjectMeshIntegrationTemporaryDirectory { directory in
        let sourceDocument = try projectMeshIntegrationCADAndSharedMeshDocument(named: "CAD and Mesh")
        let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
        let controller = try projectMeshIntegrationController(document: sourceDocument)
        let workspace = await ProjectWorkspace(project: controller)
        let initial = try await workspace.evaluate()
        let catalog = try await workspace.catalog(from: initial)
        let catalogSource = try #require(catalog.source(for: sourceAsset.id))
        #expect(initial.document.document.hasAuthoritativeCADSource)
        #expect(catalogSource.references.count == 2)
        let cadBodyReference = try #require(catalogSource.references.first {
            $0.representationID == "representation.integration-shared"
        })
        let sharedMeshReference = try #require(catalogSource.references.first {
            $0.representationID == "representation.integration-shared-second"
        })
        #expect(cadBodyReference.selectedPurposes == [.presentation])
        #expect(sharedMeshReference.selectedPurposes == [.modeling, .presentation])
        #expect(initial.viewport.items.count == 2)
        #expect(initial.viewport.items.allSatisfy {
            $0.reference == .authoredMesh(sourceAsset.id)
        })

        let page = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: catalogSource.handle,
                domain: .face,
                limits: ProjectMeshReadLimits(maxPageRecords: 1)
            ),
            from: initial
        )
        let neighborhood = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: catalogSource.handle,
                origin: .face(sourceAsset.source.faceIDs[0]),
                depth: 1,
                limits: ProjectMeshReadLimits(maxOutputRecords: 4)
            ),
            from: initial
        )
        #expect(page.records.count == 1)
        #expect(neighborhood.records.isEmpty == false)

        let request = ProjectMeshEditRequest(
            handle: catalogSource.handle,
            plan: try projectMeshIntegrationExtrudeTranslatePlan(
                faceID: sourceAsset.source.faceIDs[0]
            ),
            snapshot: initial,
            name: "integration.cad-shared-mesh.extrude-translate"
        )
        let preview = try await workspace.preview(request)
        #expect(preview.receipt.stepReceipts.count == 2)
        #expect(preview.copyTelemetry.didCopy)
        let committed = try await workspace.commit(request)
        let committedAsset = try #require(
            committed.view.document.document.authoredMeshAssets[sourceAsset.id]
        )
        #expect(committed.receipt.didChange)
        #expect(committed.receipt.telemetry.didCopy)
        #expect(committed.view.viewport.items.count == 2)
        #expect(committed.view.viewport.items.allSatisfy {
            $0.reference == .authoredMesh(sourceAsset.id)
                && $0.mesh == committedAsset.source
        })

        let presentation = try await workspace.evaluate(from: committed.view)
        let evaluated = try await controller.currentEvaluation()
        #expect(presentation.viewport.items.count == 2)
        #expect(evaluated.id.purpose == .presentation)
        #expect(evaluated.occurrences.count == 2)
        #expect(evaluated.occurrences.values.allSatisfy {
            $0.reference == .authoredMesh(sourceAsset.id)
                && $0.mesh == committedAsset.source
                && $0.copyTelemetry.didCopy == false
        })

        let undone = try await workspace.undo(from: presentation)
        #expect(undone.document.document.hasAuthoritativeCADSource)
        #expect(try #require(undone.document.document.authoredMeshAssets[sourceAsset.id]) == sourceAsset)
        let redone = try await workspace.redo(from: undone)
        #expect(redone.document.document.hasAuthoritativeCADSource)
        #expect(try #require(redone.document.document.authoredMeshAssets[sourceAsset.id]) == committedAsset)
        #expect(redone.viewport.items.count == 2)

        let saveURL = directory.appendingPathComponent("cad-and-mesh.rupa")
        _ = try await workspace.save(to: saveURL)
        let loaded = try await workspace.load(from: saveURL)
        let loadedSource = try #require(
            loaded.document.document.authoredMeshAssets[sourceAsset.id]
        )
        let loadedCatalog = try await workspace.catalog(from: loaded)
        let loadedReferences = try #require(loadedCatalog.source(for: sourceAsset.id)).references
        #expect(loaded.document.document.hasAuthoritativeCADSource)
        #expect(loaded.document.document.cadDocument.metadata.name == "CAD and Mesh")
        #expect(loadedReferences.count == 2)
        #expect(loaded.viewport.items.count == 2)
        #expect(loaded.viewport.items.allSatisfy {
            $0.reference == .authoredMesh(sourceAsset.id)
                && $0.mesh == loadedSource.source
        })
    }
}

@Test(.timeLimit(.minutes(1)))
func projectMeshValidPlanExecutionFailurePreservesControllerAndWorkspaceAggregate() async throws {
    let sourceDocument = try projectMeshIntegrationMeshOnlyDocument(named: "Execution Failure")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let controller = try projectMeshIntegrationController(document: sourceDocument)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let before = try await controller.currentState()
    let beforeView = try #require(await workspace.view)
    let structurallyValidPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("runtime-missing-vertex"),
                operation: .primitive(
                    .setVertexPositions([
                        try MeshVertexPositionEdit(
                            vertexID: MeshVertexID(99_999),
                            position: GeometryPoint3D(x: 0, y: 0, z: 1)
                        ),
                    ])
                )
            ),
        ]
    )
    let request = ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: projectMeshIntegrationCoordinate(from: initial),
            sourceID: sourceAsset.id,
            contentIdentity: sourceAsset.contentIdentity
        ),
        plan: structurallyValidPlan,
        snapshot: initial,
        name: "integration.runtime-failure"
    )

    var failure: ProjectMeshEditError?
    do {
        _ = try await workspace.commit(request)
    } catch let error as ProjectMeshEditError {
        failure = error
    }
    let after = try await controller.currentState()
    let afterView = try #require(await workspace.view)

    #expect(failure?.code == .invalidPlan)
    #expect(after.document.authoredMeshAssets == before.document.authoredMeshAssets)
    #expect(after.package.productSource == before.package.productSource)
    #expect(after.package.cadSource == before.package.cadSource)
    #expect(after.package.authoredMeshAssets == before.package.authoredMeshAssets)
    #expect(after.documentGeneration == before.documentGeneration)
    #expect(after.transactionRevision == before.transactionRevision)
    #expect(after.publicationSequence == before.publicationSequence)
    #expect(after.isDirty == before.isDirty)
    #expect(after.canUndo == before.canUndo)
    #expect(after.canRedo == before.canRedo)
    #expect(after.selection == before.selection)
    #expect(after.workspaceState.revision == before.workspaceState.revision)
    #expect(after.workspaceState.ruler == before.workspaceState.ruler)
    #expect(after.workspaceState.viewportGridSettings == before.workspaceState.viewportGridSettings)
    #expect(after.workspaceState.activeConstructionPlaneID == before.workspaceState.activeConstructionPlaneID)
    #expect(after.workspaceState.curveCurvatureDisplays == before.workspaceState.curveCurvatureDisplays)
    #expect(after.workspaceState.pointDisplays == before.workspaceState.pointDisplays)
    #expect(after.workspaceState.surfaceControlPointDisplays == before.workspaceState.surfaceControlPointDisplays)
    #expect(after.workspaceState.surfaceFrameDisplays == before.workspaceState.surfaceFrameDisplays)
    #expect(after.evaluationSnapshot == before.evaluationSnapshot)
    #expect(after.evaluation.id == before.evaluation.id)
    #expect(after.evaluation.occurrences.keys == before.evaluation.occurrences.keys)
    for occurrenceID in before.evaluation.occurrences.keys {
        #expect(after.evaluation.occurrences[occurrenceID]?.reference
            == before.evaluation.occurrences[occurrenceID]?.reference)
        #expect(after.evaluation.occurrences[occurrenceID]?.mesh.identity
            == before.evaluation.occurrences[occurrenceID]?.mesh.identity)
    }
    #expect(afterView.transactionRevision == beforeView.transactionRevision)
    #expect(afterView.publicationSequence == beforeView.publicationSequence)
    #expect(afterView.documentGeneration == beforeView.documentGeneration)
    #expect(afterView.viewport == beforeView.viewport)
}

private func projectMeshIntegrationController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func projectMeshIntegrationMeshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try projectMeshIntegrationTriangleMesh(identity: "mesh.integration-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.integration-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectMeshIntegrationRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func projectMeshIntegrationCADAndSharedMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let featureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(featureID)
    }?.key)
    var bodyObject = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(bodyObject.geometryRepresentations.selection?.modeling)
    let mesh = try projectMeshIntegrationTriangleMesh(identity: "mesh.integration-shared")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.integration-shared"
    document.authoredMeshAssets[asset.id] = asset
    bodyObject.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(asset.id)
    )
    bodyObject.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = bodyObject
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Shared Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectMeshIntegrationRepresentationSet(
                representationID: "representation.integration-shared-second",
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func projectMeshIntegrationRepresentationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(id: representationID, source: source),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func projectMeshIntegrationTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func projectMeshIntegrationExtrudeTranslatePlan(faceID: MeshFaceID) throws -> MeshEditPlan {
    let extrusion = MeshEditStep(
        id: MeshEditStepID("extrude"),
        operation: .extrudeFaces(
            .explicit(try MeshSelectionSet(elements: [.face(faceID)])),
            offset: GeometryVector3D(x: 0, y: 0, z: 1)
        )
    )
    let translate = MeshEditStep(
        id: MeshEditStepID("translate-created"),
        operation: .translateElements(
            .output(stepID: extrusion.id, role: .createdVertices),
            offset: GeometryVector3D(x: 1, y: 0, z: 0)
        )
    )
    return try MeshEditPlan(steps: [extrusion, translate])
}

private func projectMeshIntegrationCoordinate(from view: ProjectViewSnapshot) -> ProjectAuthorityCoordinate {
    ProjectAuthorityCoordinate(
        projectID: view.projectID,
        transactionRevision: view.transactionRevision,
        publicationSequence: view.publicationSequence
    )
}

private func withProjectMeshIntegrationTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-mesh-integration-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try await body(directory)
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            // The test result remains valid when cleanup is unavailable.
        }
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            // Preserve the behavioral failure rather than replacing it with cleanup noise.
        }
        throw primaryError
    }
}
