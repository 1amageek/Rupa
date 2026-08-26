import RupaCoreTypes
import RupaViewportScene

@MainActor
final class MeshSourcePresentationPlanCache {
    private var snapshotID: EvaluationSnapshotID?
    private var cachedResult: Result<MeshSourcePresentationRenderPlan, MeshSourcePresentationRenderError>?

    func result(
        for scene: UniversalViewportScene
    ) -> Result<MeshSourcePresentationRenderPlan, MeshSourcePresentationRenderError> {
        if snapshotID == scene.snapshotID,
           let cachedResult {
            return cachedResult
        }
        let result: Result<MeshSourcePresentationRenderPlan, MeshSourcePresentationRenderError>
        do {
            let renderer = MeshSourcePresentationRenderer()
            let plan = try renderer.makePlan(for: scene)
            try renderer.render(plan: plan) { _ in }
            result = .success(plan)
        } catch let error as MeshSourcePresentationRenderError {
            result = .failure(error)
        } catch {
            result = .failure(
                MeshSourcePresentationRenderError(
                    code: .failed,
                    message: String(describing: error)
                )
            )
        }
        snapshotID = scene.snapshotID
        cachedResult = result
        return result
    }
}
