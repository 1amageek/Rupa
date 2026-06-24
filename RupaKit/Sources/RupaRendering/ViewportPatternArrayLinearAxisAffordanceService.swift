import CoreGraphics
import RupaCore

struct ViewportPatternArrayLinearAxisAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayLinearAxisAffordanceCandidate] {
        let metadata = document.productMetadata
        let sourceIDs = selectedPatternArraySourceIDs(
            selection: selection,
            metadata: metadata
        )
        guard !sourceIDs.isEmpty else {
            return []
        }
        return sourceIDs.flatMap { sourceID in
            candidates(
                sourceID: sourceID,
                metadata: metadata,
                scene: scene,
                layout: layout
            )
        }
    }

    private func candidates(
        sourceID: PatternArraySourceID,
        metadata: ProductMetadata,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayLinearAxisAffordanceCandidate] {
        guard let source = metadata.patternArrays[sourceID],
              case .rectangular(let rectangular) = source.distribution,
              let baseProjectedPoint = sourceBaseProjectedPoint(
                  source: source,
                  metadata: metadata,
                  scene: scene,
                  layout: layout
              ) else {
            return []
        }

        var result: [ViewportPatternArrayLinearAxisAffordanceCandidate] = []
        if let candidate = candidate(
            sourceID: sourceID,
            axisSlot: .first,
            axis: rectangular.firstAxis,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
        ) {
            result.append(candidate)
        }
        if let secondAxis = rectangular.secondAxis,
           let candidate = candidate(
               sourceID: sourceID,
               axisSlot: .second,
               axis: secondAxis,
               baseProjectedPoint: baseProjectedPoint,
               layout: layout
           ) {
            result.append(candidate)
        }
        return result
    }

    private func candidate(
        sourceID: PatternArraySourceID,
        axisSlot: ViewportPatternArrayLinearAxisSlot,
        axis: PatternArrayLinearAxis,
        baseProjectedPoint: CGPoint,
        layout: ViewportLayout
    ) -> ViewportPatternArrayLinearAxisAffordanceCandidate? {
        guard let distanceMeters = constantLengthMeters(axis.distance),
              let geometry = ViewportPatternArrayLinearAxisAffordanceGeometry(
                  baseProjectedPoint: baseProjectedPoint,
                  axisDirection: axis.direction,
                  distanceMeters: distanceMeters,
                  layout: layout
              ) else {
            return nil
        }
        return ViewportPatternArrayLinearAxisAffordanceCandidate(
            target: ViewportPatternArrayLinearAxisHandleTarget(
                sourceID: sourceID,
                axisSlot: axisSlot,
                distanceMode: axis.distanceMode,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func selectedPatternArraySourceIDs(
        selection: SelectionModel,
        metadata: ProductMetadata
    ) -> [PatternArraySourceID] {
        var sourceIDs: [PatternArraySourceID] = []
        var seenSourceIDs: Set<PatternArraySourceID> = []
        for target in selection.selectedTargets {
            guard let sourceID = patternArraySourceID(
                containing: target.sceneNodeID,
                metadata: metadata
            ),
                  seenSourceIDs.insert(sourceID).inserted else {
                continue
            }
            sourceIDs.append(sourceID)
        }
        return sourceIDs
    }

    private func patternArraySourceID(
        containing sceneNodeID: SceneNodeID,
        metadata: ProductMetadata
    ) -> PatternArraySourceID? {
        for source in metadata.patternArrays.values {
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                continue
            }
            if sceneNodeID == source.rootSceneNodeID {
                return source.id
            }
            if rootNode.childIDs.contains(where: { outputSceneNodeID in
                sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID,
                    metadata: metadata
                )
            }) {
                return source.id
            }
        }
        return nil
    }

    private func sourceBaseProjectedPoint(
        source: PatternArraySource,
        metadata: ProductMetadata,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> CGPoint? {
        if let definition = metadata.componentDefinitions[source.definitionID] {
            let sourceRootIDs = Set(
                definition.rootSceneNodeIDs.flatMap { rootID in
                    sceneSubtreeIDs(rootedAt: rootID, metadata: metadata)
                }
            )
            let sourceCenters = scene.items.compactMap { item -> CGPoint? in
                guard let sceneNodeID = item.sceneNodeID,
                      sourceRootIDs.contains(sceneNodeID),
                      item.componentInstanceID == nil else {
                    return nil
                }
                return itemProjectedCenter(item, layout: layout)
            }
            if let center = average(sourceCenters) {
                return center
            }
        }

        let outputRootIDs = Set(outputRootSceneNodeIDs(source: source, metadata: metadata).prefix(1))
        let outputCenters = scene.items.compactMap { item -> CGPoint? in
            guard let sceneNodeID = item.sceneNodeID,
                  outputRootIDs.contains(sceneNodeID) else {
                return nil
            }
            return itemProjectedCenter(item, layout: layout)
        }
        return average(outputCenters)
    }

    private func outputRootSceneNodeIDs(
        source: PatternArraySource,
        metadata: ProductMetadata
    ) -> [SceneNodeID] {
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

    private func itemProjectedCenter(
        _ item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGPoint {
        if let projection = layout.bodyProjection(for: item) {
            return projection.center
        }
        return layout.projectedFootprint(item.modelBounds).center
    }

    private func average(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else {
            return nil
        }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }

    private func sceneSubtreeIDs(
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

    private func appendSceneSubtreeIDs(
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

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        metadata: ProductMetadata
    ) -> Bool {
        var visited: Set<SceneNodeID> = []
        return sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            metadata: metadata,
            visited: &visited
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
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
                metadata: metadata,
                visited: &visited
            )
        }
    }

    private func constantLengthMeters(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > 0.0 else {
            return nil
        }
        return quantity.value
    }
}

struct ViewportPatternArrayLinearAxisAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayLinearAxisHandleTarget
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry
}

struct ViewportPatternArrayLinearAxisHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var axisSlot: ViewportPatternArrayLinearAxisSlot
    var distanceMode: PatternArrayDistanceMode
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry

    var identity: ViewportPatternArrayLinearAxisHandleIdentity {
        ViewportPatternArrayLinearAxisHandleIdentity(
            sourceID: sourceID,
            axisSlot: axisSlot
        )
    }

    var distanceModeTitle: String {
        switch distanceMode {
        case .spacing:
            "Spacing"
        case .extent:
            "Extent"
        }
    }
}

struct ViewportPatternArrayLinearAxisHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var axisSlot: ViewportPatternArrayLinearAxisSlot
}
