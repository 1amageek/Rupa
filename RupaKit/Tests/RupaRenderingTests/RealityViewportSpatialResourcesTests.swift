import AppKit
import Metal
import RealityKit
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

@Suite(.serialized)
@MainActor
struct RealityViewportSpatialResourcesTests {
    private var triangle: RealityViewportSpatialBatch.Mesh {
        .init(positions: [.init(x: -0.7, y: -0.5, z: 0), .init(x: 0.2, y: -0.5, z: 0),
                          .init(x: -0.25, y: 0.6, z: 0)],
              indices: [0, 1, 2], topology: .triangles, color: [1, 0, 0, 1])
    }

    @Test
    func nativeHandleFragmentsPreserveFrameLocalIdentity() async throws {
        var first = triangle
        first.handleIndex = 0
        var second = triangle
        second.handleIndex = 1
        var sectioned = second
        sectioned.attachment = .sectionedGeometry
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        let batch = try RealityViewportSpatialBatch(
            meshes: [first, first, triangle, second, sectioned],
            paths: [.init(path: path, origin: .origin, xAxis: [1, 0, 0], yAxis: [0, 1, 0],
                          color: [1, 1, 1, 1], handleIndex: 0)],
            labels: [.init(text: "X", anchor: .origin, offset: .zero, heightPoints: 12,
                           color: [1, 1, 1, 1], handleIndex: 0)],
            markers: [.init(shape: .sphere, anchor: .origin, diameterPoints: 8,
                            color: [1, 1, 1, 1], handleIndex: 1)],
            cameraLines: [.init(points: [.init(anchor: .origin, offset: .zero),
                                         .init(anchor: .origin, offset: .fixed(CGPoint(x: 8, y: 0)))],
                                color: [1, 1, 1, 1], handleIndex: 1)],
            cameraPaths: [.init(path: path, anchor: .origin, offset: .zero,
                                color: [1, 1, 1, 1], handleIndex: 0)],
            handleCount: 2, renderOrigin: .origin, retainedSurfaceByteCount: 0
        )
        let resources = try await RealityViewportSpatialResources.prepare(batch: batch)
        let children = Array(resources.root.children)
        #expect(children.count == 8)
        #expect(children.filter { resources.handleIndex(for: $0) == 0 }.count == 4)
        #expect(children.filter { resources.handleIndex(for: $0) == 1 }.count == 3)
        #expect(children.filter { resources.handleIndex(for: $0) == nil }.count == 1)
        #expect(resources.sectionedRoot.children.count == 1)
        let section = try #require(resources.sectionedRoot.children.first)
        #expect(resources.handleIndex(for: section) == 1)
        let label = try #require(children.first { !$0.children.isEmpty })
        let glyph = try #require(label.children.first)
        #expect(resources.handleIndex(for: glyph) == 0)
        #expect(resources.handleIndex(for: Entity()) == nil)

        var invalid = triangle
        invalid.handleIndex = 1
        do {
            _ = try RealityViewportSpatialBatch(meshes: [invalid], handleCount: 1,
                                                renderOrigin: .origin, retainedSurfaceByteCount: 0)
            Issue.record("An out-of-table handle index was accepted.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .invalidSceneItem)
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(handleCount: -1, renderOrigin: .origin, retainedSurfaceByteCount: 0)
        }
    }

    @Test
    func admissionRejectsInsteadOfTruncating() throws {
        let batch = try RealityViewportSpatialBatch(meshes: [triangle, triangle],
                                                    renderOrigin: .origin, retainedSurfaceByteCount: 0)
        #expect(batch.meshes.count == 2)
        let exactBytes = batch.admittedByteCount
        _ = try RealityViewportSpatialBatch(meshes: [triangle, triangle], renderOrigin: .origin,
                                             retainedSurfaceByteCount: 0,
                                             limits: .init(maxItemCount: 2, maxPositionCount: 6,
                                                           maxTriangleCount: 2, maxRetainedByteCount: exactBytes))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(meshes: [triangle, triangle], renderOrigin: .origin,
                                             retainedSurfaceByteCount: 1,
                                             limits: .init(maxItemCount: 2, maxPositionCount: 6,
                                                           maxTriangleCount: 2, maxRetainedByteCount: exactBytes))
        }
        let line = RealityViewportSpatialBatch.CameraLine(
            points: [.init(anchor: .origin, offset: .zero), .init(anchor: .origin, offset: .fixed(CGPoint(x: 1, y: 0)))],
            color: [1, 1, 1, 1]
        )
        _ = try RealityViewportSpatialBatch(cameraLines: [line], renderOrigin: .origin,
                                             retainedSurfaceByteCount: 0,
                                             limits: .init(maxItemCount: 3, maxPositionCount: 2,
                                                           maxTriangleCount: 1, maxRetainedByteCount: 10_000))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(cameraLines: [line], renderOrigin: .origin,
                                             retainedSurfaceByteCount: 0,
                                             limits: .init(maxItemCount: 2, maxPositionCount: 2,
                                                           maxTriangleCount: 1, maxRetainedByteCount: 10_000))
        }
        let limits = MeshSourcePresentationPlanLimits(maxItemCount: 1, maxPositionCount: 6,
                                                      maxTriangleCount: 2, maxRetainedByteCount: 10_000)
        do {
            _ = try RealityViewportSpatialBatch(meshes: [triangle, triangle], renderOrigin: .origin,
                                                 retainedSurfaceByteCount: 0, limits: limits)
            Issue.record("Over-budget geometry was accepted.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .resourceExhausted)
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(meshes: [triangle], renderOrigin: .origin,
                                             retainedSurfaceByteCount: .max)
        }
        for mesh in [
            RealityViewportSpatialBatch.Mesh(positions: [.origin], indices: [0, 1], topology: .lines, color: [1, 1, 1, 1]),
            .init(positions: [.origin, .init(x: .nan, y: 0, z: 0)], indices: [0, 1], topology: .lines, color: [1, 1, 1, 1]),
            .init(positions: triangle.positions, indices: [0, 1, 2], topology: .triangles, color: [.nan, 0, 0, 1])
        ] {
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try RealityViewportSpatialBatch(meshes: [mesh], renderOrigin: .origin, retainedSurfaceByteCount: 0)
            }
        }
        var moveOnly = Path()
        moveOnly.move(to: CGPoint(x: 1, y: 1))
        for path in [Path(), moveOnly] {
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try RealityViewportSpatialBatch(
                    paths: [.init(path: path, origin: .origin, xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: [1, 1, 1, 1])],
                    renderOrigin: .origin, retainedSurfaceByteCount: 0)
            }
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try RealityViewportSpatialBatch(
                    cameraPaths: [.init(path: path, anchor: .origin, offset: .zero, color: [1, 1, 1, 1])],
                    renderOrigin: .origin, retainedSurfaceByteCount: 0)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func boundsRulersRepositionWithoutRegeneratingResources(perspective: Bool) async throws {
        _ = NSApplication.shared
        let bounds = try GeometryBounds3D(minimum: .init(x: -0.5, y: -0.5, z: -0.5),
                                         maximum: .init(x: 0.5, y: 0.5, z: 0.5))
        let labels = ViewportMeasurementBoundsRulerLabels(x: "World X", y: "World Y", z: "World Z")
        let group = RealityViewportSpatialBatch.BoundsRulers(input: .init(bounds: bounds, labels: labels),
                                                             heightPoints: 9, color: [1, 1, 1, 1])
        let batch = try RealityViewportSpatialBatch(boundsRulers: group, renderOrigin: .origin, retainedSurfaceByteCount: 0)
        #expect(batch.itemCount == 24)
        #expect(batch.positionCount == 18 + 21)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(boundsRulers: group, renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: 23, maxPositionCount: 100, maxTriangleCount: 1, maxRetainedByteCount: 100_000))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(boundsRulers: group, renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: 24, maxPositionCount: 100, maxTriangleCount: 1,
                              maxRetainedByteCount: batch.admittedByteCount - 1))
        }
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let camera = Entity()
        camera.position.z = 5
        if perspective {
            var lens = PerspectiveCameraComponent()
            lens.fieldOfViewInDegrees = 60
            camera.components.set(lens)
        } else {
            var lens = OrthographicCameraComponent()
            lens.scale = 4
            lens.near = 0.01; lens.far = 100
            camera.components.set(lens)
        }
        let capture = CameraCapture()
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(camera)
            content.add(prepared.root)
            capture.content = content
        }.frame(width: 800, height: 600))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            capture.content?.remove(prepared.root)
            capture.content?.remove(camera)
            capture.content = nil
            window.contentViewController = nil
            window.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while capture.content == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let content = try #require(capture.content)
        let original = meshes(in: prepared.root)
        #expect(original.count == 6)
        let safeRect = CGRect(x: 10, y: 10, width: 780, height: 580)
        var previousPositions: [SIMD3<Float>] = []
        for angle: Float in [0, 0.6] {
            camera.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            camera.position = camera.orientation.act([0, 0, 5])
            let settle = ContinuousClock.now.advanced(by: .seconds(5))
            var expected = ViewportMeasurementBoundsRulerPlacement(rulers: [], disabledAxes: [])
            while ContinuousClock.now < settle {
                try prepared.updateCamera(camera: camera, content: content, safeRect: safeRect)
                expected = ViewportMeasurementBoundsRulerLayout().placement(for: bounds, labels: labels,
                    project: { content.project(point: SIMD3(Float($0.x), Float($0.y), Float($0.z)), to: .local) },
                    safeRect: safeRect, excludedRects: [])
                let positions = prepared.root.children.map(\.position)
                if !expected.rulers.isEmpty, previousPositions.isEmpty || positions != previousPositions { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(!expected.rulers.isEmpty)
            #expect(prepared.disabledRulerAxes == expected.disabledAxes)
            if !previousPositions.isEmpty { #expect(prepared.root.children.map(\.position) != previousPositions) }
            previousPositions = prepared.root.children.map(\.position)
            for ruler in expected.rulers {
                let index = try #require(ViewportMeasurementRulerAxis.allCases.firstIndex(of: ruler.axis))
                let label = prepared.root.children[index * 2]
                let projected = try #require(content.project(point: label.position, to: .local))
                #expect(abs(projected.x - ruler.labelRect.midX) < 0.1)
                #expect(abs(projected.y - ruler.labelRect.midY) < 0.1)
            }
            try prepared.updateCamera(camera: camera, content: content, safeRect: safeRect, excludedRects: [safeRect])
            #expect(prepared.disabledRulerAxes.count == 3)
            #expect(prepared.root.children.allSatisfy { !$0.isEnabled })
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try prepared.updateCamera(camera: camera, content: content, safeRect: safeRect,
                                      excludedRects: Array(repeating: .zero, count: 617))
        }
        #expect(prepared.root.children.allSatisfy { !$0.isEnabled })
        for (resource, previous) in zip(meshes(in: prepared.root), original) { #expect(resource === previous) }
        #expect(prepared.root.children.allSatisfy { $0.components[CollisionComponent.self] == nil })
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func directedOffsetMatchesNativeProjectionAfterOrbit(perspective: Bool) async throws {
        _ = NSApplication.shared
        let anchor = Point3D(x: -0.3, y: -0.2, z: 0.1)
        let toward = Point3D(x: 0.7, y: 0.4, z: 0.9)
        let batch = try RealityViewportSpatialBatch(labels: [
            .init(text: "Direction", anchor: anchor,
                  offset: .directed(toward: toward, parallel: 30, perpendicular: 12), heightPoints: 10, color: [1, 1, 1, 1]),
            .init(text: "Degenerate", anchor: anchor,
                  offset: .directed(toward: anchor, parallel: 30, perpendicular: 12), heightPoints: 10, color: [1, 1, 1, 1]),
            .init(text: "Behind", anchor: anchor,
                  offset: .directed(toward: .init(x: 0, y: 0, z: 20), parallel: 30, perpendicular: 12), heightPoints: 10, color: [1, 1, 1, 1]),
            .init(text: "Natural", anchor: anchor,
                  offset: .projected(toward: toward, minimumLength: 1, parallel: 8, perpendicular: 12),
                  heightPoints: 10, color: [1, 1, 1, 1]),
            .init(text: "Minimum", anchor: anchor,
                  offset: .projected(toward: toward, minimumLength: 512, parallel: 8, perpendicular: 12),
                  heightPoints: 10, color: [1, 1, 1, 1])
        ], renderOrigin: .origin, retainedSurfaceByteCount: 0)
        #expect(batch.itemCount == 10)
        #expect(batch.positionCount == 9 + 10 + 6 + 7 + 7 + 5)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(labels: [
                .init(text: "Invalid", anchor: anchor,
                      offset: .projected(toward: toward, minimumLength: -1, parallel: 0, perpendicular: 0),
                      heightPoints: 10, color: [1, 1, 1, 1]),
            ], renderOrigin: .origin, retainedSurfaceByteCount: 0)
        }
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let original = meshes(in: prepared.root)
        let camera = Entity()
        if perspective {
            var lens = PerspectiveCameraComponent()
            lens.fieldOfViewInDegrees = 60
            camera.components.set(lens)
        } else {
            var lens = OrthographicCameraComponent()
            lens.scale = 3; lens.near = 0.01; lens.far = 100
            camera.components.set(lens)
        }
        camera.position.z = 5
        let capture = CameraCapture()
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(camera); content.add(prepared.root)
            capture.content = content
        }.frame(width: 400, height: 300))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            capture.content?.remove(prepared.root); capture.content?.remove(camera)
            capture.content = nil
            window.contentViewController = nil; window.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while capture.content == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let content = try #require(capture.content)
        for angle: Float in [0, 0.5] {
            camera.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            camera.position = camera.orientation.act([0, 0, angle == 0 ? 5 : 7])
            let settle = ContinuousClock.now.advanced(by: .seconds(5))
            var matched = false
            while ContinuousClock.now < settle {
                try prepared.updateCamera(camera: camera, content: content)
                if let a = content.project(point: SIMD3(Float(anchor.x), Float(anchor.y), Float(anchor.z)), to: .local),
                   let b = content.project(point: SIMD3(Float(toward.x), Float(toward.y), Float(toward.z)), to: .local),
                   let p = content.project(point: prepared.root.children[0].position, to: .local) {
                    let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
                    matched = abs(p.x - a.x - (dx * 30 - dy * 12) / length) < 0.1
                        && abs(p.y - a.y - (dy * 30 + dx * 12) / length) < 0.1
                    for (index, minimumLength) in [(3, CGFloat(1)), (4, CGFloat(512))] {
                        guard let tip = content.project(point: prepared.root.children[index].position, to: .local) else {
                            matched = false
                            break
                        }
                        let distance = max(length, minimumLength) + 8
                        matched = matched && abs(tip.x - a.x - (dx * distance - dy * 12) / length) < 0.1
                            && abs(tip.y - a.y - (dy * distance + dx * 12) / length) < 0.1
                    }
                    if matched { break }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(matched)
            #expect(prepared.root.children[0].isEnabled)
            #expect(!prepared.root.children[1].isEnabled)
            #expect(!prepared.root.children[2].isEnabled)
        }
        for (mesh, previous) in zip(meshes(in: prepared.root), original) { #expect(mesh === previous) }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedTopologySharesNativeResourcesAcrossPlacements() async throws {
        _ = NSApplication.shared
        let path = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
        let batch = try RealityViewportSpatialBatch(
            paths: [.init(path: path, origin: .origin, xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: [1, 0, 0, 1]),
                    .init(path: Path(CGRect(x: 0, y: 0, width: 1, height: 1)), origin: .init(x: 1, y: 2, z: 3),
                          xAxis: [0, 1, 0], yAxis: [0, 0, 1], color: [0, 1, 0, 1]),
                    .init(path: path, origin: .origin, xAxis: [2, 0, 0], yAxis: [0, 1, 0], color: [1, 0, 0, 1])],
            labels: [.init(text: "25 mm", anchor: .origin, offset: .zero, heightPoints: 12, color: [1, 1, 1, 1]),
                     .init(text: "25 mm", anchor: .init(x: 1, y: 2, z: 3), offset: .fixed(CGPoint(x: 10, y: 15)),
                           heightPoints: 14, color: [0, 1, 1, 1], alignment: .trailing),
                     .init(text: "26 mm", anchor: .origin, offset: .zero, heightPoints: 12, color: [1, 1, 1, 1])],
            cameraPaths: [.init(path: path, anchor: .origin, offset: .zero, color: [1, 0, 0, 1]),
                          .init(path: path, anchor: .init(x: 1, y: 0, z: 0), offset: .fixed(CGPoint(x: 15, y: 0)), color: [0, 1, 0, 1])],
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let resources = meshes(in: prepared.root)
        try #require(resources.count == 8)
        #expect(resources[0] === resources[1])
        #expect(resources[0] !== resources[2])
        #expect(resources[3] === resources[4])
        #expect(resources[3] !== resources[5])
        #expect(resources[6] === resources[7])
        #expect(prepared.root.children[0].position != prepared.root.children[1].position)
        #expect(prepared.root.children[0].orientation != prepared.root.children[1].orientation)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPreparationCannotReturnARoot() async throws {
        let batch = try RealityViewportSpatialBatch(meshes: [triangle], renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let task = Task { @MainActor in try await RealityViewportSpatialResources.prepare(batch: batch) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled preparation returned a root.")
        } catch is CancellationError { }
    }

    @Test(.timeLimit(.minutes(1)))
    func mountedAnnotationsKeepPixelScaleWithoutReplacingResources() async throws {
        _ = NSApplication.shared
        // One label, one path, and one line with two placements leave 635 markers at
        // the existing 640-item ceiling. All markers share one native mesh.
        let markers: [RealityViewportSpatialBatch.Marker] = (0..<635).map {
            .init(shape: .box, anchor: .init(x: 0, y: 0, z: Double($0) / 635), diameterPoints: 10, color: [1, 0, 0, 1])
        }
        let batch = try RealityViewportSpatialBatch(
            labels: [.init(text: "25 mm", anchor: .origin, offset: .fixed(CGPoint(x: 30, y: -20)),
                           heightPoints: 12, color: [1, 1, 1, 1], alignment: .center)],
            markers: markers,
            cameraLines: [.init(points: [.init(anchor: .origin, offset: .zero),
                                         .init(anchor: .origin, offset: .fixed(CGPoint(x: 30, y: -20)))],
                                color: [0, 1, 0, 1])],
            cameraPaths: [.init(path: Path(roundedRect: CGRect(x: -16, y: -8, width: 32, height: 16), cornerRadius: 3)
                .strokedPath(.init(lineWidth: 2)), anchor: .origin, offset: .fixed(CGPoint(x: -30, y: 20)), color: [0, 0, 1, 1])],
            renderOrigin: .origin, retainedSurfaceByteCount: 0
        )
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let camera = Entity()
        camera.position.z = 3
        let capture = CameraCapture()
        func view(perspective: Bool, scale: Float) -> some View {
            RealityView { content in
                content.camera = .virtual
                content.add(camera)
                content.add(prepared.root)
                capture.content = content
            } update: { content in
                camera.components.remove(OrthographicCameraComponent.self)
                camera.components.remove(PerspectiveCameraComponent.self)
                if perspective {
                    var lens = PerspectiveCameraComponent()
                    lens.fieldOfViewInDegrees = 60
                    camera.components.set(lens)
                    camera.position.z = scale * 3
                } else {
                    var lens = OrthographicCameraComponent()
                    lens.scale = scale
                    lens.near = 0.01; lens.far = 100
                    camera.components.set(lens)
                }
                capture.content = content
            }.frame(width: 400, height: 300)
        }
        let controller = NSHostingController(rootView: view(perspective: false, scale: 1))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            capture.content?.remove(prepared.root)
            capture.content?.remove(camera)
            capture.content = nil
            window.contentViewController = nil
            window.close()
        }
        let original = meshes(in: prepared.root)
        var updateDurations: [Double] = []
        for perspective in [false, true] {
            for scale: Float in [1, 2] {
                controller.rootView = view(perspective: perspective, scale: scale)
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                var matched = false
                while ContinuousClock.now < deadline {
                    controller.view.layoutSubtreeIfNeeded()
                    if let content = capture.content {
                        let start = ContinuousClock.now
                        try prepared.updateCamera(camera: camera, content: content)
                        let elapsed = start.duration(to: .now).components
                        updateDurations.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                        let label = prepared.root.children[0]
                        let marker = prepared.root.children[1]
                        if label.isEnabled, marker.isEnabled,
                           let anchor = content.project(point: .zero, to: .local),
                           let position = content.project(point: label.position, to: .local),
                           let edge = content.project(point: SIMD3(marker.scale.x, 0, 0), to: .local),
                           abs(position.x - anchor.x - 30) < 0.1,
                           abs(position.y - anchor.y + 20) < 0.1,
                           abs(abs(edge.x - anchor.x) - 10) < 0.1 {
                            matched = true
                            break
                        }
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(matched, "Native annotation mapping failed: perspective=\(perspective), scale=\(scale)")
                let content = try #require(capture.content)
                for index in [1, 318, 635] {
                    let marker = prepared.root.children[index]
                    let start = try #require(content.project(point: marker.position, to: .local))
                    let end = try #require(content.project(point: marker.position + SIMD3(marker.scale.x, 0, 0), to: .local))
                    #expect(abs(abs(end.x - start.x) - 10) < 0.1)
                }
                for (mesh, previous) in zip(meshes(in: prepared.root), original) {
                    #expect(mesh === previous)
                }
            }
        }
        #expect(prepared.root.children.count == 638)
        #expect(prepared.root.children.allSatisfy { $0.isEnabled })
        let sharedMarker = prepared.root.children[1].components[ModelComponent.self]?.mesh
        for index in 1...635 {
            #expect(prepared.root.children[index].components[ModelComponent.self]?.mesh === sharedMarker)
        }
        let glyph = try #require(prepared.root.children[0].children.first as? ModelEntity)
        let glyphMesh = try #require(glyph.model?.mesh)
        #expect(abs(glyph.position.x + glyphMesh.bounds.center.x) < 1e-6)
        let content = try #require(capture.content)
        let anchor = try #require(content.project(point: .zero, to: .local))
        let cameraPath = prepared.root.children[637]
        let pathPosition = try #require(content.project(point: cameraPath.position, to: .local))
        #expect(abs(pathPosition.x - anchor.x + 30) < 0.1)
        #expect(abs(pathPosition.y - anchor.y - 20) < 0.1)
        print("Native 640-item annotation camera update milliseconds: \(updateDurations)")
    }

    @MainActor
    private final class CameraCapture {
        var content: RealityViewCameraContent?
    }

    private func meshes(in entity: Entity) -> [MeshResource] {
        let own = entity.components[ModelComponent.self].map { [$0.mesh] } ?? []
        return own + entity.children.flatMap { meshes(in: $0) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nativeGridTextUpdatesAtConstantPixelScale(perspective: Bool) async throws {
        _ = NSApplication.shared
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = Entity()
        let root = Entity()
        let background = ModelEntity(mesh: .generatePlane(width: 20, height: 20),
                                     materials: [UnlitMaterial(color: .red)])
        root.addChild(background)
        let label = Entity()
        var text = TextComponent()
        text.size = CGSize(width: 160, height: 32)
        text.text = AttributedString(NSAttributedString(string: "111 mm", attributes: [
            .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white
        ]))
        label.components.set(text)
        camera.addChild(label)
        root.addChild(camera)
        renderer.entities.append(root)
        renderer.activeCamera = camera
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: 400, height: 300, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var extents: [CGRect] = []
        var images: [[UInt8]] = []
        for frame in 0..<3 {
            camera.position.z = frame == 0 ? 5 : 10
            let unitsPerPixel: Float
            if perspective {
                var lens = PerspectiveCameraComponent()
                lens.fieldOfViewInDegrees = 60
                lens.near = 0.01
                camera.components.set(lens)
                unitsPerPixel = 2 * 0.5 * tan(.pi / 6) / 300
            } else {
                var lens = OrthographicCameraComponent()
                lens.scale = frame == 0 ? 1 : 2
                lens.near = 0.01; lens.far = 100
                camera.components.set(lens)
                unitsPerPixel = 2 * lens.scale / 300
            }
            label.position = [-80 * unitsPerPixel, 16 * unitsPerPixel, -0.5]
            label.scale = .init(repeating: unitsPerPixel)
            if frame == 2 {
                text.size.width = 180
                text.text = AttributedString(NSAttributedString(string: "888888 mm", attributes: [
                    .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white
                ]))
                label.components.set(text)
            }
            var bytes = [UInt8](repeating: 0, count: 400 * 300 * 4)
            // Native text backing is generated by the engine after component mutation.
            for _ in 0..<8 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                                     onComplete: { _ in continuation.resume() })
                    } catch { continuation.resume(throwing: error) }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let nativeWidth = label.visualBounds(relativeTo: label).extents.x
            try #require(nativeWidth.isFinite && nativeWidth > 0)
            #expect(abs(nativeWidth / Float(text.size.width) - 0.0254 / 72) < 1e-8)
            // TextComponent already converts typographic points into native meters.
            label.scale = .init(repeating: unitsPerPixel * Float(text.size.width) / nativeWidth)
            label.position = [0, 0, -0.5]
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                                 onComplete: { _ in continuation.resume() })
                } catch { continuation.resume(throwing: error) }
            }
            texture.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 300), mipmapLevel: 0)
            var minX = 400, minY = 300, maxX = -1, maxY = -1
            for pixel in 0..<(400 * 300) where bytes[pixel * 4] > 150 && bytes[pixel * 4 + 1] > 150 {
                minX = min(minX, pixel % 400); maxX = max(maxX, pixel % 400)
                minY = min(minY, pixel / 400); maxY = max(maxY, pixel / 400)
            }
            try #require(maxX > minX && maxY > minY, "Native TextComponent produced no visible text.")
            extents.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            images.append(bytes)
            #expect(label.parent === camera && camera.parent === root)
            #expect(renderer.entities.first === root)
        }
        #expect(abs(extents[0].width - extents[1].width) <= 2)
        #expect(abs(extents[0].height - extents[1].height) <= 2)
        #expect(extents[2].width > extents[1].width)
        #expect(images[1] != images[2])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nativeGridReusesResourcesAndPreservesCompleteFrameOnFailure(perspective: Bool) async throws {
        _ = NSApplication.shared
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(includesGrid: true, renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: 359, maxPositionCount: 1000, maxTriangleCount: 1, maxRetainedByteCount: 100_000))
        }
        let placement = RealityViewportSpatialBatch.GridPlacement(
            center: .init(x: 0.2, y: -0.3, z: 0), uAxis: [1, 0, 0], vAxis: [0, 1, 0],
            widthMeters: nil, heightMeters: 0.7, color: [0, 1, 1, 1])
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(gridPlacement: placement, renderOrigin: .origin, retainedSurfaceByteCount: 0)
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialBatch(includesGrid: true, gridPlacement: placement, renderOrigin: .origin,
                retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: 360, maxPositionCount: 1000, maxTriangleCount: 1, maxRetainedByteCount: 100_000))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try placement.transform(minorStepMeters: .nan, renderOrigin: .origin)
        }
        let batch = try RealityViewportSpatialBatch(includesGrid: true, gridPlacement: placement,
                                                    renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let grid = try #require(prepared.root.children.first as? ModelEntity)
        let mesh = try #require(grid.model?.mesh)
        let placementEntity = try #require(prepared.root.children.dropFirst().first as? ModelEntity)
        let placementMesh = try #require(placementEntity.model?.mesh)
        let camera = Entity()
        camera.position.z = 5
        if perspective {
            var lens = PerspectiveCameraComponent()
            lens.fieldOfViewInDegrees = 60
            lens.near = 0.01
            camera.components.set(lens)
        } else {
            var lens = OrthographicCameraComponent()
            lens.scale = 4; lens.near = 0.01; lens.far = 100
            camera.components.set(lens)
        }
        let capture = CameraCapture()
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(camera)
            content.add(prepared.root)
            capture.content = content
        }.frame(width: 800, height: 600))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            capture.content?.remove(prepared.root)
            capture.content?.remove(camera)
            capture.content = nil
            window.contentViewController = nil
            window.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while capture.content == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let content = try #require(capture.content)
        let ruler = RulerConfiguration(displayUnit: .meter, minorTickMeters: 0.1, majorTickMeters: 1, visibleSpanMeters: 100)
        var originalLabels: [Entity] = []
        var heights: [CGFloat] = []
        var placementWidths: [Float] = []
        var readouts: [ViewportProjectedGrid.ScaleReadout] = []
        for frame in 0..<2 {
            camera.position.x = Float(frame) * 0.6
            camera.position.z = frame == 0 ? 5 : 10
            if !perspective {
                var lens = try #require(camera.components[OrthographicCameraComponent.self])
                lens.scale = frame == 0 ? 4 : 8
                camera.components.set(lens)
            }
            try await Task.sleep(for: .milliseconds(50))
            let error = try prepared.updateCamera(camera: camera, content: content,
                gridRuler: ruler, gridBasis: .axisFront(.z), gridSize: CGSize(width: 800, height: 600))
            #expect(error == nil)
            let readout = try #require(prepared.scaleReadout)
            #expect(readout.minorStep.meters.isFinite && readout.minorStep.meters > 0)
            #expect(readout.workspaceSpan.meters == ruler.visibleSpanMeters)
            readouts.append(readout)
            #expect(grid.isEnabled)
            #expect(grid.model?.mesh === mesh)
            #expect(placementEntity.isEnabled && placementEntity.model?.mesh === placementMesh)
            #expect(abs(placementEntity.scale.y - 0.7) < 1e-6)
            #expect(simd_distance(placementEntity.position, [0.2, -0.3, 0]) < 1e-6)
            placementWidths.append(placementEntity.scale.x)
            let labels = prepared.root.children.filter { $0.components[TextComponent.self] != nil && $0.isEnabled }
            try #require(!labels.isEmpty)
            if frame == 0 { originalLabels = labels }
            else {
                for (a, b) in zip(originalLabels, labels) { #expect(a === b) }
            }
            try await Task.sleep(for: .milliseconds(150))
            let label = try #require(labels.first)
            let bounds = label.visualBounds(relativeTo: label)
            let a = try #require(content.project(point: label.convert(position: bounds.min, to: nil), to: .local))
            let b = try #require(content.project(point: label.convert(position: bounds.max, to: nil), to: .local))
            heights.append(abs(b.y - a.y))
            #expect(heights.last! > 5)
        }
        #expect(abs(heights[0] - heights[1]) < 1)
        #expect(readouts.count == 2)
        #expect(placementWidths[1] > placementWidths[0])
        let previousReadout = try #require(readouts.last)
        let transforms = prepared.root.children.map(\.transform)
        var invalid = ruler
        invalid.majorTickMeters = 0
        let failure = try prepared.updateCamera(camera: camera, content: content,
            gridRuler: invalid, gridBasis: .axisFront(.z), gridSize: CGSize(width: 800, height: 600))
        #expect(failure != nil)
        #expect(prepared.scaleReadout == previousReadout)
        #expect(prepared.root.children.map(\.transform) == transforms)
        #expect(grid.isEnabled && grid.model?.mesh === mesh)
        #expect(placementEntity.isEnabled && placementEntity.model?.mesh === placementMesh)
        #expect(try prepared.updateCamera(camera: camera, content: content,
            gridRuler: nil, gridBasis: .axisFront(.z), gridSize: CGSize(width: 800, height: 600)) == nil)
        #expect(prepared.scaleReadout == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sectionContainmentExpandsForCameraRelativeGeometry(perspective: Bool) async throws {
        _ = NSApplication.shared
        let batch = try RealityViewportSpatialBatch(
            markers: Array(repeating: .init(shape: .box, anchor: .init(x: 0.2, y: 0, z: 0), diameterPoints: 40,
                                            color: [1, 0, 0, 1], attachment: .sectionedGeometry), count: 640),
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let capture = CameraCapture()
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(viewport.root)
            capture.content = content
        }.frame(width: 400, height: 300))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            viewport.unbind()
            #expect(capture.content?.entities.contains { $0 === viewport.root } == false)
            window.contentViewController = nil
            window.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while capture.content == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let content = try #require(capture.content)
        viewport.bind(content)
        let original = meshes(in: viewport.root)
        let plane = SectionAnalysisResult.Plane(sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
                                                origin: .origin, normal: .init(x: 1, y: 0, z: 0),
                                                u: .init(x: 0, y: 1, z: 0), v: .init(x: 0, y: 0, z: 1))
        var extents: [Float] = []
        var maximumUpdate = Duration.zero
        for zoom in [1.0, 0.02] {
            var camera = ViewportCamera.identity
            camera.zoom = zoom
            camera.projection = perspective ? .perspective(fieldOfViewRadians: .pi / 3) : .parallel
            let layout = ViewportLayout(modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
                                        size: CGSize(width: 400, height: 300), camera: camera,
                                        basis: .axisFront(.z), verticalBounds: 0...0)
            try viewport.applyCamera(layout: layout, revision: zoom == 1 ? 1 : 2)
            try viewport.applySection(plane: plane, side: .front, tolerance: 0)
            let settle = ContinuousClock.now.advanced(by: .seconds(5))
            var matched = false
            while ContinuousClock.now < settle {
                let start = ContinuousClock.now
                try viewport.updateSpatialCamera()
                maximumUpdate = max(maximumUpdate, start.duration(to: .now))
                let clipper = viewport.root.children.first { $0.components[ClippingComponent.self] != nil }
                if let a = viewport.project(.origin), let b = viewport.project(.init(x: 1, y: 0, z: 0)),
                   abs(abs(b.x - a.x) - layout.scale) < 0.1,
                   let clipper, let clipping = clipper.components[ClippingComponent.self] {
                    let worldBounds = clipper.visualBounds(relativeTo: clipper, excludeInactive: false)
                    if worldBounds.extents.x > 0, worldBounds.max.z <= clipping.bounds.max.z,
                       worldBounds.min.x >= clipping.bounds.min.x, worldBounds.max.x <= clipping.bounds.max.x,
                       worldBounds.min.y >= clipping.bounds.min.y, worldBounds.max.y <= clipping.bounds.max.y {
                        #expect(abs(clipping.bounds.min.z) < 1e-6)
                        extents.append(worldBounds.extents.x)
                        matched = true
                        break
                    }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(matched)
            for (mesh, previous) in zip(meshes(in: viewport.root), original) { #expect(mesh === previous) }
        }
        try #require(extents.count == 2)
        #expect(extents[1] > extents[0] * 10)
        print("Native sectioned 640-item update, perspective=\(perspective): \(maximumUpdate)")
        #expect(maximumUpdate <= .nanoseconds(8_333_333))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sceneWithoutSurfaceClipsOnlySectionedGeometry(perspective: Bool) async throws {
        _ = NSApplication.shared
        func quad(y: Double, color: SIMD4<Float>, attachment: RealityViewportSpatialBatch.Attachment) -> RealityViewportSpatialBatch.Mesh {
            .init(positions: [.init(x: -0.7, y: y, z: 0), .init(x: 0.7, y: y, z: 0),
                              .init(x: 0.7, y: y + 0.3, z: 0), .init(x: -0.7, y: y + 0.3, z: 0)],
                  indices: [0, 1, 2, 0, 2, 3], topology: .triangles, color: color, attachment: attachment)
        }
        let batch = try RealityViewportSpatialBatch(
            meshes: [quad(y: 0.2, color: [1, 0, 0, 1], attachment: .sectionedGeometry),
                     quad(y: -0.5, color: [0, 1, 0, 1], attachment: .world)],
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        #expect(viewport.snapshotID == nil)
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        renderer.entities.append(viewport.root)
        renderer.activeCamera = viewport.camera
        var camera = ViewportCamera.identity
        camera.projection = perspective ? .perspective(fieldOfViewRadians: .pi / 3) : .parallel
        let layout = ViewportLayout(modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
                                    size: CGSize(width: 256, height: 256), camera: camera,
                                    basis: .axisFront(.z), verticalBounds: 0...0)
        try viewport.applyCamera(layout: layout, revision: 1)
        let plane = SectionAnalysisResult.Plane(sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
                                                origin: .origin, normal: .init(x: 1, y: 0, z: 0),
                                                u: .init(x: 0, y: 1, z: 0), v: .init(x: 0, y: 0, z: 1))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var counts: [(red: Int, green: Int)] = []
        for cut in [false, true] {
            try viewport.applySection(plane: cut ? plane : nil, side: .front, tolerance: 0)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do { try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output, onComplete: { _ in continuation.resume() }) }
                catch { continuation.resume(throwing: error) }
            }
            var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
            texture.getBytes(&bytes, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            var red = 0, green = 0
            for index in stride(from: 0, to: bytes.count, by: 4) {
                if bytes[index + 2] > 150 && bytes[index + 1] < 50 { red += 1 }
                if bytes[index + 1] > 150 && bytes[index + 2] < 50 { green += 1 }
            }
            counts.append((red, green))
        }
        #expect(counts[0].red > 500)
        #expect(counts[1].red > counts[0].red / 3 && counts[1].red < counts[0].red * 2 / 3)
        #expect(counts[0].green == counts[1].green && counts[0].green > 500)
        #expect(viewport.hitTest(.zero, revision: 1).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeBatchDrawsAllMaterialPartsAndPlanarPaths() async throws {
        _ = NSApplication.shared
        let concaveFill = try ViewportSpatialOverlayProducer.polygonFill([
            .init(x: 0.4, y: 0.2, z: 0), .init(x: 0.7, y: 0.2, z: 0),
            .init(x: 0.7, y: 0.3, z: 0), .init(x: 0.5, y: 0.3, z: 0),
            .init(x: 0.5, y: 0.5, z: 0), .init(x: 0.4, y: 0.5, z: 0),
        ], color: [0, 0, 1, 1])
        let occludedPositions = [Point3D(x: -0.4, y: -0.3, z: -1), .init(x: -0.1, y: -0.3, z: -1),
                                 .init(x: -0.1, y: 0, z: -1), .init(x: -0.4, y: 0, z: -1)]
        let batch = try RealityViewportSpatialBatch(
            meshes: [triangle, .init(positions: [.init(x: -0.8, y: -0.7, z: 0), .init(x: 0.8, y: -0.7, z: 0)],
                                     indices: [0, 1], topology: .lines, color: [0, 1, 0, 1]),
                     .init(positions: occludedPositions, indices: [0, 1, 2, 0, 2, 3],
                           topology: .triangles, color: [1, 0, 1, 1], depth: .annotation),
                     .init(positions: occludedPositions, indices: [0, 1, 2, 0, 2, 3],
                           topology: .triangles, color: [1, 1, 0, 1], depth: .scene)],
            paths: [concaveFill],
            renderOrigin: .origin, retainedSurfaceByteCount: 0
        )
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = Entity()
        var lens = OrthographicCameraComponent()
        lens.near = 0.01; lens.far = 10; lens.scale = 1
        camera.components.set(lens)
        camera.position.z = 3
        renderer.activeCamera = camera
        renderer.entities.append(contentsOf: [camera, prepared.root])
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: 256, height: 256, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var centroids: [Double] = []
        let originalResources = prepared.root.children.compactMap { $0.components[ModelComponent.self]?.mesh }
        for frame in 0..<2 {
            camera.position.x = Float(frame) * 0.15
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                                 onComplete: { _ in continuation.resume() })
                } catch { continuation.resume(throwing: error) }
            }
            var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
            texture.getBytes(&bytes, bytesPerRow: 256 * 4,
                             from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            var red = 0, green = 0, blue = 0, redX = 0, magenta = 0, yellow = 0
            var blueMinX = 256, blueMaxX = 0, blueMinY = 256, blueMaxY = 0
            for pixel in 0..<(256 * 256) {
                let i = pixel * 4
                if bytes[i + 2] > 150 && bytes[i + 1] < 50 && bytes[i] < 50 { red += 1; redX += pixel % 256 }
                if bytes[i + 1] > 150 && bytes[i + 2] < 50 { green += 1 }
                if bytes[i] > 150 && bytes[i + 2] < 50 {
                    blue += 1
                    blueMinX = min(blueMinX, pixel % 256); blueMaxX = max(blueMaxX, pixel % 256)
                    blueMinY = min(blueMinY, pixel / 256); blueMaxY = max(blueMaxY, pixel / 256)
                }
                if bytes[i + 2] > 150 && bytes[i] > 150 && bytes[i + 1] < 50 { magenta += 1 }
                if bytes[i + 2] > 150 && bytes[i + 1] > 150 && bytes[i] < 50 { yellow += 1 }
            }
            try #require(red > 500)
            #expect(green > 100)
            #expect(blue > 100)
            let gapX = blueMinX + (blueMaxX - blueMinX) * 3 / 4
            let gapY = blueMinY + (blueMaxY - blueMinY) / 4
            #expect(bytes[(gapY * 256 + gapX) * 4] < 50,
                    "Native polygon tessellation filled the concave cutout.")
            #expect(magenta > 100, "Annotation material failed to draw over the occluding world surface.")
            #expect(yellow == 0, "Scene-depth material incorrectly drew through the world surface.")
            centroids.append(Double(redX) / Double(red))
            let resources = prepared.root.children.compactMap { $0.components[ModelComponent.self]?.mesh }
            #expect(resources.count == originalResources.count)
            for (a, b) in zip(resources, originalResources) { #expect(a === b) }
        }
        #expect(centroids[1] < centroids[0] - 10)
    }
}
