import AppKit
import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// A hover delta drawn over a mounted frame draws the complete overlay, keeps every native
/// resource the frame prepared, and answers each hit with the complete overlay's records.
@Suite(.serialized)
@MainActor
struct RealityViewportSpatialDeltaMountTests {
    private let featureID = FeatureID()
    private let a = Point3D(x: -0.3, y: 0, z: 0)
    private let b = Point3D(x: 0.3, y: 0, z: 0)
    private let c = Point3D(x: 0, y: 0.3, z: 0)

    private func record(_ u: Int) throws -> ViewportSpatialInteractionRecord {
        let reference = SelectionReference.surface(.controlPoint(.init(
            surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "surface", ordinal: 0),
                                          geometrySignature: .vertex(point: .origin))), uIndex: u, vIndex: 0)))
        return try ViewportSpatialInteractionRecord(target: .surfaceControlPoint(.init(
            featureID: featureID, target: reference, point: .origin, modelTransform: .identity, dragMode: .planar)))
    }

    private func marker(_ anchor: Point3D, handle: UInt32) -> RealityViewportSpatialBatch.Marker {
        .init(shape: .sphere, anchor: anchor, diameterPoints: 12, color: [1, 1, 1, 1],
              handleIndex: handle, hitTolerancePoints: 8)
    }

    private func line(_ y: Double, color: SIMD4<Float>) -> RealityViewportSpatialBatch.Mesh {
        .init(positions: [Point3D(x: -0.4, y: y, z: 0), Point3D(x: 0.4, y: y, z: 0)], indices: [0, 1],
              topology: .lines, color: color)
    }

    private func batch(
        markers: [RealityViewportSpatialBatch.Marker], meshes: [RealityViewportSpatialBatch.Mesh],
        labelHandle: UInt32, records: [ViewportSpatialInteractionRecord],
        limits: MeshSourcePresentationPlanLimits = .standard
    ) throws -> RealityViewportSpatialBatch {
        let label = RealityViewportSpatialBatch.Label(
            text: "A", anchor: a, offset: .zero, heightPoints: 12, color: [1, 1, 1, 1],
            handleIndex: labelHandle, hitRectPoints: CGRect(x: -4, y: -4, width: 8, height: 8))
        return try RealityViewportSpatialBatch(
            meshes: meshes, labels: [label], markers: markers, handleCount: records.count,
            retainedSemanticByteCount: try ViewportSpatialInteractionRecord.retainedByteCount(for: records, limits: limits),
            renderOrigin: .origin, retainedSurfaceByteCount: 0, limits: limits)
    }

    /// Mounted: markers A (handle 0) and B (handle 1), two white lines, a label on A.
    /// Complete: B is gone, C takes handle 0 and A handle 1, and the second line turns red.
    private func scenario(limits: MeshSourcePresentationPlanLimits = .standard) throws -> (
        mounted: RealityViewportSpatialBatch, mountedRecords: [ViewportSpatialInteractionRecord],
        complete: RealityViewportSpatialBatch, completeRecords: [ViewportSpatialInteractionRecord]
    ) {
        let recordA = try record(1), recordB = try record(2), recordC = try record(3)
        let mountedRecords = [recordA, recordB]
        let completeRecords = [recordC, recordA]
        let mounted = try batch(markers: [marker(a, handle: 0), marker(b, handle: 1)],
            meshes: [line(-0.2, color: [1, 1, 1, 1]), line(0.2, color: [1, 1, 1, 1])],
            labelHandle: 0, records: mountedRecords, limits: limits)
        let complete = try batch(markers: [marker(a, handle: 1), marker(c, handle: 0)],
            meshes: [line(-0.2, color: [1, 1, 1, 1]), line(0.2, color: [1, 0, 0, 1])],
            labelHandle: 1, records: completeRecords, limits: limits)
        return (mounted, mountedRecords, complete, completeRecords)
    }

    @Test(.timeLimit(.minutes(1)))
    func aMountedDeltaDrawsTheCompleteOverlayAndAnswersWithItsRecords() async throws {
        _ = NSApplication.shared
        let scenario = try scenario()
        let delta = try #require(try RealityViewportSpatialDelta.make(
            mounted: scenario.mounted, mountedRecords: scenario.mountedRecords,
            complete: scenario.complete, completeRecords: scenario.completeRecords))
        #expect(delta.suppressed.markers == [1] && delta.suppressed.meshes == [1] && delta.suppressed.count == 2)
        #expect(delta.added?.markers.count == 1 && delta.added?.meshes.count == 1)
        #expect(delta.retainedHandles == [0: 1])

        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: scenario.mounted, reusing: nil)
        let size = CGSize(width: 512, height: 384)
        var reportedError: MeshSourcePresentationRenderError?
        let layout = ViewportLayout(modelBounds: CGRect(x: -0.5, y: -0.5, width: 1, height: 1),
            size: size, camera: .init(zoom: 1, projection: .parallel), basis: .axisFront(.z),
            verticalBounds: -0.01...0.01)
        let controller = NSHostingController(rootView: RealityViewportView(
            viewport: viewport, viewportRevision: 1, displayMode: .solid, shading: .init(style: .flat),
            occurrenceMaterials: [:], layout: layout,
            interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [],
                               hoveredSceneNodeID: nil),
            sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        func answersA() -> Bool {
            guard viewport.appliedViewportRevision == 1, let point = viewport.project(a) else { return false }
            do { return try viewport.spatialHandleHits(at: point, revision: 1) == [0] } catch { return false }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !answersA() {
            if let reportedError { throw reportedError }
            try #require(ContinuousClock.now < deadline, "The mounted overlay never answered its handle.")
            try await Task.sleep(for: .milliseconds(20))
        }
        func hits(_ point: Point3D) throws -> [UInt32] {
            try viewport.spatialHandleHits(at: try #require(viewport.project(point)), revision: 1)
        }
        func entities(_ entity: Entity) -> [ObjectIdentifier] {
            [ObjectIdentifier(entity)] + entity.children.flatMap(entities)
        }
        #expect(try hits(b) == [1])
        #expect(try hits(c).isEmpty)
        #expect(viewport.drawnWorldMeshPartCount == 2)
        let prepared = Set(entities(viewport.root))

        let layer = try await viewport.prepareSpatialDelta(delta)
        // Preparation is off-scene: the mounted overlay draws and answers as before.
        #expect(try hits(b) == [1])
        #expect(Set(entities(viewport.root)) == prepared)

        try viewport.applySpatialDelta(layer)
        // Applied and placed at once, with no further camera update.
        #expect(try hits(a) == [1])
        #expect(try hits(b).isEmpty)
        #expect(try hits(c) == [0])
        #expect(viewport.drawnWorldMeshPartCount == 2)
        #expect(Set(entities(viewport.root)).isSuperset(of: prepared))

        // Another frame's layer is refused and changes nothing.
        let other = try await RealityViewport.prepare(plan: nil, spatialBatch: scenario.mounted, reusing: nil)
        let foreign = try await other.prepareSpatialDelta(delta)
        #expect(throws: MeshSourcePresentationRenderError.self) { try viewport.applySpatialDelta(foreign) }
        #expect(try hits(b).isEmpty)
        #expect(try hits(c) == [0])

        // Withdrawing the delta draws the prepared overlay again with its own records.
        try viewport.applySpatialDelta(nil)
        #expect(try hits(a) == [0])
        #expect(try hits(b) == [1])
        #expect(try hits(c).isEmpty)
        #expect(viewport.drawnWorldMeshPartCount == 2)
        #expect(Set(entities(viewport.root)) == prepared)
        #expect(reportedError == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDeltaThatDoesNotFitOverThePreparedOverlayIsExhausted() async throws {
        let probe = try scenario()
        let probeDelta = try #require(try RealityViewportSpatialDelta.make(
            mounted: probe.mounted, mountedRecords: probe.mountedRecords,
            complete: probe.complete, completeRecords: probe.completeRecords))
        let probeBase = try await RealityViewportSpatialResources.prepare(batch: probe.mounted)
        let added = try #require(probeDelta.added)
        // The prepared overlay and the complete one each fit; together with the added items they do not.
        let standard = MeshSourcePresentationPlanLimits.standard
        let limits = MeshSourcePresentationPlanLimits(
            maxItemCount: probeBase.preparedItemCount + added.itemCount - 1,
            maxPositionCount: standard.maxPositionCount, maxTriangleCount: standard.maxTriangleCount,
            maxRetainedByteCount: standard.maxRetainedByteCount)
        let tight = try scenario(limits: limits)
        let delta = try #require(try RealityViewportSpatialDelta.make(
            mounted: tight.mounted, mountedRecords: tight.mountedRecords,
            complete: tight.complete, completeRecords: tight.completeRecords))
        let base = try await RealityViewportSpatialResources.prepare(batch: tight.mounted)
        do {
            _ = try await RealityViewportSpatialResources.prepareDelta(batch: try #require(delta.added), over: base)
            Issue.record("A delta beyond the prepared overlay's admission must be refused.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .resourceExhausted)
        }
    }
}
