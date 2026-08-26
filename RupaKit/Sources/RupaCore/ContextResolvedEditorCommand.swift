import Foundation

/// An editor command whose snapshot-dependent inputs are explicit and immutable.
public struct ContextResolvedEditorCommand: Equatable, Sendable {
    public let command: EditorCommand

    public init(
        resolving command: EditorCommand,
        in context: EditorCommandPlanningContext,
        using resolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver()
    ) throws {
        let resolved = try resolver.resolve(command, in: context)
        try resolver.requireFullyResolved(resolved)
        self.command = resolved
    }

    public init(
        validating command: EditorCommand,
        using resolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver()
    ) throws {
        try resolver.requireFullyResolved(command)
        self.command = command
    }
}
