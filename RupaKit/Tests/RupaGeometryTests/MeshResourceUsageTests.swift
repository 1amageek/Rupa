import Foundation
import RupaCoreTypes
import Testing
@testable import RupaGeometry

@Suite("Mesh resource usage")
struct MeshResourceUsageTests {
    private static func triangle() throws -> MeshSource {
        var builder = MeshSourceBuilder(identity: "mesh.usage.triangle")
        let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [v0, v1, v2])
        return try builder.build()
    }

    private static func quad() throws -> MeshSource {
        var builder = MeshSourceBuilder(identity: "mesh.usage.quad")
        let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
        let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [v0, v1, v2, v3])
        return try builder.build()
    }

    @Test("A triangle accounts for its own elements", .timeLimit(.minutes(1)))
    func triangleAccountsForItsOwnElements() throws {
        let mesh = try Self.triangle()

        let usage = try mesh.resourceUsage()

        #expect(usage.vertexCount == 3)
        #expect(usage.edgeCount == 3)
        #expect(usage.faceCount == 1)
        #expect(usage.cornerCount == 3)
        #expect(usage.triangleCount == 1)
    }

    @Test("Every buffer is charged", .timeLimit(.minutes(1)))
    func everyBufferIsCharged() throws {
        let mesh = try Self.triangle()

        let usage = try mesh.resourceUsage()

        // Stated per buffer rather than as one constant, so dropping a buffer
        // from the accounting fails here instead of silently under-charging.
        let expected =
            3 * MemoryLayout<MeshVertexID>.stride
            + 3 * MemoryLayout<GeometryPoint3D>.stride
            + 3 * MemoryLayout<MeshEdgeID>.stride
            + 3 * MemoryLayout<MeshEdgeEndpoints>.stride
            + 1 * MemoryLayout<MeshFaceID>.stride
            + 1 * MemoryLayout<MeshIndexRange>.stride
            + 3 * MemoryLayout<MeshCornerID>.stride
            + 3 * MemoryLayout<MeshVertexID>.stride
            + 3 * MemoryLayout<MeshEdgeID>.stride
        #expect(usage.byteCount == expected)
    }

    @Test("A quad fan-triangulates to two triangles", .timeLimit(.minutes(1)))
    func quadFanTriangulatesToTwoTriangles() throws {
        let usage = try Self.quad().resourceUsage()

        #expect(usage.faceCount == 1)
        #expect(usage.cornerCount == 4)
        #expect(usage.triangleCount == 2)
    }

    @Test("An attribute layer is charged", .timeLimit(.minutes(1)))
    func attributeLayerIsCharged() throws {
        let plain = try Self.triangle().resourceUsage()

        var builder = MeshSourceBuilder(identity: "mesh.usage.attributed")
        let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [v0, v1, v2])
        try builder.setAttribute(
            GeometryAttributeLayer(
                descriptor: GeometryAttributeDescriptor(
                    id: "attribute.normal",
                    name: "Normal",
                    domain: .vertex,
                    valueType: .vector3,
                    interpolation: .linear
                ),
                values: .vector3(
                    GeometryBuffer([
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                    ])
                )
            )
        )
        let attributed = try builder.build().resourceUsage()

        #expect(attributed.vertexCount == plain.vertexCount)
        #expect(
            attributed.byteCount
                == plain.byteCount + 3 * MemoryLayout<GeometryPoint3D>.stride
        )
    }

    @Test("Usages add", .timeLimit(.minutes(1)))
    func usagesAdd() throws {
        let triangle = try Self.triangle().resourceUsage()
        let quad = try Self.quad().resourceUsage()

        let total = try triangle.adding(quad)

        #expect(total.vertexCount == triangle.vertexCount + quad.vertexCount)
        #expect(total.triangleCount == 3)
        #expect(total.byteCount == triangle.byteCount + quad.byteCount)
        #expect(try MeshResourceUsage.zero.adding(triangle) == triangle)
    }

    @Test("An unrepresentable total is a typed failure", .timeLimit(.minutes(1)))
    func unrepresentableTotalIsTypedFailure() throws {
        let saturated = MeshResourceUsage(
            vertexCount: Int.max,
            edgeCount: 0,
            faceCount: 0,
            cornerCount: 0,
            triangleCount: 0,
            byteCount: 0
        )
        let error = #expect(throws: MeshSourceError.self) {
            _ = try saturated.adding(saturated)
        }
        #expect(error?.code == .resourceLimitExceeded)
    }

    @Test("Preflight storage uses the same footprint as a materialized source", .timeLimit(.minutes(1)))
    func preflightStorageMatchesMaterializedSource() throws {
        let usage = try Self.triangle().resourceUsage()
        let estimate = try MeshResourceUsage.materializedStorage(
            vertexCount: usage.vertexCount,
            edgeCount: usage.edgeCount,
            faceCount: usage.faceCount,
            cornerCount: usage.cornerCount,
            triangleCount: usage.triangleCount
        )

        #expect(estimate == usage)
    }

    @Test("Preflight storage overflow is typed", .timeLimit(.minutes(1)))
    func preflightStorageOverflowIsTyped() throws {
        let error = #expect(throws: MeshSourceError.self) {
            _ = try MeshResourceUsage.materializedStorage(
                vertexCount: Int.max,
                edgeCount: 0,
                faceCount: 0,
                cornerCount: 0,
                triangleCount: 0
            )
        }

        #expect(error?.code == .resourceLimitExceeded)
    }

    @Test("Malformed paired buffers are rejected before accounting", .timeLimit(.minutes(1)))
    func malformedPairedBuffersAreRejectedBeforeAccounting() throws {
        let encoded = try JSONEncoder().encode(Self.triangle())
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var positions = object["vertexPositions"] as? [[String: Any]],
              !positions.isEmpty else {
            Issue.record("The triangle fixture did not encode vertex positions as an array.")
            return
        }
        positions.removeLast()
        object["vertexPositions"] = positions
        let malformed = try JSONDecoder().decode(
            MeshSource.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        let error = #expect(throws: MeshSourceError.self) {
            _ = try malformed.resourceUsage()
        }
        #expect(error?.code == .invalidBuffer)
    }
}
