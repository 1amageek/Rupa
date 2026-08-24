import Foundation
import RupaCoreTypes
import Testing

@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecRoundTripsEveryAttributeStorageType() throws {
    let source = try attributedMeshSource()
    let data = try MeshSourceCodec.encode(source)
    let decoded = try MeshSourceCodec.decode(data)

    #expect(decoded == source)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecIsDeterministicAcrossChunkSizes() throws {
    let source = try attributedMeshSource()
    var firstLimits = MeshSourceCodecLimits.standard
    firstLimits.maximumChunkByteCount = 7
    var secondLimits = MeshSourceCodecLimits.standard
    secondLimits.maximumChunkByteCount = 257
    var firstSink = RecordingMeshSourceSink()
    var secondSink = RecordingMeshSourceSink()
    var firstTelemetry = GeometryCopyTelemetry()
    var secondTelemetry = GeometryCopyTelemetry()

    try MeshSourceCodec.encode(
        source,
        to: &firstSink,
        limits: firstLimits,
        telemetry: &firstTelemetry
    )
    try MeshSourceCodec.encode(
        source,
        to: &secondSink,
        limits: secondLimits,
        telemetry: &secondTelemetry
    )

    #expect(firstSink.data == secondSink.data)
    #expect(firstSink.maximumWrittenByteCount <= 7)
    #expect(secondSink.maximumWrittenByteCount <= 257)
    #expect(firstTelemetry.copiedBytes == UInt64(firstSink.data.count))
    #expect(secondTelemetry.copiedBytes == UInt64(secondSink.data.count))
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecCanonicalizesSignedFloatingPointZero() throws {
    var negativeZeroBuilder = MeshSourceBuilder(identity: "fixture.codec.zero")
    _ = try negativeZeroBuilder.addVertex(
        GeometryPoint3D(x: -0.0, y: -0.0, z: -0.0)
    )
    let negativeZeroSource = try negativeZeroBuilder.build()
    var positiveZeroBuilder = MeshSourceBuilder(identity: "fixture.codec.zero")
    _ = try positiveZeroBuilder.addVertex(
        GeometryPoint3D(x: 0.0, y: 0.0, z: 0.0)
    )
    let positiveZeroSource = try positiveZeroBuilder.build()

    #expect(negativeZeroSource == positiveZeroSource)
    #expect(
        try MeshSourceCodec.encode(negativeZeroSource)
            == MeshSourceCodec.encode(positiveZeroSource)
    )
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecRejectsCorruptTruncatedAndTrailingFrames() throws {
    let data = try MeshSourceCodec.encode(attributedMeshSource())

    var invalidMagic = data
    invalidMagic[0] ^= 0xFF
    #expect(meshSourceErrorCode { try MeshSourceCodec.decode(invalidMagic) } == .malformedPayload)

    var unsupportedVersion = data
    unsupportedVersion[8] = 2
    unsupportedVersion[9] = 0
    #expect(
        meshSourceErrorCode { try MeshSourceCodec.decode(unsupportedVersion) }
            == .unsupportedVersion
    )

    #expect(
        meshSourceErrorCode { try MeshSourceCodec.decode(Data(data.dropLast())) }
            == .truncatedPayload
    )

    var trailing = data
    trailing.append(0)
    #expect(meshSourceErrorCode { try MeshSourceCodec.decode(trailing) } == .malformedPayload)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecEnforcesResourceLimitsBeforeWriting() throws {
    let source = try attributedMeshSource()
    var sink = RecordingMeshSourceSink()
    var telemetry = GeometryCopyTelemetry()
    var blobLimits = MeshSourceCodecLimits.standard
    blobLimits.maximumBlobByteCount = MeshSourceBinaryFormat.headerByteCount

    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.encode(
                source,
                to: &sink,
                limits: blobLimits,
                telemetry: &telemetry
            )
        } == .resourceLimitExceeded
    )
    #expect(sink.data.isEmpty)
    #expect(!telemetry.didCopy)

    var elementLimits = MeshSourceCodecLimits.standard
    elementLimits.maximumElementCountPerBuffer = 2
    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.encode(
                source,
                to: &sink,
                limits: elementLimits,
                telemetry: &telemetry
            )
        } == .resourceLimitExceeded
    )

    var attributeLimits = MeshSourceCodecLimits.standard
    attributeLimits.maximumAttributeCount = 6
    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.encode(
                source,
                to: &sink,
                limits: attributeLimits,
                telemetry: &telemetry
            )
        } == .resourceLimitExceeded
    )

    var stringLimits = MeshSourceCodecLimits.standard
    stringLimits.maximumStringByteCount = 3
    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.encode(
                source,
                to: &sink,
                limits: stringLimits,
                telemetry: &telemetry
            )
        } == .resourceLimitExceeded
    )
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryDecoderEnforcesLimitsAndReportsInputFailure() throws {
    let data = try MeshSourceCodec.encode(attributedMeshSource())
    var elementLimits = MeshSourceCodecLimits.standard
    elementLimits.maximumElementCountPerBuffer = 2
    var limitedSource = ChunkedMeshSource(data: data, maximumReadByteCount: 11)
    var telemetry = GeometryCopyTelemetry()

    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.decode(
                from: &limitedSource,
                limits: elementLimits,
                telemetry: &telemetry
            )
        } == .resourceLimitExceeded
    )
    #expect(!telemetry.didCopy)

    var failingSource = FailingMeshSourceSource()
    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.decode(
                from: &failingSource,
                telemetry: &telemetry
            )
        } == .ioFailure
    )
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryEncoderReportsOutputFailureWithoutTelemetryCommit() throws {
    let source = try attributedMeshSource()
    var sink = FailingMeshSourceSink()
    var telemetry = GeometryCopyTelemetry()

    #expect(
        meshSourceErrorCode {
            try MeshSourceCodec.encode(
                source,
                to: &sink,
                telemetry: &telemetry
            )
        } == .ioFailure
    )
    #expect(!telemetry.didCopy)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBinaryCodecBoundsChunksAndRecordsOnlyRequiredFrameCopies() throws {
    var builder = MeshSourceBuilder(identity: "fixture.codec.large")
    let vertexCount = 20_000
    try builder.reserveCapacity(vertexCount: vertexCount, faceCount: 0, cornerCount: 0)
    for index in 0..<vertexCount {
        _ = try builder.addVertex(
            GeometryPoint3D(x: Double(index), y: Double(index % 13), z: 0)
        )
    }
    let source = try builder.build()
    var limits = MeshSourceCodecLimits.standard
    limits.maximumChunkByteCount = 4_096
    var sink = RecordingMeshSourceSink()
    var encodeTelemetry = GeometryCopyTelemetry()

    try MeshSourceCodec.encode(
        source,
        to: &sink,
        limits: limits,
        telemetry: &encodeTelemetry
    )

    var input = ChunkedMeshSource(data: sink.data, maximumReadByteCount: 997)
    var decodeTelemetry = GeometryCopyTelemetry()
    let decoded = try MeshSourceCodec.decode(
        from: &input,
        limits: limits,
        telemetry: &decodeTelemetry
    )

    #expect(decoded == source)
    #expect(sink.maximumWrittenByteCount <= limits.maximumChunkByteCount)
    #expect(input.maximumReturnedByteCount <= 997)
    #expect(input.maximumRequestedByteCount == limits.maximumChunkByteCount)
    #expect(
        encodeTelemetry.events == [
            GeometryCopyEvent(reason: .codecEncode, copiedBytes: UInt64(sink.data.count))
        ])
    #expect(
        decodeTelemetry.events == [
            GeometryCopyEvent(reason: .codecDecode, copiedBytes: UInt64(sink.data.count))
        ])
}

private func attributedMeshSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "fixture.codec.attributes")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [v0, v1, v2])
    try builder.setAttribute(
        attribute(
            id: "attribute.boolean",
            name: "Boolean",
            domain: .vertex,
            valueType: .boolean,
            interpolation: .none,
            values: .boolean(GeometryBuffer([true, false, true]))
        ))
    try builder.setAttribute(
        attribute(
            id: "attribute.int32",
            name: "Integer",
            domain: .face,
            valueType: .int32,
            interpolation: .constant,
            values: .int32(GeometryBuffer([Int32(-7)]))
        ))
    try builder.setAttribute(
        attribute(
            id: "attribute.float32",
            name: "Float",
            domain: .edge,
            valueType: .float32,
            interpolation: .nearest,
            values: .float32(GeometryBuffer([Float(1.25), Float(-2.5), Float(3.75)]))
        ))
    try builder.setAttribute(
        attribute(
            id: "attribute.float64",
            name: "Double",
            domain: .corner,
            valueType: .float64,
            interpolation: .linear,
            values: .float64(GeometryBuffer([1.0, 2.0, 3.0]))
        ))
    try builder.setAttribute(
        attribute(
            id: "attribute.vector2",
            name: "Vector 2",
            domain: .corner,
            valueType: .vector2,
            interpolation: .linear,
            values: .vector2(
                GeometryBuffer([
                    GeometryVector2D(x: 0, y: 0),
                    GeometryVector2D(x: 1, y: 0),
                    GeometryVector2D(x: 0, y: 1),
                ]))
        ))
    try builder.setAttribute(
        attribute(
            id: "attribute.vector3",
            name: "Vector 3",
            domain: .vertex,
            valueType: .vector3,
            interpolation: .linear,
            values: .vector3(
                GeometryBuffer([
                    GeometryPoint3D(x: 0, y: 0, z: 1),
                    GeometryPoint3D(x: 0, y: 1, z: 0),
                    GeometryPoint3D(x: 1, y: 0, z: 0),
                ]))
        ))
    try builder.setAttribute(
        GeometryAttributeLayer(
            descriptor: GeometryAttributeDescriptor(
                id: "attribute.vector4.sparse",
                name: "Vector 4 Sparse",
                domain: .vertex,
                valueType: .vector4,
                interpolation: .linear,
                isSparse: true
            ),
            values: .vector4(
                GeometryBuffer([
                    GeometryVector4D(x: 1, y: 2, z: 3, w: 4),
                    GeometryVector4D(x: 5, y: 6, z: 7, w: 8),
                ])),
            indices: GeometryBuffer([UInt32(0), UInt32(2)])
        )
    )
    return try builder.build()
}

private func attribute(
    id: GeometryAttributeID,
    name: String,
    domain: GeometryAttributeDomain,
    valueType: GeometryAttributeValueType,
    interpolation: GeometryAttributeInterpolation,
    values: GeometryAttributeStorage
) -> GeometryAttributeLayer {
    GeometryAttributeLayer(
        descriptor: GeometryAttributeDescriptor(
            id: id,
            name: name,
            domain: domain,
            valueType: valueType,
            interpolation: interpolation
        ),
        values: values
    )
}

private func meshSourceErrorCode<T>(
    _ operation: () throws -> T
) -> MeshSourceError.Code? {
    do {
        _ = try operation()
        return nil
    } catch let error as MeshSourceError {
        return error.code
    } catch {
        return nil
    }
}

private struct RecordingMeshSourceSink: MeshSourceChunkSink {
    private(set) var data = Data()
    private(set) var maximumWrittenByteCount = 0

    mutating func write(_ chunk: borrowing Span<UInt8>) throws {
        maximumWrittenByteCount = max(maximumWrittenByteCount, chunk.count)
        chunk.withUnsafeBytes { data.append(contentsOf: $0) }
    }
}

private struct ChunkedMeshSource: MeshSourceChunkSource {
    private let data: Data
    private let maximumReadByteCount: Int
    private var offset = 0
    private(set) var maximumRequestedByteCount = 0
    private(set) var maximumReturnedByteCount = 0

    init(data: Data, maximumReadByteCount: Int) {
        self.data = data
        self.maximumReadByteCount = maximumReadByteCount
    }

    mutating func read(into buffer: inout MutableSpan<UInt8>) throws -> Int {
        maximumRequestedByteCount = max(maximumRequestedByteCount, buffer.count)
        let count = min(maximumReadByteCount, buffer.count, data.count - offset)
        guard count > 0 else {
            return 0
        }
        data.withUnsafeBytes { sourceBytes in
            buffer.withUnsafeMutableBytes { destinationBytes in
                let source = UnsafeRawBufferPointer(
                    start: sourceBytes.baseAddress?.advanced(by: offset),
                    count: count
                )
                destinationBytes.copyMemory(from: source)
            }
        }
        offset += count
        maximumReturnedByteCount = max(maximumReturnedByteCount, count)
        return count
    }
}

private enum CodecFixtureFailure: Error {
    case intentional
}

private struct FailingMeshSourceSink: MeshSourceChunkSink {
    mutating func write(_ chunk: borrowing Span<UInt8>) throws {
        throw CodecFixtureFailure.intentional
    }
}

private struct FailingMeshSourceSource: MeshSourceChunkSource {
    mutating func read(into buffer: inout MutableSpan<UInt8>) throws -> Int {
        throw CodecFixtureFailure.intentional
    }
}
