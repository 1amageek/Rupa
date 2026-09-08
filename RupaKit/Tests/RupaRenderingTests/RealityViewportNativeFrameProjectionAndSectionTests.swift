import AppKit
import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// Mounted-frame coverage for the two native queries the CAD topology resolver
/// consumes but a synthetic frame cannot prove: which projection the frame was
/// drawn with, and whether the frame retains a world point across the active
/// section. Both are answered by the real `RealityView` camera, so a stub frame
/// only exercises the resolver's use of them, never their truthfulness.
@Suite(.serialized)
@MainActor
struct RealityViewportNativeFrameProjectionAndSectionTests {
    private struct MountedFrame {
        let viewport: RealityViewport
        let window: NSWindow
    }

    private func mount(perspective: Bool, suffix: String) async throws -> MountedFrame {
        _ = NSApplication.shared
        let plan = try MeshSourcePresentationRenderPlan(scene: planCacheScene(suffix: suffix))
        let batch = try RealityViewportSpatialBatch(
            renderOrigin: .origin,
            retainedSurfaceByteCount: plan.retainedByteCount
        )
        let viewport = try await RealityViewport.prepare(
            plan: plan,
            spatialBatch: batch,
            reusing: nil
        )
        let size = CGSize(width: 512, height: 384)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: 0, y: -0.5, width: 1, height: 1),
            size: size,
            camera: .init(
                zoom: 0.6,
                projection: perspective ? .standardPerspective : .parallel
            ),
            basis: .axisFront(.z),
            verticalBounds: 0...1
        )
        var reportedError: MeshSourcePresentationRenderError?
        let controller = NSHostingController(
            rootView: RealityViewportView(
                viewport: viewport,
                viewportRevision: 1,
                displayMode: .solid,
                shading: .init(style: .flat),
                materialColors: [:],
                layout: layout,
                interaction: .init(
                    sceneNodeIDByOccurrenceID: [:],
                    selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [],
                    hoveredSceneNodeID: nil
                ),
                sectionPlane: nil,
                retainedSide: .front,
                sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }
            ).frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)

        // The RealityView camera is not exact-ready until its first native
        // update, so the frame is observed rather than assumed.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewport.project(Point3D(x: 0.5, y: 0.5, z: 0)) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        if let reportedError { throw reportedError }
        return MountedFrame(viewport: viewport, window: window)
    }

    private func unmount(_ frame: MountedFrame) {
        frame.viewport.unbind()
        frame.window.contentViewController = nil
        frame.window.close()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nativeFrameReportsTheProjectionItWasDrawnWith(perspective: Bool) async throws {
        let frame = try await mount(perspective: perspective, suffix: "native-projection")
        defer { unmount(frame) }
        let viewport = frame.viewport

        #expect(try viewport.usesPerspectiveProjection(revision: 1) == perspective)
        #expect(
            (viewport.camera.components[PerspectiveCameraComponent.self] != nil) == perspective
        )
        #expect(
            (viewport.camera.components[OrthographicCameraComponent.self] != nil) == !perspective
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.usesPerspectiveProjection(revision: 2)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nativeFrameSeparatesSectionRemovalFromAnEmptyPixel(perspective: Bool) async throws {
        let frame = try await mount(perspective: perspective, suffix: "native-section")
        defer { unmount(frame) }
        let viewport = frame.viewport

        // The drawn quad spans x and y in 0...1 at z == 0, so the cut plane's
        // normal lies in the quad's own plane: a normal along z would put the
        // whole quad behind the cut and disable the geometry root, which is a
        // different answer than a partial section. `kept` and `removed` are both
        // drawn points on either side of the cut, and `emptyKept` draws nothing
        // yet is retained: only the section query separates the last two,
        // because both are empty pixels.
        let kept = Point3D(x: 0.75, y: 0.5, z: 0.0)
        let removed = Point3D(x: 0.25, y: 0.5, z: 0.0)
        let emptyKept = Point3D(x: 5.0, y: 5.0, z: 0.0)
        let surfacePoint = try #require(viewport.project(removed))

        #expect(try viewport.retainsSectionedPoint(kept, revision: 1))
        #expect(try viewport.retainsSectionedPoint(removed, revision: 1))
        #expect(try viewport.retainsSectionedPoint(emptyKept, revision: 1))
        #expect(try viewport.surfaceHit(at: surfacePoint, revision: 1) != nil)

        // An unrepresentable point is invalid input whether or not a section is
        // active, so the failure is owned before the scene state is consulted.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.retainsSectionedPoint(
                Point3D(x: .nan, y: 0.5, z: 0.0),
                revision: 1
            )
        }

        let section = SectionAnalysisResult.Plane(
            sourceKind: .sketchPlane,
            sourceID: nil,
            sourceName: nil,
            origin: .init(x: 0.5, y: 0, z: 0),
            normal: .init(x: 1, y: 0, z: 0),
            u: .init(x: 0, y: 1, z: 0),
            v: .init(x: 0, y: 0, z: 1)
        )
        try viewport.applySection(plane: section, side: .front, tolerance: 0)

        #expect(try viewport.retainsSectionedPoint(kept, revision: 1))
        #expect(try viewport.retainsSectionedPoint(removed, revision: 1) == false)
        #expect(try viewport.retainsSectionedPoint(emptyKept, revision: 1))
        #expect(try viewport.surfaceHit(at: surfacePoint, revision: 1) == nil)

        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.retainsSectionedPoint(
                Point3D(x: .nan, y: 0.5, z: 0.0),
                revision: 1
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.retainsSectionedPoint(kept, revision: 2)
        }
    }
}
