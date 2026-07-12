import Foundation
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSourceBuilderCreatesCompactPolygonTopology() throws {
    var builder = MeshSourceBuilder(identity: "fixture.mesh")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let faceID = try builder.addFace(vertexIDs: [v0, v1, v2, v3])
    let source = try builder.build()

    #expect(source.vertexIDs.count == 4)
    #expect(source.edgeIDs.count == 4)
    #expect(source.faceIDs == GeometryBuffer([faceID]))
    #expect(source.cornerIDs.count == 4)

    let loop = try source.faceLoop(for: faceID)
    #expect(loop.count == 4)
    #expect(Array(loop).map(\.rawValue) == [0, 1, 2, 3])
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBuilderReusesSharedEdgesAcrossFaces() throws {
    var builder = MeshSourceBuilder(identity: "fixture.shared")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    _ = try builder.addFace(vertexIDs: [v0, v2, v3])
    let source = try builder.build()

    #expect(source.faceIDs.count == 2)
    #expect(source.edgeIDs.count == 5)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceCodecRoundTripsAndRejectsInvalidPayloads() throws {
    var builder = MeshSourceBuilder(identity: "fixture.codec")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    let source = try builder.build()
    let data = try MeshSourceCodec.encode(source)
    let decoded = try MeshSourceCodec.decode(data)

    #expect(decoded == source)

    var error: MeshSourceError?
    do {
        _ = try MeshSourceCodec.decode(Data("not-json".utf8))
    } catch let caught as MeshSourceError {
        error = caught
    }
    #expect(error?.code == .malformedPayload)
}
