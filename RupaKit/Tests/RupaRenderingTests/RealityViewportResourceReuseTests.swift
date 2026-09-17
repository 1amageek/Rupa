import Foundation
import CoreGraphics
import Metal
import RealityKit
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import Testing
import simd

@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportReusesEqualNativeAssetsAcrossSnapshotUpdates() async throws {
    let baseScene = try planCacheScene(suffix: "resource-reuse-base")
    let baseItem = try #require(baseScene.items.first)
    let translated = try GeometryTransform3D(values: [
        1, 0, 0, 2,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    let addedID = SceneOccurrenceID(rawValue: "occurrence.resource-reuse-added")
    let addedBounds = try baseItem.mesh.bounds().transformed(by: translated)
    let addedItem = UniversalViewportSceneItem(
        id: addedID,
        definitionID: baseItem.definitionID,
        displayName: "Resource reuse added occurrence",
        representationID: baseItem.representationID,
        reference: baseItem.reference,
        mesh: baseItem.mesh,
        worldTransform: translated,
        worldBounds: addedBounds
    )
    let nextScene = UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: baseScene.projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision(1)
        ),
        projectID: baseScene.projectID,
        items: baseScene.items + [addedItem]
    )
    let changedSource = try planCacheScene(
        suffix: "resource-reuse-changed", projectID: baseScene.projectID,
        transform: GeometryTransform3D(values: [
            2, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    )
    let changedScene = UniversalViewportScene(
        snapshotID: .init(projectID: baseScene.projectID, purpose: .presentation,
                          sourceRevision: DocumentTransactionRevision(2)),
        projectID: baseScene.projectID, items: changedSource.items
    )

    let baseViewport = try await RealityViewport.prepare(
        plan: try MeshSourcePresentationRenderPlan(scene: baseScene)
    )
    let nextViewport = try await RealityViewport.prepare(
        plan: try MeshSourcePresentationRenderPlan(scene: nextScene),
        spatialBatch: nil,
        reusing: baseViewport
    )
    let changedViewport = try await RealityViewport.prepare(
        plan: try MeshSourcePresentationRenderPlan(scene: changedScene),
        spatialBatch: nil,
        reusing: nextViewport
    )

    let baseSurfaces = surfaceEntities(in: baseViewport)
    let nextSurfaces = surfaceEntities(in: nextViewport)
    let changedSurfaces = surfaceEntities(in: changedViewport)
    #expect(baseSurfaces.count == 1)
    #expect(nextSurfaces.count == 2)
    #expect(changedSurfaces.count == 1)
    #expect(baseSurfaces[0] !== nextSurfaces[0])

    let baseMesh = try #require(baseSurfaces[0].components[ModelComponent.self]?.mesh)
    let nextMesh = try #require(nextSurfaces[0].components[ModelComponent.self]?.mesh)
    let changedMesh = try #require(changedSurfaces[0].components[ModelComponent.self]?.mesh)
    #expect(baseMesh === nextMesh)
    #expect(nextSurfaces[1].components[ModelComponent.self]?.mesh === baseMesh)
    #expect(changedMesh !== nextMesh)

    let baseShape = try #require(baseSurfaces[0].components[CollisionComponent.self]?.shapes.first)
    let nextShape = try #require(nextSurfaces[0].components[CollisionComponent.self]?.shapes.first)
    let changedShape = try #require(changedSurfaces[0].components[CollisionComponent.self]?.shapes.first)
    #expect(baseShape == nextShape)
    #expect(nextSurfaces[1].components[CollisionComponent.self]?.shapes.first == baseShape)
    #expect(changedShape != nextShape)

    let baseLine = try #require(lineMeshes(in: baseViewport).first)
    let nextLine = try #require(lineMeshes(in: nextViewport).first)
    let changedLine = try #require(lineMeshes(in: changedViewport).first)
    #expect(baseLine === nextLine)
    #expect(changedLine !== nextLine)
    #expect(nextViewport.maximumNativeUploadDuration == .zero)

    let nextRenderer = try RealityRenderer()
    nextRenderer.entities.append(nextViewport.root)
    nextRenderer.activeCamera = nextViewport.camera
    try nextViewport.applyCamera(layout: ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 3, height: 1), size: CGSize(width: 64, height: 64),
        camera: .init(), basis: .axisFront(.z), verticalBounds: 0...1
    ), displayScale: 2, revision: 1)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        do {
            try nextRenderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
        } catch { continuation.resume(throwing: error) }
    }
    let retainedHit = try #require(nextViewport.root.scene?.raycast(
        origin: [0.25, 0.25, 0.5], direction: [0, 0, -1], length: 2
    ).first)
    #expect(try #require(nextViewport.triangle(for: retainedHit)).occurrenceID == baseItem.id)
    let addedHit = try #require(
        nextViewport.root.scene?.raycast(
            origin: [2.25, 0.25, 0.5], direction: [0, 0, -1], length: 2
        ).first
    )
    let addedTriangle = try #require(nextViewport.triangle(for: addedHit))
    #expect(addedTriangle.occurrenceID == addedID)
    func pixels() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: 64 * 4,
                             from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
        }
        return bytes
    }
    let committedPixels = pixels()

    // Solid previews own drawing buffers, preserve shear, and never mutate
    // another occurrence sharing the committed native asset.
    let mutation = Transform3D(matrix: try Matrix4x4(values: [
        1, 0.5, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
    ]))
    try nextViewport.applyObjectPreviews([baseItem.id.rawValue: mutation], displayMode: .solid)
    let previewMesh = try #require(nextSurfaces[0].model?.mesh)
    #expect(previewMesh !== baseMesh)
    #expect(nextSurfaces[1].model?.mesh === baseMesh)
    let previewBounds = nextSurfaces[0].visualBounds(relativeTo: nextViewport.root)
    #expect(abs(previewBounds.min.x - 1) < 0.00001)
    #expect(abs(previewBounds.max.x - 2.5) < 0.00001)
    #expect(nextSurfaces[0].model?.materials.isEmpty == false)
    try nextViewport.applyObjectPreviews([baseItem.id.rawValue: mutation], displayMode: .solid)
    #expect(nextSurfaces[0].model?.mesh === previewMesh)
    try nextViewport.applyObjectPreviews([:], displayMode: .solid, snapshotID: changedScene.snapshotID)
    #expect(nextSurfaces[0].model?.mesh === previewMesh, "A retained predecessor must not flash its baseline.")
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try nextViewport.surfaceHit(at: .zero, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try nextViewport.occurrenceIDs(intersecting: .init(x: 0, y: 0, width: 64, height: 64), revision: 1)
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        do {
            try nextRenderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
        } catch { continuation.resume(throwing: error) }
    }
    try nextViewport.applyObjectPreviews([:], displayMode: .solid)
    #expect(zip(committedPixels, pixels()).filter { $0 != $1 }.count > 100,
            "The GPU must draw the changed solid, not merely update metadata.")
    #expect(nextSurfaces[0].model?.mesh === baseMesh)
    #expect(nextSurfaces[1].model?.mesh === baseMesh)
    let occurrence = try #require(MeshSourcePresentationRenderPlan(scene: nextScene).occurrences.first)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try RealityViewportObjectPreview(occurrence: occurrence, availableBytes: 1)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func resourceCacheWithdrawsSourceAssetsOnFailureAndTeardown() async throws {
    let baseScene = try planCacheScene(suffix: "resource-cache-base")
    let failingScene = try planCacheScene(suffix: "resource-cache-failing")
    let failingSnapshotID = failingScene.snapshotID
    let cache = MeshSourcePresentationPlanCache { scene in
        if scene.snapshotID == failingSnapshotID {
            throw MeshSourcePresentationRenderError(code: .failed, message: "Injected source replacement failure.")
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    let baseIdentity = resourceReuseIdentity(for: baseScene)
    let failingIdentity = resourceReuseIdentity(for: failingScene)

    cache.prepare(resourceReuseRequest(scene: baseScene, identity: baseIdentity))
    try await waitForReady(cache)
    weak var weakBaseSurface = cache.surface(for: baseIdentity)
    #expect(weakBaseSurface != nil)
    let baseRoot = try #require(weakBaseSurface?.root)
    let baseMesh: MeshResource
    do {
        let surface = try #require(weakBaseSurface)
        baseMesh = try #require(surfaceEntities(in: surface).first?.model?.mesh)
    }
    let replacementScene = UniversalViewportScene(
        snapshotID: .init(projectID: baseScene.projectID, purpose: .presentation,
                          sourceRevision: DocumentTransactionRevision(1)),
        projectID: baseScene.projectID, items: baseScene.items
    )
    let replacementIdentity = resourceReuseIdentity(for: replacementScene)
    cache.prepare(resourceReuseRequest(scene: replacementScene, identity: replacementIdentity))
    #expect(cache.surface(for: baseIdentity) == nil)
    #expect(cache.surface(for: replacementIdentity) == nil)
    #expect(cache.displaySurface(for: baseIdentity) == nil)
    #expect(cache.displaySurface(for: replacementIdentity) == nil)
    #expect(baseRoot.isEnabled == false)
    try await waitForReady(cache)
    try await waitForRelease { weakBaseSurface == nil }
    weak var replacementSurface = cache.surface(for: replacementIdentity)
    let replacementRoot = try #require(replacementSurface?.root)
    #expect(replacementRoot !== baseRoot)
    #expect(surfaceEntities(in: try #require(replacementSurface)).first?.model?.mesh === baseMesh)

    cache.prepare(resourceReuseRequest(scene: failingScene, identity: failingIdentity))
    #expect(cache.surface(for: baseIdentity) == nil)
    #expect(cache.displaySurface(for: baseIdentity) == nil)
    #expect(cache.displaySurface(for: failingIdentity) == nil)
    #expect(cache.surface(for: replacementIdentity) == nil)
    #expect(cache.displaySurface(for: replacementIdentity) == nil)
    #expect(replacementRoot.isEnabled == false)
    try await waitForFailure(cache)
    #expect(cache.failure(for: failingIdentity)?.message == "Injected source replacement failure.")
    #expect(cache.surface(for: failingIdentity) == nil)
    #expect(cache.displaySurface(for: failingIdentity) == nil)
    try await waitForRelease { replacementSurface == nil }

    cache.prepare(resourceReuseRequest(scene: baseScene, identity: baseIdentity))
    try await waitForReady(cache)
    weak var teardownSurface = cache.surface(for: baseIdentity)
    #expect(teardownSurface != nil)
    cache.teardown()
    if case .idle = cache.state {
        // The cache has withdrawn its only current owner.
    } else {
        Issue.record("Resource reuse teardown did not return the cache to idle.")
    }
    #expect(cache.surface(for: failingIdentity) == nil)
    try await waitForRelease { teardownSurface == nil }
}

@MainActor
private func surfaceEntities(in viewport: RealityViewport) -> [ModelEntity] {
    var result: [ModelEntity] = []
    func visit(_ entity: Entity) {
        if let model = entity as? ModelEntity,
           model.components[CollisionComponent.self] != nil {
            result.append(model)
        }
        for child in entity.children {
            visit(child)
        }
    }
    visit(viewport.root)
    return result
}

@MainActor
private func lineMeshes(in viewport: RealityViewport) -> [MeshResource] {
    var result: [MeshResource] = []
    func visit(_ entity: Entity) {
        if entity.components[CollisionComponent.self] == nil,
           let mesh = entity.components[ModelComponent.self]?.mesh {
            result.append(mesh)
        }
        for child in entity.children {
            visit(child)
        }
    }
    visit(viewport.root)
    return result
}

private let resourceReuseDocumentID = DocumentID()

private func resourceReuseIdentity(
    for scene: UniversalViewportScene
) -> RealityViewportPreparationRequest.Identity {
    .init(
        scene: ViewportSceneSnapshotKey(
            source: .document(id: resourceReuseDocumentID, generation: DocumentGeneration(1)),
            currentEvaluationGeneration: nil,
            evaluationCacheGeneration: nil,
            workspaceRenderState: .init(
                revision: WorkspaceRevision(),
                ruler: .standard(for: .millimeter)
            ),
            renderInvalidation: RenderInvalidation(),
            sectionClippingPlan: nil,
            objectDefinitions: []
        ),
        snapshotID: scene.snapshotID,
        overlayRevision: 0
    )
}

private func resourceReuseRequest(
    scene: UniversalViewportScene,
    identity: RealityViewportPreparationRequest.Identity
) -> RealityViewportPreparationRequest {
    .init(
        identity: identity,
        scene: scene,
        fallbackOrigin: .origin,
        spatialOverlay: { origin, charge in
            (
                try RealityViewportSpatialBatch(
                    renderOrigin: origin,
                    retainedSurfaceByteCount: charge
                ),
                []
            )
        }
    )
}

@MainActor
private func waitForReady(_ cache: MeshSourcePresentationPlanCache) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if case .ready = cache.state { return }
        if case let .failed(_, error) = cache.state { throw error }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw MeshSourcePresentationRenderError(code: .failed, message: "Resource reuse cache did not become ready.")
}

@MainActor
private func waitForFailure(_ cache: MeshSourcePresentationPlanCache) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if case .failed = cache.state { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw MeshSourcePresentationRenderError(code: .failed, message: "Resource reuse cache did not publish failure.")
}

@MainActor
private func waitForRelease(_ released: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !released(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(released())
}
