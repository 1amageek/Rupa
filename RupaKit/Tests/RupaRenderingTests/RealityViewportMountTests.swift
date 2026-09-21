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
        let renderOrigin = Point3D(x: 0.3, y: -0.2, z: 0.1)
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
                shading: .init(style: .flat), occurrenceMaterials: [:],
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
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        let axes = try ["X", "Y", "Z"].map { name in
            try #require(viewport.root.findEntity(named: "Reference Axis \(name)") as? ModelEntity)
        }
        let meshes = try axes.map { try #require($0.model?.mesh) }
        // Frame 53 reproduces inward Float rounding after origin rebasing;
        // retain the neighboring orientations, then finish at the GPU fixture.
        for frame in [0, 1, 52, 53, 54, 2] {
            let zoom = [CGFloat(0.05), 1, 30][frame % 3]
            let basis: ViewportProjectionBasis = frame == 0 ? .axisFront(.z) : frame == 1 ? .axisFront(.x)
                : frame == 2 ? .isometric : .orbit(yaw: CGFloat(frame) * 0.37, elevation: CGFloat(frame) * 0.11)
            let revision = UInt64(frame + 1)
            if frame > 0 {
                reportedError = nil
                size = frame == 1 ? CGSize(width: 640, height: 240) : CGSize(width: 512, height: 384)
                window.setContentSize(size)
                controller.rootView = view(basis, zoom: zoom, revision: revision)
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while viewport.appliedViewportRevision != revision || viewport.project(.origin) == nil {
                if let reportedError {
                    Issue.record("Orbit frame \(frame), perspective \(perspective): \(reportedError.message)")
                    throw reportedError
                }
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
                #expect(distance < 0.5, "Native axis moved away from the CAD origin at frame \(frame).")
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
        let camera = viewport.camera.clone(recursive: true)
        renderer.entities.append(camera)
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

    @Test(.timeLimit(.minutes(1)))
    func lineQueryClipsBeforeToleranceAndRestoresPerspectivePosition() throws {
        let first = SIMD3<Float>(0, 0, 0), last = SIMD3<Float>(2, 0, 2)
        let hit = try #require(RealityViewportSpatialResources.lineHit(at: CGPoint(x: 10, y: 7),
            first: first, last: last, projectedFirst: .zero, projectedLast: CGPoint(x: 20, y: 0),
            tolerance: 8, firstDepth: 1, lastDepth: 3, perspective: true))
        #expect(hit.position == SIMD3<Float>(0.5, 0, 0.5))
        #expect(hit.distance == 7)
        #expect(RealityViewportSpatialResources.lineHit(at: CGPoint(x: 10, y: 9),
            first: first, last: last, projectedFirst: .zero, projectedLast: CGPoint(x: 20, y: 0),
            tolerance: 8, firstDepth: 1, lastDepth: 3, perspective: true) == nil)
        let section = RealityViewportSectionHalfSpace(
            normal: SIMD3<Double>(1, 0, 0), offset: 1.2, tolerance: 0
        )
        let retained = try #require(try RealityViewportSpatialResources.clippedLine(first: first, last: last, section: section))
        #expect(abs(retained.first.x - 1.2) < 0.00001)
        let nearDepth = 1 + 2 * retained.lower
        let projectedFirst = CGPoint(x: CGFloat(retained.first.x / nearDepth * 30), y: 0)
        // The uncut nearest point is clipped away, but the visible endpoint
        // remains within the pointer tolerance and must still be selectable.
        let edgeHit = try #require(RealityViewportSpatialResources.lineHit(at: CGPoint(x: 15, y: 0),
            first: retained.first, last: retained.last, projectedFirst: projectedFirst,
            projectedLast: CGPoint(x: 20, y: 0), tolerance: 8,
            firstDepth: nearDepth, lastDepth: 3, perspective: true))
        #expect(edgeHit.distance < 2)
        #expect(edgeHit.position == retained.first)
        #expect(try RealityViewportSpatialResources.clippedLine(first: first, last: last,
            section: RealityViewportSectionHalfSpace(
                normal: [1, 0, 0], offset: 3, tolerance: 0
            )) == nil)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try RealityViewportSpatialResources.clippedLine(first: first, last: last,
                section: RealityViewportSectionHalfSpace(
                    normal: [Double.nan, 0, 0], offset: 0, tolerance: 0
                ))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func lineCollisionTracksProjectedTolerance(perspective: Bool, cameraRelative: Bool) async throws {
        _ = NSApplication.shared
        let points: [Point3D] = [.init(x: -0.003, y: 0, z: -0.003), .origin, .init(x: 0.003, y: 0, z: 0.003)]
        let offsets: [CGFloat] = [-20, 0, 20]
        let batch = try RealityViewportSpatialBatch(
            meshes: cameraRelative ? [] : [.init(positions: points, indices: [0, 1, 1, 2], topology: .lines,
                color: [1, 1, 1, 1], handleIndex: 0, hitTolerancePoints: 8)],
            cameraLines: cameraRelative ? [.init(points: zip(points, offsets).map {
                .init(anchor: $0, offset: .fixed(CGPoint(x: $1, y: 0)))
            }, color: [1, 1, 1, 1], widthPoints: 2, handleIndex: 0, hitTolerancePoints: 8)] : [],
            handleCount: 1, renderOrigin: .origin, retainedSurfaceByteCount: 0)
        #expect(batch.lineCollisionCount == 2)
        do {
            _ = try RealityViewportSpatialBatch(meshes: batch.meshes, cameraLines: batch.cameraLines,
                handleCount: 1, renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: batch.itemCount - 1, maxPositionCount: batch.limits.maxPositionCount,
                    maxTriangleCount: batch.limits.maxTriangleCount, maxRetainedByteCount: batch.limits.maxRetainedByteCount))
            Issue.record("Line proxies bypassed native entity admission.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .resourceExhausted)
        }
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let size = CGSize(width: 512, height: 384)
        var reportedError: MeshSourcePresentationRenderError?
        func view(zoom: CGFloat, revision: UInt64) -> some View {
            RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                shading: .init(style: .flat), occurrenceMaterials: [:],
                layout: .init(modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02), size: size,
                    camera: .init(zoom: zoom, projection: perspective ? .standardPerspective : .parallel),
                    basis: .axisFront(.z), verticalBounds: -0.01...0.01),
                interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 })
                .frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(zoom: 0.2, revision: 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        func colliders(in entity: Entity) -> [Entity] {
            var result = entity.components[CollisionComponent.self] == nil ? [] : [entity]
            for child in entity.children { result.append(contentsOf: colliders(in: child)) }
            return result
        }
        let collisionEntities = colliders(in: viewport.root)
        #expect(collisionEntities.count == 2)
        let shape = try #require(collisionEntities.first?.components[CollisionComponent.self]?.shapes.first)
        for (iteration, zoom) in [CGFloat(0.2), 1, 20].enumerated() {
            let revision = UInt64(iteration + 1)
            if iteration > 0 { controller.rootView = view(zoom: zoom, revision: revision) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while viewport.appliedViewportRevision != revision || viewport.project(.origin) == nil {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(reportedError == nil)
            if cameraRelative && !perspective {
                let strokes = collisionEntities.compactMap(\.parent).first?.children.flatMap { entity in
                    entity.children.compactMap { $0 as? ModelEntity }
                } ?? []
                #expect(strokes.count == 2)
                for stroke in strokes {
                    let a = stroke.convert(position: [0, -0.5, 0], to: nil)
                    let b = stroke.convert(position: [0, 0.5, 0], to: nil)
                    let p = try #require(viewport.project(.init(x: Double(a.x), y: Double(a.y), z: Double(a.z))))
                    let q = try #require(viewport.project(.init(x: Double(b.x), y: Double(b.y), z: Double(b.z))))
                    #expect(abs(hypot(p.x - q.x, p.y - q.y) - 2) < 0.01)
                }
            }
            for collider in collisionEntities {
                #expect(collider.components[CollisionComponent.self]?.shapes.first == shape)
            }
            let center = try #require(viewport.project(.origin))
            #expect(try viewport.spatialHandleHits(at: center, revision: revision) == [0], "Center at zoom \(zoom)")
            #expect(try viewport.spatialHandleHits(at: CGPoint(x: center.x, y: center.y + 7), revision: revision) == [0], "Interior tolerance at zoom \(zoom)")
            #expect(try viewport.spatialHandleHits(at: CGPoint(x: center.x, y: center.y + 9), revision: revision).isEmpty)
            var endpoint = try #require(viewport.project(points[2]))
            if cameraRelative { endpoint.x += offsets[2] }
            let endpointDepth = -viewport.camera.convert(position: [0.003, 0, 0.003], from: nil).z
            let near = try #require(viewport.camera.components[PerspectiveCameraComponent.self]?.near
                ?? viewport.camera.components[OrthographicCameraComponent.self]?.near)
            let endpointHits = try viewport.spatialHandleHits(at: CGPoint(x: endpoint.x + 7, y: endpoint.y), revision: revision)
            if endpointDepth >= near {
                #expect(endpointHits == [0], "Visible endpoint tolerance at zoom \(zoom)")
            } else {
                // Native project may return a finite screen point behind the
                // eye; it is not a visible endpoint or a valid collision target.
                #expect(endpointHits.isEmpty)
                for collider in collisionEntities { #expect(collider.isEnabledInHierarchy) }
            }
            #expect(try viewport.spatialHandleHits(at: CGPoint(x: endpoint.x + 9, y: endpoint.y), revision: revision).isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func markerCollisionTracksExplicitPixelTolerance(perspective: Bool, sphere: Bool) async throws {
        _ = NSApplication.shared
        let marker = RealityViewportSpatialBatch.Marker(
            shape: sphere ? .sphere : .box, anchor: .origin, diameterPoints: 12,
            color: [1, 1, 1, 1], handleIndex: 0, hitTolerancePoints: 8
        )
        let batch = try RealityViewportSpatialBatch(markers: [marker], handleCount: 1,
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let size = CGSize(width: 512, height: 384)
        let interaction = MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil)
        var reportedError: MeshSourcePresentationRenderError?
        func view(zoom: CGFloat, revision: UInt64) -> some View {
            let layout = ViewportLayout(modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
                size: size, camera: .init(zoom: zoom, projection: perspective ? .standardPerspective : .parallel),
                basis: .axisFront(.z), verticalBounds: -0.01...0.01)
            return RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                shading: .init(style: .flat), occurrenceMaterials: [:], layout: layout, interaction: interaction,
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(zoom: 0.2, revision: 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        func collider(in entity: Entity) -> Entity? {
            if entity.components[CollisionComponent.self] != nil { return entity }
            for child in entity.children { if let result = collider(in: child) { return result } }
            return nil
        }
        let entity = try #require(collider(in: viewport.root))
        let collision = try #require(entity.components[CollisionComponent.self])
        let collisionShape = try #require(collision.shapes.first)
        #expect(collision.filter.group == RealityViewport.spatialCollisionGroup)
        #expect(viewport.spatialHandleIndex(for: entity) == 0)
        for (offset, zoom) in [CGFloat(0.2), 1, 20].enumerated() {
            let revision = UInt64(offset + 1)
            if offset > 0 { controller.rootView = view(zoom: zoom, revision: revision) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while viewport.appliedViewportRevision != revision || !entity.isEnabledInHierarchy {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(reportedError == nil)
            #expect(entity.components[CollisionComponent.self]?.shapes.first == collisionShape)
            let screenCenter = try #require(viewport.project(.origin))
            // The visual radius is 6 pt; the explicit circular input radius is
            // 8 pt for both marker shapes, independent of lens and zoom.
            for (offset, expected) in [(CGPoint(x: 7, y: 0), true),
                                       (CGPoint(x: 9, y: 0), false),
                                       (CGPoint(x: 6, y: 6), false)] {
                let point = CGPoint(x: screenCenter.x + offset.x, y: screenCenter.y + offset.y)
                #expect(try viewport.spatialHandleHits(at: point, revision: revision).contains(0) == expected)
            }
            #expect(try viewport.surfaceHit(at: screenCenter, revision: revision) == nil)
            #expect(try viewport.spatialHandleHits(at: screenCenter, revision: revision) == [0])
            #expect(try viewport.spatialHandleHits(at: CGPoint(x: screenCenter.x + 12, y: screenCenter.y), revision: revision).isEmpty)
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try viewport.spatialHandleHits(at: screenCenter, revision: revision + 1)
            }
            entity.isEnabled = false
            #expect(try viewport.spatialHandleHits(at: screenCenter, revision: revision).isEmpty)
            entity.isEnabled = true
        }
        viewport.invalidateCamera()
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.spatialHandleHits(at: .zero, revision: 3)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [0, 1, 2, 3, 4])
    func spatialHandleQuerySeparatesOcclusionSectionAndAnnotation(perspective: Bool, family: Int) async throws {
        _ = NSApplication.shared
        let plan = try MeshSourcePresentationRenderPlan(scene: planCacheScene(suffix: "spatial-occlusion"))
        let markers: [RealityViewportSpatialBatch.Marker] = [
            .init(shape: .sphere, anchor: .init(x: 0.5, y: 0.5, z: 0.2), diameterPoints: 16,
                  color: [1, 1, 1, 1], depth: .scene, handleIndex: 0, hitTolerancePoints: 8),
            .init(shape: .sphere, anchor: .init(x: 0.5, y: 0.5, z: -0.2), diameterPoints: 16,
                  color: [1, 1, 1, 1], depth: .scene, handleIndex: 1, hitTolerancePoints: 8),
            .init(shape: .sphere, anchor: .init(x: 0.5, y: 0.5, z: -0.2), diameterPoints: 16,
                  color: [1, 1, 1, 1], depth: .annotation, handleIndex: 2, hitTolerancePoints: 8),
            .init(shape: .box, anchor: .init(x: 0.5, y: 0.5, z: 0.3), diameterPoints: 16,
                  color: [1, 1, 1, 1], depth: .annotation, handleIndex: 2, hitTolerancePoints: 8),
            .init(shape: .sphere, anchor: .init(x: 0.5, y: 0.5, z: 0.1), diameterPoints: 16,
                  color: [1, 1, 1, 1], depth: .scene, attachment: .sectionedGeometry, handleIndex: 3, hitTolerancePoints: 8)
        ]
        let labels: [RealityViewportSpatialBatch.Label] = family == 1 ? markers.map {
            .init(text: "Label", anchor: $0.anchor, offset: .zero, heightPoints: 12, color: $0.color,
                  depth: $0.depth, attachment: $0.attachment, handleIndex: $0.handleIndex,
                  hitRectPoints: CGRect(x: -8, y: -8, width: 16, height: 16))
        } : []
        let paths: [RealityViewportSpatialBatch.CameraPath] = family == 2 ? markers.map {
            .init(path: Path(CGRect(x: -2, y: -2, width: 4, height: 4)), anchor: $0.anchor,
                  offset: .zero, color: $0.color, depth: $0.depth, attachment: $0.attachment,
                  handleIndex: $0.handleIndex, hitTolerancePoints: 8)
        } : []
        let fills: [RealityViewportSpatialBatch.Mesh] = family == 3 ? markers.map { marker in
            let p = marker.anchor
            return .init(positions: [.init(x: p.x - 0.05, y: p.y - 0.05, z: p.z),
                .init(x: p.x + 0.05, y: p.y - 0.05, z: p.z),
                .init(x: p.x + 0.05, y: p.y + 0.05, z: p.z),
                .init(x: p.x - 0.05, y: p.y + 0.05, z: p.z)],
                indices: [0, 1, 2, 0, 2, 3], topology: .triangles, color: marker.color,
                depth: marker.depth, attachment: marker.attachment,
                handleIndex: marker.handleIndex, hitTolerancePoints: 0)
        } : []
        let planarFills: [RealityViewportSpatialBatch.PlanarPath] = family == 4 ? markers.map {
            .init(path: Path(CGRect(x: -0.05, y: -0.05, width: 0.1, height: 0.1)), origin: $0.anchor,
                xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: $0.color, depth: $0.depth,
                attachment: $0.attachment, handleIndex: $0.handleIndex, hitTolerancePoints: 0)
        } : []
        let batch = try RealityViewportSpatialBatch(meshes: fills, paths: planarFills,
            labels: labels, markers: family == 0 ? markers : [],
            cameraPaths: paths, handleCount: 4,
            renderOrigin: .origin, retainedSurfaceByteCount: plan.retainedByteCount)
        let viewport = try await RealityViewport.prepare(plan: plan, spatialBatch: batch, reusing: nil)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.spatialHandleHits(at: .zero, revision: 1)
        }
        let size = CGSize(width: 512, height: 384)
        let layout = ViewportLayout(modelBounds: CGRect(x: 0, y: -0.5, width: 1, height: 1), size: size,
            camera: .init(zoom: 0.6, projection: perspective ? .standardPerspective : .parallel),
            basis: .axisFront(.z), verticalBounds: 0...1)
        var reportedError: MeshSourcePresentationRenderError?
        let view = RealityViewportView(viewport: viewport, viewportRevision: 1, displayMode: .solid,
            shading: .init(style: .flat), occurrenceMaterials: [:], layout: layout,
            interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
            sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
            onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewport.project(.init(x: 0.5, y: 0.5, z: 0)) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reportedError == nil)
        if let lens = viewport.camera.components[OrthographicCameraComponent.self] {
            for marker in markers {
                let depth = -viewport.camera.convert(position: [Float(marker.anchor.x), Float(marker.anchor.y), Float(marker.anchor.z)], from: nil).z
                #expect(depth > lens.near && depth < lens.far)
            }
        }
        let point = try #require(viewport.project(.init(x: 0.5, y: 0.5, z: 0)))
        let hits = try viewport.spatialHandleHits(at: point, revision: 1)
        #expect(hits.first == 2)
        #expect(Set(hits) == [0, 2, 3])
        #expect(hits.count == 3)
        #expect(try viewport.surfaceHit(at: point, revision: 1) != nil)
        let section = SectionAnalysisResult.Plane(sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
            origin: .init(x: 0, y: 0, z: 0.15), normal: .init(x: 0, y: 0, z: 1),
            u: .init(x: 1, y: 0, z: 0), v: .init(x: 0, y: 1, z: 0))
        try viewport.applySection(plane: section, side: .front, tolerance: 0)
        let sectionHits = try viewport.spatialHandleHits(at: point, revision: 1)
        #expect(sectionHits.first == 2)
        #expect(Set(sectionHits) == [0, 1, 2])
        #expect(try viewport.surfaceHit(at: point, revision: 1) == nil)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try viewport.spatialHandleHits(at: CGPoint(x: CGFloat.nan, y: 0), revision: 1)
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
            includesAxes: true,
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
                occurrenceMaterials: [:],
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
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
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

        let mountedScene = try #require(viewport.root.scene)
        let tickQuery = EntityQuery(where: .has(TextComponent.self))
        let tickDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !mountedScene.performQuery(tickQuery).contains(where: {
            $0.isEnabledInHierarchy && $0.visualBounds(relativeTo: $0).extents.y > 0
        }), ContinuousClock.now < tickDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let publishedTicks = Array(mountedScene.performQuery(tickQuery)).filter {
            $0.isEnabledInHierarchy && !$0.name.hasPrefix("Reference Axis ")
        }
        try #require(!publishedTicks.isEmpty)
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        let renderedCamera = viewport.camera.clone(recursive: false)
        renderer.entities.append(renderedCamera)
        renderer.activeCamera = renderedCamera
        for label in publishedTicks { renderer.entities.append(label.clone(recursive: true)) }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        for _ in 0..<8 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                        onComplete: { _ in continuation.resume() })
                } catch { continuation.resume(throwing: error) }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&pixels, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let visiblePixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 10 }.count
        #expect(visiblePixels > 100, "Production grid labels must produce visible GPU pixels, not just entity bounds.")
        // The mount withholds spatial picking while waiting for the next native
        // camera frame. That must not withdraw already published annotations.
        viewport.setPresentationEnabled(false)
        #expect(publishedTicks.allSatisfy { $0.isEnabledInHierarchy })
        viewport.setPresentationEnabled(true)

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

        // Geometry replacement must retain the resolved camera and native tick
        // glyphs. Observe engine frames, not merely eventual readiness.
        let replacement = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: viewport)
        let scene = try #require(viewport.root.scene)
        let textQuery = EntityQuery(where: .has(TextComponent.self))
        let glyphDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var originalLabels: [Entity] = []
        while ContinuousClock.now < glyphDeadline {
            originalLabels = Array(scene.performQuery(textQuery)).filter { $0.isEnabledInHierarchy }
            if !originalLabels.isEmpty && originalLabels.allSatisfy({ $0.visualBounds(relativeTo: $0).extents.y > 0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!originalLabels.isEmpty)
        try #require(originalLabels.allSatisfy { $0.visualBounds(relativeTo: $0).extents.y > 0 })
        let originalParents = originalLabels.map { $0.parent }
        let priorLayout = layout(camera: camera)
        camera.focus = priorLayout.focus
        camera.referenceScale = priorLayout.scale / camera.zoom
        let changedLayout = ViewportLayout(modelBounds: CGRect(x: -10, y: -10, width: 20, height: 20),
            size: size, camera: camera, basis: basis, verticalBounds: -10...10)
        var observedFrames = 0
        var blankFrames = 0
        var blankTextFrames = 0
        let subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in
            observedFrames += 1
            let previousVisible = viewport.project(.origin) != nil && viewport.gridScaleReadout != nil
            let replacementVisible = replacement.project(.origin) != nil && replacement.gridScaleReadout != nil
            if !previousVisible && !replacementVisible {
                blankFrames += 1
            }
            if !originalLabels.contains(where: { $0.isEnabledInHierarchy && $0.visualBounds(relativeTo: $0).extents.y > 0 }) {
                blankTextFrames += 1
            }
        }
        defer { subscription.cancel() }
        controller.rootView = view(changedLayout, revision: 2, renderer: replacement)
        let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < replacementDeadline {
            controller.view.layoutSubtreeIfNeeded()
            if replacement.gridScaleReadout != nil, replacement.project(.origin) != nil,
               observedFrames >= 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observedFrames >= 3)
        #expect(replacement.camera === viewport.camera,
                "Hover-only frame replacement must not replace the mounted camera.")
        #expect(replacement.camera.parent !== replacement.root)
        #expect(blankFrames == 0, "An unchanged-camera overlay replacement blanked a native engine frame.")
        #expect(blankTextFrames == 0, "A model replacement withdrew already drawn tick labels.")
        for (label, parent) in zip(originalLabels, originalParents) {
            #expect(label.parent === parent)
            #expect(label.isEnabledInHierarchy)
            #expect(label.visualBounds(relativeTo: label).extents.y > 0)
        }
        #expect(replacement.gridScaleReadout != nil)
        let replacementProjection = try #require(replacement.project(.origin))
        #expect(hypot(replacementProjection.x - expectedUpdatedProjection.x,
                      replacementProjection.y - expectedUpdatedProjection.y) <= 1)
        var current = replacement
        let mountedCamera = current.camera
        for revision in UInt64(3)...10 {
            let next = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: current)
            controller.rootView = view(changedLayout, revision: revision, renderer: next)
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while next.appliedViewportRevision != revision || next.gridScaleReadout == nil {
                try #require(ContinuousClock.now < deadline)
                #expect(originalLabels.allSatisfy { $0.isEnabledInHierarchy })
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(next.camera === mountedCamera)
            let point = try #require(next.project(.origin))
            #expect(hypot(point.x - replacementProjection.x, point.y - replacementProjection.y) < 0.5)
            #expect(originalLabels.allSatisfy { $0.isEnabledInHierarchy })
            current = next
        }
        current.invalidateCamera()
        #expect(originalLabels.allSatisfy { !$0.isEnabledInHierarchy })
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
                occurrenceMaterials: [:],
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
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
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

    /// The host owns one native scene, and that scene is never empty.
    ///
    /// Withdrawing a frame must leave its root drawing in the scene, because
    /// the cache withdraws the requested identity for the whole of every
    /// rebuild and a host that emptied its scene for that span would black
    /// the canvas out on each document mutation. The successor frame is what
    /// removes the predecessor, and it is adopted by that same scene: a host
    /// unmounted per source change would hand reused native resources to a
    /// scene whose predecessor is still being discarded.
    @Test(.timeLimit(.minutes(1)))
    func withdrawnFrameKeepsDrawingUntilItsSuccessorAttaches() async throws {
        _ = NSApplication.shared
        let size = CGSize(width: 480, height: 360)
        func makeViewport() async throws -> RealityViewport {
            let batch = try RealityViewportSpatialBatch(
                includesAxes: true, renderOrigin: .origin, retainedSurfaceByteCount: 0
            )
            return try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        }
        let first = try await makeViewport()
        let second = try await makeViewport()
        var reportedError: MeshSourcePresentationRenderError?
        func view(_ viewport: RealityViewport?, revision: UInt64) -> some View {
            RealityViewportView(
                viewport: viewport,
                viewportRevision: revision,
                displayMode: .solid,
                shading: .init(style: .flat),
                occurrenceMaterials: [:],
                layout: .init(
                    modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
                    size: size,
                    camera: .init(zoom: 1, projection: .parallel),
                    basis: .isometric,
                    verticalBounds: -0.01...0.01
                ),
                interaction: .init(
                    sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [], hoveredSceneNodeID: nil
                ),
                sectionPlane: nil,
                retainedSide: .front,
                sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }
            )
            .frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(first, revision: 1))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer {
            first.unbind()
            second.unbind()
            window.contentViewController = nil
            window.close()
        }

        func settle(until ready: () -> Bool) async throws -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while ContinuousClock.now < deadline {
                controller.view.layoutSubtreeIfNeeded()
                if ready() { return true }
                try await Task.sleep(for: .milliseconds(20))
            }
            return ready()
        }

        let mounted = try await settle {
            reportedError == nil && first.appliedViewportRevision == 1 && first.root.scene != nil
        }
        #expect(mounted)
        let scene = try #require(first.root.scene)

        controller.rootView = view(nil, revision: 2)
        // Nothing may change here, so run the host long enough that an update
        // which removed the root would have done so before this is read.
        for _ in 0..<10 {
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.root.scene === scene)

        controller.rootView = view(second, revision: 3)
        let adopted = try await settle {
            reportedError == nil && second.appliedViewportRevision == 3
                && second.root.scene != nil && first.root.scene == nil
        }
        #expect(adopted)
        #expect(second.root.scene === scene)
        #expect(first.root.scene == nil)
    }
}
