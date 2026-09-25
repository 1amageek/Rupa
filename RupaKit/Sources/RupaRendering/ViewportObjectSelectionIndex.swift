import RupaCore
import RupaViewportScene
import SwiftCAD

/// The selected object targets and the body items they select.
///
/// A feature is presented by at most one scene node, so an object target names its body item
/// exactly by scene node; there is no feature-level fallback or de-duplication between targets.
public struct ViewportObjectSelectionIndex: Sendable {
    public let objectTargets: [SelectionTarget]
    public let sceneNodeIDs: Set<SceneNodeID>
    public let featureIDs: Set<FeatureID>

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
        let sourceTargets = objectTargets.compactMap { target -> SourceTarget? in
            guard let featureID = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID else {
                return nil
            }
            return SourceTarget(featureID: featureID, target: target)
        }
        self.objectTargets = objectTargets
        self.sceneNodeIDs = Set(objectTargets.map(\.sceneNodeID))
        self.featureIDs = Set(sourceTargets.map(\.featureID))
        self.sourceTargets = sourceTargets
    }

    func contains(_ item: ViewportSceneItem) -> Bool {
        item.sceneNodeID.map(sceneNodeIDs.contains) ?? false
    }

    func selectedBodySourceItems(in scene: ViewportScene) -> [ViewportSceneItem] {
        sourceTargets.compactMap { sourceTarget in
            scene.items.first { item in
                item.sceneNodeID == sourceTarget.target.sceneNodeID
                    && item.featureID == sourceTarget.featureID
                    && item.kind.selectableKind == .body
            }
        }
    }

    func exactTarget(for item: ViewportSceneItem) -> SelectionTarget? {
        guard let sceneNodeID = item.sceneNodeID else {
            return nil
        }
        return objectTargets.first { $0.sceneNodeID == sceneNodeID }
    }

    private struct SourceTarget: Equatable, Sendable {
        let featureID: FeatureID
        let target: SelectionTarget
    }
}
