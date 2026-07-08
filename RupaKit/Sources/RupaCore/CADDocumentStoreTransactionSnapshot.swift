public struct CADDocumentStoreTransactionSnapshot: Sendable {
    public var document: DocumentSnapshot
    public var evaluationCache: EvaluatedDocumentCache?

    public init(
        document: DocumentSnapshot,
        evaluationCache: EvaluatedDocumentCache?
    ) {
        self.document = document
        self.evaluationCache = evaluationCache
    }
}
