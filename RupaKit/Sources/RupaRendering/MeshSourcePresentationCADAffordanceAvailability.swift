public enum MeshSourcePresentationCADAffordanceAvailability: Equatable, Sendable {
    case available(MeshSourcePresentationCADAffordanceContext)
    case unavailable(MeshSourcePresentationCADAffordanceUnavailableReason)
}
