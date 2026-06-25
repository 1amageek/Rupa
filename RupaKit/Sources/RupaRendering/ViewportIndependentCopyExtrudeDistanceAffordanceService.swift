import CoreGraphics
import RupaCore

struct ViewportIndependentCopyExtrudeDistanceAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyExtrudeDistanceAffordanceCandidate] {
        let index = ViewportIndependentCopyOutputSelectionIndex(
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
        output: ViewportSelectedIndependentCopyOutput,
        index: ViewportIndependentCopyOutputSelectionIndex,
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
        output: ViewportSelectedIndependentCopyOutput,
        index: ViewportIndependentCopyOutputSelectionIndex,
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
        output: ViewportSelectedIndependentCopyOutput,
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
