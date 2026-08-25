import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaProjectPackage

@Test(.timeLimit(.minutes(1)))
func projectPackagePlanningIsDeterministicAndUsesBoundedBorrowedChunks() throws {
    let first = try triangleSource(id: "mesh.first", xOffset: 0)
    let second = try triangleSource(id: "mesh.second", xOffset: 2)
    let forward = try ProjectSourceModel(
        id: "project.package",
        name: "Package",
        meshSources: [first.identity: first, second.identity: second]
    )
    let reverse = try ProjectSourceModel(
        id: "project.package",
        name: "Package",
        meshSources: [second.identity: second, first.identity: first]
    )
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumChunkByteCount = 17
    limits.meshSource.maximumChunkByteCount = 17
    let planner = ProjectPackageSourcePlanner(limits: limits)

    let firstPlan = try planner.plan(forward)
    let secondPlan = try planner.plan(reverse)
    let cadEntry = try ProjectPackageCADSource(
        data: Data("{\"fixture\":\"contract\"}".utf8)
    ).sourceEntry
    let firstManifest = try ProjectPackageManifest(
        documentID: forward.id,
        sourceEntries: [firstPlan.sourceEntry, cadEntry]
            + firstPlan.blobs.map { try $0.reference.sourceEntry }
    )
    let secondManifest = try ProjectPackageManifest(
        documentID: reverse.id,
        sourceEntries: [secondPlan.sourceEntry, cadEntry]
            + secondPlan.blobs.map { try $0.reference.sourceEntry }
    )

    #expect(firstPlan.sourceData == secondPlan.sourceData)
    #expect(firstManifest == secondManifest)
    #expect(firstManifest.documentContentIdentity == secondManifest.documentContentIdentity)
    #expect(firstPlan.blobs.map(\.reference.path) == secondPlan.blobs.map(\.reference.path))
    #expect(firstPlan.blobs.allSatisfy { $0.maximumEncodedChunkByteCount <= 17 })
    #expect(firstPlan.telemetry.events.count == 2)
    #expect(!String(decoding: firstPlan.sourceData, as: UTF8.self).contains("vertexPositions"))

    let envelope = try ProjectPackageCanonicalJSON.decode(
        ProjectPackageSourceEnvelope.self,
        from: firstPlan.sourceData
    )
    let reconstructed = try envelope.makeProject(meshSources: forward.meshSources)
    #expect(reconstructed == forward)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageContentIdentityIsIndependentOfManifestEntryOrder() throws {
    let metadata = try sourceEntry(
        path: ProjectPackageManifest.sourceMetadataPath,
        seed: "metadata"
    )
    let cad = try ProjectPackageCADSource(
        data: Data("{\"fixture\":\"identity\"}".utf8)
    ).sourceEntry
    let fingerprint = try fingerprint(seed: "mesh")
    let blob = try ProjectSourceBlobReference(
        mediaType: ProjectPackageMeshDigestSink.mediaType,
        schemaVersion: 1,
        byteCount: 12,
        fingerprint: fingerprint
    ).sourceEntry

    let first = try ProjectPackageManifest(
        documentID: "project.identity",
        sourceEntries: [metadata, cad, blob]
    )
    let second = try ProjectPackageManifest(
        documentID: "project.identity",
        sourceEntries: [blob, metadata, cad]
    )

    #expect(first == second)
    #expect(first.documentContentIdentity == second.documentContentIdentity)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageContractsRejectTraversalDuplicatesAndAlteredIdentity() throws {
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageSourceEntry(
            path: "source/../escape",
            mediaType: "application/octet-stream",
            schemaVersion: 1,
            byteCount: 1,
            fingerprint: fingerprint(seed: "escape")
        )
    } == .invalidEntryPath)

    let metadata = try sourceEntry(
        path: ProjectPackageManifest.sourceMetadataPath,
        seed: "metadata"
    )
    let cad = try ProjectPackageCADSource(
        data: Data("{\"fixture\":\"contract\"}".utf8)
    ).sourceEntry
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageManifest(
            documentID: "project.missing-cad",
            sourceEntries: [metadata]
        )
    } == .missingEntry)
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageManifest(
            documentID: "project.duplicate",
            sourceEntries: [metadata, cad, metadata]
        )
    } == .duplicateEntry)

    let manifest = try ProjectPackageManifest(
        documentID: "project.tamper",
        sourceEntries: [metadata, cad]
    )
    let encoded = try ProjectPackageCanonicalJSON.encode(manifest)
    let original = manifest.documentContentIdentity.content.fingerprint.value
    let tampered = String(decoding: encoded, as: UTF8.self)
        .replacingOccurrences(of: original, with: String(repeating: "0", count: 64))
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageCanonicalJSON.decode(
            ProjectPackageManifest.self,
            from: Data(tampered.utf8)
        )
    } == .integrityMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectPackagePlannerRejectsConfiguredEntryLimit() throws {
    let mesh = try triangleSource(id: "mesh.limit", xOffset: 0)
    let project = try ProjectSourceModel(
        id: "project.limit",
        name: "Limit",
        meshSources: [mesh.identity: mesh]
    )
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumEntryCount = 1

    #expect(projectPackageErrorCode {
        _ = try ProjectPackageSourcePlanner(limits: limits).plan(project)
    } == .resourceLimitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageCRC32MatchesPublishedVector() {
    let bytes = ContiguousArray("123456789".utf8)
    var crc32 = ProjectPackageCRC32()
    bytes.withUnsafeBufferPointer { pointer in
        crc32.update(Span(_unsafeElements: pointer))
    }
    #expect(crc32.checksum == 0xcbf4_3926)
}

private func triangleSource(id: GeometrySourceID, xOffset: Double) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: id)
    let first = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: xOffset + 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func sourceEntry(path: String, seed: String) throws -> ProjectPackageSourceEntry {
    try ProjectPackageSourceEntry(
        path: path,
        mediaType: "application/vnd.rupa.project-source+json",
        schemaVersion: 1,
        byteCount: 8,
        fingerprint: fingerprint(seed: seed)
    )
}

private func fingerprint(seed: String) throws -> ContentFingerprint {
    try .sha256(
        algorithm: "sha256-test-v1",
        data: Data(seed.utf8)
    )
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
