import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// The view-ray anchor is the ray origin a creation drag and a pick carry when
/// the gesture names no exact world point, so the only thing worth proving is
/// that the point comes from the frame that drew the pixel: it lies on the
/// displayed canvas plane, the mounted probe projects it back to the pixel that
/// produced it, and two pixels give two anchors. The refusals matter for the
/// same reason -- a substituted ray origin moves the created geometry -- so a
/// plane that names no normal, a revision the frame never applied, and an
/// unmounted viewport must each yield no anchor at all.
@Suite(.serialized)
@MainActor
struct ViewportCanvasViewRayAnchorTests {
    private static let documentID = DocumentID()

    /// The mounted basis draws world X and world Y, so the displayed canvas
    /// plane is the world XY plane and its normal runs along world Z.
    private static let basis = ViewportProjectionBasis.axisFront(.z)
    private static let size = CGSize(width: 512, height: 384)
    private static let firstPoint = CGPoint(x: 180, y: 140)
    private static let secondPoint = CGPoint(x: 330, y: 250)

    private func identity(
        overlayRevision: UInt64
    ) -> RealityViewportPreparationRequest.Identity {
        .init(
            scene: ViewportSceneSnapshotKey(
                source: .document(
                    id: Self.documentID, generation: DocumentGeneration(1)
                ),
                currentEvaluationGeneration: nil,
                evaluationCacheGeneration: nil,
                workspaceRenderState: .init(
                    revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)
                ),
                renderInvalidation: RenderInvalidation(),
                sectionClippingPlan: nil,
                objectDefinitions: []
            ),
            snapshotID: nil,
            overlayRevision: overlayRevision
        )
    }

    private func anchor(
        at point: CGPoint,
        canvasPlane: ViewportCanvasPlane = .displayed(for: ViewportCanvasViewRayAnchorTests.basis),
        cache: MeshSourcePresentationPlanCache,
        identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Point3D {
        try ViewportCanvasViewRayAnchorResolver.resolve(
            at: point,
            canvasPlane: canvasPlane,
            planCache: cache,
            identity: identity,
            revision: revision
        )
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func viewRayAnchorIsTheMountedFramesOwnCanvasPoint(
        perspective: Bool
    ) async throws {
        _ = NSApplication.shared
        let cache = MeshSourcePresentationPlanCache()
        let identity = identity(overlayRevision: perspective ? 402 : 401)

        // Nothing is prepared, so no frame answers for the identity at all.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try anchor(
                at: Self.firstPoint, cache: cache, identity: identity, revision: 1
            )
        }

        cache.prepare(RealityViewportPreparationRequest(
            identity: identity,
            scene: nil,
            fallbackOrigin: .origin,
            spatialOverlay: { origin, charge in
                let input = ViewportSpatialOverlayInput(
                    // The anchor query needs a mounted camera, not a handle
                    // table, so the frame carries one marker that claims no
                    // interaction record.
                    markers: [.init(
                        family: .transform,
                        value: .init(
                            shape: .sphere, anchor: .origin, diameterPoints: 12,
                            color: [1, 0, 0, 1], handleIndex: nil, hitTolerancePoints: nil
                        )
                    )],
                    interactionRecords: [],
                    renderOrigin: origin,
                    retainedSurfaceByteCount: charge,
                    topologyRevision: identity.overlayRevision
                )
                return try ViewportSpatialOverlayProducer.makeBuilder(from: input)(origin, charge)
            }
        ))
        let settleDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while cache.surface(for: identity) == nil {
            if let failure = cache.failure(for: identity) { throw failure }
            try #require(ContinuousClock.now < settleDeadline)
            try await Task.sleep(for: .milliseconds(1))
        }
        let viewport = try #require(cache.surface(for: identity))
        defer { viewport.unbind(); cache.teardown() }

        // A retained surface that has applied no camera is not an authority.
        #expect(!cache.hasReadyCamera(for: identity, revision: 1))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try anchor(
                at: Self.firstPoint, cache: cache, identity: identity, revision: 1
            )
        }

        let layout = ViewportLayout(
            modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
            size: Self.size,
            camera: .init(
                zoom: 0.2, projection: perspective ? .standardPerspective : .parallel
            ),
            basis: Self.basis,
            verticalBounds: -0.01...0.01
        )
        var reportedError: MeshSourcePresentationRenderError?
        var reportedRevision: UInt64?
        let controller = NSHostingController(
            rootView: RealityViewportView(
                viewport: viewport, viewportRevision: 1, displayMode: .solid,
                shading: .init(style: .flat), materialColors: [:], layout: layout,
                interaction: .init(
                    sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [], hoveredSceneNodeID: nil
                ),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onAppliedFrameRevision: { reportedRevision = $0 },
                onUpdateResult: { reportedError = $0 }
            ).frame(width: Self.size.width, height: Self.size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.titled],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { window.contentViewController = nil; window.close() }

        let mountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            controller.view.layoutSubtreeIfNeeded()
            if let reportedError { throw reportedError }
            if viewport.appliedViewportRevision == 1,
               viewport.project(.origin) != nil,
               reportedRevision == 1 {
                break
            }
            try #require(ContinuousClock.now < mountDeadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cache.hasReadyCamera(for: identity, revision: 1))

        let canvasPlane = ViewportCanvasPlane.displayed(for: Self.basis)
        let normal = try #require(canvasPlane.normal)
        let planeOrigin = canvasPlane.worldPoint(first: 0, second: 0)
        let first = try anchor(
            at: Self.firstPoint, cache: cache, identity: identity, revision: 1
        )
        let second = try anchor(
            at: Self.secondPoint, cache: cache, identity: identity, revision: 1
        )

        // The anchor lies on the canvas plane the current projection basis
        // names, stated in metres, so an anchor taken from any other plane
        // shows up as a signed distance rather than as a plausible point.
        #expect(abs((first - planeOrigin).dot(normal)) < 1.0e-9)
        #expect(abs((second - planeOrigin).dot(normal)) < 1.0e-9)

        // The anchor is the frame's own answer for that pixel: the mounted
        // probe projects it back to the pixel that produced it.
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: cache, identity: identity, revision: 1
        )
        #expect(probe.usesPerspectiveProjection == perspective)
        let projectedFirst = try #require(
            try probe.projectedPointWithinDepthRange(first)
        )
        let projectedSecond = try #require(
            try probe.projectedPointWithinDepthRange(second)
        )
        #expect(abs(projectedFirst.point.x - Self.firstPoint.x) < 1.0e-3)
        #expect(abs(projectedFirst.point.y - Self.firstPoint.y) < 1.0e-3)
        #expect(abs(projectedSecond.point.x - Self.secondPoint.x) < 1.0e-3)
        #expect(abs(projectedSecond.point.y - Self.secondPoint.y) < 1.0e-3)

        // Two pixels name two anchors, so a constant substituted origin would
        // not satisfy the round trip above by accident.
        #expect(first != second)

        // A canvas plane whose axes are collinear spans no plane, and the
        // refusal is the resolver's own rather than the frame's.
        var degenerate = canvasPlane
        degenerate.secondAxis = degenerate.firstAxis
        #expect(degenerate.normal == nil)
        #expect(throws: ViewportCanvasViewRayAnchorResolver.Failure.undefinedCanvasPlaneNormal) {
            try anchor(
                at: Self.firstPoint, canvasPlane: degenerate, cache: cache,
                identity: identity, revision: 1
            )
        }

        // A revision the frame never applied drew other pixels, so it answers
        // no anchor instead of one taken from a different ray origin.
        #expect(!cache.hasReadyCamera(for: identity, revision: 2))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try anchor(
                at: Self.firstPoint, cache: cache, identity: identity, revision: 2
            )
        }

        window.contentViewController = nil
        window.close()
        let unmountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewport.appliedViewportRevision != nil,
              ContinuousClock.now < unmountDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!cache.hasReadyCamera(for: identity, revision: 1))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try anchor(
                at: Self.firstPoint, cache: cache, identity: identity, revision: 1
            )
        }
    }
}
