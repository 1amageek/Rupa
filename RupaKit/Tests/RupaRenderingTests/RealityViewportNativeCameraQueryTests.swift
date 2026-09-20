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

private func nativeCameraQueryIdentity(
    overlayRevision: UInt64
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

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeCameraQueriesUseMountedEmptySceneCalibration() async throws {
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
                shading: .init(style: .flat), occurrenceMaterials: [:], layout: layout,
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
        controller.view.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer {
            window.contentViewController = nil
            window.close()
            viewport.unbind()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var screenPoint: CGPoint?
        var planePoint: Point3D?
        while ContinuousClock.now < deadline {
            controller.view.layoutSubtreeIfNeeded()
            if let reportedError { throw reportedError }
            if viewport.appliedViewportRevision == 1,
               let projected = viewport.project(anchor) {
                do {
                    planePoint = try viewport.worldPlaneIntersection(
                        at: projected,
                        planeOrigin: Point3D(x: renderOrigin.x, y: renderOrigin.y, z: renderOrigin.z),
                        planeNormal: Vector3D(x: 0, y: 0, z: 1),
                        revision: 1
                    )
                    screenPoint = projected
                    break
                } catch {
                    // The RealityView camera is not exact-ready until its first
                    // native update; continue observing the mounted frame.
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let projected = try #require(screenPoint)
        let resolved = try #require(planePoint)
        #expect(resolved.isApproximatelyEqual(to: anchor, tolerance: 1e-4))

        #expect(try viewport.projectWithinDepthRange(anchor, revision: 1) == projected)
        let near = try #require(viewport.camera.components[OrthographicCameraComponent.self]?.near
            ?? viewport.camera.components[PerspectiveCameraComponent.self]?.near)
        let far = try #require(viewport.camera.components[OrthographicCameraComponent.self]?.far
            ?? viewport.camera.components[PerspectiveCameraComponent.self]?.far)
        var rejectedDepths: [Float] = [-1, 0, near / 2]
        if far.isFinite { rejectedDepths.append(far * 2) }
        for depth in rejectedDepths {
            let scenePoint = viewport.camera.convert(position: [0, 0, -depth], to: nil)
            let worldPoint = Point3D(x: Double(scenePoint.x) + renderOrigin.x,
                                     y: Double(scenePoint.y) + renderOrigin.y,
                                     z: Double(scenePoint.z) + renderOrigin.z)
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try viewport.projectWithinDepthRange(worldPoint, revision: 1)
            }
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.projectWithinDepthRange(Point3D(x: .nan, y: 0, z: 0), revision: 1)
        }

        let xDirection = Vector3D(x: 1, y: 0, z: 0)
        let xAxisOrigin = Point3D(x: renderOrigin.x, y: anchor.y, z: anchor.z)
        let axisParameter = try viewport.worldAxisParameter(
            at: projected, axisOrigin: xAxisOrigin,
            axisDirection: xDirection, revision: 1
        )
        #expect(abs(axisParameter - 0.5) < 1e-3)
        let moved = Point3D(x: anchor.x + 0.001, y: anchor.y, z: anchor.z)
        let movedScreen = try #require(viewport.project(moved))
        let delta = try viewport.worldAxisDelta(
            from: projected, to: movedScreen,
            axisOrigin: xAxisOrigin, axisDirection: xDirection, revision: 1
        )
        #expect(delta > 0)
        #expect(delta.isFinite)

        if perspective {
            // A front-facing perspective ray can still resolve a depth-axis
            // movement when the retained axis is offset from the eye. The
            // 1mm result must come from the native ray/axis solve, not a screen
            // chord measured with the current layout scale.
            let depthAxisOrigin = Point3D(x: anchor.x + 0.25, y: anchor.y, z: anchor.z)
            let depthStart = depthAxisOrigin
            let depthEnd = Point3D(x: depthAxisOrigin.x, y: depthAxisOrigin.y,
                                   z: depthAxisOrigin.z + 0.001)
            let depthStartScreen = try #require(viewport.project(depthStart))
            let depthEndScreen = try #require(viewport.project(depthEnd))
            let depthDelta = try viewport.worldAxisDelta(
                from: depthStartScreen, to: depthEndScreen,
                axisOrigin: depthAxisOrigin,
                axisDirection: Vector3D(x: 0, y: 0, z: 1), revision: 1
            )
            #expect(abs(depthDelta - 0.001) < 0.0001)

            let eye = viewport.camera.convert(position: .zero, to: nil)
            let eyeWorld = Point3D(x: Double(eye.x) + renderOrigin.x,
                                   y: Double(eye.y) + renderOrigin.y,
                                   z: Double(eye.z) + renderOrigin.z)
            let crossingOrigin = Point3D(x: eyeWorld.x + 0.25,
                                         y: eyeWorld.y, z: eyeWorld.z)
            let beforeEye = Point3D(x: crossingOrigin.x, y: crossingOrigin.y,
                                    z: crossingOrigin.z - 0.5)
            let afterEye = Point3D(x: crossingOrigin.x, y: crossingOrigin.y,
                                   z: crossingOrigin.z + 0.5)
            let beforeScreen = try #require(viewport.project(beforeEye))
            let smallMove = Point3D(x: beforeEye.x, y: beforeEye.y, z: beforeEye.z + 0.001)
            let smallMoveScreen = try #require(viewport.project(smallMove))
            let forward = try viewport.worldAxisDelta(
                from: beforeScreen, to: smallMoveScreen,
                axisOrigin: crossingOrigin,
                axisDirection: Vector3D(x: 0, y: 0, z: 1), revision: 1
            )
            let backward = try viewport.worldAxisDelta(
                from: smallMoveScreen, to: beforeScreen,
                axisOrigin: crossingOrigin,
                axisDirection: Vector3D(x: 0, y: 0, z: 1), revision: 1
            )
            #expect(abs(forward - 0.001) < 1e-5)
            #expect(abs(backward + 0.001) < 1e-5)
            if let afterScreen = viewport.project(afterEye) {
                let probeDX = afterScreen.x - beforeScreen.x
                let probeDY = afterScreen.y - beforeScreen.y
                let moveDX = smallMoveScreen.x - beforeScreen.x
                let moveDY = smallMoveScreen.y - beforeScreen.y
                #expect(probeDX * moveDX + probeDY * moveDY < 0)
                #expect(throws: MeshSourcePresentationRenderError.self) {
                    try viewport.worldAxisParameter(
                        at: afterScreen, axisOrigin: crossingOrigin,
                        axisDirection: Vector3D(x: 0, y: 0, z: 1), revision: 1
                    )
                }
            }
        }

        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.worldAxisParameter(
                at: projected, axisOrigin: anchor,
                axisDirection: Vector3D(x: 0, y: 0, z: 1), revision: 1
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.worldPlaneIntersection(
                at: projected,
                planeOrigin: renderOrigin,
                planeNormal: Vector3D(x: .nan, y: 0, z: 1),
                revision: 1
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.worldPlaneIntersection(
                at: projected, planeOrigin: renderOrigin,
                planeNormal: Vector3D(x: 0, y: 0, z: 1), revision: 2
            )
        }

        // A resolved camera must project the same world point even when the
        // next geometry frame changes its fit bounds, chrome and clipping extent.
        let stableCamera = ViewportCamera(zoom: 0.6,
            projection: perspective ? .standardPerspective : .parallel,
            focus: layout.focus, referenceScale: layout.scale / 0.6)
        let changedLayout = ViewportLayout(
            modelBounds: CGRect(x: 90, y: 5, width: 30, height: 50), size: size,
            camera: stableCamera, basis: .axisFront(.z), verticalBounds: -50...0,
            fittingInsets: ViewportCanvasChromeLayout(
                viewportSize: size, bottomReservedHeight: 96).fittingInsets)
        controller.rootView = RealityViewportView(
            viewport: viewport, viewportRevision: 2, displayMode: .solid,
            shading: .init(style: .flat), occurrenceMaterials: [:], layout: changedLayout,
            interaction: interaction, sectionPlane: nil,
            retainedSide: .front, sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }
        ).frame(width: size.width, height: size.height)
        let changedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !viewport.isCameraReady(revision: 2), ContinuousClock.now < changedDeadline {
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(viewport.isCameraReady(revision: 2))
        let unchanged = try viewport.projectWithinDepthRange(anchor, revision: 2)
        #expect(hypot(unchanged.x - projected.x, unchanged.y - projected.y) < 0.02)

        window.contentViewController = nil
        window.close()
        let unmountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewport.appliedViewportRevision != nil, ContinuousClock.now < unmountDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.worldPlaneIntersection(
                at: projected, planeOrigin: renderOrigin,
                planeNormal: Vector3D(x: 0, y: 0, z: 1), revision: 1
            )
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func nativeCameraCacheForwardsExactReadyQueriesAndRejectsStaleFrames() async throws {
    _ = NSApplication.shared
    let renderOrigin = Point3D(x: 100, y: -40, z: 12)
    let identity = nativeCameraQueryIdentity(overlayRevision: 1)
    let cache = MeshSourcePresentationPlanCache()
    cache.prepare(.init(
        identity: identity,
        scene: nil,
        fallbackOrigin: renderOrigin,
        spatialOverlay: { origin, charge in
            (try RealityViewportSpatialBatch(
                renderOrigin: origin,
                retainedSurfaceByteCount: charge
            ), [])
        }
    ))
    let readyDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while cache.surface(for: identity) == nil, ContinuousClock.now < readyDeadline {
        if case let .failed(_, error) = cache.state { throw error }
        try await Task.sleep(for: .milliseconds(10))
    }
    let viewport = try #require(cache.surface(for: identity))
    let size = CGSize(width: 512, height: 384)
    let anchor = Point3D(x: renderOrigin.x + 0.5,
                         y: renderOrigin.y + 0.5,
                         z: renderOrigin.z)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: renderOrigin.x, y: renderOrigin.z, width: 1, height: 1),
        size: size,
        camera: .init(zoom: 0.6, projection: .standardPerspective),
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
            shading: .init(style: .flat), occurrenceMaterials: [:], layout: layout,
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
        cache.teardown()
    }

    let mountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    var projected: CGPoint?
    while ContinuousClock.now < mountDeadline {
        controller.view.layoutSubtreeIfNeeded()
        if let reportedError { throw reportedError }
        if viewport.appliedViewportRevision == 1,
           let point = viewport.project(anchor) {
            do {
                _ = try cache.worldPlaneIntersection(
                    at: point,
                    planeOrigin: renderOrigin,
                    planeNormal: Vector3D(x: 0, y: 0, z: 1),
                    for: identity,
                    revision: 1
                )
                projected = point
                break
            } catch {
                // Wait for the first exact-ready native camera update.
            }
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    let screenPoint = try #require(projected)
    let resolved = try cache.worldPlaneIntersection(
        at: screenPoint,
        planeOrigin: renderOrigin,
        planeNormal: Vector3D(x: 0, y: 0, z: 1),
        for: identity,
        revision: 1
    )
    #expect(resolved.isApproximatelyEqual(to: anchor, tolerance: 1e-4))
    #expect(try cache.projectWithinDepthRange(anchor, for: identity, revision: 1) == screenPoint)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.projectWithinDepthRange(anchor, for: identity, revision: 2)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.projectWithinDepthRange(anchor, for: nativeCameraQueryIdentity(overlayRevision: 2), revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.worldPlaneIntersection(
            at: screenPoint,
            planeOrigin: renderOrigin,
            planeNormal: Vector3D(x: 0, y: 0, z: 1),
            for: identity,
            revision: 2
        )
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.worldPlaneIntersection(
            at: screenPoint,
            planeOrigin: renderOrigin,
            planeNormal: Vector3D(x: 0, y: 0, z: 1),
            for: nativeCameraQueryIdentity(overlayRevision: 2),
            revision: 1
        )
    }
    window.contentViewController = nil
    window.close()
    let unmountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while viewport.appliedViewportRevision != nil, ContinuousClock.now < unmountDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.projectWithinDepthRange(anchor, for: identity, revision: 1)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try cache.worldPlaneIntersection(
            at: screenPoint,
            planeOrigin: renderOrigin,
            planeNormal: Vector3D(x: 0, y: 0, z: 1),
            for: identity,
            revision: 1
        )
    }
}
