import RupaCore

struct WorkspaceProjectionTargetResolver {
    var document: DesignDocument
    var selection: SelectionModel
    var displayUnit: LengthDisplayUnit
    var objectRegistry: ObjectTypeRegistry

    func sketchCurveProjectionTargets(for entity: InspectorSketchEntity) -> [SelectionTarget] {
        sketchEntityInspectorStateBuilder.curveProjectionTargets(for: entity)
    }

    func wholeSketchCurveTarget(for target: SelectionTarget) -> SelectionTarget? {
        sketchEntityInspectorStateBuilder.wholeCurveTarget(for: target)
    }

    func curveProjectionTargetsForGeneratedFace(
        excluding faceTarget: SelectionTarget
    ) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in selection.selectedTargets where target != faceTarget {
            let curveTarget: SelectionTarget?
            if let sketchCurveTarget = wholeSketchCurveTarget(for: target) {
                curveTarget = sketchCurveTarget
            } else if case .edge(let componentID) = target.component,
                      componentID.isStableTopology {
                curveTarget = target
            } else {
                curveTarget = nil
            }
            guard let curveTarget else {
                continue
            }
            append(curveTarget, to: &projectedTargets, seen: &seen)
        }
        return projectedTargets
    }

    func bodyOutlineProjectionTargets(from nodes: [SceneNode]) -> [SelectionTarget] {
        guard selection.selectedTargets.allSatisfy({ $0.component == .object }) else {
            return []
        }
        return nodes.compactMap { node in
            guard node.reference?.kind == .body else {
                return nil
            }
            return SelectionTarget(sceneNodeID: node.id)
        }
    }

    func generatedEdgeProjectionTargets(from targets: [SelectionTarget]) -> [SelectionTarget] {
        WorkspaceSelectionTargetClassification(targets: targets).generatedEdgeTargets
    }

    private var sketchEntityInspectorStateBuilder: WorkspaceSketchEntityInspectorStateBuilder {
        WorkspaceSketchEntityInspectorStateBuilder(
            document: document,
            selection: selection,
            displayUnit: displayUnit,
            objectRegistry: objectRegistry
        )
    }

    private func append(
        _ target: SelectionTarget,
        to targets: inout [SelectionTarget],
        seen: inout Set<String>
    ) {
        let key = "\(target.sceneNodeID.description):\(String(describing: target.component))"
        if seen.insert(key).inserted {
            targets.append(target)
        }
    }
}
