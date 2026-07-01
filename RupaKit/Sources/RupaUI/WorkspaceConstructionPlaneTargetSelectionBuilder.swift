import RupaCore

struct WorkspaceConstructionPlaneTargetSelectionBuilder {
    var document: DesignDocument
    var selection: SelectionModel

    var sketchPointTargets: [SelectionTarget] {
        sketchPointTargets(from: selection.selectedTargets)
    }

    var constructionPlaneTargets: [SelectionTarget]? {
        let targets = selection.selectedTargets
        guard targets.isEmpty == false else {
            return nil
        }

        let classification = WorkspaceSelectionTargetClassification(targets: targets)
        let pointTargets = classification.vertexTargets + sketchPointTargets(from: targets)
        if targets.count == 1,
           classification.faceTargets.count == 1
            || classification.regionTargets.count == 1
            || classification.constructionPlaneTargets.count == 1 {
            return targets
        }
        if targets.count == 2,
           classification.faceTargets.count == 1,
           classification.edgeTargets.count == 1 {
            return targets
        }
        if targets.count >= 2,
           classification.edgeTargets.isEmpty,
           targets.count == classification.faceTargets.count
            + classification.regionTargets.count
            + classification.constructionPlaneTargets.count {
            return targets
        }
        if targets.count >= 2,
           targets.count == pointTargets.count {
            return targets
        }
        return nil
    }

    private func sketchPointTargets(from targets: [SelectionTarget]) -> [SelectionTarget] {
        let sketchEntityTargets = targets.filter { target in
            if case .sketchEntity = target.component {
                return true
            }
            return false
        }
        guard sketchEntityTargets.isEmpty == false else {
            return []
        }

        let explicitPointTargets = sketchEntityTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else {
                return false
            }
            return componentID.sketchPointReference != nil
        }
        let explicitPointTargetSet = Set(explicitPointTargets)

        do {
            let pointTargets = try SketchEntitySummaryService()
                .summarize(document: document)
                .entries
                .filter { $0.entityKind == "point" }
                .compactMap { $0.selectionTarget() }
            let pointTargetSet = Set(pointTargets)
            return sketchEntityTargets.filter { target in
                if explicitPointTargetSet.contains(target) {
                    return true
                }
                return pointTargetSet.contains(target)
            }
        } catch {
            return explicitPointTargets
        }
    }
}
