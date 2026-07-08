public struct EditorSessionTransactionSnapshot: Sendable {
    public var store: CADDocumentStoreTransactionSnapshot
    public var commandStack: CommandStackSnapshot
    public var selection: SelectionModel

    public init(
        store: CADDocumentStoreTransactionSnapshot,
        commandStack: CommandStackSnapshot,
        selection: SelectionModel
    ) {
        self.store = store
        self.commandStack = commandStack
        self.selection = selection
    }
}
