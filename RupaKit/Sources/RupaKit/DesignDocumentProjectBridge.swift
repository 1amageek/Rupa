import Foundation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import SwiftCAD

/// Projects the editor's document representation into the universal source model.
///
/// This is intentionally a one-way adapter. `DesignDocument` remains the source of
/// truth for the current editor, while `ProjectSourceModel` is the immutable input
/// contract for evaluation, rendering, automation, and external providers.
public struct DesignDocumentProjectBridge: Sendable {
    public init() {}

    public func sourceModel(for document: DesignDocument) throws -> ProjectSourceModel {
        try projection(for: document).source
    }

    public func projection(
        for document: DesignDocument
    ) throws -> DesignDocumentProjectProjection {
        do {
            try document.validate()
        } catch {
            throw DesignDocumentProjectBridgeError(
                code: .invalidDocument,
                message: "The design document cannot be projected: \(error)."
            )
        }

        let metadata = document.productMetadata
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]
        for parent in metadata.sceneNodes.values {
            for childID in parent.childIDs {
                guard metadata.sceneNodes[childID] != nil else {
                    throw DesignDocumentProjectBridgeError(
                        code: .unknownChild,
                        message: "Scene node \(parent.id.description) references unknown child "
                            + "\(childID.description)."
                    )
                }
                guard parentByChild[childID] == nil else {
                    throw DesignDocumentProjectBridgeError(
                        code: .multipleParents,
                        message: "Scene node \(childID.description) has more than one parent."
                    )
                }
                parentByChild[childID] = parent.id
            }
        }

        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        for nodeID in metadata.sceneNodes.keys.sorted() {
            guard let node = metadata.sceneNodes[nodeID] else {
                continue
            }
            let definitionID = definitionID(for: nodeID)
            let occurrenceID = occurrenceID(for: nodeID)
            let transform: GeometryTransform3D
            do {
                transform = try GeometryTransform3D(values: node.localTransform.matrix.values)
            } catch {
                throw DesignDocumentProjectBridgeError(
                    code: .invalidTransform,
                    message: "Scene node \(nodeID.description) has an invalid transform: \(error)."
                )
            }
            definitions[definitionID] = ObjectDefinition(
                id: definitionID,
                name: node.name,
                representations: evaluationRepresentations(for: node)
            )
            occurrences[occurrenceID] = SceneOccurrence(
                id: occurrenceID,
                definitionID: definitionID,
                parentID: parentByChild[nodeID].map(occurrenceID(for:)),
                localTransform: transform
            )
        }

        let roots = try metadata.rootSceneNodeIDs.map { nodeID in
            guard metadata.sceneNodes[nodeID] != nil else {
                throw DesignDocumentProjectBridgeError(
                    code: .unknownChild,
                    message: "The document root references an unknown scene node \(nodeID.description)."
                )
            }
            return occurrenceID(for: nodeID)
        }

        let projectName = document.cadDocument.metadata.name ?? "Untitled"
        let source = try ProjectSourceModel(
            id: document.projectID,
            name: projectName,
            authoredMeshAssets: document.authoredMeshAssets,
            objectDefinitions: definitions,
            occurrences: occurrences,
            rootOccurrenceIDs: roots
        )
        return DesignDocumentProjectProjection(
            source: source,
            sceneNodeIDByOccurrenceID: sceneNodeNavigationIndex(for: document)
        )
    }

    public func sceneNodeNavigationIndex(
        for document: DesignDocument
    ) -> [SceneOccurrenceID: SceneNodeID] {
        Dictionary(uniqueKeysWithValues: document.productMetadata.sceneNodes.keys.map { nodeID in
            (occurrenceID(for: nodeID), nodeID)
        })
    }

    private func definitionID(for nodeID: SceneNodeID) -> ObjectDefinitionID {
        ObjectDefinitionID(rawValue: "object.\(nodeID.description)")
    }

    private func occurrenceID(for nodeID: SceneNodeID) -> SceneOccurrenceID {
        SceneOccurrenceID(rawValue: "scene.\(nodeID.description)")
    }

    private func evaluationRepresentations(
        for node: SceneNode
    ) -> GeometryRepresentationSet {
        let isBody = node.object?.category == .body || node.reference?.kind == .body
        guard isBody else {
            return .empty
        }
        return node.object?.geometryRepresentations ?? .empty
    }

}
