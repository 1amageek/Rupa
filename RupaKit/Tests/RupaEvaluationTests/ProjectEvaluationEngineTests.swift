import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import Synchronization
import Testing

@Test(.timeLimit(.minutes(1)))
func projectEvaluationProducesImmutableOccurrenceSnapshotsWithWorldBounds() throws {
    let mesh = try triangleSource()
    let definition = ObjectDefinition(
        id: "triangle.definition",
        name: "Triangle",
        geometry: .mesh(mesh.identity)
    )
    let root = SceneOccurrence(
        id: "triangle.root",
        definitionID: definition.id,
        localTransform: try translation(x: 2, y: 3, z: 0)
    )
    let project = try ProjectSourceModel(
        id: "project.evaluation",
        name: "Evaluation",
        meshSources: [mesh.identity: mesh],
        objectDefinitions: [definition.id: definition],
        occurrences: [root.id: root],
        rootOccurrenceIDs: [root.id]
    )

    let snapshot = try ProjectEvaluationEngine().evaluate(
        project,
        sourceRevision: DocumentTransactionRevision(7)
    )
    let evaluated = try #require(snapshot.occurrences[root.id])

    #expect(snapshot.id.sourceRevision == DocumentTransactionRevision(7))
    #expect(evaluated.worldBounds.minimum == GeometryPoint3D(x: 2, y: 3, z: 0))
    #expect(evaluated.worldBounds.maximum == GeometryPoint3D(x: 3, y: 4, z: 0))
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationComposesParentAndChildTransforms() throws {
    let mesh = try triangleSource()
    let definition = ObjectDefinition(id: "definition", name: "Triangle", geometry: .mesh(mesh.identity))
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
        meshSources: [mesh.identity: mesh],
        objectDefinitions: [definition.id: definition],
        occurrences: [root.id: root, child.id: child],
        rootOccurrenceIDs: [root.id]
    )

    let snapshot = try ProjectEvaluationEngine().evaluate(project)
    let evaluatedChild = try #require(snapshot.occurrences[child.id])

    #expect(evaluatedChild.worldBounds.minimum == GeometryPoint3D(x: 10, y: 4, z: 0))
}

@Test(.timeLimit(.minutes(1)))
func projectEvaluationRejectsUnregisteredExternalProviders() throws {
    let definition = ObjectDefinition(
        id: "external.definition",
        name: "External",
        geometry: .external(providerID: "cad", sourceID: "document", outputID: "body")
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
        _ = try ProjectEvaluationEngine().evaluate(project)
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
    let definition = ObjectDefinition(
        id: "shared.definition",
        name: "Shared",
        geometry: reference
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
        project,
        sourceRevision: sourceRevision
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
    let definition = ObjectDefinition(
        id: "missing.definition",
        name: "Missing",
        geometry: reference
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
        _ = try ProjectEvaluationEngine(registry: registry).evaluate(project)
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
    let definition = ObjectDefinition(
        id: "invalid-bounds.definition",
        name: "Invalid Bounds",
        geometry: reference
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
        _ = try ProjectEvaluationEngine(registry: registry).evaluate(project)
    } catch let caught as EvaluationError {
        error = caught
    }

    #expect(error?.code == .invalidResult)
}

private func triangleSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "mesh.evaluation")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    return try builder.build()
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
