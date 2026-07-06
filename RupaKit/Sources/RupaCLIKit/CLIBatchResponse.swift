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
        // Per-command diagnostics are authoritative in `results[]`. This top-level
        // aggregate is a deduplicated union: document/workspace-level diagnostics
        // (precision, scale recommendations) repeat across commands with distinct
        // ids but identical content, so dedupe by (severity, code, message) while
        // preserving first-seen order.
        var seenDiagnosticKeys: Set<String> = []
        var dedupedDiagnostics: [EditorDiagnostic] = []
        for result in results {
            for diagnostic in result.diagnostics {
                let key = "\(diagnostic.severity.rawValue)|\(diagnostic.code?.rawValue ?? "")|\(diagnostic.message)"
                if seenDiagnosticKeys.insert(key).inserted {
                    dedupedDiagnostics.append(diagnostic)
                }
            }
        }
        self.diagnostics = dedupedDiagnostics
        self.message = "Applied \(results.count) automation command\(results.count == 1 ? "" : "s")."
    }
}
