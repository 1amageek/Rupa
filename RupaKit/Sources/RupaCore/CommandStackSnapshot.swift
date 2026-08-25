public struct CommandStackSnapshot: Sendable {
    public var undoEntries: [CommandHistoryEntry]
    public var redoEntries: [CommandHistoryEntry]
    let mutationToken: CommandStackMutationToken

    public init(
        undoEntries: [CommandHistoryEntry],
        redoEntries: [CommandHistoryEntry]
    ) {
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
        self.mutationToken = CommandStackMutationToken()
    }

    init(
        undoEntries: [CommandHistoryEntry],
        redoEntries: [CommandHistoryEntry],
        mutationToken: CommandStackMutationToken
    ) {
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
        self.mutationToken = mutationToken
    }
}

final class CommandStackMutationToken: Sendable {}
