import AppKit
import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

@Suite(.serialized)
@MainActor
struct RealityViewportReplacementContinuityTests {
    @Test(.timeLimit(.minutes(1)))
    func sourceReplacementRetainsDisplayButRefusesStaleInput() async throws {
        let scene = try planCacheScene(suffix: "continuity")
        let cache = MeshSourcePresentationPlanCache()
        func identity(_ scene: UniversalViewportScene) -> RealityViewportPreparationRequest.Identity {
            .init(scene: .init(source: .presentation(scene.snapshotID),
                currentEvaluationGeneration: nil, evaluationCacheGeneration: nil,
                workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
                renderInvalidation: RenderInvalidation(), sectionClippingPlan: nil, objectDefinitions: []),
                snapshotID: scene.snapshotID, overlayRevision: 0)
        }
        let initial = identity(scene)
        func request(_ scene: UniversalViewportScene) -> RealityViewportPreparationRequest {
            .init(identity: identity(scene), scene: scene, fallbackOrigin: .origin,
                  spatialOverlay: { origin, bytes in
                      (try RealityViewportSpatialBatch(renderOrigin: origin, retainedSurfaceByteCount: bytes), [])
                  })
        }
        cache.prepare(request(scene))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while cache.surface(for: initial) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        let displayed = try #require(cache.surface(for: initial))
        let next = UniversalViewportScene(
            snapshotID: .init(projectID: scene.projectID, purpose: .presentation,
                              sourceRevision: DocumentTransactionRevision(1)),
            projectID: scene.projectID, items: scene.items)
        let nextIdentity = identity(next)
        cache.prepare(request(next))
        #expect(displayed.root.isEnabled)
        #expect(cache.displayCandidate(for: nextIdentity) === displayed)
        #expect(cache.surface(for: initial) == nil)
        #expect(cache.displaySurface(for: nextIdentity) == nil)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try cache.surfaceHit(at: .zero, for: nextIdentity, revision: 1)
        }
        cache.reject(nextIdentity, error: .init(code: .failed, message: "Injected capture failure"))
        #expect(displayed.root.isEnabled)
        #expect(cache.displayCandidate(for: nextIdentity) === displayed)
        cache.teardown()
        #expect(!displayed.root.isEnabled)
    }

    @Test(.timeLimit(.minutes(1)))
    func mountedReplacementNeverRemovesBothPictures() async throws {
        _ = NSApplication.shared
        let plan = try MeshSourcePresentationRenderPlan(scene: planCacheScene(suffix: "mounted-continuity"))
        func prepare(_ origin: Point3D) async throws -> RealityViewport {
            try await RealityViewport.prepare(plan: plan,
                spatialBatch: RealityViewportSpatialBatch(renderOrigin: origin, retainedSurfaceByteCount: plan.retainedByteCount),
                reusing: nil)
        }
        let first = try await prepare(.origin)
        let next = try await prepare(Point3D(x: 0.1, y: 0, z: 0))
        let size = CGSize(width: 512, height: 384)
        func view(_ viewport: RealityViewport, revision: UInt64) -> some View {
            RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                shading: .init(style: .flat), occurrenceMaterials: [:],
                layout: .init(modelBounds: CGRect(x: 0, y: -0.5, width: 1, height: 1), size: size,
                              camera: .init(zoom: 0.6), basis: .axisFront(.z), verticalBounds: 0...1),
                interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                                   previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0, onUpdateResult: { _ in })
                .frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(first, revision: 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        defer { window.contentViewController = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !first.isCameraReady(revision: 1) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        func hasVisibleGeometry(_ entity: Entity) -> Bool {
            guard entity.isEnabledInHierarchy, entity.scene != nil else { return false }
            if entity.components[ModelComponent.self] != nil { return true }
            return entity.children.contains { hasVisibleGeometry($0) }
        }
        #expect(hasVisibleGeometry(first.root))
        controller.rootView = view(next, revision: 2)
        window.contentView?.layoutSubtreeIfNeeded()
        while !next.isCameraReady(revision: 2) {
            try #require(ContinuousClock.now < deadline)
            #expect(hasVisibleGeometry(first.root) || hasVisibleGeometry(next.root),
                    "A camera readiness wait must not blank both model roots.")
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(hasVisibleGeometry(next.root))
        #expect(first.root.scene == nil)
    }
}
