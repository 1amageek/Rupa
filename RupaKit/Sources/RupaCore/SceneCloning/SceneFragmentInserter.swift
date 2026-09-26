import SwiftCAD
import RupaCoreTypes

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
        cadDocument: inout CADDocument
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
            node.reference = try node.reference.map { try remapped($0, featureIDMap: featureIDMap) }
            node.object = try node.object.map { object in
                var copied = object
                try copied.remapCADRepresentations(using: featureIDMap, documentID: updatedDocument.id)
                if let section = object.sourceSection {
                    copied.sourceSection = try section.remappingFeatureIDs(featureIDMap)
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

        metadata = updatedMetadata
        cadDocument = updatedDocument
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

    private func remapped(
        _ reference: SceneNodeReference,
        featureIDMap: [FeatureID: FeatureID]
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
        case .componentInstance, .construction, .authoredMesh:
            throw EditorError(code: .commandInvalid, message: "Only feature, body and sketch nodes are copied.")
        }
    }
}
