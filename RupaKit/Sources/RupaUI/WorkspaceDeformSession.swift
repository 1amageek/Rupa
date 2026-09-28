import RupaCore

/// Deform Curve's dialog while it runs, on the sketch curves selected when it started: a click
/// picks the reference face (where the curves lie), the next the target face, and a later click
/// replaces the target. OK, Return or right-click deforms once both are picked; Escape ends it
/// without a change.
struct WorkspaceDeformSession: Equatable {
    enum Step: Equatable {
        case referenceFace
        case targetFace
        case options
    }

    let curves: [SelectionTarget]
    private(set) var referenceFace: SelectionTarget?
    private(set) var targetFace: SelectionTarget?
    var options: CurveDeformationOptions
    /// N offset in meters; the dialog's length field.
    var offsetNMeters: Double

    /// The dialog for the selected curves, or nil when none is selected.
    init?(selectedCurves: [SelectionTarget], options: CurveDeformationOptions = CurveDeformationOptions()) {
        guard !selectedCurves.isEmpty else { return nil }
        curves = selectedCurves
        self.options = options
        offsetNMeters = 0
    }

    var step: Step {
        if referenceFace == nil { return .referenceFace }
        if targetFace == nil { return .targetFace }
        return .options
    }

    var prompt: String {
        switch step {
        case .referenceFace: "Deform: click the reference face the curves lie on."
        case .targetFace: "Deform: click the target face."
        case .options: "Deform: set the values, then OK, Return or right-click."
        }
    }

    mutating func pick(face: SelectionTarget) {
        if referenceFace == nil {
            referenceFace = face
        } else {
            targetFace = face
        }
    }

    /// The command OK submits, nil until both faces are picked.
    var command: EditorCommand? {
        guard let referenceFace, let targetFace else { return nil }
        var resolved = options
        resolved.offsetN = .length(offsetNMeters, .meter)
        return .deformCurves(targets: curves, referenceFace: referenceFace, targetFace: targetFace, options: resolved)
    }
}
