import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Resolves current topology without changing the source. The command store
    /// owns candidate evaluation and rollback of the returned transaction.
    public func prepareBodyEdgeTreatment(
        name: String,
        target: SelectionTarget,
        treatment: BodyEdgeTreatment,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureGraphTransaction {
        let name = try normalizedMetadataName(name, owner: "Edge treatment")
        guard case .edge(let component) = target.component,
              let subshapeID = component.generatedTopologySubshapeID,
              let node = productMetadata.sceneNodes[target.sceneNodeID],
              !node.isLocked,
              node.reference?.kind == .body,
              let sourceID = node.reference?.featureID,
              node.object?.sourceFeatureID == sourceID else {
            throw EditorError(code: .commandInvalid,
                message: "Edge treatment requires a generated CAD edge on an unlocked source body.")
        }
        var parentID: SceneNodeID?
        var visited: Set<SceneNodeID> = [node.id]
        var childID = node.id
        while let parent = productMetadata.sceneNodes.values.first(where: { $0.childIDs.contains(childID) }) {
            guard visited.insert(parent.id).inserted, !parent.isLocked else {
                throw EditorError(code: .commandInvalid, message: "Edge treatment cannot edit a locked or cyclic hierarchy.")
            }
            if parentID == nil { parentID = parent.id }
            childID = parent.id
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, metricPolicy: .omit
        )
        guard let entry = topology.entries.first(where: {
            $0.subshapeID == GeneratedSubshapeIdentity.string(for: subshapeID)
                && $0.kind == .edge && $0.sceneNodeID == node.id.description
        }), let edge = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved,
                message: "The selected edge is absent from the current body topology. Select the edge again.")
        }
        let operation: FeatureOperation
        let amount: CADExpression
        switch treatment {
        case .fillet(let radius):
            amount = radius
            operation = .fillet(.init(target: .init(featureID: sourceID), edges: [edge], radius: radius))
        case .chamfer(let distance):
            amount = distance
            operation = .chamfer(.init(target: .init(featureID: sourceID), edges: [edge], distance: distance))
        case .g2Blend(let distance):
            amount = distance
            operation = .g2Blend(.init(target: .init(featureID: sourceID), edges: [edge], distance: distance))
        }
        guard try resolvedPositiveLengthValue(amount, owner: "Edge treatment amount") > modelingSettings.tolerance.distance else {
            throw EditorError(code: .commandInvalid, message: "Edge treatment amount must exceed modeling tolerance.")
        }
        let feature = try FeatureNodeFactory.make(
            operation: operation, id: FeatureID(), in: cadDocument, tolerance: modelingSettings.tolerance
        )
        var namedFeature = feature
        namedFeature.name = name
        return FeatureGraphTransaction(features: [namedFeature], presentations: [
            FeaturePresentation(featureID: feature.id, sceneNodeID: SceneNodeID(),
                parentSceneNodeID: parentID, name: name,
                kind: .body(sourceSection: nil, typeID: nil, geometryRole: .solid, properties: .init()),
                localTransform: node.localTransform, materialID: node.materialID)
        ], primaryFeatureID: feature.id)
    }
}
