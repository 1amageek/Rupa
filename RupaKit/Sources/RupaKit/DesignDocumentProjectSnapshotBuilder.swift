import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaViewportScene

public struct DesignDocumentProjectSnapshotBuilder: Sendable {
    private let bridge: DesignDocumentProjectBridge

    public init(bridge: DesignDocumentProjectBridge = DesignDocumentProjectBridge()) {
        self.bridge = bridge
    }

    public func build(
        document: DesignDocument,
        generation: DocumentGeneration
    ) async throws -> DesignDocumentProjectSnapshot {
        let bridge = self.bridge
        return try await Task.detached(priority: nil) {
            try Task.checkCancellation()
            let source = try bridge.sourceModel(for: document)
            let sourceRevision = DocumentTransactionRevision(generation.value)
            let evaluation = try bridge.evaluationEngine(for: document).evaluate(
                source,
                sourceRevision: sourceRevision
            )
            let viewport = try UniversalViewportSceneBuilder().build(
                from: evaluation,
                project: source
            )
            try Task.checkCancellation()
            return DesignDocumentProjectSnapshot(
                documentGeneration: generation,
                sourceRevision: sourceRevision,
                source: source,
                evaluation: evaluation,
                viewport: viewport
            )
        }.value
    }
}
