import AppKit
import RealityKit
import RupaCore
import RupaGeometry
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func releasedBodyKeepsItsPositionThroughPredecessorAndCommittedNativeFrames() async throws {
    _ = NSApplication.shared
    let scene = try planCacheScene(suffix: "release-handoff")
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let occurrence = try #require(scene.items.first).occurrenceID.rawValue
    let documentID = DesignDocument.empty().id
    let original = ViewportSourceIdentity.document(id: documentID, generation: DocumentGeneration(1))
    let committed = ViewportSourceIdentity.document(id: documentID, generation: DocumentGeneration(2))
    let handoff = ViewportBodyCommitHandoff()
    await handoff.begin(source: original, snapshotID: scene.snapshotID,
        mutation: try ViewportWorldTransformAlgebra.translation(.init(x: 2, y: 0, z: 0)),
        occurrenceIDs: [occurrence], commit: { committed }, onFailure: { Issue.record($0) }).value
    #expect(handoff.isPending)
    #expect(handoff.snapshotID == scene.snapshotID)

    let size = CGSize(width: 512, height: 384)
    func view(_ viewport: RealityViewport, source: ViewportSourceIdentity) -> some View {
        RealityViewportView(viewport: viewport, viewportRevision: 1, displayMode: .solid,
            shading: .init(style: .flat), occurrenceMaterials: [:],
            layout: .init(modelBounds: CGRect(x: -4, y: -4, width: 8, height: 8), size: size,
                          camera: .identity, basis: .axisFront(.z), verticalBounds: -4...4),
            interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                               previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
            sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
            objectPreviewTransforms: handoff.transforms(for: original),
            objectPreviewSnapshotID: handoff.snapshotID,
            onAppliedFrameRevision: { revision in
                if let revision, viewport.isCameraReady(revision: revision) { handoff.observe(source) }
            }, onUpdateResult: { _ in })
            .frame(width: size.width, height: size.height)
    }
    let first = try await RealityViewport.prepare(plan: plan)
    let controller = NSHostingController(rootView: view(first, source: original))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    defer { first.unbind(); window.contentViewController = nil; window.close() }
    func surface(_ entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity,
           model.components[CollisionComponent.self]?.filter.group == RealityViewport.surfaceCollisionGroup {
            return model
        }
        return entity.children.lazy.compactMap(surface).first
    }
    func check(_ viewport: RealityViewport) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !viewport.isCameraReady(revision: 1) {
            try #require(ContinuousClock.now < deadline)
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let model = try #require(surface(viewport.root))
        let minimum = Double(model.visualBounds(relativeTo: viewport.root).min.x) + viewport.renderOrigin.x
        #expect(abs(minimum - 2) < 1e-5, "The released object must never return to x=0 or apply its delta twice.")
    }
    try await check(first)
    // An already-running overlay build may publish another predecessor after commit.
    let predecessor = try await RealityViewport.prepare(plan: plan, spatialBatch: nil, reusing: first)
    controller.rootView = view(predecessor, source: original)
    try await check(predecessor)
    #expect(handoff.isPending)
    let next = try planCacheScene(suffix: "release-handoff", projectID: scene.projectID, revision: 1,
        transform: GeometryTransform3D(values: [1, 0, 0, 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]))
    let successor = try await RealityViewport.prepare(plan: MeshSourcePresentationRenderPlan(scene: next),
                                                    spatialBatch: nil, reusing: predecessor)
    controller.rootView = view(successor, source: committed)
    try await check(successor)
    let receiptDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while handoff.isPending {
        try #require(ContinuousClock.now < receiptDeadline)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!handoff.isPending)
    #expect(handoff.snapshotID == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func valueUpdateReusesHandleCollisionWithoutSharingFrameState() async throws {
    func batch(_ index: UInt32) throws -> RealityViewportSpatialBatch {
        try .init(markers: [.init(shape: .box, anchor: .init(x: Double(index), y: 0, z: 0),
            diameterPoints: 10, color: [1, 1, 1, 1], handleIndex: index, hitTolerancePoints: 8)],
            handleCount: 2, renderOrigin: .origin, retainedSurfaceByteCount: 0)
    }
    func collider(_ root: Entity) -> Entity? {
        if root.components[CollisionComponent.self] != nil { return root }
        return root.children.lazy.compactMap(collider).first
    }
    let original = try await RealityViewportSpatialResources.prepare(batch: batch(0))
    let changed = try await RealityViewportSpatialResources.prepare(batch: batch(1), reusing: original)
    let first = try #require(collider(original.root))
    let second = try #require(collider(changed.root))
    let shape = try #require(first.components[CollisionComponent.self]?.shapes.first)
    #expect(first !== second)
    #expect(shape == second.components[CollisionComponent.self]?.shapes.first)
    #expect(original.handleIndex(for: first) == 0)
    #expect(changed.handleIndex(for: second) == 1)
    #expect(changed.handleIndex(for: first) == nil)
    second.position.x = 20
    #expect(first.position.x != second.position.x)
    let empty = try await RealityViewportSpatialResources.prepare(batch:
        .init(renderOrigin: .origin, retainedSurfaceByteCount: 0), reusing: changed)
    let retired = try await RealityViewportSpatialResources.prepare(batch: batch(0), reusing: empty)
    #expect(try #require(collider(retired.root)).components[CollisionComponent.self]?.shapes.first != shape)
}
