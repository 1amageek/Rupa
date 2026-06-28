import RupaCore

struct ViewportSlotWidthSourceTargetResolver {
    var document: DesignDocument

    func sourceTarget(for target: SelectionTarget) -> ViewportSlotWidthSourceTarget? {
        guard case .sketchEntity(let componentID) = target.component,
              let sketchReference = componentID.sketchEntityBaseReference,
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .sketch,
              reference.featureID == sketchReference.featureID else {
            return nil
        }
        return ViewportSlotWidthSourceTarget(
            featureID: sketchReference.featureID,
            entityID: sketchReference.entityID,
            target: SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(
                    .sketchEntity(
                        featureID: sketchReference.featureID,
                        entityID: sketchReference.entityID
                    )
                )
            )
        )
    }
}
