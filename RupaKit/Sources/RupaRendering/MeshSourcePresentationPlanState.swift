/// Query readiness is exact; the cache separately retains an overlay-only display.
enum MeshSourcePresentationPlanState {
    case idle
    case preparing(identity: RealityViewportPreparationRequest.Identity)
    case ready(identity: RealityViewportPreparationRequest.Identity,
               plan: MeshSourcePresentationRenderPlan?, surface: RealityViewport)
    case failed(identity: RealityViewportPreparationRequest.Identity, error: MeshSourcePresentationRenderError)

    var identity: RealityViewportPreparationRequest.Identity? {
        switch self {
        case .idle: nil
        case let .preparing(identity), let .ready(identity, _, _), let .failed(identity, _): identity
        }
    }
}
