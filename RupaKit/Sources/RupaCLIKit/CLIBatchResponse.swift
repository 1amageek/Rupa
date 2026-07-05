import RupaAutomation
import RupaCore

public struct CLIBatchResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var commandCount: Int
    public var didMutate: Bool
    public var results: [AutomationResult]
    public var diagnostics: [EditorDiagnostic]

    public init(
        results: [AutomationResult],
        generation: DocumentGeneration,
        dirty: Bool,
        saved: Bool
    ) {
        self.results = results
        self.generation = generation.value
        self.dirty = dirty
        self.saved = saved
        self.commandCount = results.count
        self.didMutate = results.contains { $0.didMutate }
        self.diagnostics = results.flatMap { $0.diagnostics }
        self.message = "Applied \(results.count) automation command\(results.count == 1 ? "" : "s")."
    }
}
