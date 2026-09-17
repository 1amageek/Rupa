import AppKit
import Foundation
import RealityKit
import simd
import RupaCore
import RupaCoreTypes
import RupaGeometry
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing

private func viewPlaneSeparation(
    of point: Point3D, from anchor: Point3D, forward: SIMD3<Double>
) -> Double {
    let offset = SIMD3<Double>(point.x - anchor.x, point.y - anchor.y, point.z - anchor.z)
    return abs(simd_dot(offset, forward))
}

private func viewPlaneDistance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
    let dx = lhs.x - rhs.x, dy = lhs.y - rhs.y, dz = lhs.z - rhs.z
    return (dx * dx + dy * dy + dz * dz).squareRoot()
}

/// The construction-plane handles drag on the plane through their own world
/// point that faces the mounted camera. This proves the query the owner asks
/// for: the answer stays on that plane, lands back under the screen position
/// that asked for it, and moves with the anchor's depth under perspective.
@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeViewPlaneQueryAnswersTheFacingPlaneThroughItsAnchor() async throws {
    _ = NSApplication.shared

    for perspective in [false, true] {
        let renderOrigin = Point3D(x: 100, y: -40, z: 12)
        let batch = try RealityViewportSpatialBatch(
            renderOrigin: renderOrigin,
            retainedSurfaceByteCount: 0
        )
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let size = CGSize(width: 512, height: 384)
        let anchor = Point3D(x: renderOrigin.x + 0.5,
                             y: renderOrigin.y + 0.5,
                             z: renderOrigin.z)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: renderOrigin.x, y: renderOrigin.z, width: 1, height: 1),
            size: size,
            camera: .init(zoom: 0.6,
                          projection: perspective ? .standardPerspective : .parallel),
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
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer {
            window.contentViewController = nil
            window.close()
            viewport.unbind()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var pressScreen: CGPoint?
        var pressPoint: Point3D?
        while ContinuousClock.now < deadline {
            controller.view.layoutSubtreeIfNeeded()
            if let reportedError { throw reportedError }
            if viewport.appliedViewportRevision == 1,
               let projected = viewport.project(anchor) {
                do {
                    pressPoint = try viewport.viewPlaneIntersection(
                        at: projected, through: anchor, revision: 1
                    )
                    pressScreen = projected
                    break
                } catch {
                    // The RealityView camera is not exact-ready until its first
                    // native update; continue observing the mounted frame.
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let projected = try #require(pressScreen)
        let pressed = try #require(pressPoint)
        // The screen position the anchor projects to answers the anchor itself.
        #expect(pressed.isApproximatelyEqual(to: anchor, tolerance: 1e-4))

        let forwardFloat = viewport.camera.convert(direction: SIMD3<Float>(0, 0, -1), to: nil)
        let rawForward = SIMD3<Double>(Double(forwardFloat.x),
                                       Double(forwardFloat.y),
                                       Double(forwardFloat.z))
        let forward = rawForward / simd_length(rawForward)

        let draggedScreen = CGPoint(x: projected.x + 37, y: projected.y - 24)
        let dragged = try viewport.viewPlaneIntersection(
            at: draggedScreen, through: anchor, revision: 1
        )
        // The answer stays on the anchor's facing plane, and it lands back
        // under the screen position that asked for it.
        #expect(viewPlaneSeparation(of: dragged, from: anchor, forward: forward) < 1e-5)
        let draggedProjection = try #require(viewport.project(dragged))
        #expect(abs(draggedProjection.x - draggedScreen.x) < 1e-2)
        #expect(abs(draggedProjection.y - draggedScreen.y) < 1e-2)

        // A handle further from the eye answers its own plane. Under
        // perspective the same screen travel is a longer world move there;
        // under parallel projection the two planes answer the same move.
        let deeperAnchor = Point3D(x: anchor.x, y: anchor.y, z: anchor.z - 0.4)
        let deeper = try viewport.viewPlaneIntersection(
            at: draggedScreen, through: deeperAnchor, revision: 1
        )
        #expect(viewPlaneSeparation(of: deeper, from: deeperAnchor, forward: forward) < 1e-5)
        let deeperProjection = try #require(viewport.project(deeper))
        #expect(abs(deeperProjection.x - draggedScreen.x) < 1e-2)
        #expect(abs(deeperProjection.y - draggedScreen.y) < 1e-2)
        let nearTravel = viewPlaneDistance(dragged, anchor)
        let deepTravel = viewPlaneDistance(deeper, deeperAnchor)
        let eye = viewport.camera.convert(position: .zero, to: nil)
        let eyeWorld = Point3D(x: Double(eye.x) + renderOrigin.x,
                               y: Double(eye.y) + renderOrigin.y,
                               z: Double(eye.z) + renderOrigin.z)
        if perspective {
            let nearDepth = viewPlaneSeparation(of: anchor, from: eyeWorld, forward: forward)
            let deepDepth = viewPlaneSeparation(of: deeperAnchor, from: eyeWorld, forward: forward)
            #expect(deepDepth > nearDepth)
            #expect(abs(deepTravel - nearTravel * deepDepth / nearDepth) < 1e-4)
        } else {
            #expect(abs(deepTravel - nearTravel) < 1e-5)
        }

        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.viewPlaneIntersection(
                at: CGPoint(x: Double.nan, y: 0), through: anchor, revision: 1
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.viewPlaneIntersection(
                at: projected, through: Point3D(x: .nan, y: 0, z: 0), revision: 1
            )
        }
        // An anchor behind the eye names no plane the pointer can reach.
        let behindEye = Point3D(x: eyeWorld.x, y: eyeWorld.y, z: eyeWorld.z + 0.5)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.viewPlaneIntersection(at: projected, through: behindEye, revision: 1)
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.viewPlaneIntersection(at: projected, through: anchor, revision: 2)
        }

        window.contentViewController = nil
        window.close()
        let unmountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewport.appliedViewportRevision != nil, ContinuousClock.now < unmountDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.viewPlaneIntersection(at: projected, through: anchor, revision: 1)
        }
    }
}
