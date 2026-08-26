import RupaCore
import RupaViewportScene
import SwiftCAD

public struct ViewportObjectSelectionIndex: Sendable {
    public let objectTargets: [SelectionTarget]
    public let sceneNodeIDs: Set<SceneNodeID>
    public let featureIDs: Set<FeatureID>

    private let featureIDBySceneNodeID: [SceneNodeID: FeatureID]
    private let targetCountByFeatureID: [FeatureID: Int]
    private let sourceTargets: [SourceTarget]

    public init(
        document: DesignDocument,
        selection: SelectionModel
    ) {
        let objectTargets = selection.selectedTargets.filter { target in
            if case .object = target.component {
                return true
            }
            return false
        }
        var featureIDBySceneNodeID: [SceneNodeID: FeatureID] = [:]
        featureIDBySceneNodeID.reserveCapacity(objectTargets.count)
        for target in objectTargets {
            if let featureID = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID {
                featureIDBySceneNodeID[target.sceneNodeID] = featureID
            }
        }
        var indexedFeatureIDs: Set<FeatureID> = []
        var targetCountByFeatureID: [FeatureID: Int] = [:]
        for featureID in featureIDBySceneNodeID.values {
            targetCountByFeatureID[featureID, default: 0] += 1
        }
        var reversedSourceTargets: [SourceTarget] = []
        reversedSourceTargets.reserveCapacity(featureIDBySceneNodeID.count)
        for target in objectTargets.reversed() {
            guard let featureID = featureIDBySceneNodeID[target.sceneNodeID],
                  indexedFeatureIDs.insert(featureID).inserted else {
                continue
            }
            reversedSourceTargets.append(SourceTarget(featureID: featureID, target: target))
        }
        self.objectTargets = objectTargets
        self.sceneNodeIDs = Set(objectTargets.map(\.sceneNodeID))
        self.featureIDs = Set(featureIDBySceneNodeID.values)
        self.featureIDBySceneNodeID = featureIDBySceneNodeID
        self.targetCountByFeatureID = targetCountByFeatureID
        self.sourceTargets = Array(reversedSourceTargets.reversed())
    }

    func contains(_ item: ViewportSceneItem) -> Bool {
        if let sceneNodeID = item.sceneNodeID {
            return sceneNodeIDs.contains(sceneNodeID)
        }
        return featureIDs.contains(item.featureID)
    }

    func selectedBodySourceItems(in scene: ViewportScene) -> [ViewportSceneItem] {
        var result: [ViewportSceneItem] = []
        result.reserveCapacity(min(sourceTargets.count, scene.items.count))

        for sourceTarget in sourceTargets {
            guard let item = exactBodyItem(
                    sceneNodeID: sourceTarget.target.sceneNodeID,
                    featureID: sourceTarget.featureID,
                    allowsFeatureFallback: targetCountByFeatureID[sourceTarget.featureID] == 1,
                    in: scene
                  ) else {
                continue
            }
            result.append(item)
        }
        return result
    }

    func exactTarget(for item: ViewportSceneItem) -> SelectionTarget? {
        if let sceneNodeID = item.sceneNodeID {
            return objectTargets.first { $0.sceneNodeID == sceneNodeID }
        }
        guard targetCountByFeatureID[item.featureID] == 1,
              let sourceTarget = sourceTargets.first(where: { $0.featureID == item.featureID }) else {
            return nil
        }
        return sourceTarget.target
    }

    private func exactBodyItem(
        sceneNodeID: SceneNodeID,
        featureID: FeatureID,
        allowsFeatureFallback: Bool,
        in scene: ViewportScene
    ) -> ViewportSceneItem? {
        if let exactItem = scene.items.first(where: { item in
            item.sceneNodeID == sceneNodeID
                && item.featureID == featureID
                && item.kind.selectableKind == .body
        }) {
            return exactItem
        }
        guard allowsFeatureFallback else {
            return nil
        }
        return scene.items.first { item in
            item.sceneNodeID == nil
                && item.featureID == featureID
                && item.kind.selectableKind == .body
        }
    }

    private struct SourceTarget: Equatable, Sendable {
        let featureID: FeatureID
        let target: SelectionTarget
    }
}
