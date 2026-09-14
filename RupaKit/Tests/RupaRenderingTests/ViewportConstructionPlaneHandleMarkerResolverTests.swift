import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// The construction-plane accessibility markers report where the frame drew
/// the handles, so the only thing worth proving is that their screen points
/// are the mounted frame's own projection of the prepared records' points, and
/// that a frame which cannot answer yet produces no marker instead of a
/// failure. A stub frame could not separate those two answers.
@Suite(.serialized)
@MainActor
struct ViewportConstructionPlaneHandleMarkerResolverTests {
    private static let documentID = DocumentID()
    private static let planeID = ConstructionPlaneSourceID()
    private static let sceneNodeID = SceneNodeID()

    // The mounted basis draws world X and world Y, so the plane's normal runs
    // along world Y: the normal handle is then a different screen point than
    // the origin handle, and a resolver that anchored both on the record's
    // origin would place them on top of each other.
    private static let planeOrigin = Point3D(x: 0.002, y: -0.001, z: 0)
    private static let planeNormal = Vector3D(x: 0, y: 1, z: 0)
    private static let planeNormalEnd = Point3D(x: 0.002, y: 0.003, z: 0)

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

    private func record(
        handle: ViewportConstructionPlaneHandleKind
    ) throws -> ViewportSpatialInteractionRecord {
        try ViewportSpatialInteractionRecord(target: .constructionPlane(
            identity: .init(
                constructionPlaneID: Self.planeID,
                sceneNodeID: Self.sceneNodeID,
                handle: handle
            ),
            origin: Self.planeOrigin,
            normal: Self.planeNormal,
            normalEnd: Self.planeNormalEnd,
            corners: [
                Point3D(x: -0.004, y: -0.001, z: -0.004),
                Point3D(x: 0.008, y: -0.001, z: -0.004),
                Point3D(x: 0.008, y: -0.001, z: 0.004),
                Point3D(x: -0.004, y: -0.001, z: 0.004)
            ]
        ))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func constructionPlaneMarkersComeFromTheMountedFrameProjection(
        perspective: Bool
    ) async throws {
        _ = NSApplication.shared
        let cache = MeshSourcePresentationPlanCache()
        let identity = identity(overlayRevision: perspective ? 302 : 301)

        // Nothing is prepared, so no frame answers for the identity at all.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try cache.interactionRecords(for: identity)
        }

        let records = [
            try record(handle: .origin),
            try record(handle: .normal)
        ]
        cache.prepare(RealityViewportPreparationRequest(
            identity: identity,
            scene: nil,
            fallbackOrigin: .origin,
            spatialOverlay: { origin, charge in
                let input = ViewportSpatialOverlayInput(
                    markers: [.init(
                        family: .transform,
                        value: .init(
                            shape: .sphere, anchor: .origin, diameterPoints: 12,
                            color: [1, 0, 0, 1], handleIndex: 0, hitTolerancePoints: 8
                        )
                    )],
                    interactionRecords: records,
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

        // The records are retained before anything is mounted, but no camera
        // has been applied: the markers are absent rather than failed.
        #expect(try cache.interactionRecords(for: identity).count == 2)
        #expect(!cache.hasReadyCamera(for: identity, revision: 1))
        #expect(try ViewportConstructionPlaneHandleMarkerResolver.resolve(
            planCache: cache, identity: identity, revision: 1
        ).isEmpty)

        let size = CGSize(width: 512, height: 384)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
            size: size,
            camera: .init(
                zoom: 0.2, projection: perspective ? .standardPerspective : .parallel
            ),
            basis: .axisFront(.z),
            verticalBounds: -0.01...0.01
        )
        var reportedError: MeshSourcePresentationRenderError?
        var reportedRevision: UInt64?
        var revisionReportCount = 0
        let controller = NSHostingController(
            rootView: RealityViewportView(
                viewport: viewport, viewportRevision: 1, displayMode: .solid,
                shading: .init(style: .flat), materialColors: [:], layout: layout,
                interaction: .init(
                    sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [], hoveredSceneNodeID: nil
                ),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onAppliedFrameRevision: { revision in
                    reportedRevision = revision
                    revisionReportCount += 1
                },
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

        // The mount owns the applied revision: the overlay learns it from the
        // frame rather than from the body that ran before `applyCamera`.
        #expect(revisionReportCount >= 1)
        #expect(cache.hasReadyCamera(for: identity, revision: 1))

        let markers = try ViewportConstructionPlaneHandleMarkerResolver.resolve(
            planCache: cache, identity: identity, revision: 1
        )
        #expect(markers.count == 2)
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: cache, identity: identity, revision: 1
        )
        #expect(probe.usesPerspectiveProjection == perspective)
        let expectedOrigin = try #require(
            try probe.projectedPointWithinDepthRange(Self.planeOrigin)
        )
        let expectedNormalEnd = try #require(
            try probe.projectedPointWithinDepthRange(Self.planeNormalEnd)
        )
        let originMarker = try #require(markers.first { $0.identity.handle == .origin })
        let normalMarker = try #require(markers.first { $0.identity.handle == .normal })

        #expect(originMarker.point == expectedOrigin.point)
        #expect(normalMarker.point == expectedNormalEnd.point)
        #expect(originMarker.point != normalMarker.point)
        #expect(originMarker.identity.constructionPlaneID == Self.planeID)
        #expect(originMarker.identity.sceneNodeID == Self.sceneNodeID)
        #expect(normalMarker.identity.constructionPlaneID == Self.planeID)
        #expect(normalMarker.identity.sceneNodeID == Self.sceneNodeID)

        // The reported world values describe the plane, not the marker, so both
        // handles carry the record's own origin and normal.
        #expect(originMarker.origin == Self.planeOrigin)
        #expect(originMarker.normal == Self.planeNormal)
        #expect(normalMarker.origin == Self.planeOrigin)
        #expect(normalMarker.normal == Self.planeNormal)

        // A revision the frame has not applied is not ready, and readiness is
        // decided before any projection, so it yields no marker and no failure
        // while the same revision fails the projection queries themselves.
        #expect(try ViewportConstructionPlaneHandleMarkerResolver.resolve(
            planCache: cache, identity: identity, revision: 2
        ).isEmpty)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try cache.projectedPointWithinDepthRange(
                Self.planeOrigin, for: identity, revision: 2
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
        #expect(try ViewportConstructionPlaneHandleMarkerResolver.resolve(
            planCache: cache, identity: identity, revision: 1
        ).isEmpty)

        // A withdrawn frame answers no record at all, which is the throw the
        // resolver would surface if the readiness gate had let it through.
        cache.teardown()
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try cache.interactionRecords(for: identity)
        }
    }
}
