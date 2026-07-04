struct WorkspaceTopBarPresentation: Equatable, Sendable {
    var selectedTargetCount: Int

    init(selectedTargetCount: Int) {
        self.selectedTargetCount = max(0, selectedTargetCount)
    }

    var showsSelectionCount: Bool {
        selectedTargetCount > 0
    }

    var selectionTitle: String? {
        guard showsSelectionCount else {
            return nil
        }
        return "\(selectedTargetCount) selected"
    }
}
