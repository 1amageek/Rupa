struct WorkspaceTopBarPresentation: Equatable, Sendable {
    var selectedTargetCount: Int
    var selectionScope: WorkspaceSelectionScope

    init(selectedTargetCount: Int, selectionScope: WorkspaceSelectionScope) {
        self.selectedTargetCount = max(0, selectedTargetCount)
        self.selectionScope = selectionScope
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

    /// The scope is a mode that changes what every click selects, and the digit
    /// keys change it without touching the rail that shows it. Naming it beside
    /// the selection count makes a scope changed by key visible where the user
    /// is already looking.
    var selectionScopeTitle: String {
        selectionScope.title
    }

    var selectionScopeSystemImage: String {
        selectionScope.systemImage
    }
}
