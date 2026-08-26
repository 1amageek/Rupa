import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaViewportScene
@testable import RupaGeometry
import Testing

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationAcceptsCADMeshAndMixedSelections() throws {
    let source = try presentationTriangleSource(identity: "mesh.presentation")
    let projectID = ProjectID(rawValue: "project.presentation")
    let meshReference = GeometrySourceReference.authoredMesh(source.identity)
    let cadReference = GeometrySourceReference.cad(
        sourceID: "cad.document",
        outputID: "cad.output"
    )
    let meshRepresentationID = GeometryRepresentationID(rawValue: "representation.mesh")
    let cadRepresentationID = GeometryRepresentationID(rawValue: "representation.cad")
    let meshDefinitionID = ObjectDefinitionID(rawValue: "object.mesh")
    let cadDefinitionID = ObjectDefinitionID(rawValue: "object.cad")
    let meshOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.mesh")
    let cadOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.cad")

    let meshDefinition = ObjectDefinition(
        id: meshDefinitionID,
        name: "Mesh",
        representations: presentationRepresentations(
            id: meshRepresentationID,
            reference: meshReference
        )
    )
    let cadDefinition = ObjectDefinition(
        id: cadDefinitionID,
        name: "CAD",
        representations: presentationRepresentations(
            id: cadRepresentationID,
            reference: cadReference
        )
    )
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Presentation",
        authoredMeshAssets: [
            source.identity: try AuthoredMeshAsset(source: source, provenance: .created),
        ],
        objectDefinitions: [
            meshDefinitionID: meshDefinition,
            cadDefinitionID: cadDefinition,
        ],
        occurrences: [
            meshOccurrenceID: SceneOccurrence(
                id: meshOccurrenceID,
                definitionID: meshDefinitionID
            ),
            cadOccurrenceID: SceneOccurrence(
                id: cadOccurrenceID,
                definitionID: cadDefinitionID
            ),
        ],
        rootOccurrenceIDs: [meshOccurrenceID, cadOccurrenceID]
    )
    let bounds = try source.bounds()
    let meshOccurrence = EvaluatedOccurrenceSnapshot(
        occurrenceID: meshOccurrenceID,
        definitionID: meshDefinitionID,
        representationID: meshRepresentationID,
        reference: meshReference,
        mesh: source,
        worldTransform: .identity,
        worldBounds: bounds
    )
    let cadOccurrence = EvaluatedOccurrenceSnapshot(
        occurrenceID: cadOccurrenceID,
        definitionID: cadDefinitionID,
        representationID: cadRepresentationID,
        reference: cadReference,
        mesh: source,
        worldTransform: .identity,
        worldBounds: bounds
    )
    let snapshotID = EvaluationSnapshotID(
        projectID: projectID,
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision()
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: snapshotID,
        projectID: projectID,
        occurrences: [
            meshOccurrenceID: meshOccurrence,
            cadOccurrenceID: cadOccurrence,
        ],
        copyTelemetry: GeometryCopyTelemetry()
    )

    let scene = try UniversalViewportSceneBuilder().build(
        from: snapshot,
        project: project
    )

    #expect(scene.items.map(\.occurrenceID) == [cadOccurrenceID, meshOccurrenceID])
    #expect(scene.items.map(\.representationID).contains(cadRepresentationID))
    #expect(scene.items.map(\.reference).contains(cadReference))
    #expect(scene.items.map(\.reference).contains(meshReference))
    #expect(scene.items.allSatisfy { $0.mesh.identity == source.identity })
    #expect(scene.copyTelemetry == snapshot.copyTelemetry)
    #expect(scene.items.allSatisfy { $0.copyTelemetry.didCopy == false })
    for occurrence in snapshot.occurrences.values {
        guard let item = scene.items.first(where: { $0.occurrenceID == occurrence.occurrenceID }) else {
            Issue.record("The scene did not preserve the evaluated occurrence identity.")
            continue
        }
        expectSharedGeometryBuffers(occurrence.mesh, item.mesh)
        expectSharedGeometryBuffers(source, occurrence.mesh)
    }
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsMissingSourceOccurrence() throws {
    let source = try presentationTriangleSource(identity: "mesh.missing-occurrence")
    let projectID = ProjectID(rawValue: "project.missing-occurrence")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.missing-source")
    let definitionID = ObjectDefinitionID(rawValue: "object.missing-source")
    let representationID = GeometryRepresentationID(rawValue: "representation.missing-source")
    let reference = GeometrySourceReference.cad(
        sourceID: "cad.document",
        outputID: "cad.output"
    )
    let definition = ObjectDefinition(
        id: definitionID,
        name: "Missing source occurrence",
        representations: presentationRepresentations(
            id: representationID,
            reference: reference
        )
    )
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Missing source occurrence",
        objectDefinitions: [definitionID: definition],
        occurrences: [:],
        rootOccurrenceIDs: []
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [occurrenceID: EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )],
        copyTelemetry: GeometryCopyTelemetry()
    )

    var error: UniversalViewportSceneError?
    do {
        _ = try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .occurrenceMismatch)
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsSourceEvaluatedDefinitionMismatch() throws {
    let source = try presentationTriangleSource(identity: "mesh.definition-mismatch")
    let projectID = ProjectID(rawValue: "project.definition-mismatch")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.definition-mismatch")
    let sourceDefinitionID = ObjectDefinitionID(rawValue: "object.source-definition")
    let evaluatedDefinitionID = ObjectDefinitionID(rawValue: "object.evaluated-definition")
    let representationID = GeometryRepresentationID(rawValue: "representation.definition-mismatch")
    let reference = GeometrySourceReference.cad(
        sourceID: "cad.document",
        outputID: "cad.output"
    )
    let sourceDefinition = ObjectDefinition(
        id: sourceDefinitionID,
        name: "Source definition",
        representations: presentationRepresentations(
            id: representationID,
            reference: reference
        )
    )
    let evaluatedDefinition = ObjectDefinition(
        id: evaluatedDefinitionID,
        name: "Evaluated definition",
        representations: presentationRepresentations(
            id: representationID,
            reference: reference
        )
    )
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Definition mismatch",
        objectDefinitions: [
            sourceDefinitionID: sourceDefinition,
            evaluatedDefinitionID: evaluatedDefinition,
        ],
        occurrences: [occurrenceID: SceneOccurrence(
            id: occurrenceID,
            definitionID: sourceDefinitionID
        )],
        rootOccurrenceIDs: [occurrenceID]
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [occurrenceID: EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: evaluatedDefinitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )],
        copyTelemetry: GeometryCopyTelemetry()
    )

    var error: UniversalViewportSceneError?
    do {
        _ = try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .occurrenceMismatch)
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsPresentationAuthorityMismatch() throws {
    let source = try presentationTriangleSource(identity: "mesh.authoritative")
    let declaredSource = try source.reidentified(as: "mesh.declared")
    let projectID = ProjectID(rawValue: "project.authority")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.authority")
    let definitionID = ObjectDefinitionID(rawValue: "object.authority")
    let presentationID = GeometryRepresentationID(rawValue: "representation.authority")
    let declaredReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.declared")
    )
    let actualReference = GeometrySourceReference.authoredMesh(source.identity)
    let definition = ObjectDefinition(
        id: definitionID,
        name: "Authority",
        representations: presentationRepresentations(
            id: presentationID,
            reference: declaredReference
        )
    )
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Authority",
        authoredMeshAssets: [
            source.identity: try AuthoredMeshAsset(source: source, provenance: .created),
            declaredSource.identity: try AuthoredMeshAsset(source: declaredSource, provenance: .created),
        ],
        objectDefinitions: [definitionID: definition],
        occurrences: [occurrenceID: SceneOccurrence(id: occurrenceID, definitionID: definitionID)],
        rootOccurrenceIDs: [occurrenceID]
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [occurrenceID: EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: presentationID,
            reference: actualReference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )],
        copyTelemetry: GeometryCopyTelemetry()
    )

    var error: UniversalViewportSceneError?
    do {
        _ = try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .sourceMismatch)
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsAuthoredMeshIdentityMismatch() throws {
    let source = try presentationTriangleSource(identity: "mesh.actual")
    let item = UniversalViewportSceneItem(
        id: SceneOccurrenceID(rawValue: "occurrence.identity"),
        definitionID: ObjectDefinitionID(rawValue: "object.identity"),
        displayName: "Identity",
        representationID: GeometryRepresentationID(rawValue: "representation.identity"),
        reference: .authoredMesh(GeometrySourceID(rawValue: "mesh.expected")),
        mesh: source,
        worldTransform: .identity,
        worldBounds: try source.bounds()
    )

    var error: UniversalViewportSceneError?
    do {
        try item.validate()
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .sourceIdentityMismatch)
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsProjectMismatch() throws {
    let source = try presentationTriangleSource(identity: "mesh.project-mismatch")
    let projectID = ProjectID(rawValue: "project.expected")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.project-mismatch")
    let definitionID = ObjectDefinitionID(rawValue: "object.project-mismatch")
    let representationID = GeometryRepresentationID(rawValue: "representation.project-mismatch")
    let reference = GeometrySourceReference.authoredMesh(source.identity)
    let definition = ObjectDefinition(
        id: definitionID,
        name: "Project mismatch",
        representations: presentationRepresentations(
            id: representationID,
            reference: reference
        )
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [occurrenceID: EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )],
        copyTelemetry: GeometryCopyTelemetry()
    )
    let mismatchedProject = try ProjectSourceModel(
        id: ProjectID(rawValue: "project.actual"),
        name: "Project mismatch",
        authoredMeshAssets: [source.identity: try AuthoredMeshAsset(source: source, provenance: .created)],
        objectDefinitions: [definitionID: definition],
        occurrences: [occurrenceID: SceneOccurrence(id: occurrenceID, definitionID: definitionID)],
        rootOccurrenceIDs: [occurrenceID]
    )

    var error: UniversalViewportSceneError?
    do {
        _ = try UniversalViewportSceneBuilder().build(
            from: snapshot,
            project: mismatchedProject
        )
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .projectMismatch)
}

@Test(.timeLimit(.minutes(1)))
func universalViewportPresentationRejectsNonPresentationPurpose() throws {
    let source = try presentationTriangleSource(identity: "mesh.purpose-mismatch")
    let projectID = ProjectID(rawValue: "project.purpose-mismatch")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.purpose-mismatch")
    let definitionID = ObjectDefinitionID(rawValue: "object.purpose-mismatch")
    let representationID = GeometryRepresentationID(rawValue: "representation.purpose-mismatch")
    let reference = GeometrySourceReference.authoredMesh(source.identity)
    let definition = ObjectDefinition(
        id: definitionID,
        name: "Purpose mismatch",
        representations: presentationRepresentations(
            id: representationID,
            reference: reference
        )
    )
    let project = try ProjectSourceModel(
        id: projectID,
        name: "Purpose mismatch",
        authoredMeshAssets: [source.identity: try AuthoredMeshAsset(source: source, provenance: .created)],
        objectDefinitions: [definitionID: definition],
        occurrences: [occurrenceID: SceneOccurrence(id: occurrenceID, definitionID: definitionID)],
        rootOccurrenceIDs: [occurrenceID]
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .modeling,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [occurrenceID: EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )],
        copyTelemetry: GeometryCopyTelemetry()
    )

    var error: UniversalViewportSceneError?
    do {
        _ = try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
    } catch let caught as UniversalViewportSceneError {
        error = caught
    }
    #expect(error?.code == .purposeMismatch)
}

private func presentationRepresentations(
    id: GeometryRepresentationID,
    reference: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [id: GeometryRepresentation(id: id, source: reference)],
        selection: GeometryRepresentationSelection(modeling: id, presentation: id)
    )
}

private func presentationTriangleSource(identity: String) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: identity))
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func expectSharedGeometryBuffers(_ expected: MeshSource, _ actual: MeshSource) {
    #expect(expected.vertexIDs.storage.chunkIdentities == actual.vertexIDs.storage.chunkIdentities)
    #expect(expected.vertexPositions.storage.chunkIdentities == actual.vertexPositions.storage.chunkIdentities)
    #expect(expected.edgeIDs.storage.chunkIdentities == actual.edgeIDs.storage.chunkIdentities)
    #expect(expected.edgeEndpoints.storage.chunkIdentities == actual.edgeEndpoints.storage.chunkIdentities)
    #expect(expected.faceIDs.storage.chunkIdentities == actual.faceIDs.storage.chunkIdentities)
    #expect(expected.faceCornerRanges.storage.chunkIdentities == actual.faceCornerRanges.storage.chunkIdentities)
    #expect(expected.cornerIDs.storage.chunkIdentities == actual.cornerIDs.storage.chunkIdentities)
    #expect(expected.cornerVertexIDs.storage.chunkIdentities == actual.cornerVertexIDs.storage.chunkIdentities)
    #expect(expected.cornerEdgeIDs.storage.chunkIdentities == actual.cornerEdgeIDs.storage.chunkIdentities)
}
