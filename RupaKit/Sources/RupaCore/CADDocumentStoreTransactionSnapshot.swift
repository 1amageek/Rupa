public struct CADDocumentStoreTransactionSnapshot: Sendable {
    public let document: DocumentSnapshot
    public let evaluationCache: EvaluatedDocumentCache?
    /// The store's validation of `document`, captured with it, so a store rebuilt from the
    /// snapshot validates nothing the published store already validated.
    public let validatedSource: ValidatedDesignDocument?
    public let completedEvaluationPassCount: UInt64

    package init(
        document: DocumentSnapshot,
        evaluationCache: EvaluatedDocumentCache?,
        validatedSource: ValidatedDesignDocument?,
        completedEvaluationPassCount: UInt64
    ) {
        self.document = document
        self.evaluationCache = evaluationCache
        self.validatedSource = validatedSource
        self.completedEvaluationPassCount = completedEvaluationPassCount
    }
}
