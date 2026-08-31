import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
@testable import RupaGeometry
import RupaKit
import RupaProjectAccess
import RupaProjectAccessComposition
import RupaProjectAccessPlatform
import RupaProjectModel
import Testing

@MainActor
@Test(.timeLimit(.minutes(2)))
func closedAccessPreservesAuthoredMeshAuthorityAndZeroCopyAcrossUnrelatedMutations() async throws {
    for kind in AccessZeroCopyFixtureKind.allCases {
        let directory = try makeAccessZeroCopyTemporaryDirectory()
        do {
            try await verifyAccessZeroCopyFixture(kind, in: directory)
            try FileManager.default.removeItem(at: directory)
        } catch {
            let primaryError = error
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                // Preserve the behavioral failure rather than replacing it with cleanup noise.
            }
            throw primaryError
        }
    }
}

@MainActor
private func verifyAccessZeroCopyFixture(
    _ kind: AccessZeroCopyFixtureKind,
    in directory: URL
) async throws {
    let fixture = try makeAccessZeroCopyFixture(kind)
    let input = directory.appendingPathComponent("input.rupa")
    let output = directory.appendingPathComponent("output.rupa")
    let factory = DefaultProjectWorkspaceFactory()

    let sourceWorkspace = try factory.makeWorkspace(document: fixture.document)
    _ = try await sourceWorkspace.evaluate()
    _ = try await sourceWorkspace.save(to: input)
    let inputPackageBytes = try Data(contentsOf: input)
    let expectedMeshBytes = try MeshSourceCodec.encode(fixture.asset.source)

    let initiallyLoadedWorkspace = try factory.makeWorkspace()
    let initiallyLoaded = try await initiallyLoadedWorkspace.load(from: input)
    try expectAccessZeroCopyAggregate(
        initiallyLoaded,
        expectedAsset: fixture.asset,
        expectedMeshBytes: expectedMeshBytes,
        expectedPresentationRepresentationID: fixture.presentationRepresentationID
    )

    let opener = ClosedProjectAccessOpening(
        leaseStore: ProjectFileAuthorityLeaseStore(
            rootDirectory: directory.appendingPathComponent("leases", isDirectory: true)
        )
    )
    let session = try await opener.open(
        .closedProject(input: input, output: output),
        deadline: ContinuousClock.now.advanced(by: .seconds(60))
    )
    do {
        let initialResponse = try await session.send(
            .designDisplaySnapshot(sessionID: session.sessionID, expectedGeneration: nil)
        )
        let initialGeneration = try accessZeroCopyGeneration(from: initialResponse)
        let mutationResponse = try await session.send(
            .execute(
                sessionID: session.sessionID,
                command: fixture.unrelatedMutation,
                expectedGeneration: initialGeneration
            )
        )
        let commandResult = try accessZeroCopyCommandResult(from: mutationResponse)
        #expect(commandResult.didMutate)
        #expect(try Data(contentsOf: input) == inputPackageBytes)

        let saveResult = try await session.save(
            expectedGeneration: commandResult.generation
        )
        #expect(saveResult.path == output.path)
        #expect(try Data(contentsOf: input) == inputPackageBytes)
        await session.finish()
    } catch {
        await session.finish()
        throw error
    }

    let finallyLoadedWorkspace = try factory.makeWorkspace()
    let finallyLoaded = try await finallyLoadedWorkspace.load(from: output)
    try expectAccessZeroCopyAggregate(
        finallyLoaded,
        expectedAsset: fixture.asset,
        expectedMeshBytes: expectedMeshBytes,
        expectedPresentationRepresentationID: fixture.presentationRepresentationID
    )
}

private enum AccessZeroCopyFixtureKind: CaseIterable, Sendable {
    case cadAndMesh
    case meshOnly
}

private struct AccessZeroCopyFixture: Sendable {
    let document: DesignDocument
    let asset: AuthoredMeshAsset
    let presentationRepresentationID: GeometryRepresentationID
    let unrelatedMutation: AutomationCommand
}

private func makeAccessZeroCopyFixture(
    _ kind: AccessZeroCopyFixtureKind
) throws -> AccessZeroCopyFixture {
    let sourceID: GeometrySourceID
    let representationID: GeometryRepresentationID
    let importedFingerprint: ContentFingerprint
    switch kind {
    case .cadAndMesh:
        sourceID = "mesh.access-zero-copy.cad-and-mesh"
        representationID = "representation.access-zero-copy.cad-and-mesh"
        importedFingerprint = try ContentFingerprint(
            algorithm: "fixture-revision",
            value: "cad-and-mesh"
        )
    case .meshOnly:
        sourceID = "mesh.access-zero-copy.mesh-only"
        representationID = "representation.access-zero-copy.mesh-only"
        importedFingerprint = try ContentFingerprint(
            algorithm: "fixture-revision",
            value: "mesh-only"
        )
    }
    let asset = try AuthoredMeshAsset(
        source: try makeAccessZeroCopyTriangleMesh(identity: sourceID),
        provenance: .imported(
            try ContentIdentity(
                domain: "rupa.access-zero-copy-import",
                fingerprint: importedFingerprint
            )
        )
    )

    switch kind {
    case .cadAndMesh:
        var document = DesignDocument.empty(named: "Access Zero Copy CAD and Mesh")
        let bodyFeatureID = try document.createExtrudedRectangle(
            name: "Existing CAD Body",
            plane: .xy,
            width: .length(1, .meter),
            height: .length(1, .meter),
            depth: .length(1, .meter),
            direction: .normal
        )
        let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
            $0.value.reference == .body(bodyFeatureID)
        }?.key)
        var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
        let cadRepresentationID = try #require(
            object.geometryRepresentations.selection?.modeling
        )
        document.authoredMeshAssets[asset.id] = asset
        object.geometryRepresentations.representations[representationID] =
            GeometryRepresentation(
                id: representationID,
                source: .authoredMesh(asset.id)
            )
        object.geometryRepresentations.selection = GeometryRepresentationSelection(
            modeling: cadRepresentationID,
            presentation: representationID
        )
        document.productMetadata.sceneNodes[bodyNodeID]?.object = object
        try document.validate()
        return AccessZeroCopyFixture(
            document: document,
            asset: asset,
            presentationRepresentationID: representationID,
            unrelatedMutation: .createExtrudedRectangle(
                name: "Unrelated CAD Body",
                plane: .xy,
                width: .length(0.25, .meter),
                height: .length(0.25, .meter),
                depth: .length(0.25, .meter),
                direction: .normal
            )
        )
    case .meshOnly:
        var document = DesignDocument.empty(named: "Access Zero Copy Mesh Only")
        document.authoredMeshAssets[asset.id] = asset
        _ = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Authored Mesh",
            reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(
                category: .body,
                geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [
                        representationID: GeometryRepresentation(
                            id: representationID,
                            source: .authoredMesh(asset.id)
                        ),
                    ],
                    selection: GeometryRepresentationSelection(
                        modeling: representationID,
                        presentation: representationID
                    )
                )
            )
        )
        try document.validate()
        return AccessZeroCopyFixture(
            document: document,
            asset: asset,
            presentationRepresentationID: representationID,
            unrelatedMutation: .renameDocument(name: "Renamed Mesh Only")
        )
    }
}

private func makeAccessZeroCopyTriangleMesh(
    identity: GeometrySourceID
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(first, second, third)
    return try builder.build()
}

private func accessZeroCopyGeneration(
    from response: AgentResponse
) throws -> DocumentGeneration {
    guard case .designDisplaySnapshot(let snapshot) = response else {
        throw EditorError(
            code: .commandFailed,
            message: "Closed access did not return a design display snapshot."
        )
    }
    return snapshot.generation
}

private func accessZeroCopyCommandResult(
    from response: AgentResponse
) throws -> AutomationResult {
    guard case .command(let result) = response else {
        throw EditorError(
            code: .commandFailed,
            message: "Closed access did not execute the unrelated source mutation."
        )
    }
    return result
}

private func expectAccessZeroCopyAggregate(
    _ view: ProjectViewSnapshot,
    expectedAsset: AuthoredMeshAsset,
    expectedMeshBytes: Data,
    expectedPresentationRepresentationID: GeometryRepresentationID
) throws {
    let authoritativeAsset = try #require(
        view.document.document.authoredMeshAssets[expectedAsset.id]
    )
    #expect(authoritativeAsset.id == expectedAsset.id)
    #expect(authoritativeAsset.contentIdentity == expectedAsset.contentIdentity)
    #expect(authoritativeAsset.provenance == expectedAsset.provenance)
    #expect(try MeshSourceCodec.encode(authoritativeAsset.source) == expectedMeshBytes)

    let occurrence = try #require(view.viewport.items.first {
        $0.reference == .authoredMesh(expectedAsset.id)
    })
    #expect(occurrence.representationID == expectedPresentationRepresentationID)
    #expect(occurrence.mesh.identity == expectedAsset.id)
    #expect(occurrence.copyTelemetry.didCopy == false)
    if view.viewport.items.allSatisfy({ item in
        if case .authoredMesh = item.sourceReference {
            return true
        }
        return false
    }) {
        #expect(view.viewport.copyTelemetry.didCopy == false)
    }

    let sceneNodeID = try #require(view.sceneNodeID(for: occurrence.occurrenceID))
    let object = try #require(
        view.document.document.productMetadata.sceneNodes[sceneNodeID]?.object
    )
    #expect(
        object.geometryRepresentations.selection?.presentation
            == expectedPresentationRepresentationID
    )
    #expect(
        object.geometryRepresentations.representations[
            expectedPresentationRepresentationID
        ]?.source == .authoredMesh(expectedAsset.id)
    )

    expectAccessZeroCopyMeshStorage(
        occurrence.mesh,
        sharesStorageWith: authoritativeAsset.source
    )
}

private func expectAccessZeroCopyMeshStorage(
    _ evaluated: MeshSource,
    sharesStorageWith authoritative: MeshSource
) {
    expectAccessZeroCopyBuffer(evaluated.vertexIDs, authoritative.vertexIDs)
    expectAccessZeroCopyBuffer(evaluated.vertexPositions, authoritative.vertexPositions)
    expectAccessZeroCopyBuffer(evaluated.edgeIDs, authoritative.edgeIDs)
    expectAccessZeroCopyBuffer(evaluated.edgeEndpoints, authoritative.edgeEndpoints)
    expectAccessZeroCopyBuffer(evaluated.faceIDs, authoritative.faceIDs)
    expectAccessZeroCopyBuffer(evaluated.faceCornerRanges, authoritative.faceCornerRanges)
    expectAccessZeroCopyBuffer(evaluated.cornerIDs, authoritative.cornerIDs)
    expectAccessZeroCopyBuffer(evaluated.cornerVertexIDs, authoritative.cornerVertexIDs)
    expectAccessZeroCopyBuffer(evaluated.cornerEdgeIDs, authoritative.cornerEdgeIDs)
}

private func expectAccessZeroCopyBuffer<Element>(
    _ evaluated: GeometryBuffer<Element>,
    _ authoritative: GeometryBuffer<Element>
) where Element: Codable & Sendable {
    #expect(
        evaluated.storage.chunkIdentities
            == authoritative.storage.chunkIdentities
    )
    #expect(
        evaluated.storage.pageIdentities
            == authoritative.storage.pageIdentities
    )
}

private func makeAccessZeroCopyTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "RupaProjectAccessZeroCopy-" + UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}
