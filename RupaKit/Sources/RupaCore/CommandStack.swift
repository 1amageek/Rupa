import Foundation
import Observation
import RupaCoreTypes

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
    @ObservationIgnored private var groupedExecution: GroupedExecutionState?

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

    public func snapshot() -> CommandStackSnapshot {
        CommandStackSnapshot(
            undoEntries: undoEntries,
            redoEntries: redoEntries
        )
    }

    public func restore(_ snapshot: CommandStackSnapshot) {
        undoEntries = snapshot.undoEntries
        redoEntries = snapshot.redoEntries
    }

    func collapseUndoEntries(
        startingAt startIndex: Int,
        commandName: String
    ) {
        guard undoEntries.indices.contains(startIndex) else {
            return
        }
        let groupedEntries = undoEntries[startIndex...]
        guard let firstEntry = groupedEntries.first,
              let lastEntry = groupedEntries.last else {
            return
        }
        if groupedEntries.count == 1 {
            undoEntries[startIndex].commandName = commandName
            return
        }
        undoEntries.replaceSubrange(
            startIndex...,
            with: [
                CommandHistoryEntry(
                    commandName: commandName,
                    before: firstEntry.before,
                    after: lastEntry.after
                ),
            ]
        )
    }

    public func markCurrentStateClean() {
        for index in undoEntries.indices {
            undoEntries[index].before.isDirty = true
            undoEntries[index].after.isDirty = true
        }
        for index in redoEntries.indices {
            redoEntries[index].before.isDirty = true
            redoEntries[index].after.isDirty = true
        }

        if let currentEntryIndex = undoEntries.indices.last {
            undoEntries[currentEntryIndex].after.isDirty = false
        }
        if let currentEntryIndex = redoEntries.indices.last {
            redoEntries[currentEntryIndex].before.isDirty = false
        }
    }

    func appendCommittedEntry(
        commandName: String,
        before: DocumentSnapshot,
        after: DocumentSnapshot
    ) {
        undoEntries.append(
            CommandHistoryEntry(
                commandName: commandName,
                before: before,
                after: after
            )
        )
        redoEntries.removeAll()
    }

    @discardableResult
    public func execute(
        _ command: EditorCommand,
        in store: CADDocumentStore,
        expectedGeneration: DocumentGeneration? = nil
    ) throws -> CommandExecutionResult {
        try store.requireGeneration(expectedGeneration)
        if groupedExecution != nil {
            let result = try store.apply(command)
            if result.didMutate {
                groupedExecution?.didMutate = true
            }
            return result
        }
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

    package func withGroupedExecution<Value>(
        commandName: String,
        in store: CADDocumentStore,
        _ operation: () throws -> Value
    ) throws -> Value {
        guard groupedExecution == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Source command groups cannot be nested."
            )
        }
        guard !commandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Source command group names must not be empty."
            )
        }

        let storeSnapshot = store.transactionSnapshot()
        let historySnapshot = snapshot()
        groupedExecution = GroupedExecutionState()
        do {
            let value = try store.withDeferredEvaluation(operation)
            let completedGroup = groupedExecution
            groupedExecution = nil
            let generationChanged = store.generation != storeSnapshot.document.generation
            if completedGroup?.didMutate == true {
                guard generationChanged else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "A source command reported a mutation without advancing the document generation."
                    )
                }
                guard store.evaluatedGeneration == store.generation else {
                    throw EditorError(
                        code: .evaluationFailed,
                        message: "Source command group evaluation did not reach the proposed generation."
                    )
                }
                switch store.evaluationStatus {
                case .valid:
                    break
                case .failed(let message):
                    throw EditorError(code: .evaluationFailed, message: message)
                case .notEvaluated:
                    throw EditorError(
                        code: .evaluationFailed,
                        message: "Source command group did not produce an evaluated document."
                    )
                }
                undoEntries.append(
                    CommandHistoryEntry(
                        commandName: commandName,
                        before: storeSnapshot.document,
                        after: store.snapshot()
                    )
                )
                redoEntries.removeAll()
            } else if generationChanged {
                throw EditorError(
                    code: .commandFailed,
                    message: "A source command advanced the document generation without reporting a mutation."
                )
            }
            return value
        } catch {
            groupedExecution = nil
            store.restoreTransactionSnapshot(storeSnapshot)
            restore(historySnapshot)
            throw error
        }
    }

    @discardableResult
    public func undo(in store: CADDocumentStore) throws -> CommandExecutionResult {
        guard let entry = undoEntries.popLast() else {
            throw EditorError(
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
            throw EditorError(
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

private struct GroupedExecutionState {
    var didMutate = false
}
