import CoreGraphics
import RupaCore

struct ViewportIndependentCopyBodyDimensionAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyBodyDimensionAffordanceCandidate] {
        let index = ViewportIndependentCopyOutputSelectionIndex(
            metadata: document.productMetadata,
            scene: scene
        )
        let selectedOutputs = index.selectedOutputs(selection: selection)
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
    ) -> [ViewportIndependentCopyBodyDimensionAffordanceCandidate] {
        let items = editableItems(
            output: output,
            index: index,
            selection: selection
        )
        let entriesByFeatureID = dimensionEntriesByFeatureID(
            items: items,
            document: document
        )
        return items.flatMap { item in
            entriesByFeatureID[item.featureID.description, default: []].compactMap { entry in
                candidate(
                    entry: entry,
                    item: item,
                    output: output,
                    layout: layout
                )
            }
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

    private func dimensionEntriesByFeatureID(
        items: [ViewportSceneItem],
        document: DesignDocument
    ) -> [String: [ObjectDimensionSummaryResult.Entry]] {
        let targets = items.compactMap { item -> SelectionTarget? in
            guard let sceneNodeID = item.sceneNodeID else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID)
        }
        guard !targets.isEmpty else {
            return [:]
        }
        let summary: ObjectDimensionSummaryResult
        do {
            summary = try ObjectDimensionSummaryService().summarize(
                document: document,
                targets: targets
            )
        } catch {
            return [:]
        }
        return Dictionary(grouping: summary.entries, by: \.sourceFeatureID)
    }

    private func candidate(
        entry: ObjectDimensionSummaryResult.Entry,
        item: ViewportSceneItem,
        output: ViewportSelectedIndependentCopyOutput,
        layout: ViewportLayout
    ) -> ViewportIndependentCopyBodyDimensionAffordanceCandidate? {
        guard entry.sourceFeatureID == item.featureID.description,
              entry.resolvedMeters.isFinite,
              entry.resolvedMeters > 0.0 else {
            return nil
        }
        let descriptor: DimensionDescriptor
        switch (entry.sourceKind, entry.kind) {
        case (.box, .sizeX):
            descriptor = DimensionDescriptor(
                kind: .sizeX,
                label: "X",
                axisDirection: .unitX,
                baseModelPoint: Point3D(
                    x: Double(item.modelBounds.minX),
                    y: bodyCenterY(for: item),
                    z: Double(item.modelBounds.midY)
                )
            )
        case (.box, .sizeZ):
            descriptor = DimensionDescriptor(
                kind: .sizeZ,
                label: "Z",
                axisDirection: .unitZ,
                baseModelPoint: Point3D(
                    x: Double(item.modelBounds.midX),
                    y: bodyCenterY(for: item),
                    z: Double(item.modelBounds.minY)
                )
            )
        case (.cylinder, .radius):
            descriptor = DimensionDescriptor(
                kind: .radius,
                label: "R",
                axisDirection: .unitX,
                baseModelPoint: Point3D(
                    x: Double(item.modelBounds.midX),
                    y: bodyCenterY(for: item),
                    z: Double(item.modelBounds.midY)
                )
            )
        default:
            return nil
        }
        let transformedAxis = output.modelTransform.viewportTransformedVector(descriptor.axisDirection)
        let axisScale = transformedAxis.length
        guard axisScale.isFinite,
              axisScale > 1.0e-12 else {
            return nil
        }
        guard let geometry = ViewportPatternArrayLinearAxisAffordanceGeometry(
            baseProjectedPoint: layout.project(descriptor.baseModelPoint),
            axisDirection: transformedAxis,
            distanceMeters: entry.resolvedMeters * axisScale,
            layout: layout,
            viewportLength: 58.0
        ) else {
            return nil
        }
        return ViewportIndependentCopyBodyDimensionAffordanceCandidate(
            target: ViewportIndependentCopyBodyDimensionHandleTarget(
                sourceID: output.source.id,
                outputIndex: output.outputIndex,
                outputSceneNodeID: output.outputSceneNodeID,
                featureID: item.featureID,
                kind: descriptor.kind,
                label: descriptor.label,
                valueScale: axisScale,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func bodyCenterY(for item: ViewportSceneItem) -> Double {
        guard case .body(let component) = item.kind,
              component.yMinMeters.isFinite,
              component.yMaxMeters.isFinite else {
            return 0.0
        }
        return (component.yMinMeters + component.yMaxMeters) * 0.5
    }
}

private struct DimensionDescriptor {
    var kind: ViewportIndependentCopyBodyDimensionKind
    var label: String
    var axisDirection: Vector3D
    var baseModelPoint: Point3D
}

struct ViewportIndependentCopyBodyDimensionAffordanceCandidate: Equatable {
    var target: ViewportIndependentCopyBodyDimensionHandleTarget
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry
}

struct ViewportIndependentCopyBodyDimensionHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
    var outputSceneNodeID: SceneNodeID
    var featureID: FeatureID
    var kind: ViewportIndependentCopyBodyDimensionKind
    var label: String
    var valueScale: Double
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry

    var identity: ViewportIndependentCopyBodyDimensionHandleIdentity {
        ViewportIndependentCopyBodyDimensionHandleIdentity(
            sourceID: sourceID,
            outputIndex: outputIndex,
            featureID: featureID,
            kind: kind
        )
    }
}

struct ViewportIndependentCopyBodyDimensionHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var outputIndex: Int
    var featureID: FeatureID
    var kind: ViewportIndependentCopyBodyDimensionKind
}
