import SwiftCAD
import RupaCoreTypes
import RupaProjectModel

struct PatternArrayIndependentCopyBuilder: Sendable {
    /// Inserts one copy of the definition per transform, each under a new output group whose
    /// local transform is that pattern transform.
    func createOutputs(
        name: String,
        definition: ComponentDefinition,
        transforms: [Transform3D],
        startingOutputIndex: Int = 0,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument,
        tolerance: ModelingTolerance
    ) throws -> PatternArrayIndependentCopyBuildResult {
        let fragment = try SceneFragmentExtractor().extract(
            rootSceneNodeIDs: definition.rootSceneNodeIDs,
            frame: .parentOfFirstRoot,
            metadata: metadata,
            cadDocument: cadDocument,
            // FIXME(INCOMPLETE_IMPLEMENTATION): Independent-copy pattern outputs are built where
            // only metadata and the CAD document are in reach, so a definition presenting an
            // authored mesh fails extraction as a missing mesh. Production path: independent-copy
            // Rectangular, Radial and Curve arrays. Completion requires the pattern synchronizer to
            // carry the document's authored mesh assets through to insertion.
            authoredMeshAssets: [:]
        )
        guard !fragment.features.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays require cloneable CAD feature scene nodes."
            )
        }

        var updatedMetadata = metadata
        var updatedCADDocument = cadDocument
        var outputSceneNodeIDs: [SceneNodeID] = []
        var outputFeatureIDs: [FeatureID] = []
        var unusedMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
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
                authoredMeshAssets: &unusedMeshAssets
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

    func removeOutputs(
        source: PatternArraySource,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) {
        removeOutputs(
            rootedAt: source.outputSceneNodeIDs,
            featureIDs: Set(source.outputFeatureIDs),
            metadata: &metadata,
            cadDocument: &cadDocument
        )
    }

    func removeOutputs(
        rootedAt sceneNodeIDs: [SceneNodeID],
        featureIDs: Set<FeatureID>,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) {
        SceneFragmentOutputRemover().remove(
            rootedAt: sceneNodeIDs,
            featureIDs: featureIDs,
            metadata: &metadata,
            cadDocument: &cadDocument
        )
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
