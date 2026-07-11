import RupaAutomation
import RupaCore

public struct CLIBatchResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var workspaceRevision: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var commandCount: Int
    public var didMutate: Bool
    public var results: [AutomationResult]
    public var diagnostics: [EditorDiagnostic]
    public var metrics: AutomationBatchMetrics

    public init(
        results: [AutomationResult],
        generation: DocumentGeneration,
        workspaceRevision: WorkspaceRevision,
        dirty: Bool,
        saved: Bool,
        metrics: AutomationBatchMetrics
    ) {
        self.results = results
        self.generation = generation.value
        self.workspaceRevision = workspaceRevision.value
        self.dirty = dirty
        self.saved = saved
        self.metrics = metrics
        self.commandCount = results.count
        self.didMutate = results.contains { $0.didMutate }
        // Specialized command diagnostics remain in their result. Aggregate
        // workspace diagnostics belong to the final result, so this top-level
        // union deduplicates by content while preserving first-seen order.
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
