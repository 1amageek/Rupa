import RupaCore

public struct ViewportPatternArrayPreviewService: Sendable {
    public init() {}

    public func previews(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel
    ) -> [ViewportPatternArrayPreview] {
        guard !selection.selectedTargets.isEmpty else {
            return []
        }
        let index = ViewportPatternArrayPreviewIndex(
            metadata: document.productMetadata,
            scene: scene,
            selection: selection
        )
        return document.productMetadata.patternArrays.values
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.id.description < rhs.id.description
                }
                return lhs.name < rhs.name
            }
            .compactMap { source in
                preview(
                    for: source,
                    index: index
                )
            }
    }

    private func preview(
        for source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex
    ) -> ViewportPatternArrayPreview? {
        let outputs: [ViewportPatternArrayPreview.Output]
        switch source.outputMode {
        case .componentInstance:
            outputs = componentInstanceOutputs(
                for: source,
                index: index
            )
        case .independentCopy:
            outputs = independentCopyOutputs(
                for: source,
                index: index
            )
        }

        let rootIsSelected = index.selectedSceneNodeIDs.contains(source.rootSceneNodeID)
        guard rootIsSelected || outputs.contains(where: \.isSelected) else {
            return nil
        }

        return ViewportPatternArrayPreview(
            sourceID: source.id,
            distributionKind: distributionKind(for: source.distribution),
            outputMode: source.outputMode,
            outputCount: outputCount(for: source),
            outputs: outputs
        )
    }

    private func componentInstanceOutputs(
        for source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex
    ) -> [ViewportPatternArrayPreview.Output] {
        let outputSceneNodeIDsByInstanceID = componentInstanceOutputSceneNodeIDs(
            source: source,
            index: index
        )

        return source.outputInstanceIDs.enumerated().map { outputIndex, componentInstanceID in
            let outputSceneNodeID = outputSceneNodeIDsByInstanceID[componentInstanceID]
            let sceneNodeIsSelected = outputSceneNodeID.map(index.selectedSceneNodeIDs.contains) == true
            return ViewportPatternArrayPreview.Output(
                index: outputIndex,
                itemIDs: outputSceneNodeID.flatMap { index.itemIDsBySceneNodeID[$0] } ?? [],
                isSelected: sceneNodeIsSelected
            )
        }
    }

    private func independentCopyOutputs(
        for source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex
    ) -> [ViewportPatternArrayPreview.Output] {
        source.outputSceneNodeIDs.enumerated().map { outputIndex, outputSceneNodeID in
            let subtreeIDs = sceneSubtreeIDs(
                rootedAt: outputSceneNodeID,
                index: index
            )
            return ViewportPatternArrayPreview.Output(
                index: outputIndex,
                itemIDs: itemIDs(in: subtreeIDs, index: index),
                isSelected: !index.selectedSceneNodeIDs.isDisjoint(with: subtreeIDs)
            )
        }
    }

    private func componentInstanceOutputSceneNodeIDs(
        source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex
    ) -> [ComponentInstanceID: SceneNodeID] {
        guard let rootNode = index.metadata.sceneNodes[source.rootSceneNodeID] else {
            return [:]
        }
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: SceneNodeID] = [:]
        sceneNodeIDsByInstanceID.reserveCapacity(rootNode.childIDs.count)
        let outputInstanceIDs = Set(source.outputInstanceIDs)
        for childID in rootNode.childIDs {
            guard let componentInstanceID = index.metadata.sceneNodes[childID]?.reference?.componentInstanceID,
                  outputInstanceIDs.contains(componentInstanceID) else {
                continue
            }
            sceneNodeIDsByInstanceID[componentInstanceID] = childID
        }
        return sceneNodeIDsByInstanceID
    }

    private func itemIDs(
        in sceneNodeIDs: Set<SceneNodeID>,
        index: ViewportPatternArrayPreviewIndex
    ) -> [String] {
        sceneNodeIDs
            .flatMap { index.itemIDsBySceneNodeID[$0] ?? [] }
            .sorted()
    }

    private func sceneSubtreeIDs(
        rootedAt rootSceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex
    ) -> Set<SceneNodeID> {
        var result: Set<SceneNodeID> = []
        appendSceneSubtreeIDs(
            rootSceneNodeID,
            index: index,
            result: &result
        )
        return result
    }

    private func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex,
        result: inout Set<SceneNodeID>
    ) {
        guard result.insert(sceneNodeID).inserted,
              let sceneNode = index.metadata.sceneNodes[sceneNodeID] else {
            return
        }
        for childID in sceneNode.childIDs {
            appendSceneSubtreeIDs(
                childID,
                index: index,
                result: &result
            )
        }
    }

    private func distributionKind(
        for distribution: PatternArrayDistribution
    ) -> PatternArraySummary.DistributionKind {
        switch distribution {
        case .rectangular:
            .rectangular
        case .radial:
            .radial
        case .curve:
            .curve
        }
    }

    private func outputCount(for source: PatternArraySource) -> Int {
        switch source.outputMode {
        case .componentInstance:
            source.outputInstanceIDs.count
        case .independentCopy:
            source.outputSceneNodeIDs.count
        }
    }
}

private struct ViewportPatternArrayPreviewIndex: Sendable {
    let metadata: ProductMetadata
    let selectedSceneNodeIDs: Set<SceneNodeID>
    let itemIDsBySceneNodeID: [SceneNodeID: [String]]

    init(
        metadata: ProductMetadata,
        scene: ViewportScene,
        selection: SelectionModel
    ) {
        self.metadata = metadata
        selectedSceneNodeIDs = Set(selection.selectedTargets.map(\.sceneNodeID))
        itemIDsBySceneNodeID = Dictionary(grouping: scene.items.compactMap { item -> (SceneNodeID, String)? in
            guard let sceneNodeID = item.sceneNodeID else {
                return nil
            }
            return (sceneNodeID, item.id)
        }, by: \.0)
            .mapValues { pairs in
                pairs.map(\.1).sorted()
            }
    }
}
