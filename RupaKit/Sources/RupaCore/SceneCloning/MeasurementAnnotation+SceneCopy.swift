import SwiftCAD
import RupaCoreTypes

extension MeasurementAnnotation {
    /// This measurement as it belongs to a copy: its annotation node, and every anchor on copied
    /// geometry, name the copies; anchors on geometry outside the copy keep measuring it. World
    /// positions move by `placement`, the motion that carries the copy to where it lands. Anchor
    /// occurrences on copied nodes are left for the caller to resolve in the new scene.
    func copied(
        sceneNodes sceneIDMap: [SceneNodeID: SceneNodeID],
        features featureIDMap: [FeatureID: FeatureID],
        placement: Transform3D
    ) throws -> MeasurementAnnotation {
        var copy = self
        copy.id = MeasurementAnnotationID()
        copy.sceneNodeID = sceneNodeID.flatMap { sceneIDMap[$0] }
        copy.anchors = try anchors.map { try $0.copied(sceneNodes: sceneIDMap, features: featureIDMap, placement: placement) }
        copy.labelPosition = try labelPosition.map { try placement.applied(to: $0) }
        if let axis = placementAxis {
            let moved = try placement.applyingLinearPart(to: axis)
            copy.placementAxis = try moved.normalized(tolerance: ModelingTolerance.standard.distance)
        }
        return copy
    }
}

extension MeasurementAnchor {
    /// Whether the anchor sits on a node of the copy, and so follows it.
    func isCopied(with sceneIDMap: [SceneNodeID: SceneNodeID]) -> Bool {
        let nodes = [sceneNodeID, topologyReference?.sceneNodeID, topologyEdgeParameter?.sceneNodeID].compactMap { $0 }
        return nodes.contains { sceneIDMap[$0] != nil }
    }

    fileprivate func copied(
        sceneNodes sceneIDMap: [SceneNodeID: SceneNodeID],
        features featureIDMap: [FeatureID: FeatureID],
        placement: Transform3D
    ) throws -> MeasurementAnchor {
        var copy = self
        if kind == .worldPoint, sceneNodeID == nil, let worldPoint {
            copy.worldPoint = try placement.applied(to: worldPoint)
            return copy
        }
        guard isCopied(with: sceneIDMap) else { return copy }
        copy.sceneNodeID = sceneNodeID.map { sceneIDMap[$0] ?? $0 }
        // The copy's occurrence path differs from the source's; the caller resolves it anew.
        copy.occurrenceID = nil
        if let worldPoint { copy.worldPoint = try placement.applied(to: worldPoint) }
        if var reference = sketchReference {
            reference.featureID = featureIDMap[reference.featureID] ?? reference.featureID
            copy.sketchReference = reference
        }
        if var reference = sketchCurveParameter {
            reference.featureID = featureIDMap[reference.featureID] ?? reference.featureID
            copy.sketchCurveParameter = reference
        }
        if var reference = topologyReference {
            reference.sceneNodeID = sceneIDMap[reference.sceneNodeID] ?? reference.sceneNodeID
            reference.component = Self.copied(reference.component, features: featureIDMap)
            reference.subshapeID = Self.copied(subshapeString: reference.subshapeID, features: featureIDMap)
            reference.referenceID = nil
            copy.topologyReference = reference
        }
        if var reference = topologyEdgeParameter {
            reference.sceneNodeID = sceneIDMap[reference.sceneNodeID] ?? reference.sceneNodeID
            reference.component = Self.copied(reference.component, features: featureIDMap)
            reference.subshapeID = Self.copied(subshapeString: reference.subshapeID, features: featureIDMap)
            reference.referenceID = nil
            copy.topologyEdgeParameter = reference
        }
        return copy
    }

    /// A generated subshape of a copied feature keeps its role and ordinal under the copy's ID.
    private static func copied(subshape: SubshapeID, features: [FeatureID: FeatureID]) -> SubshapeID {
        guard let feature = features[subshape.featureID] else { return subshape }
        return SubshapeID(featureID: feature, role: subshape.role, ordinal: subshape.ordinal)
    }

    private static func copied(subshapeString: String, features: [FeatureID: FeatureID]) -> String {
        guard let subshape = GeneratedSubshapeIdentity.subshapeID(from: subshapeString) else { return subshapeString }
        return GeneratedSubshapeIdentity.string(for: copied(subshape: subshape, features: features))
    }

    private static func copied(_ component: SelectionComponent, features: [FeatureID: FeatureID]) -> SelectionComponent {
        func mapped(_ id: SelectionComponentID) -> SelectionComponentID {
            guard let subshape = id.generatedTopologySubshapeID else { return id }
            return .generatedTopology(copied(subshape: subshape, features: features))
        }
        switch component {
        case .face(let id): return .face(mapped(id))
        case .edge(let id): return .edge(mapped(id))
        case .vertex(let id): return .vertex(mapped(id))
        case .object, .sketchEntity, .region, .constructionPlane: return component
        }
    }
}
