import RupaCore
import RupaViewportScene

struct ViewportSelectedIndependentCopyOutput: Equatable {
    var source: PatternArraySource
    var outputIndex: Int
    var outputSceneNodeID: SceneNodeID
    var modelTransform: Transform3D
}

struct ViewportIndependentCopyOutputIdentity: Hashable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
}

struct ViewportIndependentCopyOutputSelectionIndex {
    private var outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]]
    private var outputsByIdentity: [ViewportIndependentCopyOutputIdentity: ViewportSelectedIndependentCopyOutput]
    private var subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>]
    private var bodyItems: [ViewportSceneItem]

    private struct Storage {
        let outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]]
        let outputsByIdentity: [ViewportIndependentCopyOutputIdentity: ViewportSelectedIndependentCopyOutput]
        let subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>]
        let bodyItems: [ViewportSceneItem]
    }

    init(
        metadata: ProductMetadata,
        scene: ViewportScene
    ) {
        let result = Self.buildStorage(metadata: metadata, scene: scene) { _, _, _ in }
        guard case .success(let storage) = result else {
            preconditionFailure("The nonthrowing independent-copy index could not be built.")
        }
        self = Self(storage: storage)
    }

    /// Builds the same index while charging recursive source traversal and
    /// allowing the worker to propagate cancellation or typed admission
    /// failure before nested subtree materialization.
    init(
        metadata: ProductMetadata,
        scene: ViewportScene,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        switch Self.buildStorage(metadata: metadata, scene: scene, checkpoint: checkpoint) {
        case .success(let storage):
            self = Self(storage: storage)
        case .failure(let error):
            throw error
        }
    }

    private init(storage: Storage) {
        self.outputIDsBySceneNodeID = storage.outputIDsBySceneNodeID
        self.outputsByIdentity = storage.outputsByIdentity
        self.subtreeIDsByOutputSceneNodeID = storage.subtreeIDsByOutputSceneNodeID
        self.bodyItems = storage.bodyItems
    }

    private static func buildStorage(
        metadata: ProductMetadata,
        scene: ViewportScene,
        checkpoint: (Int, Int, Int) throws -> Void = { _, _, _ in }
    ) -> Result<Storage, Error> {
        do {
            // Charge before sorting/materializing the metadata source list.
            try checkpoint(0, 0, metadata.patternArrays.count)
            let sources = metadata.patternArrays.values.sorted {
                $0.id.description < $1.id.description
            }
            let transformIndex = ViewportSceneTransformIndex(metadata: metadata)
            var records: [ViewportSelectedIndependentCopyOutput] = []
            for source in sources where source.outputMode == .independentCopy {
                try checkpoint(0, 0, source.outputSceneNodeIDs.count)
                for (outputIndex, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
                    try checkpoint(0, 0, 1)
                    records.append(ViewportSelectedIndependentCopyOutput(
                        source: source,
                        outputIndex: outputIndex,
                        outputSceneNodeID: outputSceneNodeID,
                        modelTransform: transformIndex.transform(for: outputSceneNodeID)
                    ))
                }
            }

            try checkpoint(0, 0, records.count)
            var subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>] = [:]
            var outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]] = [:]
            var outputsByIdentity: [ViewportIndependentCopyOutputIdentity: ViewportSelectedIndependentCopyOutput] = [:]
            for record in records {
                try checkpoint(0, 0, 1)
                let identity = ViewportIndependentCopyOutputIdentity(
                    sourceID: record.source.id,
                    outputIndex: record.outputIndex
                )
                outputsByIdentity[identity] = record
                let subtreeIDs = Set(try Self.sceneSubtreeIDs(
                    rootedAt: record.outputSceneNodeID,
                    metadata: metadata,
                    checkpoint: checkpoint
                ))
                subtreeIDsByOutputSceneNodeID[record.outputSceneNodeID] = subtreeIDs
                try checkpoint(0, 0, subtreeIDs.count)
                for sceneNodeID in subtreeIDs {
                    outputIDsBySceneNodeID[sceneNodeID, default: []].append(identity)
                }
            }

            try checkpoint(0, 0, scene.items.count)
            let bodyItems = scene.items.filter { item in
                if case .body = item.kind {
                    return true
                }
                return false
            }
            return .success(Storage(
                outputIDsBySceneNodeID: outputIDsBySceneNodeID,
                outputsByIdentity: outputsByIdentity,
                subtreeIDsByOutputSceneNodeID: subtreeIDsByOutputSceneNodeID,
                bodyItems: bodyItems
            ))
        } catch {
            return .failure(error)
        }
    }

    func selectedOutputs(selection: SelectionModel) -> [ViewportSelectedIndependentCopyOutput] {
        var selected: [ViewportSelectedIndependentCopyOutput] = []
        var seen: Set<ViewportIndependentCopyOutputIdentity> = []
        for target in selection.selectedTargets {
            guard let identities = outputIDsBySceneNodeID[target.sceneNodeID] else {
                continue
            }
            for identity in identities where seen.insert(identity).inserted {
                guard let output = outputsByIdentity[identity] else {
                    continue
                }
                selected.append(output)
            }
        }
        return selected
    }

    func bodyItems(
        rootedAt outputSceneNodeID: SceneNodeID,
        ownedFeatureIDs: Set<FeatureID>
    ) -> [ViewportSceneItem] {
        guard let subtreeIDs = subtreeIDsByOutputSceneNodeID[outputSceneNodeID] else {
            return []
        }
        return bodyItems.filter { item in
            guard let sceneNodeID = item.sceneNodeID,
                  subtreeIDs.contains(sceneNodeID),
                  ownedFeatureIDs.contains(item.featureID) else {
                return false
            }
            return true
        }
    }

    private static func sceneSubtreeIDs(
        rootedAt rootSceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [SceneNodeID] {
        var result: [SceneNodeID] = []
        var visited: Set<SceneNodeID> = []
        try appendSceneSubtreeIDs(
            rootSceneNodeID,
            metadata: metadata,
            visited: &visited,
            result: &result,
            checkpoint: checkpoint
        )
        return result
    }

    private static func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visited: inout Set<SceneNodeID>,
        result: inout [SceneNodeID],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(0, 0, 1)
        guard visited.insert(sceneNodeID).inserted else {
            return
        }
        result.append(sceneNodeID)
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        try checkpoint(0, 0, sceneNode.childIDs.count)
        for childID in sceneNode.childIDs {
            try appendSceneSubtreeIDs(
                childID,
                metadata: metadata,
                visited: &visited,
                result: &result,
                checkpoint: checkpoint
            )
        }
    }
}
