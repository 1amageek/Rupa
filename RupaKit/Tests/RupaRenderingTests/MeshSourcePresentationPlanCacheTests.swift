import AppKit
import Foundation
import CoreGraphics
import Metal
import RealityKit
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import Synchronization
import Testing
import SwiftCAD
import SwiftUI
import simd
@testable import RupaRendering

private let planCacheDocumentID = DocumentID()

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeScaledPrimitiveCollisionPreservesSubmillimeterExtent() async throws {
    let renderer = try RealityRenderer()
    let root = Entity()
    let camera = Entity()
    var lens = OrthographicCameraComponent()
    lens.scale = 0.01
    lens.near = 0.01
    lens.far = 0.2
    camera.components.set(lens)
    camera.position.z = 0.1
    root.addChild(camera)
    let target = Entity()
    root.addChild(target)
    renderer.entities.append(root)
    renderer.activeCamera = camera
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    for sphere in [false, true] {
        for scaled in [false, true] {
            let extent: Float = scaled ? 1 : 0.0002
            let shape = sphere ? ShapeResource.generateSphere(radius: extent / 2) : ShapeResource.generateBox(size: SIMD3(repeating: extent))
            target.components.set(CollisionComponent(shapes: [shape]))
            target.scale = SIMD3(repeating: scaled ? 0.0002 : 1)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output, onComplete: { _ in continuation.resume() })
                } catch { continuation.resume(throwing: error) }
            }
            let scene = try #require(root.scene)
            let offsets: [Float] = [0, 0.00005, 0.00015, 0.0005, 0.0015]
            let hits = offsets.map { x in
                scene.raycast(origin: [x, 0, 0.1], direction: [0, 0, -1], length: 0.2).contains { $0.entity === target }
            }
            #expect(hits == (scaled
                ? [true, true, false, false, false]
                : [true, true, true, true, false]))
        }
    }
}

private func planCacheIdentity(
    _ scene: UniversalViewportScene?,
    overlayRevision: UInt64 = 0,
    generation: UInt64 = 1
) -> RealityViewportPreparationRequest.Identity {
    .init(scene: ViewportSceneSnapshotKey(
        source: .document(id: planCacheDocumentID, generation: DocumentGeneration(generation)),
        currentEvaluationGeneration: nil, evaluationCacheGeneration: nil,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        renderInvalidation: RenderInvalidation(), sectionClippingPlan: nil, objectDefinitions: []),
          snapshotID: scene?.snapshotID, overlayRevision: overlayRevision)
}

private extension MeshSourcePresentationPlanCache {
    func prepare(for scene: UniversalViewportScene) {
        prepare(.init(identity: planCacheIdentity(scene), scene: scene, fallbackOrigin: .origin,
                      spatialOverlay: { origin, charge in
            (try RealityViewportSpatialBatch(renderOrigin: origin, retainedSurfaceByteCount: charge), [])
        }))
    }
    func surface(for scene: UniversalViewportScene) -> RealityViewport? { surface(for: planCacheIdentity(scene)) }
    func failure(for scene: UniversalViewportScene) -> MeshSourcePresentationRenderError? { failure(for: planCacheIdentity(scene)) }
    func isPreparing(_ scene: UniversalViewportScene) -> Bool { isPreparing(planCacheIdentity(scene)) }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeHandleTableResolvesOnlyTheMatchingPublishedFrame() async throws {
    let cache = MeshSourcePresentationPlanCache()
    let featureID = FeatureID()
    let reference = SelectionReference.surface(.controlPoint(.init(
        surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "surface", ordinal: 0),
                                      geometrySignature: .vertex(point: .origin))), uIndex: 1, vIndex: 2)))
    func record(point: SwiftCAD.Point3D) throws -> ViewportSpatialInteractionRecord {
        try .init(target: .surfaceControlPoint(.init(
            featureID: featureID, target: reference, point: point,
            modelTransform: .identity, dragMode: .planar)), occurrenceID: "surface.first")
    }
    let firstHandle = try record(point: .init(x: 1, y: 2, z: 3))
    let secondHandle = try record(point: .init(x: 4, y: 5, z: 6))
    func expectBaseline(_ actual: ViewportSpatialInteractionRecord?, matches expected: ViewportSpatialInteractionRecord) {
        #expect(actual?.identity == expected.identity)
        #expect(actual?.occurrenceID == expected.occurrenceID)
        if case .surfaceControlPoint(let value) = actual?.target,
           case .surfaceControlPoint(let baseline) = expected.target {
            #expect(value.point == baseline.point)
            #expect(value.target == baseline.target)
        } else { Issue.record("The native index lost its prepared drag baseline.") }
    }
    let first = planCacheIdentity(nil, overlayRevision: 101)
    let second = planCacheIdentity(nil, overlayRevision: 102)
    func request(_ identity: RealityViewportPreparationRequest.Identity,
                 handle: ViewportSpatialInteractionRecord) -> RealityViewportPreparationRequest {
        .init(identity: identity, scene: nil, fallbackOrigin: .origin, spatialOverlay: { origin, charge in
            let input = ViewportSpatialOverlayInput(
                markers: [.init(family: .transform,
                                value: .init(shape: .box, anchor: .origin, diameterPoints: 8,
                                             color: [1, 0, 0, 1], handleIndex: 0, hitTolerancePoints: 12))],
                interactionRecords: [handle], renderOrigin: origin,
                retainedSurfaceByteCount: charge, topologyRevision: identity.overlayRevision)
            return try ViewportSpatialOverlayProducer.makeBuilder(from: input)(origin, charge)
        })
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    #expect(cache.interactionRecord(at: 0, for: first) == nil)
    cache.prepare(request(first, handle: firstHandle))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    #expect(cache.interactionRecord(at: 0, for: first) == nil)
    try await settlePlanCache(cache)
    expectBaseline(cache.interactionRecord(at: 0, for: first), matches: firstHandle)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    let prepared = try #require(cache.surface(for: first))
    func nativeHandleIndex(_ entity: Entity) -> UInt32? {
        if let index = prepared.spatialHandleIndex(for: entity) { return index }
        for child in entity.children {
            if let index = nativeHandleIndex(child) { return index }
        }
        return nil
    }
    let nativeIndex = try #require(nativeHandleIndex(prepared.root))
    expectBaseline(cache.interactionRecord(at: nativeIndex, for: first), matches: firstHandle)
    #expect(cache.interactionRecord(at: 1, for: first) == nil)
    // `second` differs from the published frame by overlay revision alone, so
    // the frame the view is displaying is what a pointer could have addressed,
    // and it answers with the table it drew. The changed-scene identity below
    // is the negative that keeps this rule falsifiable.
    expectBaseline(cache.interactionRecord(at: 0, for: second), matches: firstHandle)
    #expect(cache.interactionRecord(at: 0, for: planCacheIdentity(nil, overlayRevision: 101, generation: 2)) == nil)
    cache.prepare(request(second, handle: secondHandle))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    // The rebuild is in flight: the first frame is still displayed, so it still
    // answers for both identities with the table it drew.
    expectBaseline(cache.interactionRecord(at: 0, for: first), matches: firstHandle)
    expectBaseline(cache.interactionRecord(at: 0, for: second), matches: firstHandle)
    try await settlePlanCache(cache)
    expectBaseline(cache.interactionRecord(at: 0, for: second), matches: secondHandle)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    // The published frame moved on, so the superseded overlay identity is
    // answered by the table now displayed, never by the retired one.
    expectBaseline(cache.interactionRecord(at: 0, for: first), matches: secondHandle)
    #expect(cache.interactionRecord(at: 0, for: planCacheIdentity(nil, overlayRevision: 102, generation: 2)) == nil)
    cache.teardown()
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: second, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: second, revision: 1)
    }
    #expect(cache.interactionRecord(at: 0, for: second) == nil)

    // A mismatched native count must fail before any handle gains authority.
    cache.prepare(.init(identity: first, scene: nil, fallbackOrigin: .origin, spatialOverlay: { origin, charge in
        (try RealityViewportSpatialBatch(renderOrigin: origin, retainedSurfaceByteCount: charge), [firstHandle])
    }))
    try await settlePlanCacheFailure(cache)
    #expect(cache.failure(for: first)?.code == .invalidSceneItem)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: first, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: first, revision: 1)
    }
    #expect(cache.interactionRecord(at: 0, for: first) == nil)
    cache.teardown()

    cache.prepare(.init(identity: second, scene: nil, fallbackOrigin: .origin, spatialOverlay: { origin, charge in
        (try RealityViewportSpatialBatch(handleCount: 1, renderOrigin: origin, retainedSurfaceByteCount: charge), [secondHandle])
    }))
    try await settlePlanCacheFailure(cache)
    #expect(cache.failure(for: second)?.code == .invalidSceneItem)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: .zero, for: second, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: second, revision: 1)
    }
    #expect(cache.interactionRecord(at: 0, for: second) == nil)
    cache.teardown()
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func nativeMeshElementsAcceptOutsideSilhouetteTolerance(perspective: Bool) async throws {
    _ = NSApplication.shared
    let base = try planCacheScene(suffix: perspective ? "mesh-tolerance-perspective" : "mesh-tolerance-ortho")
    let near = try #require(base.items.first)
    func translated(_ suffix: String, z: Double) throws -> UniversalViewportSceneItem {
        let transform = try GeometryTransform3D(values: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, z, 0, 0, 0, 1])
        return .init(id: SceneOccurrenceID(rawValue: near.occurrenceID.rawValue + suffix),
                     definitionID: near.definitionID, displayName: suffix, representationID: near.representationID,
                     reference: near.reference, mesh: near.mesh, copyTelemetry: near.copyTelemetry,
                     worldTransform: transform, worldBounds: try near.mesh.bounds().transformed(by: transform))
    }
    let far = try translated(".far", z: -1)
    let items = perspective ? [far, try translated(".behind-camera", z: 1_000), near] : [far, near]
    let scene = UniversalViewportScene(snapshotID: base.snapshotID, projectID: base.projectID,
                                      items: items, copyTelemetry: base.copyTelemetry)
    let identity = planCacheIdentity(scene)
    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: scene))
    let plan = try #require(cache.plan(for: scene))
    defer { viewport.unbind(); cache.teardown() }
    let size = CGSize(width: 512, height: 384)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1), size: size,
        camera: .init(zoom: 0.6, projection: perspective ? .standardPerspective : .parallel),
        basis: .axisFront(.z), verticalBounds: 0...1)
    var failure: MeshSourcePresentationRenderError?
    let controller = NSHostingController(rootView: RealityViewportView(
        viewport: viewport, viewportRevision: 1, displayMode: .solid,
        shading: .init(style: .flat), materialColors: [:], layout: layout,
        interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
        sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
        onUpdateResult: { failure = $0 }
    ).frame(width: size.width, height: size.height))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while viewport.appliedViewportRevision != 1 || viewport.project(.origin) == nil {
        try #require(ContinuousClock.now < deadline)
        if let failure { throw failure }
        try await Task.sleep(for: .milliseconds(10))
    }
    let center = try cache.project(.init(x: 0.5, y: 0.5, z: 0), for: identity, revision: 1)
    let corner = try cache.project(.origin, for: identity, revision: 1)
    let edge = try cache.project(.init(x: 0, y: 0.5, z: 0), for: identity, revision: 1)
    func outside(_ anchor: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = anchor.x - center.x, dy = anchor.y - center.y
        let length = hypot(dx, dy)
        return .init(x: anchor.x + dx / length * distance, y: anchor.y + dy / length * distance)
    }
    var expectedVertex: MeshVertexID?
    var expectedEdge: MeshEdgeID?
    plan.forEachTriangle { triangle in
        let vertices = [(triangle.firstVertexID, triangle.firstPosition),
                        (triangle.secondVertexID, triangle.secondPosition),
                        (triangle.thirdVertexID, triangle.thirdPosition)]
        for (id, position) in vertices where position.x == 0 && position.y == 0 { expectedVertex = id }
        let edges = [triangle.firstEdgeID, triangle.secondEdgeID, triangle.thirdEdgeID]
        for side in 0..<3 where vertices[side].1.x == 0 && vertices[(side + 1) % 3].1.x == 0 {
            expectedEdge = edges[side]
        }
    }
    let vertexID = try #require(expectedVertex)
    let edgeID = try #require(expectedEdge)
    #expect(try cache.meshElement(at: center, domain: .face, for: identity, revision: 1)?.occurrenceID == near.occurrenceID)
    #expect(try cache.meshElement(at: center, domain: .edge, for: identity, revision: 1) == nil,
            "Tessellation diagonals are not source edges.")
    #expect(try cache.meshElement(at: outside(edge, distance: 7), domain: .edge, for: identity, revision: 1)?.element == .edge(edgeID))
    #expect(try cache.meshElement(at: outside(corner, distance: 7), domain: .vertex, for: identity, revision: 1)?.element == .vertex(vertexID))
    #expect(try cache.meshElement(at: outside(edge, distance: 7), domain: .edge, for: identity, revision: 1)?.occurrenceID == near.occurrenceID)
    #expect(try cache.meshElement(at: outside(edge, distance: 9), domain: .edge, for: identity, revision: 1) == nil)
    #expect(try cache.meshElement(at: outside(corner, distance: 9), domain: .vertex, for: identity, revision: 1) == nil)
    #expect(try cache.meshElement(at: outside(edge, distance: 7), domain: .face, for: identity, revision: 1) == nil)
    if perspective {
        let occludedEdge = try cache.project(.init(x: 0, y: 0.5, z: -1), for: identity, revision: 1)
        #expect(hypot(edge.x - occludedEdge.x, edge.y - occludedEdge.y) > 8)
        #expect(try cache.meshElement(at: occludedEdge, domain: .edge, for: identity, revision: 1) == nil)
    }
    let section = SectionAnalysisResult.Plane(sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
        origin: .init(x: 0.5, y: 0, z: 0), normal: .init(x: 1, y: 0, z: 0),
        u: .init(x: 0, y: 1, z: 0), v: .init(x: 0, y: 0, z: 1))
    try viewport.applySection(plane: section, side: .front, tolerance: 0)
    #expect(try cache.meshElement(at: outside(edge, distance: 7), domain: .edge, for: identity, revision: 1) == nil)
    #expect(try cache.meshElement(at: outside(corner, distance: 7), domain: .vertex, for: identity, revision: 1) == nil)
    let retainedFace = try cache.project(.init(x: 0.75, y: 0.5, z: 0), for: identity, revision: 1)
    #expect(try cache.meshElement(at: retainedFace, domain: .face, for: identity, revision: 1)?.occurrenceID == near.occurrenceID)
    try viewport.applySection(plane: nil, side: .front, tolerance: 0)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.meshElement(at: edge, domain: .edge, for: identity, revision: 2)
    }
    viewport.setPresentationEnabled(false)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.meshElement(at: corner, domain: .vertex, for: identity, revision: 1)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func nativeMountedInteractionRecordsResolveOrthoAndPerspectiveHits(
    perspective: Bool
) async throws {
    _ = NSApplication.shared
    let cache = MeshSourcePresentationPlanCache()
    let identity = planCacheIdentity(nil, overlayRevision: perspective ? 202 : 201)
    let featureID = FeatureID()
    let reference = SelectionReference.surface(.controlPoint(.init(
        surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "native-interaction", ordinal: 0),
                                      geometrySignature: .vertex(point: .origin))), uIndex: 0, vIndex: 0)))
    let record = try ViewportSpatialInteractionRecord(
        target: .surfaceControlPoint(.init(
            featureID: featureID, target: reference, point: .origin,
            modelTransform: .identity, dragMode: .planar)),
        occurrenceID: "native.interaction")
    let request = RealityViewportPreparationRequest(
        identity: identity, scene: nil, fallbackOrigin: .origin,
        spatialOverlay: { origin, charge in
            let input = ViewportSpatialOverlayInput(
                markers: [.init(family: .transform,
                                value: .init(shape: .sphere, anchor: .origin, diameterPoints: 12,
                                             color: [1, 0, 0, 1], handleIndex: 0, hitTolerancePoints: 8))],
                interactionRecords: [record], renderOrigin: origin,
                retainedSurfaceByteCount: charge, topologyRevision: identity.overlayRevision)
            return try ViewportSpatialOverlayProducer.makeBuilder(from: input)(origin, charge)
        })
    cache.prepare(request)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: identity))
    defer { viewport.unbind(); cache.teardown() }

    let size = CGSize(width: 512, height: 384)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02), size: size,
        camera: .init(zoom: 0.2, projection: perspective ? .standardPerspective : .parallel),
        basis: .axisFront(.z), verticalBounds: -0.01...0.01)
    var reportedError: MeshSourcePresentationRenderError?
    let interaction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
        previewSceneNodeIDs: [], hoveredSceneNodeID: nil)
    let controller = NSHostingController(
        rootView: RealityViewportView(
            viewport: viewport, viewportRevision: 1, displayMode: .solid,
            shading: .init(style: .flat), materialColors: [:], layout: layout,
            interaction: interaction, sectionPlane: nil, retainedSide: .front,
            sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }
        ).frame(width: size.width, height: size.height))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }

    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var center: CGPoint?
    while ContinuousClock.now < deadline {
        controller.view.layoutSubtreeIfNeeded()
        if let reportedError { throw reportedError }
        if viewport.appliedViewportRevision == 1,
           let projected = viewport.project(.origin) {
            center = projected
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    let screenCenter = try #require(center)
    let strictProjection = try cache.project(.origin, for: identity, revision: 1)
    #expect(hypot(strictProjection.x - screenCenter.x, strictProjection.y - screenCenter.y) <= 0.1)
    let hits = try cache.interactionRecords(at: screenCenter, for: identity, revision: 1)
    #expect(hits.count == 1)
    #expect(hits.first?.identity == record.identity)
    #expect(hits.first?.occurrenceID == record.occurrenceID)
    let materialized = try record.materialize { try cache.project($0, for: identity, revision: 1) }
    guard case .projectionFree = materialized else {
        Issue.record("The native record lost its projection-free input route.")
        return
    }
    let radialRecord = try ViewportSpatialInteractionRecord(target: .patternArrayRadialAngle(.init(
        sourceID: .init(), title: "Native radial input", center: .origin, axis: .unitZ,
        referencePoint: .init(x: 0.01, y: 0, z: 0), angleRadians: 0.5,
        displayAngleRadians: nil, angleMode: .spacing, state: .normal)))
    let radialInput = try radialRecord.materialize { try cache.project($0, for: identity, revision: 1) }
    guard case .patternArrayRadialAngle(_, let radial) = radialInput else {
        Issue.record("The native radial record did not materialize.")
        return
    }
    let radialTip = try cache.project(.init(x: 0.01, y: 0, z: 0), for: identity, revision: 1)
    let tangentTip = try cache.project(.init(x: 0, y: 0.01, z: 0), for: identity, revision: 1)
    #expect(radial.center == strictProjection)
    #expect(abs(radial.radialVector.dx - (radialTip.x - strictProjection.x)) < 0.01)
    #expect(abs(radial.tangentVector.dy - (tangentTip.y - strictProjection.y)) < 0.01)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try radialRecord.materialize { try cache.project($0, for: identity, revision: 2) }
    }
    #expect(try cache.interactionRecords(at: CGPoint(x: -10_000, y: -10_000), for: identity, revision: 1).isEmpty)

    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: screenCenter, for: identity, revision: 2)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: CGPoint(x: CGFloat.nan, y: screenCenter.y), for: identity, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: identity, revision: 2)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.init(x: .nan, y: 0, z: 0), for: identity, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try viewport.project(.origin, revision: 2)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try viewport.project(.init(x: .nan, y: 0, z: 0), revision: 1)
    }

    window.contentViewController = nil
    window.close()
    let unmountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while viewport.appliedViewportRevision != nil, ContinuousClock.now < unmountDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.interactionRecords(at: screenCenter, for: identity, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.project(.origin, for: identity, revision: 1)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeFrameCacheCoalescesOverlayIdentityAndMountsWithoutSurface() async throws {
    let scene = try planCacheScene(suffix: "overlay-revision")
    let gate = PlanBuildGate()
    let started = Mutex(0)
    let cache = MeshSourcePresentationPlanCache { scene in
        let index = started.withLock { $0 += 1; return $0 }
        await gate.arrive(String(index))
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    func request(_ scene: UniversalViewportScene?, revision: UInt64) -> RealityViewportPreparationRequest {
        .init(identity: planCacheIdentity(scene, overlayRevision: revision), scene: scene, fallbackOrigin: .origin,
              spatialOverlay: { origin, charge in
            (try RealityViewportSpatialBatch(
                meshes: [.init(positions: [.origin, .init(x: 1, y: 0, z: 0)], indices: [0, 1],
                                topology: .lines, color: [0, 1, 0, 1])],
                renderOrigin: origin, retainedSurfaceByteCount: charge), [])
        })
    }
    cache.prepare(request(scene, revision: 1))
    await gate.waitForArrival("1")
    cache.prepare(request(scene, revision: 2))
    cache.prepare(request(scene, revision: 3))
    await gate.open("1")
    await gate.waitForArrival("2")
    #expect(cache.surface(for: planCacheIdentity(scene, overlayRevision: 1)) == nil)
    #expect(cache.isPreparing(planCacheIdentity(scene, overlayRevision: 3)))
    await gate.open("2")
    try await settlePlanCache(cache)
    let ready = try #require(cache.surface(for: planCacheIdentity(scene, overlayRevision: 3)))
    cache.prepare(request(scene, revision: 4))
    #expect(ready.root.isEnabled, "An overlay-only preparation must not blank the displayed scene.")
    #expect(cache.displaySurface(for: planCacheIdentity(scene, overlayRevision: 4)) === ready)
    // `surface(for:)` reports whether this identity's own frame is prepared,
    // which during an overlay-only rebuild it is not. Query authority is a
    // separate rule: the frame the view is still displaying answers for the
    // pending overlay identity, because those are the pixels a pointer can have
    // addressed. The mounted assertions at the end of this test prove it.
    #expect(cache.surface(for: planCacheIdentity(scene, overlayRevision: 4)) == nil,
            "An overlay-only rebuild must not report the pending frame as prepared.")
    try await settlePlanCache(cache)
    #expect(started.withLock { $0 } == 2, "Overlay-only replacement rebuilt the surface plan.")
    #expect(cache.surface(for: planCacheIdentity(scene, overlayRevision: 3)) == nil)
    #expect(cache.surface(for: planCacheIdentity(scene, overlayRevision: 4))?.maximumNativeUploadDuration == .zero)
    let replacement = try #require(cache.surface(for: planCacheIdentity(scene, overlayRevision: 4)))
    let rejected = planCacheIdentity(scene, overlayRevision: 5)
    cache.reject(rejected, error: .init(code: .failed, message: "Rejected overlay fixture."))
    #expect(cache.displaySurface(for: rejected) === replacement)
    #expect(replacement.root.isEnabled)
    #expect(cache.surface(for: rejected) == nil)
    #expect(cache.failure(for: rejected) != nil)
    cache.prepare(request(nil, revision: 5))
    #expect(!replacement.root.isEnabled)
    #expect(cache.displaySurface(for: planCacheIdentity(nil, overlayRevision: 5)) == nil)
    try await settlePlanCache(cache)
    let empty = try #require(cache.surface(for: planCacheIdentity(nil, overlayRevision: 5)))
    let emptyIdentity = planCacheIdentity(nil, overlayRevision: 5)
    #expect(empty.snapshotID == nil)
    #expect(empty.root.children.contains { $0 === empty.camera })
    #expect(started.withLock { $0 } == 2)

    // The exact-ready surface is not queryable until its native root is mounted.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: .zero, for: emptyIdentity, revision: 5)
    }

    let emptySize = CGSize(width: 512, height: 384)
    let emptyLayout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1), size: emptySize,
        camera: .init(zoom: 0.6), basis: .axisFront(.z), verticalBounds: 0...1
    )
    let emptyInteraction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
        previewSceneNodeIDs: [], hoveredSceneNodeID: nil
    )
    var emptyMountError: MeshSourcePresentationRenderError?
    let emptyController = NSHostingController(
        rootView: RealityViewportView(
            viewport: empty, viewportRevision: 5, displayMode: .solid,
            shading: .init(style: .flat), materialColors: [:], layout: emptyLayout,
            interaction: emptyInteraction, sectionPlane: nil, retainedSide: .front,
            sectionTolerance: 0,
            onUpdateResult: { emptyMountError = $0 }
        ).frame(width: emptySize.width, height: emptySize.height)
    )
    let emptyWindow = NSWindow(
        contentRect: CGRect(origin: .zero, size: emptySize), styleMask: [.titled],
        backing: .buffered, defer: false
    )
    emptyWindow.isReleasedWhenClosed = false
    emptyWindow.contentViewController = emptyController
    emptyWindow.orderFront(nil)
    defer {
        emptyWindow.contentViewController = nil
        emptyWindow.close()
    }
    let emptyDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < emptyDeadline,
          (empty.appliedViewportRevision != 5 || empty.root.scene == nil) {
        emptyController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(emptyMountError == nil)
    #expect(empty.appliedViewportRevision == 5)
    #expect(empty.root.scene != nil)
    let mountedEmptyMiss = try cache.surfaceHit(
        at: CGPoint(x: emptySize.width / 2, y: emptySize.height / 2),
        for: emptyIdentity, revision: 5
    )
    #expect(mountedEmptyMiss == nil)

    // An overlay-only rebuild starting from the mounted frame. The frame stays
    // displayed and stays the query authority, so the same point that answered a
    // truthful miss above answers one again instead of becoming unavailable.
    let pendingOverlay = planCacheIdentity(nil, overlayRevision: 6)
    cache.prepare(request(nil, revision: 6))
    #expect(cache.isPreparing(pendingOverlay))
    #expect(empty.root.isEnabled)
    #expect(cache.displaySurface(for: pendingOverlay) === empty)
    #expect(cache.surface(for: pendingOverlay) == nil)
    #expect(cache.hasReadyCamera(for: pendingOverlay, revision: 5))
    #expect(try cache.surfaceHit(
        at: CGPoint(x: emptySize.width / 2, y: emptySize.height / 2),
        for: pendingOverlay, revision: 5
    ) == nil)
    #expect(try cache.interactionRecords(
        at: CGPoint(x: emptySize.width / 2, y: emptySize.height / 2),
        for: pendingOverlay, revision: 5
    ).isEmpty)

    // A failure recorded for the requested identity keeps the frame displayed
    // but withdraws its authority, so display and queries never disagree about
    // which frame the viewport is showing.
    let rejectedOverlay = planCacheIdentity(nil, overlayRevision: 7)
    cache.reject(rejectedOverlay, error: .init(code: .failed, message: "Rejected mounted overlay fixture."))
    #expect(empty.root.isEnabled)
    #expect(cache.displaySurface(for: rejectedOverlay) === empty)
    #expect(cache.failure(for: rejectedOverlay) != nil)
    #expect(cache.hasReadyCamera(for: rejectedOverlay, revision: 5) == false)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(
            at: CGPoint(x: emptySize.width / 2, y: emptySize.height / 2),
            for: rejectedOverlay, revision: 5
        )
    }

    emptyWindow.contentViewController = nil
    emptyWindow.close()
    cache.teardown()
    #expect(!empty.root.isEnabled)

    // Idle and preparing states are unavailable rather than legitimate misses.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: .zero, for: emptyIdentity, revision: 5)
    }
    cache.prepare(request(nil, revision: 8))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: .zero, for: planCacheIdentity(nil, overlayRevision: 8), revision: 5)
    }
    cache.teardown()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func overlayReplacementSharesSurfaceAssetsButNotEntities() async throws {
    let scene = try planCacheScene(suffix: "overlay-assets")
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    func batch(_ color: SIMD4<Float>) throws -> RealityViewportSpatialBatch {
        try RealityViewportSpatialBatch(markers: [.init(shape: .box, anchor: .origin, diameterPoints: 8, color: color)],
                                        renderOrigin: .origin, retainedSurfaceByteCount: plan.retainedByteCount)
    }
    let first = try await RealityViewport.prepare(plan: plan, spatialBatch: batch([1, 0, 0, 1]), reusing: nil)
    let second = try await RealityViewport.prepare(plan: plan, spatialBatch: batch([0, 1, 0, 1]), reusing: first)
    func surfaces(_ root: Entity) -> [Entity] {
        (root.components[CollisionComponent.self] == nil ? [] : [root]) + root.children.flatMap { surfaces($0) }
    }
    let a = try #require(surfaces(first.root).first)
    let b = try #require(surfaces(second.root).first)
    #expect(a !== b)
    #expect(a.components[ModelComponent.self]?.mesh === b.components[ModelComponent.self]?.mesh)
    // Component access exposes ShapeResource's native value-equality contract,
    // not a stable Swift wrapper reference (the existing instance test uses it too).
    #expect(a.components[CollisionComponent.self]?.shapes.first == b.components[CollisionComponent.self]?.shapes.first)
    #expect(second.maximumNativeUploadDuration == .zero)
    b.position.x += 2
    #expect(a.position != b.position)
    let wrongCharge = try RealityViewportSpatialBatch(renderOrigin: .origin, retainedSurfaceByteCount: 0)
    await #expect(throws: MeshSourcePresentationRenderError.self) {
        try await RealityViewport.prepare(plan: plan, spatialBatch: wrongCharge, reusing: first)
    }
    let fullItemBudget = try RealityViewportSpatialBatch(
        markers: Array(repeating: .init(shape: .box, anchor: .origin, diameterPoints: 8, color: [1, 1, 1, 1]), count: 640),
        renderOrigin: .origin, retainedSurfaceByteCount: plan.retainedByteCount)
    await #expect(throws: MeshSourcePresentationRenderError.self) {
        try await RealityViewport.prepare(plan: plan, spatialBatch: fullItemBudget, reusing: first)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeMaterialColorChangesWithoutGeometryReplacement() async throws {
    let scene = try planCacheScene(suffix: "material-update")
    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: scene))
    defer { cache.teardown() }
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    renderer.cameraSettings.isToneMappingEnabled = false
    renderer.entities.append(viewport.root)
    renderer.activeCamera = viewport.camera
    let layout = ViewportLayout(modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                size: CGSize(width: 96, height: 96), camera: .init(zoom: 0.6),
                                basis: .axisFront(.z), verticalBounds: 0...0)
    try viewport.applyCamera(layout: layout, revision: 1)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                              width: 96, height: 96, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    let sample = try #require(layout.projectedPoint(Point3D(x: 0.25, y: 0.25, z: 0))).point
    let sampleX = Int(sample.x.rounded())
    let sampleY = Int(sample.y.rounded())
    try #require((0..<96).contains(sampleX) && (0..<96).contains(sampleY))
    let interaction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil
    )
    func apply(_ color: ColorRGBA?) throws {
        try viewport.applyAppearance(displayMode: .solid, shading: .init(style: .flat, solidColor: .material),
                                     materialColors: color.map { [scene.items[0].id: $0] } ?? [:], interaction: interaction,
                                     sectionPlane: nil, retainedSide: .front, sectionTolerance: 0)
    }
    func renderedPixel() async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
            } catch { continuation.resume(throwing: error) }
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(sampleX, sampleY, 1, 1), mipmapLevel: 0)
        return pixel
    }
    var originalMesh: MeshResource?
    for (color, channel) in [(ColorRGBA(r: 1, g: 0, b: 0, a: 1), 2),
                             (ColorRGBA(r: 0, g: 0, b: 1, a: 1), 0)] {
        try apply(color)
        let pixel = try await renderedPixel()
        #expect(pixel[channel] > 200 && pixel[2 - channel] < 20, "Material-only update rendered BGRA \(pixel)")
        let nativeScene = try #require(viewport.root.scene)
        let hit = try #require(nativeScene.raycast(origin: [0.5, 0.5, 2], direction: [0, 0, -1], length: 3).first)
        let mesh = try #require(hit.entity.components[ModelComponent.self]?.mesh)
        if let originalMesh { #expect(mesh === originalMesh) } else { originalMesh = mesh }
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try apply(ColorRGBA(r: .nan, g: 0, b: 0, a: 1))
    }
    let preserved = try await renderedPixel()
    #expect(preserved[0] > 200 && preserved[2] < 20, "Failed appearance update changed BGRA \(preserved)")
    let nativeScene = try #require(viewport.root.scene)
    let hit = try #require(nativeScene.raycast(origin: [0.5, 0.5, 2], direction: [0, 0, -1], length: 3).first)
    #expect(hit.entity.components[ModelComponent.self]?.mesh === originalMesh)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeMountedViewportProjectsAndPicksAcrossCameraChanges() async throws {
    _ = NSApplication.shared
    let scene = try planCacheScene(suffix: "mounted-camera")
    let cache = MeshSourcePresentationPlanCache()
    let identity = planCacheIdentity(scene)
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: scene))
    defer { viewport.unbind(); cache.teardown() }

    func firstCollisionSurface(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity,
           model.components[CollisionComponent.self] != nil {
            return model
        }
        for child in entity.children {
            if let surface = firstCollisionSurface(in: child) {
                return surface
            }
        }
        return nil
    }
    try viewport.validateSurfaceCompleteness()
    let collisionSurface = try #require(firstCollisionSurface(in: viewport.root))
    let savedCollision = try #require(collisionSurface.components[CollisionComponent.self])
    collisionSurface.components.remove(CollisionComponent.self)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try viewport.validateSurfaceCompleteness()
    }
    collisionSurface.components.set(savedCollision)
    try viewport.validateSurfaceCompleteness()

    let size = CGSize(width: 512, height: 384)
    let world = Point3D(x: 0.2, y: 0.3, z: 0)
    var reportedError: MeshSourcePresentationRenderError?
    let interaction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
        previewSceneNodeIDs: [], hoveredSceneNodeID: nil
    )
    func view(_ layout: ViewportLayout, revision: UInt64) -> some View {
        RealityViewportView(
            viewport: viewport, viewportRevision: revision, displayMode: .solid,
            shading: .init(style: .flat), materialColors: [:],
            layout: layout, interaction: interaction, sectionPlane: nil,
            retainedSide: .front, sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }
        ).frame(width: size.width, height: size.height)
    }
    var layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1), size: size,
        camera: .init(zoom: 0.6), basis: .axisFront(.z), verticalBounds: 0...1
    )
    let controller = NSHostingController(rootView: view(layout, revision: 1))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }

    func entities(_ entity: Entity) -> [ObjectIdentifier] {
        [ObjectIdentifier(entity)] + entity.children.flatMap { entities($0) }
    }
    let originalEntities = entities(viewport.root)
    var revision: UInt64 = 0
    for projection in [ViewportCameraProjection.standardPerspective, .parallel] {
        for offset in [false, true] {
            for basis in [ViewportProjectionBasis.axisFront(.z),
                          .interpolated(from: .isometric, to: .axisFront(.z), progress: 0.5)] {
                revision += 1
                layout = ViewportLayout(
                    modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1), size: size,
                    camera: .init(zoom: 0.6, pan: offset ? CGSize(width: 17, height: -11) : .zero,
                                  projection: projection),
                    basis: basis, verticalBounds: 0...1,
                    fittingInsets: offset ? .init(top: 20, leading: 45, bottom: 70, trailing: 10) : .zero
                )
                let expected = try #require(layout.projectedPoint(world)).point
                controller.rootView = view(layout, revision: revision)
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                var matched = false
                var lastHitPosition: Point3D?
                // This observes native query convergence after a real SwiftUI
                // mount/update, not a GPU-presented-frame acknowledgement.
                while ContinuousClock.now < deadline {
                    controller.view.layoutSubtreeIfNeeded()
                    if let error = reportedError { throw error }
                    if viewport.appliedViewportRevision == revision,
                       let actual = viewport.project(world),
                       hypot(actual.x - expected.x, actual.y - expected.y) < 0.1,
                       let hit = viewport.hitTest(actual, revision: revision).first {
                        let position = Point3D(
                            x: Double(hit.position.x) + viewport.renderOrigin.x,
                            y: Double(hit.position.y) + viewport.renderOrigin.y,
                            z: Double(hit.position.z) + viewport.renderOrigin.z
                        )
                        lastHitPosition = position
                        guard position.isApproximatelyEqual(to: world, tolerance: 1e-4) else {
                            try await Task.sleep(for: .milliseconds(10))
                            continue
                        }
                        let triangle = try #require(viewport.triangle(for: hit))
                        #expect(triangle.occurrenceID.rawValue == "occurrence.plan-cache.mounted-camera")
                        let surfaceHit = try #require(try cache.surfaceHit(at: actual, for: identity, revision: revision))
                        #expect(surfaceHit.triangle.occurrenceID == triangle.occurrenceID)
                        #expect(surfaceHit.triangle.faceID == triangle.faceID)
                        #expect(surfaceHit.point.isApproximatelyEqual(to: world, tolerance: 1e-4))
                        #expect(viewport.hitTest(actual, revision: revision - 1).isEmpty)
                        matched = true
                        break
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                try #require(matched, "Mounted query mismatch: revision=\(revision), expected=\(expected), actual=\(String(describing: viewport.project(world))), applied=\(String(describing: viewport.appliedViewportRevision)), lastHit=\(String(describing: lastHitPosition))")
                #expect(viewport.hitTest(CGPoint(x: CGFloat.nan, y: 0), revision: revision).isEmpty)
                #expect(viewport.hitTest(CGPoint(x: -1_000, y: -1_000), revision: revision).isEmpty)
                let nativeWorld = SIMD3<Float>(Float(world.x - viewport.renderOrigin.x),
                                              Float(world.y - viewport.renderOrigin.y),
                                              Float(world.z - viewport.renderOrigin.z))
                let depth = -viewport.camera.convert(position: nativeWorld, from: nil).z
                // Change only the native clipping interval: geometry remains
                // intersectable, but input must exclude the invisible surface.
                if let original = viewport.camera.components[OrthographicCameraComponent.self] {
                    var clipped = original
                    clipped.near = depth * 1.1
                    clipped.far = depth * 2
                    viewport.camera.components.set(clipped)
                    #expect(viewport.hitTest(expected, revision: revision).isEmpty)
                    let clippedSurfaceHit = try cache.surfaceHit(at: expected, for: identity, revision: revision)
                    #expect(clippedSurfaceHit == nil)
                    clipped.near = depth * 0.1
                    clipped.far = depth * 0.9
                    viewport.camera.components.set(clipped)
                    #expect(viewport.hitTest(expected, revision: revision).isEmpty)
                    let clippedSurfaceHitAfterFar = try cache.surfaceHit(at: expected, for: identity, revision: revision)
                    #expect(clippedSurfaceHitAfterFar == nil)
                    viewport.camera.components.set(original)
                } else if let original = viewport.camera.components[PerspectiveCameraComponent.self] {
                    var clipped = original
                    clipped.near = depth * 1.1
                    clipped.far = depth * 2
                    viewport.camera.components.set(clipped)
                    #expect(viewport.hitTest(expected, revision: revision).isEmpty)
                    let clippedSurfaceHit = try cache.surfaceHit(at: expected, for: identity, revision: revision)
                    #expect(clippedSurfaceHit == nil)
                    clipped.near = depth * 0.1
                    clipped.far = depth * 0.9
                    viewport.camera.components.set(clipped)
                    #expect(viewport.hitTest(expected, revision: revision).isEmpty)
                    let clippedSurfaceHitAfterFar = try cache.surfaceHit(at: expected, for: identity, revision: revision)
                    #expect(clippedSurfaceHitAfterFar == nil)
                    viewport.camera.components.set(original)
                }
                let restoredSurfaceHit = try #require(
                    try cache.surfaceHit(at: expected, for: identity, revision: revision)
                )
                #expect(restoredSurfaceHit.point.isApproximatelyEqual(to: world, tolerance: 1e-4))
                #expect(entities(viewport.root) == originalEntities)
            }
        }
    }
    let miss = try cache.surfaceHit(at: CGPoint(x: -1_000, y: -1_000), for: identity, revision: revision)
    #expect(miss == nil)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: CGPoint(x: 0, y: 0), for: identity, revision: revision - 1)
    }
    // An overlay-only rebuild keeps the mounted frame as the query authority,
    // so this resolves against the drawn pixels and reports a truthful miss.
    // A changed snapshot is a different drawing and withdraws authority.
    #expect(
        try cache.surfaceHit(
            at: CGPoint(x: 0, y: 0),
            for: planCacheIdentity(scene, overlayRevision: 99), revision: revision
        ) == nil
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: CGPoint(x: 0, y: 0), for: planCacheIdentity(nil, overlayRevision: 99), revision: revision)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.surfaceHit(at: CGPoint(x: CGFloat.nan, y: 0), for: identity, revision: revision)
    }
    window.contentViewController = nil
    window.close()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while viewport.appliedViewportRevision != nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(viewport.appliedViewportRevision == nil)
    #expect(viewport.project(world) == nil)
    #expect(viewport.hitTest(.zero, revision: revision).isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func nativeSurfaceHitChoosesNearestOverlappingSurfaceAndRestoresWorldOrigin(
    perspective: Bool
) async throws {
    _ = NSApplication.shared
    let nearTransform = try GeometryTransform3D(values: [
        1, 0, 0, 10,
        0, 1, 0, 20,
        0, 0, 1, 30,
        0, 0, 0, 1,
    ])
    let farTransform = try GeometryTransform3D(values: [
        1, 0, 0, 10,
        0, 1, 0, 20,
        0, 0, 1, 29,
        0, 0, 0, 1,
    ])
    let baseScene = try planCacheScene(suffix: "overlapping-surfaces", transform: nearTransform)
    let nearItem = try #require(baseScene.items.first)
    let farOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.plan-cache.overlapping-surfaces.far")
    let farItem = UniversalViewportSceneItem(
        id: farOccurrenceID,
        definitionID: nearItem.definitionID,
        displayName: "Far overlapping surface",
        representationID: nearItem.representationID,
        reference: nearItem.reference,
        mesh: nearItem.mesh,
        copyTelemetry: nearItem.copyTelemetry,
        worldTransform: farTransform,
        worldBounds: try nearItem.mesh.bounds().transformed(by: farTransform)
    )
    let scene = UniversalViewportScene(
        snapshotID: baseScene.snapshotID,
        projectID: baseScene.projectID,
        items: [nearItem, farItem],
        copyTelemetry: baseScene.copyTelemetry
    )
    let cache = MeshSourcePresentationPlanCache()
    let identity = planCacheIdentity(scene)
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let plan = try #require(cache.plan(for: scene))
    #expect(plan.itemCount == 2)
    let viewport = try #require(cache.surface(for: scene))
    defer { viewport.unbind(); cache.teardown() }
    #expect(viewport.renderOrigin == Point3D(x: 10, y: 20, z: 30))
    try viewport.validateSurfaceCompleteness()

    let size = CGSize(width: 512, height: 384)
    let camera = ViewportCamera(
        zoom: 0.6,
        projection: perspective ? .standardPerspective : .parallel
    )
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 10, y: 29, width: 1, height: 2),
        size: size,
        camera: camera,
        basis: .axisFront(.z),
        verticalBounds: 20...21
    )
    let nearPoint = Point3D(x: 10.2, y: 20.3, z: 30)
    let expected = try #require(layout.projectedPoint(nearPoint)).point
    var reportedError: MeshSourcePresentationRenderError?
    let interaction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
        previewSceneNodeIDs: [], hoveredSceneNodeID: nil
    )
    let controller = NSHostingController(
        rootView: RealityViewportView(
            viewport: viewport, viewportRevision: 1, displayMode: .solid,
            shading: .init(style: .flat), materialColors: [:], layout: layout,
            interaction: interaction, sectionPlane: nil, retainedSide: .front,
            sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }
        ).frame(width: size.width, height: size.height)
    )
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
        backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }

    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var actual: CGPoint?
    while ContinuousClock.now < deadline {
        controller.view.layoutSubtreeIfNeeded()
        if let reportedError { throw reportedError }
        if viewport.appliedViewportRevision == 1,
           let projected = viewport.project(nearPoint),
           hypot(projected.x - expected.x, projected.y - expected.y) <= 1 {
            actual = projected
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    let queryPoint = try #require(actual)
    let hit = try #require(try cache.surfaceHit(at: queryPoint, for: identity, revision: 1))
    #expect(hit.triangle.occurrenceID.rawValue == "occurrence.plan-cache.overlapping-surfaces")
    #expect(hit.point.isApproximatelyEqual(to: nearPoint, tolerance: 1e-4))
    #expect(hit.point.z > 29.5)
}

// MARK: - Off-actor preparation

@MainActor
@Test(.timeLimit(.minutes(1)))
func planPreparationRunsOffTheMainActor() async throws {
    let scene = try planCacheScene(suffix: "off-main")
    let hasStarted = Mutex(false)
    let mayFinish = Mutex(false)
    let cache = MeshSourcePresentationPlanCache { scene in
        hasStarted.withLock { $0 = true }
        // Spin without suspending. A build that ran on `MainActor` could never
        // observe the release below, because only `MainActor` publishes it, so
        // this loop is what proves the build left `MainActor`.
        while mayFinish.withLock({ $0 }) == false {
            continue
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    #expect(cache.isPreparing(scene))
    #expect(cache.plan(for: scene) == nil)

    while hasStarted.withLock({ $0 }) == false {
        await Task.yield()
    }
    mayFinish.withLock { $0 = true }

    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planPreparationDoesNotCompleteOnTheCallingActor() async throws {
    let scene = try planCacheScene(suffix: "not-synchronous")
    let cache = MeshSourcePresentationPlanCache()

    cache.prepare(for: scene)

    guard case let .preparing(snapshotID) = cache.state else {
        Issue.record("Plan preparation must not complete on the calling actor.")
        return
    }
    #expect(snapshotID.snapshotID == scene.snapshotID)
    #expect(cache.plan(for: scene) == nil)
    #expect(cache.failure(for: scene) == nil)

    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Identity

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheExposesReadyPlanOnlyToItsOwnScene() async throws {
    let scene = try planCacheScene(suffix: "identity")
    let otherScene = try planCacheScene(suffix: "identity-other")
    let cache = MeshSourcePresentationPlanCache()

    cache.prepare(for: scene)
    try await settlePlanCache(cache)

    #expect(cache.plan(for: scene) != nil)
    #expect(cache.plan(for: otherScene) == nil)
    #expect(cache.isPreparing(otherScene) == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheIgnoresARepeatedPrepareForTheSameScene() async throws {
    let scene = try planCacheScene(suffix: "repeat")
    let buildCount = Mutex(0)
    let cache = MeshSourcePresentationPlanCache { scene in
        buildCount.withLock { $0 += 1 }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    cache.prepare(for: scene)
    await Task.yield()

    #expect(buildCount.withLock { $0 } == 1)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Staleness

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheDiscardsAStaleSuccess() async throws {
    let firstScene = try planCacheScene(suffix: "stale-success-first")
    let secondScene = try planCacheScene(suffix: "stale-success-second")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(firstScene.snapshotID.projectID.rawValue)

    // The scene changes while the first build is parked at the gate.
    cache.prepare(for: secondScene)
    #expect(cache.isPreparing(secondScene))

    // Releasing the superseded build must publish nothing.
    await gate.open(firstScene.snapshotID.projectID.rawValue)
    await Task.yield()
    #expect(cache.plan(for: firstScene) == nil)
    #expect(cache.isPreparing(secondScene))

    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: secondScene) != nil)
    #expect(cache.plan(for: firstScene) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheDiscardsAStaleFailure() async throws {
    let firstScene = try planCacheScene(suffix: "stale-failure-first")
    let secondScene = try planCacheScene(suffix: "stale-failure-second")
    let failingProjectID = firstScene.snapshotID.projectID.rawValue
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        if scene.snapshotID.projectID.rawValue == failingProjectID {
            throw MeshSourcePresentationRenderError(
                code: .failed,
                message: "Superseded build failed."
            )
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(failingProjectID)
    cache.prepare(for: secondScene)

    await gate.open(failingProjectID)
    await Task.yield()
    #expect(cache.failure(for: firstScene) == nil)
    #expect(cache.isPreparing(secondScene))

    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: secondScene) != nil)
}

// MARK: - Failure

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCachePublishesAMatchingFailure() async throws {
    let scene = try planCacheScene(suffix: "failure")
    let cache = MeshSourcePresentationPlanCache { _ in
        throw MeshSourcePresentationRenderError(
            code: .resourceExhausted,
            message: "Presentation plan exceeded its ceiling."
        )
    }

    cache.prepare(for: scene)
    try await settlePlanCacheFailure(cache)

    let failure = try #require(cache.failure(for: scene))
    #expect(failure.code == .resourceExhausted)
    #expect(cache.plan(for: scene) == nil)
    #expect(cache.isPreparing(scene) == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheRecordsNothingForACancelledBuild() async throws {
    let scene = try planCacheScene(suffix: "cancelled")
    let cache = MeshSourcePresentationPlanCache { _ in
        throw CancellationError()
    }

    cache.prepare(for: scene)
    for _ in 0..<32 {
        await Task.yield()
    }

    // A cancellation is not a failure, so the state stays `preparing` until a
    // newer scene or a teardown replaces it.
    #expect(cache.isPreparing(scene))
    #expect(cache.failure(for: scene) == nil)
    #expect(cache.plan(for: scene) == nil)
}

// MARK: - Cancellation and teardown

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCancelsTheBuildASceneChangeSupersedes() async throws {
    let firstScene = try planCacheScene(suffix: "cancel-first")
    let secondScene = try planCacheScene(suffix: "cancel-second")
    let gate = PlanBuildGate()
    let observedCancellation = Mutex(false)
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        if Task.isCancelled {
            observedCancellation.withLock { $0 = true }
            throw CancellationError()
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: firstScene)
    await gate.waitForArrival(firstScene.snapshotID.projectID.rawValue)
    cache.prepare(for: secondScene)
    await gate.open(firstScene.snapshotID.projectID.rawValue)
    await gate.open(secondScene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)

    #expect(observedCancellation.withLock { $0 })
    #expect(cache.plan(for: secondScene) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheTeardownReturnsToIdleAndDiscardsALaterCompletion() async throws {
    let scene = try planCacheScene(suffix: "teardown")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive(scene.snapshotID.projectID.rawValue)
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }

    cache.prepare(for: scene)
    await gate.waitForArrival(scene.snapshotID.projectID.rawValue)
    cache.teardown()

    guard case .idle = cache.state else {
        Issue.record("Teardown must return the plan cache to idle.")
        return
    }

    await gate.open(scene.snapshotID.projectID.rawValue)
    for _ in 0..<32 {
        await Task.yield()
    }

    guard case .idle = cache.state else {
        Issue.record("A completion after teardown must be discarded.")
        return
    }
    #expect(cache.plan(for: scene) == nil)

    // A torn-down cache still accepts the same scene again.
    cache.prepare(for: scene)
    await gate.open(scene.snapshotID.projectID.rawValue)
    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
}

// MARK: - Support

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativePresentationCachePreservesProjectionAndSourceFaceIdentity() async throws {
    let scene = try planCacheScene(suffix: "native-camera")
    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: scene))
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    renderer.cameraSettings.isToneMappingEnabled = false
    renderer.entities.append(viewport.root)
    renderer.activeCamera = viewport.camera
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 512, height: 384, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    for projection in [ViewportCameraProjection.parallel, .perspective(fieldOfViewRadians: .pi / 3)] {
        var camera = ViewportCamera.identity
        camera.projection = projection
        camera.zoom = 0.6
        let layout = ViewportLayout(modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                    size: CGSize(width: 512, height: 384), camera: camera,
                                    basis: .isometric, verticalBounds: 0...0,
                                    fittingInsets: .init(top: 20, leading: 45, bottom: 70, trailing: 10))
        try viewport.applyCamera(layout: layout, revision: 7)
        #expect(viewport.camera.components[ProjectiveTransformCameraComponent.self] == nil)
        switch projection {
        case .parallel:
            #expect(viewport.camera.components[OrthographicCameraComponent.self] != nil)
            #expect(viewport.camera.components[PerspectiveCameraComponent.self] == nil)
        case .perspective:
            #expect(viewport.camera.components[PerspectiveCameraComponent.self] != nil)
            #expect(viewport.camera.components[OrthographicCameraComponent.self] == nil)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
            } catch { continuation.resume(throwing: error) }
        }
        let screenPoint = try #require(layout.projectedPoint(Point3D(x: 0.25, y: 0.25, z: 0)))
        let x = Int(screenPoint.point.x.rounded())
        let y = Int(screenPoint.point.y.rounded())
        try #require((0..<512).contains(x) && (0..<384).contains(y))
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        if !(pixel[0] > 20 && pixel[1] > 20 && pixel[2] > 20) {
            var pixels = [UInt8](repeating: 0, count: 512 * 384 * 4)
            texture.getBytes(&pixels, bytesPerRow: 512 * 4, from: MTLRegionMake2D(0, 0, 512, 384), mipmapLevel: 0)
            var bounds = CGRect.null
            for row in 0..<384 {
                for column in 0..<512 where pixels[(row * 512 + column) * 4] > 20 {
                    bounds = bounds.union(CGRect(x: column, y: row, width: 1, height: 1))
                }
            }
            Issue.record("Native camera \(projection), sample=(\(x),\(y)), BGRA=\(pixel), rendered bounds=\(bounds), scale=\(layout.scale)")
        }
        #expect(viewport.appliedViewportRevision == 7)
    }
    let section = SectionAnalysisResult.Plane(sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
                                               origin: Point3D(x: 0.5, y: 0, z: 0),
                                               normal: Vector3D(x: 1, y: 0, z: 0),
                                               u: Vector3D(x: 0, y: 1, z: 0), v: Vector3D(x: 0, y: 0, z: 1))
    for side: SectionAnalysisRetainedSide? in [.front, .behind, nil] {
        try viewport.applySection(plane: side == nil ? nil : section, side: side ?? .front, tolerance: 0)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
            } catch { continuation.resume(throwing: error) }
        }
        let layout = try #require(viewport.appliedLayout)
        for pointX in [0.25, 0.75] {
            let projected = try #require(layout.projectedPoint(Point3D(x: pointX, y: 0.5, z: 0)))
            let x = Int(projected.point.x.rounded())
            let y = Int(projected.point.y.rounded())
            try #require((0..<512).contains(x) && (0..<384).contains(y))
            var pixel = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            let visible = side == nil || (side == .front ? pointX > 0.5 : pointX < 0.5)
            #expect((pixel[0] > 20) == visible, "Section \(String(describing: side)), x=\(pointX), BGRA=\(pixel)")
            let scene = try #require(viewport.root.scene)
            let hits = scene.raycast(origin: [Float(pointX), 0.5, 2], direction: [0, 0, -1], length: 5)
            #expect(!hits.isEmpty)
            #expect(!viewport.retainedHits(hits, rayDirection: [0, 0, -1]).isEmpty == visible)
        }
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try viewport.applySection(plane: section, side: .front, tolerance: .nan)
    }
    let originalBounds = viewport.root.visualBounds(relativeTo: viewport.root)
    var distantPlane = section
    distantPlane.origin = Point3D(x: 1e20, y: 0, z: 0)
    try viewport.applySection(plane: distantPlane, side: .behind, tolerance: 0)
    #expect(viewport.root.visualBounds(relativeTo: viewport.root) == originalBounds)
    let nativeScene = try #require(viewport.root.scene)
    for location in [SIMD3<Float>(0.2, 0.1, 2), SIMD3<Float>(0.8, 0.9, 2)] {
        let hit = try #require(nativeScene.raycast(origin: location, direction: [0, 0, -1], length: 5).first)
        let triangle = try #require(viewport.triangle(for: hit))
        #expect(triangle.occurrenceID.rawValue == "occurrence.plan-cache.native-camera")
        let a = triangle.firstPosition
        let b = triangle.secondPosition
        let c = triangle.thirdPosition
        let point = SIMD2<Double>(Double(hit.position.x), Double(hit.position.y))
        let signs = [(a, b), (b, c), (c, a)].map { start, end in
            (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
        }
        #expect(signs.allSatisfy { $0 >= -0.00001 } || signs.allSatisfy { $0 <= 0.00001 })
    }
    viewport.unbind()
    #expect(viewport.appliedViewportRevision == nil)
    #expect(viewport.hitTest(.zero, revision: 7).isEmpty)
    cache.teardown()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativePresentationBackfaceVisibilityMatchesCollision() async throws {
    _ = NSApplication.shared
    let scene = try planCacheScene(suffix: "native-backface")
    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(for: scene)
    try await settlePlanCache(cache)
    let viewport = try #require(cache.surface(for: scene))
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    renderer.cameraSettings.isToneMappingEnabled = false
    renderer.entities.append(viewport.root)
    renderer.activeCamera = viewport.camera

    var lens = OrthographicCameraComponent()
    lens.near = 0.01
    lens.far = 100
    lens.scale = 1
    viewport.camera.components.set(lens)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 128,
        height: 128,
        mipmapped: false
    )
    textureDescriptor.storageMode = .shared
    textureDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    let interaction = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [:],
        selectedSceneNodeIDs: [],
        previewSceneNodeIDs: [],
        hoveredSceneNodeID: nil
    )
    let nativeScene = try #require(viewport.root.scene)

    let sourceTriangleCount = try #require(cache.plan(for: scene)).triangleCount
    for (back, culling) in [(false, false), (true, false), (false, true), (true, true)] {
        let eye: SIMD3<Float> = back ? [0.5, 0.5, -3] : [0.5, 0.5, 3]
        viewport.camera.look(at: [0.5, 0.5, 0], from: eye, relativeTo: nil)
        try viewport.applyAppearance(
            displayMode: .solid,
            shading: ViewportShading(style: .flat, isBackfaceCullingEnabled: culling),
            materialColors: [:],
            interaction: interaction,
            sectionPlane: nil,
            retainedSide: .front,
            sectionTolerance: 0
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(
                    deltaTime: 1 / 60,
                    cameraOutput: output,
                    onComplete: { _ in continuation.resume() }
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }

        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: 128 * 4,
            from: MTLRegionMake2D(0, 0, 128, 128),
            mipmapLevel: 0
        )
        let center = (64 * 128 + 64) * 4
        let rendered = pixels[center..<center + 3].contains { $0 > 8 }
        #expect(rendered == !(back && culling), "Unexpected native material visibility.")
        let origin: SIMD3<Float> = back ? [0.2, 0.1, -2] : [0.2, 0.1, 2]
        let direction: SIMD3<Float> = back ? [0, 0, 1] : [0, 0, -1]
        let rawHits = nativeScene.raycast(origin: origin, direction: direction, length: 5)
        #expect(!rawHits.isEmpty, "Native raycast missed the quad from \(back ? "back" : "front").")
        let retainedHits = viewport.retainedHits(rawHits, rayDirection: direction)
        for hit in rawHits {
            let faceIndex = try #require(hit.triangleHit).faceIndex
            #expect(back
                    ? (sourceTriangleCount..<(2 * sourceTriangleCount)).contains(faceIndex)
                    : (0..<sourceTriangleCount).contains(faceIndex))
            let triangle = try #require(viewport.triangle(for: hit))
            #expect(triangle.occurrenceID.rawValue == "occurrence.plan-cache.native-backface")
            let a = triangle.firstPosition
            let b = triangle.secondPosition
            let c = triangle.thirdPosition
            let point = SIMD2<Double>(Double(hit.position.x), Double(hit.position.y))
            let signs = [(a, b), (b, c), (c, a)].map { start, end in
                (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
            }
            #expect(signs.allSatisfy { $0 >= -0.00001 } || signs.allSatisfy { $0 <= 0.00001 })
        }
        #expect(
            (!retainedHits.isEmpty) == rendered,
            "Backface state mismatch: back=\(back), culling=\(culling), rendered=\(rendered), retained=\(!retainedHits.isEmpty)"
        )
    }

    viewport.unbind()
    cache.teardown()
}

@Test
func nativeCollisionFaceMappingRejectsInvalidIndices() {
    #expect(RealityViewport.sourceTriangleIndex(for: 0, triangleCount: 2) == 0)
    #expect(RealityViewport.sourceTriangleIndex(for: 1, triangleCount: 2) == 1)
    #expect(RealityViewport.sourceTriangleIndex(for: 2, triangleCount: 2) == 0)
    #expect(RealityViewport.sourceTriangleIndex(for: 3, triangleCount: 2) == 1)
    #expect(RealityViewport.sourceTriangleIndex(for: 4, triangleCount: 2) == nil)
    #expect(RealityViewport.sourceTriangleIndex(for: -1, triangleCount: 2) == nil)
    #expect(RealityViewport.sourceTriangleIndex(for: 0, triangleCount: 0) == nil)
    #expect(RealityViewport.sourceTriangleIndex(for: Int.max, triangleCount: 2) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCoalescesAndRejectsFailureFromARestartedSnapshot() async throws {
    let scene = try planCacheScene(suffix: "restart")
    let skipped = try planCacheScene(suffix: "skipped")
    let gate = PlanBuildGate()
    let started = Mutex(0)
    let cache = MeshSourcePresentationPlanCache { scene in
        let index = started.withLock { count in
            count += 1
            return count
        }
        await gate.arrive(String(index))
        if index == 1 {
            throw MeshSourcePresentationRenderError(code: .failed, message: "Abandoned worker failure.")
        }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    cache.prepare(for: scene)
    await gate.waitForArrival("1")
    cache.teardown()
    cache.prepare(for: skipped)
    cache.prepare(for: scene)
    await gate.open("1")
    await gate.waitForArrival("2")
    #expect(cache.isPreparing(scene))
    #expect(cache.failure(for: scene) == nil)
    #expect(started.withLock { $0 } == 2)
    await gate.open("2")
    try await settlePlanCache(cache)
    #expect(cache.plan(for: scene) != nil)
    #expect(cache.surface(for: scene) != nil)
    #expect(started.withLock { $0 } == 2)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheReleasesNativeSurfaceAndRootOnReplacementAndTeardown() async throws {
    let firstScene = try planCacheScene(suffix: "release-first")
    let secondScene = try planCacheScene(suffix: "release-second")
    let cache = MeshSourcePresentationPlanCache()

    cache.prepare(for: firstScene)
    try await settlePlanCache(cache)
    weak var replacedViewport: RealityViewport?
    weak var replacedRoot: Entity?
    do {
        let surface = try #require(cache.surface(for: firstScene))
        replacedViewport = surface
        replacedRoot = surface.root
    }

    cache.prepare(for: secondScene)
    #expect(cache.surface(for: firstScene) == nil)
    #expect(cache.surface(for: secondScene) == nil)
    try await settlePlanCache(cache)
    let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while (replacedViewport != nil || replacedRoot != nil), ContinuousClock.now < replacementDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(replacedViewport == nil)
    #expect(replacedRoot == nil)

    weak var tornDownViewport: RealityViewport?
    weak var tornDownRoot: Entity?
    do {
        let surface = try #require(cache.surface(for: secondScene))
        tornDownViewport = surface
        tornDownRoot = surface.root
    }
    cache.teardown()
    guard case .idle = cache.state else {
        Issue.record("Teardown must release the native surface and return the cache to idle.")
        return
    }
    #expect(cache.surface(for: secondScene) == nil)
    let teardownDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while (tornDownViewport != nil || tornDownRoot != nil), ContinuousClock.now < teardownDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(tornDownViewport == nil)
    #expect(tornDownRoot == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCachePublishesNativePrecisionFailureAndRecoversWithTheNextScene() async throws {
    let tinyTransform = try GeometryTransform3D(values: [
        1e-100, 0, 0, 0,
        0, 1e-100, 0, 0,
        0, 0, 1e-100, 0,
        0, 0, 0, 1,
    ])
    let invalidScene = try planCacheScene(
        suffix: "native-precision-invalid",
        transform: tinyTransform
    )

    // The CPU plan and source triangulation remain valid; native Float
    // precision is the boundary that must report the typed failure.
    let cpuPlan = try MeshSourcePresentationRenderPlan(scene: invalidScene)
    #expect(cpuPlan.triangleCount == 2)
    #expect(cpuPlan.positionCount == 4)

    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(for: invalidScene)
    try await settlePlanCacheFailure(cache)
    let failure = try #require(cache.failure(for: invalidScene))
    #expect(failure.code == .invalidTransform)
    #expect(cache.plan(for: invalidScene) == nil)
    #expect(cache.surface(for: invalidScene) == nil)

    let validScene = try planCacheScene(suffix: "native-precision-recovery")
    cache.prepare(for: validScene)
    try await settlePlanCache(cache)
    #expect(cache.failure(for: validScene) == nil)
    #expect(cache.plan(for: validScene) != nil)
    #expect(cache.surface(for: validScene) != nil)
    cache.teardown()
}

/// Parks each build until the test opens its key, so staleness, cancellation,
/// and teardown are decided by the test rather than by construction timing.
@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCaptureRejectionWithdrawsPendingAndRejectsLateWorker() async throws {
    let scene = try planCacheScene(suffix: "capture-rejection")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { _ in
        await gate.arrive("started")
        throw MeshSourcePresentationRenderError(code: .failed, message: "Late abandoned worker.")
    }
    cache.prepare(for: scene)
    await gate.waitForArrival("started")
    let rejected = planCacheIdentity(nil, overlayRevision: 201)
    let failure = MeshSourcePresentationRenderError(code: .invalidSceneItem, message: "Invalid overlay capture.")
    cache.reject(rejected, error: failure)
    #expect(cache.failure(for: rejected) == failure)
    #expect(cache.surface(for: rejected) == nil)
    #expect(cache.surface(for: scene) == nil)
    let next = planCacheIdentity(nil, overlayRevision: 202)
    cache.prepare(.init(identity: next, scene: nil, fallbackOrigin: .origin, spatialOverlay: { origin, charge in
        (try RealityViewportSpatialBatch(renderOrigin: origin, retainedSurfaceByteCount: charge), [])
    }))
    await gate.open("started")
    try await settlePlanCache(cache)
    #expect(cache.surface(for: next) != nil)
    #expect(cache.failure(for: rejected) == nil)
    #expect(cache.surface(for: rejected) == nil)
    cache.teardown()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func planCacheCancelledCaptureCannotPrepareOrRejectNewerIdentity() async throws {
    let scene = try planCacheScene(suffix: "cancelled-capture-order")
    let gate = PlanBuildGate()
    let cache = MeshSourcePresentationPlanCache { scene in
        await gate.arrive("B")
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    cache.prepare(for: scene)
    await gate.waitForArrival("B")

    let cancelledIdentity = planCacheIdentity(nil, overlayRevision: 302)
    let captureCount = Mutex(0)
    let cancelledTask = Task { @MainActor in
        await Task.yield()
        cache.prepare(
            identity: cancelledIdentity,
            scene: nil,
            fallbackOrigin: .origin
        ) {
            captureCount.withLock { $0 += 1 }
            throw MeshSourcePresentationRenderError(
                code: .failed,
                message: "A cancelled capture must not reject the newer preparation."
            )
        }
    }
    cancelledTask.cancel()
    await cancelledTask.value

    #expect(captureCount.withLock { $0 } == 0)
    #expect(cache.isPreparing(scene))
    #expect(cache.failure(for: cancelledIdentity) == nil)

    await gate.open("B")
    try await settlePlanCache(cache)
    #expect(cache.surface(for: scene) != nil)
    #expect(cache.failure(for: scene) == nil)
    cache.teardown()
}

private actor PlanBuildGate {
    private var openedKeys: Set<String> = []
    private var arrivedKeys: Set<String> = []
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var arrivalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func arrive(_ key: String) async {
        arrivedKeys.insert(key)
        if let waiters = arrivalWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        if openedKeys.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters[key, default: []].append(continuation)
        }
    }

    func open(_ key: String) {
        openedKeys.insert(key)
        if let waiters = releaseWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitForArrival(_ key: String) async {
        if arrivedKeys.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            arrivalWaiters[key, default: []].append(continuation)
        }
    }
}

@MainActor
private func settlePlanCache(
    _ cache: MeshSourcePresentationPlanCache
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if case .ready = cache.state {
            return
        }
        if case let .failed(_, error) = cache.state {
            throw error
        }
        // GPU preparation can include cold shader compilation. Scheduler yield
        // counts are not a duration budget and can expire before that work runs.
        try await Task.sleep(for: .milliseconds(1))
    }
    throw MeshSourcePresentationRenderError(
        code: .failed,
        message: "The plan cache did not reach a ready state."
    )
}

@MainActor
private func settlePlanCacheFailure(
    _ cache: MeshSourcePresentationPlanCache
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if case .failed = cache.state {
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw MeshSourcePresentationRenderError(
        code: .failed,
        message: "The plan cache did not reach a failed state."
    )
}

func planCacheScene(
    suffix: String,
    projectID: ProjectID? = nil,
    transform: GeometryTransform3D = .identity
) throws -> UniversalViewportScene {
    let projectID = projectID ?? ProjectID(rawValue: "project.plan-cache.\(suffix)")
    let sourceID = GeometrySourceID(rawValue: "mesh.plan-cache.\(suffix)")
    let reference = GeometrySourceReference.authoredMesh(sourceID)

    var builder = MeshSourceBuilder(identity: sourceID)
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    let source = try builder.build()

    let definitionID = ObjectDefinitionID(rawValue: "object.plan-cache.\(suffix)")
    let representationID = GeometryRepresentationID(rawValue: "representation.plan-cache.\(suffix)")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.plan-cache.\(suffix)")

    let project = try ProjectSourceModel(
        id: projectID,
        name: "Plan cache",
        authoredMeshAssets: [
            sourceID: try AuthoredMeshAsset(source: source, provenance: .created)
        ],
        objectDefinitions: [
            definitionID: ObjectDefinition(
                id: definitionID,
                name: "Plan cache \(suffix)",
                representations: GeometryRepresentationSet(
                    representations: [
                        representationID: GeometryRepresentation(
                            id: representationID,
                            source: reference
                        )
                    ],
                    selection: GeometryRepresentationSelection(
                        modeling: representationID,
                        presentation: representationID
                    )
                )
            )
        ],
        occurrences: [
            occurrenceID: SceneOccurrence(
                id: occurrenceID,
                definitionID: definitionID
            )
        ],
        rootOccurrenceIDs: [occurrenceID]
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: [
            occurrenceID: EvaluatedOccurrenceSnapshot(
                occurrenceID: occurrenceID,
                definitionID: definitionID,
                representationID: representationID,
                reference: reference,
                mesh: source,
                worldTransform: transform,
                worldBounds: try source.bounds().transformed(by: transform)
            )
        ],
        copyTelemetry: GeometryCopyTelemetry()
    )
    return try UniversalViewportSceneBuilder().build(from: snapshot, project: project)
}
