import RupaViewportScene

public protocol MeshSourcePresentationRendering: Sendable {
    func makePlan(
        for scene: UniversalViewportScene
    ) throws -> MeshSourcePresentationRenderPlan

    func render(
        plan: MeshSourcePresentationRenderPlan,
        visit: (MeshSourcePresentationTriangle) throws -> Void
    ) throws
}
