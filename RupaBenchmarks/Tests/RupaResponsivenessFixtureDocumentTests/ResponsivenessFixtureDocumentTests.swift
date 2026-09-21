import Foundation
import RupaCore
import RupaProject
import RupaProjectPackage
import RupaResponsivenessBaseline
import RupaResponsivenessFixtureDocument
import Testing

@Suite("Responsiveness fixture document contracts")
struct ResponsivenessFixtureDocumentTests {
    /// A small fixture with the same shape as the standard one, so the contracts
    /// are checked without materializing 301,632 triangles per test.
    private static let smallParameters = ResponsivenessFixture.Parameters(
        version: 1,
        name: "fixture-document-test",
        bodyCount: 2,
        segmentCount: 16,
        baseRadiusMeters: 0.030,
        radiusStepMeters: 0.002,
        lengthMeters: 0.45,
        bodySpacingMeters: 0.20
    )

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rupa-fixture-document-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    @Test("The written package reloads to the fixture's meshes")
    func writtenPackageReloadsToTheFixture() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try ResponsivenessFixture.build(Self.smallParameters)
        let url = directory.appendingPathComponent("fixture.rupa")

        let result = try ResponsivenessFixtureDocumentWriter().write(fixture, to: url)

        #expect(result.bodyCount == fixture.bodies.count)
        #expect(result.vertexCount == fixture.vertexCount)
        #expect(result.faceCount == fixture.faceCount)
        #expect(result.fixtureContentDigest == fixture.contentDigest)
        #expect(result.byteCount > 0)

        // Reload through the store the application loads with, so the writer's
        // own verification cannot be the only evidence.
        let reloaded = try ProjectPackageStore().load(from: url)
        #expect(reloaded.authoredMeshAssets.count == fixture.bodies.count)
        for body in fixture.bodies {
            let asset = try #require(reloaded.authoredMeshAssets[body.asset.id])
            #expect(asset == body.asset)
        }
    }

    @Test("Every fixture body is written as a placed mesh body")
    func everyBodyIsWrittenAsAPlacedMeshBody() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try ResponsivenessFixture.build(Self.smallParameters)
        let url = directory.appendingPathComponent("fixture.rupa")
        try ResponsivenessFixtureDocumentWriter().write(fixture, to: url)

        let reloaded = try ProjectPackageStore().load(from: url)
        let product = try JSONProjectProductSourceCodec().decode(reloaded.productSource)
        let bodyNodes = product.productMetadata.sceneNodes.values.filter {
            $0.reference?.kind == .authoredMesh
        }
        #expect(bodyNodes.count == fixture.bodies.count)

        let referencedSourceIDs = Set(bodyNodes.compactMap { $0.reference?.geometrySourceID })
        #expect(referencedSourceIDs == Set(fixture.bodies.map(\.asset.id)))
        for node in bodyNodes {
            #expect(node.object?.category == .body)
            #expect(node.object?.geometryRole == .mesh)
            #expect(node.object?.geometryRepresentations.selection?.presentation != nil)
        }

        // The fixture spaces its bodies along x, so no two bodies may be written
        // at the same place.
        let placements: Set<[Double]> = Set(bodyNodes.map { $0.localTransform.matrix.values })
        #expect(placements.count == fixture.bodies.count)
    }

    @Test("Writing the same fixture twice writes the same content")
    func writingTwiceWritesTheSameContent() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try ResponsivenessFixture.build(Self.smallParameters)
        let writer = ResponsivenessFixtureDocumentWriter()
        let first = directory.appendingPathComponent("first.rupa")
        let second = directory.appendingPathComponent("second.rupa")

        let firstResult = try writer.write(fixture, to: first)
        let secondResult = try writer.write(fixture, to: second)

        #expect(firstResult.bodyCount == secondResult.bodyCount)
        #expect(firstResult.vertexCount == secondResult.vertexCount)
        #expect(firstResult.faceCount == secondResult.faceCount)
        let store = ProjectPackageStore()
        let reloadedFirst = try store.load(from: first)
        let reloadedSecond = try store.load(from: second)
        #expect(reloadedFirst.authoredMeshAssets == reloadedSecond.authoredMeshAssets)
    }

    @Test("An unwritable destination is a typed failure")
    func unwritableDestinationIsTypedFailure() throws {
        let fixture = try ResponsivenessFixture.build(Self.smallParameters)
        let url = URL(fileURLWithPath: "/dev/null/missing-directory/fixture.rupa")

        #expect(throws: ResponsivenessFixtureDocumentError.self) {
            try ResponsivenessFixtureDocumentWriter().write(fixture, to: url)
        }
    }
}
