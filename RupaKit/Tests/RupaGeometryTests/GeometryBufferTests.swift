import Foundation
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func geometryBufferViewsAndLeasesRetainStorageWithoutCopies() throws {
    var telemetry = GeometryCopyTelemetry()
    let view: GeometryBufferView<Int32> = try {
        let buffer = GeometryBuffer([Int32(1), 2, 3, 4])
        return try buffer.view(1..<3, telemetry: &telemetry)
    }()
    let lease: GeometryBufferLease<Int32> = try {
        let buffer = GeometryBuffer([Int32(5), 6, 7, 8])
        return try buffer.lease(1..<4, telemetry: &telemetry)
    }()

    #expect(Array(view) == [2, 3])
    #expect(view.startIndex == 1)
    #expect(view.endIndex == 3)
    #expect(Array(lease) == [6, 7, 8])
    #expect(telemetry.copiedBytes == 0)
    #expect(!telemetry.didCopy)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderPreservesOriginalAndReportsTouchedChunkCopy() throws {
    let buffer = GeometryBuffer([1, 2, 3, 4])
    var builder = buffer.makeBuilder()
    #expect(builder.telemetry.copiedBytes == 0)
    try builder.replaceSubrange(1..<2, with: [20])
    let edited = builder.build()

    #expect(Array(buffer) == [1, 2, 3, 4])
    #expect(Array(edited) == [1, 20, 3, 4])
    #expect(builder.telemetry.didCopy)
    #expect(builder.telemetry.events.first?.reason == .sourceEdit)
    #expect(builder.telemetry.copiedBytes == UInt64(4 * MemoryLayout<Int>.stride))
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderPreservesEveryUntouchedChunkIdentity() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let original = GeometryBuffer(
        Array(0..<12),
        preferredChunkByteCount: chunkByteCount
    )
    let originalIdentities = original.storage.chunkIdentities
    var builder = original.makeBuilder()

    try builder.replaceSubrange(5..<6, with: [50])
    let edited = builder.build()
    let editedIdentities = edited.storage.chunkIdentities

    #expect(originalIdentities.count == 3)
    #expect(originalIdentities[0] == editedIdentities[0])
    #expect(originalIdentities[1] != editedIdentities[1])
    #expect(originalIdentities[2] == editedIdentities[2])
    #expect(builder.telemetry.copiedBytes == UInt64(chunkByteCount))
    #expect(original[5] == 5)
    #expect(edited[5] == 50)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderCopiesAnEditedChunkOnlyOncePerEditSession() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let original = GeometryBuffer(
        Array(0..<12),
        preferredChunkByteCount: chunkByteCount
    )
    var builder = original.makeBuilder()

    try builder.replaceSubrange(4..<5, with: [40])
    try builder.replaceSubrange(6..<7, with: [60])
    let edited = builder.build()

    #expect(builder.telemetry.copiedBytes == UInt64(chunkByteCount))
    #expect(edited[4] == 40)
    #expect(edited[6] == 60)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderAccountsForCopyAfterPublishingASnapshot() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let original = GeometryBuffer(
        Array(0..<8),
        preferredChunkByteCount: chunkByteCount
    )
    var builder = original.makeBuilder()

    try builder.replaceSubrange(1..<2, with: [10])
    let firstSnapshot = builder.build()
    try builder.replaceSubrange(2..<3, with: [20])
    let secondSnapshot = builder.build()

    #expect(Array(firstSnapshot) == [0, 10, 2, 3, 4, 5, 6, 7])
    #expect(Array(secondSnapshot) == [0, 10, 20, 3, 4, 5, 6, 7])
    #expect(builder.telemetry.copiedBytes == UInt64(chunkByteCount * 2))
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuildersRemainIsolatedAcrossIndependentEditSessions() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let original = GeometryBuffer(
        Array(0..<12),
        preferredChunkByteCount: chunkByteCount
    )
    var first = original.makeBuilder()
    var second = original.makeBuilder()

    try first.replaceSubrange(4..<5, with: [40])
    try second.replaceSubrange(4..<5, with: [400])
    let firstResult = first.build()
    let secondResult = second.build()

    #expect(original[4] == 4)
    #expect(firstResult[4] == 40)
    #expect(secondResult[4] == 400)
    #expect(first.telemetry.copiedBytes == UInt64(chunkByteCount))
    #expect(second.telemetry.copiedBytes == UInt64(chunkByteCount))
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderPreservesUntouchedDirectoryPageIdentities() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let chunkCount = GeometryBufferLayout.chunkDirectoryPageCapacity * 2 + 1
    let original = GeometryBuffer(
        Array(0..<(chunkCount * 4)),
        preferredChunkByteCount: chunkByteCount
    )
    let originalPageIdentities = original.storage.pageIdentities
    var builder = original.makeBuilder()
    let editedIndex = (GeometryBufferLayout.chunkDirectoryPageCapacity + 1) * 4

    try builder.replaceSubrange(editedIndex..<(editedIndex + 1), with: [-1])
    let edited = builder.build()
    let editedPageIdentities = edited.storage.pageIdentities

    #expect(originalPageIdentities.count == 3)
    #expect(originalPageIdentities[0] == editedPageIdentities[0])
    #expect(originalPageIdentities[1] != editedPageIdentities[1])
    #expect(originalPageIdentities[2] == editedPageIdentities[2])
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferDefaultChunkSizeSatisfiesTheLocalEditCopyBudget() throws {
    let values = (0..<100_000).map {
        GeometryPoint3D(x: Double($0), y: 0, z: 0)
    }
    let original = GeometryBuffer(values)
    var builder = original.makeBuilder()

    try builder.replaceSubrange(
        50_000..<50_001,
        with: CollectionOfOne(GeometryPoint3D(x: -1, y: -2, z: -3))
    )
    let edited = builder.build()

    #expect(edited[50_000].x == -1)
    #expect(
        builder.telemetry.copiedBytes
            <= GeometryBufferPerformanceContract.maximumCopiedBytesPerLocalEdit
    )
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderAppendCopiesOnlyAPartialFinalChunk() throws {
    let chunkByteCount = 4 * MemoryLayout<Int32>.stride
    let partial = GeometryBuffer(
        [Int32(1), 2, 3],
        preferredChunkByteCount: chunkByteCount
    )
    var partialBuilder = partial.makeBuilder()
    try partialBuilder.append(4)
    let completed = partialBuilder.build()

    #expect(Array(completed) == [1, 2, 3, 4])
    #expect(
        partialBuilder.telemetry.copiedBytes
            == UInt64(3 * MemoryLayout<Int32>.stride)
    )

    let completedIdentity = completed.storage.chunkIdentities[0]
    var fullBuilder = completed.makeBuilder()
    try fullBuilder.append(5)
    let extended = fullBuilder.build()

    #expect(Array(extended) == [1, 2, 3, 4, 5])
    #expect(fullBuilder.telemetry.copiedBytes == 0)
    #expect(extended.storage.chunkIdentities[0] == completedIdentity)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferVariableLengthReplacementPreservesCompletePrefixChunks() throws {
    let chunkByteCount = 4 * MemoryLayout<Int>.stride
    let original = GeometryBuffer(
        Array(0..<12),
        preferredChunkByteCount: chunkByteCount
    )
    let originalIdentities = original.storage.chunkIdentities
    var builder = original.makeBuilder()

    try builder.replaceSubrange(5..<7, with: [50, 51, 52])
    let edited = builder.build()

    #expect(Array(edited) == [0, 1, 2, 3, 4, 50, 51, 52, 7, 8, 9, 10, 11])
    #expect(original.storage.chunkIdentities[0] == edited.storage.chunkIdentities[0])
    #expect(originalIdentities[1] != edited.storage.chunkIdentities[1])
    #expect(builder.telemetry.copiedBytes == UInt64(6 * MemoryLayout<Int>.stride))
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferLeaseSupportsConcurrentImmutableReads() async throws {
    let values = (0..<4_096).map(Int64.init)
    let lease = GeometryBuffer(
        values,
        preferredChunkByteCount: 4 * 1_024
    ).lease()
    let expected = values.reduce(Int64.zero, +)

    let results = await withTaskGroup(of: Int64.self, returning: [Int64].self) { group in
        for _ in 0..<16 {
            group.addTask {
                lease.reduce(Int64.zero, +)
            }
        }
        var results: [Int64] = []
        for await result in group {
            results.append(result)
        }
        return results
    }

    #expect(results.count == 16)
    #expect(results.allSatisfy { $0 == expected })
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferContiguousChunkAccessIsAlignedAndRangeBounded() throws {
    let values = (0..<10).map {
        GeometryPoint3D(x: Double($0), y: Double($0 + 1), z: Double($0 + 2))
    }
    let buffer = GeometryBuffer(
        values,
        preferredChunkByteCount: 4 * MemoryLayout<GeometryPoint3D>.stride
    )
    let view = try buffer.view(2..<9)
    var visitedElementCount = 0
    var visitedChunkCount = 0

    view.withContiguousChunks { span in
        visitedElementCount += span.count
        visitedChunkCount += 1
        span.withUnsafeBufferPointer { pointer in
            let address = Int(bitPattern: pointer.baseAddress)
            #expect(address % MemoryLayout<GeometryPoint3D>.alignment == 0)
        }
    }

    #expect(visitedElementCount == 7)
    #expect(visitedChunkCount == 3)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferContentHashIsChunkIndependentCanonicalAndBounded() throws {
    let values = [Float(-0.0), 1.5, -2.25, 4.0]
    let smallChunks = GeometryBuffer(
        values,
        preferredChunkByteCount: MemoryLayout<Float>.stride
    )
    let largeChunks = GeometryBuffer(
        [Float(0.0), 1.5, -2.25, 4.0],
        preferredChunkByteCount: 64 * 1_024
    )
    let first = try smallChunks.contentFingerprint(maximumElementCount: 4)
    let second = try largeChunks.contentFingerprint(maximumElementCount: 4)

    #expect(first == second)
    #expect(first.algorithm == "sha256-rupa-geometry-buffer-v1")
    #expect(throws: GeometryBufferError.self) {
        _ = try smallChunks.contentFingerprint(maximumElementCount: 3)
    }
    #expect(throws: GeometryBufferError.self) {
        _ = try GeometryBuffer([Float.infinity]).contentFingerprint(maximumElementCount: 1)
    }
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferCodableStreamsTheFlatWireRepresentationAcrossChunks() throws {
    let original = GeometryBuffer(
        (0..<20).map(Int32.init),
        preferredChunkByteCount: 4 * MemoryLayout<Int32>.stride
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GeometryBuffer<Int32>.self, from: data)

    #expect(decoded == original)
    #expect(String(decoding: data, as: UTF8.self).hasPrefix("[0,1,2,3"))
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferMaterializationReportsOwnedBytes() throws {
    var telemetry = GeometryCopyTelemetry()
    let buffer = try GeometryBuffer(
        materializing: [Int32(1), 2, 3, 4],
        telemetry: &telemetry
    )

    #expect(buffer.count == 4)
    #expect(
        telemetry.events == [
            GeometryCopyEvent(
                reason: .bufferMaterialization,
                copiedBytes: UInt64(4 * MemoryLayout<Int32>.stride)
            )
        ])
}

@Test(.timeLimit(.minutes(1)))
func geometryCopyTelemetryPreservesItsWireShapeAndRejectsOverflow() throws {
    let original = try GeometryCopyTelemetry(events: [
        GeometryCopyEvent(reason: .sourceEdit, copiedBytes: 16),
        GeometryCopyEvent(reason: .bufferMaterialization, copiedBytes: 32),
    ])

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GeometryCopyTelemetry.self, from: data)

    #expect(decoded == original)
    #expect(String(decoding: data, as: UTF8.self).hasPrefix("{\"events\":"))
    #expect(throws: GeometryBufferError.self) {
        _ = try GeometryCopyTelemetry(events: [
            GeometryCopyEvent(reason: .sourceEdit, copiedBytes: UInt64.max),
            GeometryCopyEvent(reason: .sourceEdit, copiedBytes: 1),
        ])
    }
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferRejectsOutOfBoundsLeaseAndBuilderRanges() throws {
    let buffer = GeometryBuffer([Int32(1), 2, 3])
    var builder = buffer.makeBuilder()

    #expect(throws: GeometryBufferError.self) {
        _ = try buffer.lease(2..<4)
    }
    #expect(throws: GeometryBufferError.self) {
        try builder.replaceSubrange(3..<4, with: [4])
    }
}
