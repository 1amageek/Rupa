public struct DocumentEvaluationResult: Sendable {
    public var snapshot: EvaluationSnapshot
    public var evaluationCache: EvaluatedDocumentCache?
    /// The validation the evaluation read or made, whenever the document validated, including a
    /// document with nothing for the CAD kernel to evaluate, which has no evaluation cache.
    public var validatedDocument: ValidatedDesignDocument?

    public init(
        snapshot: EvaluationSnapshot,
        evaluationCache: EvaluatedDocumentCache? = nil,
        validatedDocument: ValidatedDesignDocument? = nil
    ) {
        self.snapshot = snapshot
        self.evaluationCache = evaluationCache
        self.validatedDocument = validatedDocument ?? evaluationCache?.validatedDocument
    }
}
