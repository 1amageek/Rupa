import Foundation
import Observation

public struct CommandHistoryEntry: Sendable {
    public var commandName: String
    public var before: DocumentSnapshot
    public var after: DocumentSnapshot

    public init(
        commandName: String,
        before: DocumentSnapshot,
        after: DocumentSnapshot
    ) {
        self.commandName = commandName
        self.before = before
        self.after = after
    }
}

@Observable
public final class CommandStack {
    public private(set) var undoEntries: [CommandHistoryEntry]
    public private(set) var redoEntries: [CommandHistoryEntry]

    public init(
        undoEntries: [CommandHistoryEntry] = [],
        redoEntries: [CommandHistoryEntry] = []
    ) {
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
    }

    public var canUndo: Bool {
        !undoEntries.isEmpty
    }

    public var canRedo: Bool {
        !redoEntries.isEmpty
    }

    @discardableResult
    public func execute(
        _ command: EditorCommand,
        in store: CADDocumentStore,
        expectedGeneration: DocumentGeneration? = nil
    ) throws -> CommandExecutionResult {
        try store.requireGeneration(expectedGeneration)
        let before = store.snapshot()
        let result = try store.apply(command)
        let after = store.snapshot()

        if result.didMutate {
            undoEntries.append(
                CommandHistoryEntry(
                    commandName: command.name,
                    before: before,
                    after: after
                )
            )
            redoEntries.removeAll()
        }

        return result
    }

    @discardableResult
    public func undo(in store: CADDocumentStore) throws -> CommandExecutionResult {
        guard let entry = undoEntries.popLast() else {
            throw RupaError(
                code: .commandInvalid,
                message: "There is no command to undo."
            )
        }
        try store.restoreAsMutation(entry.before)
        store.evaluateCurrentDocument()
        redoEntries.append(entry)
        return CommandExecutionResult(
            commandName: "undo.\(entry.commandName)",
            generation: store.generation,
            didMutate: true,
            diagnostics: store.diagnostics
        )
    }

    @discardableResult
    public func redo(in store: CADDocumentStore) throws -> CommandExecutionResult {
        guard let entry = redoEntries.popLast() else {
            throw RupaError(
                code: .commandInvalid,
                message: "There is no command to redo."
            )
        }
        try store.restoreAsMutation(entry.after)
        store.evaluateCurrentDocument()
        undoEntries.append(entry)
        return CommandExecutionResult(
            commandName: "redo.\(entry.commandName)",
            generation: store.generation,
            didMutate: true,
            diagnostics: store.diagnostics
        )
    }
}
