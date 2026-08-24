enum MeshSourceBinaryFormat {
    static let magic: [UInt8] = [0x52, 0x55, 0x50, 0x41, 0x4D, 0x53, 0x48, 0x31]
    static let schemaVersion: UInt16 = 1
    static let flags: UInt16 = 0
    static let headerByteCount: UInt64 = 20

    static func encodedDomain(_ domain: GeometryAttributeDomain) -> UInt8 {
        switch domain {
        case .vertex: 0
        case .edge: 1
        case .face: 2
        case .corner: 3
        case .point: 4
        case .curve: 5
        case .instance: 6
        }
    }

    static func decodedDomain(_ value: UInt8) throws -> GeometryAttributeDomain {
        switch value {
        case 0: .vertex
        case 1: .edge
        case 2: .face
        case 3: .corner
        case 4: .point
        case 5: .curve
        case 6: .instance
        default:
            throw invalidTag("attribute domain", value: value)
        }
    }

    static func encodedValueType(_ valueType: GeometryAttributeValueType) -> UInt8 {
        switch valueType {
        case .boolean: 0
        case .int32: 1
        case .float32: 2
        case .float64: 3
        case .vector2: 4
        case .vector3: 5
        case .vector4: 6
        }
    }

    static func decodedValueType(_ value: UInt8) throws -> GeometryAttributeValueType {
        switch value {
        case 0: .boolean
        case 1: .int32
        case 2: .float32
        case 3: .float64
        case 4: .vector2
        case 5: .vector3
        case 6: .vector4
        default:
            throw invalidTag("attribute value type", value: value)
        }
    }

    static func encodedInterpolation(
        _ interpolation: GeometryAttributeInterpolation
    ) -> UInt8 {
        switch interpolation {
        case .none: 0
        case .constant: 1
        case .nearest: 2
        case .linear: 3
        }
    }

    static func decodedInterpolation(
        _ value: UInt8
    ) throws -> GeometryAttributeInterpolation {
        switch value {
        case 0: .none
        case 1: .constant
        case 2: .nearest
        case 3: .linear
        default:
            throw invalidTag("attribute interpolation", value: value)
        }
    }

    private static func invalidTag(_ name: String, value: UInt8) -> MeshSourceError {
        MeshSourceError(
            code: .malformedPayload,
            message: "Mesh source \(name) tag \(value) is invalid."
        )
    }
}
