import AppKit
import RealityKit
import RupaCore
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func objectPreviewMovesSolidAndHandlesWithoutFrameReplacement(perspective: Bool) async throws {
    _ = NSApplication.shared
    let scene = try planCacheScene(suffix: "synchronous-preview")
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let id = try #require(scene.items.first).occurrenceID.rawValue
    let anchor = Point3D(x: 0.2, y: 0.2, z: 0)
    let arrow = RealityViewportSpatialBatch.CameraLine(points: [
        .init(anchor: anchor, offset: .zero),
        .init(anchor: anchor, offset: .directed(toward: anchor + .unitX, parallel: 40, perpendicular: 0))
    ], color: [1, 0, 0, 1], widthPoints: 2, handleIndex: 1, hitTolerancePoints: 7,
       objectPreviewOccurrenceID: id)
    let curveEnd = Point3D(x: 0.8, y: 0.5, z: 0.2)
    let curve = RealityViewportSpatialBatch.CameraLine(points: (0...1024).map { index in
        .init(anchor: anchor + (curveEnd - anchor) * (Double(index) / 1024), offset: .zero)
    }, color: [1, 1, 1, 1], handleIndex: 2,
       objectPreviewOccurrenceID: id)
    let batch = try RealityViewportSpatialBatch(markers: [
        .init(shape: .box, anchor: anchor, diameterPoints: 10, color: [1, 1, 1, 1],
              handleIndex: 0, hitTolerancePoints: 8, objectPreviewOccurrenceID: id)
    ], cameraLines: [arrow, curve], cameraPaths: [
        .init(path: Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))
            .strokedPath(StrokeStyle(lineWidth: 2)), anchor: anchor, offset: .zero,
              color: [1, 1, 1, 1], handleIndex: 3, hitTolerancePoints: 12,
              objectPreviewOccurrenceID: id)
    ], handleCount: 4, renderOrigin: .origin, retainedSurfaceByteCount: plan.retainedByteCount)
    #expect(batch.itemCount < 100)
    #expect(batch.positionCount >= 1025)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try RealityViewportSpatialBatch(cameraLines: [curve], renderOrigin: .origin,
            retainedSurfaceByteCount: 0, limits: .init(maxItemCount: 1,
                maxPositionCount: 1024, maxTriangleCount: 0, maxRetainedByteCount: 1_000_000))
    }
    let viewport = try await RealityViewport.prepare(plan: plan, spatialBatch: batch, reusing: nil)
    let size = CGSize(width: 512, height: 384)
    var reported: MeshSourcePresentationRenderError?
    let view = RealityViewportView(viewport: viewport, viewportRevision: 1, displayMode: .solid,
        shading: .init(style: .flat), occurrenceMaterials: [:],
        layout: .init(modelBounds: CGRect(x: -2, y: -2, width: 4, height: 4), size: size,
                      camera: .init(projection: perspective ? .standardPerspective : .parallel),
                      basis: .axisFront(.z), verticalBounds: -2...2),
        interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [], previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
        sectionPlane: nil, retainedSide: .front, sectionTolerance: 0, onUpdateResult: { reported = $0 })
        .frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: view)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.contentView?.layoutSubtreeIfNeeded()
    defer { viewport.unbind(); window.contentViewController = nil; window.close() }
    #expect(!window.isVisible && !window.isKeyWindow)
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while viewport.appliedViewportRevision != 1 || viewport.project(anchor) == nil {
        try #require(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(20))
    }
    _ = try viewport.updateSpatialCamera()
    #expect(reported == nil)
    func descendants(_ root: Entity) -> [Entity] { [root] + root.children.flatMap(descendants) }
    let entities = descendants(viewport.root)
    let marker = try #require(entities.first {
        viewport.spatialHandleIndex(for: $0) == 0 && $0 is ModelEntity
    })
    let line = try #require(entities.compactMap { $0 as? ModelEntity }.first {
        viewport.spatialHandleIndex(for: $0) == 1 && $0.model?.mesh.lowLevelMesh != nil
    })
    let lineResource = try #require(line.model?.mesh)
    let editHandle = try #require(entities.first {
        viewport.spatialHandleIndex(for: $0) == 3 && $0 is ModelEntity
    })
    let curveEntity = try #require(entities.compactMap { $0 as? ModelEntity }.first {
        viewport.spatialHandleIndex(for: $0) == 2 && $0.model?.mesh.lowLevelMesh != nil
    })
    let curveResource = try #require(curveEntity.model?.mesh)
    let surface = try #require(entities.compactMap { $0 as? ModelEntity }.first {
        $0.components[CollisionComponent.self]?.filter.group == RealityViewport.surfaceCollisionGroup
    })
    let sourceMesh = try #require(surface.model?.mesh)
    // No await, worker, root replacement or source publication between updates.
    for factor: Double in [1, 0.1, 0, -0.1, -1, 1] {
        let mutation = Transform3D(matrix: try Matrix4x4(values: [
            factor, 0, 0, 0.4, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
        ]))
        try viewport.applyObjectPreviews([id: mutation], displayMode: .solid)
        _ = try viewport.updateSpatialCamera()
        let moved = try ViewportWorldTransformAlgebra.transformedPoint(anchor, by: mutation)
        let position = marker.position(relativeTo: viewport.root)
        #expect(abs(Double(position.x) - moved.x) < 1e-5)
        #expect(abs(Double(position.y) - moved.y) < 1e-5)
        #expect(abs(Double(editHandle.position(relativeTo: viewport.root).x) - moved.x) < 1e-5)
        #expect(surface.model?.mesh !== sourceMesh)
        let bounds = surface.visualBounds(relativeTo: viewport.root)
        #expect(abs(Double(bounds.min.x) - (0.4 + min(0, factor))) < 1e-5)
        #expect(abs(Double(bounds.max.x) - (0.4 + max(0, factor))) < 1e-5)
        #expect(line.model?.mesh === lineResource)
        #expect(curveEntity.model?.mesh === curveResource)
        let curveMesh = try #require(curveResource.lowLevelMesh)
        let expectedEnd = try ViewportWorldTransformAlgebra.transformedPoint(curveEnd, by: mutation)
        curveMesh.withUnsafeBytes(bufferIndex: 0) {
            let points = $0.bindMemory(to: SIMD3<Float>.self)
            #expect(abs(Double(points[0].x) - moved.x) < 1e-5)
            #expect(abs(Double(points[1024].x) - expectedEnd.x) < 1e-5)
            #expect(abs(Double(points[1024].z) - expectedEnd.z) < 1e-5)
        }
        let mesh = try #require(lineResource.lowLevelMesh)
        var first = SIMD3<Float>.zero, last = SIMD3<Float>.zero
        mesh.withUnsafeBytes(bufferIndex: 0) {
            let points = $0.bindMemory(to: SIMD3<Float>.self)
            first = points[0]; last = points[1]
        }
        let a = try #require(viewport.project(.init(x: Double(first.x), y: Double(first.y), z: Double(first.z))))
        let b = try #require(viewport.project(.init(x: Double(last.x), y: Double(last.y), z: Double(last.z))))
        #expect(abs(hypot(b.x - a.x, b.y - a.y) - 40) < 0.5)
        let screen = try #require(viewport.project(moved))
        #expect(try viewport.spatialHandleHits(at: screen, revision: 1).contains(0))
        #expect(try viewport.spatialHandleHits(at: screen, revision: 1).contains(3))
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            for radius: Double in [7.99, 8.01] {
                let point = CGPoint(x: screen.x + cos(angle) * radius, y: screen.y + sin(angle) * radius)
                #expect(try viewport.spatialHandleHits(at: point, revision: 1).contains(0) == (radius < 8),
                        "Marker radius must match screen points in every direction: \(perspective), \(factor), \(step), \(radius)")
            }
        }
    }
    try viewport.applyObjectPreviews([:], displayMode: .solid)
    _ = try viewport.updateSpatialCamera()
    #expect(surface.model?.mesh === sourceMesh)
    #expect(abs(Double(marker.position(relativeTo: viewport.root).x) - anchor.x) < 1e-5)
    #expect(descendants(viewport.root).count == entities.count)
}
