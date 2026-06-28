import RupaCore

struct WorkspaceSketchCommandTargetResolver {
    func entity(from result: Result<InspectorSketchEntity?, Error>) -> InspectorSketchEntity? {
        switch result {
        case .success(let entity):
            return entity
        case .failure:
            return nil
        }
    }

    func slotSourceCurveTarget(for entity: InspectorSketchEntity?) -> SelectionTarget? {
        guard let entity,
              ["line", "arc", "spline"].contains(entity.entityKind) else {
            return nil
        }
        return SelectionTarget(
            sceneNodeID: entity.target.sceneNodeID,
            component: .sketchEntity(
                .sketchEntity(
                    featureID: entity.sourceFeatureID,
                    entityID: entity.entityID
                )
            )
        )
    }

    func vertexOffsetTarget(for entity: InspectorSketchEntity?) -> SelectionTarget? {
        guard let entity,
              vertexOffsetHandle(for: entity) != nil else {
            return nil
        }
        return entity.target
    }

    func vertexOffsetHandle(for entity: InspectorSketchEntity) -> SketchEntityPointHandle? {
        SketchVertexOffsetInspectorState(
            entityKind: entity.entityKind,
            entityID: entity.entityID,
            target: entity.target
        )
        .handle
    }
}
