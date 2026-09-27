import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createPatternArray(
        name: String,
        definitionID: ComponentDefinitionID,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode = .componentInstance,
        parentSceneNodeID: SceneNodeID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArraySourceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Pattern array"
        )
        try distribution.validate()
        guard productMetadata.patternArrays.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array source names must be unique."
            )
        }
        let synchronizer = PatternArrayDocumentSynchronizer()
        _ = try synchronizer.requireRenderableDefinition(
            definitionID,
            metadata: productMetadata
        )

        switch outputMode {
        case .componentInstance, .independentCopy:
            break
        }

        var updatedCADDocument = cadDocument
        var updatedMeshAssets = authoredMeshAssets
        var updatedMetadata = productMetadata
        // The pattern group sits where its outputs are placed from: a given parent, otherwise the
        // first document root.
        guard let rootSceneNodeID = parentSceneNodeID ?? updatedMetadata.rootSceneNodeIDs.first,
              updatedMetadata.sceneNodes[rootSceneNodeID] != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays require a valid root scene node."
            )
        }

        let groupNode = SceneNode(
            name: trimmedName,
            object: .group()
        )
        updatedMetadata.sceneNodes[groupNode.id] = groupNode
        updatedMetadata.sceneNodes[rootSceneNodeID]?.childIDs.append(groupNode.id)

        let source = PatternArraySource(
            name: trimmedName,
            definitionID: definitionID,
            distribution: distribution,
            outputMode: outputMode,
            outputInstanceIDs: [],
            rootSceneNodeID: groupNode.id
        )
        updatedMetadata.patternArrays[source.id] = source
        try synchronizer.synchronizeOutputs(
            for: source.id,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument,
            authoredMeshAssets: &updatedMeshAssets,
            tolerance: modelingSettings.tolerance
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        authoredMeshAssets = updatedMeshAssets
        productMetadata = updatedMetadata
        return source.id
    }

    /// Arrays the objects `rootSceneNodeIDs` in one step: they become a component definition and
    /// the array is placed beside them, so its distribution is read in their parent's frame.
    @discardableResult
    public mutating func createPatternArray(
        name: String,
        copying rootSceneNodeIDs: [SceneNodeID],
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArraySourceID {
        if let refusal = productMetadata.sceneCopyRefusal(for: rootSceneNodeIDs) {
            throw refusal
        }
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let roots = hierarchy.outermostSceneNodeIDs(among: rootSceneNodeIDs)
        let takenNames = Set(productMetadata.componentDefinitions.values.map(\.name))
        var definitionName = "\(name) Source"
        var ordinal = 2
        while takenNames.contains(definitionName) {
            definitionName = "\(name) Source \(ordinal)"
            ordinal += 1
        }
        var updated = self
        let definitionID = try updated.createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: roots,
            objectRegistry: objectRegistry
        )
        let sourceID = try updated.createPatternArray(
            name: name,
            definitionID: definitionID,
            distribution: distribution,
            outputMode: outputMode,
            parentSceneNodeID: hierarchy.parentID(of: roots[0]),
            objectRegistry: objectRegistry
        )
        self = updated
        return sourceID
    }

    public mutating func updatePatternArray(
        id: PatternArraySourceID,
        name: String? = nil,
        definitionID: ComponentDefinitionID? = nil,
        distribution: PatternArrayDistribution? = nil,
        outputMode: PatternArrayOutputMode? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        var updatedCADDocument = cadDocument
        var updatedMeshAssets = authoredMeshAssets
        var updatedMetadata = productMetadata
        guard var source = updatedMetadata.patternArrays[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array update requires an existing pattern source."
            )
        }
        let synchronizer = PatternArrayDocumentSynchronizer()

        if let name {
            let trimmedName = try normalizedMetadataName(
                name,
                owner: "Pattern array"
            )
            guard updatedMetadata.patternArrays.values.allSatisfy({
                $0.id == id || $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
            }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Pattern array source names must be unique."
                )
            }
            source.name = trimmedName
            guard var rootNode = updatedMetadata.sceneNodes[source.rootSceneNodeID],
                  rootNode.reference == nil,
                  rootNode.object?.category == .group else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array update requires an existing output group scene node."
                )
            }
            rootNode.name = trimmedName
            updatedMetadata.sceneNodes[source.rootSceneNodeID] = rootNode
        }

        let nextDefinitionID = definitionID ?? source.definitionID
        let definition = try synchronizer.requireRenderableDefinition(
            nextDefinitionID,
            metadata: updatedMetadata
        )
        source.definitionID = definition.id

        if let distribution {
            try distribution.validate()
            source.distribution = distribution
        }

        let nextOutputMode = outputMode ?? source.outputMode
        switch nextOutputMode {
        case .componentInstance, .independentCopy:
            break
        }
        source.outputMode = nextOutputMode

        let previousSource = updatedMetadata.patternArrays[id]
        updatedMetadata.patternArrays[id] = source
        try synchronizer.synchronizeOutputs(
            for: id,
            previousSource: previousSource,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument,
            authoredMeshAssets: &updatedMeshAssets,
            tolerance: modelingSettings.tolerance
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        authoredMeshAssets = updatedMeshAssets
        productMetadata = updatedMetadata
    }

    @discardableResult
    public mutating func explodePatternArray(
        id: PatternArraySourceID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArrayExplodeResult {
        var updatedCADDocument = cadDocument
        var updatedMeshAssets = authoredMeshAssets
        var updatedMetadata = productMetadata
        guard let source = updatedMetadata.patternArrays[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing pattern source."
            )
        }
        guard updatedMetadata.sceneNodes[source.rootSceneNodeID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing output group scene node."
            )
        }

        let result = try PatternArrayDocumentSynchronizer().materializedOutputsForExplode(
            source: source,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument,
            authoredMeshAssets: &updatedMeshAssets,
            tolerance: modelingSettings.tolerance
        )
        updatedMetadata.patternArrays.removeValue(forKey: id)
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        authoredMeshAssets = updatedMeshAssets
        productMetadata = updatedMetadata
        return result
    }

    public mutating func regeneratePatternArrays(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard productMetadata.patternArrays.isEmpty == false else {
            return
        }
        var updatedCADDocument = cadDocument
        var updatedMeshAssets = authoredMeshAssets
        var updatedMetadata = productMetadata
        let sourceIDs = updatedMetadata.patternArrays.keys.sorted {
            $0.description < $1.description
        }
        let synchronizer = PatternArrayDocumentSynchronizer()
        for sourceID in sourceIDs {
            try synchronizer.synchronizeOutputs(
                for: sourceID,
                metadata: &updatedMetadata,
                cadDocument: &updatedCADDocument,
            authoredMeshAssets: &updatedMeshAssets,
            tolerance: modelingSettings.tolerance
            )
        }
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        authoredMeshAssets = updatedMeshAssets
        productMetadata = updatedMetadata
    }
}
