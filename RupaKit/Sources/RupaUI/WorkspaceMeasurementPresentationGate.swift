import RupaCore

/// Decides which selected-object world-bounds presentations the current tool
/// shows. The spatial rulers reach the object with leaders and labels, so they
/// belong to the Measure tool alone and never compete with the affordances the
/// Select tool draws around the same selection. The text readout accompanies
/// every tool that can draw a ruler, which keeps the value of an axis the
/// frame refuses to place readable. `ViewportMeasurement/DESIGN.md` owns the
/// contract; the readout predicate stays a superset of the ruler predicate.
enum WorkspaceMeasurementPresentationGate {
    static func showsBoundsRulers(
        selectedTool: ModelingTool,
        hasOwningInteraction: Bool
    ) -> Bool {
        guard !hasOwningInteraction else { return false }
        return selectedTool == .measure
    }

    static func showsBoundsReadout(
        selectedTool: ModelingTool,
        selectionScope: WorkspaceSelectionScope,
        hasOwningInteraction: Bool
    ) -> Bool {
        guard !hasOwningInteraction else { return false }
        switch selectedTool {
        case .measure:
            return true
        case .select:
            // Sub-object scopes report the picked element instead, so the
            // whole-occurrence extents would describe something else.
            return selectionScope == .object
        default:
            // The remaining tools author geometry and own the context panel.
            return false
        }
    }
}
