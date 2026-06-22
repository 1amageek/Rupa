import CoreGraphics

@MainActor
public final class ViewportIdentityHitResolver {
    public typealias RendererFactory = () throws -> ViewportIdentityBufferRenderer

    private struct Cache {
        var scene: ViewportScene
        var layout: ViewportLayout
        var buffer: ViewportIdentityBuffer
    }

    private var renderer: ViewportIdentityBufferRenderer?
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

    public func invalidate() {
        cached = nil
    }

    private func identityHit(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) throws -> ViewportHit? {
        let buffer = try identityBuffer(for: scene, layout: layout)
        return try buffer.sample(at: point).hit
    }

    private func identityBuffer(
        for scene: ViewportScene,
        layout: ViewportLayout
    ) throws -> ViewportIdentityBuffer {
        if let cached,
           cached.scene == scene,
           cached.layout == layout {
            return cached.buffer
        }

        let plan = ViewportIdentityPickRenderPlanBuilder()
            .build(scene: scene, layout: layout)
        let buffer = try identityRenderer().render(
            plan: plan,
            viewportSize: layout.viewportSize
        )
        cached = Cache(scene: scene, layout: layout, buffer: buffer)
        return buffer
    }

    private func identityRenderer() throws -> ViewportIdentityBufferRenderer {
        if let renderer {
            return renderer
        }
        let renderer = try rendererFactory()
        self.renderer = renderer
        return renderer
    }
}
