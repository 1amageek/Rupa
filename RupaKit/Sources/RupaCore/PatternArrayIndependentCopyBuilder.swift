import SwiftCAD

struct PatternArrayIndependentCopyBuilder: Sendable {
    func createOutputs(
        name: String,
        definition: ComponentDefinition,
        transforms: [Transform3D],
        startingOutputIndex: Int = 0,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws -> PatternArrayIndependentCopyBuildResult {
        let sourceFeatureIDs = try sourceFeatureClosure(
            for: definition,
            metadata: metadata,
            cadDocument: cadDocument
        )
        guard !sourceFeatureIDs.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays require cloneable CAD feature scene nodes."
            )
        }

        var outputSceneNodeIDs: [SceneNodeID] = []
        var outputFeatureIDs: [FeatureID] = []
        outputSceneNodeIDs.reserveCapacity(transforms.count)
        outputFeatureIDs.reserveCapacity(transforms.count * sourceFeatureIDs.count)

        var updatedCADDocument = cadDocument
        for (relativeOutputIndex, transform) in transforms.enumerated() {
            let outputIndex = startingOutputIndex + relativeOutputIndex
            let featureIDMap = featureIDMap(for: sourceFeatureIDs)
            let clonedFeatures = try clonedFeatureNodes(
                sourceFeatureIDs: sourceFeatureIDs,
                featureIDMap: featureIDMap,
                cadDocument: cadDocument,
                outputIndex: outputIndex
            )
            try appendClonedFeatures(
                clonedFeatures,
                to: &updatedCADDocument
            )
            outputFeatureIDs.append(contentsOf: clonedFeatures.map(\.id))

            var outputNode = SceneNode(
                name: "\(name) \(outputIndex + 1)",
                object: .group(),
                localTransform: transform
            )
            let clonedRootIDs = try definition.rootSceneNodeIDs.map { rootSceneNodeID in
                try cloneSceneTree(
                    rootSceneNodeID,
                    namePrefix: outputNode.name,
                    featureIDMap: featureIDMap,
                    metadata: &metadata
                )
            }
            outputNode.childIDs = clonedRootIDs
            metadata.sceneNodes[outputNode.id] = outputNode
            outputSceneNodeIDs.append(outputNode.id)
        }

        try updatedCADDocument.validate()
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
        removeSceneSubtrees(
            rootedAt: sceneNodeIDs,
            metadata: &metadata
        )
        removeFeatures(
            featureIDs,
            from: &cadDocument
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

    private func sourceFeatureClosure(
        for definition: ComponentDefinition,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) throws -> [FeatureID] {
        var referencedFeatureIDs: Set<FeatureID> = []
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            try collectSceneFeatureIDs(
                rootSceneNodeID,
                metadata: metadata,
                featureIDs: &referencedFeatureIDs
            )
        }
        guard !referencedFeatureIDs.isEmpty else {
            return []
        }

        var closureFeatureIDs = referencedFeatureIDs
        var pendingFeatureIDs = Array(referencedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array source scene nodes must reference existing CAD features."
                )
            }
            for input in feature.inputs where closureFeatureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }

        let orderedFeatureIDs = cadDocument.designGraph.order.filter {
            closureFeatureIDs.contains($0)
        }
        guard orderedFeatureIDs.count == closureFeatureIDs.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Independent-copy pattern array feature closure must be fully ordered in the CAD graph."
            )
        }
        return orderedFeatureIDs
    }

    private func collectSceneFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureIDs: inout Set<FeatureID>
    ) throws {
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Independent-copy pattern array definitions must reference existing scene nodes."
            )
        }
        if sceneNode.reference?.kind == .componentInstance || sceneNode.object?.category == .componentInstance {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays do not clone nested component instances yet."
            )
        }
        if let featureID = sceneNode.reference?.featureID {
            featureIDs.insert(featureID)
        }
        for childID in sceneNode.childIDs {
            try collectSceneFeatureIDs(
                childID,
                metadata: metadata,
                featureIDs: &featureIDs
            )
        }
    }

    private func featureIDMap(
        for sourceFeatureIDs: [FeatureID]
    ) -> [FeatureID: FeatureID] {
        Dictionary(uniqueKeysWithValues: sourceFeatureIDs.map { ($0, FeatureID()) })
    }

    private func clonedFeatureNodes(
        sourceFeatureIDs: [FeatureID],
        featureIDMap: [FeatureID: FeatureID],
        cadDocument: CADDocument,
        outputIndex: Int
    ) throws -> [FeatureNode] {
        let remapper = PatternArrayFeatureIDRemapper(featureIDMap: featureIDMap)
        return try sourceFeatureIDs.map { sourceFeatureID in
            guard var feature = cadDocument.designGraph.nodes[sourceFeatureID],
                  let clonedFeatureID = featureIDMap[sourceFeatureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array feature closure contains a missing CAD feature."
                )
            }
            feature.id = clonedFeatureID
            if let name = feature.name {
                feature.name = "\(name) Copy \(outputIndex + 1)"
            }
            feature.inputs = try feature.inputs.map(remapper.remappedInput)
            feature.outputs = try feature.outputs.map(remapper.remappedOutput)
            feature.operation = try remapper.remappedOperation(feature.operation)
            return feature
        }
    }

    private func appendClonedFeatures(
        _ features: [FeatureNode],
        to cadDocument: inout CADDocument
    ) throws {
        var updatedCADDocument = cadDocument
        for feature in features {
            guard updatedCADDocument.designGraph.nodes[feature.id] == nil,
                  !updatedCADDocument.designGraph.order.contains(feature.id) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Independent-copy pattern array generated duplicate CAD feature IDs."
                )
            }
            updatedCADDocument.designGraph.nodes[feature.id] = feature
            updatedCADDocument.designGraph.order.append(feature.id)
            updatedCADDocument.designGraph.dependencies.append(
                contentsOf: dependencyEdges(for: feature)
            )
        }
        updatedCADDocument.designGraph.revision = updatedCADDocument.designGraph.revision.advanced()
        cadDocument = updatedCADDocument
    }

    private func dependencyEdges(for feature: FeatureNode) -> [DependencyEdge] {
        Set(feature.inputs.map(\.featureID))
            .sorted { $0.description < $1.description }
            .map { DependencyEdge(source: $0, target: feature.id) }
    }

    private func cloneSceneTree(
        _ sceneNodeID: SceneNodeID,
        namePrefix: String,
        featureIDMap: [FeatureID: FeatureID],
        metadata: inout ProductMetadata
    ) throws -> SceneNodeID {
        guard var sceneNode = metadata.sceneNodes[sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Independent-copy pattern array source scene tree contains a missing node."
            )
        }
        let clonedSceneNodeID = SceneNodeID()
        let childIDs = sceneNode.childIDs
        sceneNode.id = clonedSceneNodeID
        sceneNode.name = "\(namePrefix) \(sceneNode.name)"
        sceneNode.reference = try sceneNode.reference.map {
            try remappedSceneNodeReference($0, using: featureIDMap)
        }
        sceneNode.object = try sceneNode.object.map {
            try remappedObjectDescriptor($0, using: featureIDMap)
        }
        sceneNode.childIDs = try childIDs.map { childID in
            try cloneSceneTree(
                childID,
                namePrefix: namePrefix,
                featureIDMap: featureIDMap,
                metadata: &metadata
            )
        }
        metadata.sceneNodes[clonedSceneNodeID] = sceneNode
        return clonedSceneNodeID
    }

    private func remappedSceneNodeReference(
        _ reference: SceneNodeReference,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> SceneNodeReference {
        let remapper = PatternArrayFeatureIDRemapper(featureIDMap: featureIDMap)
        switch reference.kind {
        case .feature:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Feature scene references require a feature ID.")
            }
            return .feature(try remapper.remappedFeatureID(featureID))
        case .body:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Body scene references require a feature ID.")
            }
            return .body(try remapper.remappedFeatureID(featureID))
        case .sketch:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Sketch scene references require a feature ID.")
            }
            return .sketch(try remapper.remappedFeatureID(featureID))
        case .componentInstance:
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays do not clone component instance scene references."
            )
        case .construction:
            return reference
        }
    }

    private func remappedObjectDescriptor(
        _ object: ObjectDescriptor,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> ObjectDescriptor {
        let remapper = PatternArrayFeatureIDRemapper(featureIDMap: featureIDMap)
        guard object.category != .componentInstance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays do not clone component instance objects."
            )
        }
        var clonedObject = object
        if let sourceFeatureID = object.sourceFeatureID {
            clonedObject.sourceFeatureID = try remapper.remappedFeatureID(sourceFeatureID)
        }
        if let sourceSection = object.sourceSection {
            clonedObject.sourceSection = try remapper.remappedBodySourceSectionReference(sourceSection)
        }
        return clonedObject
    }

    private func removeSceneSubtrees(
        rootedAt rootSceneNodeIDs: [SceneNodeID],
        metadata: inout ProductMetadata
    ) {
        var removedSceneNodeIDs: Set<SceneNodeID> = []
        for rootSceneNodeID in rootSceneNodeIDs {
            collectSceneSubtree(
                rootSceneNodeID,
                metadata: metadata,
                removedSceneNodeIDs: &removedSceneNodeIDs
            )
        }
        guard !removedSceneNodeIDs.isEmpty else {
            return
        }
        for sceneNodeID in removedSceneNodeIDs {
            metadata.sceneNodes.removeValue(forKey: sceneNodeID)
        }
        metadata.rootSceneNodeIDs.removeAll { removedSceneNodeIDs.contains($0) }
        for sceneNodeID in metadata.sceneNodes.keys {
            metadata.sceneNodes[sceneNodeID]?.childIDs.removeAll { removedSceneNodeIDs.contains($0) }
        }
    }

    private func collectSceneSubtree(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        removedSceneNodeIDs: inout Set<SceneNodeID>
    ) {
        guard removedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        for childID in sceneNode.childIDs {
            collectSceneSubtree(
                childID,
                metadata: metadata,
                removedSceneNodeIDs: &removedSceneNodeIDs
            )
        }
    }

    private func removeFeatures(
        _ featureIDs: Set<FeatureID>,
        from cadDocument: inout CADDocument
    ) {
        guard !featureIDs.isEmpty else {
            return
        }
        cadDocument.designGraph.order.removeAll { featureIDs.contains($0) }
        for featureID in featureIDs {
            cadDocument.designGraph.nodes.removeValue(forKey: featureID)
        }
        cadDocument.designGraph.dependencies.removeAll {
            featureIDs.contains($0.source) || featureIDs.contains($0.target)
        }
        cadDocument.designGraph.revision = cadDocument.designGraph.revision.advanced()
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
