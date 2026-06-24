import Foundation
import SwiftCAD

public struct EvaluationScheduler: Sendable {
    private let evaluatorOverride: DocumentEvaluator?

    public init(evaluator: DocumentEvaluator? = nil) {
        self.evaluatorOverride = evaluator
    }

    public func evaluate(
        document: DesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> EvaluationSnapshot {
        evaluateResult(
            document: document,
            generation: generation,
            objectRegistry: objectRegistry
        ).snapshot
    }

    public func evaluateResult(
        document: DesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> DocumentEvaluationResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            return DocumentEvaluationResult(
                snapshot: failedSnapshot(
                    message: String(describing: error),
                    generation: generation
                )
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return DocumentEvaluationResult(
                snapshot: evaluatedEmptyDocument(generation: generation)
            )
        }

        let evaluator = evaluatorOverride ?? .modelingDefault(
            for: document,
            objectRegistry: objectRegistry
        )
        let report = evaluator.evaluateReport(document.cadDocument)
        guard report.isComplete, let evaluatedDocument = report.evaluatedDocument else {
            let message = report.failure?.message ?? "Document evaluation did not complete."
            return DocumentEvaluationResult(
                snapshot: failedSnapshot(
                    message: message,
                    generation: generation
                )
            )
        }

        return DocumentEvaluationResult(
            snapshot: EvaluationSnapshot(
                status: .valid,
                evaluatedGeneration: generation,
                renderInvalidation: RenderInvalidation(
                    generation: generation,
                    reason: .evaluated
                ),
                bodyCount: evaluatedDocument.meshes.count,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Evaluation completed with \(evaluatedDocument.meshes.count) generated bodies."
                    ),
                ]
            ),
            evaluatedDocument: evaluatedDocument
        )
    }

    private func evaluatedEmptyDocument(
        generation: DocumentGeneration
    ) -> EvaluationSnapshot {
        EvaluationSnapshot(
            status: .valid,
            evaluatedGeneration: generation,
            renderInvalidation: RenderInvalidation(
                generation: generation,
                reason: .evaluated
            ),
            bodyCount: 0,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Document source is valid. No generated bodies."
                ),
            ]
        )
    }

    private func failedSnapshot(
        message: String,
        generation: DocumentGeneration
    ) -> EvaluationSnapshot {
        EvaluationSnapshot(
            status: .failed(message: message),
            evaluatedGeneration: generation,
            renderInvalidation: RenderInvalidation(
                generation: generation,
                reason: .evaluationFailed
            ),
            bodyCount: 0,
            diagnostics: [
                EditorDiagnostic(
                    severity: .error,
                    message: message
                ),
            ]
        )
    }
}
