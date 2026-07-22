import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSelectionSetNormalizesTypedElementsDeterministically() throws {
    let selection = try MeshSelectionSet(elements: [
        .face(MeshFaceID(2)),
        .vertex(MeshVertexID(4)),
        .face(MeshFaceID(2)),
        .edge(MeshEdgeID(1)),
    ])

    #expect(selection.elements == [
        .edge(MeshEdgeID(1)),
        .face(MeshFaceID(2)),
        .vertex(MeshVertexID(4)),
    ])
}

@Test(.timeLimit(.minutes(1)))
func meshSelectionSetRejectsMissingElementsInSource() throws {
    var builder = MeshSourceBuilder(identity: "fixture.selection")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let faceID = try builder.addFace(vertexIDs: [v0, v1, v2])
    let source = try builder.build()
    let selection = try MeshSelectionSet(elements: [.face(faceID), .vertex(MeshVertexID(999))])

    var error: MeshSourceError?
    do {
        _ = try selection.validated(in: source)
    } catch let caught as MeshSourceError {
        error = caught
    }

    #expect(error?.code == .invalidReference)
}
