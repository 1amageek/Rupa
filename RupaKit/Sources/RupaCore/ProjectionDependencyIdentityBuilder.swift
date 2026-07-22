import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ProjectionDependencyIdentityBuilder: Sendable {
    public init() {}

    public func identity(
        for semanticEntityID: SemanticEntityID,
        in envelope: SemanticExtensionEnvelope,
        document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> ProjectionDependencyIdentity {
        guard let semanticEntity = envelope.projection.semanticEntities.first(where: {
            $0.id == semanticEntityID
        }) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection dependency identity requires a declared semantic entity."
            )
        }
        let payload = try dependencyPayload(
            semanticEntity: semanticEntity,
            envelope: envelope,
            document: document
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return ProjectionDependencyIdentity(
            documentID: document.cadDocument.id,
            generation: generation,
            fingerprint: try ContentFingerprint(
                algorithm: "sha256-projection-dependencies-v1",
                value: StableDigest.sha256Hex(for: data)
            )
        )
    }

    private func dependencyPayload(
        semanticEntity: ProjectionSemanticEntity,
        envelope: SemanticExtensionEnvelope,
        document: DesignDocument
    ) throws -> ProjectionDependencyFingerprintPayload {
        let projection = envelope.projection
        let semanticEntityIDs = try collectSemanticEntityClosure(
            startingAt: semanticEntity.id,
            projection: projection
        )
        let sourceReferences = projection.sourceReferences
            .filter { semanticEntityIDs.contains($0.semanticEntityID) }
            .sorted { sourceReferenceKey($0) < sourceReferenceKey($1) }
        let sceneReferences = projection.sceneReferences
            .filter { semanticEntityIDs.contains($0.semanticEntityID) }
            .sorted { sceneReferenceKey($0) < sceneReferenceKey($1) }
        let topologyReferences = projection.topologyReferences
            .filter { semanticEntityIDs.contains($0.semanticEntityID) }
            .sorted { topologyReferenceKey($0) < topologyReferenceKey($1) }
        let boundaryTags = projection.boundaryTags
            .filter { semanticEntityIDs.contains($0.semanticEntityID) }
            .sorted { boundaryTagKey($0) < boundaryTagKey($1) }

        let semanticSources = try semanticEntityIDs.sorted { $0.rawValue < $1.rawValue }.flatMap { id in
            guard let entity = projection.semanticEntities.first(where: { $0.id == id }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection boundary dependencies must reference declared semantic entities."
                )
            }
            return try entity.sourcePaths.sorted {
                payloadPathKey($0) < payloadPathKey($1)
            }.map { path in
                SemanticSourceRecord(
                    semanticEntityID: id,
                    path: path,
                    value: try path.resolve(in: envelope.payload)
                )
            }
        }

        var sceneNodeIDs = Set(sceneReferences.map(\.sceneNodeID))
        for boundaryTag in boundaryTags {
            if case .sceneNode(let id) = boundaryTag.target {
                sceneNodeIDs.insert(id)
            }
        }
        let sceneDependencies = try collectSceneDependencies(
            startingAt: sceneNodeIDs,
            metadata: document.productMetadata
        )

        var featureIDs = Set(sourceReferences.map(\.featureID))
        featureIDs.formUnion(topologyReferences.map(\.owningFeatureID))
        featureIDs.formUnion(sceneDependencies.featureIDs)
        for boundaryTag in boundaryTags {
            switch boundaryTag.target {
            case .sourceFeature(let id):
                featureIDs.insert(id)
            case .topology(_, let owningFeatureID):
                featureIDs.insert(owningFeatureID)
            case .semanticEntity, .sceneNode:
                break
            }
        }
        let featureClosure = try collectFeatureClosure(
            startingAt: featureIDs,
            document: document.cadDocument
        )
        let parameterRecords = try collectParameterRecords(
            for: featureClosure.ids,
            document: document.cadDocument
        )
        let dependentSceneNodeIDs = Set(sceneDependencies.sceneNodes.map(\.tableID))
        let topologyMaterialBindings = document.productMetadata.topologyMaterialBindings.values
            .filter { dependentSceneNodeIDs.contains($0.target.sceneNodeID) }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let materials = try mergedMaterialRecords(
            sceneRecords: sceneDependencies.materials,
            additionalIDs: Set(topologyMaterialBindings.compactMap(\.materialID)),
            metadata: document.productMetadata
        )

        return ProjectionDependencyFingerprintPayload(
            documentID: document.cadDocument.id,
            schemaVersion: document.cadDocument.schemaVersion,
            units: document.cadDocument.units,
            semanticNamespace: envelope.namespace,
            semanticSchemaVersion: envelope.schemaVersion,
            semanticSources: semanticSources,
            sourceReferences: sourceReferences,
            sceneReferences: sceneReferences,
            topologyReferences: topologyReferences,
            boundaryTags: boundaryTags,
            featureNodes: featureClosure.records,
            parameters: parameterRecords,
            sceneNodes: sceneDependencies.sceneNodes,
            componentDefinitions: sceneDependencies.componentDefinitions,
            componentInstances: sceneDependencies.componentInstances,
            constructionPlanes: sceneDependencies.constructionPlanes,
            materials: materials,
            topologyMaterialBindings: topologyMaterialBindings
        )
    }

    private func collectSemanticEntityClosure(
        startingAt initialID: SemanticEntityID,
        projection: ProjectionManifest
    ) throws -> Set<SemanticEntityID> {
        var pending = [initialID]
        var ids: Set<SemanticEntityID> = []
        while let id = pending.popLast() {
            guard ids.insert(id).inserted else {
                continue
            }
            guard projection.semanticEntities.contains(where: { $0.id == id }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection semantic dependencies reference a missing semantic entity."
                )
            }
            for boundaryTag in projection.boundaryTags where boundaryTag.semanticEntityID == id {
                if case .semanticEntity(let referencedID) = boundaryTag.target {
                    pending.append(referencedID)
                }
            }
        }
        return ids
    }

    private func collectFeatureClosure(
        startingAt initialIDs: Set<FeatureID>,
        document: CADDocument
    ) throws -> (ids: Set<FeatureID>, records: [FeatureNodeRecord]) {
        var pending = Array(initialIDs)
        var ids: Set<FeatureID> = []
        while let id = pending.popLast() {
            guard ids.insert(id).inserted else {
                continue
            }
            guard let node = document.designGraph.nodes[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection dependencies reference a missing CAD feature."
                )
            }
            pending.append(contentsOf: node.inputs.map(\.featureID))
        }
        let records = try ids.sorted { $0.description < $1.description }.map { id in
            guard let node = document.designGraph.nodes[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection feature dependency disappeared during identity construction."
                )
            }
            return FeatureNodeRecord(tableID: id, node: node)
        }
        return (ids, records)
    }

    private func collectParameterRecords(
        for featureIDs: Set<FeatureID>,
        document: CADDocument
    ) throws -> [ParameterRecord] {
        let featureDescriptions = Set(featureIDs.map(\.description))
        let usageMap = ParameterSourceUsageService().usageMap(in: document)
        var parameterIDs = Set(usageMap.compactMap { parameterID, usages in
            usages.contains { featureDescriptions.contains($0.featureID) }
                ? parameterID
                : nil
        })
        var pending = Array(parameterIDs)
        while let parameterID = pending.popLast() {
            guard let parameter = document.parameters.parameters[parameterID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection feature dependencies reference a missing parameter."
                )
            }
            for dependencyID in CADExpressionParameterReferenceCollector.parameterIDs(
                in: parameter.expression
            ) where parameterIDs.insert(dependencyID).inserted {
                pending.append(dependencyID)
            }
        }
        return try parameterIDs.sorted { $0.description < $1.description }.map { id in
            guard let parameter = document.parameters.parameters[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection parameter dependency disappeared during identity construction."
                )
            }
            return ParameterRecord(tableID: id, parameter: parameter)
        }
    }

    private func collectSceneDependencies(
        startingAt initialIDs: Set<SceneNodeID>,
        metadata: ProductMetadata
    ) throws -> SceneDependencyRecords {
        let parentIDs = metadata.sceneNodes.reduce(into: [SceneNodeID: Set<SceneNodeID>]()) { result, entry in
            for childID in entry.value.childIDs {
                result[childID, default: []].insert(entry.key)
            }
        }
        var pendingSubtreeNodeIDs = Array(initialIDs)
        var pendingAncestorNodeIDs: [SceneNodeID] = []
        var pendingComponentInstanceIDs: [ComponentInstanceID] = []
        var sceneNodeIDs: Set<SceneNodeID> = []
        var expandedSubtreeNodeIDs: Set<SceneNodeID> = []
        var componentInstanceIDs: Set<ComponentInstanceID> = []
        var componentDefinitionIDs: Set<ComponentDefinitionID> = []
        var featureIDs: Set<FeatureID> = []
        var constructionPlaneIDs: Set<ConstructionPlaneSourceID> = []
        var materialIDs: Set<MaterialID> = []

        while !pendingSubtreeNodeIDs.isEmpty
            || !pendingAncestorNodeIDs.isEmpty
            || !pendingComponentInstanceIDs.isEmpty {
            while let id = pendingSubtreeNodeIDs.popLast() {
                guard expandedSubtreeNodeIDs.insert(id).inserted else {
                    continue
                }
                let node = try requireSceneNode(id, in: metadata)
                pendingSubtreeNodeIDs.append(contentsOf: node.childIDs)
                pendingAncestorNodeIDs.append(contentsOf: parentIDs[id] ?? [])
                collect(
                    node: node,
                    sceneNodeID: id,
                    sceneNodeIDs: &sceneNodeIDs,
                    featureIDs: &featureIDs,
                    constructionPlaneIDs: &constructionPlaneIDs,
                    materialIDs: &materialIDs,
                    componentInstanceIDs: &componentInstanceIDs,
                    pendingComponentInstanceIDs: &pendingComponentInstanceIDs
                )
            }

            while let id = pendingAncestorNodeIDs.popLast() {
                guard sceneNodeIDs.contains(id) == false else {
                    continue
                }
                let node = try requireSceneNode(id, in: metadata)
                pendingAncestorNodeIDs.append(contentsOf: parentIDs[id] ?? [])
                collect(
                    node: node,
                    sceneNodeID: id,
                    sceneNodeIDs: &sceneNodeIDs,
                    featureIDs: &featureIDs,
                    constructionPlaneIDs: &constructionPlaneIDs,
                    materialIDs: &materialIDs,
                    componentInstanceIDs: &componentInstanceIDs,
                    pendingComponentInstanceIDs: &pendingComponentInstanceIDs
                )
            }

            while let instanceID = pendingComponentInstanceIDs.popLast() {
                guard let instance = metadata.componentInstances[instanceID] else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection dependencies reference a missing component instance."
                    )
                }
                guard componentDefinitionIDs.insert(instance.definitionID).inserted else {
                    continue
                }
                guard let definition = metadata.componentDefinitions[instance.definitionID] else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection dependencies reference a missing component definition."
                    )
                }
                pendingSubtreeNodeIDs.append(contentsOf: definition.rootSceneNodeIDs)
            }
        }

        let sceneNodes = try sceneNodeIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.map { id in
            SceneNodeRecord(tableID: id, node: try requireSceneNode(id, in: metadata))
        }
        let componentDefinitions = try componentDefinitionIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.map { id in
            guard let definition = metadata.componentDefinitions[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection component definition dependency disappeared during identity construction."
                )
            }
            return ComponentDefinitionRecord(tableID: id, definition: definition)
        }
        let componentInstances = try componentInstanceIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.map { id in
            guard let instance = metadata.componentInstances[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection component instance dependency disappeared during identity construction."
                )
            }
            return ComponentInstanceRecord(tableID: id, instance: instance)
        }
        let constructionPlanes = try constructionPlaneIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.map { id in
            guard let plane = metadata.constructionPlanes[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection scene dependencies reference a missing construction plane."
                )
            }
            return ConstructionPlaneRecord(tableID: id, plane: plane)
        }
        let materials = try materialIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.map { id in
            guard let material = metadata.materialLibrary.materials[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection scene dependencies reference a missing material."
                )
            }
            return MaterialRecord(tableID: id, material: material)
        }
        return SceneDependencyRecords(
            featureIDs: featureIDs,
            sceneNodes: sceneNodes,
            componentDefinitions: componentDefinitions,
            componentInstances: componentInstances,
            constructionPlanes: constructionPlanes,
            materials: materials
        )
    }

    private func mergedMaterialRecords(
        sceneRecords: [MaterialRecord],
        additionalIDs: Set<MaterialID>,
        metadata: ProductMetadata
    ) throws -> [MaterialRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: sceneRecords.map { ($0.tableID, $0) })
        for id in additionalIDs where recordsByID[id] == nil {
            guard let material = metadata.materialLibrary.materials[id] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection topology material dependencies reference a missing material."
                )
            }
            recordsByID[id] = MaterialRecord(tableID: id, material: material)
        }
        return recordsByID.keys.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.compactMap { recordsByID[$0] }
    }

    private func requireSceneNode(
        _ id: SceneNodeID,
        in metadata: ProductMetadata
    ) throws -> SceneNode {
        guard let node = metadata.sceneNodes[id] else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection dependencies reference a missing scene node."
            )
        }
        return node
    }

    private func collect(
        node: SceneNode,
        sceneNodeID: SceneNodeID,
        sceneNodeIDs: inout Set<SceneNodeID>,
        featureIDs: inout Set<FeatureID>,
        constructionPlaneIDs: inout Set<ConstructionPlaneSourceID>,
        materialIDs: inout Set<MaterialID>,
        componentInstanceIDs: inout Set<ComponentInstanceID>,
        pendingComponentInstanceIDs: inout [ComponentInstanceID]
    ) {
        guard sceneNodeIDs.insert(sceneNodeID).inserted else {
            return
        }
        if let featureID = node.reference?.featureID {
            featureIDs.insert(featureID)
        }
        if let featureID = node.object?.sourceFeatureID {
            featureIDs.insert(featureID)
        }
        if let constructionPlaneID = node.reference?.constructionPlaneID {
            constructionPlaneIDs.insert(constructionPlaneID)
        }
        if let materialID = node.materialID {
            materialIDs.insert(materialID)
        }
        if let componentInstanceID = node.reference?.componentInstanceID
            ?? node.object?.componentInstanceID,
           componentInstanceIDs.insert(componentInstanceID).inserted {
            pendingComponentInstanceIDs.append(componentInstanceID)
        }
    }

    private func sourceReferenceKey(_ reference: ProjectionManifest.SourceReference) -> String {
        "\(reference.semanticEntityID.rawValue):\(reference.featureID.description):\(reference.componentID?.rawValue ?? ""):\(reference.ownership.rawValue)"
    }

    private func sceneReferenceKey(_ reference: ProjectionManifest.SceneReference) -> String {
        "\(reference.semanticEntityID.rawValue):\(reference.sceneNodeID.rawValue.uuidString):\(reference.objectTypeID?.rawValue ?? "")"
    }

    private func topologyReferenceKey(_ reference: ProjectionManifest.TopologyReference) -> String {
        "\(reference.semanticEntityID.rawValue):\(reference.owningFeatureID.description):\(reference.role.rawValue):\(stableSubshapeKey(reference.stableReference))"
    }

    private func boundaryTagKey(_ tag: ProjectionManifest.BoundaryTag) -> String {
        "\(tag.semanticEntityID.rawValue):\(tag.kind):\(boundaryTargetKey(tag.target))"
    }

    private func boundaryTargetKey(_ target: ProjectionManifest.BoundaryTarget) -> String {
        switch target {
        case .semanticEntity(let id):
            return "semantic:\(id.rawValue)"
        case .sourceFeature(let id):
            return "feature:\(id.description)"
        case .sceneNode(let id):
            return "scene:\(id.rawValue.uuidString)"
        case .topology(let reference, let owningFeatureID):
            return "topology:\(owningFeatureID.description):\(stableSubshapeKey(reference))"
        }
    }

    private func stableSubshapeKey(_ reference: StableSubshapeReference) -> String {
        let id = reference.subshapeID
        return "\(id.featureID.description):\(id.role):\(id.ordinal)"
    }

    private func payloadPathKey(_ path: SemanticPayloadPath) -> String {
        path.components.map { component in
            switch component {
            case .key(let key):
                return "k:\(key)"
            case .index(let index):
                return "i:\(index)"
            }
        }
        .joined(separator: "/")
    }
}

private struct ProjectionDependencyFingerprintPayload: Encodable {
    var documentID: DocumentID
    var schemaVersion: SchemaVersion
    var units: UnitSystem
    var semanticNamespace: SemanticNamespaceID
    var semanticSchemaVersion: SemanticSchemaVersion
    var semanticSources: [SemanticSourceRecord]
    var sourceReferences: [ProjectionManifest.SourceReference]
    var sceneReferences: [ProjectionManifest.SceneReference]
    var topologyReferences: [ProjectionManifest.TopologyReference]
    var boundaryTags: [ProjectionManifest.BoundaryTag]
    var featureNodes: [FeatureNodeRecord]
    var parameters: [ParameterRecord]
    var sceneNodes: [SceneNodeRecord]
    var componentDefinitions: [ComponentDefinitionRecord]
    var componentInstances: [ComponentInstanceRecord]
    var constructionPlanes: [ConstructionPlaneRecord]
    var materials: [MaterialRecord]
    var topologyMaterialBindings: [TopologyMaterialBinding]
}

private struct SemanticSourceRecord: Encodable {
    var semanticEntityID: SemanticEntityID
    var path: SemanticPayloadPath
    var value: SemanticJSONValue
}

private struct FeatureNodeRecord: Encodable {
    var tableID: FeatureID
    var node: FeatureNode
}

private struct ParameterRecord: Encodable {
    var tableID: ParameterID
    var parameter: Parameter
}

private struct SceneNodeRecord: Encodable {
    var tableID: SceneNodeID
    var node: SceneNode
}

private struct ComponentDefinitionRecord: Encodable {
    var tableID: ComponentDefinitionID
    var definition: ComponentDefinition
}

private struct ComponentInstanceRecord: Encodable {
    var tableID: ComponentInstanceID
    var instance: ComponentInstance
}

private struct ConstructionPlaneRecord: Encodable {
    var tableID: ConstructionPlaneSourceID
    var plane: ConstructionPlaneSource
}

private struct MaterialRecord: Encodable {
    var tableID: MaterialID
    var material: Material
}

private struct SceneDependencyRecords {
    var featureIDs: Set<FeatureID>
    var sceneNodes: [SceneNodeRecord]
    var componentDefinitions: [ComponentDefinitionRecord]
    var componentInstances: [ComponentInstanceRecord]
    var constructionPlanes: [ConstructionPlaneRecord]
    var materials: [MaterialRecord]
}
