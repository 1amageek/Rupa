import AppKit
import Metal
import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

@Suite(.serialized)
@MainActor
struct RealityViewportMountTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func referenceAxesFollowMountedCameraWithoutGrid(perspective: Bool) async throws {
        _ = NSApplication.shared
        let renderOrigin = Point3D(x: 0.003, y: 0.002, z: -0.001)
        let batch = try RealityViewportSpatialBatch(includesAxes: true,
            renderOrigin: renderOrigin, retainedSurfaceByteCount: 0)
        #expect(!batch.includesGrid && batch.meshes.isEmpty && batch.handleCount == 0)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(includesAxes: true, renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: batch.itemCount - 1, maxPositionCount: 100,
                    maxTriangleCount: 100, maxRetainedByteCount: batch.admittedByteCount))
        }
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        var reportedError: MeshSourcePresentationRenderError?
        var size = CGSize(width: 512, height: 384)
        func view(_ basis: ViewportProjectionBasis, zoom: CGFloat, revision: UInt64) -> some View {
            RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                shading: .init(style: .flat), materialColors: [:],
                layout: .init(modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02), size: size,
                    camera: .init(zoom: zoom, pan: revision == 2 ? CGSize(width: 35, height: -20) : .zero,
                        projection: perspective ? .standardPerspective : .parallel),
                    basis: basis, verticalBounds: -0.01...0.01),
                interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(.axisFront(.z), zoom: 0.05, revision: 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        let axes = try ["X", "Y", "Z"].map { name in
            try #require(viewport.root.findEntity(named: "Reference Axis \(name)") as? ModelEntity)
        }
        let meshes = try axes.map { try #require($0.model?.mesh) }
        for (frame, zoom) in [CGFloat(0.05), 1, 30].enumerated() {
            let basis: ViewportProjectionBasis = frame == 0 ? .axisFront(.z) : frame == 1 ? .axisFront(.x) : .isometric
            let revision = UInt64(frame + 1)
            if frame > 0 {
                size = frame == 1 ? CGSize(width: 640, height: 240) : CGSize(width: 512, height: 384)
                window.setContentSize(size)
                controller.rootView = view(basis, zoom: zoom, revision: revision)
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while viewport.appliedViewportRevision != revision || viewport.project(.origin) == nil
                    || axes.filter({ $0.isEnabledInHierarchy }).count < 2 {
                try #require(ContinuousClock.now < deadline, "Native reference axes never became visible.")
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(reportedError == nil)
            #expect(viewport.gridScaleReadout == nil)
            if frame == 0 { #expect(!axes[2].isEnabled) }
            if frame == 1 && !perspective { #expect(!axes[0].isEnabled) }
            let origin = try #require(viewport.project(.origin))
            for (index, axis) in axes.enumerated() {
                #expect(axis.model?.mesh === meshes[index])
                #expect(axis.components[CollisionComponent.self] == nil)
                guard axis.isEnabled else { continue }
                let mesh = try #require(axis.model?.mesh.lowLevelMesh)
                var first = SIMD3<Float>.zero, last = SIMD3<Float>.zero
                mesh.withUnsafeBytes(bufferIndex: 0) { bytes in
                    let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                    first = vertices[0]; last = vertices[1]
                }
                let a = try #require(viewport.project(.init(x: Double(first.x) + renderOrigin.x,
                    y: Double(first.y) + renderOrigin.y, z: Double(first.z) + renderOrigin.z)))
                let b = try #require(viewport.project(.init(x: Double(last.x) + renderOrigin.x,
                    y: Double(last.y) + renderOrigin.y, z: Double(last.z) + renderOrigin.z)))
                let length = hypot(b.x - a.x, b.y - a.y)
                #expect(length > 0.001, "frame \(frame), axis \(index): \(a) -> \(b)")
                let distance = abs((b.x - a.x) * (origin.y - a.y) - (b.y - a.y) * (origin.x - a.x)) / length
                #expect(distance < 0.5, "Native axis moved away from the CAD origin.")
                if frame < 2 && index != (frame == 0 ? 2 : 0) {
                    func atEdge(_ p: CGPoint) -> Bool {
                        min(abs(p.x), abs(p.y), abs(p.x - size.width), abs(p.y - size.height)) < 0.5
                    }
                    #expect(atEdge(a) && atEdge(b), "frame \(frame), axis \(index): \(a) -> \(b), viewport \(size)")
                }
            }
        }
        // Render the actual prepared resources through RealityKit/Metal as
        // well as checking projection; a populated buffer alone is not proof.
        let renderer = try RealityRenderer()
        let renderedRoot = viewport.root.clone(recursive: true)
        renderer.entities.append(renderedRoot)
        let camera = try #require(renderedRoot.children.first {
            $0.components[OrthographicCameraComponent.self] != nil || $0.components[PerspectiveCameraComponent.self] != nil
        })
        renderer.activeCamera = camera
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 512, height: 384, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        for _ in 0..<3 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do { try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output, onComplete: { _ in continuation.resume() }) }
                catch { continuation.resume(throwing: error) }
            }
        }
        var bytes = [UInt8](repeating: 0, count: 512 * 384 * 4)
        texture.getBytes(&bytes, bytesPerRow: 512 * 4, from: MTLRegionMake2D(0, 0, 512, 384), mipmapLevel: 0)
        for channel in 0..<3 {
            let colored = stride(from: 0, to: bytes.count, by: 4).filter {
                Int(bytes[$0 + channel]) > Int(bytes[$0 + (channel + 1) % 3]) + 20
                    && Int(bytes[$0 + channel]) > Int(bytes[$0 + (channel + 2) % 3]) + 20
            }.count
            #expect(colored > 20, "RealityKit produced no visible reference axis for color channel \(channel).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func referenceAxesClipInfiniteLinesWithoutModelExtent() throws {
        let forward = CGAffineTransform(a: 100, b: 0, c: 0, d: -100, tx: 50, ty: 40)
        func segment(_ origin: SIMD3<Double>, _ direction: SIMD3<Double>,
                     perspective: Bool = false, far: Double = 100) throws -> (start: CGPoint, end: CGPoint)? {
            try RealityViewportSpatialResources.projectedAxis(origin: origin, direction: direction,
                forward: forward, sampleDepth: 1, perspective: perspective,
                near: 0.1, far: far, viewportSize: CGSize(width: 100, height: 80))
        }
        for perspective in [false, true] {
            for pan in [0.0, 10_000.0, -10_000.0] {
                let x = try #require(try segment([pan, 0, -2], [1, 0, 0], perspective: perspective))
                #expect(abs(x.start.x) < 0.01 && abs(x.end.x - 100) < 0.01)
                #expect(abs(x.start.y - 40) < 0.01 && abs(x.end.y - 40) < 0.01)
            }
            let y = try #require(try segment([0, 0, -2], [0, 1, 0], perspective: perspective))
            #expect(abs(y.start.y - 80) < 0.01 && abs(y.end.y) < 0.01)
            #expect(try segment([0, 0, -2], [0, 0, 1], perspective: perspective) == nil)
        }
        // An infinite far plane ends at the true vanishing point, never an
        // arbitrary large world coordinate. A finite far plane clips sooner.
        let infinite = try #require(try segment([0, 0, -2], [0.2, 0, -1], perspective: true, far: .infinity))
        #expect(abs(infinite.start.x) < 0.01)
        #expect(abs(infinite.end.x - 70) < 0.01)
        let finite = try #require(try segment([0, 0, -2], [0.2, 0, -1], perspective: true, far: 3))
        #expect(abs(finite.end.x - (50 + 20.0 / 3)) < 0.01)
        #expect(try segment([0, 10, -2], [1, 0, 0]) == nil)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try segment([.nan, 0, -2], [1, 0, 0])
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try segment([0, 0, -2], [1, 0, 0], far: 0)
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try segment([Double.greatestFiniteMagnitude, 0, -2], [1, 0, 0])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func coldMountPublishesNativeGridWithoutManualCameraUpdates(
        perspective: Bool,
        isometric: Bool
    ) async throws {
        _ = NSApplication.shared
        let batch = try RealityViewportSpatialBatch(
            includesGrid: true,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0
        )
        let viewport = try await RealityViewport.prepare(
            plan: nil,
            spatialBatch: batch,
            reusing: nil
        )
        let size = isometric
            ? CGSize(width: 550, height: 680)
            : CGSize(width: 800, height: 600)
        let basis: ViewportProjectionBasis = isometric ? .isometric : .axisFront(.z)
        let projection: ViewportCameraProjection = perspective
            ? .perspective(fieldOfViewRadians: .pi / 3)
            : .parallel
        let ruler = RulerConfiguration(
            displayUnit: .meter,
            minorTickMeters: 0.1,
            majorTickMeters: 1,
            visibleSpanMeters: 100
        )
        let interaction = MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: [:],
            selectedSceneNodeIDs: [],
            previewSceneNodeIDs: [],
            hoveredSceneNodeID: nil
        )
        var reportedError: MeshSourcePresentationRenderError?
        var reportedGridError: MeshSourcePresentationRenderError?
        var reportedReadout: ViewportProjectedGrid.ScaleReadout?

        func layout(camera: ViewportCamera) -> ViewportLayout {
            ViewportLayout(
                modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
                size: size,
                camera: camera,
                basis: basis,
                verticalBounds: -1...1
            )
        }

        func view(_ value: ViewportLayout, revision: UInt64, renderer: RealityViewport) -> some View {
            RealityViewportView(
                viewport: renderer,
                viewportRevision: revision,
                displayMode: .solid,
                shading: .init(style: .flat),
                materialColors: [:],
                layout: value,
                interaction: interaction,
                sectionPlane: nil,
                retainedSide: .front,
                sectionTolerance: 0,
                gridRuler: ruler,
                onGridUpdateResult: { error, readout in
                    reportedGridError = error
                    reportedReadout = readout
                },
                onUpdateResult: { error in
                    reportedError = error
                }
            )
            .frame(width: size.width, height: size.height)
        }

        var camera = ViewportCamera(zoom: 1, projection: projection)
        let controller = NSHostingController(rootView: view(layout(camera: camera), revision: 1, renderer: viewport))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            viewport.unbind()
            window.contentViewController = nil
            window.close()
        }

        func nativeGridModel() -> ModelEntity? {
            func find(in entity: Entity) -> ModelEntity? {
                if let model = entity as? ModelEntity,
                   model.model != nil {
                    return model
                }
                for child in entity.children {
                    if let model = find(in: child) { return model }
                }
                return nil
            }
            return find(in: viewport.root)
        }

        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var firstReady = false
        while ContinuousClock.now < firstDeadline {
            controller.view.layoutSubtreeIfNeeded()
            if reportedError == nil,
               viewport.appliedViewportRevision == 1,
               viewport.root.isEnabled,
               let readout = reportedReadout,
               reportedGridError == nil,
               readout.minorStep.meters.isFinite,
               readout.minorStep.meters > 0,
               nativeGridModel()?.isEnabled == true {
                firstReady = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        if !firstReady {
            if let reportedError { Issue.record("Cold mount failed: \(reportedError.message)") }
            if let reportedGridError { Issue.record("Native grid failed: \(reportedGridError.message)") }
            Issue.record("Native grid did not become ready during the cold mount deadline.")
        }
        #expect(firstReady)
        let initialGridMesh = try #require(nativeGridModel()?.model?.mesh)

        if isometric {
            let initialLayout = layout(camera: camera)
            let plane = ViewportCanvasPlane.displayed(for: basis)
            let samples = [
                CGPoint(x: size.width / 2, y: size.height / 2),
                CGPoint(x: 16, y: 16),
                CGPoint(x: size.width - 16, y: 16),
                CGPoint(x: 16, y: size.height - 16),
                CGPoint(x: size.width - 16, y: size.height - 16)
            ]
            let bounds = try #require(nativeGridModel()?.visualBounds(
                relativeTo: viewport.root,
                excludeInactive: false
            ))
            let cameraNear: Double
            let cameraFar: Double
            if let component = viewport.camera.components[OrthographicCameraComponent.self] {
                cameraNear = Double(component.near)
                cameraFar = Double(component.far)
            } else if let component = viewport.camera.components[PerspectiveCameraComponent.self] {
                cameraNear = Double(component.near)
                cameraFar = Double(component.far)
            } else {
                throw RealityViewportSpatialBatch.invalid("Mounted native camera has no lens component.")
            }
            for screenPoint in samples {
                let worldPoint = try #require(initialLayout.unproject(screenPoint, onto: plane))
                let expectedScreenPoint = try #require(initialLayout.projectedPoint(worldPoint)).point
                let actualScreenPoint = try #require(viewport.project(worldPoint))
                let localPoint = viewport.camera.convert(
                    position: SIMD3<Float>(
                        Float(worldPoint.x), Float(worldPoint.y), Float(worldPoint.z)
                    ),
                    from: nil
                )
                let depth = Double(-localPoint.z)
                let nativePoint = SIMD3<Float>(
                    Float(worldPoint.x), Float(worldPoint.y), Float(worldPoint.z)
                )
                let epsilon: Float = 1.0e-3
                #expect(nativePoint.x >= bounds.min.x - epsilon)
                #expect(nativePoint.x <= bounds.max.x + epsilon)
                #expect(nativePoint.y >= bounds.min.y - epsilon)
                #expect(nativePoint.y <= bounds.max.y + epsilon)
                #expect(nativePoint.z >= bounds.min.z - epsilon)
                #expect(nativePoint.z <= bounds.max.z + epsilon)
                #expect(depth.isFinite)
                #expect(depth >= cameraNear - 1.0e-4)
                if cameraFar.isFinite {
                    #expect(depth <= cameraFar + 1.0e-4)
                }
                #expect(hypot(
                    actualScreenPoint.x - expectedScreenPoint.x,
                    actualScreenPoint.y - expectedScreenPoint.y
                ) <= 1.0)
            }
        }

        camera = ViewportCamera(
            zoom: 1.6,
            pan: CGSize(width: 120, height: -80),
            projection: projection
        )
        controller.rootView = view(layout(camera: camera), revision: 2, renderer: viewport)
        let expectedUpdatedProjection = try #require(layout(camera: camera).projectedPoint(.origin)).point

        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var secondReady = false
        while ContinuousClock.now < secondDeadline {
            controller.view.layoutSubtreeIfNeeded()
            let projected = viewport.project(.origin)
            let projectedMatchesLayout = projected.map {
                hypot($0.x - expectedUpdatedProjection.x, $0.y - expectedUpdatedProjection.y) <= 1.0
            } ?? false
            if reportedError == nil,
               viewport.appliedViewportRevision == 2,
               viewport.root.isEnabled,
               viewport.gridScaleReadout != nil,
               reportedGridError == nil,
               nativeGridModel()?.isEnabled == true,
               projectedMatchesLayout {
                secondReady = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        if !secondReady {
            if let reportedError { Issue.record("Native camera update failed: \(reportedError.message)") }
            if let reportedGridError { Issue.record("Native grid update failed: \(reportedGridError.message)") }
            Issue.record("Native grid did not follow the camera during the cold-mount update deadline.")
        }
        #expect(secondReady)
        #expect(viewport.gridScaleReadout != nil)
        #expect(nativeGridModel()?.model?.mesh === initialGridMesh)

        // A hover-only candidate keeps the same camera. Observe native engine
        // frames, not just eventual readiness, to detect a blank replacement.
        let replacement = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: viewport)
        let scene = try #require(viewport.root.scene)
        var observedFrames = 0
        var blankFrames = 0
        let subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in
            observedFrames += 1
            let previousVisible = viewport.project(.origin) != nil && viewport.gridScaleReadout != nil
            let replacementVisible = replacement.project(.origin) != nil && replacement.gridScaleReadout != nil
            if !previousVisible && !replacementVisible {
                blankFrames += 1
            }
        }
        defer { subscription.cancel() }
        controller.rootView = view(layout(camera: camera), revision: 2, renderer: replacement)
        let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < replacementDeadline {
            controller.view.layoutSubtreeIfNeeded()
            if replacement.gridScaleReadout != nil, replacement.project(.origin) != nil,
               observedFrames >= 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observedFrames >= 3)
        #expect(blankFrames == 0, "An unchanged-camera overlay replacement blanked a native engine frame.")
        #expect(replacement.gridScaleReadout != nil)
        let replacementProjection = try #require(replacement.project(.origin))
        #expect(hypot(replacementProjection.x - expectedUpdatedProjection.x,
                      replacementProjection.y - expectedUpdatedProjection.y) <= 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func remountPreservesNativeGridAfterSwiftUIIdentityChange(perspective: Bool) async throws {
        _ = NSApplication.shared
        let batch = try RealityViewportSpatialBatch(
            includesGrid: true,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0
        )
        let viewport = try await RealityViewport.prepare(
            plan: nil,
            spatialBatch: batch,
            reusing: nil
        )
        let size = CGSize(width: 800, height: 600)
        let projection: ViewportCameraProjection = perspective
            ? .perspective(fieldOfViewRadians: .pi / 3)
            : .parallel
        let ruler = RulerConfiguration(
            displayUnit: .meter,
            minorTickMeters: 0.1,
            majorTickMeters: 1,
            visibleSpanMeters: 100
        )
        let interaction = MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: [:],
            selectedSceneNodeIDs: [],
            previewSceneNodeIDs: [],
            hoveredSceneNodeID: nil
        )
        var reportedError: MeshSourcePresentationRenderError?
        var reportedGridError: MeshSourcePresentationRenderError?
        var reportedReadout: ViewportProjectedGrid.ScaleReadout?
        var lastSuccessfulGridMount: Int?

        func layout(camera: ViewportCamera) -> ViewportLayout {
            ViewportLayout(
                modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
                size: size,
                camera: camera,
                basis: .axisFront(.z),
                verticalBounds: -1...1
            )
        }

        func view(_ value: ViewportLayout, mountID: Int) -> some View {
            RealityViewportView(
                viewport: viewport,
                viewportRevision: 1,
                displayMode: .solid,
                shading: .init(style: .flat),
                materialColors: [:],
                layout: value,
                interaction: interaction,
                sectionPlane: nil,
                retainedSide: .front,
                sectionTolerance: 0,
                gridRuler: ruler,
                onGridUpdateResult: { error, readout in
                    reportedGridError = error
                    reportedReadout = readout
                    if error == nil, readout != nil {
                        lastSuccessfulGridMount = mountID
                    }
                },
                onUpdateResult: { error in
                    reportedError = error
                }
            )
            .frame(width: size.width, height: size.height)
            .id(mountID)
        }

        let camera = ViewportCamera(zoom: 1, projection: projection)
        let expectedProjection = try #require(layout(camera: camera).projectedPoint(.origin)).point
        let controller = NSHostingController(rootView: view(layout(camera: camera), mountID: 0))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            viewport.unbind()
            window.contentViewController = nil
            window.close()
        }

        func nativeGridModel() -> ModelEntity? {
            func find(in entity: Entity) -> ModelEntity? {
                if let model = entity as? ModelEntity,
                   model.model != nil {
                    return model
                }
                for child in entity.children {
                    if let model = find(in: child) { return model }
                }
                return nil
            }
            return find(in: viewport.root)
        }

        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < firstDeadline {
            controller.view.layoutSubtreeIfNeeded()
            if reportedError == nil,
               reportedGridError == nil,
               lastSuccessfulGridMount == 0,
               viewport.appliedViewportRevision == 1,
               viewport.root.isEnabled,
               viewport.root.scene != nil,
               viewport.project(.origin) != nil,
               reportedReadout != nil,
               nativeGridModel()?.isEnabled == true {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(lastSuccessfulGridMount == 0)
        #expect(viewport.root.scene != nil)
        let initialGridMesh = try #require(nativeGridModel()?.model?.mesh)

        controller.rootView = view(layout(camera: camera), mountID: 1)
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var remounted = false
        while ContinuousClock.now < secondDeadline {
            controller.view.layoutSubtreeIfNeeded()
            let projectionMatchesLayout = viewport.project(.origin).map {
                hypot($0.x - expectedProjection.x, $0.y - expectedProjection.y) <= 1.0
            } ?? false
            if reportedError == nil,
               reportedGridError == nil,
               lastSuccessfulGridMount == 1,
               viewport.appliedViewportRevision == 1,
               viewport.root.isEnabled,
               viewport.root.scene != nil,
               viewport.gridScaleReadout != nil,
               nativeGridModel()?.isEnabled == true,
               projectionMatchesLayout {
                try await Task.sleep(for: .milliseconds(100))
                controller.view.layoutSubtreeIfNeeded()
                let stillMounted = viewport.root.scene != nil && viewport.project(.origin) != nil
                remounted = stillMounted && lastSuccessfulGridMount == 1
                if remounted { break }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        if !remounted {
            if let reportedError { Issue.record("Remounted native camera failed: \(reportedError.message)") }
            if let reportedGridError { Issue.record("Remounted native grid failed: \(reportedGridError.message)") }
            Issue.record("The replacement RealityViewport mount did not retain native projection and grid.")
        }
        #expect(remounted)
        #expect(viewport.root.scene != nil)
        #expect(viewport.project(.origin) != nil)
        #expect(viewport.gridScaleReadout != nil)
        #expect(nativeGridModel()?.model?.mesh === initialGridMesh)
    }
}
