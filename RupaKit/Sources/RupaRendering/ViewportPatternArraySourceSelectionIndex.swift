import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPatternArraySourceSelectionIndex {
    var metadata: ProductMetadata
    var scene: ViewportScene
    var selection: SelectionModel

    func selectedSourceIDs() -> [PatternArraySourceID] {
        selectedSourceIDs(checkpoint: { _, _, _ in })
    }

    func selectedSourceIDs(
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [PatternArraySourceID] {
        try checkpoint(0, 0, selection.selectedTargets.count)
        var sourceIDs: [PatternArraySourceID] = []
        var seenSourceIDs: Set<PatternArraySourceID> = []
        if !selection.selectedTargets.isEmpty {
            sourceIDs.reserveCapacity(selection.selectedTargets.count)
            seenSourceIDs.reserveCapacity(selection.selectedTargets.count)
        }
        for target in selection.selectedTargets {
            try checkpoint(0, 0, 1)
            guard let sourceID = try patternArraySourceID(
                containing: target.sceneNodeID,
                checkpoint: checkpoint
            ), seenSourceIDs.insert(sourceID).inserted else {
                continue
            }
            sourceIDs.append(sourceID)
        }
        return sourceIDs
    }

    func sourceBaseProjectedPoint(
        source: PatternArraySource,
        layout: ViewportLayout
    ) -> CGPoint? {
        sourceBaseSceneItems(source: source)
            .compactMap { itemProjectedCenter($0, layout: layout) }
            .average()
            ?? sourceOutputFallbackSceneItems(source: source)
            .compactMap { itemProjectedCenter($0, layout: layout) }
            .average()
    }

    func sourceBaseModelPoint(source: PatternArraySource) -> Point3D? {
        sourceBaseModelPoint(source: source, checkpoint: { _, _, _ in })
    }

    /// Worker-facing source anchor traversal. The checkpoint is invoked before
    /// subtree visits and before materializing the selected scene-item values.
    func sourceBaseModelPoint(
        source: PatternArraySource,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Point3D? {
        let sceneItems = try sourceBaseSceneItems(
            source: source,
            checkpoint: checkpoint
        )
        if !sceneItems.isEmpty {
            try checkpoint(sceneItems.count, sceneItems.count, 0)
            var sum = Point3D(x: 0, y: 0, z: 0)
            for item in sceneItems {
                try checkpoint(0, 0, 1)
                let point = itemModelCenter(item)
                sum = Point3D(
                    x: sum.x + point.x,
                    y: sum.y + point.y,
                    z: sum.z + point.z
                )
            }
            let count = Double(sceneItems.count)
            return Point3D(
                x: sum.x / count,
                y: sum.y / count,
                z: sum.z / count
            )
        }
        let fallbackItems = try sourceOutputFallbackSceneItems(
            source: source,
            checkpoint: checkpoint
        )
        guard !fallbackItems.isEmpty else {
            return nil
        }
        try checkpoint(fallbackItems.count, fallbackItems.count, 0)
        var sum = Point3D(x: 0, y: 0, z: 0)
        for item in fallbackItems {
            try checkpoint(0, 0, 1)
            let point = itemModelCenter(item)
            sum = Point3D(
                x: sum.x + point.x,
                y: sum.y + point.y,
                z: sum.z + point.z
            )
        }
        let count = Double(fallbackItems.count)
        return Point3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }

    private func sourceBaseSceneItems(source: PatternArraySource) -> [ViewportSceneItem] {
        guard let definition = metadata.componentDefinitions[source.definitionID] else {
            return []
        }
        let sourceRootIDs = Set(
            definition.rootSceneNodeIDs.flatMap { rootID in
                sceneSubtreeIDs(rootedAt: rootID)
            }
        )
        return scene.items.filter { item in
            guard let sceneNodeID = item.sceneNodeID,
                  sourceRootIDs.contains(sceneNodeID),
                  item.componentInstanceID == nil else {
                return false
            }
            return true
        }
    }

    private func sourceBaseSceneItems(
        source: PatternArraySource,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [ViewportSceneItem] {
        guard let definition = metadata.componentDefinitions[source.definitionID] else {
            return []
        }
        try checkpoint(0, 0, definition.rootSceneNodeIDs.count)
        var sourceRootIDs: Set<SceneNodeID> = []
        if !definition.rootSceneNodeIDs.isEmpty {
            sourceRootIDs.reserveCapacity(definition.rootSceneNodeIDs.count)
        }
        for rootID in definition.rootSceneNodeIDs {
            let subtreeIDs = try sceneSubtreeIDs(
                rootedAt: rootID,
                checkpoint: checkpoint
            )
            sourceRootIDs.formUnion(subtreeIDs)
        }
        var matchingItemCount = 0
        for item in scene.items {
            try checkpoint(0, 0, 1)
            guard let sceneNodeID = item.sceneNodeID,
                  sourceRootIDs.contains(sceneNodeID),
                  item.componentInstanceID == nil else {
                continue
            }
            matchingItemCount += 1
        }
        try checkpoint(matchingItemCount, matchingItemCount, 0)
        var result: [ViewportSceneItem] = []
        if matchingItemCount > 0 {
            result.reserveCapacity(matchingItemCount)
        }
        for item in scene.items {
            try checkpoint(0, 0, 1)
            guard let sceneNodeID = item.sceneNodeID,
                  sourceRootIDs.contains(sceneNodeID),
                  item.componentInstanceID == nil else {
                continue
            }
            result.append(item)
        }
        return result
    }

    private func sourceOutputFallbackSceneItems(source: PatternArraySource) -> [ViewportSceneItem] {
        let outputRootIDs = Set(outputRootSceneNodeIDs(source: source))
        return scene.items.filter { item in
            guard let sceneNodeID = item.sceneNodeID else {
                return false
            }
            return outputRootIDs.contains(sceneNodeID)
        }
    }

    private func sourceOutputFallbackSceneItems(
        source: PatternArraySource,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [ViewportSceneItem] {
        let outputRootIDs = try outputRootSceneNodeIDs(
            source: source,
            checkpoint: checkpoint
        )
        var matchingItemCount = 0
        for item in scene.items {
            try checkpoint(0, 0, 1)
            if let sceneNodeID = item.sceneNodeID,
               outputRootIDs.contains(sceneNodeID) {
                matchingItemCount += 1
            }
        }
        try checkpoint(matchingItemCount, matchingItemCount, 0)
        var result: [ViewportSceneItem] = []
        if matchingItemCount > 0 {
            result.reserveCapacity(matchingItemCount)
        }
        for item in scene.items {
            try checkpoint(0, 0, 1)
            guard let sceneNodeID = item.sceneNodeID,
                  outputRootIDs.contains(sceneNodeID) else {
                continue
            }
            result.append(item)
        }
        return result
    }

    private func outputRootSceneNodeIDs(source: PatternArraySource) -> [SceneNodeID] {
        outputRootSceneNodeIDs(source: source, checkpoint: { _, _, _ in })
    }

    private func outputRootSceneNodeIDs(
        source: PatternArraySource,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [SceneNodeID] {
        switch source.outputMode {
        case .componentInstance:
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                return []
            }
            try checkpoint(0, 0, rootNode.childIDs.count)
            try checkpoint(0, 0, source.outputInstanceIDs.count)
            let outputInstanceIDs = Set(source.outputInstanceIDs)
            var result: [SceneNodeID] = []
            if !rootNode.childIDs.isEmpty {
                result.reserveCapacity(1)
            }
            for childID in rootNode.childIDs {
                try checkpoint(0, 0, 1)
                guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID else {
                    continue
                }
                guard outputInstanceIDs.contains(componentInstanceID) else {
                    continue
                }
                result.append(childID)
                break
            }
            return result
        case .independentCopy:
            try checkpoint(0, 0, source.outputSceneNodeIDs.count)
            return Array(source.outputSceneNodeIDs.prefix(1))
        }
    }

    private func patternArraySourceID(
        containing sceneNodeID: SceneNodeID,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> PatternArraySourceID? {
        try checkpoint(0, 0, metadata.patternArrays.count)
        for source in metadata.patternArrays.values {
            try checkpoint(0, 0, 1)
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                continue
            }
            if sceneNodeID == source.rootSceneNodeID {
                return source.id
            }
            for outputSceneNodeID in rootNode.childIDs {
                try checkpoint(0, 0, 1)
                if try sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID,
                    checkpoint: checkpoint
                ) {
                    return source.id
                }
            }
        }
        return nil
    }

    private func itemProjectedCenter(
        _ item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGPoint? {
        if let projection = layout.bodyProjection(for: item) {
            return projection.center
        }
        return layout.projectedFootprintIfVisible(item.modelBounds)?.center
    }

    private func itemModelCenter(_ item: ViewportSceneItem) -> Point3D {
        let y: Double
        if case .body(let component) = item.kind,
           component.yMinMeters.isFinite,
           component.yMaxMeters.isFinite {
            y = (component.yMinMeters + component.yMaxMeters) * 0.5
        } else {
            y = 0.0
        }
        return Point3D(
            x: Double(item.modelBounds.midX),
            y: y,
            z: Double(item.modelBounds.midY)
        )
    }

    private func sceneSubtreeIDs(rootedAt rootSceneNodeID: SceneNodeID) -> [SceneNodeID] {
        var result: [SceneNodeID] = []
        var visited: Set<SceneNodeID> = []
        appendSceneSubtreeIDs(
            rootSceneNodeID,
            visited: &visited,
            result: &result
        )
        return result
    }

    private func sceneSubtreeIDs(
        rootedAt rootSceneNodeID: SceneNodeID,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Set<SceneNodeID> {
        try checkpoint(0, 0, 1)
        var result: Set<SceneNodeID> = []
        result.reserveCapacity(1)
        var visited: Set<SceneNodeID> = []
        visited.reserveCapacity(1)
        try appendSceneSubtreeIDs(
            rootSceneNodeID,
            visited: &visited,
            result: &result,
            checkpoint: checkpoint
        )
        return result
    }

    private func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
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
                visited: &visited,
                result: &result
            )
        }
    }

    private func appendSceneSubtreeIDs(
        _ sceneNodeID: SceneNodeID,
        visited: inout Set<SceneNodeID>,
        result: inout Set<SceneNodeID>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows {
        try checkpoint(0, 0, 1)
        guard visited.insert(sceneNodeID).inserted,
              result.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        for childID in sceneNode.childIDs {
            try appendSceneSubtreeIDs(
                childID,
                visited: &visited,
                result: &result,
                checkpoint: checkpoint
            )
        }
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        try checkpoint(0, 0, 1)
        var visited: Set<SceneNodeID> = []
        visited.reserveCapacity(1)
        return try sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            visited: &visited,
            checkpoint: checkpoint
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        visited: inout Set<SceneNodeID>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        try checkpoint(0, 0, 1)
        guard visited.insert(rootSceneNodeID).inserted else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        guard let sceneNode = metadata.sceneNodes[rootSceneNodeID] else {
            return false
        }
        for childID in sceneNode.childIDs {
            if try sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                visited: &visited,
                checkpoint: checkpoint
            ) {
                return true
            }
        }
        return false
    }
}

private extension Array where Element == CGPoint {
    func average() -> CGPoint? {
        guard !isEmpty else {
            return nil
        }
        let sum = reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(count),
            y: sum.y / CGFloat(count)
        )
    }
}

private extension Array where Element == Point3D {
    func average() -> Point3D? {
        guard !isEmpty else {
            return nil
        }
        let sum = reduce(Point3D(x: 0, y: 0, z: 0)) { partial, point in
            Point3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let count = Double(count)
        return Point3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }
}
