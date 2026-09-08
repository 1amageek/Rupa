import RupaCoreTypes
import RupaGeometry
import SwiftCAD

/// The immutable universal source and copy telemetry produced from one
/// Swift-CAD mesh. The conversion owner is shared by evaluated CAD and file
/// exchange so both paths preserve the same topology and attribute contract.
struct CADMeshSourceMaterialization: Sendable {
    let source: MeshSource
    let copyTelemetry: GeometryCopyTelemetry
}

enum CADMeshSourceConversionError: Error, Equatable, Sendable {
    case unsupportedMaterial
    case invalidMesh(String)
    /// The builder did not name triangle `triangleIndex` `MeshFaceID(triangleIndex)`.
    ///
    /// CAD face provenance is recorded against the Swift-CAD triangle order, so
    /// a native hit can only be resolved through the mesh face identity if the
    /// two orders coincide. A divergence is reported rather than repaired,
    /// because a repaired ordering would resolve hits to the wrong CAD face.
    case faceIdentityMismatch(triangleIndex: Int, faceID: UInt64)
}

enum CADMeshSourceConverter {
    static func makeMeshSource(
        identity: GeometrySourceID,
        mesh: Mesh
    ) throws -> CADMeshSourceMaterialization {
        try Task.checkCancellation()
        guard mesh.material == nil else {
            throw CADMeshSourceConversionError.unsupportedMaterial
        }
        guard !mesh.positions.isEmpty,
              !mesh.indices.isEmpty,
              mesh.indices.count.isMultiple(of: 3),
              (mesh.normals.isEmpty || mesh.normals.count == mesh.positions.count),
              (mesh.textureCoordinates.isEmpty
                || mesh.textureCoordinates.count == mesh.positions.count),
              (mesh.vertexColors.isEmpty || mesh.vertexColors.count == mesh.positions.count)
        else {
            throw CADMeshSourceConversionError.invalidMesh(
                "Mesh buffers do not satisfy the universal source conversion contract."
            )
        }

        do {
            var builder = MeshSourceBuilder(identity: identity)
            try builder.reserveCapacity(
                vertexCount: mesh.positions.count,
                faceCount: mesh.indices.count / 3,
                cornerCount: mesh.indices.count
            )

            var vertices: [MeshVertexID] = []
            vertices.reserveCapacity(mesh.positions.count)
            for (index, position) in mesh.positions.enumerated() {
                if index.isMultiple(of: 1_024) {
                    try Task.checkCancellation()
                }
                vertices.append(
                    try builder.addVertex(
                        GeometryPoint3D(x: position.x, y: position.y, z: position.z)
                    )
                )
            }

            for triangleStart in stride(from: 0, to: mesh.indices.count, by: 3) {
                if triangleStart.isMultiple(of: 3 * 1_024) {
                    try Task.checkCancellation()
                }
                guard let firstIndex = Int(exactly: mesh.indices[triangleStart]),
                      let secondIndex = Int(exactly: mesh.indices[triangleStart + 1]),
                      let thirdIndex = Int(exactly: mesh.indices[triangleStart + 2]),
                      vertices.indices.contains(firstIndex),
                      vertices.indices.contains(secondIndex),
                      vertices.indices.contains(thirdIndex) else {
                    throw CADMeshSourceConversionError.invalidMesh(
                        "Mesh triangle index is outside the position buffer."
                    )
                }
                let triangleIndex = triangleStart / 3
                let faceID = try builder.addTriangle(
                    vertices[firstIndex],
                    vertices[secondIndex],
                    vertices[thirdIndex]
                )
                guard faceID.rawValue == UInt64(triangleIndex) else {
                    throw CADMeshSourceConversionError.faceIdentityMismatch(
                        triangleIndex: triangleIndex,
                        faceID: faceID.rawValue
                    )
                }
            }

            if !mesh.normals.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.normal",
                            name: "CAD Normal",
                            domain: .vertex,
                            valueType: .vector3,
                            interpolation: .linear
                        ),
                        values: .vector3(GeometryBuffer(try mesh.normals.map {
                            try Task.checkCancellation()
                            return GeometryPoint3D(x: $0.x, y: $0.y, z: $0.z)
                        }))
                    )
                )
            }
            if !mesh.textureCoordinates.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.uv",
                            name: "CAD UV",
                            domain: .vertex,
                            valueType: .vector2,
                            interpolation: .linear
                        ),
                        values: .vector2(GeometryBuffer(try mesh.textureCoordinates.map {
                            try Task.checkCancellation()
                            return GeometryVector2D(x: $0.x, y: $0.y)
                        }))
                    )
                )
            }
            if !mesh.vertexColors.isEmpty {
                try builder.setAttribute(
                    GeometryAttributeLayer(
                        descriptor: GeometryAttributeDescriptor(
                            id: "cad.color",
                            name: "CAD Vertex Color",
                            domain: .vertex,
                            valueType: .vector4,
                            interpolation: .linear
                        ),
                        values: .vector4(GeometryBuffer(try mesh.vertexColors.map {
                            try Task.checkCancellation()
                            return GeometryVector4D(x: $0.r, y: $0.g, z: $0.b, w: $0.a)
                        }))
                    )
                )
            }

            var copyTelemetry = GeometryCopyTelemetry()
            let source = try builder.build(telemetry: &copyTelemetry)
            return CADMeshSourceMaterialization(
                source: source,
                copyTelemetry: copyTelemetry
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as CADMeshSourceConversionError {
            throw error
        } catch {
            throw CADMeshSourceConversionError.invalidMesh(
                "CAD mesh could not be converted without loss: \(error)"
            )
        }
    }
}
