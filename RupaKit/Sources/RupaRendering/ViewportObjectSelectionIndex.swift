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
            guard let featureID = target.sourceFeatureID ?? document.productMetadata.sceneNodes[target.sourceSceneNodeID ?? target.sceneNodeID]?.reference?.featureID else {
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
        objectTargets.contains { target in
            target.sceneNodeID == item.sceneNodeID && (target.occurrenceID == nil || target.occurrenceID == item.occurrenceID)
        }
    }

    func selectedBodySourceItems(in scene: ViewportScene) -> [ViewportSceneItem] {
        scene.items.filter { item in
            guard item.kind.selectableKind == .body else { return false }
            return sourceTargets.contains { sourceTarget in
                let target = sourceTarget.target
                return item.featureID == sourceTarget.featureID && item.sceneNodeID == target.sceneNodeID &&
                    (target.occurrenceID == nil || target.occurrenceID == item.occurrenceID) &&
                    (target.sourceBodyID == nil || target.sourceBodyID == item.sourceBodyID)
            }
        }
    }

    func exactTarget(for item: ViewportSceneItem) -> SelectionTarget? {
        guard let sceneNodeID = item.sceneNodeID else {
            return nil
        }
        return objectTargets.first { $0.sceneNodeID == sceneNodeID && ($0.occurrenceID == nil || $0.occurrenceID == item.occurrenceID) }
    }

    private struct SourceTarget: Equatable, Sendable {
        let featureID: FeatureID
        let target: SelectionTarget
    }
}
