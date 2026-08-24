import Foundation

extension BinaryMeshSourceCodec {
    public func encode<Sink: MeshSourceChunkSink>(
        _ source: MeshSource,
        to sink: inout Sink,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws {
        let totalByteCount = try MeshSourceBinarySizeCalculator.encodedByteCount(
            of: source,
            limits: limits
        )
        var updatedTelemetry = telemetry
        do {
            try updatedTelemetry.record(
                reason: .codecEncode,
                copiedBytes: totalByteCount
            )
        } catch let error as GeometryBufferError {
            throw MeshSourceError(code: .resourceLimitExceeded, message: error.message)
        }

        var writer = MeshSourceBinaryWriter(
            sink: sink,
            chunkByteCount: limits.maximumChunkByteCount
        )
        defer {
            sink = writer.sink
        }

        try writer.writeBytes(MeshSourceBinaryFormat.magic)
        try writer.writeUInt16(MeshSourceBinaryFormat.schemaVersion)
        try writer.writeUInt16(MeshSourceBinaryFormat.flags)
        try writer.writeUInt64(totalByteCount - MeshSourceBinaryFormat.headerByteCount)

        try writer.writeString(source.identity.rawValue)
        try writeOptionalID(source.allocationState.nextVertexID?.rawValue, to: &writer)
        try writeOptionalID(source.allocationState.nextEdgeID?.rawValue, to: &writer)
        try writeOptionalID(source.allocationState.nextFaceID?.rawValue, to: &writer)
        try writeOptionalID(source.allocationState.nextCornerID?.rawValue, to: &writer)

        try writeCount(source.vertexIDs.count, to: &writer)
        for value in source.vertexIDs {
            try writer.writeUInt64(value.rawValue)
        }
        try writeCount(source.vertexPositions.count, to: &writer)
        for value in source.vertexPositions {
            try writePoint3D(value, to: &writer)
        }
        try writeCount(source.edgeIDs.count, to: &writer)
        for value in source.edgeIDs {
            try writer.writeUInt64(value.rawValue)
        }
        try writeCount(source.edgeEndpoints.count, to: &writer)
        for value in source.edgeEndpoints {
            try writer.writeUInt64(value.start.rawValue)
            try writer.writeUInt64(value.end.rawValue)
        }
        try writeCount(source.faceIDs.count, to: &writer)
        for value in source.faceIDs {
            try writer.writeUInt64(value.rawValue)
        }
        try writeCount(source.faceCornerRanges.count, to: &writer)
        for value in source.faceCornerRanges {
            try writer.writeUInt64(try exactUInt64(value.start))
            try writer.writeUInt64(try exactUInt64(value.count))
        }
        try writeCount(source.cornerIDs.count, to: &writer)
        for value in source.cornerIDs {
            try writer.writeUInt64(value.rawValue)
        }
        try writeCount(source.cornerVertexIDs.count, to: &writer)
        for value in source.cornerVertexIDs {
            try writer.writeUInt64(value.rawValue)
        }
        try writeCount(source.cornerEdgeIDs.count, to: &writer)
        for value in source.cornerEdgeIDs {
            try writer.writeUInt64(value.rawValue)
        }

        let layers = source.attributes.sortedLayers()
        try writer.writeUInt32(UInt32(layers.count))
        for layer in layers {
            try write(layer, to: &writer)
        }
        try writer.finish()

        guard writer.writtenByteCount == totalByteCount else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source encoder produced an inconsistent frame length."
            )
        }
        telemetry = updatedTelemetry
    }

    private func writeOptionalID<Sink: MeshSourceChunkSink>(
        _ rawValue: UInt64?,
        to writer: inout MeshSourceBinaryWriter<Sink>
    ) throws {
        guard let rawValue else {
            try writer.writeByte(0)
            return
        }
        try writer.writeByte(1)
        try writer.writeUInt64(rawValue)
    }

    private func writeCount<Sink: MeshSourceChunkSink>(
        _ count: Int,
        to writer: inout MeshSourceBinaryWriter<Sink>
    ) throws {
        try writer.writeUInt64(try exactUInt64(count))
    }

    private func writePoint3D<Sink: MeshSourceChunkSink>(
        _ value: GeometryPoint3D,
        to writer: inout MeshSourceBinaryWriter<Sink>
    ) throws {
        try writer.writeDouble(value.x)
        try writer.writeDouble(value.y)
        try writer.writeDouble(value.z)
    }

    private func write<Sink: MeshSourceChunkSink>(
        _ layer: GeometryAttributeLayer,
        to writer: inout MeshSourceBinaryWriter<Sink>
    ) throws {
        let descriptor = layer.descriptor
        try writer.writeString(descriptor.id.rawValue)
        try writer.writeString(descriptor.name)
        try writer.writeByte(MeshSourceBinaryFormat.encodedDomain(descriptor.domain))
        try writer.writeByte(MeshSourceBinaryFormat.encodedValueType(descriptor.valueType))
        try writer.writeByte(
            MeshSourceBinaryFormat.encodedInterpolation(descriptor.interpolation)
        )
        try writer.writeByte(descriptor.isSparse ? 1 : 0)
        try writeCount(layer.values.count, to: &writer)
        try write(layer.values, to: &writer)
        if let indices = layer.indices {
            for index in indices {
                try writer.writeUInt32(index)
            }
        }
    }

    private func write<Sink: MeshSourceChunkSink>(
        _ storage: GeometryAttributeStorage,
        to writer: inout MeshSourceBinaryWriter<Sink>
    ) throws {
        switch storage {
        case .boolean(let values):
            for value in values {
                try writer.writeByte(value ? 1 : 0)
            }
        case .int32(let values):
            for value in values {
                try writer.writeInt32(value)
            }
        case .float32(let values):
            for value in values {
                try writer.writeFloat(value)
            }
        case .float64(let values):
            for value in values {
                try writer.writeDouble(value)
            }
        case .vector2(let values):
            for value in values {
                try writer.writeDouble(value.x)
                try writer.writeDouble(value.y)
            }
        case .vector3(let values):
            for value in values {
                try writePoint3D(value, to: &writer)
            }
        case .vector4(let values):
            for value in values {
                try writer.writeDouble(value.x)
                try writer.writeDouble(value.y)
                try writer.writeDouble(value.z)
                try writer.writeDouble(value.w)
            }
        }
    }

    private func exactUInt64(_ value: Int) throws -> UInt64 {
        guard let result = UInt64(exactly: value) else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source index cannot be represented by the binary format."
            )
        }
        return result
    }
}
