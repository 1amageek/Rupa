import RupaKit

/// Slide's Control toggle: the project as it was when Slide started, drawn in place of the slid
/// result while Control is held, so the result can be compared with what it replaced. Releasing
/// Control or ending Slide returns to the current project.
struct WorkspaceSlideComparison {
    private(set) var baseline: ProjectViewSnapshot?
    private(set) var isControlHeld = false

    /// Slide started (the project before any slide is the baseline) or ended (no baseline).
    mutating func slideActivityChanged(isActive: Bool, current: ProjectViewSnapshot) {
        baseline = isActive ? current : nil
        if !isActive { isControlHeld = false }
    }

    mutating func controlChanged(isHeld: Bool) {
        isControlHeld = isHeld
    }

    /// Control is held while Slide runs: the viewport draws the baseline and takes no slide.
    var isComparing: Bool {
        isControlHeld && baseline != nil
    }

    /// The project the viewport draws.
    func displayed(_ current: ProjectViewSnapshot) -> ProjectViewSnapshot {
        isComparing ? baseline ?? current : current
    }
}
