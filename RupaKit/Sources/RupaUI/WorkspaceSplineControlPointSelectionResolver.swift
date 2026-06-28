import RupaCore

struct WorkspaceSplineControlPointSelectionResolver {
    var selection: SelectionModel

    func selectedControlPointIndexes(for entity: InspectorSketchEntity) -> [Int] {
        var indexes: [Int] = []
        var seenIndexes: Set<Int> = []
        for target in selection.selectedTargets {
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchControlPointReference,
                  reference.featureID == entity.sourceFeatureID,
                  reference.entityID == entity.entityID,
                  entity.controlPoints.indices.contains(reference.index),
                  seenIndexes.insert(reference.index).inserted else {
                continue
            }
            indexes.append(reference.index)
        }
        return indexes
    }

    func slideInput(for entity: InspectorSketchEntity?) -> WorkspaceSplineControlPointSlideInput? {
        guard let entity,
              entity.entityKind == "spline" else {
            return nil
        }
        let selectedIndexes = selectedControlPointIndexes(for: entity)
        guard selectedIndexes.isEmpty == false else {
            return nil
        }
        return WorkspaceSplineControlPointSlideInput(
            target: entity.target,
            controlPointIndexes: selectedIndexes
        )
    }
}
