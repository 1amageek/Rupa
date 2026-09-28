import SwiftCAD
import RupaCoreTypes
import RupaProjectModel

struct PatternArrayIndependentCopyBuilder: Sendable {
    /// Inserts one copy of the definition per transform, each under a new output group whose
    /// local transform is that pattern transform.
    func createOutputs(
        name: String,
        fragment: SceneFragment,
        transforms: [Transform3D],
        startingOutputIndex: Int = 0,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument,
        authoredMeshAssets: inout [GeometrySourceID: AuthoredMeshAsset],
        tolerance: ModelingTolerance
    ) throws -> PatternArrayIndependentCopyBuildResult {
        guard !fragment.features.isEmpty || !fragment.authoredMeshes.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays require CAD features or meshes to copy."
            )
        }

        var updatedMetadata = metadata
        var updatedCADDocument = cadDocument
        var outputSceneNodeIDs: [SceneNodeID] = []
        var outputFeatureIDs: [FeatureID] = []
        for (relativeOutputIndex, transform) in transforms.enumerated() {
            let outputIndex = startingOutputIndex + relativeOutputIndex
            var outputNode = SceneNode(
                name: "\(name) \(outputIndex + 1)",
                object: .group(),
                localTransform: transform
            )
            let insertion = try SceneFragmentInserter().insert(
                fragment,
                placement: .identity,
                parentWorld: .identity,
                attachment: .detached,
                naming: .patternOutput(prefix: outputNode.name, outputIndex: outputIndex),
                metadata: &updatedMetadata,
                cadDocument: &updatedCADDocument,
                authoredMeshAssets: &authoredMeshAssets
            )
            outputNode.childIDs = insertion.rootSceneNodeIDs
            updatedMetadata.sceneNodes[outputNode.id] = outputNode
            outputSceneNodeIDs.append(outputNode.id)
            outputFeatureIDs.append(contentsOf: insertion.featureIDs)
        }

        try updatedCADDocument.validate(tolerance: tolerance)
        metadata = updatedMetadata
        cadDocument = updatedCADDocument
        return PatternArrayIndependentCopyBuildResult(
            outputSceneNodeIDs: outputSceneNodeIDs,
            outputFeatureIDs: outputFeatureIDs
        )
    }

    /// Captures copies in the array frame before stale outputs are removed.
    func sourceFragment(
        definition: ComponentDefinition, metadata: ProductMetadata, cadDocument: CADDocument,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]
    ) throws -> SceneFragment {
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        let sourceIDs = definition.rootSceneNodeIDs.flatMap { hierarchy.subtreeIDs(of: $0) }
        guard sourceIDs.contains(where: { metadata.sceneNodes[$0]?.reference?.kind == .componentInstance }) else {
            return try SceneFragmentExtractor().extract(rootSceneNodeIDs: definition.rootSceneNodeIDs,
                frame: .parentOfFirstRoot, metadata: metadata, cadDocument: cadDocument,
                authoredMeshAssets: authoredMeshAssets)
        }
        let inverseFrame = try hierarchy.parentWorldTransform(of: definition.rootSceneNodeIDs[0]).inverse()
        var temporary = DesignDocument(cadDocument: cadDocument, productMetadata: metadata,
            authoredMeshAssets: authoredMeshAssets)
        // The temporary copies are not generated outputs. Array metadata may be midway
        // through creation here; it does not own anything in this private realization.
        temporary.productMetadata.patternArrays = [:]
        var roots = try temporary.duplicateSceneNodes(ids: definition.rootSceneNodeIDs)
        while true {
            let current = try SceneNodeHierarchy(metadata: temporary.productMetadata)
            let ids = roots.flatMap { current.subtreeIDs(of: $0) }
            guard let id = ids.first(where: { temporary.productMetadata.sceneNodes[$0]?.reference?.kind == .componentInstance }),
                  let node = temporary.productMetadata.sceneNodes[id],
                  let instanceID = node.reference?.componentInstanceID,
                  let instance = temporary.productMetadata.componentInstances[instanceID] else { break }
            let expanded = try temporary.realizeComponentInstances(sceneNodeIDs: [id])
            for root in expanded {
                let visible = (temporary.productMetadata.sceneNodes[root]?.isVisible ?? false)
                    && node.isVisible && instance.isVisible
                temporary.productMetadata.sceneNodes[root]?.isVisible = visible
            }
            if let index = roots.firstIndex(of: id) { roots.replaceSubrange(index...index, with: expanded) }
        }
        var fragment = try temporary.sceneFragment(copying: roots)
        for index in fragment.roots.indices {
            fragment.roots[index].placement = try inverseFrame.composed(with: fragment.roots[index].placement)
        }
        return fragment
    }

    func removeOutputs(
        source: PatternArraySource,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument,
        authoredMeshAssets: inout [GeometrySourceID: AuthoredMeshAsset]
    ) {
        removeOutputs(
            rootedAt: source.outputSceneNodeIDs,
            featureIDs: Set(source.outputFeatureIDs),
            metadata: &metadata,
            cadDocument: &cadDocument,
            authoredMeshAssets: &authoredMeshAssets
        )
    }

    /// Removes the outputs and the mesh copies only they presented.
    func removeOutputs(
        rootedAt sceneNodeIDs: [SceneNodeID],
        featureIDs: Set<FeatureID>,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument,
        authoredMeshAssets: inout [GeometrySourceID: AuthoredMeshAsset]
    ) {
        var removedMeshIDs: Set<GeometrySourceID> = []
        var pending = sceneNodeIDs
        while let id = pending.popLast() {
            guard let node = metadata.sceneNodes[id] else { continue }
            removedMeshIDs.formUnion(Self.authoredMeshIDs(of: node))
            pending.append(contentsOf: node.childIDs)
        }
        SceneFragmentOutputRemover().remove(
            rootedAt: sceneNodeIDs,
            featureIDs: featureIDs,
            metadata: &metadata,
            cadDocument: &cadDocument
        )
        guard !removedMeshIDs.isEmpty else { return }
        let stillPresented = metadata.sceneNodes.values.reduce(into: Set<GeometrySourceID>()) {
            $0.formUnion(Self.authoredMeshIDs(of: $1))
        }
        for id in removedMeshIDs.subtracting(stillPresented) {
            authoredMeshAssets.removeValue(forKey: id)
        }
    }

    /// The authored meshes a node presents or carries as a representation.
    static func authoredMeshIDs(of node: SceneNode) -> Set<GeometrySourceID> {
        var ids = Set(node.object?.geometryRepresentations.representations.values.compactMap { representation -> GeometrySourceID? in
            if case .authoredMesh(let id) = representation.source { return id }
            return nil
        } ?? [])
        if node.reference?.kind == .authoredMesh, let id = node.reference?.geometrySourceID {
            ids.insert(id)
        }
        return ids
    }

    func outputFeatureClosure(
        rootedAt sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) -> Set<FeatureID> {
        let referencedFeatureIDs = referencedFeatureIDs(
            inSceneSubtreeRootedAt: sceneNodeID,
            metadata: metadata
        )
        return dependencyFeatureClosure(
            from: referencedFeatureIDs,
            cadDocument: cadDocument
        )
    }

    func orderedFeatureIDs(
        _ featureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> [FeatureID] {
        cadDocument.designGraph.order.filter {
            featureIDs.contains($0)
        }
    }

    private func referencedFeatureIDs(
        inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
        metadata: ProductMetadata
    ) -> Set<FeatureID> {
        var featureIDs: Set<FeatureID> = []
        collectReferencedFeatureIDs(
            rootSceneNodeID,
            metadata: metadata,
            featureIDs: &featureIDs
        )
        return featureIDs
    }

    private func collectReferencedFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureIDs: inout Set<FeatureID>
    ) {
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if let featureID = sceneNode.reference?.featureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceFeatureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceSection?.featureID {
            featureIDs.insert(featureID)
        }
        for childID in sceneNode.childIDs {
            collectReferencedFeatureIDs(
                childID,
                metadata: metadata,
                featureIDs: &featureIDs
            )
        }
    }

    private func dependencyFeatureClosure(
        from seedFeatureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> Set<FeatureID> {
        var featureIDs = seedFeatureIDs
        var pendingFeatureIDs = Array(seedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            for input in feature.inputs where featureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }
        return featureIDs
    }
}
