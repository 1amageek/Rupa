import RupaCoreTypes
import RupaGeometry

public struct AuthoredMeshSourceIdentityService: Sendable {
    public static let domain = "rupa.authored-mesh-source"
    public static let fingerprintAlgorithm = "sha256-rupa-authored-mesh-source-v1"

    public init() {}

    public func identity(for source: MeshSource) throws -> ContentIdentity {
        try source.validate()
        return try identityForValidatedSource(source)
    }

    func identityForValidatedSource(_ source: MeshSource) throws -> ContentIdentity {
        var hasher = StableSHA256Hasher()
        hasher.update(string: "rupa.authored-mesh-source.v1")
        hasher.update(string: source.identity.rawValue)
        append(source.allocationState.nextVertexID?.rawValue, to: &hasher)
        append(source.allocationState.nextEdgeID?.rawValue, to: &hasher)
        append(source.allocationState.nextFaceID?.rawValue, to: &hasher)
        append(source.allocationState.nextCornerID?.rawValue, to: &hasher)

        hasher.update(count: source.vertexIDs.count)
        for value in source.vertexIDs {
            hasher.update(value.rawValue)
        }
        hasher.update(count: source.vertexPositions.count)
        for value in source.vertexPositions {
            append(value, to: &hasher)
        }
        hasher.update(count: source.edgeIDs.count)
        for value in source.edgeIDs {
            hasher.update(value.rawValue)
        }
        hasher.update(count: source.edgeEndpoints.count)
        for value in source.edgeEndpoints {
            hasher.update(value.start.rawValue)
            hasher.update(value.end.rawValue)
        }
        hasher.update(count: source.faceIDs.count)
        for value in source.faceIDs {
            hasher.update(value.rawValue)
        }
        hasher.update(count: source.faceCornerRanges.count)
        for value in source.faceCornerRanges {
            hasher.update(UInt64(value.start))
            hasher.update(UInt64(value.count))
        }
        hasher.update(count: source.cornerIDs.count)
        for value in source.cornerIDs {
            hasher.update(value.rawValue)
        }
        hasher.update(count: source.cornerVertexIDs.count)
        for value in source.cornerVertexIDs {
            hasher.update(value.rawValue)
        }
        hasher.update(count: source.cornerEdgeIDs.count)
        for value in source.cornerEdgeIDs {
            hasher.update(value.rawValue)
        }

        let layers = source.attributes.sortedLayers()
        hasher.update(count: layers.count)
        for layer in layers {
            append(layer, to: &hasher)
        }
        return try ContentIdentity(
            domain: Self.domain,
            fingerprint: ContentFingerprint(
                algorithm: Self.fingerprintAlgorithm,
                value: hasher.hexDigest()
            )
        )
    }

    private func append(
        _ value: UInt64?,
        to hasher: inout StableSHA256Hasher
    ) {
        guard let value else {
            hasher.update(byte: 0)
            return
        }
        hasher.update(byte: 1)
        hasher.update(value)
    }

    private func append(
        _ point: GeometryPoint3D,
        to hasher: inout StableSHA256Hasher
    ) {
        append(point.x, to: &hasher)
        append(point.y, to: &hasher)
        append(point.z, to: &hasher)
    }

    private func append(
        _ layer: GeometryAttributeLayer,
        to hasher: inout StableSHA256Hasher
    ) {
        let descriptor = layer.descriptor
        hasher.update(string: descriptor.id.rawValue)
        hasher.update(string: descriptor.name)
        hasher.update(string: descriptor.domain.rawValue)
        hasher.update(string: descriptor.valueType.rawValue)
        hasher.update(string: descriptor.interpolation.rawValue)
        hasher.update(byte: descriptor.isSparse ? 1 : 0)
        hasher.update(count: layer.values.count)
        append(layer.values, to: &hasher)
        if let indices = layer.indices {
            hasher.update(byte: 1)
            hasher.update(count: indices.count)
            for index in indices {
                hasher.update(index)
            }
        } else {
            hasher.update(byte: 0)
        }
    }

    private func append(
        _ storage: GeometryAttributeStorage,
        to hasher: inout StableSHA256Hasher
    ) {
        switch storage {
        case .boolean(let values):
            for value in values {
                hasher.update(byte: value ? 1 : 0)
            }
        case .int32(let values):
            for value in values {
                hasher.update(UInt32(bitPattern: value))
            }
        case .float32(let values):
            for value in values {
                let canonical = value == 0 ? Float(0) : value
                hasher.update(canonical.bitPattern)
            }
        case .float64(let values):
            for value in values {
                append(value, to: &hasher)
            }
        case .vector2(let values):
            for value in values {
                append(value.x, to: &hasher)
                append(value.y, to: &hasher)
            }
        case .vector3(let values):
            for value in values {
                append(value, to: &hasher)
            }
        case .vector4(let values):
            for value in values {
                append(value.x, to: &hasher)
                append(value.y, to: &hasher)
                append(value.z, to: &hasher)
                append(value.w, to: &hasher)
            }
        }
    }

    private func append(
        _ value: Double,
        to hasher: inout StableSHA256Hasher
    ) {
        let canonical = value == 0 ? 0.0 : value
        hasher.update(canonical.bitPattern)
    }
}
