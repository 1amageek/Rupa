import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaRendering
import RupaViewportScene
import Testing

@Test(.timeLimit(.minutes(1)))
func viewportMeshSelectionOverlayUsesWorldPointsAndOriginalBoundaries() throws {
    let fixture = try viewportMeshSelectionOverlayFixture()
    let mesh = fixture.mesh
    let selected: [MeshSelectionElement] = [
        .vertex(mesh.vertexIDs[0]),
        .corner(mesh.cornerIDs[1]),
        .edge(mesh.edgeIDs[0]),
        .face(mesh.faceIDs[0]),
    ]

    let overlay = try ViewportMeshSelectionOverlay.build(
        snapshotID: fixture.snapshotID,
        item: fixture.item,
        selectedElements: selected,
        maxVisibleSegments: 3
    )

    #expect(overlay.snapshotID == fixture.snapshotID)
    #expect(overlay.sourceID == mesh.identity)
    #expect(overlay.sourceReference == .authoredMesh(mesh.identity))
    #expect(overlay.occurrenceID == fixture.item.occurrenceID)
    #expect(overlay.selectedElements == selected)
    #expect(overlay.points.count == 2)
    #expect(overlay.points[0].element == selected[0])
    #expect(overlay.points[0].vertexID == mesh.vertexIDs[0])
    #expect(overlay.points[0].sourcePosition == mesh.vertexPositions[0])
    #expect(overlay.points[0].position == GeometryPoint3D(x: 10, y: 20, z: 30))
    #expect(overlay.points[1].element == selected[1])
    #expect(overlay.points[1].vertexID == mesh.cornerVertexIDs[1])
    #expect(overlay.points[1].sourcePosition == mesh.vertexPositions[1])
    #expect(overlay.points[1].position == GeometryPoint3D(x: 11, y: 20, z: 30))

    #expect(overlay.sourceBoundarySegmentCount == 4)
    #expect(overlay.visibleBoundarySegmentCount == 3)
    #expect(overlay.boundarySegments.count == 3)
    #expect(overlay.omittedBoundarySegmentCount == 1)
    #expect(overlay.isTruncated)
    #expect(overlay.boundarySegments[0].edgeID == mesh.edgeIDs[0])
    #expect(overlay.boundarySegments.allSatisfy { mesh.edgeIDs.contains($0.edgeID) })
    #expect(overlay.boundarySegments[0].start == GeometryPoint3D(x: 10, y: 20, z: 30))
    #expect(overlay.boundarySegments[0].end == GeometryPoint3D(x: 11, y: 20, z: 30))
}

@Test(.timeLimit(.minutes(1)))
func viewportMeshSelectionOverlayDoesNotTransformOmittedSegments() throws {
    let fixture = try viewportMeshSelectionOverlayFixture()
    let transform = try GeometryTransform3D(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 1, 0, -1,
    ])
    let item = UniversalViewportSceneItem(
        id: fixture.item.occurrenceID,
        definitionID: fixture.item.definitionID,
        displayName: fixture.item.displayName,
        representationID: fixture.item.representationID,
        reference: fixture.item.sourceReference,
        mesh: fixture.mesh,
        worldTransform: transform,
        worldBounds: try GeometryBounds3D(
            minimum: GeometryPoint3D(x: -1, y: -1, z: -1),
            maximum: GeometryPoint3D(x: 1, y: 1, z: 1)
        )
    )

    let overlay = try ViewportMeshSelectionOverlay.build(
        snapshotID: fixture.snapshotID,
        item: item,
        selectedElements: [.face(fixture.mesh.faceIDs[0])],
        maxVisibleSegments: 1
    )

    #expect(overlay.sourceBoundarySegmentCount == 4)
    #expect(overlay.visibleBoundarySegmentCount == 1)
    #expect(overlay.isTruncated)
}

@Test(.timeLimit(.minutes(1)))
func viewportMeshSelectionOverlayRejectsCallerLimitsAndOversizedSelection() throws {
    let fixture = try viewportMeshSelectionOverlayFixture()

    var negativeLimitError: ViewportMeshSelectionOverlay.BuildError?
    do {
        _ = try ViewportMeshSelectionOverlay.build(
            snapshotID: fixture.snapshotID,
            item: fixture.item,
            selectedElements: [],
            maxVisibleSegments: -1
        )
    } catch let error as ViewportMeshSelectionOverlay.BuildError {
        negativeLimitError = error
    }
    #expect(negativeLimitError == .invalidLimit)

    var excessiveLimitError: ViewportMeshSelectionOverlay.BuildError?
    do {
        _ = try ViewportMeshSelectionOverlay.build(
            snapshotID: fixture.snapshotID,
            item: fixture.item,
            selectedElements: [],
            maxVisibleSegments: 2_049
        )
    } catch let error as ViewportMeshSelectionOverlay.BuildError {
        excessiveLimitError = error
    }
    #expect(excessiveLimitError == .invalidLimit)

    let oversizedSelection = Array(
        repeating: MeshSelectionElement.vertex(fixture.mesh.vertexIDs[0]),
        count: MeshEditLimits.standard.maxSelectedIDs + 1
    )
    var selectionLimitError: ViewportMeshSelectionOverlay.BuildError?
    do {
        _ = try ViewportMeshSelectionOverlay.build(
            snapshotID: fixture.snapshotID,
            item: fixture.item,
            selectedElements: oversizedSelection
        )
    } catch let error as ViewportMeshSelectionOverlay.BuildError {
        selectionLimitError = error
    }
    #expect(selectionLimitError == .selectionLimitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func viewportMeshSelectionOverlayStopsBeforeCancelledBuild() async throws {
    let fixture = try viewportMeshSelectionOverlayFixture()
    let gate = AsyncStream<Void>.makeStream()
    let task = Task {
        var iterator = gate.stream.makeAsyncIterator()
        _ = await iterator.next()
        return try ViewportMeshSelectionOverlay.build(
            snapshotID: fixture.snapshotID,
            item: fixture.item,
            selectedElements: [.face(fixture.mesh.faceIDs[0])]
        )
    }
    task.cancel()
    gate.continuation.finish()

    await #expect(throws: CancellationError.self) {
        _ = try await task.value
    }
}

private struct ViewportMeshSelectionOverlayFixture {
    let snapshotID: EvaluationSnapshotID
    let item: UniversalViewportSceneItem
    let mesh: MeshSource
}

private func viewportMeshSelectionOverlayFixture() throws
    -> ViewportMeshSelectionOverlayFixture
{
    var builder = MeshSourceBuilder(identity: "mesh.selection-overlay")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    let mesh = try builder.build()
    let transform = try GeometryTransform3D(values: [
        1, 0, 0, 10,
        0, 1, 0, 20,
        0, 0, 1, 30,
        0, 0, 0, 1,
    ])
    let item = UniversalViewportSceneItem(
        id: SceneOccurrenceID(rawValue: "occurrence.selection-overlay"),
        definitionID: ObjectDefinitionID(rawValue: "definition.selection-overlay"),
        displayName: "Selection Overlay",
        representationID: GeometryRepresentationID(rawValue: "representation.selection-overlay"),
        reference: .authoredMesh(mesh.identity),
        mesh: mesh,
        worldTransform: transform,
        worldBounds: try mesh.bounds().transformed(by: transform)
    )
    let snapshotID = EvaluationSnapshotID(
        projectID: ProjectID(rawValue: "project.selection-overlay"),
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision(9)
    )
    return ViewportMeshSelectionOverlayFixture(
        snapshotID: snapshotID,
        item: item,
        mesh: mesh
    )
}
