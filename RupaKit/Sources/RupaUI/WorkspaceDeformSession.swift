import RupaCore

/// Deform's dialog while it runs, on what was selected when it started: sketch curves (Deform
/// Curve) or body objects (Deform Solid and Sheet), never both. A click picks the reference face
/// (where the curves or bodies lie), the next the target face, and a later click replaces the
/// target. OK, Return or right-click deforms once both are picked; Escape ends it without a change.
struct WorkspaceDeformSession: Equatable {
    enum Subject: Equatable {
        case curves([SelectionTarget])
        case bodies([SceneNodeID])
    }

    enum Step: Equatable {
        case referenceFace
        case targetFace
        case options
    }

    let subject: Subject
    private(set) var referenceFace: SelectionTarget?
    private(set) var targetFace: SelectionTarget?
    var options: CurveDeformationOptions
    /// N offset in meters; the dialog's length field.
    var offsetNMeters: Double

    /// The dialog for the selected curves or bodies, or nil when neither or both are selected.
    init?(
        selectedCurves: [SelectionTarget],
        selectedBodies: [SceneNodeID] = [],
        options: CurveDeformationOptions = CurveDeformationOptions()
    ) {
        switch (selectedCurves.isEmpty, selectedBodies.isEmpty) {
        case (false, true): subject = .curves(selectedCurves)
        case (true, false): subject = .bodies(selectedBodies)
        default: return nil
        }
        self.options = options
        offsetNMeters = 0
    }

    /// What was deformed, for the status line.
    var subjectDescription: String {
        switch subject {
        case .curves(let curves): "\(curves.count) curve\(curves.count == 1 ? "" : "s")"
        case .bodies(let bodies): "\(bodies.count) bod\(bodies.count == 1 ? "y" : "ies")"
        }
    }

    var step: Step {
        if referenceFace == nil { return .referenceFace }
        if targetFace == nil { return .targetFace }
        return .options
    }

    var prompt: String {
        switch step {
        case .referenceFace:
            switch subject {
            case .curves: "Deform: click the reference face the curves lie on."
            case .bodies: "Deform: click the reference face the bodies lie on."
            }
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
        switch subject {
        case .curves(let curves):
            return .deformCurves(targets: curves, referenceFace: referenceFace, targetFace: targetFace, options: resolved)
        case .bodies(let bodies):
            return .deformBodies(targets: bodies, referenceFace: referenceFace, targetFace: targetFace, options: resolved)
        }
    }
}
