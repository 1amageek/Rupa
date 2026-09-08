import AppKit
import Metal
import RealityKit
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
import simd
@testable import RupaRendering

/// Probes RealityKit's native collision resource for a zero-depth extruded path.
@Suite(.serialized)
@MainActor
struct RealityViewportSpatialCollisionTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func chromeExclusionsShareGeneratedFillBudget(grid: Bool) async throws {
        _ = NSApplication.shared
        let descriptor = RealityViewportSpatialBatch.PlanarPath(
            path: Path(CGRect(x: 0, y: 0, width: 0.01, height: 0.01)), origin: .origin,
            xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: [1, 1, 1, 1],
            handleIndex: 0, hitTolerancePoints: 8)
        let bounds = try GeometryBounds3D(minimum: .init(x: -0.01, y: -0.01, z: -0.01),
            maximum: .init(x: 0.01, y: 0.01, z: 0.01))
        let rulers: RealityViewportSpatialBatch.BoundsRulers? = grid ? nil : .init(
            input: .init(bounds: bounds, labels: .init(x: "X", y: "Y", z: "Z")),
            heightPoints: 9, color: [1, 1, 1, 1])
        let batch = try RealityViewportSpatialBatch(paths: [descriptor], boundsRulers: rulers,
            includesGrid: grid, handleCount: 1, renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let baseline = try await RealityViewportSpatialResources.prepare(batch: batch)
        let bounded = try RealityViewportSpatialBatch(paths: [descriptor], boundsRulers: rulers,
            includesGrid: grid, handleCount: 1, renderOrigin: .origin, retainedSurfaceByteCount: 0,
            limits: .init(maxItemCount: baseline.preparedItemCount + 1,
                maxPositionCount: batch.limits.maxPositionCount, maxTriangleCount: batch.limits.maxTriangleCount,
                maxRetainedByteCount: batch.limits.maxRetainedByteCount))
        let prepared = try await RealityViewportSpatialResources.prepare(batch: bounded)
        let camera = Entity()
        camera.position.z = 1
        var lens = OrthographicCameraComponent()
        lens.scale = 1; lens.near = 0.01; lens.far = 10
        camera.components.set(lens)
        let capture = RealityViewCapture()
        let size = CGSize(width: 320, height: 240)
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(camera)
            content.add(prepared.root)
            capture.content = content
        }.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
            backing: .buffered, defer: false)
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
        while capture.content?.project(point: .zero, to: .local) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        let content = try #require(capture.content)
        let rect = CGRect(origin: .zero, size: size)
        let ruler = RulerConfiguration(displayUnit: .meter, minorTickMeters: 0.1,
            majorTickMeters: 1, visibleSpanMeters: 10)
        #expect(try prepared.updateCamera(camera: camera, content: content, safeRect: rect,
            excludedRects: [rect], gridRuler: grid ? ruler : nil,
            gridBasis: .axisFront(.z), gridSize: size) == nil)
        do {
            let failure = try prepared.updateCamera(camera: camera, content: content, safeRect: rect,
                excludedRects: [rect, rect], gridRuler: grid ? ruler : nil,
                gridBasis: .axisFront(.z), gridSize: size)
            #expect(grid && failure?.code == .resourceExhausted)
        } catch let error as MeshSourcePresentationRenderError {
            #expect(!grid)
            #expect(error.code == .resourceExhausted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedFillAdmissionIsCumulative() async throws {
        let descriptor = RealityViewportSpatialBatch.PlanarPath(
            path: Path(CGRect(x: 0, y: 0, width: 0.01, height: 0.01)), origin: .origin,
            xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: [1, 1, 1, 1],
            handleIndex: 0, hitTolerancePoints: 8)
        let batch = try RealityViewportSpatialBatch(paths: [descriptor], handleCount: 1,
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let prepared = try await RealityViewportSpatialResources.prepare(batch: batch)
        let exact = MeshSourcePresentationPlanLimits(maxItemCount: prepared.preparedItemCount,
            maxPositionCount: prepared.preparedPositionCount, maxTriangleCount: prepared.preparedTriangleCount,
            maxRetainedByteCount: prepared.preparedByteCount)
        for field in 0...4 {
            let limits = MeshSourcePresentationPlanLimits(maxItemCount: exact.maxItemCount - (field == 1 ? 1 : 0),
                maxPositionCount: exact.maxPositionCount - (field == 2 ? 1 : 0),
                maxTriangleCount: exact.maxTriangleCount - (field == 3 ? 1 : 0),
                maxRetainedByteCount: exact.maxRetainedByteCount - (field == 4 ? 1 : 0))
            do {
                let bounded = try RealityViewportSpatialBatch(paths: [descriptor], handleCount: 1,
                    renderOrigin: .origin, retainedSurfaceByteCount: 0, limits: limits)
                _ = try await RealityViewportSpatialResources.prepare(batch: bounded)
                #expect(field == 0)
            } catch let error as MeshSourcePresentationRenderError {
                #expect(field != 0)
                #expect(error.code == .resourceExhausted)
            }
        }
        let pair = try RealityViewportSpatialBatch(paths: [descriptor, descriptor], handleCount: 1,
            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        let dynamicItems = prepared.preparedItemCount - batch.itemCount
        do {
            let bounded = try RealityViewportSpatialBatch(paths: [descriptor, descriptor], handleCount: 1,
                renderOrigin: .origin, retainedSurfaceByteCount: 0,
                limits: .init(maxItemCount: pair.itemCount + dynamicItems,
                    maxPositionCount: pair.limits.maxPositionCount, maxTriangleCount: pair.limits.maxTriangleCount,
                    maxRetainedByteCount: pair.limits.maxRetainedByteCount))
            _ = try await RealityViewportSpatialResources.prepare(batch: bounded)
            Issue.record("A cached path resource bypassed cumulative per-fragment proxy admission.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .resourceExhausted)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func filledFootprintsPreserveHolesAndBoundaryTolerance(perspective: Bool, planar: Bool) async throws {
        _ = NSApplication.shared
        let origin = Point3D(x: 0.002, y: -0.003, z: 0.001)
        func world(_ x: Double, _ y: Double) -> Point3D {
            .init(x: origin.x + x, y: origin.y + y * 0.8, z: origin.z + y * 0.6)
        }
        let vertices = [world(-0.004, -0.004), world(0.004, -0.004),
            world(0.004, 0.004), world(-0.004, 0.004),
            world(-0.0015, -0.0015), world(0.0015, -0.0015),
            world(0.0015, 0.0015), world(-0.0015, 0.0015)]
        let indices: [UInt32] = [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
            2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]
        var path = Path(CGRect(x: -0.004, y: -0.004, width: 0.008, height: 0.008))
        path.addRect(CGRect(x: -0.0015, y: -0.0015, width: 0.003, height: 0.003))
        let back = ViewportProjectionBasis(mode: .orbit, xDirection: .init(dx: -1, dy: 0),
            yDirection: .init(dx: 0, dy: -1), zDirection: .zero)
        for tolerance: Float in [0, 8] {
            let meshes: [RealityViewportSpatialBatch.Mesh] = planar ? [] : [
                .init(positions: vertices, indices: indices, topology: .triangles, color: [1, 1, 1, 1],
                    handleIndex: 0, hitTolerancePoints: tolerance)]
            let paths: [RealityViewportSpatialBatch.PlanarPath] = planar ? [
                .init(path: path, origin: origin, xAxis: [1, 0, 0], yAxis: [0, 0.8, 0.6],
                    color: [1, 1, 1, 1], handleIndex: 0, hitTolerancePoints: tolerance)] : []
            let batch = try RealityViewportSpatialBatch(meshes: meshes, paths: paths, handleCount: 1,
                renderOrigin: origin, retainedSurfaceByteCount: 0)
            let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
            let size = CGSize(width: 640, height: 480)
            var reportedError: MeshSourcePresentationRenderError?
            func view(_ revision: UInt64) -> some View {
                RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                    shading: .init(style: .flat), materialColors: [:],
                    layout: .init(modelBounds: CGRect(x: -0.006, y: -0.006, width: 0.012, height: 0.012),
                        size: size, camera: .init(zoom: revision == 1 ? 0.6 : 1,
                            pan: revision == 3 ? CGSize(width: 19, height: -11) : .zero,
                            projection: perspective ? .standardPerspective : .parallel),
                        basis: revision == 1 ? .axisFront(.z) : revision == 2 ? back : .isometric,
                        verticalBounds: -0.006...0.006),
                    interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                        previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                    sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                    onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height)
            }
            let controller = NSHostingController(rootView: view(1))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.orderFront(nil)
            defer { viewport.unbind(); window.contentViewController = nil; window.close() }
            func shapes(_ entity: Entity) -> [ShapeResource] {
                var values = entity.components[CollisionComponent.self]?.shapes ?? []
                for child in entity.children { values.append(contentsOf: shapes(child)) }
                return values
            }
            let originalShapes = shapes(viewport.root)
            for revision: UInt64 in 1...3 {
                if revision > 1 { controller.rootView = view(revision) }
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while viewport.appliedViewportRevision != revision || viewport.project(origin) == nil {
                    try #require(ContinuousClock.now < deadline)
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(reportedError == nil)
                let center = try #require(viewport.project(origin))
                let fill = try #require(viewport.project(world(0.0027, 0)))
                let projected = try vertices.map { try #require(viewport.project($0)) }
                var projectedFill = Path()
                for start in [0, 4] {
                    projectedFill.move(to: projected[start])
                    for index in (start + 1)..<(start + 4) { projectedFill.addLine(to: projected[index]) }
                    projectedFill.closeSubpath()
                }
                func expectedHit(_ point: CGPoint) -> Bool {
                    if projectedFill.contains(point, eoFill: true) { return true }
                    for start in [0, 4] {
                        for offset in 0..<4 {
                            let a = projected[start + offset], b = projected[start + (offset + 1) % 4]
                            let dx = b.x - a.x, dy = b.y - a.y
                            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
                            if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= CGFloat(tolerance) { return true }
                        }
                    }
                    return false
                }
                #expect(try viewport.spatialHandleHits(at: fill, revision: revision) == [0])
                // A nearly edge-on hole may be narrower than twice the explicit
                // tolerance. Its center then legitimately belongs to the rim.
                #expect(try viewport.spatialHandleHits(at: center, revision: revision).contains(0) == expectedHit(center))
                for (coordinate, direction) in [(0.004, CGFloat(1)), (0.0015, CGFloat(-1))] {
                    let edge = try #require(viewport.project(world(coordinate, 0)))
                    let edgeTop = try #require(viewport.project(world(coordinate, 0.0005)))
                    let dx = edgeTop.x - edge.x, dy = edgeTop.y - edge.y
                    let length = hypot(dx, dy)
                    try #require(length > 0)
                    var normal = CGPoint(x: -dy / length, y: dx / length)
                    if normal.x * (edge.x - center.x) + normal.y * (edge.y - center.y) < 0 {
                        normal.x = -normal.x; normal.y = -normal.y
                    }
                    for distance: CGFloat in [6, 10] {
                        let sample = CGPoint(x: edge.x + direction * distance * normal.x,
                            y: edge.y + direction * distance * normal.y)
                        let actual = try viewport.spatialHandleHits(at: sample, revision: revision).contains(0)
                        #expect(actual == expectedHit(sample),
                            "Revision \(revision), tolerance \(tolerance), edge \(coordinate), offset \(distance)")
                    }
                }
                #expect(shapes(viewport.root) == originalShapes)
                #expect(throws: MeshSourcePresentationRenderError.self) {
                    try viewport.spatialHandleHits(at: fill, revision: revision + 1)
                }
                func setVisualsEnabled(_ entity: Entity, _ enabled: Bool) {
                    if entity.components[ModelComponent.self] != nil { entity.isEnabled = enabled }
                    for child in entity.children { setVisualsEnabled(child, enabled) }
                }
                setVisualsEnabled(viewport.root, false)
                #expect(try viewport.spatialHandleHits(at: fill, revision: revision).isEmpty)
                setVisualsEnabled(viewport.root, true)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func cameraFootprintsIgnoreGlyphSize(perspective: Bool, label: Bool) async throws {
        _ = NSApplication.shared
        let anchor = Point3D(x: 0.004, y: 0.002, z: -0.003)
        let offset = CGPoint(x: -30, y: 20)
        let rectangle = CGRect(x: 14, y: -10, width: 44, height: 22)
        let path = Path(CGRect(x: -1, y: -1, width: 2, height: 2))
        let labels: [RealityViewportSpatialBatch.Label] = label ? [
            .init(text: "Wide visual label", anchor: anchor, offset: .fixed(offset), heightPoints: 12,
                  color: [1, 1, 1, 1], handleIndex: 0, hitRectPoints: rectangle)
        ] : []
        let paths: [RealityViewportSpatialBatch.CameraPath] = label ? [] : [
            .init(path: path, anchor: anchor, offset: .fixed(offset), color: [1, 1, 1, 1],
                  handleIndex: 0, hitTolerancePoints: 8)
        ]
        let origin = Point3D(x: 0.003, y: -0.003, z: 0.002)
        let batch = try RealityViewportSpatialBatch(labels: labels, cameraPaths: paths,
            handleCount: 1, renderOrigin: origin, retainedSurfaceByteCount: 0)
        for limits in [
            MeshSourcePresentationPlanLimits(maxItemCount: batch.itemCount - 1,
                maxPositionCount: batch.limits.maxPositionCount, maxTriangleCount: batch.limits.maxTriangleCount,
                maxRetainedByteCount: batch.limits.maxRetainedByteCount),
            .init(maxItemCount: batch.limits.maxItemCount, maxPositionCount: batch.limits.maxPositionCount,
                  maxTriangleCount: batch.limits.maxTriangleCount, maxRetainedByteCount: batch.admittedByteCount - 1)
        ] {
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try RealityViewportSpatialBatch(labels: labels, cameraPaths: paths,
                    handleCount: 1, renderOrigin: origin, retainedSurfaceByteCount: 0, limits: limits)
            }
        }
        let viewport = try await RealityViewport.prepare(plan: nil, spatialBatch: batch, reusing: nil)
        let size = CGSize(width: 640, height: 360)
        var reportedError: MeshSourcePresentationRenderError?
        func view(zoom: CGFloat, revision: UInt64) -> some View {
            RealityViewportView(viewport: viewport, viewportRevision: revision, displayMode: .solid,
                shading: .init(style: .flat), materialColors: [:],
                layout: .init(modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02), size: size,
                    camera: .init(zoom: zoom, pan: revision == 2 ? CGSize(width: 23, height: -17) : .zero,
                        projection: perspective ? .standardPerspective : .parallel),
                    basis: revision == 3 ? .isometric : .axisFront(.z), verticalBounds: -0.01...0.01),
                interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
                sectionPlane: nil, retainedSide: .front, sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }).frame(width: size.width, height: size.height)
        }
        let controller = NSHostingController(rootView: view(zoom: 0.2, revision: 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer { viewport.unbind(); window.contentViewController = nil; window.close() }
        func colliders(_ entity: Entity) -> [Entity] {
            var result = entity.components[CollisionComponent.self] == nil ? [] : [entity]
            for child in entity.children { result.append(contentsOf: colliders(child)) }
            return result
        }
        let entities = colliders(viewport.root)
        try #require(entities.count == 1)
        let entity = entities[0]
        let shape = try #require(entity.components[CollisionComponent.self]?.shapes.first)
        for (iteration, zoom) in [CGFloat(0.2), 1, 2].enumerated() {
            let revision = UInt64(iteration + 1)
            if iteration > 0 { controller.rootView = view(zoom: zoom, revision: revision) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while viewport.appliedViewportRevision != revision || viewport.project(anchor) == nil {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(reportedError == nil)
            let projected = try #require(viewport.project(anchor))
            let center = CGPoint(x: projected.x + offset.x, y: projected.y + offset.y)
            let inside = label ? CGPoint(x: center.x + rectangle.minX + 1, y: center.y + rectangle.maxY - 1)
                : CGPoint(x: center.x + 7, y: center.y)
            let outside = label ? CGPoint(x: center.x + rectangle.minX - 1, y: center.y + rectangle.midY)
                : CGPoint(x: center.x + 9, y: center.y)
            #expect(try viewport.spatialHandleHits(at: inside, revision: revision) == [0])
            #expect(try viewport.spatialHandleHits(at: outside, revision: revision).isEmpty)
            #expect(entity.components[CollisionComponent.self]?.shapes.first == shape)
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try viewport.spatialHandleHits(at: inside, revision: revision + 1)
            }
            viewport.root.isEnabled = false
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try viewport.spatialHandleHits(at: inside, revision: revision)
            }
            viewport.root.isEnabled = true
        }
    }

    @Test
    func labelRectanglesAreExplicitAndValidated() throws {
        for rect in [CGRect(x: 0, y: 0, width: 0, height: 10),
                     CGRect(x: 0, y: 0, width: 10, height: -1),
                     CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10),
                     CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 10)] {
            #expect(throws: MeshSourcePresentationRenderError.self) {
                try RealityViewportSpatialBatch(labels: [
                    .init(text: "Label", anchor: .origin, offset: .zero, heightPoints: 12,
                          color: [1, 1, 1, 1], handleIndex: 0, hitRectPoints: rect)
                ], handleCount: 1, renderOrigin: .origin, retainedSurfaceByteCount: 0)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pathNormalizationRejectsEmptyAndUnadmittedGrowth() async throws {
        var source = Path()
        source.addRect(CGRect(x: 0, y: 0, width: 2, height: 2))
        source.addRect(CGRect(x: 1, y: 1, width: 2, height: 2))
        let normalized = try await RealityViewportSpatialResources.normalizedPath(source,
            additionalPositionLimit: 100, additionalByteLimit: 100_000)
        func count(_ path: Path) -> Int {
            var result = 0
            path.forEach {
                switch $0 {
                case .move, .line: result += 1
                case .quadCurve: result += 2
                case .curve: result += 3
                case .closeSubpath: break
                }
            }
            return result
        }
        let growth = count(normalized) - count(source)
        try #require(growth > 0)
        let bytes = growth * MemoryLayout<Path.Element>.stride
        _ = try await RealityViewportSpatialResources.normalizedPath(source,
            additionalPositionLimit: growth, additionalByteLimit: bytes)
        for limits in [(growth - 1, bytes), (growth, bytes - 1)] {
            do {
                _ = try await RealityViewportSpatialResources.normalizedPath(source,
                    additionalPositionLimit: limits.0, additionalByteLimit: limits.1)
                Issue.record("Native normalization exceeded aggregate admission.")
            } catch let error as MeshSourcePresentationRenderError {
                #expect(error.code == .resourceExhausted)
            }
        }
        let descriptor = RealityViewportSpatialBatch.PlanarPath(path: source, origin: .origin,
            xAxis: [1, 0, 0], yAxis: [0, 1, 0], color: [1, 1, 1, 1])
        let baseline = try RealityViewportSpatialBatch(paths: [descriptor], renderOrigin: .origin,
            retainedSurfaceByteCount: 0)
        for headroom in [(growth, bytes), (growth - 1, bytes), (growth, bytes - 1)] {
            let admitted = try RealityViewportSpatialBatch(paths: [descriptor], renderOrigin: .origin,
                retainedSurfaceByteCount: 0, limits: .init(maxItemCount: baseline.itemCount,
                    maxPositionCount: baseline.positionCount + headroom.0,
                    maxTriangleCount: baseline.limits.maxTriangleCount,
                    maxRetainedByteCount: baseline.admittedByteCount + headroom.1))
            let fits = headroom.0 == growth && headroom.1 == bytes
            do {
                _ = try await RealityViewportSpatialResources.prepare(batch: admitted)
                #expect(fits, "Production preparation exceeded normalization admission.")
            } catch let error as MeshSourcePresentationRenderError {
                #expect(!fits)
                #expect(error.code == .resourceExhausted)
            }
        }
        var emptyFill = Path()
        emptyFill.addRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        emptyFill.addRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        do {
            _ = try await RealityViewportSpatialResources.normalizedPath(emptyFill,
                additionalPositionLimit: 100, additionalByteLimit: 100_000)
            Issue.record("An empty normalized fill was sent to native extrusion.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .invalidSceneItem)
        }
    }

    @MainActor
    private final class RealityViewCapture {
        var content: RealityViewCameraContent?
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeExtrudedPathCollisionPreservesHoleAcrossEntityTransforms() async throws {
        _ = NSApplication.shared

        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        var profile = Path()
        profile.addRect(CGRect(x: -1, y: -1, width: 2, height: 2))
        profile.addRect(CGRect(x: -0.3, y: -0.3, width: 0.6, height: 0.6))
        let normalized = try await RealityViewportSpatialResources.normalizedPath(profile,
            additionalPositionLimit: 100, additionalByteLimit: 100_000)
        let mesh = try await MeshResource(extruding: normalized, extrusionOptions: extrusion)
        #expect(!mesh.contents.instances.isEmpty)
        var unplaced = mesh.contents
        unplaced.instances = []
        var visited = false
        do {
            try RealityViewportSpatialResources.pathParts(unplaced) { _, _ in visited = true }
            Issue.record("Unplaced model templates became collision geometry.")
        } catch let error as MeshSourcePresentationRenderError {
            #expect(error.code == .invalidSceneItem)
        }
        #expect(!visited)
        let shape = try await ShapeResource.generateStaticMesh(from: mesh)

        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = "Native Extruded Hole"
        entity.components.set(CollisionComponent(shapes: [shape]))
        let originalMesh = try #require(entity.model?.mesh)
        let originalShape = try #require(entity.components[CollisionComponent.self]?.shapes.first)

        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        let renderCamera = Entity()
        var renderLens = OrthographicCameraComponent()
        renderLens.scale = 2
        renderLens.near = 0.01
        renderLens.far = 10
        renderCamera.components.set(renderLens)
        renderCamera.position.z = 3
        renderer.activeCamera = renderCamera
        renderer.entities.append(contentsOf: [renderCamera, entity.clone(recursive: true)])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 256, height: 256, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                    onComplete: { _ in continuation.resume() })
            } catch { continuation.resume(throwing: error) }
        }
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        texture.getBytes(&pixels, bytesPerRow: 256 * 4,
            from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
        #expect(pixels[(128 * 256 + 128) * 4] < 10, "The native rendered hole was filled.")
        #expect(pixels[(128 * 256 + 176) * 4] > 150, "The native filled sample was not rendered.")

        let camera = Entity()
        camera.position = [0, 0, 3]
        var lens = OrthographicCameraComponent()
        lens.scale = 4
        lens.near = 0.01
        lens.far = 100
        camera.components.set(lens)

        let capture = RealityViewCapture()
        let controller = NSHostingController(rootView: RealityView { content in
            content.camera = .virtual
            content.add(camera)
            content.add(entity)
            capture.content = content
        }.frame(width: 800, height: 600))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            capture.content?.remove(entity)
            capture.content?.remove(camera)
            capture.content = nil
            window.contentViewController = nil
            window.close()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while entity.scene == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let scene = try #require(entity.scene)

        let filled = SIMD3<Float>(0.75, 0, 0)
        let hole = SIMD3<Float>(0, 0, 0)
        let outside = SIMD3<Float>(1.25, 0, 0)

        func contains(_ bounds: BoundingBox, _ point: SIMD3<Float>) -> Bool {
            bounds.min.x - 0.001 <= point.x && point.x <= bounds.max.x + 0.001
                && bounds.min.y - 0.001 <= point.y && point.y <= bounds.max.y + 0.001
                && bounds.min.z - 0.001 <= point.z && point.z <= bounds.max.z + 0.001
        }

        func hasHit(_ localPoint: SIMD3<Float>, fromFront: Bool) -> Bool {
            let worldPoint = entity.convert(position: localPoint, to: nil)
            let normal = simd_normalize(entity.convert(direction: SIMD3<Float>(0, 0, 1), to: nil))
            let rayOrigin = worldPoint + (fromFront ? normal : -normal) * 2
            let rayDirection = fromFront ? -normal : normal
            return scene.raycast(origin: rayOrigin, direction: rayDirection, length: 4)
                .contains { $0.entity === entity }
        }

        func assertCurrentTransform(_ label: String) {
            let bounds = entity.visualBounds(relativeTo: nil)
            let filledWorldPoint = entity.convert(position: filled, to: nil)
            #expect(contains(bounds, filledWorldPoint), "Filled sample left the rendered bounds")
            for fromFront in [true, false] {
                #expect(hasHit(filled, fromFront: fromFront), "Filled sample missed")
                #expect(!hasHit(hole, fromFront: fromFront), "Hole sample collided")
                #expect(!hasHit(outside, fromFront: fromFront), "Outside sample collided")
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        assertCurrentTransform("initial")
        let initialBounds = entity.visualBounds(relativeTo: nil)

        entity.position = [0.35, -0.25, 0.4]
        entity.orientation = simd_quatf(angle: Float.pi / 7, axis: [0, 1, 0])
        entity.scale = SIMD3<Float>(repeating: 1.5)
        try await Task.sleep(for: .milliseconds(50))
        assertCurrentTransform("transformed")

        let transformedBounds = entity.visualBounds(relativeTo: nil)
        #expect(transformedBounds.extents.x > initialBounds.extents.x)
        #expect(entity.model?.mesh === originalMesh)
        #expect(entity.components[CollisionComponent.self]?.shapes.first == originalShape)
    }
}
