import Foundation

public struct CommandExecutionResult: Equatable, Sendable {
    public var commandName: String
    public var generation: DocumentGeneration
    public var didMutate: Bool
    public var diagnostics: [RupaDiagnostic]

    public init(
        commandName: String,
        generation: DocumentGeneration,
        didMutate: Bool,
        diagnostics: [RupaDiagnostic]
    ) {
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
    }
}
