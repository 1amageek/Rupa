import Foundation

public struct RupaSaveResult: Codable, Equatable, Sendable {
    public var message: String
    public var path: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var diagnostics: [RupaDiagnostic]

    public init(
        message: String,
        path: String,
        generation: DocumentGeneration,
        dirty: Bool,
        diagnostics: [RupaDiagnostic]
    ) {
        self.message = message
        self.path = path
        self.generation = generation
        self.dirty = dirty
        self.diagnostics = diagnostics
    }
}
