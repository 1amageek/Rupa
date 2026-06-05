import Foundation
import RupaCore

public struct AutomationResult: Codable, Equatable, Sendable {
    public var message: String
    public var commandName: String?
    public var generation: DocumentGeneration
    public var didMutate: Bool
    public var diagnostics: [EditorDiagnostic]

    public init(
        message: String,
        commandName: String? = nil,
        generation: DocumentGeneration = DocumentGeneration(),
        didMutate: Bool = false,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.message = message
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
    }
}
