import RupaCoreTypes
import RupaGeometry
import RupaProject
import RupaProjectModel
import Testing

@Test(.timeLimit(.minutes(1)))
func projectControllerEvaluatesBeforePublishingAStagedSource() async throws {
    let initial = try ProjectSourceModel(id: "project.controller", name: "Controller")
    let controller = try ProjectController(source: initial)

    let result = try await controller.commit { source in
        let mesh = try triangleSource()
        let withMesh = try source.adding(mesh)
        let definition = ObjectDefinition(
            id: "definition.triangle",
            name: "Triangle",
            geometry: .mesh(mesh.identity)
        )
        let withDefinition = try withMesh.adding(definition)
        return try withDefinition.adding(
            SceneOccurrence(
                id: "occurrence.triangle",
                definitionID: definition.id
            ),
            asRoot: true
        )
    }

    #expect(result.sourceRevision == DocumentTransactionRevision(1))
    #expect(result.evaluation.occurrences.count == 1)
    #expect(await controller.currentSource() == result.source)
    #expect(try await controller.currentEvaluation().id == result.evaluation.id)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerDoesNotPublishWhenEvaluationFails() async throws {
    let definition = ObjectDefinition(
        id: "definition.external",
        name: "External",
        geometry: .external(providerID: "cad", sourceID: "document", outputID: "body")
    )
    let occurrence = SceneOccurrence(id: "occurrence.external", definitionID: definition.id)
    let initial = try ProjectSourceModel(
        id: "project.failed",
        name: "Failed",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    let controller = try ProjectController(source: initial)
    var error: ProjectControllerError?

    do {
        _ = try await controller.commit { $0 }
    } catch let caught as ProjectControllerError {
        error = caught
    }

    #expect(error?.code == .evaluationFailed)
    #expect(await controller.currentSource() == initial)
    #expect(await controller.currentSourceRevision() == DocumentTransactionRevision())
}

private func triangleSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "mesh.controller")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    return try builder.build()
}
