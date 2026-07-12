import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
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
