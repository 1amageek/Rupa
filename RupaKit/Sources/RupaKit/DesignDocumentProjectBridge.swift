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
        let placedOccurrences = try SceneNodeHierarchy(metadata: metadata).resolvedOccurrences()
        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        var navigation: [SceneOccurrenceID: SceneNodeID] = [:]
        for occurrence in placedOccurrences {
            guard let node = metadata.sceneNodes[occurrence.sourceSceneNodeID] else {
                throw DesignDocumentProjectBridgeError(
                    code: .unknownChild, message: "Resolved occurrence source node is missing."
                )
            }
            let definitionID = definitionID(for: node.id)
            let transform: GeometryTransform3D
            do {
                transform = try GeometryTransform3D(values: occurrence.localTransform.matrix.values)
            } catch {
                throw DesignDocumentProjectBridgeError(
                    code: .invalidTransform,
                    message: "Scene node \(node.id.description) has an invalid transform: \(error)."
                )
            }
            if definitions[definitionID] == nil {
                definitions[definitionID] = ObjectDefinition(
                    id: definitionID, name: node.name,
                    representations: evaluationRepresentations(for: node)
                )
            }
            occurrences[occurrence.id] = SceneOccurrence(
                id: occurrence.id, definitionID: definitionID,
                parentID: occurrence.parentID, localTransform: transform
            )
            navigation[occurrence.id] = occurrence.sceneNodeID
        }
        let roots = placedOccurrences.filter { $0.parentID == nil }.map(\.id)

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
            sceneNodeIDByOccurrenceID: navigation
        )
    }

    public func sceneNodeNavigationIndex(
        for document: DesignDocument
    ) throws -> [SceneOccurrenceID: SceneNodeID] {
        Dictionary(uniqueKeysWithValues: try SceneNodeHierarchy(metadata: document.productMetadata)
            .resolvedOccurrences().map { ($0.id, $0.sceneNodeID) })
    }

    private func definitionID(for nodeID: SceneNodeID) -> ObjectDefinitionID {
        ObjectDefinitionID(rawValue: "object.\(nodeID.description)")
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
