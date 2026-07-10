import SwiftCAD
import RupaCoreTypes

public struct MeshContentFingerprintService: Sendable {
    public init() {}

    public func fingerprint(
        for meshes: [BodyID: Mesh]
    ) throws -> ContentFingerprint {
        guard !meshes.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Mesh artifact content must contain at least one body mesh."
            )
        }

        let bodyIDs = meshes.keys.sorted { $0.description < $1.description }
        var hasher = CanonicalIdentityHasher(domain: "mesh-content.v1")
        hasher.appendField("bodies")
        hasher.appendCount(bodyIDs.count)
        for bodyID in bodyIDs {
            guard let mesh = meshes[bodyID] else {
                throw ReferenceValidationError(
                    code: .invalidIdentity,
                    message: "Mesh artifact content changed during fingerprint construction."
                )
            }
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
