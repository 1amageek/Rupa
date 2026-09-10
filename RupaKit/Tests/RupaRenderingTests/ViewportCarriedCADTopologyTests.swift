import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Thrown by a native query the face branch must not reach.
private struct UnreachableNativeQuery: Error {}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeTriangleHitOnACarriedExtrudeTopologyNamesThePreparedCADFace() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )
    let item = try #require(scene.items.first {
        guard case .body = $0.kind else { return false }
        return $0.featureID == bodyFeatureID
    })
    guard case .body(let component) = item.kind else {
        Issue.record("The extrude item is not a body item.")
        return
    }
    let topology = try #require(component.topology)
    let mesh = try #require(component.mesh)
    #expect(!topology.meshFaceRuns.isEmpty)

    // One query per recorded run: the frame reports the triangle it drew, and
    // the prepared run list answers with the CAD face that emitted it. The
    // projection, surface and section queries throw, so a face answered here
    // is read from the carried run list and is not re-derived from the mesh.
    for run in topology.meshFaceRuns {
        for triangleIndex in [run.triangleRange.lowerBound, run.triangleRange.upperBound - 1] {
            let candidate = try #require(
                try ViewportNativeCADTopologyResolver.resolve(
                    at: CGPoint(x: 120, y: 90),
                    topology: topology,
                    modelTransform: item.modelTransform,
                    selectionHitPolicy: .face,
                    visibleSurface: (faceID: MeshFaceID(UInt64(triangleIndex)), depth: 4.5),
                    usesPerspectiveProjection: false,
                    project: { _ in throw UnreachableNativeQuery() },
                    surfaceHit: { _ in throw UnreachableNativeQuery() },
                    retainsSectionedPoint: { _ in throw UnreachableNativeQuery() }
                )
            )
            #expect(candidate.component == .face(run.componentID))
            guard case .face(let componentID) = candidate.component else {
                Issue.record("The resolved candidate is not a face.")
                return
            }
            #expect(componentID.generatedTopologySubshapeID != nil)
        }
    }

    // A triangle the run list does not describe is a truthful miss, never a
    // substituted neighbouring face.
    let triangleCount = mesh.indices.count / 3
    #expect(
        try ViewportNativeCADTopologyResolver.resolve(
            at: CGPoint(x: 120, y: 90),
            topology: topology,
            modelTransform: item.modelTransform,
            selectionHitPolicy: .face,
            visibleSurface: (faceID: MeshFaceID(UInt64(triangleCount)), depth: 4.5),
            usesPerspectiveProjection: false,
            project: { _ in throw UnreachableNativeQuery() },
            surfaceHit: { _ in throw UnreachableNativeQuery() },
            retainsSectionedPoint: { _ in throw UnreachableNativeQuery() }
        ) == nil
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func overlayBodyGeometryFollowsTheEditStateAndNotTheCarriedMesh() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )
    let item = try #require(scene.items.first {
        guard case .body = $0.kind else { return false }
        return $0.featureID == bodyFeatureID
    })
    guard case .body(let component) = item.kind else {
        Issue.record("The extrude item is not a body item.")
        return
    }
    let mesh = try #require(component.mesh)

    // Both snapshots mount a native scene and render a drag preview document,
    // so the only difference between them is whether an edit state owns this
    // body's shape.
    let idle = try ViewportSpatialOverlayProducer.makeInput(
        from: dragPreviewSnapshot(scene: scene, item: item, editedBody: nil),
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 1
    )
    let idleBodyMeshes = idle.meshes.filter { $0.family == .body }
    #expect(idleBodyMeshes.count == 1)
    #expect(idleBodyMeshes.first?.value.indices == mesh.indices)
    #expect(idle.paths.allSatisfy { $0.family != .body })

    let dragging = try ViewportSpatialOverlayProducer.makeInput(
        from: dragPreviewSnapshot(
            scene: scene,
            item: item,
            editedBody: .init(xMin: 5, xMax: 7, yMin: 1, yMax: 4, zMin: -2, zMax: 2)
        ),
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 1
    )
    let draggingBodyMeshes = dragging.meshes.filter { $0.family == .body }
    #expect(draggingBodyMeshes.count == 6)
    #expect(dragging.paths.filter { $0.family == .body }.count == 6)
    #expect(draggingBodyMeshes.allSatisfy {
        $0.value.positions.allSatisfy { (5 ... 7).contains($0.x) }
    })
}

@MainActor
private func dragPreviewSnapshot(
    scene: ViewportScene,
    item: ViewportSceneItem,
    editedBody: ViewportObjectEditState?
) -> ViewportSpatialOverlaySemanticSnapshot {
    ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        editedBodies: editedBody.map { [item.featureID: $0] } ?? [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: true
    )
}
