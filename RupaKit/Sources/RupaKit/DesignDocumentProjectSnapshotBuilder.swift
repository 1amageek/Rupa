import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaViewportScene

public struct DesignDocumentProjectSnapshotBuilder: Sendable {
    private let bridge: DesignDocumentProjectBridge
    private let evaluatorFactory: any DesignDocumentProjectEvaluatorFactory

    public init(
        bridge: DesignDocumentProjectBridge = DesignDocumentProjectBridge(),
        evaluatorFactory: any DesignDocumentProjectEvaluatorFactory =
            DefaultDesignDocumentProjectEvaluatorFactory()
    ) {
        self.bridge = bridge
        self.evaluatorFactory = evaluatorFactory
    }

    /// Builds one coherent source, evaluation, and viewport snapshot.
    ///
    /// Pass the matching current evaluation to avoid evaluating the CAD source
    /// again during migration. A stale evaluation is rejected explicitly.
    public func build(
        document: DesignDocument,
        generation: DocumentGeneration,
        currentEvaluation: DocumentEvaluationContext?
    ) async throws -> DesignDocumentProjectSnapshot {
        if let currentEvaluation,
           !currentEvaluation.matches(document: document, generation: generation) {
            throw DesignDocumentProjectBridgeError(
                code: .staleEvaluation,
                message: "The reusable CAD evaluation does not match the requested document generation."
            )
        }
        let bridge = self.bridge
        let evaluatorFactory = self.evaluatorFactory
        return try await Task.detached(priority: nil) {
            try Task.checkCancellation()
            let source = try bridge.sourceModel(for: document)
            let sourceRevision = DocumentTransactionRevision(generation.value)
            let evaluation = try evaluatorFactory.makeEvaluator(
                for: document,
                reusing: currentEvaluation
            ).evaluate(
                project: source,
                purpose: .presentation,
                revision: sourceRevision
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
