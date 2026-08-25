import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaProjectModel
import Testing
@testable import RupaCore
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func authoredMeshVertexEditPreservesAuthorityAndSharesUnchangedStorage() throws {
    let source = try largeEditableMeshSource(identity: "mesh.vertex-edit", vertexCount: 6_000)
    let fixture = try meshOnlyDocument(source: source)
    let target = AuthoredMeshEditTarget(
        sceneNodeID: fixture.sceneNodeID,
        representationID: fixture.representationID,
        sourceID: source.identity,
        expectedSourceIdentity: fixture.asset.contentIdentity
    )
    let replacement = GeometryPoint3D(x: 40, y: 50, z: 60)

    let application = try DefaultGeometrySourceCommandApplier().apply(
        .editAuthoredMesh(
            .setVertexPosition(
                target: target,
                vertexID: source.vertexIDs[0],
                position: replacement
            )
        ),
        to: fixture.document
    )
    let editedAsset = try #require(application.document.authoredMeshAssets[source.identity])
    guard case .authoredMeshEdit(let result) = application.result else {
        Issue.record("Expected an Authored Mesh edit result.")
        return
    }

    #expect(result.didMutate)
    #expect(result.previousSourceIdentity == fixture.asset.contentIdentity)
    #expect(result.sourceIdentity == editedAsset.contentIdentity)
    #expect(result.sourceIdentity != result.previousSourceIdentity)
    #expect(result.copyTelemetry.didCopy)
    #expect(
        result.copyTelemetry.copiedBytes
            < UInt64(source.vertexPositions.count * MemoryLayout<GeometryPoint3D>.stride)
    )
    #expect(try editedAsset.source.position(of: source.vertexIDs[0]) == replacement)
    #expect(try source.position(of: source.vertexIDs[0]) != replacement)
    #expect(editedAsset.provenance == fixture.asset.provenance)
    expectUnchangedMeshStorageShared(source, editedAsset.source)
    #expect(
        editedAsset.source.vertexPositions.storage.chunkIdentities.dropFirst()
            == source.vertexPositions.storage.chunkIdentities.dropFirst()
    )
    #expect(
        application.document.productMetadata.sceneNodes[fixture.sceneNodeID]?
            .object?.geometryRepresentations
            == fixture.document.productMetadata.sceneNodes[fixture.sceneNodeID]?
                .object?.geometryRepresentations
    )
}

@Test(.timeLimit(.minutes(1)))
func authoredMeshNoOpPreservesContentAndEveryBufferIdentity() throws {
    let source = try editableQuadSource(identity: "mesh.no-op")
    let fixture = try meshOnlyDocument(source: source)
    let originalPosition = try source.position(of: source.vertexIDs[0])
    let command = GeometrySourceCommand.editAuthoredMesh(
        .setVertexPosition(
            target: AuthoredMeshEditTarget(
                sceneNodeID: fixture.sceneNodeID,
                representationID: fixture.representationID,
                sourceID: source.identity,
                expectedSourceIdentity: fixture.asset.contentIdentity
            ),
            vertexID: source.vertexIDs[0],
            position: originalPosition
        )
    )

    let application = try DefaultGeometrySourceCommandApplier().apply(
        command,
        to: fixture.document
    )
    let retained = try #require(application.document.authoredMeshAssets[source.identity])

    #expect(!application.result.didMutate)
    #expect(!application.result.copyTelemetry.didCopy)
    #expect(retained.contentIdentity == fixture.asset.contentIdentity)
    expectAllMeshStorageShared(source, retained.source)
}

@Test(.timeLimit(.minutes(1)))
func authoredMeshEditRejectsStaleSourceIdentityWithoutMutation() throws {
    let source = try editableQuadSource(identity: "mesh.stale")
    let fixture = try meshOnlyDocument(source: source)
    let target = AuthoredMeshEditTarget(
        sceneNodeID: fixture.sceneNodeID,
        representationID: fixture.representationID,
        sourceID: source.identity,
        expectedSourceIdentity: fixture.asset.contentIdentity
    )
    let applier = DefaultGeometrySourceCommandApplier()
    let first = try applier.apply(
        .editAuthoredMesh(
            .setVertexPosition(
                target: target,
                vertexID: source.vertexIDs[0],
                position: GeometryPoint3D(x: 0, y: 0, z: 1)
            )
        ),
        to: fixture.document
    )
    let publishedIdentity = first.document.authoredMeshAssets[source.identity]?.contentIdentity
    var error: EditorError?

    do {
        _ = try applier.apply(
            .editAuthoredMesh(
                .setVertexPosition(
                    target: target,
                    vertexID: source.vertexIDs[1],
                    position: GeometryPoint3D(x: 1, y: 0, z: 2)
                )
            ),
            to: first.document
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .sourceIdentityMismatch)
    #expect(first.document.authoredMeshAssets[source.identity]?.contentIdentity == publishedIdentity)
    #expect(try first.document.authoredMeshAssets[source.identity]?.source.position(of: source.vertexIDs[1]) == source.vertexPositions[1])
}

@Test(.timeLimit(.minutes(1)))
func authoredMeshFaceEditsPreservePersistentIdentityAndVertexStorage() throws {
    let source = try editableQuadSource(identity: "mesh.face-edit")
    let fixture = try meshOnlyDocument(source: source)
    let applier = DefaultGeometrySourceCommandApplier()
    let added = try applier.apply(
        .editAuthoredMesh(
            .addFace(
                target: AuthoredMeshEditTarget(
                    sceneNodeID: fixture.sceneNodeID,
                    representationID: fixture.representationID,
                    sourceID: source.identity,
                    expectedSourceIdentity: fixture.asset.contentIdentity
                ),
                vertexIDs: [source.vertexIDs[0], source.vertexIDs[2], source.vertexIDs[3]]
            )
        ),
        to: fixture.document
    )
    let addedAsset = try #require(added.document.authoredMeshAssets[source.identity])
    guard case .authoredMeshEdit(let addedResult) = added.result else {
        Issue.record("Expected an Authored Mesh edit result.")
        return
    }
    let addedFaceID = try #require(addedResult.addedFaceID)

    #expect(addedAsset.source.faceIDs.contains(source.faceIDs[0]))
    #expect(addedAsset.source.faceIDs.contains(addedFaceID))
    #expect(
        addedAsset.source.vertexPositions.storage.chunkIdentities
            == source.vertexPositions.storage.chunkIdentities
    )
    #expect(addedAsset.provenance == fixture.asset.provenance)

    let deleted = try applier.apply(
        .editAuthoredMesh(
            .deleteFace(
                target: AuthoredMeshEditTarget(
                    sceneNodeID: fixture.sceneNodeID,
                    representationID: fixture.representationID,
                    sourceID: source.identity,
                    expectedSourceIdentity: addedAsset.contentIdentity
                ),
                faceID: source.faceIDs[0]
            )
        ),
        to: added.document
    )
    let deletedAsset = try #require(deleted.document.authoredMeshAssets[source.identity])

    #expect(!deletedAsset.source.faceIDs.contains(source.faceIDs[0]))
    #expect(deletedAsset.source.faceIDs.contains(addedFaceID))
    #expect(deletedAsset.provenance == fixture.asset.provenance)
}

@Test(.timeLimit(.minutes(1)))
func authoredMeshTopologyEditRejectsAttributeRemappingWithoutMutation() throws {
    let source = try attributedTriangleSource(identity: "mesh.attributes")
    let fixture = try meshOnlyDocument(source: source)
    var error: MeshSourceError?

    do {
        _ = try DefaultGeometrySourceCommandApplier().apply(
            .editAuthoredMesh(
                .deleteFace(
                    target: AuthoredMeshEditTarget(
                        sceneNodeID: fixture.sceneNodeID,
                        representationID: fixture.representationID,
                        sourceID: source.identity,
                        expectedSourceIdentity: fixture.asset.contentIdentity
                    ),
                    faceID: source.faceIDs[0]
                )
            ),
            to: fixture.document
        )
    } catch let caught as MeshSourceError {
        error = caught
    }

    #expect(error?.code == .unsupportedOperation)
    #expect(fixture.document.authoredMeshAssets[source.identity] == fixture.asset)
}

@Test(.timeLimit(.minutes(1)))
func authoredMeshEditRejectsMismatchedObjectRepresentationAndSource() throws {
    let source = try editableQuadSource(identity: "mesh.target")
    let fixture = try meshOnlyDocument(source: source)
    let otherSourceID: GeometrySourceID = "mesh.other"
    let target = AuthoredMeshEditTarget(
        sceneNodeID: fixture.sceneNodeID,
        representationID: fixture.representationID,
        sourceID: otherSourceID,
        expectedSourceIdentity: fixture.asset.contentIdentity
    )
    var error: EditorError?

    do {
        _ = try DefaultGeometrySourceCommandApplier().apply(
            .editAuthoredMesh(
                .setVertexPosition(
                    target: target,
                    vertexID: source.vertexIDs[0],
                    position: GeometryPoint3D(x: 0, y: 0, z: 1)
                )
            ),
            to: fixture.document
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .commandInvalid)
    #expect(fixture.document.authoredMeshAssets[source.identity] == fixture.asset)
}

@Test(.timeLimit(.minutes(1)))
func geometrySourceCommandsRejectMissingObjectAndRepresentationReferences() throws {
    let source = try editableQuadSource(identity: "mesh.missing-references")
    let fixture = try meshOnlyDocument(source: source)
    let applier = DefaultGeometrySourceCommandApplier()
    var missingObjectError: EditorError?
    var missingRepresentationError: EditorError?
    var missingSelectionError: EditorError?

    do {
        _ = try applier.apply(
            .editAuthoredMesh(
                .setVertexPosition(
                    target: AuthoredMeshEditTarget(
                        sceneNodeID: SceneNodeID(),
                        representationID: fixture.representationID,
                        sourceID: source.identity,
                        expectedSourceIdentity: fixture.asset.contentIdentity
                    ),
                    vertexID: source.vertexIDs[0],
                    position: GeometryPoint3D(x: 0, y: 0, z: 1)
                )
            ),
            to: fixture.document
        )
    } catch let caught as EditorError {
        missingObjectError = caught
    }
    do {
        _ = try applier.apply(
            .editAuthoredMesh(
                .setVertexPosition(
                    target: AuthoredMeshEditTarget(
                        sceneNodeID: fixture.sceneNodeID,
                        representationID: "representation.missing",
                        sourceID: source.identity,
                        expectedSourceIdentity: fixture.asset.contentIdentity
                    ),
                    vertexID: source.vertexIDs[0],
                    position: GeometryPoint3D(x: 0, y: 0, z: 1)
                )
            ),
            to: fixture.document
        )
    } catch let caught as EditorError {
        missingRepresentationError = caught
    }
    do {
        _ = try applier.apply(
            .selectRepresentation(
                GeometryRepresentationSelectionCommand(
                    sceneNodeID: fixture.sceneNodeID,
                    purpose: .presentation,
                    representationID: "representation.missing"
                )
            ),
            to: fixture.document
        )
    } catch let caught as EditorError {
        missingSelectionError = caught
    }

    #expect(missingObjectError?.code == .referenceUnresolved)
    #expect(missingRepresentationError?.code == .referenceUnresolved)
    #expect(missingSelectionError?.code == .referenceUnresolved)
    #expect(fixture.document.authoredMeshAssets[source.identity] == fixture.asset)
}

@Test(.timeLimit(.minutes(1)))
func presentationSelectionChangesUseContextWithoutChangingCADOrMeshAuthority() throws {
    var document = DesignDocument.empty(named: "Hybrid Selection")
    let cadFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(cadFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[sceneNodeID]?.object)
    let cadRepresentationID = try #require(object.geometryRepresentations.selection?.modeling)
    let source = try editableQuadSource(identity: "mesh.presentation-selection")
    let asset = try AuthoredMeshAsset(source: source, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.presentation-selection"
    object.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(source.identity)
    )
    document.productMetadata.sceneNodes[sceneNodeID]?.object = object
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.validate()

    let application = try DefaultGeometrySourceCommandApplier().apply(
        .selectRepresentation(
            GeometryRepresentationSelectionCommand(
                sceneNodeID: sceneNodeID,
                purpose: .presentation,
                representationID: meshRepresentationID
            )
        ),
        to: document
    )
    let selectedObject = try #require(
        application.document.productMetadata.sceneNodes[sceneNodeID]?.object
    )

    #expect(application.result.didMutate)
    #expect(selectedObject.geometryRepresentations.selection?.modeling == cadRepresentationID)
    #expect(selectedObject.geometryRepresentations.selection?.presentation == meshRepresentationID)
    #expect(application.document.productMetadata.sceneNodes[sceneNodeID]?.reference == .body(cadFeatureID))
    #expect(
        LiveDocumentEvaluationIdentity(document: application.document.cadDocument)
            == LiveDocumentEvaluationIdentity(document: document.cadDocument)
    )
    #expect(application.document.authoredMeshAssets == document.authoredMeshAssets)

    let noOp = try DefaultGeometrySourceCommandApplier().apply(
        .selectRepresentation(
            GeometryRepresentationSelectionCommand(
                sceneNodeID: sceneNodeID,
                purpose: .presentation,
                representationID: meshRepresentationID
            )
        ),
        to: application.document
    )
    #expect(!noOp.result.didMutate)
}

@Test(.timeLimit(.minutes(1)))
func editorSessionPublishesAuthoredMeshEditWithGenerationRevisionAndUndoHistory() throws {
    let source = try editableQuadSource(identity: "mesh.session-edit")
    let fixture = try meshOnlyDocument(source: source)
    let session = EditorSession(document: fixture.document)
    let replacement = GeometryPoint3D(x: 0, y: 0, z: 2)

    let result = try session.execute(
        .editAuthoredMesh(
            .setVertexPosition(
                target: AuthoredMeshEditTarget(
                    sceneNodeID: fixture.sceneNodeID,
                    representationID: fixture.representationID,
                    sourceID: source.identity,
                    expectedSourceIdentity: fixture.asset.contentIdentity
                ),
                vertexID: source.vertexIDs[0],
                position: replacement
            )
        ),
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )

    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.transactionRevision == DocumentTransactionRevision(1))
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(
        try session.document.authoredMeshAssets[source.identity]?
            .source.position(of: source.vertexIDs[0]) == replacement
    )

    _ = try session.undo(expectedTransactionRevision: DocumentTransactionRevision(1))

    #expect(session.generation == DocumentGeneration(2))
    #expect(session.transactionRevision == DocumentTransactionRevision(2))
    #expect(
        session.document.authoredMeshAssets[source.identity]?.contentIdentity
            == fixture.asset.contentIdentity
    )
}

@Test(.timeLimit(.minutes(1)))
func editorSessionAuthoredMeshNoOpDoesNotAdvanceGenerationOrRevision() throws {
    let source = try editableQuadSource(identity: "mesh.session-no-op")
    let fixture = try meshOnlyDocument(source: source)
    let session = EditorSession(document: fixture.document)

    let result = try session.execute(
        .editAuthoredMesh(
            .setVertexPosition(
                target: AuthoredMeshEditTarget(
                    sceneNodeID: fixture.sceneNodeID,
                    representationID: fixture.representationID,
                    sourceID: source.identity,
                    expectedSourceIdentity: fixture.asset.contentIdentity
                ),
                vertexID: source.vertexIDs[0],
                position: try source.position(of: source.vertexIDs[0])
            )
        ),
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )

    #expect(!result.didMutate)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.transactionRevision == DocumentTransactionRevision(0))
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(
        session.document.authoredMeshAssets[source.identity]?.contentIdentity
            == fixture.asset.contentIdentity
    )
}

@Test(.timeLimit(.minutes(1)))
func makeEditablePromotesModelingCADSnapshotWithoutCopyingMeshStorage() throws {
    let fixture = try makeEditableCADFixture()
    let application = try DefaultGeometrySourceCommandApplier().apply(
        .makeCADRepresentationEditable(fixture.command),
        to: fixture.document
    )
    let asset = try #require(
        application.document.authoredMeshAssets[fixture.command.authoredMeshSourceID]
    )
    let object = try #require(
        application.document.productMetadata.sceneNodes[fixture.sceneNodeID]?.object
    )
    let selection = try #require(object.geometryRepresentations.selection)
    guard case .makeEditable(let result) = application.result else {
        Issue.record("Expected a Make Editable result.")
        return
    }

    #expect(application.result.didMutate)
    #expect(result.copyTelemetry == fixture.command.evaluationCopyTelemetry)
    #expect(selection.modeling == fixture.cadRepresentationID)
    #expect(selection.presentation == fixture.command.authoredMeshRepresentationID)
    #expect(
        object.geometryRepresentations
            .representations[fixture.cadRepresentationID]?.source
            == fixture.cadReference
    )
    #expect(
        object.geometryRepresentations
            .representations[fixture.command.authoredMeshRepresentationID]?.source
            == .authoredMesh(fixture.command.authoredMeshSourceID)
    )
    #expect(
        asset.provenance == .derivedFromCAD(
            representationID: fixture.cadRepresentationID,
            sourceIdentity: fixture.command.sourceIdentity
        )
    )
    #expect(asset.source.identity == fixture.command.authoredMeshSourceID)
    expectAllMeshStorageShared(fixture.command.evaluatedMesh, asset.source)
    #expect(
        application.document.productMetadata.sceneNodes[fixture.sceneNodeID]?.reference
            == .body(fixture.bodyFeatureID)
    )
    #expect(
        try application.document.cadDocument.sourceFingerprint(tolerance: .standard)
            == fixture.document.cadDocument.sourceFingerprint(tolerance: .standard)
    )
}

@Test(.timeLimit(.minutes(1)))
func makeEditableCanRetainCADPresentationSelection() throws {
    let fixture = try makeEditableCADFixture(switchesPresentationSelection: false)
    let application = try DefaultGeometrySourceCommandApplier().apply(
        .makeCADRepresentationEditable(fixture.command),
        to: fixture.document
    )
    let object = try #require(
        application.document.productMetadata.sceneNodes[fixture.sceneNodeID]?.object
    )

    #expect(object.geometryRepresentations.selection?.modeling == fixture.cadRepresentationID)
    #expect(object.geometryRepresentations.selection?.presentation == fixture.cadRepresentationID)
    #expect(
        application.document.authoredMeshAssets[fixture.command.authoredMeshSourceID] != nil
    )
}

@Test(.timeLimit(.minutes(1)))
func makeEditableRejectsWrongPurposeMismatchedRepresentationAndDuplicateIdentity() throws {
    let fixture = try makeEditableCADFixture()
    var wrongPurposeError: EditorError?
    do {
        _ = try makeEditableCommand(
            fixture: fixture,
            snapshotID: EvaluationSnapshotID(
                projectID: fixture.document.projectID,
                purpose: .presentation,
                sourceRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as EditorError {
        wrongPurposeError = error
    }
    #expect(wrongPurposeError?.code == .commandInvalid)

    let mismatched = try makeEditableCommand(
        fixture: fixture,
        sourceRepresentationID: "cad.missing"
    )
    var mismatchedError: EditorError?
    do {
        _ = try DefaultGeometrySourceCommandApplier().apply(
            .makeCADRepresentationEditable(mismatched),
            to: fixture.document
        )
    } catch let error as EditorError {
        mismatchedError = error
    }
    #expect(mismatchedError?.code == .referenceUnresolved)

    let first = try DefaultGeometrySourceCommandApplier().apply(
        .makeCADRepresentationEditable(fixture.command),
        to: fixture.document
    )
    var duplicateError: EditorError?
    do {
        _ = try DefaultGeometrySourceCommandApplier().apply(
            .makeCADRepresentationEditable(fixture.command),
            to: first.document
        )
    } catch let error as EditorError {
        duplicateError = error
    }
    #expect(duplicateError?.code == .commandInvalid)
}

@Test(.timeLimit(.minutes(1)))
func makeEditableCommandCodecPreservesBindingsAndRejectsInvalidPurpose() throws {
    let fixture = try makeEditableCADFixture()
    let encoded = try JSONEncoder().encode(fixture.command)
    let decoded = try JSONDecoder().decode(
        MakeCADRepresentationEditableCommand.self,
        from: encoded
    )
    #expect(decoded == fixture.command)

    var payload = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    var snapshot = try #require(
        payload["evaluationSnapshotID"] as? [String: Any]
    )
    snapshot["purpose"] = GeometryRepresentationPurpose.presentation.rawValue
    payload["evaluationSnapshotID"] = snapshot
    let invalid = try JSONSerialization.data(withJSONObject: payload)
    var error: EditorError?
    do {
        _ = try JSONDecoder().decode(
            MakeCADRepresentationEditableCommand.self,
            from: invalid
        )
    } catch let caught as EditorError {
        error = caught
    }
    #expect(error?.code == .commandInvalid)
}

@Test(.timeLimit(.minutes(1)))
func makeEditableRejectsChangedCADSourceWithoutMutation() throws {
    let fixture = try makeEditableCADFixture()
    var changedDocument = fixture.document
    try changedDocument.setExtrudeDistance(
        featureID: fixture.bodyFeatureID,
        distance: .length(2, .meter)
    )
    let changedFingerprint = try changedDocument.cadDocument.sourceFingerprint(
        tolerance: .standard
    )
    var error: EditorError?

    do {
        _ = try DefaultGeometrySourceCommandApplier().apply(
            .makeCADRepresentationEditable(fixture.command),
            to: changedDocument
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .sourceIdentityMismatch)
    #expect(changedDocument.authoredMeshAssets.isEmpty)
    #expect(
        try changedDocument.cadDocument.sourceFingerprint(tolerance: .standard)
            == changedFingerprint
    )
}

@Test(.timeLimit(.minutes(1)))
func editorSessionRejectsMakeEditableSnapshotFromStaleTransactionRevision() throws {
    let fixture = try makeEditableCADFixture(
        snapshotRevision: DocumentTransactionRevision(1)
    )
    let session = EditorSession(document: fixture.document)
    var error: EditorError?

    do {
        _ = try session.execute(
            .makeCADRepresentationEditable(fixture.command),
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .documentTransactionRevisionMismatch)
    #expect(session.transactionRevision == DocumentTransactionRevision(0))
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.authoredMeshAssets.isEmpty)
    #expect(session.commandStack.undoEntries.isEmpty)
}

private struct MakeEditableCADFixture {
    let document: DesignDocument
    let sceneNodeID: SceneNodeID
    let bodyFeatureID: FeatureID
    let cadRepresentationID: GeometryRepresentationID
    let cadReference: GeometrySourceReference
    let command: MakeCADRepresentationEditableCommand
}

private func makeEditableCADFixture(
    switchesPresentationSelection: Bool = true,
    snapshotRevision: DocumentTransactionRevision = DocumentTransactionRevision(0)
) throws -> MakeEditableCADFixture {
    var document = DesignDocument.empty(named: "Make Editable")
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    let object = try #require(document.productMetadata.sceneNodes[sceneNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let cadReference = try #require(
        object.geometryRepresentations.representations[cadRepresentationID]?.source
    )
    let evaluatedMesh = try editableQuadSource(identity: "cad.evaluation.body")
    var telemetry = GeometryCopyTelemetry()
    try telemetry.record(reason: .bufferMaterialization, copiedBytes: 256)
    let command = try MakeCADRepresentationEditableCommand(
        sceneNodeID: sceneNodeID,
        sourceRepresentationID: cadRepresentationID,
        sourceReference: cadReference,
        evaluationSnapshotID: EvaluationSnapshotID(
            projectID: document.projectID,
            purpose: .modeling,
            sourceRevision: snapshotRevision
        ),
        sourceIdentity: CADSourceContentIdentityService().identity(for: document),
        evaluatedMesh: evaluatedMesh,
        evaluationCopyTelemetry: telemetry,
        authoredMeshSourceID: "mesh.editable.body",
        authoredMeshRepresentationID: "representation.editable.body",
        switchesPresentationSelection: switchesPresentationSelection
    )
    return MakeEditableCADFixture(
        document: document,
        sceneNodeID: sceneNodeID,
        bodyFeatureID: bodyFeatureID,
        cadRepresentationID: cadRepresentationID,
        cadReference: cadReference,
        command: command
    )
}

private func makeEditableCommand(
    fixture: MakeEditableCADFixture,
    sourceRepresentationID: GeometryRepresentationID? = nil,
    snapshotID: EvaluationSnapshotID? = nil
) throws -> MakeCADRepresentationEditableCommand {
    try MakeCADRepresentationEditableCommand(
        sceneNodeID: fixture.sceneNodeID,
        sourceRepresentationID: sourceRepresentationID ?? fixture.cadRepresentationID,
        sourceReference: fixture.cadReference,
        evaluationSnapshotID: snapshotID ?? fixture.command.evaluationSnapshotID,
        sourceIdentity: fixture.command.sourceIdentity,
        evaluatedMesh: fixture.command.evaluatedMesh,
        evaluationCopyTelemetry: fixture.command.evaluationCopyTelemetry,
        authoredMeshSourceID: fixture.command.authoredMeshSourceID,
        authoredMeshRepresentationID: fixture.command.authoredMeshRepresentationID,
        switchesPresentationSelection: fixture.command.switchesPresentationSelection
    )
}

private struct MeshSourceCommandFixture {
    let document: DesignDocument
    let asset: AuthoredMeshAsset
    let sceneNodeID: SceneNodeID
    let representationID: GeometryRepresentationID
}

private func meshOnlyDocument(source: MeshSource) throws -> MeshSourceCommandFixture {
    let asset = try AuthoredMeshAsset(
        source: source,
        provenance: .imported(
            try ContentIdentity(
                domain: "rupa.import-source",
                fingerprint: ContentFingerprint(
                    algorithm: "import-revision",
                    value: "fixture-1"
                )
            )
        )
    )
    let representationID = GeometryRepresentationID(
        rawValue: "representation.\(source.identity.rawValue)"
    )
    var document = DesignDocument.empty(named: "Mesh Source Command")
    document.authoredMeshAssets[asset.id] = asset
    let sceneNodeID = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Editable Mesh",
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
        )
    )
    _ = try document.validate()
    return MeshSourceCommandFixture(
        document: document,
        asset: asset,
        sceneNodeID: sceneNodeID,
        representationID: representationID
    )
}

private func editableQuadSource(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    _ = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func largeEditableMeshSource(
    identity: GeometrySourceID,
    vertexCount: Int
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    try builder.reserveCapacity(vertexCount: vertexCount, faceCount: 1, cornerCount: 3)
    var vertexIDs: [MeshVertexID] = []
    vertexIDs.reserveCapacity(vertexCount)
    for index in 0..<vertexCount {
        vertexIDs.append(
            try builder.addVertex(
                GeometryPoint3D(x: Double(index), y: 0, z: 0)
            )
        )
    }
    _ = try builder.addFace(vertexIDs: Array(vertexIDs.prefix(3)))
    return try builder.build()
}

private func attributedTriangleSource(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "material.index",
                name: "Material Index",
                domain: .face,
                valueType: .int32,
                interpolation: .constant
            ),
            values: .int32(GeometryBuffer([Int32(1)]))
        )
    )
    return try builder.build()
}

private func expectUnchangedMeshStorageShared(
    _ original: MeshSource,
    _ edited: MeshSource
) {
    #expect(original.vertexIDs.storage.chunkIdentities == edited.vertexIDs.storage.chunkIdentities)
    #expect(original.edgeIDs.storage.chunkIdentities == edited.edgeIDs.storage.chunkIdentities)
    #expect(original.edgeEndpoints.storage.chunkIdentities == edited.edgeEndpoints.storage.chunkIdentities)
    #expect(original.faceIDs.storage.chunkIdentities == edited.faceIDs.storage.chunkIdentities)
    #expect(original.faceCornerRanges.storage.chunkIdentities == edited.faceCornerRanges.storage.chunkIdentities)
    #expect(original.cornerIDs.storage.chunkIdentities == edited.cornerIDs.storage.chunkIdentities)
    #expect(original.cornerVertexIDs.storage.chunkIdentities == edited.cornerVertexIDs.storage.chunkIdentities)
    #expect(original.cornerEdgeIDs.storage.chunkIdentities == edited.cornerEdgeIDs.storage.chunkIdentities)
}

private func expectAllMeshStorageShared(
    _ original: MeshSource,
    _ edited: MeshSource
) {
    expectUnchangedMeshStorageShared(original, edited)
    #expect(
        original.vertexPositions.storage.chunkIdentities
            == edited.vertexPositions.storage.chunkIdentities
    )
}
