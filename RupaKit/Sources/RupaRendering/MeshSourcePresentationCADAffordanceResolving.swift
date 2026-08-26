import RupaCore
import RupaCoreTypes
import RupaViewportScene

public protocol MeshSourcePresentationCADAffordanceResolving: Sendable {
    func resolve(
        item: UniversalViewportSceneItem,
        navigation: MeshSourcePresentationNavigationMap,
        document: DesignDocument,
        generation: DocumentGeneration,
        cadInteraction: DocumentEvaluationContext?
    ) -> MeshSourcePresentationCADAffordanceAvailability
}
