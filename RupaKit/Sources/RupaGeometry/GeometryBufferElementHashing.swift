import RupaCoreTypes

extension MeshVertexID: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-vertex-id-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(rawValue)
    }
}

extension MeshEdgeID: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-edge-id-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(rawValue)
    }
}

extension MeshFaceID: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-face-id-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(rawValue)
    }
}

extension MeshCornerID: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-corner-id-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) {
        hasher.update(rawValue)
    }
}

extension GeometryPoint3D: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "geometry-point-3d-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        try x.updateGeometryBufferContentHash(&hasher)
        try y.updateGeometryBufferContentHash(&hasher)
        try z.updateGeometryBufferContentHash(&hasher)
    }
}

extension GeometryVector2D: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "geometry-vector-2d-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        try x.updateGeometryBufferContentHash(&hasher)
        try y.updateGeometryBufferContentHash(&hasher)
    }
}

extension GeometryVector4D: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "geometry-vector-4d-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        try x.updateGeometryBufferContentHash(&hasher)
        try y.updateGeometryBufferContentHash(&hasher)
        try z.updateGeometryBufferContentHash(&hasher)
        try w.updateGeometryBufferContentHash(&hasher)
    }
}

extension MeshEdgeEndpoints: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-edge-endpoints-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        start.updateGeometryBufferContentHash(&hasher)
        end.updateGeometryBufferContentHash(&hasher)
    }
}

extension MeshIndexRange: GeometryBufferContentHashable {
    public static var geometryBufferContentDomain: String { "mesh-index-range-v1" }

    public func updateGeometryBufferContentHash(
        _ hasher: inout StableSHA256Hasher
    ) throws {
        guard let start = UInt64(exactly: start),
            let count = UInt64(exactly: count)
        else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Mesh index ranges must be non-negative to produce a content hash."
            )
        }
        hasher.update(start)
        hasher.update(count)
    }
}
