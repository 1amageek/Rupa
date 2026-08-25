import SwiftCAD
import RupaCoreTypes

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
            let pipeline = pipelineOverride ?? .modelingDefault(
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
            let evaluator = exactEvaluatorOverride ?? DocumentEvaluator.modelingDefault(
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
