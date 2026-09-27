import RupaCore

/// Cut Curve's dialog while it runs: the target curves, the cutters, which of the two a click on a
/// curve adds to or removes from, and Extend.
///
/// C starts it on the selected sketch curves: with several selected, the last one is the cutter
/// and the others are the targets; with one, it is the target and the clicks pick cutters. Return
/// or right-click cuts, Tab toggles Extend and Escape ends it.
struct WorkspaceCutCurveSession: Equatable {
    enum Role: Equatable {
        case targets
        case cutters
    }

    private(set) var targets: [SelectionTarget]
    private(set) var cutters: [SelectionTarget]
    /// Which list a clicked curve joins.
    var picking: Role
    /// Extend: a line or circle cutter reaches the targets along itself.
    var extendsCutter: Bool

    init(selectedCurves: [SelectionTarget], extendsCutter: Bool = false) {
        switch selectedCurves.count {
        case 0:
            targets = []
            cutters = []
            picking = .targets
        case 1:
            targets = selectedCurves
            cutters = []
            picking = .cutters
        default:
            targets = Array(selectedCurves.dropLast())
            cutters = [selectedCurves[selectedCurves.count - 1]]
            picking = .cutters
        }
        self.extendsCutter = extendsCutter
    }

    /// Whether both lists hold a curve, so the cut can run.
    var canCut: Bool {
        !targets.isEmpty && !cutters.isEmpty
    }

    /// Every curve the dialog holds, which the viewport shows selected.
    var curves: [SelectionTarget] {
        targets + cutters
    }

    var prompt: String {
        switch picking {
        case .targets: "Cut Curve: click the curves to cut, Return cuts, Tab extends the cutter."
        case .cutters: "Cut Curve: click the cutting curves, Return cuts, Tab extends the cutter."
        }
    }

    /// A clicked curve joins the list being picked, or leaves it when it is already there; a curve
    /// is never both a target and a cutter.
    mutating func toggle(_ curve: SelectionTarget) {
        switch picking {
        case .targets:
            if let index = targets.firstIndex(of: curve) {
                targets.remove(at: index)
            } else {
                cutters.removeAll { $0 == curve }
                targets.append(curve)
            }
        case .cutters:
            if let index = cutters.firstIndex(of: curve) {
                cutters.remove(at: index)
            } else {
                targets.removeAll { $0 == curve }
                cutters.append(curve)
            }
        }
    }
}
