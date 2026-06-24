import SwiftCAD

public struct DocumentEvaluationContextResolver: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func evaluatedDocument(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil,
        failurePrefix: String
    ) throws -> EvaluatedDocument {
        if let currentEvaluation {
            do {
                if try currentEvaluation.matches(
                    document: document,
                    generation: currentGeneration
                ) {
                    return currentEvaluation.evaluatedDocument
                }
            } catch {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "\(failurePrefix): \(String(describing: error))"
                )
            }
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
}
