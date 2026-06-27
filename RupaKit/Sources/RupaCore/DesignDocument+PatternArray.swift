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
        var updatedMetadata = productMetadata
        guard let rootSceneNodeID = updatedMetadata.rootSceneNodeIDs.first,
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
            cadDocument: &updatedCADDocument
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
        return source.id
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
            cadDocument: &updatedCADDocument
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
    }

    @discardableResult
    public mutating func explodePatternArray(
        id: PatternArraySourceID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArrayExplodeResult {
        var updatedCADDocument = cadDocument
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
            cadDocument: &updatedCADDocument
        )
        updatedMetadata.patternArrays.removeValue(forKey: id)
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
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
        var updatedMetadata = productMetadata
        let sourceIDs = updatedMetadata.patternArrays.keys.sorted {
            $0.description < $1.description
        }
        let synchronizer = PatternArrayDocumentSynchronizer()
        for sourceID in sourceIDs {
            try synchronizer.synchronizeOutputs(
                for: sourceID,
                metadata: &updatedMetadata,
                cadDocument: &updatedCADDocument
            )
        }
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
    }
}
