import RupaGeometry
import RupaCoreTypes
import Testing
@testable import RupaProjectModel

@Test(.timeLimit(.minutes(1)))
func projectSourceModelValidatesMeshDefinitionsAndHierarchy() throws {
    let mesh = try triangleSource()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.triangle"
    let definition = ObjectDefinition(
        id: "triangle.definition",
        name: "Triangle",
        representations: GeometryRepresentationSet(
            representations: [
                representationID: GeometryRepresentation(
                    id: representationID,
                    source: .authoredMesh(mesh.identity)
                ),
            ],
            selection: GeometryRepresentationSelection(
                modeling: representationID,
                presentation: representationID
            )
        )
    )
    let occurrence = SceneOccurrence(
        id: "triangle.occurrence",
        definitionID: definition.id
    )
    let project = try ProjectSourceModel(
        id: "project.fixture",
        name: "Fixture",
        authoredMeshAssets: [asset.id: asset],
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )

    #expect(project.authoredMeshAssets.count == 1)
    #expect(
        project.objectDefinitions[definition.id]?.representations.source(for: .presentation)
            == .authoredMesh(mesh.identity)
    )
}

@Test(.timeLimit(.minutes(1)))
func projectSourceModelRejectsHierarchyCycles() throws {
    let definition = ObjectDefinition(id: "definition", name: "Empty")
    let first = SceneOccurrence(id: "first", definitionID: definition.id, parentID: "second")
    let second = SceneOccurrence(id: "second", definitionID: definition.id, parentID: "first")
    var error: ProjectModelError?

    do {
        _ = try ProjectSourceModel(
            id: "project.cycle",
            name: "Cycle",
            objectDefinitions: [definition.id: definition],
            occurrences: [first.id: first, second.id: second]
        )
    } catch let caught as ProjectModelError {
        error = caught
    }

    #expect(error?.code == .hierarchyCycle)
}

@Test(.timeLimit(.minutes(1)))
func projectSourceModelRejectsExternalReferenceIDsWithSurroundingWhitespace() throws {
    let reference = GeometrySourceReference.external(
        providerID: " provider",
        sourceID: "source",
        outputID: "output"
    )
    var error: ProjectModelError?

    do {
        try reference.validate()
    } catch let caught as ProjectModelError {
        error = caught
    }

    #expect(error?.code == .invalidReference)
}

private func triangleSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "mesh.triangle")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    return try builder.build()
}
