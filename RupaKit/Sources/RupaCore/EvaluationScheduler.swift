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
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            return failedSnapshot(
                message: String(describing: error),
                generation: generation
            )
        }

        guard document.cadDocument.hasActiveBodyProducingFeatures else {
            return evaluatedEmptyDocument(generation: generation)
        }

        let evaluator = evaluatorOverride ?? .modelingDefault(
            for: document,
            objectRegistry: objectRegistry
        )
        let report = evaluator.evaluateReport(document.cadDocument)
        guard report.isComplete, let evaluatedDocument = report.evaluatedDocument else {
            let message = report.failure?.message ?? "Document evaluation did not complete."
            return failedSnapshot(
                message: message,
                generation: generation
            )
        }

        return EvaluationSnapshot(
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

private extension CADDocument {
    var hasActiveBodyProducingFeatures: Bool {
        designGraph.order.contains { featureID in
            guard let feature = designGraph.nodes[featureID], !feature.isSuppressed else {
                return false
            }
            switch feature.operation {
            case .sketch:
                return false
            case .extrude:
                return true
            case .sweep:
                return true
            case .polySpline:
                return true
            case .faceLoopOffset:
                return true
            case .edgeOffset:
                return true
            case .faceKnife:
                return true
            }
        }
    }
}
