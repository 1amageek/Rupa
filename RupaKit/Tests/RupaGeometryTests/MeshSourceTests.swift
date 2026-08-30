import Foundation
import RupaCoreTypes
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
func meshSourceBuilderAddsTrianglesWithoutWeakeningValidation() throws {
    var builder = MeshSourceBuilder(identity: "fixture.triangles")
    try builder.reserveCapacity(vertexCount: 4, faceCount: 2, cornerCount: 6)
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v0, v2, v3)
    #expect(throws: MeshSourceError.self) {
        _ = try builder.addTriangle(v0, v0, v1)
    }
    #expect(throws: MeshSourceError.self) {
        _ = try builder.addTriangle(v0, v1, MeshVertexID(4))
    }
    let source = try builder.build()

    #expect(source.faceIDs.count == 2)
    #expect(source.cornerIDs.count == 6)
    #expect(source.edgeIDs.count == 5)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBuilderRejectsInvalidCapacityEstimates() {
    var builder = MeshSourceBuilder(identity: "fixture.capacity")

    #expect(throws: MeshSourceError.self) {
        try builder.reserveCapacity(vertexCount: -1, faceCount: 0, cornerCount: 0)
    }
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
func meshEditBufferCopiesOneSharedChunkOnceForMultipleVertexMoves() throws {
    var builder = MeshSourceBuilder(identity: "fixture.edit-multiple-vertices")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    let source = try builder.build()
    var edit = MeshEditBuffer(source: source)

    try edit.setVertexPosition(GeometryPoint3D(x: 0, y: 0, z: 2), for: v0)
    try edit.setVertexPosition(GeometryPoint3D(x: 1, y: 0, z: 3), for: v1)
    let committed = try edit.commit()

    #expect(committed.source.vertexPositions[0].z == 2)
    #expect(committed.source.vertexPositions[1].z == 3)
    #expect(
        committed.telemetry.copiedBytes
            == UInt64(
                source.vertexPositions.count * MemoryLayout<GeometryPoint3D>.stride
            )
    )
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

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationUsesSourceOrderForConvexFaces() throws {
    var builder = MeshSourceBuilder(identity: "fixture.triangulation-fan")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 2, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 2, y: 2, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 2, z: 0))
    let faceID = try builder.addFace(vertexIDs: [first, second, third, fourth])
    let source = try builder.build()
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()

    let triangles = try source.triangulate(
        faceIndex: 0,
        using: index,
        telemetry: &telemetry
    )

    #expect(triangles == [
        MeshTriangle(faceID: faceID, vertexIDs: (first, second, third)),
        MeshTriangle(faceID: faceID, vertexIDs: (first, third, fourth)),
    ])
    #expect(telemetry.faceVisits == 1)
    #expect(telemetry.cornerVisits == 4)
    #expect(telemetry.indexedVertexLookups == 4)
    #expect(telemetry.positionReads == 4)
    #expect(telemetry.globalIdentifierScans == 0)
    #expect(telemetry.nonConvexWorkUnits == 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationUsesScaleAwareConvexFanForHighSegmentCylinderCap() throws {
    let segmentCount = 6_284
    let radius = 0.035
    var builder = MeshSourceBuilder(identity: "fixture.triangulation-cylinder")
    try builder.reserveCapacity(
        vertexCount: segmentCount,
        faceCount: 1,
        cornerCount: segmentCount
    )
    var vertices: [MeshVertexID] = []
    vertices.reserveCapacity(segmentCount)
    for index in 0..<segmentCount {
        let angle = 2.0 * Double.pi * Double(index) / Double(segmentCount)
        vertices.append(
            try builder.addVertex(
                GeometryPoint3D(
                    x: radius * cos(angle),
                    y: radius * sin(angle),
                    z: 0
                )
            )
        )
    }
    _ = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()

    let triangles = try source.triangulate(
        faceIndex: 0,
        using: index,
        tolerance: 1e-9,
        limits: .standard,
        telemetry: &telemetry
    )

    #expect(triangles.count == segmentCount - 2)
    #expect(telemetry.faceVisits == 1)
    #expect(telemetry.cornerVisits == segmentCount)
    #expect(telemetry.indexedVertexLookups == segmentCount)
    #expect(telemetry.positionReads == segmentCount)
    #expect(telemetry.nonConvexWorkUnits == 0)
    #expect(telemetry.globalIdentifierScans == 0)
    #expect(telemetry.sourcePositionMaterializations == 0)
    #expect(telemetry.scratchPositionValues == segmentCount)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationAcceptsAnIndexForAValueCopiedSource() throws {
    let source = try makeTriangulationSquare(identity: "fixture.triangulation-shared")
    let copiedSource = source
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()

    let triangles = try copiedSource.triangulate(
        faceIndex: 0,
        using: index,
        telemetry: &telemetry
    )

    #expect(triangles.count == 2)
    #expect(telemetry.globalIdentifierScans == 0)
    #expect(telemetry.cornerVisits == 4)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationRoutesShallowConcavityToBudgetedEarClipping() throws {
    var builder = MeshSourceBuilder(identity: "fixture.triangulation-shallow-concavity")
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 2, z: 0),
        GeometryPoint3D(x: 1, y: 1.99999999975, z: 0),
        GeometryPoint3D(x: 0, y: 2, z: 0),
    ]
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()

    let triangles = try source.triangulate(
        faceIndex: 0,
        using: index,
        tolerance: 1e-9,
        limits: .standard,
        telemetry: &telemetry
    )

    #expect(triangles.count == 3)
    #expect(telemetry.nonConvexWorkUnits > 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationRoutesCollinearVerticesToEarClipping() throws {
    var builder = MeshSourceBuilder(identity: "fixture.triangulation-collinear")
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 1, z: 0),
        GeometryPoint3D(x: 0, y: 1, z: 0),
    ]
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()

    let triangles = try source.triangulate(
        faceIndex: 0,
        using: index,
        tolerance: 1e-9,
        limits: .standard,
        telemetry: &telemetry
    )

    #expect(triangles.count == 3)
    #expect(telemetry.nonConvexWorkUnits > 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationChargesConcaveWorkAndRejectsBudgetExhaustion() throws {
    var builder = MeshSourceBuilder(identity: "fixture.triangulation-budget")
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 3, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0),
        GeometryPoint3D(x: 0, y: 3, z: 0),
    ]
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    let source = try builder.build()
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()
    var error: MeshTriangulationError?

    do {
        _ = try source.triangulate(
            faceIndex: 0,
            using: index,
            tolerance: 1e-9,
            limits: MeshTriangulationLimits(
                maxFaceCornerCount: 16_384,
                maxNonConvexWorkUnits: 0
            ),
            telemetry: &telemetry
        )
    } catch let caught as MeshTriangulationError {
        error = caught
    }

    #expect(error?.code == .budgetExceeded)
    #expect(telemetry.nonConvexWorkUnits == 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationRejectsAnIndexFromDifferentStorage() throws {
    let first = try makeTriangulationSquare(identity: "fixture.triangulation-stale")
    let second = try makeTriangulationSquare(identity: "fixture.triangulation-stale")
    let index = try first.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()
    var error: MeshTriangulationError?

    do {
        _ = try second.triangulate(
            faceIndex: 0,
            using: index,
            telemetry: &telemetry
        )
    } catch let caught as MeshTriangulationError {
        error = caught
    }

    #expect(error?.code == .invalidReference)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationRejectsLimitsAboveHardMaximum() throws {
    let source = try makeTriangulationSquare(identity: "fixture.triangulation-limits")
    let index = try source.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()
    var error: MeshTriangulationError?

    do {
        _ = try source.triangulate(
            faceIndex: 0,
            using: index,
            limits: MeshTriangulationLimits(
                maxFaceCornerCount: MeshTriangulationLimits.hardMaximum.maxFaceCornerCount + 1,
                maxNonConvexWorkUnits: MeshTriangulationLimits.hardMaximum.maxNonConvexWorkUnits
            ),
            telemetry: &telemetry
        )
    } catch let caught as MeshTriangulationError {
        error = caught
    }

    #expect(error?.code == .invalidLimits)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceTriangulationReportsFaceRangeArithmeticOverflow() throws {
    let source = try makeTriangulationSquare(identity: "fixture.triangulation-overflow")
    let malformedSource = try sourceByDecoding(
        source,
        firstFaceCornerRange: MeshIndexRange(start: Int.max, count: 3)
    )
    let index = try malformedSource.makeTriangulationIndex()
    var telemetry = MeshTriangulationTelemetry()
    var error: MeshTriangulationError?

    do {
        _ = try malformedSource.triangulate(
            faceIndex: 0,
            using: index,
            telemetry: &telemetry
        )
    } catch let caught as MeshTriangulationError {
        error = caught
    }

    #expect(error?.code == .sizeOverflow)
    #expect(telemetry.faceVisits == 1)
    #expect(telemetry.cornerVisits == 0)
}

private func makeTriangulationSquare(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

private func sourceByDecoding(
    _ source: MeshSource,
    firstFaceCornerRange range: MeshIndexRange
) throws -> MeshSource {
    let encoded = try JSONEncoder().encode(source)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
          var ranges = object["faceCornerRanges"] as? [[String: Any]],
          !ranges.isEmpty else {
        throw MeshTriangulationError(
            code: .failed,
            message: "Triangulation test source did not encode a face range."
        )
    }
    ranges[0] = ["start": range.start, "count": range.count]
    object["faceCornerRanges"] = ranges
    let malformedData = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(MeshSource.self, from: malformedData)
}
