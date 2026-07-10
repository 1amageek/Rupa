public struct EditorSessionTransactionSnapshot: Sendable {
    public var store: CADDocumentStoreTransactionSnapshot
    public var commandStack: CommandStackSnapshot
    public var selection: SelectionModel
    public var workspaceState: WorkspaceState

    public init(
        store: CADDocumentStoreTransactionSnapshot,
        commandStack: CommandStackSnapshot,
        selection: SelectionModel,
        workspaceState: WorkspaceState
    ) {
        self.store = store
        self.commandStack = commandStack
        self.selection = selection
        self.workspaceState = workspaceState
    }
}
