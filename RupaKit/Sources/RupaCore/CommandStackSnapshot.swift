public struct CommandStackSnapshot: Sendable {
    public var undoEntries: [CommandHistoryEntry]
    public var redoEntries: [CommandHistoryEntry]

    public init(
        undoEntries: [CommandHistoryEntry],
        redoEntries: [CommandHistoryEntry]
    ) {
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
    }
}
