import RupaCoreTypes

/// Supplies a stable domain and canonical byte contribution for geometry-buffer hashing.
public protocol GeometryBufferContentHashable: Codable, Sendable {
    static var geometryBufferContentDomain: String { get }

    func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws
}

extension Bool: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "bool-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(byte: self ? 1 : 0)
    }
}

extension Int32: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "int32-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(UInt32(bitPattern: self))
    }
}

extension UInt32: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "uint32-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(self)
    }
}

extension Float: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "float32-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        guard isFinite else {
            throw GeometryBufferError(
                code: .nonFiniteHashValue,
                message: "Geometry buffer content hashes require finite Float values."
            )
        }
        hasher.update((self == 0 ? Float.zero : self).bitPattern)
    }
}

extension Double: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "float64-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        guard isFinite else {
            throw GeometryBufferError(
                code: .nonFiniteHashValue,
                message: "Geometry buffer content hashes require finite Double values."
            )
        }
        hasher.update((self == 0 ? Double.zero : self).bitPattern)
    }
}

extension Optional: GeometryBufferContentHashable
where Wrapped: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String {
        "optional<\(Wrapped.geometryBufferContentDomain)>-v1"
    }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        switch self {
        case .none:
            hasher.update(byte: 0)
        case .some(let value):
            hasher.update(byte: 1)
            try value.updateGeometryBufferContentHash(&hasher)
        }
    }
}
