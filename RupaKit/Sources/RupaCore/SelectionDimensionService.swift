import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SelectionDimensionService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func evaluate(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        dimensionID: SelectionDimensionID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SelectionDimensionEvaluationResult {
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
        let rawEvaluation: SwiftCAD.SelectionDimensionEvaluation
        if let dimensionID {
            rawEvaluation = try pipeline.evaluateSelectionDimension(
                dimensionID,
                in: evaluatedDocument
            )
        } else {
            rawEvaluation = try pipeline.evaluateSelectionDimensions(in: evaluatedDocument)
        }
        return SelectionDimensionEvaluationResult(
            evaluation: rawEvaluation,
            displayUnit: displayUnit
        )
    }
}
