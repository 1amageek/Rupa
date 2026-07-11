import SwiftCAD
import RupaCoreTypes

public struct MeshContentFingerprintService: Sendable {
    public init() {}

    public func fingerprint<Meshes: Collection>(
        for meshes: Meshes
    ) throws -> ContentFingerprint
    where Meshes.Element == (key: BodyID, value: Mesh) {
        guard !meshes.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Mesh artifact content must contain at least one body mesh."
            )
        }

        let orderedMeshes = meshes.sorted {
            $0.key.description < $1.key.description
        }
        var hasher = CanonicalIdentityHasher(domain: "mesh-content.v1")
        hasher.appendField("bodies")
        hasher.appendCount(orderedMeshes.count)
        for (bodyID, mesh) in orderedMeshes {
            hasher.appendField("body")
            hasher.appendString(bodyID.description)
            append(mesh: mesh, to: &hasher)
        }
        return try hasher.fingerprint(algorithm: "sha256-mesh-content-v1")
    }

    private func append(
        mesh: Mesh,
        to hasher: inout CanonicalIdentityHasher
    ) {
        hasher.appendField("positions")
        hasher.appendCount(mesh.positions.count)
        for point in mesh.positions {
            hasher.appendDouble(point.x)
            hasher.appendDouble(point.y)
            hasher.appendDouble(point.z)
        }

        hasher.appendField("normals")
        hasher.appendCount(mesh.normals.count)
        for normal in mesh.normals {
            hasher.appendDouble(normal.x)
            hasher.appendDouble(normal.y)
            hasher.appendDouble(normal.z)
        }

        hasher.appendField("indices")
        hasher.appendCount(mesh.indices.count)
        for index in mesh.indices {
            hasher.appendUInt32(index)
        }

        hasher.appendField("textureCoordinates")
        hasher.appendCount(mesh.textureCoordinates.count)
        for coordinate in mesh.textureCoordinates {
            hasher.appendDouble(coordinate.x)
            hasher.appendDouble(coordinate.y)
        }

        hasher.appendField("vertexColors")
        hasher.appendCount(mesh.vertexColors.count)
        for color in mesh.vertexColors {
            hasher.appendDouble(color.r)
            hasher.appendDouble(color.g)
            hasher.appendDouble(color.b)
            hasher.appendDouble(color.a)
        }

        hasher.appendField("material")
        if let material = mesh.material {
            hasher.appendBool(true)
            hasher.appendString(material.description)
        } else {
            hasher.appendBool(false)
        }
    }
}
