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
        let edgeTargets = edgeTargets
        return WorkspaceTopologyEditInspectorState(
            isSingleNodeSelection: nodes.count == 1,
            selectedTargetSummary: selectedTargetSummary,
            faceTarget: faceTarget,
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
        let targets = faceTargets
        guard targets.count == 1 else {
            return nil
        }
        return targets.first
    }

    var faceTargets: [SelectionTarget] {
        selection.selectedTargets.filter { target in
            if case .face = target.component {
                return true
            }
            return false
        }
    }

    var edgeTargets: [SelectionTarget] {
        selection.selectedTargets.filter { target in
            if case .edge = target.component {
                return true
            }
            return false
        }
    }

    var vertexTarget: SelectionTarget? {
        let targets = vertexTargets
        guard targets.count == 1, let target = targets.first else {
            return nil
        }
        return target
    }

    var vertexTargets: [SelectionTarget] {
        selection.selectedTargets.filter { target in
            if case .vertex = target.component {
                return true
            }
            return false
        }
    }

    var regionTargets: [SelectionTarget] {
        selection.selectedTargets.filter { target in
            if case .region = target.component {
                return true
            }
            return false
        }
    }

    func generatedEdgeProjectionTargets(from targets: [SelectionTarget]) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in targets {
            guard case .edge(let componentID) = target.component,
                  componentID.generatedTopologyPersistentName != nil else {
                continue
            }
            let key = "\(target.sceneNodeID.description):\(String(describing: target.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(target)
            }
        }
        return projectedTargets
    }
}
