import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaProjectPackage

@Test(.timeLimit(.minutes(1)))
func projectPackageSaveLoadRoundTripUsesBoundedStreamingAndReusesBlobPayload() throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("source.swcad")
        let reusedURL = directory.appendingPathComponent("reused.swcad")
        let mesh = try looseVertexSource(id: "mesh.large", count: 20_000)
        let project = try ProjectSourceModel(
            id: "project.large",
            name: "Large",
            meshSources: [mesh.identity: mesh]
        )
        let store = ProjectPackageStore()

        let first = try store.save(try ProjectPackageDocument(source: project), to: sourceURL)
        #expect(first.document.source == project)
        #expect(first.report.encodedSourceBlobCount == 1)
        #expect(first.report.reusedSourceBlobCount == 0)
        #expect(first.report.maximumWriteChunkByteCount <= 64 * 1_024)
        #expect(first.document.loadReport?.maximumReadChunkByteCount ?? 0 <= 64 * 1_024)
        #expect(
            first.report.geometryCopyTelemetry.events.filter {
                $0.reason == .codecEncode
            }.count == 2
        )

        let second = try store.save(first.document, to: reusedURL)
        #expect(second.document.source == project)
        #expect(second.documentContentIdentity == first.documentContentIdentity)
        #expect(second.report.encodedSourceBlobCount == 0)
        #expect(second.report.reusedSourceBlobCount == 1)
        #expect(second.report.maximumWriteChunkByteCount <= 64 * 1_024)
        #expect(
            second.report.geometryCopyTelemetry.events.filter {
                $0.reason == .codecEncode
            }.count == 1
        )

        let firstPayload = try activeBlobPayload(in: first.document)
        let secondPayload = try activeBlobPayload(in: second.document)
        #expect(firstPayload == secondPayload)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackagePreservesOpaqueAdjunctsAndGarbageCollectsOnlyExplicitly() throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("source.swcad")
        let preservedURL = directory.appendingPathComponent("preserved.swcad")
        let collectedURL = directory.appendingPathComponent("collected.swcad")
        let firstMesh = try triangleSource(id: "mesh.first", xOffset: 0)
        let secondMesh = try triangleSource(id: "mesh.second", xOffset: 2)
        let original = try ProjectSourceModel(
            id: "project.preservation",
            name: "Preservation",
            meshSources: [
                firstMesh.identity: firstMesh,
                secondMesh.identity: secondMesh,
            ]
        )
        let retainedSource = try ProjectSourceModel(
            id: original.id,
            name: original.name,
            meshSources: [firstMesh.identity: firstMesh]
        )
        let store = ProjectPackageStore()
        _ = try store.save(try ProjectPackageDocument(source: original), to: sourceURL)
        try addAdjunct(
            path: "extensions/example/vendor.bin",
            data: Data([1, 3, 3, 7]),
            to: sourceURL
        )

        let loaded = try store.load(from: sourceURL)
        let replaced = try loaded.replacingSource(retainedSource)
        let preserved = try store.save(replaced, to: preservedURL)
        #expect(preserved.document.source == retainedSource)
        #expect(preserved.report.preservedAdjunctCount == 1)
        #expect(preserved.report.reusedSourceBlobCount == 2)
        #expect(preserved.document.manifest?.sourceEntries.count == 3)
        #expect(
            try adjunctPayload(
                path: "extensions/example/vendor.bin",
                in: preserved.document
            ) == Data([1, 3, 3, 7])
        )

        let collected = try store.save(
            preserved.document.garbageCollectingUnreferencedSourceBlobs(),
            to: collectedURL
        )
        #expect(collected.document.manifest?.sourceEntries.count == 2)
        #expect(
            try adjunctPayload(
                path: "extensions/example/vendor.bin",
                in: collected.document
            ) == Data([1, 3, 3, 7])
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageLoadRejectsPayloadCorruptionAndArchiveTraversal() throws {
    try withTemporaryDirectory { directory in
        let corruptedURL = directory.appendingPathComponent("corrupted.swcad")
        let traversalURL = directory.appendingPathComponent("traversal.swcad")
        let store = ProjectPackageStore()
        let project = try singleTriangleProject()
        let saved = try store.save(try ProjectPackageDocument(source: project), to: corruptedURL)
        let blobEntry = try #require(
            saved.document.manifest?.sourceEntries.first {
                $0.path != ProjectPackageManifest.sourceMetadataPath
            }
        )
        let descriptor = try #require(saved.document.backing?.entries[blobEntry.path])
        var corruptedData = try Data(contentsOf: corruptedURL)
        corruptedData[descriptor.payloadRange.lowerBound] ^= 0xff
        try corruptedData.write(to: corruptedURL)
        #expect(projectPackageErrorCode { try store.load(from: corruptedURL) } == .integrityMismatch)

        _ = try store.save(try ProjectPackageDocument(source: project), to: traversalURL)
        try addAdjunct(path: "records/x", data: Data([9]), to: traversalURL)
        var traversalData = try Data(contentsOf: traversalURL)
        let replacements = replaceAll(
            Data("records/x".utf8),
            with: Data("../evilxx".utf8),
            in: &traversalData
        )
        #expect(replacements == 2)
        try traversalData.write(to: traversalURL)
        #expect(projectPackageErrorCode { try store.load(from: traversalURL) } == .invalidEntryPath)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageLoadRejectsInconsistentStoredEntryLength() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("length.swcad")
        let store = ProjectPackageStore()
        let saved = try store.save(
            try ProjectPackageDocument(source: singleTriangleProject()),
            to: url
        )
        let descriptor = try #require(
            saved.document.backing?.entries[ProjectPackageManifest.sourceMetadataPath]
        )
        var data = try Data(contentsOf: url)
        let uncompressedSizeOffset = descriptor.localRecordRange.lowerBound + 22
        data[uncompressedSizeOffset] ^= 0x01
        try data.write(to: url)

        #expect(projectPackageErrorCode { try store.load(from: url) } == .malformedArchive)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageArchiveRejectsDuplicatesAndConfiguredLimits() throws {
    var sink = ProjectPackageDataSink()
    var writer = try ProjectPackageArchiveWriter(
        sink: sink,
        limits: .standard
    )
    try writer.writeDataEntry(path: "manifest.json", data: Data([1]))
    #expect(projectPackageErrorCode {
        try writer.writeDataEntry(path: "manifest.json", data: Data([2]))
    } == .duplicateEntry)
    sink = writer.sink
    #expect(sink.writtenByteCount > 0)

    let mesh = try triangleSource(id: "mesh.limit", xOffset: 0)
    let project = try ProjectSourceModel(
        id: "project.limit",
        name: "Limit",
        meshSources: [mesh.identity: mesh]
    )
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumArchiveByteCount = 1_024
    limits.maximumManifestByteCount = 512
    limits.maximumSourceMetadataByteCount = 512
    limits.maximumSourceBlobByteCount = 512
    limits.maximumPreservedAdjunctByteCount = 512
    limits.maximumChunkByteCount = 128
    limits.meshSource.maximumBlobByteCount = 512
    limits.meshSource.maximumChunkByteCount = 128
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageSourcePlanner(limits: limits).plan(project)
    } == .resourceLimitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageFailedAtomicReplacementPreservesDestinationAndCleansTemporaryFile() throws {
    try withTemporaryDirectory { directory in
        let destinationURL = directory.appendingPathComponent("atomic.swcad")
        let original = try singleTriangleProject()
        let replacementMesh = try triangleSource(id: "mesh.triangle", xOffset: 5)
        let replacement = try ProjectSourceModel(
            id: original.id,
            name: original.name,
            meshSources: [replacementMesh.identity: replacementMesh]
        )
        let store = ProjectPackageStore()
        let saved = try store.save(
            try ProjectPackageDocument(source: original),
            to: destinationURL
        )
        let replaced = try store.save(
            saved.document.replacingSource(replacement),
            to: destinationURL
        )
        #expect(replaced.document.source == replacement)

        let failingStore = ProjectPackageStore(
            limits: .standard,
            replaceFile: { _, _ in
                throw ProjectPackageError(
                    code: .atomicSaveFailure,
                    message: "Intentional replacement failure."
                )
            }
        )

        #expect(projectPackageErrorCode {
            _ = try failingStore.save(
                replaced.document.replacingSource(original),
                to: destinationURL
            )
        } == .atomicSaveFailure)
        #expect(try store.load(from: destinationURL).source == replacement)
        let temporaryPrefix = ".\(destinationURL.lastPathComponent)."
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).filter { $0.hasPrefix(temporaryPrefix) && $0.hasSuffix(".tmp") }
        #expect(remainingNames.isEmpty)
    }
}

private func singleTriangleProject() throws -> ProjectSourceModel {
    let mesh = try triangleSource(id: "mesh.triangle", xOffset: 0)
    return try ProjectSourceModel(
        id: "project.round-trip",
        name: "Round Trip",
        meshSources: [mesh.identity: mesh]
    )
}

private func triangleSource(id: GeometrySourceID, xOffset: Double) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: id)
    let first = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: xOffset + 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func looseVertexSource(id: GeometrySourceID, count: Int) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: id)
    try builder.reserveCapacity(vertexCount: count, faceCount: 0, cornerCount: 0)
    for index in 0..<count {
        _ = try builder.addVertex(
            GeometryPoint3D(x: Double(index), y: Double(index % 17), z: 0)
        )
    }
    return try builder.build()
}

private func activeBlobPayload(in document: ProjectPackageDocument) throws -> Data {
    let manifest = try #require(document.manifest)
    let backing = try #require(document.backing)
    let entry = try #require(
        manifest.sourceEntries.first {
            $0.path != ProjectPackageManifest.sourceMetadataPath
        }
    )
    let descriptor = try #require(backing.entries[entry.path])
    return backing.data.subdata(in: descriptor.payloadRange)
}

private func adjunctPayload(
    path: String,
    in document: ProjectPackageDocument
) throws -> Data {
    let backing = try #require(document.backing)
    let descriptor = try #require(backing.entries[path])
    return backing.data.subdata(in: descriptor.payloadRange)
}

private func addAdjunct(path: String, data: Data, to url: URL) throws {
    let originalData = try Data(contentsOf: url, options: [.mappedIfSafe])
    let limits = ProjectPackageResourceLimits.standard
    let backing = try ProjectPackageArchiveReader(limits: limits).read(originalData)
    var writer = try ProjectPackageArchiveWriter(
        sink: ProjectPackageDataSink(),
        limits: limits
    )
    let paths = (Array(backing.entries.keys) + [path]).sorted()
    for outputPath in paths {
        if outputPath == path {
            try writer.writeDataEntry(path: path, data: data)
        } else {
            let descriptor = try #require(backing.entries[outputPath])
            try writer.writeRetainedEntry(descriptor, from: backing)
        }
    }
    try writer.finish()
    try writer.sink.data.write(to: url)
}

private func replaceAll(
    _ source: Data,
    with replacement: Data,
    in data: inout Data
) -> Int {
    precondition(source.count == replacement.count)
    guard source.count > 0, data.count >= source.count else {
        return 0
    }
    var replacementCount = 0
    var offset = 0
    while offset <= data.count - source.count {
        if data[offset..<(offset + source.count)].elementsEqual(source) {
            data.replaceSubrange(offset..<(offset + source.count), with: replacement)
            replacementCount += 1
            offset += source.count
        } else {
            offset += 1
        }
    }
    return replacementCount
}

private func withTemporaryDirectory<Result>(
    _ body: (URL) throws -> Result
) throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-package-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try body(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let cleanupError {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}

private func projectPackageErrorCode<Result>(
    _ operation: () throws -> Result
) -> ProjectPackageError.Code? {
    do {
        _ = try operation()
        return nil
    } catch let error as ProjectPackageError {
        return error.code
    } catch {
        return nil
    }
}
