import CoreGraphics
import RupaCore

struct ViewportIndependentCopyExtrudeDistanceAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyExtrudeDistanceAffordanceCandidate] {
        let index = ViewportIndependentCopyExtrudeDistanceOutputIndex(
            metadata: document.productMetadata,
            scene: scene
        )
        let selectedOutputs = index.selectedOutputs(
            selection: selection
        )
        guard !selectedOutputs.isEmpty else {
            return []
        }
        return selectedOutputs.flatMap { output in
            candidates(
                output: output,
                index: index,
                document: document,
                selection: selection,
                layout: layout
            )
        }
    }

    private func candidates(
        output: SelectedIndependentCopyOutput,
        index: ViewportIndependentCopyExtrudeDistanceOutputIndex,
        document: DesignDocument,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyExtrudeDistanceAffordanceCandidate] {
        editableItems(
            output: output,
            index: index,
            selection: selection
        ).compactMap { item in
            candidate(
                item: item,
                output: output,
                document: document,
                layout: layout
            )
        }
    }

    private func editableItems(
        output: SelectedIndependentCopyOutput,
        index: ViewportIndependentCopyExtrudeDistanceOutputIndex,
        selection: SelectionModel
    ) -> [ViewportSceneItem] {
        let selectedSceneNodeIDs = Set(selection.selectedSceneNodeIDs)
        let outputItems = index.bodyItems(
            rootedAt: output.outputSceneNodeID,
            ownedFeatureIDs: Set(output.source.outputFeatureIDs)
        )
        let selectedItems = outputItems.filter { item in
            guard let sceneNodeID = item.sceneNodeID else {
                return false
            }
            return selectedSceneNodeIDs.contains(sceneNodeID)
        }
        if !selectedItems.isEmpty {
            return selectedItems
        }
        return outputItems
    }

    private func candidate(
        item: ViewportSceneItem,
        output: SelectedIndependentCopyOutput,
        document: DesignDocument,
        layout: ViewportLayout
    ) -> ViewportIndependentCopyExtrudeDistanceAffordanceCandidate? {
        guard let feature = document.cadDocument.designGraph.nodes[item.featureID],
              case .extrude(let extrude) = feature.operation,
              let axisDirection = axisDirection(for: extrude, document: document),
              let distanceMeters = resolvedLengthMeters(
                  extrude.distance,
                  document: document
              ),
              let geometry = ViewportPatternArrayLinearAxisAffordanceGeometry(
                  baseProjectedPoint: baseProjectedPoint(for: item, layout: layout),
                  axisDirection: axisDirection,
                  distanceMeters: distanceMeters,
                  layout: layout,
                  viewportLength: 70.0
              ) else {
            return nil
        }
        return ViewportIndependentCopyExtrudeDistanceAffordanceCandidate(
            target: ViewportIndependentCopyExtrudeDistanceHandleTarget(
                sourceID: output.source.id,
                outputIndex: output.outputIndex,
                outputSceneNodeID: output.outputSceneNodeID,
                featureID: item.featureID,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func resolvedLengthMeters(
        _ expression: CADExpression,
        document: DesignDocument
    ) -> Double? {
        do {
            let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
            guard quantity.kind == .length,
                  quantity.value.isFinite,
                  quantity.value > 0.0 else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    private func axisDirection(
        for extrude: ExtrudeFeature,
        document: DesignDocument
    ) -> Vector3D? {
        switch extrude.direction {
        case .normal, .symmetric:
            return profileNormal(
                featureID: extrude.profile.featureID,
                document: document
            )
        case .vector(let vector):
            return vector
        }
    }

    private func profileNormal(
        featureID: FeatureID,
        document: DesignDocument
    ) -> Vector3D? {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = feature.operation else {
            return nil
        }
        return normal(for: sketch.plane)
    }

    private func normal(for plane: SketchPlane) -> Vector3D? {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case .plane(let plane):
            let normal = plane.normal
            guard normal.length.isFinite,
                  normal.length > 1.0e-12 else {
                return nil
            }
            return normal
        }
    }

    private func baseProjectedPoint(
        for item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGPoint {
        if let projection = layout.bodyProjection(for: item) {
            return projection.center
        }
        return layout.projectedFootprint(item.modelBounds).center
    }

}

private struct SelectedIndependentCopyOutput: Equatable {
    var source: PatternArraySource
    var outputIndex: Int
    var outputSceneNodeID: SceneNodeID
}

private struct ViewportIndependentCopyOutputIdentity: Hashable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
}

private struct ViewportIndependentCopyExtrudeDistanceOutputIndex {
    private var outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]]
    private var outputsByIdentity: [ViewportIndependentCopyOutputIdentity: SelectedIndependentCopyOutput]
    private var subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>]
    private var bodyItems: [ViewportSceneItem]

    init(
        metadata: ProductMetadata,
        scene: ViewportScene
    ) {
        var records: [SelectedIndependentCopyOutput] = []
        let sources = metadata.patternArrays.values.sorted {
            $0.id.description < $1.id.description
        }
        for source in sources where source.outputMode == .independentCopy {
            for (outputIndex, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
                records.append(SelectedIndependentCopyOutput(
                    source: source,
                    outputIndex: outputIndex,
                    outputSceneNodeID: outputSceneNodeID
                ))
            }
        }

        var subtreeIDsByOutputSceneNodeID: [SceneNodeID: Set<SceneNodeID>] = [:]
        var outputIDsBySceneNodeID: [SceneNodeID: [ViewportIndependentCopyOutputIdentity]] = [:]
        var outputsByIdentity: [ViewportIndependentCopyOutputIdentity: SelectedIndependentCopyOutput] = [:]
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

    func selectedOutputs(selection: SelectionModel) -> [SelectedIndependentCopyOutput] {
        var selected: [SelectedIndependentCopyOutput] = []
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

struct ViewportIndependentCopyExtrudeDistanceAffordanceCandidate: Equatable {
    var target: ViewportIndependentCopyExtrudeDistanceHandleTarget
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry
}

struct ViewportIndependentCopyExtrudeDistanceHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
    var outputSceneNodeID: SceneNodeID
    var featureID: FeatureID
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry

    var identity: ViewportIndependentCopyExtrudeDistanceHandleIdentity {
        ViewportIndependentCopyExtrudeDistanceHandleIdentity(
            sourceID: sourceID,
            outputIndex: outputIndex,
            featureID: featureID
        )
    }
}

struct ViewportIndependentCopyExtrudeDistanceHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
    var featureID: FeatureID
}
