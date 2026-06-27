import Foundation
import SwiftCAD
import RupaCoreTypes

struct PatternArrayDocumentSynchronizer {
    private func nextAvailableMetadataName(
        prefix: String,
        existingNames: inout Set<String>
    ) -> String {
        if existingNames.insert(prefix).inserted {
            return prefix
        }

        var index = 2
        while !existingNames.insert("\(prefix) \(index)").inserted {
            index += 1
        }
        return "\(prefix) \(index)"
    }

    func requireRenderableDefinition(
        _ definitionID: ComponentDefinitionID,
        metadata: ProductMetadata
    ) throws -> ComponentDefinition {
        guard let definition = metadata.componentDefinitions[definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern arrays must reference an existing component definition."
            )
        }
        guard ComponentDefinitionSceneResolver().containsRenderableSceneNode(
            in: definition,
            metadata: metadata
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays require a component definition with at least one renderable scene node."
            )
        }
        return definition
    }

    func synchronizeOutputs(
        for sourceID: PatternArraySourceID,
        previousSource: PatternArraySource? = nil,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws {
        guard var source = metadata.patternArrays[sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing pattern source."
            )
        }
        guard let definition = metadata.componentDefinitions[source.definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing component definition."
            )
        }
        guard var rootNode = metadata.sceneNodes[source.rootSceneNodeID],
              rootNode.reference == nil,
              rootNode.object?.category == .group else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing output group scene node."
            )
        }

        let transforms = try PatternArrayInstancePlanner().transforms(
            for: source.distribution,
            parameters: cadDocument.parameters,
            cadDocument: cadDocument
        )
        guard transforms.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays must create at least one output instance."
            )
        }

        switch source.outputMode {
        case .componentInstance:
            try requireNoExternalFeatureDependents(
                of: Set(source.outputFeatureIDs),
                cadDocument: cadDocument,
                owner: "Component-instance pattern array conversion"
            )
            PatternArrayIndependentCopyBuilder().removeOutputs(
                source: source,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
            source.outputSceneNodeIDs = []
            source.outputFeatureIDs = []
            source.definitionIdentity = nil
            try synchronizePatternArrayComponentInstanceOutputs(
                source: &source,
                rootNode: &rootNode,
                transforms: transforms,
                metadata: &metadata
            )
        case .independentCopy:
            removePatternArrayComponentInstanceOutputs(
                source: source,
                rootNode: rootNode,
                metadata: &metadata
            )
            let definitionIdentity = try PatternArrayDefinitionIdentityService().identity(
                for: definition,
                metadata: metadata,
                cadDocument: cadDocument
            )
            let reuseCandidate = previousSource ?? source
            let canReuseIndependentCopies = reuseCandidate.outputMode == .independentCopy &&
                reuseCandidate.definitionID == source.definitionID &&
                reuseCandidate.definitionIdentity == definitionIdentity
            if canReuseIndependentCopies {
                try synchronizePatternArrayIndependentCopyOutputs(
                    source: &source,
                    rootNode: &rootNode,
                    definition: definition,
                    transforms: transforms,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
            } else {
                try requireNoExternalFeatureDependents(
                    of: Set(source.outputFeatureIDs),
                    cadDocument: cadDocument,
                    owner: "Independent-copy pattern array rebuild"
                )
                PatternArrayIndependentCopyBuilder().removeOutputs(
                    source: source,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
                let result = try PatternArrayIndependentCopyBuilder().createOutputs(
                    name: source.name,
                    definition: definition,
                    transforms: transforms,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
                source.outputSceneNodeIDs = result.outputSceneNodeIDs
                source.outputFeatureIDs = result.outputFeatureIDs
                rootNode.childIDs = result.outputSceneNodeIDs
                metadata.sceneNodes[source.rootSceneNodeID] = rootNode
            }
            source.outputInstanceIDs = []
            source.definitionIdentity = definitionIdentity
        }

        metadata.patternArrays[sourceID] = source
    }

    private func requireNoExternalFeatureDependents(
        of removedFeatureIDs: Set<FeatureID>,
        cadDocument: CADDocument,
        owner: String
    ) throws {
        guard !removedFeatureIDs.isEmpty else {
            return
        }
        let dependentFeatureIDs = cadDocument.designGraph.order.filter { featureID in
            guard !removedFeatureIDs.contains(featureID),
                  let feature = cadDocument.designGraph.nodes[featureID] else {
                return false
            }
            return feature.inputs.contains { removedFeatureIDs.contains($0.featureID) }
        }
        guard dependentFeatureIDs.isEmpty else {
            let dependentList = dependentFeatureIDs
                .prefix(3)
                .map(\.description)
                .joined(separator: ", ")
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot remove independent-copy output features while downstream features depend on them. Delete or detach the dependent features first: \(dependentList)."
            )
        }
    }

    private func synchronizePatternArrayIndependentCopyOutputs(
        source: inout PatternArraySource,
        rootNode: inout SceneNode,
        definition: ComponentDefinition,
        transforms: [Transform3D],
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws {
        let builder = PatternArrayIndependentCopyBuilder()
        let reusedCount = min(source.outputSceneNodeIDs.count, transforms.count)
        let reusableOutputSceneNodeIDs = Array(source.outputSceneNodeIDs.prefix(reusedCount))
        let staleOutputSceneNodeIDs = Array(source.outputSceneNodeIDs.dropFirst(reusedCount))
        let ownedFeatureIDs = Set(source.outputFeatureIDs)
        if transforms.count < source.outputSceneNodeIDs.count {
            try requireNoExternalFeatureDependents(
                of: ownedFeatureIDs,
                cadDocument: cadDocument,
                owner: "Independent-copy pattern array output removal"
            )
        }

        var reusedFeatureIDs: Set<FeatureID> = []
        reusedFeatureIDs.reserveCapacity(ownedFeatureIDs.count)
        for (index, outputSceneNodeID) in reusableOutputSceneNodeIDs.enumerated() {
            guard var outputNode = metadata.sceneNodes[outputSceneNodeID],
                  outputNode.reference == nil,
                  outputNode.object?.category == .group else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array reuse requires existing group output scene nodes."
                )
            }
            outputNode.name = "\(source.name) \(index + 1)"
            outputNode.localTransform = transforms[index]
            metadata.sceneNodes[outputSceneNodeID] = outputNode
            let outputFeatureIDs = builder.outputFeatureClosure(
                rootedAt: outputSceneNodeID,
                metadata: metadata,
                cadDocument: cadDocument
            )
            guard !outputFeatureIDs.isEmpty,
                  outputFeatureIDs.isSubset(of: ownedFeatureIDs) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array reuse requires owned output feature closures."
                )
            }
            reusedFeatureIDs.formUnion(outputFeatureIDs)
        }

        var staleFeatureIDs: Set<FeatureID> = []
        for staleOutputSceneNodeID in staleOutputSceneNodeIDs {
            staleFeatureIDs.formUnion(
                builder.outputFeatureClosure(
                    rootedAt: staleOutputSceneNodeID,
                    metadata: metadata,
                    cadDocument: cadDocument
                )
            )
        }
        staleFeatureIDs.formIntersection(ownedFeatureIDs.subtracting(reusedFeatureIDs))
        try requireNoExternalFeatureDependents(
            of: staleFeatureIDs,
            cadDocument: cadDocument,
            owner: "Independent-copy pattern array tail removal"
        )
        builder.removeOutputs(
            rootedAt: staleOutputSceneNodeIDs,
            featureIDs: staleFeatureIDs,
            metadata: &metadata,
            cadDocument: &cadDocument
        )

        let appendedTransforms = Array(transforms.dropFirst(reusedCount))
        let appendedResult: PatternArrayIndependentCopyBuildResult
        if appendedTransforms.isEmpty {
            appendedResult = PatternArrayIndependentCopyBuildResult(
                outputSceneNodeIDs: [],
                outputFeatureIDs: []
            )
        } else {
            appendedResult = try builder.createOutputs(
                name: source.name,
                definition: definition,
                transforms: appendedTransforms,
                startingOutputIndex: reusedCount,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
        }

        source.outputSceneNodeIDs = reusableOutputSceneNodeIDs + appendedResult.outputSceneNodeIDs
        let nextFeatureIDs = reusedFeatureIDs.union(appendedResult.outputFeatureIDs)
        source.outputFeatureIDs = builder.orderedFeatureIDs(
            nextFeatureIDs,
            cadDocument: cadDocument
        )
        rootNode.childIDs = source.outputSceneNodeIDs
        metadata.sceneNodes[source.rootSceneNodeID] = rootNode
    }

    private func synchronizePatternArrayComponentInstanceOutputs(
        source: inout PatternArraySource,
        rootNode: inout SceneNode,
        transforms: [Transform3D],
        metadata: inout ProductMetadata
    ) throws {
        let previousOutputIDs = source.outputInstanceIDs
        let reusableOutputIDs = Array(previousOutputIDs.prefix(transforms.count))
        let reusableOutputIDSet = Set(reusableOutputIDs)
        var usedInstanceNames = Set(
            metadata.componentInstances.values.compactMap { instance in
                previousOutputIDs.contains(instance.id)
                    ? nil
                    : instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        let existingChildIDsByInstanceID = patternArrayChildSceneNodeIDsByInstanceID(
            rootNode: rootNode,
            metadata: metadata
        )

        var nextOutputIDs: [ComponentInstanceID] = []
        var nextChildIDs: [SceneNodeID] = []
        nextOutputIDs.reserveCapacity(transforms.count)
        nextChildIDs.reserveCapacity(transforms.count)
        for (index, transform) in transforms.enumerated() {
            let instanceID = index < reusableOutputIDs.count
                ? reusableOutputIDs[index]
                : ComponentInstanceID()
            let instanceName: String
            if let existingInstance = metadata.componentInstances[instanceID] {
                instanceName = existingInstance.name
                usedInstanceNames.insert(existingInstance.name.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                instanceName = nextAvailableMetadataName(
                    prefix: "\(source.name) \(index + 1)",
                    existingNames: &usedInstanceNames
                )
            }

            var instance = metadata.componentInstances[instanceID] ?? ComponentInstance(
                id: instanceID,
                definitionID: source.definitionID,
                name: instanceName
            )
            instance.definitionID = source.definitionID
            instance.name = instanceName
            instance.localTransform = transform
            metadata.componentInstances[instanceID] = instance
            nextOutputIDs.append(instanceID)

            let sceneNodeID = existingChildIDsByInstanceID[instanceID] ?? SceneNodeID()
            var sceneNode = metadata.sceneNodes[sceneNodeID] ?? SceneNode(id: sceneNodeID, name: instanceName)
            sceneNode.name = instanceName
            sceneNode.reference = .componentInstance(instanceID)
            sceneNode.object = .componentInstance(instanceID)
            sceneNode.localTransform = .identity
            metadata.sceneNodes[sceneNodeID] = sceneNode
            nextChildIDs.append(sceneNodeID)
        }

        let nextOutputIDSet = Set(nextOutputIDs)
        for removedInstanceID in Set(previousOutputIDs).subtracting(nextOutputIDSet) {
            metadata.componentInstances.removeValue(forKey: removedInstanceID)
            if let removedSceneNodeID = existingChildIDsByInstanceID[removedInstanceID] {
                metadata.sceneNodes.removeValue(forKey: removedSceneNodeID)
            }
        }
        for removedChildID in Set(rootNode.childIDs).subtracting(Set(nextChildIDs)) {
            if let componentInstanceID = metadata.sceneNodes[removedChildID]?.reference?.componentInstanceID,
               !reusableOutputIDSet.contains(componentInstanceID) {
                metadata.componentInstances.removeValue(forKey: componentInstanceID)
            }
            metadata.sceneNodes.removeValue(forKey: removedChildID)
        }

        source.outputInstanceIDs = nextOutputIDs
        rootNode.childIDs = nextChildIDs
        metadata.sceneNodes[source.rootSceneNodeID] = rootNode
    }

    private func removePatternArrayComponentInstanceOutputs(
        source: PatternArraySource,
        rootNode: SceneNode,
        metadata: inout ProductMetadata
    ) {
        let ownedOutputInstanceIDs = Set(source.outputInstanceIDs)
        for instanceID in source.outputInstanceIDs {
            metadata.componentInstances.removeValue(forKey: instanceID)
        }
        for childID in rootNode.childIDs {
            guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID,
                  ownedOutputInstanceIDs.contains(componentInstanceID) else {
                continue
            }
            metadata.componentInstances.removeValue(forKey: componentInstanceID)
            metadata.sceneNodes.removeValue(forKey: childID)
        }
    }

    func materializedOutputsForExplode(
        source: PatternArraySource,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws -> PatternArrayExplodeResult {
        guard var rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing output group scene node."
            )
        }
        switch source.outputMode {
        case .componentInstance:
            let transforms = try source.outputInstanceIDs.map { instanceID -> Transform3D in
                guard let instance = metadata.componentInstances[instanceID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Pattern array explode requires existing output component instances."
                    )
                }
                return instance.localTransform
            }
            guard let definition = metadata.componentDefinitions[source.definitionID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array explode requires an existing component definition."
                )
            }
            removePatternArrayComponentInstanceOutputs(
                source: source,
                rootNode: rootNode,
                metadata: &metadata
            )
            let result = try PatternArrayIndependentCopyBuilder().createOutputs(
                name: source.name,
                definition: definition,
                transforms: transforms,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
            rootNode.childIDs = result.outputSceneNodeIDs
            metadata.sceneNodes[source.rootSceneNodeID] = rootNode
            return PatternArrayExplodeResult(
                componentInstanceIDs: source.outputInstanceIDs,
                sceneNodeIDs: result.outputSceneNodeIDs,
                featureIDs: result.outputFeatureIDs
            )
        case .independentCopy:
            return PatternArrayExplodeResult(
                sceneNodeIDs: source.outputSceneNodeIDs,
                featureIDs: source.outputFeatureIDs
            )
        }
    }

    private func patternArrayChildSceneNodeIDsByInstanceID(
        rootNode: SceneNode,
        metadata: ProductMetadata
    ) -> [ComponentInstanceID: SceneNodeID] {
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: SceneNodeID] = [:]
        for childID in rootNode.childIDs {
            guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID else {
                continue
            }
            sceneNodeIDsByInstanceID[componentInstanceID] = childID
        }
        return sceneNodeIDsByInstanceID
    }

}
