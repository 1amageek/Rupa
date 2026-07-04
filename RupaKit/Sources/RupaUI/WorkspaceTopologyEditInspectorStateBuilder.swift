import RupaCore

struct WorkspaceTopologyEditInspectorStateBuilder {
    var selection: SelectionModel
    var selectedTargetSummary: String
    var faceOffsetStepMeters: Double
    var edgeChamferStepMeters: Double
    var edgeFilletRadiusMeters: Double
    var vertexMoveStepMeters: Double
    var usesLockedRegionDistance: Bool
    var combinesRegions: Bool

    func state(for nodes: [SceneNode]) -> WorkspaceTopologyEditInspectorState {
        let classification = targetClassification
        let faceTarget = singleTarget(in: classification.faceTargets)
        let faceTargets = classification.faceTargets
        let draftPair = draftFacePair(in: faceTargets)
        let edgeTargets = classification.edgeTargets
        let vertexTarget = singleTarget(in: classification.vertexTargets)
        let regionTargets = classification.regionTargets
        return WorkspaceTopologyEditInspectorState(
            isSingleNodeSelection: nodes.count == 1,
            selectedTargetSummary: selectedTargetSummary,
            faceTarget: faceTarget,
            faceTargets: faceTargets,
            draftFaceTargets: draftPair?.targets ?? [],
            draftNeutralFaceTarget: draftPair?.neutral,
            edgeTargets: edgeTargets,
            projectableEdgeTargets: generatedEdgeProjectionTargets(from: edgeTargets),
            vertexTarget: vertexTarget,
            regionTargets: regionTargets,
            faceOffsetStepMeters: faceOffsetStepMeters,
            edgeChamferStepMeters: edgeChamferStepMeters,
            edgeFilletRadiusMeters: edgeFilletRadiusMeters,
            vertexMoveStepMeters: vertexMoveStepMeters,
            usesLockedRegionDistance: usesLockedRegionDistance,
            combinesRegions: combinesRegions
        )
    }

    var faceTarget: SelectionTarget? {
        singleTarget(in: targetClassification.faceTargets)
    }

    var faceTargets: [SelectionTarget] {
        targetClassification.faceTargets
    }

    var edgeTargets: [SelectionTarget] {
        targetClassification.edgeTargets
    }

    var vertexTarget: SelectionTarget? {
        singleTarget(in: targetClassification.vertexTargets)
    }

    var vertexTargets: [SelectionTarget] {
        targetClassification.vertexTargets
    }

    var regionTargets: [SelectionTarget] {
        targetClassification.regionTargets
    }

    func generatedEdgeProjectionTargets(from targets: [SelectionTarget]) -> [SelectionTarget] {
        WorkspaceSelectionTargetClassification(targets: targets).generatedEdgeTargets
    }

    private var targetClassification: WorkspaceSelectionTargetClassification {
        WorkspaceSelectionTargetClassification(selection: selection)
    }

    private func singleTarget(in targets: [SelectionTarget]) -> SelectionTarget? {
        guard targets.count == 1 else {
            return nil
        }
        return targets.first
    }

    private func draftFacePair(
        in targets: [SelectionTarget]
    ) -> (targets: [SelectionTarget], neutral: SelectionTarget)? {
        guard selection.selectedTargets.count >= 2,
              targets.count == selection.selectedTargets.count,
              let neutral = targets.last else {
            return nil
        }
        let draftTargets = Array(targets.dropLast())
        guard draftTargets.isEmpty == false else {
            return nil
        }
        return (draftTargets, neutral)
    }
}
