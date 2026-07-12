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

@Test(.timeLimit(.minutes(1)))
func meshSourceStoresCornerUVsAndFaceMaterialAttributes() throws {
    var builder = MeshSourceBuilder(identity: "fixture.attributes")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2, v3])
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "uv.map",
                name: "UV Map",
                domain: .corner,
                valueType: .vector2,
                interpolation: .linear
            ),
            values: .vector2(GeometryBuffer([
                GeometryVector2D(x: 0, y: 0),
                GeometryVector2D(x: 1, y: 0),
                GeometryVector2D(x: 1, y: 1),
                GeometryVector2D(x: 0, y: 1),
            ]))
        )
    )
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "material.index",
                name: "Material Index",
                domain: .face,
                valueType: .int32,
                interpolation: .constant
            ),
            values: .int32(GeometryBuffer([Int32(2)]))
        )
    )
    let source = try builder.build()

    #expect(source.attributes.count == 2)
    #expect(source.attributes.layer(for: "uv.map")?.values.valueType == .vector2)
    #expect(source.attributes.layer(for: "material.index")?.values.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceRejectsAttributeDomainLengthMismatch() throws {
    var builder = MeshSourceBuilder(identity: "fixture.invalid-attributes")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "normal",
                name: "Normal",
                domain: .vertex,
                valueType: .vector3,
                interpolation: .linear
            ),
            values: .vector3(GeometryBuffer([
                GeometryPoint3D(x: 0, y: 0, z: 1),
            ]))
        )
    )

    var error: MeshSourceError?
    do {
        _ = try builder.build()
    } catch let caught as MeshSourceError {
        error = caught
    }
    #expect(error?.code == .invalidBuffer)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulatesConcavePolygonWithoutChangingSourceTopology() throws {
    var builder = MeshSourceBuilder(identity: "fixture.concave")
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 2, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0),
        GeometryPoint3D(x: 0, y: 2, z: 0),
    ]
    let vertices = try points.map { try builder.addVertex($0) }
    let faceID = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()

    let triangles = try source.triangulate(faceID: faceID)

    #expect(triangles.count == 3)
    #expect(source.faceCornerRanges[0].count == 5)
    #expect(triangles.allSatisfy { $0.faceID == faceID })
}

@Test(.timeLimit(.minutes(1)))
func meshSourceRejectsNonPlanarPolygonTriangulation() throws {
    var builder = MeshSourceBuilder(identity: "fixture.nonplanar")
    let vertices = try [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0.1),
        GeometryPoint3D(x: 0, y: 1, z: 0),
    ].map { try builder.addVertex($0) }
    let faceID = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()
    var error: MeshTriangulationError?

    do {
        _ = try source.triangulate(faceID: faceID)
    } catch let caught as MeshTriangulationError {
        error = caught
    }

    #expect(error?.code == .nonPlanar)
}

@Test(.timeLimit(.minutes(1)))
func meshEditBufferStagesVertexMovesWithoutChangingTheSource() throws {
    var builder = MeshSourceBuilder(identity: "fixture.edit-vertex")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    let source = try builder.build()
    var edit = MeshEditBuffer(source: source)

    try edit.setVertexPosition(
        GeometryPoint3D(x: 0, y: 0, z: 2),
        for: v0
    )
    #expect(edit.hasEdits)
    #expect(try edit.position(for: v0) == GeometryPoint3D(x: 0, y: 0, z: 2))
    #expect(source.vertexPositions[0] == GeometryPoint3D(x: 0, y: 0, z: 0))

    let committed = try edit.commit()
    #expect(committed.source.vertexPositions[0] == GeometryPoint3D(x: 0, y: 0, z: 2))
    #expect(committed.source.faceIDs == source.faceIDs)
    #expect(committed.telemetry.didCopy)
}

@Test(.timeLimit(.minutes(1)))
func meshEditBufferPreservesFaceIdentityAcrossTopologyEdits() throws {
    var builder = MeshSourceBuilder(identity: "fixture.edit-topology")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let originalFaceID = try builder.addFace(vertexIDs: [v0, v1, v2])
    let source = try builder.build()
    var edit = MeshEditBuffer(source: source)
    let addedFaceID = try edit.addFace(vertexIDs: [v0, v2, v3])

    let added = try edit.commit()
    #expect(added.source.faceIDs.contains(originalFaceID))
    #expect(added.source.faceIDs.contains(addedFaceID))
    #expect(added.source.faceIDs.count == 2)

    var deletion = MeshEditBuffer(source: added.source)
    try deletion.deleteFace(originalFaceID)
    let removed = try deletion.commit()
    #expect(!removed.source.faceIDs.contains(originalFaceID))
    #expect(removed.source.faceIDs.contains(addedFaceID))
}
