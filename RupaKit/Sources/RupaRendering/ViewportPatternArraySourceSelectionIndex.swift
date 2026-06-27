import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPatternArraySourceSelectionIndex {
    var metadata: ProductMetadata
    var scene: ViewportScene
    var selection: SelectionModel

    func selectedSourceIDs() -> [PatternArraySourceID] {
        var sourceIDs: [PatternArraySourceID] = []
        var seenSourceIDs: Set<PatternArraySourceID> = []
        for target in selection.selectedTargets {
            guard let sourceID = patternArraySourceID(containing: target.sceneNodeID),
                  seenSourceIDs.insert(sourceID).inserted else {
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
            .map { itemProjectedCenter($0, layout: layout) }
            .average()
            ?? sourceOutputFallbackSceneItems(source: source)
            .map { itemProjectedCenter($0, layout: layout) }
            .average()
    }

    func sourceBaseModelPoint(source: PatternArraySource) -> Point3D? {
        sourceBaseSceneItems(source: source)
            .map(itemModelCenter)
            .average()
            ?? sourceOutputFallbackSceneItems(source: source)
            .map(itemModelCenter)
            .average()
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

    private func sourceOutputFallbackSceneItems(source: PatternArraySource) -> [ViewportSceneItem] {
        let outputRootIDs = Set(outputRootSceneNodeIDs(source: source).prefix(1))
        return scene.items.filter { item in
            guard let sceneNodeID = item.sceneNodeID else {
                return false
            }
            return outputRootIDs.contains(sceneNodeID)
        }
    }

    private func outputRootSceneNodeIDs(source: PatternArraySource) -> [SceneNodeID] {
        switch source.outputMode {
        case .componentInstance:
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                return []
            }
            let outputInstanceIDs = Set(source.outputInstanceIDs)
            return rootNode.childIDs.filter { childID in
                guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID else {
                    return false
                }
                return outputInstanceIDs.contains(componentInstanceID)
            }
        case .independentCopy:
            return source.outputSceneNodeIDs
        }
    }

    private func patternArraySourceID(containing sceneNodeID: SceneNodeID) -> PatternArraySourceID? {
        for source in metadata.patternArrays.values {
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                continue
            }
            if sceneNodeID == source.rootSceneNodeID {
                return source.id
            }
            if rootNode.childIDs.contains(where: { outputSceneNodeID in
                sceneSubtree(outputSceneNodeID, contains: sceneNodeID)
            }) {
                return source.id
            }
        }
        return nil
    }

    private func itemProjectedCenter(
        _ item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGPoint {
        if let projection = layout.bodyProjection(for: item) {
            return projection.center
        }
        return layout.projectedFootprint(item.modelBounds).center
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

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID
    ) -> Bool {
        var visited: Set<SceneNodeID> = []
        return sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            visited: &visited
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        visited: inout Set<SceneNodeID>
    ) -> Bool {
        guard visited.insert(rootSceneNodeID).inserted else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        guard let sceneNode = metadata.sceneNodes[rootSceneNodeID] else {
            return false
        }
        return sceneNode.childIDs.contains { childID in
            sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                visited: &visited
            )
        }
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
        let sum = reduce(Vector3D.zero) { partial, point in
            Vector3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let itemCount = Double(count)
        return Point3D(
            x: sum.x / itemCount,
            y: sum.y / itemCount,
            z: sum.z / itemCount
        )
    }
}
