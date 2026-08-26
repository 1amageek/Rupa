import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene
import Testing
@testable import RupaRendering
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationPickingResolvesRenderedTrianglesByOccurrenceForCADMeshAndMixedScenes() throws {
    let references: [GeometrySourceReference] = [
        .cad(sourceID: "cad.pick", outputID: "cad.output"),
        .authoredMesh(GeometrySourceID(rawValue: "mesh.pick")),
        .external(providerID: "external", sourceID: "external.pick", outputID: "external.output"),
    ]
    let (scene, source) = try pickingScene(references: references)
    let navigation = try pickingNavigation(for: scene)
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let picker: any MeshSourcePresentationPicking = MeshSourcePresentationPicker()
    let plan = try renderer.makePlan(for: scene)
    let index = try picker.makeIndex(for: scene, navigation: navigation)
    let initialTelemetry = scene.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentities(source)

    var emittedTriangleCount = 0
    var resolvedOccurrenceIDs = Set<SceneOccurrenceID>()
    var resolvedSceneNodeIDs = Set<SceneNodeID>()
    try renderer.render(plan: plan) { triangle in
        let identity = try index.identity(for: triangle.occurrenceID)
        let record = try picker.resolve(
            identity: identity,
            in: index,
            expectedSnapshotID: scene.snapshotID
        )
        #expect(record.identity == identity)
        #expect(record.snapshotID == scene.snapshotID)
        #expect(record.occurrenceID == triangle.occurrenceID)
        emittedTriangleCount += 1
        resolvedOccurrenceIDs.insert(record.occurrenceID)
        resolvedSceneNodeIDs.insert(record.sceneNodeID)
    }

    #expect(index.count == references.count)
    #expect(emittedTriangleCount == references.count * 2)
    #expect(resolvedOccurrenceIDs.count == references.count)
    #expect(resolvedSceneNodeIDs.count == references.count)
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(sourceChunkIdentities(source) == initialChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationPickingRejectsMissingDuplicateUnknownAndStaleIdentities() throws {
    let (scene, _) = try pickingScene(
        references: [.cad(sourceID: "cad.pick", outputID: "cad.output")]
    )
    let item = try #require(scene.items.first)
    let sceneNodeID = SceneNodeID()
    let validNavigation = try MeshSourcePresentationNavigationMap(
        mappings: [(occurrenceID: item.occurrenceID, sceneNodeID: sceneNodeID)]
    )
    let picker = MeshSourcePresentationPicker()
    let index = try picker.makeIndex(for: scene, navigation: validNavigation)
    let identity = try index.identity(for: item.occurrenceID)

    let otherSnapshot = EvaluationSnapshotID(
        projectID: scene.projectID,
        purpose: .presentation,
        sourceRevision: try scene.snapshotID.sourceRevision.advanced()
    )
    var staleError: MeshSourcePresentationPickError?
    do {
        _ = try picker.resolve(
            identity: identity,
            in: index,
            expectedSnapshotID: otherSnapshot
        )
    } catch let error as MeshSourcePresentationPickError {
        staleError = error
    }
    #expect(staleError?.code == .staleSnapshot)

    var unknownError: MeshSourcePresentationPickError?
    do {
        let unknownIdentity = try #require(
            MeshSourcePresentationPickIdentity(rawValue: UInt32.max)
        )
        _ = try picker.resolve(
            identity: unknownIdentity,
            in: index,
            expectedSnapshotID: scene.snapshotID
        )
    } catch let error as MeshSourcePresentationPickError {
        unknownError = error
    }
    #expect(unknownError?.code == .unknownIdentity)

    var missingNavigationError: MeshSourcePresentationPickError?
    do {
        _ = try picker.makeIndex(
            for: scene,
            navigation: MeshSourcePresentationNavigationMap(mappings: [])
        )
    } catch let error as MeshSourcePresentationPickError {
        missingNavigationError = error
    }
    #expect(missingNavigationError?.code == .missingNavigation)

    var duplicateOccurrenceError: MeshSourcePresentationPickError?
    do {
        _ = try picker.makeIndex(
            for: UniversalViewportScene(
                snapshotID: scene.snapshotID,
                projectID: scene.projectID,
                items: [item, item]
            ),
            navigation: validNavigation
        )
    } catch let error as MeshSourcePresentationPickError {
        duplicateOccurrenceError = error
    }
    #expect(duplicateOccurrenceError?.code == .duplicateOccurrence)

    var duplicateNavigationError: MeshSourcePresentationPickError?
    do {
        _ = try MeshSourcePresentationNavigationMap(
            mappings: [
                (occurrenceID: item.occurrenceID, sceneNodeID: sceneNodeID),
                (occurrenceID: item.occurrenceID, sceneNodeID: SceneNodeID()),
            ]
        )
    } catch let error as MeshSourcePresentationPickError {
        duplicateNavigationError = error
    }
    #expect(duplicateNavigationError?.code == .duplicateNavigationMapping)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationPickingRejectsIdentityOverflowAndStaleNavigationEntries() throws {
    var overflowError: MeshSourcePresentationPickError?
    do {
        _ = try MeshSourcePresentationPickIdentity(ordinal: Int.max)
    } catch let error as MeshSourcePresentationPickError {
        overflowError = error
    }
    #expect(overflowError?.code == .identityOverflow)

    let (scene, _) = try pickingScene(
        references: [.cad(sourceID: "cad.pick", outputID: "cad.output")]
    )
    let item = try #require(scene.items.first)
    var staleNavigationError: MeshSourcePresentationPickError?
    do {
        let navigation = try MeshSourcePresentationNavigationMap(
            mappings: [
                (
                    occurrenceID: item.occurrenceID,
                    sceneNodeID: SceneNodeID()
                ),
                (
                    occurrenceID: SceneOccurrenceID(rawValue: "occurrence.not-in-scene"),
                    sceneNodeID: SceneNodeID()
                ),
            ]
        )
        _ = try MeshSourcePresentationPickIndex(scene: scene, navigation: navigation)
    } catch let error as MeshSourcePresentationPickError {
        staleNavigationError = error
    }
    #expect(staleNavigationError?.code == .staleNavigation)
}

private func pickingScene(
    references: [GeometrySourceReference]
) throws -> (scene: UniversalViewportScene, source: MeshSource) {
    let source = try pickingMeshSource()
    let projectID = ProjectID(rawValue: "project.presentation-pick")
    let snapshotID = EvaluationSnapshotID(
        projectID: projectID,
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision()
    )
    let bounds = try source.bounds()
    let items = references.enumerated().map { index, reference in
        UniversalViewportSceneItem(
            id: SceneOccurrenceID(rawValue: "occurrence.presentation-pick.\(index)"),
            definitionID: ObjectDefinitionID(rawValue: "definition.presentation-pick.\(index)"),
            displayName: "Presentation Pick \(index)",
            representationID: GeometryRepresentationID(rawValue: "representation.presentation-pick.\(index)"),
            reference: reference,
            mesh: source,
            worldTransform: .identity,
            worldBounds: bounds
        )
    }
    return (
        UniversalViewportScene(
            snapshotID: snapshotID,
            projectID: projectID,
            items: items
        ),
        source
    )
}

private func pickingNavigation(
    for scene: UniversalViewportScene
) throws -> MeshSourcePresentationNavigationMap {
    try MeshSourcePresentationNavigationMap(
        mappings: scene.items.enumerated().map { _, item in
            (
                occurrenceID: item.occurrenceID,
                sceneNodeID: SceneNodeID()
            )
        }
    )
}

private func pickingMeshSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.pick"))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

private func sourceChunkIdentities(_ source: MeshSource) -> [[ObjectIdentifier]] {
    [
        source.vertexIDs.storage.chunkIdentities,
        source.vertexPositions.storage.chunkIdentities,
        source.edgeIDs.storage.chunkIdentities,
        source.edgeEndpoints.storage.chunkIdentities,
        source.faceIDs.storage.chunkIdentities,
        source.faceCornerRanges.storage.chunkIdentities,
        source.cornerIDs.storage.chunkIdentities,
        source.cornerVertexIDs.storage.chunkIdentities,
        source.cornerEdgeIDs.storage.chunkIdentities,
    ]
}
