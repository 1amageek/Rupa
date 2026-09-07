import RupaCore
import RupaViewportScene

public struct ViewportPatternArrayPreviewService: Sendable {
    public init() {}

    public func previews(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel
    ) -> [ViewportPatternArrayPreview] {
        previews(
            document: document,
            scene: scene,
            selection: selection,
            checkpoint: { _, _, _ in }
        )
    }

    /// Builds every pattern preview whose own selection predicate matches.
    /// The worker passes a checkpoint that admits output and traversal work;
    /// legacy callers pass the no-op checkpoint above.
    func previews(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [ViewportPatternArrayPreview] {
        try checkpoint(0, 0, 0)
        guard !selection.selectedTargets.isEmpty else {
            return []
        }
        let index = try ViewportPatternArrayPreviewIndex(
            metadata: document.productMetadata,
            scene: scene,
            selection: selection,
            checkpoint: checkpoint
        )
        try checkpoint(0, 0, document.productMetadata.patternArrays.count)
        let sources = try document.productMetadata.patternArrays.values.sorted { lhs, rhs in
            try checkpoint(0, 0, 1)
            if lhs.name == rhs.name {
                return lhs.id.description < rhs.id.description
            }
            return lhs.name < rhs.name
        }
        var previews: [ViewportPatternArrayPreview] = []
        if !sources.isEmpty {
            previews.reserveCapacity(sources.count)
        }
        for source in sources {
            try checkpoint(0, 0, 1)
            guard try sourceMatchesSelection(
                source,
                index: index,
                checkpoint: checkpoint
            ) else {
                continue
            }
            let outputCount = outputCount(for: source)
            try checkpoint(outputCount, 0, 0)
            if let preview = try preview(
                for: source,
                index: index,
                checkpoint: checkpoint
            ) {
                previews.append(preview)
            }
        }
        try checkpoint(previews.count, 0, 0)
        return previews
    }

    private func sourceMatchesSelection(
        _ source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        if index.selectedSceneNodeIDs.contains(source.rootSceneNodeID) {
            return true
        }
        switch source.outputMode {
        case .componentInstance:
            guard let rootNode = index.metadata.sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            try checkpoint(0, 0, rootNode.childIDs.count)
            try checkpoint(0, 0, source.outputInstanceIDs.count)
            let outputInstanceIDs = Set(source.outputInstanceIDs)
            for childID in rootNode.childIDs {
                try checkpoint(0, 0, 1)
                guard let componentInstanceID = index.metadata.sceneNodes[childID]?.reference?.componentInstanceID,
                      outputInstanceIDs.contains(componentInstanceID) else {
                    continue
                }
                if index.selectedSceneNodeIDs.contains(childID) {
                    return true
                }
            }
            return false
        case .independentCopy:
            try checkpoint(0, 0, source.outputSceneNodeIDs.count)
            for outputSceneNodeID in source.outputSceneNodeIDs {
                if try sceneSubtreeContainsSelection(
                    rootedAt: outputSceneNodeID,
                    index: index,
                    checkpoint: checkpoint
                ) {
                    return true
                }
            }
            return false
        }
    }

    private func sceneSubtreeContainsSelection(
        rootedAt rootSceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        try checkpoint(0, 0, 1)
        var visited: Set<SceneNodeID> = []
        visited.reserveCapacity(1)
        return try sceneSubtreeContainsSelection(
            rootSceneNodeID,
            index: index,
            visited: &visited,
            checkpoint: checkpoint
        )
    }

    private func sceneSubtreeContainsSelection(
        _ sceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex,
        visited: inout Set<SceneNodeID>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        try checkpoint(0, 0, 1)
        guard visited.insert(sceneNodeID).inserted else {
            return false
        }
        if index.selectedSceneNodeIDs.contains(sceneNodeID) {
            return true
        }
        guard let sceneNode = index.metadata.sceneNodes[sceneNodeID] else {
            return false
        }
        for childID in sceneNode.childIDs {
            if try sceneSubtreeContainsSelection(
                childID,
                index: index,
                visited: &visited,
                checkpoint: checkpoint
            ) {
                return true
            }
        }
        return false
    }

    private func preview(
        for source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> ViewportPatternArrayPreview? {
        try checkpoint(0, 0, 0)
        let outputs: [ViewportPatternArrayPreview.Output]
        switch source.outputMode {
        case .componentInstance:
            outputs = try componentInstanceOutputs(
                for: source,
                index: index,
                checkpoint: checkpoint
            )
        case .independentCopy:
            outputs = try independentCopyOutputs(
                for: source,
                index: index,
                checkpoint: checkpoint
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
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [ViewportPatternArrayPreview.Output] {
        guard let rootNode = index.metadata.sceneNodes[source.rootSceneNodeID] else {
            return []
        }
        try checkpoint(0, 0, rootNode.childIDs.count)
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: SceneNodeID] = [:]
        if !rootNode.childIDs.isEmpty {
            sceneNodeIDsByInstanceID.reserveCapacity(rootNode.childIDs.count)
        }
        try checkpoint(0, 0, source.outputInstanceIDs.count)
        let outputInstanceIDs = Set(source.outputInstanceIDs)
        for childID in rootNode.childIDs {
            try checkpoint(0, 0, 1)
            guard let componentInstanceID = index.metadata.sceneNodes[childID]?.reference?.componentInstanceID,
                  outputInstanceIDs.contains(componentInstanceID) else {
                continue
            }
            sceneNodeIDsByInstanceID[componentInstanceID] = childID
        }
        let outputCount = source.outputInstanceIDs.count
        try checkpoint(outputCount, 0, 0)
        var outputs: [ViewportPatternArrayPreview.Output] = []
        if outputCount > 0 {
            outputs.reserveCapacity(outputCount)
        }
        for (outputIndex, componentInstanceID) in source.outputInstanceIDs.enumerated() {
            try checkpoint(0, 0, 1)
            let outputSceneNodeID = sceneNodeIDsByInstanceID[componentInstanceID]
            let itemIDs: [String]
            if let outputSceneNodeID {
                try checkpoint(0, 0, 1)
                itemIDs = try self.itemIDs(
                    in: Set([outputSceneNodeID]),
                    index: index,
                    checkpoint: checkpoint
                )
            } else {
                itemIDs = []
            }
            outputs.append(.init(
                index: outputIndex,
                itemIDs: itemIDs,
                isSelected: outputSceneNodeID.map(index.selectedSceneNodeIDs.contains) == true
            ))
        }
        return outputs
    }

    private func independentCopyOutputs(
        for source: PatternArraySource,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [ViewportPatternArrayPreview.Output] {
        let outputCount = source.outputSceneNodeIDs.count
        try checkpoint(outputCount, 0, 0)
        var outputs: [ViewportPatternArrayPreview.Output] = []
        if outputCount > 0 {
            outputs.reserveCapacity(outputCount)
        }
        for (outputIndex, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
            try checkpoint(0, 0, 1)
            let subtreeIDs = try sceneSubtreeIDs(
                rootedAt: outputSceneNodeID,
                index: index,
                checkpoint: checkpoint
            )
            let itemIDs = try itemIDs(
                in: subtreeIDs,
                index: index,
                checkpoint: checkpoint
            )
            outputs.append(.init(
                index: outputIndex,
                itemIDs: itemIDs,
                isSelected: !index.selectedSceneNodeIDs.isDisjoint(with: subtreeIDs)
            ))
        }
        return outputs
    }

    private func itemIDs(
        in sceneNodeIDs: Set<SceneNodeID>,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [String] {
        try checkpoint(0, 0, sceneNodeIDs.count)
        var itemCount = 0
        for sceneNodeID in sceneNodeIDs {
            try checkpoint(0, 0, 1)
            itemCount += index.itemIDsBySceneNodeID[sceneNodeID]?.count ?? 0
        }
        try checkpoint(itemCount, 0, 0)
        var result: [String] = []
        if itemCount > 0 {
            result.reserveCapacity(itemCount)
        }
        for sceneNodeID in sceneNodeIDs {
            try checkpoint(0, 0, 1)
            result.append(contentsOf: index.itemIDsBySceneNodeID[sceneNodeID] ?? [])
        }
        try result.sort {
            try checkpoint(0, 0, 1)
            return $0 < $1
        }
        return result
    }

    private func sceneSubtreeIDs(
        rootedAt rootSceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Set<SceneNodeID> {
        try checkpoint(0, 0, 1)
        var result: Set<SceneNodeID> = []
        result.reserveCapacity(1)
        try appendSceneSubtreeIDs(
            rootSceneNodeID,
            index: index,
            result: &result,
            checkpoint: checkpoint
        )
        return result
    }

    private func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
        index: ViewportPatternArrayPreviewIndex,
        result: inout Set<SceneNodeID>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows {
        try checkpoint(0, 0, 1)
        guard result.insert(sceneNodeID).inserted,
              let sceneNode = index.metadata.sceneNodes[sceneNodeID] else {
            return
        }
        for childID in sceneNode.childIDs {
            try appendSceneSubtreeIDs(
                childID,
                index: index,
                result: &result,
                checkpoint: checkpoint
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
        selection: SelectionModel,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows {
        try checkpoint(0, 0, selection.selectedTargets.count)
        var selectedSceneNodeIDs: Set<SceneNodeID> = []
        if !selection.selectedTargets.isEmpty {
            selectedSceneNodeIDs.reserveCapacity(selection.selectedTargets.count)
        }
        for target in selection.selectedTargets {
            try checkpoint(0, 0, 1)
            selectedSceneNodeIDs.insert(target.sceneNodeID)
        }

        try checkpoint(0, 0, scene.items.count)
        var grouped: [SceneNodeID: [String]] = [:]
        if !scene.items.isEmpty {
            grouped.reserveCapacity(scene.items.count)
        }
        for item in scene.items {
            try checkpoint(0, 0, 1)
            guard let sceneNodeID = item.sceneNodeID else {
                continue
            }
            grouped[sceneNodeID, default: []].append(item.id)
        }
        self.metadata = metadata
        self.selectedSceneNodeIDs = selectedSceneNodeIDs
        self.itemIDsBySceneNodeID = try grouped.mapValues { values in
            try values.sorted {
                try checkpoint(0, 0, 1)
                return $0 < $1
            }
        }
    }
}
