import RupaCore

struct WorkspaceTopologyEditInspectorState: Equatable {
    var isSingleNodeSelection: Bool
    var selectedTargetSummary: String
    var faceTarget: SelectionTarget?
    var edgeTargets: [SelectionTarget]
    var projectableEdgeTargets: [SelectionTarget]
    var vertexTarget: SelectionTarget?
    var regionTargets: [SelectionTarget]
    var faceOffsetStepMeters: Double
    var edgeChamferStepMeters: Double
    var edgeFilletRadiusMeters: Double
    var vertexMoveStepMeters: Double
    var usesLockedRegionDistance: Bool
    var combinesRegions: Bool

    var canEditFace: Bool {
        isSingleNodeSelection && faceTarget != nil
    }

    var canEditEdges: Bool {
        isSingleNodeSelection && edgeTargets.isEmpty == false
    }

    var canEditVertex: Bool {
        isSingleNodeSelection && vertexTarget != nil
    }

    var canEditRegions: Bool {
        regionTargets.isEmpty == false
    }

    var regionTargetSummary: String {
        regionTargets.count == 1 ? selectedTargetSummary : "\(regionTargets.count)"
    }
}
