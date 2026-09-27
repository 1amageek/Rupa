import RupaCore

struct WorkspaceSketchCurveOperationControlsState: Equatable {
    var canExtend: Bool
    var canOffsetVertex: Bool
    var canApplyCornerTreatment: Bool
    var canJoin: Bool
    var canUnjoin: Bool
    var canAlignVertex: Bool
    var canProject: Bool
    /// The Extend shapes Core builds on the selected curve's kind (`ExtendCurveShape.supported`).
    var extendShapes: [ExtendCurveShape] = []

    /// The chosen Extend shape when the curve takes it, and otherwise the first one it takes.
    func effectiveExtendShape(_ chosen: ExtendCurveShape) -> ExtendCurveShape? {
        extendShapes.contains(chosen) ? chosen : extendShapes.first
    }
}

enum WorkspaceSketchCurveOperationControl: Hashable {
    case projection
    case alignment
    case vertexOffset
    case cornerTreatment
    case extend
    case join
}
