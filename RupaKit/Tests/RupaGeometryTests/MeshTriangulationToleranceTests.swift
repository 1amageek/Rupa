import RupaGeometry
import Testing

@Suite struct MeshTriangulationToleranceTests {
    @Test(arguments: [0.0005, 1.0], [0.0, 100.0])
    func planarFacesUseAreaUnits(size: Double, offset: Double) throws {
        // Include a concavity so both fan and ear-clipping predicates are checked.
        for coordinates in [[(0.0,0.0),(1,0),(1,1),(0,1)], [(0.0,0.0),(1,0),(1,1),(0.5,0.4),(0,1)]] {
            var builder = MeshSourceBuilder(identity: "tiny.polygon")
            let vertices = try coordinates.map { x,y in
                try builder.addVertex(GeometryPoint3D(x: offset+x*size, y: offset+y*size, z: offset))
            }
            _ = try builder.addFace(vertexIDs: vertices)
            let mesh = try builder.build()
            for tolerance in [1e-9, 1e-6, 1e-5] {
                #expect(try mesh.triangulateAll(tolerance: tolerance).count == coordinates.count-2)
            }
        }
    }

    @Test func degenerateAndNonPlanarFacesStillFail() throws {
        for positions in [[(0.0,0.0,0.0),(1,0,0),(2,0,0),(3,0,0)],
                          [(0.0,0.0,0.0),(1,0,0),(1,1,0.01),(0,1,0)]] {
            var builder = MeshSourceBuilder(identity: "invalid.polygon")
            let vertices = try positions.map { x,y,z in try builder.addVertex(GeometryPoint3D(x:x,y:y,z:z)) }
            _ = try builder.addFace(vertexIDs: vertices)
            let mesh = try builder.build()
            #expect(throws: MeshTriangulationError.self) { try mesh.triangulateAll(tolerance: 1e-6) }
        }
    }
}
