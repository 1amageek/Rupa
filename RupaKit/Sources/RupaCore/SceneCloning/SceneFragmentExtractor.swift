import SwiftCAD
import RupaCoreTypes

/// Reads selected scene subtrees and everything their geometry needs into a ``SceneFragment``.
struct SceneFragmentExtractor: Sendable {
    /// The frame root placements are expressed in.
    enum ReferenceFrame: Sendable {
        /// World placements, for copies placed anywhere in a document.
        case world
        /// Placements relative to the first root's parent, for pattern outputs that reproduce a
        /// definition inside their own frame.
        case parentOfFirstRoot
    }

    func extract(
        rootSceneNodeIDs requestedRootIDs: [SceneNodeID],
        frame: ReferenceFrame,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) throws -> SceneFragment {
        guard !requestedRootIDs.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Copying requires at least one scene node.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        for id in requestedRootIDs where hierarchy.node(id) == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(id.description) to copy does not exist."
            )
        }
        let rootIDs = hierarchy.outermostSceneNodeIDs(among: requestedRootIDs)
        for rootID in rootIDs where metadata.rootSceneNodeIDs.contains(rootID) {
            throw EditorError(code: .commandInvalid, message: "A document root is not copied; copy the objects inside it.")
        }
        var subtreeIDs: [SceneNodeID] = []
        for rootID in rootIDs {
            subtreeIDs.append(contentsOf: hierarchy.subtreeIDs(of: rootID))
        }
        let subtreeIDSet = Set(subtreeIDs)
        for id in subtreeIDs {
            try requireCopyable(id, metadata: metadata)
        }

        let reference: Transform3D
        switch frame {
        case .world:
            reference = .identity
        case .parentOfFirstRoot:
            reference = try hierarchy.parentWorldTransform(of: rootIDs[0])
        }
        let inverseReference = try reference.inverse()
        func placement(of id: SceneNodeID) throws -> Transform3D {
            try inverseReference.composed(with: try hierarchy.worldTransform(of: id))
        }

        var sceneNodes: [SceneNodeID: SceneNode] = [:]
        for id in subtreeIDs {
            sceneNodes[id] = metadata.sceneNodes[id]
        }
        let features = try featureClosure(
            seededBy: subtreeIDs.compactMap { metadata.sceneNodes[$0] },
            cadDocument: cadDocument
        )

        // A copied feature whose presenter stays behind is carried as a hidden node, so its copy is
        // presented once, at the copy's placement, instead of drawn unplaced in the world frame.
        var carriedPresenters: [SceneFragment.Root] = []
        for feature in features {
            guard let presenterID = hierarchy.presentingSceneNodeID(for: feature.id),
                  !subtreeIDSet.contains(presenterID),
                  sceneNodes[presenterID] == nil,
                  var presenter = metadata.sceneNodes[presenterID] else {
                continue
            }
            try requireCopyable(presenterID, metadata: metadata)
            presenter.childIDs = []
            presenter.isVisible = false
            presenter.boundaryOccurrences = nil
            sceneNodes[presenterID] = presenter
            carriedPresenters.append(SceneFragment.Root(
                sceneNodeID: presenterID,
                placement: try placement(of: presenterID)
            ))
        }

        let featureIDs = Set(features.map(\.id))
        let copiedNodeIDs = Set(sceneNodes.keys)
        let faceMaterialBindings = metadata.topologyMaterialBindings.values
            .filter { copiedNodeIDs.contains($0.target.sceneNodeID) }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        var materialIDs = Set(sceneNodes.values.compactMap(\.materialID))
        materialIDs.formUnion(faceMaterialBindings.compactMap(\.materialID))
        var materials: [MaterialID: Material] = [:]
        for materialID in materialIDs {
            guard let material = metadata.materialLibrary.materials[materialID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "A copied object refers to a missing material."
                )
            }
            materials[materialID] = material
        }

        return SceneFragment(
            roots: try rootIDs.map { SceneFragment.Root(sceneNodeID: $0, placement: try placement(of: $0)) },
            carriedPresenters: carriedPresenters,
            sceneNodes: sceneNodes,
            features: features,
            parameters: try parameterClosure(of: features, cadDocument: cadDocument),
            materials: materials,
            faceMaterialBindings: faceMaterialBindings,
            bridgeCurveSources: metadata.bridgeCurveSources.values
                .filter { featureIDs.contains($0.featureID) }
                .sorted { $0.id.description < $1.id.description },
            joinedCurveSources: metadata.joinedCurveSources.values
                .filter { featureIDs.contains($0.featureID) }
                .sorted { $0.id.description < $1.id.description },
            joinedCurveGroupSources: metadata.joinedCurveGroupSources.values
                .filter { featureIDs.contains($0.featureID) }
                .sorted { $0.id.description < $1.id.description }
        )
    }

    private func requireCopyable(_ id: SceneNodeID, metadata: ProductMetadata) throws {
        if let refusal = metadata.sceneCopyRefusal(forNode: id) {
            throw refusal
        }
    }

    /// The features the nodes present or are built from, with every feature they reference, in
    /// source graph order.
    private func featureClosure(
        seededBy nodes: [SceneNode],
        cadDocument: CADDocument
    ) throws -> [FeatureNode] {
        var closure: Set<FeatureID> = []
        var pending: [FeatureID] = []
        func enqueue(_ featureID: FeatureID) {
            if closure.insert(featureID).inserted {
                pending.append(featureID)
            }
        }
        for node in nodes {
            if let featureID = node.reference?.featureID { enqueue(featureID) }
            node.object?.cadRepresentationFeatureIDs.forEach(enqueue)
            if let featureID = node.object?.sourceSection?.featureID { enqueue(featureID) }
        }
        while let featureID = pending.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "A copied object refers to missing feature \(featureID.description)."
                )
            }
            feature.inputs.forEach { enqueue($0.featureID) }
            // Swift-CAD owns which operation fields name other features.
            feature.operation.referencedFeatureIDs.forEach(enqueue)
        }
        let ordered = cadDocument.designGraph.order.compactMap { featureID in
            closure.contains(featureID) ? cadDocument.designGraph.nodes[featureID] : nil
        }
        guard ordered.count == closure.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "A copied feature is missing from the design graph order."
            )
        }
        return ordered
    }

    private func parameterClosure(
        of features: [FeatureNode],
        cadDocument: CADDocument
    ) throws -> [Parameter] {
        var closure: Set<ParameterID> = []
        var pending: [ParameterID] = []
        for feature in features {
            for parameterID in feature.operation.referencedParameterIDs where closure.insert(parameterID).inserted {
                pending.append(parameterID)
            }
        }
        var parameters: [Parameter] = []
        while let parameterID = pending.popLast() {
            guard let parameter = cadDocument.parameters.parameters[parameterID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "A copied feature refers to missing parameter \(parameterID.description)."
                )
            }
            parameters.append(parameter)
            for referencedID in parameter.expression.referencedParameterIDs where closure.insert(referencedID).inserted {
                pending.append(referencedID)
            }
        }
        return parameters.sorted { $0.id.description < $1.id.description }
    }
}
