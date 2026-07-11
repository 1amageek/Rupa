import Foundation
import SwiftCAD
import RupaCoreTypes

public struct EvaluationScheduler: Sendable {
    private let evaluatorOverride: DocumentEvaluator?

    public init(evaluator: DocumentEvaluator? = nil) {
        self.evaluatorOverride = evaluator
    }

    public func evaluate(
        document: DesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        reusing previous: EvaluatedDocument? = nil
    ) -> EvaluationSnapshot {
        evaluateResult(
            document: document,
            generation: generation,
            objectRegistry: objectRegistry,
            reusing: previous
        ).snapshot
    }

    public func evaluateResult(
        document: DesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        reusing previous: EvaluatedDocument? = nil
    ) -> DocumentEvaluationResult {
        let validatedDocument: ValidatedDesignDocument
        do {
            validatedDocument = try document.validate(objectRegistry: objectRegistry)
        } catch {
            return DocumentEvaluationResult(
                snapshot: failedSnapshot(
                    message: String(describing: error),
                    generation: generation
                )
            )
        }

        return evaluateResult(
            validatedDocument: validatedDocument,
            generation: generation,
            objectRegistry: objectRegistry,
            reusing: previous
        )
    }

    public func evaluateResult(
        validatedDocument: ValidatedDesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        reusing previous: EvaluatedDocument? = nil
    ) -> DocumentEvaluationResult {
        let document = validatedDocument.document

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return DocumentEvaluationResult(
                snapshot: evaluatedEmptyDocument(generation: generation)
            )
        }

        let evaluator = evaluatorOverride ?? .modelingDefault(
            for: document,
            objectRegistry: objectRegistry
        )
        let evaluatedDocument: EvaluatedDocument
        do {
            evaluatedDocument = try evaluator.evaluate(
                validatedDocument.validatedCADDocument,
                reusing: previous
            )
        } catch {
            return DocumentEvaluationResult(
                snapshot: failedSnapshot(
                    message: String(describing: error),
                    generation: generation
                )
            )
        }

        let diagnostics = [
            EditorDiagnostic(
                severity: .info,
                message: "Evaluation completed with \(evaluatedDocument.meshes.count) generated bodies."
            ),
        ]

        return DocumentEvaluationResult(
            snapshot: EvaluationSnapshot(
                status: .valid,
                evaluatedGeneration: generation,
                renderInvalidation: RenderInvalidation(
                    generation: generation,
                    reason: .evaluated
                ),
                bodyCount: evaluatedDocument.meshes.count,
                diagnostics: diagnostics
            ),
            evaluationCache: EvaluatedDocumentCache(
                generation: generation,
                modelingSettings: document.modelingSettings,
                evaluatedDocument: evaluatedDocument,
                validatedDocument: validatedDocument
            )
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
