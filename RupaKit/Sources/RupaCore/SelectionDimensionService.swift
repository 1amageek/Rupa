import Foundation
import SwiftCAD

public struct SelectionDimensionService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func evaluate(
        document: DesignDocument,
        dimensionID: SelectionDimensionID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SelectionDimensionEvaluation {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before selection dimension evaluation: \(String(describing: error))"
            )
        }

        let pipeline = pipelineOverride ?? .modelingDefault(
            for: document,
            objectRegistry: objectRegistry
        )
        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before selection dimension evaluation"
        )
        if let dimensionID {
            return try pipeline.evaluateSelectionDimension(
                dimensionID,
                in: evaluatedDocument
            )
        }
        return try pipeline.evaluateSelectionDimensions(in: evaluatedDocument)
    }
}
