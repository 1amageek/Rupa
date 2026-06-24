public struct DocumentEvaluationResult: Sendable {
    public var snapshot: EvaluationSnapshot
    public var evaluatedDocument: EvaluatedDocument?

    public init(
        snapshot: EvaluationSnapshot,
        evaluatedDocument: EvaluatedDocument? = nil
    ) {
        self.snapshot = snapshot
        self.evaluatedDocument = evaluatedDocument
    }
}
