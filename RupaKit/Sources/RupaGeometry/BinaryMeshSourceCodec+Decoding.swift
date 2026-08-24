import Foundation
import RupaCoreTypes

extension BinaryMeshSourceCodec {
    public func decode<Source: MeshSourceChunkSource>(
        from source: inout Source,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> MeshSource {
        try limits.validate()
        var reader = MeshSourceBinaryReader(
            source: source,
            chunkByteCount: limits.maximumChunkByteCount
        )
        defer {
            source = reader.source
        }

        for expectedByte in MeshSourceBinaryFormat.magic {
            guard try reader.readByte() == expectedByte else {
                throw MeshSourceError(
                    code: .malformedPayload,
                    message: "Mesh source blob has an invalid magic value."
                )
            }
        }
        let version = try reader.readUInt16()
        guard version == MeshSourceBinaryFormat.schemaVersion else {
            throw MeshSourceError(
                code: .unsupportedVersion,
                message: "Mesh source schema version \(version) is not supported."
            )
        }
        let flags = try reader.readUInt16()
        guard flags == MeshSourceBinaryFormat.flags else {
            throw MeshSourceError(
                code: .unsupportedVersion,
                message: "Mesh source frame flags \(flags) are not supported."
            )
        }
        let bodyByteCount = try reader.readUInt64()
        try reader.setBodyByteCount(bodyByteCount, limits: limits)
        let totalByteCount = bodyByteCount + MeshSourceBinaryFormat.headerByteCount
        var updatedTelemetry = telemetry
        do {
            try updatedTelemetry.record(
                reason: .codecDecode,
                copiedBytes: totalByteCount
            )
        } catch let error as GeometryBufferError {
            throw MeshSourceError(code: .resourceLimitExceeded, message: error.message)
        }

        let identity = GeometrySourceID(rawValue: try reader.readString(limits: limits))
        let allocationState = MeshElementIDAllocationState(
            nextVertexID: try readOptionalID(from: &reader).map(MeshVertexID.init),
            nextEdgeID: try readOptionalID(from: &reader).map(MeshEdgeID.init),
            nextFaceID: try readOptionalID(from: &reader).map(MeshFaceID.init),
            nextCornerID: try readOptionalID(from: &reader).map(MeshCornerID.init)
        )

        let vertexIDs = try readBuffer(from: &reader, limits: limits) {
            MeshVertexID(try $0.readUInt64())
        }
        let vertexPositions = try readBuffer(from: &reader, limits: limits) {
            try readPoint3D(from: &$0)
        }
        let edgeIDs = try readBuffer(from: &reader, limits: limits) {
            MeshEdgeID(try $0.readUInt64())
        }
        let edgeEndpoints = try readBuffer(from: &reader, limits: limits) {
            MeshEdgeEndpoints(
                start: MeshVertexID(try $0.readUInt64()),
                end: MeshVertexID(try $0.readUInt64())
            )
        }
        let faceIDs = try readBuffer(from: &reader, limits: limits) {
            MeshFaceID(try $0.readUInt64())
        }
        let faceCornerRanges = try readBuffer(from: &reader, limits: limits) {
            MeshIndexRange(
                start: try exactInt($0.readUInt64()),
                count: try exactInt($0.readUInt64())
            )
        }
        let cornerIDs = try readBuffer(from: &reader, limits: limits) {
            MeshCornerID(try $0.readUInt64())
        }
        let cornerVertexIDs = try readBuffer(from: &reader, limits: limits) {
            MeshVertexID(try $0.readUInt64())
        }
        let cornerEdgeIDs = try readBuffer(from: &reader, limits: limits) {
            MeshEdgeID(try $0.readUInt64())
        }

        let encodedAttributeCount = try reader.readUInt32()
        guard let attributeCount = Int(exactly: encodedAttributeCount),
            attributeCount <= limits.maximumAttributeCount
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source attribute count exceeds its configured limit."
            )
        }
        var layers: [GeometryAttributeLayer] = []
        layers.reserveCapacity(attributeCount)
        for _ in 0..<attributeCount {
            layers.append(try readAttribute(from: &reader, limits: limits))
        }

        try reader.finishFrame()
        let result = try MeshSource(
            identity: identity,
            allocationState: allocationState,
            vertexIDs: vertexIDs,
            vertexPositions: vertexPositions,
            edgeIDs: edgeIDs,
            edgeEndpoints: edgeEndpoints,
            faceIDs: faceIDs,
            faceCornerRanges: faceCornerRanges,
            cornerIDs: cornerIDs,
            cornerVertexIDs: cornerVertexIDs,
            cornerEdgeIDs: cornerEdgeIDs,
            attributes: try GeometryAttributeSet(layers: layers)
        )
        telemetry = updatedTelemetry
        return result
    }

    private func readOptionalID<Source: MeshSourceChunkSource>(
        from reader: inout MeshSourceBinaryReader<Source>
    ) throws -> UInt64? {
        switch try reader.readByte() {
        case 0:
            return nil
        case 1:
            return try reader.readUInt64()
        case let tag:
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source optional ID tag \(tag) is invalid."
            )
        }
    }

    private func readBuffer<Element, Source: MeshSourceChunkSource>(
        from reader: inout MeshSourceBinaryReader<Source>,
        limits: MeshSourceCodecLimits,
        readElement: (inout MeshSourceBinaryReader<Source>) throws -> Element
    ) throws -> GeometryBuffer<Element> where Element: Codable & Sendable {
        let count = try reader.readBufferCount(limits: limits)
        var construction = GeometryBufferConstructionBuffer<Element>()
        construction.reserveCapacity(count)
        do {
            for _ in 0..<count {
                try construction.append(try readElement(&reader))
            }
        } catch let error as GeometryBufferError {
            throw MeshSourceError(code: .resourceLimitExceeded, message: error.message)
        }
        return construction.build()
    }

    private func readPoint3D<Source: MeshSourceChunkSource>(
        from reader: inout MeshSourceBinaryReader<Source>
    ) throws -> GeometryPoint3D {
        GeometryPoint3D(
            x: try reader.readDouble(),
            y: try reader.readDouble(),
            z: try reader.readDouble()
        )
    }

    private func readAttribute<Source: MeshSourceChunkSource>(
        from reader: inout MeshSourceBinaryReader<Source>,
        limits: MeshSourceCodecLimits
    ) throws -> GeometryAttributeLayer {
        let id = GeometryAttributeID(rawValue: try reader.readString(limits: limits))
        let name = try reader.readString(limits: limits)
        let domain = try MeshSourceBinaryFormat.decodedDomain(reader.readByte())
        let valueType = try MeshSourceBinaryFormat.decodedValueType(reader.readByte())
        let interpolation = try MeshSourceBinaryFormat.decodedInterpolation(
            reader.readByte()
        )
        let sparseTag = try reader.readByte()
        guard sparseTag <= 1 else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source sparse attribute tag \(sparseTag) is invalid."
            )
        }
        let isSparse = sparseTag == 1
        let valueCount = try reader.readBufferCount(limits: limits)
        let values = try readAttributeValues(
            valueType: valueType,
            count: valueCount,
            from: &reader
        )
        let indices: GeometryBuffer<UInt32>?
        if isSparse {
            indices = try readFixedCountBuffer(count: valueCount, from: &reader) {
                try $0.readUInt32()
            }
        } else {
            indices = nil
        }
        return GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: id,
                name: name,
                domain: domain,
                valueType: valueType,
                interpolation: interpolation,
                isSparse: isSparse
            ),
            values: values,
            indices: indices
        )
    }

    private func readAttributeValues<Source: MeshSourceChunkSource>(
        valueType: GeometryAttributeValueType,
        count: Int,
        from reader: inout MeshSourceBinaryReader<Source>
    ) throws -> GeometryAttributeStorage {
        switch valueType {
        case .boolean:
            return .boolean(
                try readFixedCountBuffer(count: count, from: &reader) {
                    let value = try $0.readByte()
                    guard value <= 1 else {
                        throw MeshSourceError(
                            code: .malformedPayload,
                            message: "Mesh source Boolean attribute value \(value) is invalid."
                        )
                    }
                    return value == 1
                })
        case .int32:
            return .int32(
                try readFixedCountBuffer(count: count, from: &reader) {
                    try $0.readInt32()
                })
        case .float32:
            return .float32(
                try readFixedCountBuffer(count: count, from: &reader) {
                    try $0.readFloat()
                })
        case .float64:
            return .float64(
                try readFixedCountBuffer(count: count, from: &reader) {
                    try $0.readDouble()
                })
        case .vector2:
            return .vector2(
                try readFixedCountBuffer(count: count, from: &reader) {
                    GeometryVector2D(x: try $0.readDouble(), y: try $0.readDouble())
                })
        case .vector3:
            return .vector3(
                try readFixedCountBuffer(count: count, from: &reader) {
                    try readPoint3D(from: &$0)
                })
        case .vector4:
            return .vector4(
                try readFixedCountBuffer(count: count, from: &reader) {
                    GeometryVector4D(
                        x: try $0.readDouble(),
                        y: try $0.readDouble(),
                        z: try $0.readDouble(),
                        w: try $0.readDouble()
                    )
                })
        }
    }

    private func readFixedCountBuffer<Element, Source: MeshSourceChunkSource>(
        count: Int,
        from reader: inout MeshSourceBinaryReader<Source>,
        readElement: (inout MeshSourceBinaryReader<Source>) throws -> Element
    ) throws -> GeometryBuffer<Element> where Element: Codable & Sendable {
        var construction = GeometryBufferConstructionBuffer<Element>()
        construction.reserveCapacity(count)
        do {
            for _ in 0..<count {
                try construction.append(try readElement(&reader))
            }
        } catch let error as GeometryBufferError {
            throw MeshSourceError(code: .resourceLimitExceeded, message: error.message)
        }
        return construction.build()
    }

    private func exactInt(_ value: UInt64) throws -> Int {
        guard let result = Int(exactly: value) else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source index exceeds the platform Int range."
            )
        }
        return result
    }
}
