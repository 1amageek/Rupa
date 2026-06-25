import Foundation
import SwiftCAD

public struct SelectionMeasurementService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func measure(
        query: CADAgentMeasurementQuery,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> CADAgentMeasurementQueryResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before selection measurement: \(String(describing: error))"
            )
        }

        do {
            try query.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection measurement query is invalid: \(String(describing: error))"
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
            failurePrefix: "Document must evaluate successfully before selection measurement"
        )

        switch query.kind {
        case .point:
            return .point(try pipeline.measurementPoint(for: query.first, in: evaluatedDocument))
        case .distance:
            guard let second = query.second else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection distance measurement requires a second selection."
                )
            }
            return .distance(try pipeline.distance(from: query.first, to: second, in: evaluatedDocument))
        case .angle:
            guard let second = query.second else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection angle measurement requires a second selection."
                )
            }
            return .angle(try pipeline.angle(between: query.first, and: second, in: evaluatedDocument))
        }
    }
}
