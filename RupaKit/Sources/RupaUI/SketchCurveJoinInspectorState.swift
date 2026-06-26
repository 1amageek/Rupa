import RupaCore

struct SketchCurveJoinInspectorState {
    var entityKind: String
    var sourceFeatureID: FeatureID
    var entityID: SketchEntityID
    var target: SelectionTarget
    var joinedCurveSourceID: JoinedCurveSourceID?
    var selectedTargets: [SelectionTarget]
    var entityKindsByTarget: [SelectionTarget: String]

    var joinAdjacentTarget: SelectionTarget? {
        guard entityKind == "line" else {
            return nil
        }
        return selectedTargets.first { candidate in
            guard candidate != target,
                  entityKindsByTarget[candidate] == "line",
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
        entityKind == "line" && joinedCurveSourceID != nil
    }
}
