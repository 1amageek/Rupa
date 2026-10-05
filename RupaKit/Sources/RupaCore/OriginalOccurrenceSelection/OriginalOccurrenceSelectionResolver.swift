import SwiftCAD
import RupaCoreTypes

public struct OriginalOccurrenceSelectionResolver: Sendable {
    private let occurrences: [SceneOccurrenceID: SceneNodeHierarchy.Occurrence]
    private let metadata: ProductMetadata

    public init(document: DesignDocument) throws {
        metadata = document.productMetadata
        var resolved: [SceneOccurrenceID: SceneNodeHierarchy.Occurrence] = [:]
        for occurrence in try SceneNodeHierarchy(metadata: metadata).resolvedOccurrences() {
            guard resolved.updateValue(occurrence, forKey: occurrence.id) == nil else {
                throw EditorError(code: .referenceUnresolved, message: "Original hierarchy produced a duplicate occurrence identity.")
            }
        }
        occurrences = resolved
    }

    public func resolve(_ target: SelectionTarget) throws -> SceneNodeHierarchy.Occurrence? {
        guard let id = target.occurrenceID else {
            guard target.sourceSceneNodeID == nil, target.sourceFeatureID == nil, target.sourceBodyID == nil else {
                throw EditorError(code: .referenceUnresolved, message: "Selection source authority has no occurrence identity.")
            }
            return nil
        }
        guard let sourceID = target.sourceSceneNodeID, let occurrence = occurrences[id],
              occurrence.isVisible, occurrence.sceneNodeID == target.sceneNodeID,
              occurrence.sourceSceneNodeID == sourceID,
              let source = metadata.sceneNodes[sourceID],
              target.sourceFeatureID == nil || source.reference?.featureID == target.sourceFeatureID else {
            throw EditorError(code: .referenceUnresolved, message: "Selection occurrence no longer resolves its original visible source body.")
        }
        return occurrence
    }

    public func target(for id: SceneOccurrenceID, component: SelectionComponent = .object) throws -> SelectionTarget {
        guard let occurrence = occurrences[id], occurrence.isVisible,
              let source = metadata.sceneNodes[occurrence.sourceSceneNodeID] else {
            throw EditorError(code: .referenceUnresolved, message: "Selection occurrence is missing or hidden.")
        }
        return SelectionTarget(sceneNodeID: occurrence.sceneNodeID, component: component,
            occurrenceID: id, sourceSceneNodeID: occurrence.sourceSceneNodeID, sourceFeatureID: source.reference?.featureID)
    }
}
