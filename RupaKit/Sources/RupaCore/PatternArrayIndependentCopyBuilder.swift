import SwiftCAD

struct PatternArrayIndependentCopyBuilder: Sendable {
    func createOutputs(
        name: String,
        definition: ComponentDefinition,
        transforms: [Transform3D],
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
        for (outputIndex, transform) in transforms.enumerated() {
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
        removeSceneSubtrees(
            rootedAt: source.outputSceneNodeIDs,
            metadata: &metadata
        )
        removeFeatures(
            Set(source.outputFeatureIDs),
            from: &cadDocument
        )
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
        try sourceFeatureIDs.map { sourceFeatureID in
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
            feature.inputs = try feature.inputs.map { input in
                FeatureInput(
                    featureID: try remappedFeatureID(input.featureID, using: featureIDMap),
                    role: input.role
                )
            }
            feature.outputs = try feature.outputs.map { output in
                FeatureOutput(
                    role: output.role,
                    persistentName: try output.persistentName.map {
                        try remappedPersistentName($0, using: featureIDMap)
                    }
                )
            }
            feature.operation = try remappedOperation(feature.operation, using: featureIDMap)
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
        switch reference.kind {
        case .feature:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Feature scene references require a feature ID.")
            }
            return .feature(try remappedFeatureID(featureID, using: featureIDMap))
        case .body:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Body scene references require a feature ID.")
            }
            return .body(try remappedFeatureID(featureID, using: featureIDMap))
        case .sketch:
            guard let featureID = reference.featureID else {
                throw EditorError(code: .commandInvalid, message: "Sketch scene references require a feature ID.")
            }
            return .sketch(try remappedFeatureID(featureID, using: featureIDMap))
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
        guard object.category != .componentInstance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays do not clone component instance objects."
            )
        }
        var clonedObject = object
        if let sourceFeatureID = object.sourceFeatureID {
            clonedObject.sourceFeatureID = try remappedFeatureID(sourceFeatureID, using: featureIDMap)
        }
        if let sourceProfileFeatureID = object.sourceProfileFeatureID {
            clonedObject.sourceProfileFeatureID = try remappedFeatureID(
                sourceProfileFeatureID,
                using: featureIDMap
            )
        }
        return clonedObject
    }

    private func remappedOperation(
        _ operation: FeatureOperation,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> FeatureOperation {
        switch operation {
        case .sketch:
            return operation
        case .extrude(var extrude):
            extrude.profile = try remappedProfileReference(extrude.profile, using: featureIDMap)
            return .extrude(extrude)
        case .revolve(var revolve):
            revolve.profile = try remappedProfileReference(revolve.profile, using: featureIDMap)
            return .revolve(revolve)
        case .sweep(var sweep):
            sweep.profiles = try sweep.profiles.map {
                try remappedProfileReference($0, using: featureIDMap)
            }
            sweep.path = SweepPathReference(
                featureID: try remappedFeatureID(sweep.path.featureID, using: featureIDMap)
            )
            sweep.guides = try sweep.guides.map {
                SweepGuideReference(featureID: try remappedFeatureID($0.featureID, using: featureIDMap))
            }
            sweep.targets = try sweep.targets.map {
                SweepTargetReference(featureID: try remappedFeatureID($0.featureID, using: featureIDMap))
            }
            return .sweep(sweep)
        case .polySpline:
            return operation
        case .faceLoopOffset(var faceLoopOffset):
            faceLoopOffset.target = FaceLoopOffsetTargetReference(
                featureID: try remappedFeatureID(faceLoopOffset.target.featureID, using: featureIDMap)
            )
            faceLoopOffset.facePersistentName = try remappedPersistentName(
                faceLoopOffset.facePersistentName,
                using: featureIDMap
            )
            return .faceLoopOffset(faceLoopOffset)
        case .edgeOffset(var edgeOffset):
            edgeOffset.target = EdgeOffsetTargetReference(
                featureID: try remappedFeatureID(edgeOffset.target.featureID, using: featureIDMap)
            )
            edgeOffset.edgePersistentName = try remappedPersistentName(
                edgeOffset.edgePersistentName,
                using: featureIDMap
            )
            edgeOffset.supportFacePersistentName = try remappedPersistentName(
                edgeOffset.supportFacePersistentName,
                using: featureIDMap
            )
            return .edgeOffset(edgeOffset)
        case .faceKnife(var faceKnife):
            faceKnife.target = FaceKnifeTargetReference(
                featureID: try remappedFeatureID(faceKnife.target.featureID, using: featureIDMap)
            )
            faceKnife.facePersistentName = try remappedPersistentName(
                faceKnife.facePersistentName,
                using: featureIDMap
            )
            return .faceKnife(faceKnife)
        case .bridgeCurve:
            return operation
        case .curveEdit(var curveEdit):
            curveEdit.source = try remappedCurveOutputReference(curveEdit.source, using: featureIDMap)
            curveEdit.edits = try curveEdit.edits.map {
                try remappedCurveEdit($0, using: featureIDMap)
            }
            return .curveEdit(curveEdit)
        case .curveOffset(var curveOffset):
            curveOffset.source = try remappedCurveOutputReference(curveOffset.source, using: featureIDMap)
            return .curveOffset(curveOffset)
        case .curveTrim(var curveTrim):
            curveTrim.source = try remappedCurveOutputReference(curveTrim.source, using: featureIDMap)
            return .curveTrim(curveTrim)
        }
    }

    private func remappedProfileReference(
        _ reference: ProfileReference,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> ProfileReference {
        ProfileReference(
            featureID: try remappedFeatureID(reference.featureID, using: featureIDMap),
            profileIndex: reference.profileIndex
        )
    }

    private func remappedCurveEdit(
        _ edit: CurveEdit,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> CurveEdit {
        switch edit {
        case .setControlPoint(var controlPointEdit):
            controlPointEdit.target = CurveControlPointReference(
                curve: try remappedCurveOutputReference(controlPointEdit.target.curve, using: featureIDMap),
                controlPointIndex: controlPointEdit.target.controlPointIndex
            )
            return .setControlPoint(controlPointEdit)
        case .setKnot(var knotEdit):
            knotEdit.target = CurveKnotReference(
                curve: try remappedCurveOutputReference(knotEdit.target.curve, using: featureIDMap),
                knotIndex: knotEdit.target.knotIndex
            )
            return .setKnot(knotEdit)
        case .setWeight(var weightEdit):
            weightEdit.target = CurveControlPointReference(
                curve: try remappedCurveOutputReference(weightEdit.target.curve, using: featureIDMap),
                controlPointIndex: weightEdit.target.controlPointIndex
            )
            return .setWeight(weightEdit)
        }
    }

    private func remappedCurveOutputReference(
        _ reference: CurveOutputReference,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> CurveOutputReference {
        CurveOutputReference(
            featureID: try remappedFeatureID(reference.featureID, using: featureIDMap),
            curveIndex: reference.curveIndex
        )
    }

    private func remappedPersistentName(
        _ name: PersistentName,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> PersistentName {
        PersistentName(components: try name.components.map { component in
            switch component {
            case .feature(let featureID):
                return .feature(try remappedFeatureID(featureID, using: featureIDMap))
            case .generated, .subshape, .index:
                return component
            }
        })
    }

    private func remappedFeatureID(
        _ featureID: FeatureID,
        using featureIDMap: [FeatureID: FeatureID]
    ) throws -> FeatureID {
        guard let remapped = featureIDMap[featureID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Independent-copy pattern arrays can only reference cloned source feature dependencies."
            )
        }
        return remapped
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
}
