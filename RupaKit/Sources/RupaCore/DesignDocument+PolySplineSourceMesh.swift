import Foundation
import RupaCoreTypes
import SwiftCAD
import RupaGeometry

extension DesignDocument {
    /// PolySplines' source mesh from a mesh object, as Plasticity runs PolySplines on a selected
    /// mesh: the presented authored mesh's faces triangulated (a quad as the pair of triangles the
    /// kernel reads back as one quad), its vertices placed in world space by the object's
    /// placement, so the result lands where the mesh is shown.
    public func polySplineSourceMesh(forMeshObject id: SceneNodeID) throws -> Mesh {
        guard let node = productMetadata.sceneNodes[id], let set = node.object?.geometryRepresentations,
              let selected = set.selection,
              case .authoredMesh(let sourceID) = set.representations[selected.presentation]?.source else {
            throw EditorError(code: .commandInvalid, message: "PolySplines takes a mesh object.")
        }
        guard let source = authoredMeshAssets[sourceID]?.source else {
            throw EditorError(code: .referenceUnresolved, message: "PolySplines cannot resolve mesh \(sourceID.rawValue).")
        }
        let placement = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: id)
        let index = try source.makeTriangulationIndex()
        var indices: [UInt32] = []
        var telemetry = MeshTriangulationTelemetry()
        for face in source.faceIDs.indices {
            for triangle in try source.triangulate(faceIndex: face, using: index, telemetry: &telemetry) {
                for vertex in [triangle.vertexIDs.0, triangle.vertexIDs.1, triangle.vertexIDs.2] {
                    guard let position = index.positionIndex(for: vertex), let value = UInt32(exactly: position) else {
                        throw EditorError(code: .evaluationFailed, message: "PolySplines' mesh has a triangle with an invalid vertex.")
                    }
                    indices.append(value)
                }
            }
        }
        let positions = try source.vertexPositions.map { try placement.applied(to: Point3D(x: $0.x, y: $0.y, z: $0.z)) }
        return Mesh(positions: positions, indices: indices)
    }
}
