import RupaViewportScene

/// MeshSource-native presentation adapter for existing drawing consumers.
///
/// The render owner should retain the plan returned by `makePlan(for:)` and
/// reuse it until the scene snapshot changes. Each call to `render(plan:visit:)`
/// traverses the immutable source buffers directly.
public struct MeshSourcePresentationRenderer: MeshSourcePresentationRendering, Sendable {
    public init() {}

    public func makePlan(
        for scene: UniversalViewportScene
    ) throws -> MeshSourcePresentationRenderPlan {
        try MeshSourcePresentationRenderPlan(scene: scene)
    }

    public func render(
        plan: MeshSourcePresentationRenderPlan,
        visit: (MeshSourcePresentationTriangle) throws -> Void
    ) throws {
        try plan.forEachTriangle(visit)
    }
}
