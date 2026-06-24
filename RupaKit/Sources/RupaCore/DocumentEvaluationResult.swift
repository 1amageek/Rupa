public struct DocumentEvaluationResult: Sendable {
    public var snapshot: EvaluationSnapshot
    public var evaluationCache: EvaluatedDocumentCache?

    public init(
        snapshot: EvaluationSnapshot,
        evaluationCache: EvaluatedDocumentCache? = nil
    ) {
        self.snapshot = snapshot
        self.evaluationCache = evaluationCache
    }
}
