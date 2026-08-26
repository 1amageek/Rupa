import Foundation

/// Resolves command inputs that depend on one immutable editor snapshot.
public protocol EditorCommandContextResolving: Sendable {
    func resolve(
        _ command: EditorCommand,
        in context: EditorCommandPlanningContext
    ) throws -> EditorCommand

    func resolve(
        _ commands: [EditorCommand],
        in context: EditorCommandPlanningContext
    ) throws -> [EditorCommand]

    func requireFullyResolved(_ command: EditorCommand) throws

    func requireFullyResolved(_ commands: [EditorCommand]) throws
}

public extension EditorCommandContextResolving {
    func resolve(
        _ commands: [EditorCommand],
        in context: EditorCommandPlanningContext
    ) throws -> [EditorCommand] {
        try commands.map { command in
            try resolve(command, in: context)
        }
    }

    func requireFullyResolved(_ commands: [EditorCommand]) throws {
        for command in commands {
            try requireFullyResolved(command)
        }
    }
}
