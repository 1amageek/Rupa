import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import Testing
@testable import RupaProjectPackage

@Test(.timeLimit(.minutes(1)))
func projectPackageMeshPlanningIsDeterministicAndUsesBoundedBorrowedChunks() throws {
    let first = try authoredMesh(id: "mesh.first", xOffset: 0)
    let second = try authoredMesh(id: "mesh.second", xOffset: 2)
    let forward = [first.id: first, second.id: second]
    let reverse = [second.id: second, first.id: first]
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumChunkByteCount = 17
    limits.meshSource.maximumChunkByteCount = 17
    let planner = ProjectPackageMeshPlanner(limits: limits)

    let firstPlan = try planner.plan(forward)
    let secondPlan = try planner.plan(reverse)
    let productEntry = try ProjectPackageProductSource(
        data: Data("{\"fixture\":\"contract\"}".utf8)
    ).sourceEntry
    let firstCatalogEntry = try #require(firstPlan.catalogEntry)
    let secondCatalogEntry = try #require(secondPlan.catalogEntry)
    let firstManifest = try ProjectPackageManifest(
        documentID: "project.package",
        sourceEntries: [productEntry, firstCatalogEntry]
            + firstPlan.blobs.map { try $0.reference.sourceEntry }
    )
    let secondManifest = try ProjectPackageManifest(
        documentID: "project.package",
        sourceEntries: [secondCatalogEntry, productEntry]
            + secondPlan.blobs.reversed().map { try $0.reference.sourceEntry }
    )

    #expect(firstPlan.catalogData == secondPlan.catalogData)
    #expect(firstManifest == secondManifest)
    #expect(firstManifest.documentContentIdentity == secondManifest.documentContentIdentity)
    #expect(firstPlan.blobs.map(\.reference.path) == secondPlan.blobs.map(\.reference.path))
    #expect(firstPlan.blobs.allSatisfy { $0.maximumEncodedChunkByteCount <= 17 })
    #expect(firstPlan.telemetry.events.count == 2)
    #expect(!String(decoding: try #require(firstPlan.catalogData), as: UTF8.self)
        .contains("vertexPositions"))
}

@Test(.timeLimit(.minutes(1)))
func projectPackageEmptyMeshPlanOmitsCatalogAndBlobs() throws {
    let plan = try ProjectPackageMeshPlanner(limits: .standard).plan([:])

    #expect(plan.catalogEntry == nil)
    #expect(plan.catalogData == nil)
    #expect(plan.blobs.isEmpty)
    #expect(plan.telemetry.events.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageContentIdentityIsIndependentOfManifestEntryOrder() throws {
    let product = try ProjectPackageProductSource(
        data: Data("{\"fixture\":\"identity\"}".utf8)
    ).sourceEntry
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
        sourceEntries: [product, cad, blob]
    )
    let second = try ProjectPackageManifest(
        documentID: "project.identity",
        sourceEntries: [blob, product, cad]
    )

    #expect(first == second)
    #expect(first.packageSchemaVersion == 3)
    #expect(first.documentContentIdentity == second.documentContentIdentity)
}

@Test(.timeLimit(.minutes(1)))
func projectPackageContractsRequireProductAndRejectTraversalDuplicatesAndTampering() throws {
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageSourceEntry(
            path: "source/../escape",
            mediaType: "application/octet-stream",
            schemaVersion: 1,
            byteCount: 1,
            fingerprint: fingerprint(seed: "escape")
        )
    } == .invalidEntryPath)

    let product = try ProjectPackageProductSource(
        data: Data("{\"fixture\":\"contract\"}".utf8)
    ).sourceEntry
    let cad = try ProjectPackageCADSource(
        data: Data("{\"fixture\":\"contract\"}".utf8)
    ).sourceEntry
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageManifest(
            documentID: "project.missing-product",
            sourceEntries: [cad]
        )
    } == .missingEntry)
    #expect(projectPackageErrorCode {
        _ = try ProjectPackageManifest(
            documentID: "project.duplicate",
            sourceEntries: [product, cad, product]
        )
    } == .duplicateEntry)

    let manifest = try ProjectPackageManifest(
        documentID: "project.tamper",
        sourceEntries: [product, cad]
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
func projectPackageMeshPlannerRejectsConfiguredBlobLimit() throws {
    let mesh = try authoredMesh(id: "mesh.limit", xOffset: 0)
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumSourceBlobByteCount = 64
    limits.meshSource.maximumBlobByteCount = 64

    #expect(projectPackageErrorCode {
        _ = try ProjectPackageMeshPlanner(limits: limits).plan([mesh.id: mesh])
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

private func authoredMesh(
    id: GeometrySourceID,
    xOffset: Double
) throws -> AuthoredMeshAsset {
    var builder = MeshSourceBuilder(identity: id)
    let first = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: xOffset + 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: xOffset, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try AuthoredMeshAsset(source: builder.build(), provenance: .created)
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
