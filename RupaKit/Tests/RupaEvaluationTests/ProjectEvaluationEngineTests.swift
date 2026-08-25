import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import Synchronization
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func projectEvaluationProducesImmutableOccurrenceSnapshotsWithWorldBounds() throws {
    let mesh = try triangleSource()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let definition = objectDefinition(
        id: "triangle.definition",
        name: "Triangle",
        source: .authoredMesh(mesh.identity)
    )
    let root = SceneOccurrence(
        id: "triangle.root",
        definitionID: definition.id,
        localTransform: try translation(x: 2, y: 3, z: 0)
    )
    let project = try ProjectSourceModel(
        id: "project.evaluation",
        name: "Evaluation",
        authoredMeshAssets: [asset.id: asset],
        objectDefinitions: [definition.id: definition],
        occurrences: [root.id: root],
        rootOccurrenceIDs: [root.id]
    )

    let snapshot = try ProjectEvaluationEngine().evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision(7)
    )
    let evaluated = try #require(snapshot.occurrences[root.id])

    #expect(snapshot.id.sourceRevision == DocumentTransactionRevision(7))
    #expect(snapshot.id.purpose == .presentation)
    #expect(evaluated.representationID == definition.representations.selection?.presentation)
    #expect(evaluated.worldBounds.minimum == GeometryPoint3D(x: 2, y: 3, z: 0))
    #expect(evaluated.worldBounds.maximum == GeometryPoint3D(x: 3, y: 4, z: 0))
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationComposesParentAndChildTransforms() throws {
    let mesh = try triangleSource()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let definition = objectDefinition(
        id: "definition",
        name: "Triangle",
        source: .authoredMesh(mesh.identity)
    )
    let root = SceneOccurrence(
        id: "root",
        definitionID: definition.id,
        localTransform: try translation(x: 10, y: 0, z: 0)
    )
    let child = SceneOccurrence(
        id: "child",
        definitionID: definition.id,
        parentID: root.id,
        localTransform: try translation(x: 0, y: 4, z: 0)
    )
    let project = try ProjectSourceModel(
        id: "project.hierarchy",
        name: "Hierarchy",
        authoredMeshAssets: [asset.id: asset],
        objectDefinitions: [definition.id: definition],
        occurrences: [root.id: root, child.id: child],
        rootOccurrenceIDs: [root.id]
    )

    let snapshot = try ProjectEvaluationEngine().evaluate(
        project: project,
        purpose: .modeling,
        revision: DocumentTransactionRevision()
    )
    let evaluatedChild = try #require(snapshot.occurrences[child.id])

    #expect(evaluatedChild.worldBounds.minimum == GeometryPoint3D(x: 10, y: 4, z: 0))
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationSelectsPurposeAndSharesAuthoredMeshStorageWithoutMaterialization() throws {
    let modelingMesh = try triangleSource(identity: "mesh.modeling")
    let presentationMesh = try triangleSource(identity: "mesh.presentation", xOffset: 5)
    let modelingAsset = try AuthoredMeshAsset(source: modelingMesh, provenance: .created)
    let presentationAsset = try AuthoredMeshAsset(source: presentationMesh, provenance: .created)
    let definition = objectDefinition(
        id: "multi-representation.definition",
        name: "Multi Representation",
        modelingSource: .authoredMesh(modelingAsset.id),
        presentationSource: .authoredMesh(presentationAsset.id)
    )
    let occurrence = SceneOccurrence(
        id: "multi-representation.occurrence",
        definitionID: definition.id
    )
    let project = try ProjectSourceModel(
        id: "project.multi-representation",
        name: "Multi Representation",
        authoredMeshAssets: [
            modelingAsset.id: modelingAsset,
            presentationAsset.id: presentationAsset,
        ],
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    let engine = ProjectEvaluationEngine()

    let modeling = try engine.evaluate(
        project: project,
        purpose: .modeling,
        revision: DocumentTransactionRevision(11)
    )
    let presentation = try engine.evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision(11)
    )
    let modeledOccurrence = try #require(modeling.occurrences[occurrence.id])
    let presentedOccurrence = try #require(presentation.occurrences[occurrence.id])

    #expect(modeling.id != presentation.id)
    #expect(modeling.id.purpose == .modeling)
    #expect(presentation.id.purpose == .presentation)
    #expect(modeledOccurrence.representationID == definition.representations.selection?.modeling)
    #expect(presentedOccurrence.representationID == definition.representations.selection?.presentation)
    #expect(modeledOccurrence.reference == .authoredMesh(modelingAsset.id))
    #expect(presentedOccurrence.reference == .authoredMesh(presentationAsset.id))
    #expect(modeledOccurrence.worldBounds.minimum.x == 0)
    #expect(presentedOccurrence.worldBounds.minimum.x == 5)
    #expect(modeling.copyTelemetry.didCopy == false)
    #expect(presentation.copyTelemetry.didCopy == false)
    expectSharedStorage(modelingMesh, modeledOccurrence.mesh)
    expectSharedStorage(presentationMesh, presentedOccurrence.mesh)
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationRejectsUnregisteredExternalProviders() throws {
    let definition = objectDefinition(
        id: "external.definition",
        name: "External",
        source: .external(providerID: "unregistered", sourceID: "document", outputID: "body")
    )
    let occurrence = SceneOccurrence(id: "external.occurrence", definitionID: definition.id)
    let project = try ProjectSourceModel(
        id: "project.external",
        name: "External",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    var error: EvaluationError?

    do {
        _ = try ProjectEvaluationEngine().evaluate(
            project: project,
            purpose: .presentation,
            revision: DocumentTransactionRevision()
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .providerNotRegistered)
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationBatchesSharedGeometryReferencesBeforeOccurrenceProjection() throws {
    let mesh = try triangleSource()
    let provider = RecordingGeometrySourceEvaluationProvider(
        providerID: "fixture.geometry",
        mesh: mesh
    )
    let registry = try GeometrySourceEvaluationProviderRegistry(providers: [provider])
    let reference = GeometrySourceReference.external(
        providerID: provider.providerID,
        sourceID: "shared.source",
        outputID: "shared.output"
    )
    let definition = objectDefinition(
        id: "shared.definition",
        name: "Shared",
        source: reference
    )
    let first = SceneOccurrence(id: "shared.first", definitionID: definition.id)
    let second = SceneOccurrence(id: "shared.second", definitionID: definition.id)
    let project = try ProjectSourceModel(
        id: "project.shared-geometry",
        name: "Shared Geometry",
        objectDefinitions: [definition.id: definition],
        occurrences: [first.id: first, second.id: second],
        rootOccurrenceIDs: [first.id, second.id]
    )

    let sourceRevision = DocumentTransactionRevision(9)
    let snapshot = try ProjectEvaluationEngine(registry: registry).evaluate(
        project: project,
        purpose: .presentation,
        revision: sourceRevision
    )

    #expect(snapshot.occurrences.count == 2)
    #expect(provider.callCount() == 1)
    #expect(provider.requests() == [
        GeometrySourceEvaluationRequestSnapshot(
            references: [reference],
            sourceRevision: sourceRevision
        ),
    ])
}

@Test(.timeLimit(.minutes(1)))
func providerRegistryRejectsDuplicateProviderIdentifiers() throws {
    let provider = RecordingGeometrySourceEvaluationProvider(
        providerID: "fixture.duplicate",
        mesh: try triangleSource()
    )
    var error: EvaluationError?

    do {
        _ = try GeometrySourceEvaluationProviderRegistry(providers: [provider, provider])
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .duplicateProvider)
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationRejectsIncompleteProviderResultBatches() throws {
    let provider = RecordingGeometrySourceEvaluationProvider(
        providerID: "fixture.incomplete",
        mesh: try triangleSource(),
        returnsResults: false
    )
    let registry = try GeometrySourceEvaluationProviderRegistry(providers: [provider])
    let reference = GeometrySourceReference.external(
        providerID: provider.providerID,
        sourceID: "missing.source",
        outputID: "missing.output"
    )
    let definition = objectDefinition(
        id: "missing.definition",
        name: "Missing",
        source: reference
    )
    let occurrence = SceneOccurrence(id: "missing.occurrence", definitionID: definition.id)
    let project = try ProjectSourceModel(
        id: "project.incomplete-provider",
        name: "Incomplete Provider",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    var error: EvaluationError?

    do {
        _ = try ProjectEvaluationEngine(registry: registry).evaluate(
            project: project,
            purpose: .presentation,
            revision: DocumentTransactionRevision()
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .invalidResult)
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationRejectsProviderBoundsThatDoNotMatchTheMesh() throws {
    let mesh = try triangleSource()
    let provider = RecordingGeometrySourceEvaluationProvider(
        providerID: "fixture.invalid-bounds",
        mesh: mesh,
        localBounds: try GeometryBounds3D(
            minimum: GeometryPoint3D(x: -1, y: -1, z: -1),
            maximum: GeometryPoint3D(x: 1, y: 1, z: 1)
        )
    )
    let registry = try GeometrySourceEvaluationProviderRegistry(providers: [provider])
    let reference = GeometrySourceReference.external(
        providerID: provider.providerID,
        sourceID: "invalid-bounds.source",
        outputID: "invalid-bounds.output"
    )
    let definition = objectDefinition(
        id: "invalid-bounds.definition",
        name: "Invalid Bounds",
        source: reference
    )
    let occurrence = SceneOccurrence(
        id: "invalid-bounds.occurrence",
        definitionID: definition.id
    )
    let project = try ProjectSourceModel(
        id: "project.invalid-bounds-provider",
        name: "Invalid Bounds Provider",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    var error: EvaluationError?

    do {
        _ = try ProjectEvaluationEngine(registry: registry).evaluate(
            project: project,
            purpose: .presentation,
            revision: DocumentTransactionRevision()
        )
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .invalidResult)
}

private func objectDefinition(
    id: ObjectDefinitionID,
    name: String,
    source: GeometrySourceReference
) -> ObjectDefinition {
    objectDefinition(
        id: id,
        name: name,
        modelingSource: source,
        presentationSource: source
    )
}

private func objectDefinition(
    id: ObjectDefinitionID,
    name: String,
    modelingSource: GeometrySourceReference,
    presentationSource: GeometrySourceReference
) -> ObjectDefinition {
    let modelingID = GeometryRepresentationID(
        rawValue: "representation.\(id.rawValue).modeling"
    )
    if modelingSource == presentationSource {
        return ObjectDefinition(
            id: id,
            name: name,
            representations: GeometryRepresentationSet(
                representations: [
                    modelingID: GeometryRepresentation(
                        id: modelingID,
                        source: modelingSource
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: modelingID,
                    presentation: modelingID
                )
            )
        )
    }
    let presentationID = GeometryRepresentationID(
        rawValue: "representation.\(id.rawValue).presentation"
    )
    return ObjectDefinition(
        id: id,
        name: name,
        representations: GeometryRepresentationSet(
            representations: [
                modelingID: GeometryRepresentation(
                    id: modelingID,
                    source: modelingSource
                ),
                presentationID: GeometryRepresentation(
                    id: presentationID,
                    source: presentationSource
                ),
            ],
            selection: GeometryRepresentationSelection(
                modeling: modelingID,
                presentation: presentationID
            )
        )
    )
}

private func triangleSource(
    identity: GeometrySourceID = "mesh.evaluation",
    xOffset: Double = 0
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let v0 = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: xOffset + 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    return try builder.build()
}

private func expectSharedStorage(_ source: MeshSource, _ evaluated: MeshSource) {
    #expect(source.vertexIDs.storage.chunkIdentities == evaluated.vertexIDs.storage.chunkIdentities)
    #expect(source.vertexIDs.storage.pageIdentities == evaluated.vertexIDs.storage.pageIdentities)
    #expect(
        source.vertexPositions.storage.chunkIdentities
            == evaluated.vertexPositions.storage.chunkIdentities
    )
    #expect(
        source.vertexPositions.storage.pageIdentities
            == evaluated.vertexPositions.storage.pageIdentities
    )
    #expect(source.faceIDs.storage.chunkIdentities == evaluated.faceIDs.storage.chunkIdentities)
    #expect(source.faceIDs.storage.pageIdentities == evaluated.faceIDs.storage.pageIdentities)
    #expect(
        source.cornerVertexIDs.storage.chunkIdentities
            == evaluated.cornerVertexIDs.storage.chunkIdentities
    )
    #expect(
        source.cornerVertexIDs.storage.pageIdentities
            == evaluated.cornerVertexIDs.storage.pageIdentities
    )
}

private func translation(x: Double, y: Double, z: Double) throws -> GeometryTransform3D {
    try GeometryTransform3D(values: [
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    ])
}

private final class RecordingGeometrySourceEvaluationProvider:
    GeometrySourceEvaluationProvider,
    Sendable {
    private struct State: Sendable {
        var requests: [GeometrySourceEvaluationRequestSnapshot] = []
    }

    let providerID: String
    private let mesh: MeshSource
    private let localBounds: GeometryBounds3D?
    private let returnsResults: Bool
    private let state = Mutex(State())

    init(
        providerID: String,
        mesh: MeshSource,
        localBounds: GeometryBounds3D? = nil,
        returnsResults: Bool = true
    ) {
        self.providerID = providerID
        self.mesh = mesh
        self.localBounds = localBounds
        self.returnsResults = returnsResults
    }

    func evaluate(
        _ request: GeometrySourceEvaluationRequest,
        in _: ProjectSourceModel
    ) throws -> [GeometrySourceReference: GeometryEvaluationResult] {
        state.withLock { state in
            state.requests.append(
                GeometrySourceEvaluationRequestSnapshot(
                    references: request.references,
                    sourceRevision: request.sourceRevision
                )
            )
        }

        guard returnsResults else {
            return [:]
        }
        var results: [GeometrySourceReference: GeometryEvaluationResult] = [:]
        for reference in request.references {
            results[reference] = GeometryEvaluationResult(
                reference: reference,
                mesh: mesh,
                localBounds: try localBounds ?? mesh.bounds()
            )
        }
        return results
    }

    func callCount() -> Int {
        state.withLock { $0.requests.count }
    }

    func requests() -> [GeometrySourceEvaluationRequestSnapshot] {
        state.withLock { $0.requests }
    }
}

private struct GeometrySourceEvaluationRequestSnapshot: Equatable, Sendable {
    let references: [GeometrySourceReference]
    let sourceRevision: DocumentTransactionRevision
}
