import SwiftCAD
import RupaCoreTypes

/// The evaluated form of a document for a command or query.
///
/// A current evaluation that describes the document (same generation and source identity) is
/// returned as it is. One that no longer does, because the command already changed the document,
/// seeds the kernel's incremental evaluation, so only what changed is evaluated again; this is the
/// same materialized evaluation the store accepts as exact when it matches. Without a current
/// evaluation, or with an injected evaluator, the document is evaluated from scratch.
public struct DocumentEvaluationContextResolver: Sendable {
    private let pipelineOverride: CADPipeline?
    private let exactEvaluatorOverride: (any ExactDocumentEvaluating)?

    public init(
        pipeline: CADPipeline? = nil,
        exactEvaluator: (any ExactDocumentEvaluating)? = nil
    ) {
        self.pipelineOverride = pipeline
        self.exactEvaluatorOverride = exactEvaluator
    }

    public func evaluatedDocument(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil,
        failurePrefix: String
    ) throws -> EvaluatedDocument {
        if let current = matchingCurrentEvaluation(
            document: document,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        ) {
            return current
        }

        do {
            if pipelineOverride == nil, let base = currentEvaluation?.evaluatedDocument {
                DocumentWorkProbe.current?.recordIncrementalEvaluation()
                return try DocumentEvaluator.modelingDefault(for: document, objectRegistry: objectRegistry)
                    .evaluate(document.cadDocument, reusing: base)
            }
            DocumentWorkProbe.current?.recordEvaluationFromScratch()
            let pipeline = try pipelineOverride ?? .modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
            return try pipeline.evaluate(document.cadDocument)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "\(failurePrefix): \(String(describing: error))"
            )
        }
    }

    public func exactEvaluatedDocument(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil,
        failurePrefix: String
    ) throws -> EvaluatedDocument {
        if let current = matchingCurrentEvaluation(
            document: document,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        ) {
            return current
        }

        do {
            if exactEvaluatorOverride == nil, let base = currentEvaluation?.evaluatedDocument {
                DocumentWorkProbe.current?.recordIncrementalEvaluation()
                return try DocumentEvaluator.modelingDefault(for: document, objectRegistry: objectRegistry)
                    .evaluate(document.cadDocument, reusing: base)
            }
            DocumentWorkProbe.current?.recordEvaluationFromScratch()
            let evaluator = try exactEvaluatorOverride ?? DocumentEvaluator.modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
            return try evaluator.evaluateExact(document.cadDocument)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "\(failurePrefix): \(String(describing: error))"
            )
        }
    }

    private func matchingCurrentEvaluation(
        document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) -> EvaluatedDocument? {
        guard let currentEvaluation,
              currentEvaluation.matches(
                document: document,
                generation: currentGeneration
              ) else {
            return nil
        }
        return currentEvaluation.evaluatedDocument
    }
}
