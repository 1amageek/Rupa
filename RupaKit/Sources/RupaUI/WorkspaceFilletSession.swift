import RupaCore

/// Fillet's dialog while it runs, on the sketch curves or curve ends selected when B started it:
/// D types the distance, C switches between Fillet and Chamfer, Return or right-click applies it
/// and Escape ends it without a change.
struct WorkspaceFilletSession: Equatable {
    /// What the treatment takes: curve ends (Fillet Vertex, every corner once) or two curves
    /// (Fillet Curve, at the corner they share).
    enum Targets: Equatable {
        case vertices([SelectionTarget])
        case curves(SelectionTarget, adjacent: SelectionTarget?)
    }

    let targets: Targets
    var treatment: SketchCornerTreatment

    /// The dialog for the selection, or nil when it holds no sketch curve or curve end: ends take
    /// precedence, since a corner is where they meet.
    init?(selectedSketchTargets: [SelectionTarget], treatment: SketchCornerTreatment) {
        let vertices = selectedSketchTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchPointHandleReference != nil
        }
        let curves = selectedSketchTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchEntityReference != nil
        }
        if !vertices.isEmpty {
            targets = .vertices(vertices)
        } else if let first = curves.first {
            targets = .curves(first, adjacent: curves.count > 1 ? curves[1] : nil)
        } else {
            return nil
        }
        self.treatment = treatment
    }

    var title: String {
        treatment == .fillet ? "Fillet" : "Chamfer"
    }

    /// C: Fillet ↔ Chamfer.
    mutating func toggleTreatment() {
        treatment = treatment == .fillet ? .chamfer : .fillet
    }
}
