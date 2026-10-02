import SwiftCAD
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaCore

/// PolySplines on a mesh object reads the mesh it shows, placed where it is shown.
@Suite struct PolySplineSourceMeshTests {
    private func meshDocument() throws -> (DesignDocument, SceneNodeID) {
        var builder = MeshSourceBuilder(identity: "polyspline.mesh")
        let vertices = try (0..<8).map { i in
            try builder.addVertex(GeometryPoint3D(x: Double(i & 1), y: Double((i >> 1) & 1), z: Double((i >> 2) & 1)))
        }
        for face in [[0,2,3,1], [4,5,7,6], [0,1,5,4], [2,6,7,3], [0,4,6,2], [1,3,7,5]] {
            _ = try builder.addFace(vertexIDs: face.map { vertices[$0] })
        }
        let asset = try AuthoredMeshAsset(source: builder.build(), provenance: .created)
        var document = DesignDocument.empty()
        document.authoredMeshAssets[asset.id] = asset
        let id: GeometryRepresentationID = "polyspline.mesh.representation"
        let node = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh box", reference: .authoredMesh(asset.id), object: ObjectDescriptor(
                category: .body, geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [id: GeometryRepresentation(id: id, source: .authoredMesh(asset.id))],
                    selection: GeometryRepresentationSelection(modeling: id, presentation: id)
                )
            )
        )
        return (document, node)
    }

    @Test func aMeshBoxBecomesAClosedPolySplineWhereItIsShown() throws {
        var (document, node) = try meshDocument()
        try document.setSceneNodeTransform(id: node, localTransform: .translation(Vector3D(x: 0, y: 0, z: 3)))
        let mesh = try document.polySplineSourceMesh(forMeshObject: node)
        // Six quads, each as a pair of triangles, on the cube's eight corners lifted 3 up.
        #expect(mesh.positions.count == 8 && mesh.indices.count == 36)
        #expect(mesh.positions.allSatisfy { $0.z >= 3 - 1e-12 && $0.z <= 4 + 1e-12 })
        let store = CADDocumentStore(document: document)
        _ = try store.apply(.createPolySplineSurface(name: "PolySpline", sourceMesh: mesh, options: PolySplineOptions()))
        let result = try DocumentEvaluator.modelingDefault(for: store.document).evaluateExact(store.document.cadDocument)
        #expect(result.brep.bodies.values.contains { $0.kind == .solid })
    }

    @Test func anObjectThatIsNotAMeshIsRefused() throws {
        let (document, _) = try meshDocument()
        #expect(throws: EditorError.self) { _ = try document.polySplineSourceMesh(forMeshObject: SceneNodeID()) }
    }
}
