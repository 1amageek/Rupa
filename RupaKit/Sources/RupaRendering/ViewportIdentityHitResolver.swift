import CoreGraphics
import RupaCore
import SwiftCAD

@MainActor
public final class ViewportIdentityHitResolver {
    public typealias RendererFactory = () throws -> any ViewportIdentityBufferRendering

    private struct CacheKey: Equatable {
        var scene: ViewportScene
        var layout: ViewportLayout
        var sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy
    }

    private struct Cache {
        var key: CacheKey
        var buffer: ViewportIdentityBuffer
    }

    private var renderer: (any ViewportIdentityBufferRendering)?
    private var cached: Cache?
    private let rendererFactory: RendererFactory

    public init(rendererFactory: @escaping RendererFactory = { try ViewportIdentityBufferRenderer() }) {
        self.rendererFactory = rendererFactory
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportHit? {
        do {
            return try identityHit(point: point, in: scene, layout: layout)
        } catch {
            return ViewportHitTester().hitTest(point: point, in: scene, layout: layout)
        }
    }

    public func selectionHits(
        in rect: CGRect,
        scene: ViewportScene,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all
    ) -> [ViewportHit] {
        do {
            let buffer = try identityBuffer(
                for: scene,
                layout: layout,
                sketchControlPointHitPolicy: sketchControlPointHitPolicy
            )
            return buffer.hits(in: rect)
        } catch {
            return ViewportSelectionRectangleHitTester().hits(
                in: rect,
                scene: scene,
                layout: layout,
                sketchControlPointHitPolicy: sketchControlPointHitPolicy
            )
        }
    }

    public func invalidate() {
        cached = nil
    }

    private func identityHit(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) throws -> ViewportHit? {
        let buffer = try identityBuffer(
            for: scene,
            layout: layout,
            sketchControlPointHitPolicy: .all
        )
        return try buffer.sample(at: point).hit
    }

    private func identityBuffer(
        for scene: ViewportScene,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy
    ) throws -> ViewportIdentityBuffer {
        let key = CacheKey(
            scene: scene,
            layout: layout,
            sketchControlPointHitPolicy: sketchControlPointHitPolicy
        )
        if let cached,
           cached.key == key {
            return cached.buffer
        }

        let index = ViewportIdentityPickIndexBuilder(
            sketchControlPointHitPolicy: sketchControlPointHitPolicy
        )
        .build(scene: scene)
        let plan = ViewportIdentityPickRenderPlanBuilder()
            .build(scene: scene, layout: layout, index: index)
        let buffer = try identityRenderer().render(
            plan: plan,
            viewportSize: layout.viewportSize
        )
        cached = Cache(key: key, buffer: buffer)
        return buffer
    }

    private func identityRenderer() throws -> any ViewportIdentityBufferRendering {
        if let renderer {
            return renderer
        }
        let renderer = try rendererFactory()
        self.renderer = renderer
        return renderer
    }
}
