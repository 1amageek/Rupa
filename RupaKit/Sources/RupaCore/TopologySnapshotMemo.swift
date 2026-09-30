import RupaCoreTypes

/// One document's topology snapshot, built the first time a command needs it and shared by every
/// target the command resolves: a command over many selected edges evaluates and summarizes the
/// document once instead of once per edge. The store's current evaluation, when it describes the
/// document, is read instead of evaluating the document.
final class TopologySnapshotMemo {
    private let document: DesignDocument
    private let objectRegistry: ObjectTypeRegistry
    private let currentEvaluation: DocumentEvaluationContext?
    private let currentGeneration: DocumentGeneration?
    private var snapshot: TopologySnapshot?

    init(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) {
        self.document = document
        self.objectRegistry = objectRegistry
        self.currentEvaluation = currentEvaluation
        self.currentGeneration = currentGeneration
    }

    func get() throws -> TopologySnapshot {
        if let snapshot {
            return snapshot
        }
        let built = try TopologySnapshotService().snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        snapshot = built
        return built
    }
}
