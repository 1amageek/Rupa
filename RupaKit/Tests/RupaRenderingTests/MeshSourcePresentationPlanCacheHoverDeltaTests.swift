import AppKit
import Foundation
import RealityKit
import RupaCore
import RupaCoreTypes
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing

/// A request that differs from the published frame in hover alone is drawn over that frame as a
/// delta, and every other change prepares a new frame.
@Suite(.serialized)
@MainActor
struct MeshSourcePresentationPlanCacheHoverDeltaTests {
    private let renderOrigin = Point3D(x: 10, y: -4, z: 2)
    private let featureID = FeatureID()
    private let scene = ViewportSceneSnapshotKey(
        source: .document(id: DocumentID(), generation: DocumentGeneration(1)),
        currentEvaluationGeneration: nil,
        evaluationCacheGeneration: nil,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter)),
        renderInvalidation: RenderInvalidation(),
        sectionClippingPlan: nil,
        objectDefinitions: []
    )

    private func point(_ x: Double, _ y: Double) -> Point3D {
        Point3D(x: renderOrigin.x + x, y: renderOrigin.y + y, z: renderOrigin.z)
    }

    private func record(_ u: Int) throws -> ViewportSpatialInteractionRecord {
        let reference = SelectionReference.surface(.controlPoint(.init(
            surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "surface", ordinal: 0),
                                          geometrySignature: .vertex(point: renderOrigin))), uIndex: u, vIndex: 0)))
        return try ViewportSpatialInteractionRecord(target: .surfaceControlPoint(.init(
            featureID: featureID, target: reference, point: renderOrigin,
            modelTransform: .identity, dragMode: .planar)))
    }

    private func identity(overlay: UInt64, base: UInt64?) -> RealityViewportPreparationRequest.Identity {
        .init(scene: scene, snapshotID: nil, overlayRevision: overlay, baseOverlayRevision: base)
    }

    /// Handle markers at `anchors`, in handle order, each with its record.
    private func request(
        _ identity: RealityViewportPreparationRequest.Identity,
        _ handles: [(anchor: Point3D, record: ViewportSpatialInteractionRecord)],
        includesAxes: Bool = false
    ) -> RealityViewportPreparationRequest {
        .init(identity: identity, scene: nil, fallbackOrigin: renderOrigin,
            spatialOverlay: { origin, charge in
                try ViewportSpatialOverlayProducer.makeBuilder(from: .init(
                    markers: handles.enumerated().map { index, handle in
                        .init(family: .transform, value: .init(shape: .sphere, anchor: handle.anchor,
                            diameterPoints: 12, color: [1, 0, 0, 1], handleIndex: UInt32(index),
                            hitTolerancePoints: 8))
                    },
                    interactionRecords: handles.map(\.record), includesAxes: includesAxes, renderOrigin: origin,
                    retainedSurfaceByteCount: charge, topologyRevision: identity.overlayRevision))(origin, charge)
            })
    }

    private func ready(
        _ identity: RealityViewportPreparationRequest.Identity, in cache: MeshSourcePresentationPlanCache
    ) async throws -> RealityViewport {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while cache.surface(for: identity) == nil {
            if case let .failed(_, error) = cache.state { throw error }
            try #require(ContinuousClock.now < deadline, "The requested frame never became ready.")
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(cache.surface(for: identity))
    }

    @Test(.timeLimit(.minutes(1)))
    func aHoverChangeIsDrawnOverThePublishedFrameAndAnyOtherChangePreparesANewOne() async throws {
        _ = NSApplication.shared
        let cache = MeshSourcePresentationPlanCache()
        let a = point(-0.3, 0), b = point(0.3, 0), c = point(0, 0.3)
        let recordA = try record(1), recordB = try record(2), recordC = try record(3)
        let first = identity(overlay: 1, base: 1)
        cache.prepare(request(first, [(a, recordA), (b, recordB)]))
        let viewport = try await ready(first, in: cache)

        let size = CGSize(width: 512, height: 384)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: renderOrigin.x - 0.5, y: renderOrigin.z - 0.5, width: 1, height: 1),
            size: size, camera: .init(zoom: 1, projection: .parallel), basis: .axisFront(.z),
            verticalBounds: (renderOrigin.y - 0.5)...(renderOrigin.y + 0.5))
        var reportedError: MeshSourcePresentationRenderError?
        func view(_ viewport: RealityViewport) -> some View {
            RealityViewportView(
                viewport: viewport, viewportRevision: 1, displayMode: .solid, shading: .init(style: .flat),
                occurrenceMaterials: [:], layout: layout,
                interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                                   previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }
            ).frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: AnyView(view(viewport)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        defer { window.contentViewController = nil; window.close(); cache.teardown() }

        func identities(at anchor: Point3D, for identity: RealityViewportPreparationRequest.Identity,
                        in viewport: RealityViewport) throws -> [ViewportSpatialHandleIdentity] {
            let screen = try #require(viewport.project(anchor))
            return try cache.interactionRecords(at: screen, for: identity, revision: 1).map(\.identity)
        }
        var lastWaitError: (any Error)?
        func answers(_ identity: RealityViewportPreparationRequest.Identity, in viewport: RealityViewport) -> Bool {
            guard viewport.appliedViewportRevision == 1, viewport.project(a) != nil else { return false }
            do { return try !identities(at: a, for: identity, in: viewport).isEmpty } catch {
                lastWaitError = error
                return false
            }
        }
        let mountDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !answers(first, in: viewport) {
            if let reportedError { throw reportedError }
            try #require(ContinuousClock.now < mountDeadline,
                         "The mounted frame never answered its handle: \(String(describing: lastWaitError))")
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try identities(at: b, for: first, in: viewport) == [recordB.identity])

        // Hover alone: B is withdrawn, C is added, and A is renumbered.
        let hovered = identity(overlay: 2, base: 1)
        cache.prepare(request(hovered, [(c, recordC), (a, recordA)]))
        let hoveredFrame = try await ready(hovered, in: cache)
        #expect(hoveredFrame === viewport)
        #expect(try cache.interactionRecords(for: hovered).map(\.identity) == [recordC.identity, recordA.identity])
        #expect(try identities(at: a, for: hovered, in: viewport) == [recordA.identity])
        #expect(try identities(at: b, for: hovered, in: viewport).isEmpty)
        #expect(try identities(at: c, for: hovered, in: viewport) == [recordC.identity])

        // Hover back: the delta is taken against the prepared overlay again.
        let restored = identity(overlay: 3, base: 1)
        cache.prepare(request(restored, [(a, recordA), (b, recordB)]))
        #expect(try await ready(restored, in: cache) === viewport)
        #expect(try identities(at: b, for: restored, in: viewport) == [recordB.identity])
        #expect(try identities(at: c, for: restored, in: viewport).isEmpty)

        // A change beyond hover prepares a new frame.
        let selected = identity(overlay: 4, base: 2)
        cache.prepare(request(selected, [(c, recordC), (a, recordA)]))
        let selectedFrame = try await ready(selected, in: cache)
        #expect(selectedFrame !== viewport)

        // So does a hover change the prepared frame cannot express: the axes are its own.
        let withAxes = identity(overlay: 5, base: 2)
        cache.prepare(request(withAxes, [(c, recordC), (a, recordA)], includesAxes: true))
        let axesFrame = try await ready(withAxes, in: cache)
        #expect(axesFrame !== selectedFrame)

        // And an identity that claims no base revision.
        let unclaimed = identity(overlay: 6, base: nil)
        cache.prepare(request(unclaimed, [(c, recordC), (a, recordA)], includesAxes: true))
        #expect(try await ready(unclaimed, in: cache) !== axesFrame)
        #expect(reportedError == nil)
    }

    /// Handle markers and one line per handle, in handle order, at `limits`.
    private func batchRequest(
        _ identity: RealityViewportPreparationRequest.Identity,
        _ handles: [(anchor: Point3D, record: ViewportSpatialInteractionRecord)],
        limits: MeshSourcePresentationPlanLimits
    ) -> RealityViewportPreparationRequest {
        .init(identity: identity, scene: nil, fallbackOrigin: renderOrigin,
            spatialOverlay: { origin, charge in
                let records = handles.map(\.record)
                let batch = try RealityViewportSpatialBatch(
                    meshes: handles.map { handle in
                        .init(positions: [handle.anchor, Point3D(x: handle.anchor.x + 0.05, y: handle.anchor.y, z: handle.anchor.z)],
                              indices: [0, 1], topology: .lines, color: [1, 1, 1, 1])
                    },
                    markers: handles.enumerated().map { index, handle in
                        .init(shape: .sphere, anchor: handle.anchor, diameterPoints: 12, color: [1, 0, 0, 1],
                              handleIndex: UInt32(index), hitTolerancePoints: 8)
                    },
                    handleCount: records.count,
                    retainedSemanticByteCount: try ViewportSpatialInteractionRecord.retainedByteCount(for: records, limits: limits),
                    renderOrigin: origin, retainedSurfaceByteCount: charge, limits: limits)
                return (batch, records)
            })
    }

    @Test(.timeLimit(.minutes(1)))
    func aHoverDeltaIsBasedOnAHoverFrameThatWasNeverPublished() async throws {
        _ = NSApplication.shared
        let cache = MeshSourcePresentationPlanCache()
        let a = point(-0.3, 0), b = point(0.3, 0), c = point(0, 0.3)
        let recordA = try record(1), recordB = try record(2), recordC = try record(3)
        let first = identity(overlay: 1, base: 1)
        cache.prepare(request(first, [(a, recordA), (b, recordB)]))
        let viewport = try await ready(first, in: cache)
        let host = CacheFrameHost(renderOrigin: renderOrigin)
        host.show(viewport)
        defer { host.close(); cache.teardown() }
        try await host.wait("The mounted frame never answered its handle.") {
            host.answers(a, [recordA.identity], for: first, in: cache)
        }

        // The first hover finishes after the second was requested, so it is never published; the
        // second is drawn as a delta over the same prepared overlay all the same.
        let firstHover = identity(overlay: 2, base: 1)
        let secondHover = identity(overlay: 3, base: 1)
        cache.prepare(request(firstHover, [(c, recordC), (a, recordA)]))
        cache.prepare(request(secondHover, [(b, recordB), (c, recordC)]))
        #expect(try await ready(secondHover, in: cache) === viewport)
        #expect(cache.surface(for: firstHover) == nil)
        #expect(try cache.interactionRecords(for: secondHover).map(\.identity) == [recordB.identity, recordC.identity])
        #expect(host.answers(a, [], for: secondHover, in: cache))
        #expect(host.answers(b, [recordB.identity], for: secondHover, in: cache))
        #expect(host.answers(c, [recordC.identity], for: secondHover, in: cache))
        #expect(host.reports.error == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHoverWhoseAdditionsDoNotFitPreparesACompleteFrame() async throws {
        _ = NSApplication.shared
        let a = point(-0.3, 0), b = point(0.3, 0), c = point(0, 0.3)
        let recordA = try record(1), recordB = try record(2), recordC = try record(3)
        let mountedHandles = [(anchor: a, record: recordA), (anchor: b, record: recordB)]
        let hoveredHandles = [(anchor: c, record: recordC), (anchor: a, record: recordA)]

        // The admission that fits the prepared overlay and the hovered one, but not both at once.
        func overlay(_ handles: [(anchor: Point3D, record: ViewportSpatialInteractionRecord)],
                     limits: MeshSourcePresentationPlanLimits) throws -> ViewportSpatialOverlayProducer.Output {
            try batchRequest(identity(overlay: 0, base: nil), handles, limits: limits).spatialOverlay(renderOrigin, 0)
        }
        let standard = MeshSourcePresentationPlanLimits.standard
        let probeMounted = try overlay(mountedHandles, limits: standard)
        let probeHovered = try overlay(hoveredHandles, limits: standard)
        let probeDelta = try #require(try RealityViewportSpatialDelta.make(
            mounted: probeMounted.spatialBatch, mountedRecords: probeMounted.interactionRecords,
            complete: probeHovered.spatialBatch, completeRecords: probeHovered.interactionRecords))
        let prepared = try await RealityViewportSpatialResources.prepare(batch: probeMounted.spatialBatch)
        let limits = MeshSourcePresentationPlanLimits(
            maxItemCount: prepared.preparedItemCount + (probeDelta.added?.itemCount ?? 0) - 1,
            maxPositionCount: standard.maxPositionCount, maxTriangleCount: standard.maxTriangleCount,
            maxRetainedByteCount: standard.maxRetainedByteCount)

        let cache = MeshSourcePresentationPlanCache()
        let first = identity(overlay: 1, base: 1)
        cache.prepare(batchRequest(first, mountedHandles, limits: limits))
        let viewport = try await ready(first, in: cache)
        let host = CacheFrameHost(renderOrigin: renderOrigin)
        host.show(viewport)
        defer { host.close(); cache.teardown() }
        try await host.wait("The mounted frame never answered its handle.") {
            host.answers(a, [recordA.identity], for: first, in: cache)
        }

        let hovered = identity(overlay: 2, base: 1)
        cache.prepare(batchRequest(hovered, hoveredHandles, limits: limits))
        let complete = try await ready(hovered, in: cache)
        #expect(complete !== viewport)
        host.show(complete)
        try await host.wait("The complete frame never answered its handles.") {
            host.answers(c, [recordC.identity], for: hovered, in: cache)
        }
        #expect(host.answers(a, [recordA.identity], for: hovered, in: cache))
        #expect(host.answers(b, [], for: hovered, in: cache))
        #expect(host.reports.error == nil)
    }
}

/// The production host mounting whichever cache frame a test shows.
@MainActor
private final class CacheFrameHost {
    final class Reports { var error: MeshSourcePresentationRenderError? }
    let reports = Reports()
    private let size = CGSize(width: 512, height: 384)
    private let layout: ViewportLayout
    private let window: NSWindow
    private let controller: NSHostingController<AnyView>
    private(set) var viewport: RealityViewport?

    init(renderOrigin: Point3D) {
        layout = ViewportLayout(
            modelBounds: CGRect(x: renderOrigin.x - 0.5, y: renderOrigin.z - 0.5, width: 1, height: 1),
            size: size, camera: .init(zoom: 1, projection: .parallel), basis: .axisFront(.z),
            verticalBounds: (renderOrigin.y - 0.5)...(renderOrigin.y + 0.5))
        controller = NSHostingController(rootView: AnyView(EmptyView()))
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
    }

    func show(_ viewport: RealityViewport) {
        self.viewport = viewport
        let reports = reports
        controller.rootView = AnyView(RealityViewportView(
            viewport: viewport, viewportRevision: 1, displayMode: .solid, shading: .init(style: .flat),
            occurrenceMaterials: [:], layout: layout,
            interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                               previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
            sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
            onUpdateResult: { reports.error = $0 }
        ).frame(width: size.width, height: size.height))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func close() {
        window.contentViewController = nil
        window.close()
    }

    func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            if let error = reports.error { throw error }
            try #require(ContinuousClock.now < deadline, "\(message)")
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Whether the frame answering for `identity` resolves `anchor` to exactly `expected`.
    func answers(
        _ anchor: Point3D, _ expected: [ViewportSpatialHandleIdentity],
        for identity: RealityViewportPreparationRequest.Identity, in cache: MeshSourcePresentationPlanCache
    ) -> Bool {
        guard let viewport, viewport.appliedViewportRevision == 1, let screen = viewport.project(anchor) else {
            return false
        }
        do {
            return try cache.interactionRecords(at: screen, for: identity, revision: 1).map(\.identity) == expected
        } catch {
            return false
        }
    }
}
