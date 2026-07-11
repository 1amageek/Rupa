public struct CADDocumentStoreTransactionSnapshot: Sendable {
    public let document: DocumentSnapshot
    public let evaluationCache: EvaluatedDocumentCache?
    public let completedEvaluationPassCount: UInt64

    package init(
        document: DocumentSnapshot,
        evaluationCache: EvaluatedDocumentCache?,
        completedEvaluationPassCount: UInt64
    ) {
        self.document = document
        self.evaluationCache = evaluationCache
        self.completedEvaluationPassCount = completedEvaluationPassCount
    }
}
