import RupaCore

struct SketchCurveJoinInspectorState {
    var entityKind: String
    var sourceFeatureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var joinedCurveSourceID: JoinedCurveSourceID?
    var joinedCurveGroupSourceID: JoinedCurveGroupSourceID?
    var selectedTargets: [SelectionTarget]
    var entityKindsByTarget: [SelectionTarget: String]

    var joinAdjacentTarget: SelectionTarget? {
        guard ["line", "arc"].contains(entityKind) else {
            return nil
        }
        return selectedTargets.first { candidate in
            guard candidate != target,
                  let candidateKind = entityKindsByTarget[candidate],
                  ["line", "arc"].contains(candidateKind),
                  case .sketchEntity(let componentID) = candidate.component,
                  let reference = componentID.sketchEntityBaseReference,
                  reference.featureID == sourceFeatureID,
                  reference.entityID != entityID else {
                return false
            }
            return true
        }
    }

    var canJoin: Bool {
        joinAdjacentTarget != nil
    }

    var canUnjoin: Bool {
        (entityKind == "line" && joinedCurveSourceID != nil) ||
            (["line", "arc"].contains(entityKind) && joinedCurveGroupSourceID != nil)
    }
}
