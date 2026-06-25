import RupaCore

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

    init(
        metadata: ProductMetadata,
        scene: ViewportScene
    ) {
        var records: [ViewportSelectedIndependentCopyOutput] = []
        let transformIndex = ViewportSceneTransformIndex(metadata: metadata)
        let sources = metadata.patternArrays.values.sorted {
            $0.id.description < $1.id.description
        }
        for source in sources where source.outputMode == .independentCopy {
            for (outputIndex, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
                records.append(ViewportSelectedIndependentCopyOutput(
                    source: source,
                    outputIndex: outputIndex,
                    outputSceneNodeID: outputSceneNodeID,
                    modelTransform: transformIndex.transform(for: outputSceneNodeID)
                ))
            }
        }

        var subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>] = [:]
        var outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]] = [:]
        var outputsByIdentity: [ViewportIndependentCopyOutputIdentity: ViewportSelectedIndependentCopyOutput] = [:]
        for record in records {
            let identity = ViewportIndependentCopyOutputIdentity(
                sourceID: record.source.id,
                outputIndex: record.outputIndex
            )
            outputsByIdentity[identity] = record
            let subtreeIDs = Set(Self.sceneSubtreeIDs(
                rootedAt: record.outputSceneNodeID,
                metadata: metadata
            ))
            subtreeIDsByOutputSceneNodeID[record.outputSceneNodeID] = subtreeIDs
            for sceneNodeID in subtreeIDs {
                outputIDsBySceneNodeID[sceneNodeID, default: []].append(identity)
            }
        }

        self.outputIDsBySceneNodeID = outputIDsBySceneNodeID
        self.outputsByIdentity = outputsByIdentity
        self.subtreeIDsByOutputSceneNodeID = subtreeIDsByOutputSceneNodeID
        self.bodyItems = scene.items.filter { item in
            if case .body = item.kind {
                return true
            }
            return false
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
        metadata: ProductMetadata
    ) -> [SceneNodeID] {
        var result: [SceneNodeID] = []
        var visited: Set<SceneNodeID> = []
        appendSceneSubtreeIDs(
            rootSceneNodeID,
            metadata: metadata,
            visited: &visited,
            result: &result
        )
        return result
    }

    private static func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visited: inout Set<SceneNodeID>,
        result: inout [SceneNodeID]
    ) {
        guard visited.insert(sceneNodeID).inserted else {
            return
        }
        result.append(sceneNodeID)
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        for childID in sceneNode.childIDs {
            appendSceneSubtreeIDs(
                childID,
                metadata: metadata,
                visited: &visited,
                result: &result
            )
        }
    }
}
