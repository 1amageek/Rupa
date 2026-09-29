import RupaCoreTypes

/// One document's topology snapshot, built the first time a command needs it and shared by every
/// target the command resolves: a command over many selected edges evaluates and summarizes the
/// document once instead of once per edge.
final class TopologySnapshotMemo {
    private let document: DesignDocument
    private let objectRegistry: ObjectTypeRegistry
    private var snapshot: TopologySnapshot?

    init(document: DesignDocument, objectRegistry: ObjectTypeRegistry) {
        self.document = document
        self.objectRegistry = objectRegistry
    }

    func get() throws -> TopologySnapshot {
        if let snapshot {
            return snapshot
        }
        let built = try TopologySnapshotService().snapshot(document: document, objectRegistry: objectRegistry)
        snapshot = built
        return built
    }
}
