import AppKit
import Foundation
import RealityKit
import RupaCore
import RupaCoreTypes
import RupaGeometry
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing

private func frameReadinessIdentity(
    overlayRevision: UInt64 = 1
) -> RealityViewportPreparationRequest.Identity {
    .init(
        scene: ViewportSceneSnapshotKey(
            source: .document(id: DocumentID(), generation: DocumentGeneration(1)),
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
        snapshotID: nil,
        overlayRevision: overlayRevision
    )
}

private func renderErrorCode(from error: any Error) -> MeshSourcePresentationRenderError.Code? {
    (error as? MeshSourcePresentationRenderError)?.code
}

/// Proves the producers the selection rectangle's failure policy dispatches on:
/// a frame that has judged nothing answers `frameNotReady`, and a frame that
/// judged a different camera revision answers a refusal.
@MainActor
@Suite("Viewport selection drag frame readiness")
struct ViewportSelectionDragFrameReadinessTests {
    @Test("An idle plan cache has judged nothing")
    func idlePlanCacheIsNotReady() throws {
        let cache = MeshSourcePresentationPlanCache()
        let identity = frameReadinessIdentity()

        do {
            _ = try cache.surfaceHit(at: .zero, for: identity, revision: 1)
            Issue.record("An idle plan cache must not answer a surface query.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
        do {
            _ = try cache.occurrenceIDs(
                intersecting: CGRect(x: 0, y: 0, width: 4, height: 4),
                for: identity,
                revision: 1
            )
            Issue.record("An idle plan cache must not answer an occurrence rectangle.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
    }

    @Test("A plan cache holding another identity's state has judged nothing for this one")
    func stalePlanCacheIdentityIsNotReady() throws {
        let cache = MeshSourcePresentationPlanCache()
        cache.reject(
            frameReadinessIdentity(overlayRevision: 1),
            error: .init(code: .gpuFailure, message: "recorded for another identity")
        )
        do {
            _ = try cache.surfaceHit(
                at: .zero,
                for: frameReadinessIdentity(overlayRevision: 2),
                revision: 1
            )
            Issue.record("A failure recorded for another identity must not answer this query.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
    }

    @Test("A failure recorded for the queried identity is the answer, not a readiness state")
    func recordedFailureForQueriedIdentityIsRefused() throws {
        let cache = MeshSourcePresentationPlanCache()
        let identity = frameReadinessIdentity()
        let recorded = MeshSourcePresentationRenderError(
            code: .gpuFailure,
            message: "The native frame failed."
        )
        cache.reject(identity, error: recorded)
        do {
            _ = try cache.surfaceHit(at: .zero, for: identity, revision: 1)
            Issue.record("A recorded failure must be reported to the caller.")
        } catch {
            #expect(error as? MeshSourcePresentationRenderError == recorded)
        }
    }

    @Test("An unmounted native surface has judged nothing", .timeLimit(.minutes(1)))
    func unmountedNativeSurfaceIsNotReady() async throws {
        let batch = try RealityViewportSpatialBatch(
            renderOrigin: Point3D(x: 0, y: 0, z: 0),
            retainedSurfaceByteCount: 0
        )
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        defer { viewport.unbind() }

        #expect(viewport.appliedViewportRevision == nil)
        #expect(viewport.isCameraReady(revision: 1) == false)

        do {
            _ = try viewport.surfaceHit(at: CGPoint(x: 8, y: 8), revision: 1)
            Issue.record("An unmounted surface must not answer a surface query.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
        do {
            _ = try viewport.occurrenceIDs(
                intersecting: CGRect(x: 0, y: 0, width: 16, height: 16),
                revision: 1
            )
            Issue.record("An unmounted surface must not answer an occurrence rectangle.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
        do {
            _ = try viewport.cameraDepthInterval(revision: 1)
            Issue.record("An unmounted surface must not answer a camera depth interval.")
        } catch {
            #expect(renderErrorCode(from: error) == .frameNotReady)
        }
    }

    @Test("A mounted frame refuses a camera revision it did not apply", .timeLimit(.minutes(1)))
    func mountedFrameRefusesStaleRevision() async throws {
        _ = NSApplication.shared

        let renderOrigin = Point3D(x: 0, y: 0, z: 0)
        let batch = try RealityViewportSpatialBatch(
            renderOrigin: renderOrigin,
            retainedSurfaceByteCount: 0
        )
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let size = CGSize(width: 320, height: 240)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: renderOrigin.x, y: renderOrigin.z, width: 1, height: 1),
            size: size,
            camera: .init(zoom: 0.6, projection: .parallel),
            basis: .axisFront(.z),
            verticalBounds: renderOrigin.y...(renderOrigin.y + 1)
        )
        let interaction = MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
            previewSceneNodeIDs: [], hoveredSceneNodeID: nil
        )
        var reportedError: MeshSourcePresentationRenderError?
        let controller = NSHostingController(
            rootView: RealityViewportView(
                viewport: viewport, viewportRevision: 1, displayMode: .solid,
                shading: .init(style: .flat), materialColors: [:], layout: layout,
                interaction: interaction, sectionPlane: nil,
                retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }
            ).frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            window.contentViewController = nil
            window.close()
            viewport.unbind()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var mounted = false
        while ContinuousClock.now < deadline {
            controller.view.layoutSubtreeIfNeeded()
            if let reportedError { throw reportedError }
            if viewport.isCameraReady(revision: 1) {
                mounted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(mounted)

        // The mounted frame answers the revision it applied.
        _ = try viewport.cameraDepthInterval(revision: 1)

        // A revision it never applied is a refusal, not a readiness state.
        do {
            _ = try viewport.cameraDepthInterval(revision: 2)
            Issue.record("A mounted frame must refuse an unapplied camera revision.")
        } catch {
            #expect(renderErrorCode(from: error) == .failed)
        }
        do {
            _ = try viewport.surfaceHit(at: CGPoint(x: 8, y: 8), revision: 2)
            Issue.record("A mounted frame must refuse an unapplied camera revision.")
        } catch {
            #expect(renderErrorCode(from: error) == .failed)
        }
        do {
            _ = try viewport.occurrenceIDs(
                intersecting: CGRect(x: 0, y: 0, width: 16, height: 16),
                revision: 2
            )
            Issue.record("A mounted frame must refuse an unapplied camera revision.")
        } catch {
            #expect(renderErrorCode(from: error) == .failed)
        }
    }
}
