import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaProjectModel

/// Inserts one copy of a ``SceneFragment`` into a document with fresh identities.
struct SceneFragmentInserter: Sendable {
    /// Where the copied roots are attached.
    enum Attachment: Sendable {
        /// Appended to the document roots.
        case documentRoot
        /// Inserted among `parentID`'s children starting at `index`.
        case child(of: SceneNodeID, at: Int)
        /// Not attached; the caller attaches the returned roots (pattern output wrappers).
        case detached
    }

    /// How copied names are chosen.
    enum Naming: Sendable {
        /// Roots take the lowest free numbered name and features are marked as copies.
        case copy
        /// Every node is prefixed with the pattern output name and features are numbered.
        case patternOutput(prefix: String, outputIndex: Int)
    }

    /// Inserts a copy whose roots land at `placement · fragmentPlacement` in world space, below a
    /// parent whose world transform is `parentWorld`.
    func insert(
        _ fragment: SceneFragment,
        placement: Transform3D,
        parentWorld: Transform3D,
        attachment: Attachment,
        naming: Naming,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument,
        authoredMeshAssets: inout [GeometrySourceID: AuthoredMeshAsset]
    ) throws -> SceneFragmentInsertion {
        guard let firstRoot = fragment.roots.first else {
            throw EditorError(code: .commandInvalid, message: "A scene fragment must contain at least one root.")
        }
        var updatedMetadata = metadata
        var updatedDocument = cadDocument

        try mergeParameters(fragment.parameters, into: &updatedDocument)
        let materialIDMap = mergeMaterials(fragment.materials, into: &updatedMetadata)

        let featureIDMap = Dictionary(uniqueKeysWithValues: fragment.features.map { ($0.id, FeatureID()) })
        var copiedFeatureIDs: [FeatureID] = []
        for source in fragment.features {
            guard let copiedID = featureIDMap[source.id] else { continue }
            // Swift-CAD remaps every feature reference the operation carries; a reference outside
            // the fragment is a typed failure, never a link back to the source.
            var feature = try source.remappingFeatureReferences(featureIDMap)
            feature.id = copiedID
            if let name = feature.name {
                switch naming {
                case .copy:
                    feature.name = "\(name) Copy"
                case .patternOutput(_, let outputIndex):
                    feature.name = "\(name) Copy \(outputIndex + 1)"
                }
            }
            guard updatedDocument.designGraph.nodes[copiedID] == nil else {
                throw EditorError(code: .commandInvalid, message: "A copied feature identity already exists.")
            }
            updatedDocument.designGraph.nodes[copiedID] = feature
            updatedDocument.designGraph.order.append(copiedID)
            updatedDocument.designGraph.dependencies.append(contentsOf: Set(feature.inputs.map(\.featureID))
                .sorted { $0.description < $1.description }
                .map { DependencyEdge(source: $0, target: copiedID) })
            copiedFeatureIDs.append(copiedID)
        }
        if !copiedFeatureIDs.isEmpty {
            updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
        }

        // Every copied mesh and instance gets a new identity, so no copy shares either with its source.
        var updatedMeshAssets = authoredMeshAssets
        var meshIDMap: [GeometrySourceID: GeometrySourceID] = [:]
        for id in fragment.authoredMeshes.keys.sorted(by: { $0.description < $1.description }) {
            var copiedID = GeometrySourceID()
            while updatedMeshAssets[copiedID] != nil || meshIDMap.values.contains(copiedID) {
                copiedID = GeometrySourceID()
            }
            meshIDMap[id] = copiedID
        }
        // An instance keeps its definition where the destination holds it; otherwise the definition
        // is recreated once from the content the fragment carries: its subtrees are inserted hidden
        // at their world placement under the first document root, and a new definition names them.
        var definitionIDMap: [ComponentDefinitionID: ComponentDefinitionID] = [:]
        for definitionID in Set(fragment.componentInstances.values.map(\.definitionID)).sorted(by: { $0.description < $1.description }) {
            if updatedMetadata.componentDefinitions[definitionID] != nil {
                definitionIDMap[definitionID] = definitionID
                continue
            }
            guard let carried = fragment.componentDefinitions[definitionID],
                  let documentRootID = updatedMetadata.rootSceneNodeIDs.first,
                  let documentRoot = updatedMetadata.sceneNodes[documentRootID] else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "An instance was copied without its component definition."
                )
            }
            let rootWorld = try SceneNodeHierarchy(metadata: updatedMetadata).worldTransform(of: documentRootID)
            let content = try insert(
                carried.content, placement: .identity, parentWorld: rootWorld,
                attachment: .child(of: documentRootID, at: documentRoot.childIDs.count), naming: .copy,
                metadata: &updatedMetadata, cadDocument: &updatedDocument, authoredMeshAssets: &updatedMeshAssets
            )
            for rootID in content.rootSceneNodeIDs { updatedMetadata.sceneNodes[rootID]?.isVisible = false }
            let taken = Set(updatedMetadata.componentDefinitions.values.map(\.name))
            var name = carried.name
            var ordinal = 2
            while taken.contains(name) {
                name = "\(carried.name) \(ordinal)"
                ordinal += 1
            }
            var definition = ComponentDefinition(name: name, rootSceneNodeIDs: content.rootSceneNodeIDs)
            definition.properties = carried.properties
            updatedMetadata.componentDefinitions[definition.id] = definition
            definitionIDMap[definitionID] = definition.id
        }
        // A copied construction plane is a new plane source under a new, unique name.
        var constructionPlaneIDMap: [ConstructionPlaneSourceID: ConstructionPlaneSourceID] = [:]
        for plane in fragment.constructionPlanes {
            var copied = plane
            copied.id = ConstructionPlaneSourceID()
            let taken = Set(updatedMetadata.constructionPlanes.values.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            copied.name = "\(plane.name) Copy"
            var ordinal = 2
            while taken.contains(copied.name) {
                copied.name = "\(plane.name) Copy \(ordinal)"
                ordinal += 1
            }
            updatedMetadata.constructionPlanes[copied.id] = copied
            constructionPlaneIDMap[plane.id] = copied.id
        }
        var instanceIDMap: [ComponentInstanceID: ComponentInstanceID] = [:]
        for (id, instance) in fragment.componentInstances.sorted(by: { $0.key.description < $1.key.description }) {
            var copied = instance
            copied.id = ComponentInstanceID()
            copied.definitionID = definitionIDMap[instance.definitionID] ?? instance.definitionID
            let taken = Set(updatedMetadata.componentInstances.values.map(\.name))
            var ordinal = 2
            copied.name = "\(instance.name) Copy"
            while taken.contains(copied.name) {
                copied.name = "\(instance.name) Copy \(ordinal)"
                ordinal += 1
            }
            updatedMetadata.componentInstances[copied.id] = copied
            instanceIDMap[id] = copied.id
        }
        var cadRepresentationIDMap: [GeometryRepresentationID: GeometryRepresentationID] = [:]

        let sceneIDMap = Dictionary(uniqueKeysWithValues: fragment.sceneNodes.keys.map { ($0, SceneNodeID()) })
        func copiedSceneNodeID(_ id: SceneNodeID) throws -> SceneNodeID {
            guard let copied = sceneIDMap[id] else {
                throw EditorError(code: .commandInvalid, message: "A scene fragment refers to a node it does not contain.")
            }
            return copied
        }
        var copiedNodeIDs: [SceneNodeID] = []
        func copyNode(_ id: SceneNodeID, isRoot: Bool) throws -> SceneNode {
            guard var node = fragment.sceneNodes[id] else {
                throw EditorError(code: .commandInvalid, message: "A scene fragment refers to a node it does not contain.")
            }
            node.id = try copiedSceneNodeID(id)
            node.childIDs = try node.childIDs.map(copiedSceneNodeID)
            node.reference = try node.reference.map {
                try remapped($0, featureIDMap: featureIDMap, meshIDMap: meshIDMap, instanceIDMap: instanceIDMap,
                             constructionPlaneIDMap: constructionPlaneIDMap)
            }
            node.object = try node.object.map { object in
                var copied = object
                try copied.remapCADRepresentations(using: featureIDMap, documentID: updatedDocument.id)
                for (id, representation) in object.geometryRepresentations.representations {
                    guard case .cad(_, let outputID) = representation.source,
                          let sourceFeature = UUID(uuidString: outputID).map(FeatureID.init),
                          let copiedFeature = featureIDMap[sourceFeature],
                          let copiedRepresentation = copied.geometryRepresentations.representations.values.first(where: {
                              if case .cad(_, let output) = $0.source { return output == copiedFeature.description }
                              return false
                          }) else { continue }
                    cadRepresentationIDMap[id] = copiedRepresentation.id
                }
                try remapMeshRepresentations(of: &copied, meshIDMap: meshIDMap)
                if let section = object.sourceSection {
                    copied.sourceSection = try section.remappingFeatureIDs(featureIDMap)
                }
                if let instanceID = object.componentInstanceID {
                    guard let copiedInstance = instanceIDMap[instanceID] else {
                        throw EditorError(code: .commandInvalid, message: "A copied instance object names an instance outside the copy.")
                    }
                    copied.componentInstanceID = copiedInstance
                }
                return copied
            }
            node.materialID = node.materialID.map { materialIDMap[$0] ?? $0 }
            node.boundaryOccurrences = try node.boundaryOccurrences.map {
                .init(first: try copiedSceneNodeID($0.first), second: try copiedSceneNodeID($0.second))
            }
            switch naming {
            case .copy:
                if isRoot {
                    node.name = SceneNodeNameAllocator().uniqueName(base: node.name, in: updatedMetadata)
                }
            case .patternOutput(let prefix, _):
                node.name = "\(prefix) \(node.name)"
            }
            return node
        }
        func insertSubtree(_ id: SceneNodeID, isRoot: Bool) throws {
            let node = try copyNode(id, isRoot: isRoot)
            updatedMetadata.sceneNodes[node.id] = node
            copiedNodeIDs.append(node.id)
            for childID in fragment.sceneNodes[id]?.childIDs ?? [] {
                try insertSubtree(childID, isRoot: false)
            }
        }

        let inverseParentWorld = try parentWorld.inverse()
        var copiedRootIDs: [SceneNodeID] = []
        for root in fragment.roots {
            try insertSubtree(root.sceneNodeID, isRoot: true)
            let copiedID = try copiedSceneNodeID(root.sceneNodeID)
            let local = try inverseParentWorld.composed(with: try placement.composed(with: root.placement))
            try local.validateAffinePlacement()
            updatedMetadata.sceneNodes[copiedID]?.localTransform = local
            copiedRootIDs.append(copiedID)
        }
        // Carried presenters keep their placement relative to the first root; the copy placement
        // cancels out of that relation.
        let firstCopiedRootID = copiedRootIDs[0]
        let inverseFirstRoot = try firstRoot.placement.inverse()
        for carried in fragment.carriedPresenters {
            let node = try copyNode(carried.sceneNodeID, isRoot: false)
            var hidden = node
            hidden.isVisible = false
            hidden.localTransform = try inverseFirstRoot.composed(with: carried.placement)
            try hidden.localTransform.validateAffinePlacement()
            updatedMetadata.sceneNodes[hidden.id] = hidden
            updatedMetadata.sceneNodes[firstCopiedRootID]?.childIDs.append(hidden.id)
            copiedNodeIDs.append(hidden.id)
        }

        switch attachment {
        case .documentRoot:
            updatedMetadata.rootSceneNodeIDs.append(contentsOf: copiedRootIDs)
        case .child(let parentID, let index):
            guard let parent = updatedMetadata.sceneNodes[parentID],
                  index >= 0, index <= parent.childIDs.count else {
                throw EditorError(code: .referenceUnresolved, message: "The copy destination parent does not exist.")
            }
            updatedMetadata.sceneNodes[parentID]?.childIDs.insert(contentsOf: copiedRootIDs, at: index)
        case .detached:
            break
        }

        for (id, asset) in fragment.authoredMeshes {
            guard let copiedID = meshIDMap[id] else { continue }
            var provenance = asset.provenance
            if case .derivedFromCAD(let representationID, let sourceIdentity) = provenance {
                guard let copiedRepresentation = cadRepresentationIDMap[representationID] else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "A copied mesh derived from CAD names a representation outside the copy."
                    )
                }
                provenance = .derivedFromCAD(representationID: copiedRepresentation, sourceIdentity: sourceIdentity)
            }
            updatedMeshAssets[copiedID] = try AuthoredMeshAsset(
                source: try asset.source.reidentified(as: copiedID),
                provenance: provenance
            )
        }

        for binding in fragment.faceMaterialBindings {
            guard case .face(let componentID) = binding.target.component,
                  let subshapeID = componentID.generatedTopologySubshapeID,
                  let featureID = featureIDMap[subshapeID.featureID] else {
                throw EditorError(code: .commandInvalid, message: "A copied face material binding names a face outside the copy.")
            }
            let copied = TopologyMaterialBinding(
                target: SelectionTarget(
                    sceneNodeID: try copiedSceneNodeID(binding.target.sceneNodeID),
                    component: .face(.generatedTopology(SubshapeID(
                        featureID: featureID,
                        role: subshapeID.role,
                        ordinal: subshapeID.ordinal
                    )))
                ),
                materialID: binding.materialID.map { materialIDMap[$0] ?? $0 },
                process: binding.process
            )
            updatedMetadata.topologyMaterialBindings[copied.id] = copied
        }
        func copiedFeatureID(_ featureID: FeatureID) throws -> FeatureID {
            guard let copied = featureIDMap[featureID] else {
                throw EditorError(code: .commandInvalid, message: "A copied edit source names a feature outside the copy.")
            }
            return copied
        }
        for source in fragment.bridgeCurveSources {
            var copied = source
            copied.id = BridgeCurveSourceID()
            copied.featureID = try copiedFeatureID(source.featureID)
            updatedMetadata.bridgeCurveSources[copied.id] = copied
        }
        for source in fragment.joinedCurveSources {
            var copied = source
            copied.id = JoinedCurveSourceID()
            copied.featureID = try copiedFeatureID(source.featureID)
            updatedMetadata.joinedCurveSources[copied.id] = copied
        }
        for source in fragment.joinedCurveGroupSources {
            var copied = source
            copied.id = JoinedCurveGroupSourceID()
            copied.featureID = try copiedFeatureID(source.featureID)
            updatedMetadata.joinedCurveGroupSources[copied.id] = copied
        }

        // Saved measurements follow the copy; anchors on copied nodes take the copies' occurrences.
        if !fragment.measurements.isEmpty {
            let occurrences = try SceneNodeHierarchy(metadata: updatedMetadata).resolvedOccurrences()
            for measurement in fragment.measurements {
                var copied = try measurement.copied(sceneNodes: sceneIDMap, features: featureIDMap, placement: placement)
                for index in copied.anchors.indices where measurement.anchors[index].occurrenceID != nil
                    && copied.anchors[index].occurrenceID == nil {
                    let anchor = copied.anchors[index]
                    let nodeID = anchor.sceneNodeID ?? anchor.topologyReference?.sceneNodeID ?? anchor.topologyEdgeParameter?.sceneNodeID
                    let matches = occurrences.filter { $0.sceneNodeID == nodeID }
                    guard matches.count == 1 else {
                        throw EditorError(
                            code: .commandInvalid,
                            message: "A copied measurement's anchor has no single occurrence in the copy."
                        )
                    }
                    copied.anchors[index].occurrenceID = matches[0].id
                }
                updatedMetadata.measurements[copied.id] = copied
            }
        }

        metadata = updatedMetadata
        cadDocument = updatedDocument
        authoredMeshAssets = updatedMeshAssets
        return SceneFragmentInsertion(
            rootSceneNodeIDs: copiedRootIDs,
            sceneNodeIDs: copiedNodeIDs,
            featureIDs: copiedFeatureIDs
        )
    }

    /// A parameter already present must mean the same value; otherwise the copy's geometry would
    /// silently change.
    private func mergeParameters(_ parameters: [Parameter], into cadDocument: inout CADDocument) throws {
        var added = false
        for parameter in parameters {
            if let existing = cadDocument.parameters.parameters[parameter.id] {
                guard existing == parameter else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Parameter \(parameter.name) already exists here with a different definition; the copy cannot be inserted."
                    )
                }
                continue
            }
            cadDocument.parameters.parameters[parameter.id] = parameter
            added = true
        }
        if added {
            cadDocument.parameters.revision = cadDocument.parameters.revision.advanced()
        }
    }

    /// Equal materials are shared; a material that differs under the same identity is added as a
    /// new material so neither document's appearance changes.
    private func mergeMaterials(
        _ materials: [MaterialID: Material],
        into metadata: inout ProductMetadata
    ) -> [MaterialID: MaterialID] {
        var materialIDMap: [MaterialID: MaterialID] = [:]
        for (materialID, material) in materials.sorted(by: { $0.key.description < $1.key.description }) {
            if let existing = metadata.materialLibrary.materials[materialID] {
                guard existing != material else { continue }
                var forked = material
                forked.id = MaterialID()
                metadata.materialLibrary.materials[forked.id] = forked
                materialIDMap[materialID] = forked.id
            } else {
                metadata.materialLibrary.materials[materialID] = material
            }
        }
        return materialIDMap
    }

    /// Mesh representations name the copied meshes under fresh representation IDs.
    private func remapMeshRepresentations(
        of object: inout ObjectDescriptor,
        meshIDMap: [GeometrySourceID: GeometrySourceID]
    ) throws {
        var representations = object.geometryRepresentations.representations
        var idMap: [GeometryRepresentationID: GeometryRepresentationID] = [:]
        for (id, representation) in object.geometryRepresentations.representations {
            guard case .authoredMesh(let meshID) = representation.source else { continue }
            guard let copiedMesh = meshIDMap[meshID] else {
                throw EditorError(code: .commandInvalid, message: "A copied object names a mesh outside the copy.")
            }
            let copiedID = GeometryRepresentationID()
            representations.removeValue(forKey: id)
            representations[copiedID] = GeometryRepresentation(id: copiedID, source: .authoredMesh(copiedMesh))
            idMap[id] = copiedID
        }
        object.geometryRepresentations.representations = representations
        if var selection = object.geometryRepresentations.selection {
            selection.modeling = idMap[selection.modeling] ?? selection.modeling
            selection.presentation = idMap[selection.presentation] ?? selection.presentation
            object.geometryRepresentations.selection = selection
        }
    }

    private func remapped(
        _ reference: SceneNodeReference,
        featureIDMap: [FeatureID: FeatureID],
        meshIDMap: [GeometrySourceID: GeometrySourceID],
        instanceIDMap: [ComponentInstanceID: ComponentInstanceID],
        constructionPlaneIDMap: [ConstructionPlaneSourceID: ConstructionPlaneSourceID]
    ) throws -> SceneNodeReference {
        func copied(_ featureID: FeatureID?) throws -> FeatureID {
            guard let featureID, let copied = featureIDMap[featureID] else {
                throw EditorError(code: .commandInvalid, message: "A copied scene node names a feature outside the copy.")
            }
            return copied
        }
        switch reference.kind {
        case .feature:
            return .feature(try copied(reference.featureID))
        case .body:
            return .body(try copied(reference.featureID))
        case .sketch:
            return .sketch(try copied(reference.featureID))
        case .authoredMesh:
            guard let id = reference.geometrySourceID, let copied = meshIDMap[id] else {
                throw EditorError(code: .commandInvalid, message: "A copied mesh node names a mesh outside the copy.")
            }
            return .authoredMesh(copied)
        case .componentInstance:
            guard let id = reference.componentInstanceID, let copied = instanceIDMap[id] else {
                throw EditorError(code: .commandInvalid, message: "A copied instance node names an instance outside the copy.")
            }
            return .componentInstance(copied)
        case .construction:
            guard let id = reference.constructionPlaneID else { return reference }
            guard let copied = constructionPlaneIDMap[id] else {
                throw EditorError(code: .commandInvalid, message: "A copied construction node names a plane outside the copy.")
            }
            return .constructionPlane(copied)
        }
    }
}
