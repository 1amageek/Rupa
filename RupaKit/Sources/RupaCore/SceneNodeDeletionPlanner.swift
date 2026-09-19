import Foundation
import SwiftCAD
import RupaCoreTypes

/// Everything one delete takes with it.
///
/// Deleting is never confined to what was picked. A body is a feature, features feed other features,
/// and the browser rows standing for those results describe geometry that stops existing the moment
/// its source does. The plan names the whole set before anything is removed so the caller can say how
/// far the delete reached, and so the removals can be ordered to keep the document valid at each step.
public struct SceneNodeDeletionPlan: Equatable, Sendable {
    /// The scene nodes to remove, children before their parents.
    public var sceneNodeIDs: [SceneNodeID]
    /// The features to remove, dependents before the features they consume.
    public var featureIDs: [FeatureID]
    /// The component instances the removed nodes stood for.
    public var componentInstanceIDs: [ComponentInstanceID]
    /// The construction planes the removed nodes stood for.
    public var constructionPlaneIDs: [ConstructionPlaneSourceID]
    /// The material bindings that pointed at a removed node.
    public var topologyMaterialBindingIDs: [TopologyMaterialBinding.ID]
    /// The measurements that measured something being removed.
    public var measurementIDs: [MeasurementAnnotationID]
    /// The bridge curve sources whose sketch is being removed.
    public var bridgeCurveSourceIDs: [BridgeCurveSourceID]
    /// The joined curve sources whose sketch is being removed.
    public var joinedCurveSourceIDs: [JoinedCurveSourceID]
    /// The joined curve group sources whose sketch is being removed.
    public var joinedCurveGroupSourceIDs: [JoinedCurveGroupSourceID]
    /// The scene nodes the caller did not name, reached because they depend on one that was named.
    public var dependentSceneNodeIDs: [SceneNodeID]

    public init(
        sceneNodeIDs: [SceneNodeID],
        featureIDs: [FeatureID],
        componentInstanceIDs: [ComponentInstanceID],
        constructionPlaneIDs: [ConstructionPlaneSourceID],
        topologyMaterialBindingIDs: [TopologyMaterialBinding.ID],
        measurementIDs: [MeasurementAnnotationID],
        bridgeCurveSourceIDs: [BridgeCurveSourceID],
        joinedCurveSourceIDs: [JoinedCurveSourceID],
        joinedCurveGroupSourceIDs: [JoinedCurveGroupSourceID],
        dependentSceneNodeIDs: [SceneNodeID]
    ) {
        self.sceneNodeIDs = sceneNodeIDs
        self.featureIDs = featureIDs
        self.componentInstanceIDs = componentInstanceIDs
        self.constructionPlaneIDs = constructionPlaneIDs
        self.topologyMaterialBindingIDs = topologyMaterialBindingIDs
        self.measurementIDs = measurementIDs
        self.bridgeCurveSourceIDs = bridgeCurveSourceIDs
        self.joinedCurveSourceIDs = joinedCurveSourceIDs
        self.joinedCurveGroupSourceIDs = joinedCurveGroupSourceIDs
        self.dependentSceneNodeIDs = dependentSceneNodeIDs
    }
}

/// Works out what deleting a browser selection removes, and in which order.
///
/// The arithmetic is kept out of the document for the same reason the grouping and ungrouping
/// planners are: the reachability question has enough cases — subtrees, feature dependents, the scene
/// nodes standing for those dependents — that it is worth testing without a document around it.
public struct SceneNodeDeletionPlanner: Sendable {
    public init() {}

    /// The plan for deleting `ids`.
    ///
    /// Throws rather than trimming the request when part of it cannot be deleted. A delete that
    /// quietly skipped the locked member of a selection would leave the user believing the object is
    /// gone, and the next command would be issued against a scene they no longer recognise.
    public func plan(
        metadata: ProductMetadata,
        designGraph: DesignGraph,
        ids: [SceneNodeID]
    ) throws -> SceneNodeDeletionPlan {
        guard ids.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Deleting requires at least one scene node."
            )
        }
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        let requestedIDs = Set(ids)

        var removedSceneNodeIDs: Set<SceneNodeID> = []
        var removedFeatureIDs: Set<FeatureID> = []
        var pendingSceneNodeIDs = ids
        var pendingFeatureIDs: [FeatureID] = []

        // Scene nodes and features pull each other in, so neither pass alone reaches a fixed point:
        // a feature's dependent has a browser row, and that row's subtree can hold further features.
        while pendingSceneNodeIDs.isEmpty == false || pendingFeatureIDs.isEmpty == false {
            while let sceneNodeID = pendingSceneNodeIDs.popLast() {
                guard let node = metadata.sceneNodes[sceneNodeID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Scene node \(sceneNodeID.description) is missing."
                    )
                }
                guard removedSceneNodeIDs.contains(sceneNodeID) == false else {
                    continue
                }
                try requireDeletable(
                    node,
                    isRequested: requestedIDs.contains(sceneNodeID),
                    hierarchy: hierarchy,
                    metadata: metadata
                )
                for subtreeID in hierarchy.subtreeIDs(of: sceneNodeID) {
                    guard removedSceneNodeIDs.insert(subtreeID).inserted,
                          let subtreeNode = metadata.sceneNodes[subtreeID] else {
                        continue
                    }
                    if let featureID = subtreeNode.reference?.featureID {
                        pendingFeatureIDs.append(featureID)
                    }
                }
            }

            while let featureID = pendingFeatureIDs.popLast() {
                guard removedFeatureIDs.insert(featureID).inserted else {
                    continue
                }
                guard designGraph.nodes[featureID] != nil else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Feature \(featureID.description) is missing."
                    )
                }
                for dependency in designGraph.dependencies where dependency.source == featureID {
                    pendingFeatureIDs.append(dependency.target)
                }
            }

            for (sceneNodeID, node) in metadata.sceneNodes {
                guard let featureID = node.reference?.featureID,
                      removedFeatureIDs.contains(featureID),
                      removedSceneNodeIDs.contains(sceneNodeID) == false else {
                    continue
                }
                pendingSceneNodeIDs.append(sceneNodeID)
            }
        }

        return SceneNodeDeletionPlan(
            sceneNodeIDs: orderedSceneNodeIDs(removedSceneNodeIDs, hierarchy: hierarchy),
            featureIDs: orderedFeatureIDs(removedFeatureIDs, designGraph: designGraph),
            componentInstanceIDs: componentInstanceIDs(in: removedSceneNodeIDs, metadata: metadata),
            constructionPlaneIDs: constructionPlaneIDs(in: removedSceneNodeIDs, metadata: metadata),
            topologyMaterialBindingIDs: topologyMaterialBindingIDs(
                targeting: removedSceneNodeIDs,
                metadata: metadata
            ),
            measurementIDs: measurementIDs(
                measuring: removedSceneNodeIDs,
                features: removedFeatureIDs,
                metadata: metadata
            ),
            bridgeCurveSourceIDs: metadata.bridgeCurveSources
                .filter { removedFeatureIDs.contains($0.value.featureID) }
                .map(\.key)
                .sorted(),
            joinedCurveSourceIDs: metadata.joinedCurveSources
                .filter { removedFeatureIDs.contains($0.value.featureID) }
                .map(\.key)
                .sorted(),
            joinedCurveGroupSourceIDs: metadata.joinedCurveGroupSources
                .filter { removedFeatureIDs.contains($0.value.featureID) }
                .map(\.key)
                .sorted(),
            dependentSceneNodeIDs: orderedSceneNodeIDs(
                removedSceneNodeIDs.subtracting(requestedIDs),
                hierarchy: hierarchy
            )
        )
    }

    private func requireDeletable(
        _ node: SceneNode,
        isRequested: Bool,
        hierarchy: SceneNodeHierarchy,
        metadata: ProductMetadata
    ) throws {
        guard hierarchy.isRootSceneNode(node.id) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(node.name) is a document root, which cannot be deleted."
            )
        }
        guard node.isLocked == false else {
            throw EditorError(
                code: .commandInvalid,
                message: isRequested
                    ? "\(node.name) is locked."
                    : "\(node.name) is locked and depends on what is being deleted."
            )
        }
        let ownershipResolver = PatternArrayOwnershipResolver()
        if let sourceID = ownershipResolver.sourceID(
            containingOutputSceneNode: node.id,
            in: metadata
        ) {
            let name = metadata.patternArrays[sourceID]?.name ?? "The pattern array"
            throw EditorError(
                code: .commandInvalid,
                message: "\(name) places \(node.name). Explode the pattern array to delete it."
            )
        }
    }

    /// Removed nodes deepest first, so each one is childless by the time it is removed.
    private func orderedSceneNodeIDs(
        _ ids: Set<SceneNodeID>,
        hierarchy: SceneNodeHierarchy
    ) -> [SceneNodeID] {
        ids.sorted { first, second in
            let firstDepth = hierarchy.ancestorIDs(of: first).count
            let secondDepth = hierarchy.ancestorIDs(of: second).count
            guard firstDepth == secondDepth else {
                return firstDepth > secondDepth
            }
            return first < second
        }
    }

    /// Removed features in reverse build order, so a feature is gone before the one it consumed.
    ///
    /// The graph's own order already places every source ahead of what consumes it, which is the
    /// guarantee the kernel's removal rule needs read backwards.
    private func orderedFeatureIDs(
        _ ids: Set<FeatureID>,
        designGraph: DesignGraph
    ) -> [FeatureID] {
        designGraph.order.reversed().filter { ids.contains($0) }
    }

    private func componentInstanceIDs(
        in sceneNodeIDs: Set<SceneNodeID>,
        metadata: ProductMetadata
    ) -> [ComponentInstanceID] {
        sceneNodeIDs
            .compactMap { metadata.sceneNodes[$0]?.reference?.componentInstanceID }
            .sorted()
    }

    private func constructionPlaneIDs(
        in sceneNodeIDs: Set<SceneNodeID>,
        metadata: ProductMetadata
    ) -> [ConstructionPlaneSourceID] {
        sceneNodeIDs
            .compactMap { metadata.sceneNodes[$0]?.reference?.constructionPlaneID }
            .sorted()
    }

    private func topologyMaterialBindingIDs(
        targeting sceneNodeIDs: Set<SceneNodeID>,
        metadata: ProductMetadata
    ) -> [TopologyMaterialBinding.ID] {
        metadata.topologyMaterialBindings
            .filter { sceneNodeIDs.contains($0.value.target.sceneNodeID) }
            .map(\.key)
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }

    /// The measurements whose subject is being removed.
    ///
    /// A measurement outlives an edit to what it measures, but not the removal of it: its anchors name
    /// a feature and a scene node, and neither is resolvable once they are gone.
    private func measurementIDs(
        measuring sceneNodeIDs: Set<SceneNodeID>,
        features featureIDs: Set<FeatureID>,
        metadata: ProductMetadata
    ) -> [MeasurementAnnotationID] {
        metadata.measurements
            .filter { _, measurement in
                if let sceneNodeID = measurement.sceneNodeID,
                   sceneNodeIDs.contains(sceneNodeID) {
                    return true
                }
                return measurement.anchors.contains { anchor in
                    if let featureID = anchor.sketchReference?.featureID,
                       featureIDs.contains(featureID) {
                        return true
                    }
                    if let featureID = anchor.sketchCurveParameter?.featureID,
                       featureIDs.contains(featureID) {
                        return true
                    }
                    if let sceneNodeID = anchor.topologyReference?.sceneNodeID,
                       sceneNodeIDs.contains(sceneNodeID) {
                        return true
                    }
                    if let sceneNodeID = anchor.topologyEdgeParameter?.sceneNodeID,
                       sceneNodeIDs.contains(sceneNodeID) {
                        return true
                    }
                    return false
                }
            }
            .map(\.key)
            .sorted()
    }
}
