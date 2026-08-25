import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaProjectPackage

@Test(.timeLimit(.minutes(1)))
func projectPackageRoundTripsCADOnlyCADAndMeshAndMeshOnlySources() throws {
    try withTemporaryDirectory { directory in
        let store = ProjectPackageStore()
        let product = try fixtureProductSource("authority")
        let cad = try fixtureCADSource("authority")
        let mesh = try authoredTriangle(id: "mesh.authority", xOffset: 0)

        let cadOnly = try store.save(
            ProjectPackageDocument(
                documentID: "project.cad-only",
                productSource: product,
                cadSource: cad
            ),
            to: directory.appendingPathComponent("cad-only.rupa")
        )
        #expect(cadOnly.document.productSource == product)
        #expect(cadOnly.document.cadSource == cad)
        #expect(cadOnly.document.authoredMeshAssets.isEmpty)
        try expectSourcePaths(
            in: cadOnly.document,
            includeCAD: true,
            includeMesh: false
        )

        let cadAndMesh = try store.save(
            ProjectPackageDocument(
                documentID: "project.cad-mesh",
                productSource: product,
                cadSource: cad,
                authoredMeshAssets: [mesh.id: mesh]
            ),
            to: directory.appendingPathComponent("cad-mesh.rupa")
        )
        #expect(cadAndMesh.document.cadSource == cad)
        #expect(cadAndMesh.document.authoredMeshAssets == [mesh.id: mesh])
        try expectSourcePaths(
            in: cadAndMesh.document,
            includeCAD: true,
            includeMesh: true
        )

        let meshOnly = try store.save(
            ProjectPackageDocument(
                documentID: "project.mesh-only",
                productSource: product,
                cadSource: nil,
                authoredMeshAssets: [mesh.id: mesh]
            ),
            to: directory.appendingPathComponent("mesh-only.rupa")
        )
        #expect(meshOnly.document.productSource == product)
        #expect(meshOnly.document.cadSource == nil)
        #expect(meshOnly.document.authoredMeshAssets == [mesh.id: mesh])
        try expectSourcePaths(
            in: meshOnly.document,
            includeCAD: false,
            includeMesh: true
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageRoundTripsAuthoredMeshProvenance() throws {
    try withTemporaryDirectory { directory in
        let mesh = try triangleSource(id: "mesh.derived", xOffset: 0)
        let sourceIdentity = try ContentIdentity(
            domain: AuthoredMeshProvenance.cadSourceIdentityDomain,
            fingerprint: .sha256(
                algorithm: "sha256-test-cad-v1",
                data: Data("cad-revision".utf8)
            )
        )
        let asset = try AuthoredMeshAsset(
            source: mesh,
            provenance: .derivedFromCAD(
                representationID: "representation.cad.body",
                sourceIdentity: sourceIdentity
            )
        )
        let saved = try ProjectPackageStore().save(
            ProjectPackageDocument(
                documentID: "project.provenance",
                productSource: fixtureProductSource("provenance"),
                cadSource: fixtureCADSource("provenance"),
                authoredMeshAssets: [asset.id: asset]
            ),
            to: directory.appendingPathComponent("provenance.rupa")
        )

        #expect(saved.document.authoredMeshAssets[asset.id]?.provenance == asset.provenance)
        #expect(saved.document.authoredMeshAssets[asset.id]?.source == mesh)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageSaveLoadUsesBoundedStreamingAndReusesBlobPayload() throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("source.rupa")
        let reusedURL = directory.appendingPathComponent("reused.rupa")
        let mesh = try AuthoredMeshAsset(
            source: looseVertexSource(id: "mesh.large", count: 20_000),
            provenance: .created
        )
        let document = try ProjectPackageDocument(
            documentID: "project.large",
            productSource: fixtureProductSource("large"),
            cadSource: nil,
            authoredMeshAssets: [mesh.id: mesh]
        )
        let store = ProjectPackageStore()

        let first = try store.save(document, to: sourceURL)
        #expect(first.document.authoredMeshAssets == [mesh.id: mesh])
        #expect(first.report.encodedSourceBlobCount == 1)
        #expect(first.report.reusedSourceBlobCount == 0)
        #expect(first.report.maximumWriteChunkByteCount <= 64 * 1_024)
        #expect(first.document.loadReport?.maximumReadChunkByteCount ?? 0 <= 64 * 1_024)
        #expect(first.report.geometryCopyTelemetry.events.filter {
            $0.reason == .codecEncode
        }.count == 2)

        let second = try store.save(first.document, to: reusedURL)
        #expect(second.documentContentIdentity == first.documentContentIdentity)
        #expect(second.report.encodedSourceBlobCount == 0)
        #expect(second.report.reusedSourceBlobCount == 1)
        #expect(second.report.maximumWriteChunkByteCount <= 64 * 1_024)
        #expect(second.report.geometryCopyTelemetry.events.filter {
            $0.reason == .codecEncode
        }.count == 1)
        #expect(try activeBlobPayload(in: first.document) == activeBlobPayload(in: second.document))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageEncodingAndEntryOrderAreDeterministic() throws {
    try withTemporaryDirectory { directory in
        let firstURL = directory.appendingPathComponent("first.rupa")
        let secondURL = directory.appendingPathComponent("second.rupa")
        let first = try authoredTriangle(id: "mesh.first", xOffset: 0)
        let second = try authoredTriangle(id: "mesh.second", xOffset: 2)
        let document = try ProjectPackageDocument(
            documentID: "project.deterministic",
            productSource: fixtureProductSource("deterministic"),
            cadSource: fixtureCADSource("deterministic"),
            authoredMeshAssets: [second.id: second, first.id: first]
        )
        let store = ProjectPackageStore()

        _ = try store.save(document, to: firstURL)
        _ = try store.save(document, to: secondURL)

        #expect(try Data(contentsOf: firstURL) == Data(contentsOf: secondURL))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackagePreservesOpaqueAdjunctsAndGarbageCollectsOnlyExplicitly() throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("source.rupa")
        let preservedURL = directory.appendingPathComponent("preserved.rupa")
        let collectedURL = directory.appendingPathComponent("collected.rupa")
        let first = try authoredTriangle(id: "mesh.first", xOffset: 0)
        let second = try authoredTriangle(id: "mesh.second", xOffset: 2)
        let store = ProjectPackageStore()
        _ = try store.save(
            ProjectPackageDocument(
                documentID: "project.preservation",
                productSource: fixtureProductSource("preservation"),
                cadSource: nil,
                authoredMeshAssets: [first.id: first, second.id: second]
            ),
            to: sourceURL
        )
        try addAdjunct(
            path: "adjuncts/example/vendor.bin",
            data: Data([1, 3, 3, 7]),
            to: sourceURL
        )

        let loaded = try store.load(from: sourceURL)
        let replaced = try loaded.replacingSources(
            documentID: loaded.documentID,
            product: loaded.productSource,
            cad: loaded.cadSource,
            authoredMeshAssets: [first.id: first]
        )
        let preserved = try store.save(replaced, to: preservedURL)
        #expect(preserved.document.authoredMeshAssets == [first.id: first])
        #expect(preserved.report.preservedAdjunctCount == 1)
        #expect(preserved.report.reusedSourceBlobCount == 2)
        #expect(preserved.document.manifest?.sourceEntries.count == 4)
        #expect(try adjunctPayload(
            path: "adjuncts/example/vendor.bin",
            in: preserved.document
        ) == Data([1, 3, 3, 7]))

        let collected = try store.save(
            preserved.document.garbageCollectingUnreferencedSourceBlobs(),
            to: collectedURL
        )
        #expect(collected.document.manifest?.sourceEntries.count == 3)
        #expect(try adjunctPayload(
            path: "adjuncts/example/vendor.bin",
            in: collected.document
        ) == Data([1, 3, 3, 7]))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageLoadRejectsPayloadCorruptionArchiveTraversalAndInvalidLength() throws {
    try withTemporaryDirectory { directory in
        let corruptedURL = directory.appendingPathComponent("corrupted.rupa")
        let missingURL = directory.appendingPathComponent("missing.rupa")
        let traversalURL = directory.appendingPathComponent("traversal.rupa")
        let lengthURL = directory.appendingPathComponent("length.rupa")
        let store = ProjectPackageStore()
        let document = try fixtureMeshOnlyDocument(seed: "corruption")

        let saved = try store.save(document, to: corruptedURL)
        let blobEntry = try #require(saved.document.manifest?.sourceEntries.first {
            $0.path.hasPrefix(ProjectSourceBlobReference.pathPrefix)
        })
        let descriptor = try #require(saved.document.backing?.entries[blobEntry.path])
        var corruptedData = try Data(contentsOf: corruptedURL)
        corruptedData[descriptor.payloadRange.lowerBound] ^= 0xff
        try corruptedData.write(to: corruptedURL)
        #expect(projectPackageErrorCode { try store.load(from: corruptedURL) }
            == .integrityMismatch)

        let missing = try store.save(document, to: missingURL)
        let missingBlobPath = try #require(missing.document.manifest?.sourceEntries.first {
            $0.path.hasPrefix(ProjectSourceBlobReference.pathPrefix)
        }?.path)
        try removeEntry(path: missingBlobPath, from: missingURL)
        #expect(projectPackageErrorCode { try store.load(from: missingURL) }
            == .missingEntry)

        _ = try store.save(document, to: traversalURL)
        try addAdjunct(path: "adjuncts/x/y", data: Data([9]), to: traversalURL)
        var traversalData = try Data(contentsOf: traversalURL)
        let replacements = replaceAll(
            Data("adjuncts/x/y".utf8),
            with: Data("../evilxxxxx".utf8),
            in: &traversalData
        )
        #expect(replacements == 2)
        try traversalData.write(to: traversalURL)
        #expect(projectPackageErrorCode { try store.load(from: traversalURL) }
            == .invalidEntryPath)

        let length = try store.save(document, to: lengthURL)
        let productDescriptor = try #require(
            length.document.backing?.entries[ProjectPackageManifest.productSourcePath]
        )
        var lengthData = try Data(contentsOf: lengthURL)
        lengthData[productDescriptor.localRecordRange.lowerBound + 22] ^= 0x01
        try lengthData.write(to: lengthURL)
        #expect(projectPackageErrorCode { try store.load(from: lengthURL) }
            == .malformedArchive)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageRejectsUnknownEntriesOutsideNamespacedAdjuncts() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("invalid-adjunct.rupa")
        _ = try ProjectPackageStore().save(
            fixtureMeshOnlyDocument(seed: "invalid-adjunct"),
            to: url
        )
        try addAdjunct(path: "adjuncts/vendor/x", data: Data([1]), to: url)
        var data = try Data(contentsOf: url)
        let replacements = replaceAll(
            Data("adjuncts/vendor/x".utf8),
            with: Data("external/vendor/x".utf8),
            in: &data
        )
        #expect(replacements == 2)
        try data.write(to: url)

        #expect(projectPackageErrorCode { try ProjectPackageStore().load(from: url) }
            == .invalidEntryPath)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageExplicitlyRejectsSchemaV2() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("legacy-v2.rupa")
        var writer = try ProjectPackageArchiveWriter(
            sink: ProjectPackageDataSink(),
            limits: .standard
        )
        try writer.writeDataEntry(
            path: "manifest.json",
            data: Data("{\"packageFormat\":\"rupa.project\",\"packageSchemaVersion\":2}".utf8)
        )
        try writer.finish()
        try writer.sink.data.write(to: url)

        #expect(projectPackageErrorCode { try ProjectPackageStore().load(from: url) }
            == .unsupportedSchema)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectPackageRejectsDuplicatesAndConfiguredLimits() throws {
    var writer = try ProjectPackageArchiveWriter(
        sink: ProjectPackageDataSink(),
        limits: .standard
    )
    try writer.writeDataEntry(path: "manifest.json", data: Data([1]))
    #expect(projectPackageErrorCode {
        try writer.writeDataEntry(path: "manifest.json", data: Data([2]))
    } == .duplicateEntry)

    let mesh = try authoredTriangle(id: "mesh.limit", xOffset: 0)
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumArchiveByteCount = 1_024
    limits.maximumManifestByteCount = 512
    limits.maximumProductSourceByteCount = 512
    limits.maximumCADSourceByteCount = 512
    limits.maximumMeshCatalogByteCount = 512
    limits.maximumSourceBlobByteCount = 64
    limits.maximumPreservedAdjunctByteCount = 512
    limits.maximumChunkByteCount = 128
    limits.meshSource.maximumBlobByteCount = 64
    limits.meshSource.maximumChunkByteCount = 128
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageMeshPlanner(limits: limits).plan([mesh.id: mesh])
    } == .resourceLimitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageFailedAtomicReplacementPreservesDestinationAndCleansTemporaryFile() throws {
    try withTemporaryDirectory { directory in
        let destinationURL = directory.appendingPathComponent("atomic.rupa")
        let original = try fixtureMeshOnlyDocument(seed: "original")
        let store = ProjectPackageStore()
        let saved = try store.save(original, to: destinationURL)
        let replacementProduct = try fixtureProductSource("replacement")
        let replacedDocument = try saved.document.replacingSources(
            documentID: saved.document.documentID,
            product: replacementProduct,
            cad: nil,
            authoredMeshAssets: saved.document.authoredMeshAssets
        )
        let replaced = try store.save(replacedDocument, to: destinationURL)
        #expect(replaced.document.productSource == replacementProduct)

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
            _ = try failingStore.save(original, to: destinationURL)
        } == .atomicSaveFailure)

        let retained = try store.load(from: destinationURL)
        #expect(retained.productSource == replacementProduct)
        let temporaryPrefix = ".\(destinationURL.lastPathComponent)."
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).filter { $0.hasPrefix(temporaryPrefix) && $0.hasSuffix(".tmp") }
        #expect(remainingNames.isEmpty)
    }
}

private func fixtureMeshOnlyDocument(seed: String) throws -> ProjectPackageDocument {
    let mesh = try authoredTriangle(
        id: GeometrySourceID(rawValue: "mesh.\(seed)"),
        xOffset: 0
    )
    return try ProjectPackageDocument(
        documentID: ProjectID(rawValue: "project.\(seed)"),
        productSource: fixtureProductSource(seed),
        cadSource: nil,
        authoredMeshAssets: [mesh.id: mesh]
    )
}

private func authoredTriangle(
    id: GeometrySourceID,
    xOffset: Double
) throws -> AuthoredMeshAsset {
    try AuthoredMeshAsset(
        source: triangleSource(id: id, xOffset: xOffset),
        provenance: .created
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

private func fixtureProductSource(_ seed: String) throws -> ProjectPackageProductSource {
    try ProjectPackageProductSource(data: Data("{\"fixture\":\"\(seed)\"}".utf8))
}

private func fixtureCADSource(_ seed: String) throws -> ProjectPackageCADSource {
    try ProjectPackageCADSource(data: Data("{\"fixture\":\"\(seed)\"}".utf8))
}

private func expectSourcePaths(
    in document: ProjectPackageDocument,
    includeCAD: Bool,
    includeMesh: Bool
) throws {
    let backing = try #require(document.backing)
    #expect(backing.entries[ProjectPackageManifest.productSourcePath] != nil)
    #expect((backing.entries[ProjectPackageManifest.cadSourcePath] != nil) == includeCAD)
    #expect((backing.entries[ProjectPackageManifest.meshCatalogPath] != nil) == includeMesh)
    #expect(backing.entries["source/rupa.json"] == nil)
    #expect(backing.entries.keys.contains {
        $0.hasPrefix(ProjectSourceBlobReference.pathPrefix)
    } == includeMesh)
}

private func activeBlobPayload(in document: ProjectPackageDocument) throws -> Data {
    let manifest = try #require(document.manifest)
    let backing = try #require(document.backing)
    let entry = try #require(manifest.sourceEntries.first {
        $0.path.hasPrefix(ProjectSourceBlobReference.pathPrefix)
    })
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

private func removeEntry(path: String, from url: URL) throws {
    let originalData = try Data(contentsOf: url, options: [.mappedIfSafe])
    let limits = ProjectPackageResourceLimits.standard
    let backing = try ProjectPackageArchiveReader(limits: limits).read(originalData)
    var writer = try ProjectPackageArchiveWriter(
        sink: ProjectPackageDataSink(),
        limits: limits
    )
    for outputPath in backing.entries.keys.sorted() where outputPath != path {
        let descriptor = try #require(backing.entries[outputPath])
        try writer.writeRetainedEntry(descriptor, from: backing)
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
