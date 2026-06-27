import Foundation

public struct SaveResult: Codable, Equatable, Sendable {
    public var message: String
    public var path: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var diagnostics: [EditorDiagnostic]

    public init(
        message: String,
        path: String,
        generation: DocumentGeneration,
        dirty: Bool,
        diagnostics: [EditorDiagnostic]
    ) {
        self.message = message
        self.path = path
        self.generation = generation
        self.dirty = dirty
        self.diagnostics = diagnostics
    }
}
