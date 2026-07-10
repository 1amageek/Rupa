import RupaCore
import RupaCoreTypes

public struct DomainQueryContext: Sendable {
    public let document: DesignDocument
    public let generation: DocumentGeneration
    public let objectRegistry: ObjectTypeRegistry
    public let currentEvaluation: DocumentEvaluationContext?
    public let evaluationSnapshot: EvaluationSnapshot

    public init(
        document: DesignDocument,
        generation: DocumentGeneration,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        evaluationSnapshot: EvaluationSnapshot
    ) {
        self.document = document
        self.generation = generation
        self.objectRegistry = objectRegistry
        self.currentEvaluation = currentEvaluation
        self.evaluationSnapshot = evaluationSnapshot
    }
}
