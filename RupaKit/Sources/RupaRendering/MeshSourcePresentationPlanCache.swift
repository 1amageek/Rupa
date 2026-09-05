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
            // Construction already validated every range, transform, and index,
            // so publishing the plan does not traverse it a second time.
            result = .success(try MeshSourcePresentationRenderer().makePlan(for: scene))
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
