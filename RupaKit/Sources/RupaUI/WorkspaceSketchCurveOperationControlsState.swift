struct WorkspaceSketchCurveOperationControlsState: Equatable {
    var canExtend: Bool
    var canOffsetVertex: Bool
    var canApplyCornerTreatment: Bool
    var canJoin: Bool
    var canUnjoin: Bool
    var canAlignVertex: Bool
    var canProject: Bool
}

enum WorkspaceSketchCurveOperationControl: Hashable {
    case projection
    case alignment
    case vertexOffset
    case cornerTreatment
    case extend
    case join
}
