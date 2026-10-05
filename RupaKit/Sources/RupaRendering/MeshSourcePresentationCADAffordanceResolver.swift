import Foundation
import SwiftCAD
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene
import RupaGeometry

/// Every feature's evaluated bodies, from one pass over an evaluation's subshape table: resolving
/// each presented item scanned the whole table, so a scene of many items was quadratic.
public struct MeshSourcePresentationEvaluatedBodies: Sendable {
    private let bodyIDsByFeatureID: [FeatureID: [BodyID]]
    private let metadata: ProductMetadata?
    private let occurrences: [SceneOccurrenceID: SceneNodeHierarchy.Occurrence]?

    public init(_ evaluatedDocument: EvaluatedDocument) {
        bodyIDsByFeatureID = Self.bodyIndex(evaluatedDocument)
        metadata = nil
        occurrences = nil
    }

    public init(_ evaluatedDocument: EvaluatedDocument, document: DesignDocument) throws {
        bodyIDsByFeatureID = Self.bodyIndex(evaluatedDocument)
        metadata = document.productMetadata
        var index: [SceneOccurrenceID: SceneNodeHierarchy.Occurrence] = [:]
        for occurrence in try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOccurrences() {
            try Task.checkCancellation()
            guard index.updateValue(occurrence, forKey: occurrence.id) == nil else {
                throw EditorError(code: .referenceUnresolved, message: "CAD occurrence admission contains duplicate placements.")
            }
        }
        occurrences = index
    }

    private static func bodyIndex(_ evaluatedDocument: EvaluatedDocument) -> [FeatureID: [BodyID]] {
        var index: [FeatureID: [BodyID]] = [:]
        for (subshapeID, reference) in evaluatedDocument.subshapes.entries {
            guard case let .body(bodyID) = reference,
                  evaluatedDocument.brep.bodies[bodyID] != nil else { continue }
            if index[subshapeID.featureID, default: []].contains(bodyID) == false {
                index[subshapeID.featureID, default: []].append(bodyID)
            }
        }
        return index
    }

    public func bodyIDs(for featureID: FeatureID) -> [BodyID] {
        bodyIDsByFeatureID[featureID] ?? []
    }

    func occurrence(for id: SceneOccurrenceID, in document: DesignDocument) throws -> SceneNodeHierarchy.Occurrence? {
        try Task.checkCancellation()
        if let metadata, let occurrences {
            guard metadata == document.productMetadata else {
                throw EditorError(code: .referenceUnresolved, message: "CAD occurrence admission belongs to different source metadata.")
            }
            return occurrences[id]
        }
        return try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOccurrences().first { $0.id == id }
    }
}

public struct MeshSourcePresentationCADAffordanceResolver: MeshSourcePresentationCADAffordanceResolving {
    public init() {}

    public func resolve(
        item: UniversalViewportSceneItem,
        navigation: MeshSourcePresentationNavigationMap,
        document: DesignDocument,
        generation: DocumentGeneration,
        cadInteraction: DocumentEvaluationContext?
    ) -> MeshSourcePresentationCADAffordanceAvailability {
        guard let sceneNodeID = navigation.sceneNodeID(for: item.occurrenceID) else {
            return .unavailable(.missingNavigation)
        }
        return resolve(
            item: item,
            sceneNodeID: sceneNodeID,
            document: document,
            generation: generation,
            cadInteraction: cadInteraction
        )
    }

    public func resolve(
        item: UniversalViewportSceneItem,
        sceneNodeID: SceneNodeID,
        document: DesignDocument,
        generation: DocumentGeneration,
        cadInteraction: DocumentEvaluationContext?,
        evaluatedBodies: MeshSourcePresentationEvaluatedBodies? = nil
    ) -> MeshSourcePresentationCADAffordanceAvailability {
        guard case let .cad(sourceID, outputID) = item.reference else {
            return .unavailable(.nonCADPresentation)
        }

        let index = evaluatedBodies ?? cadInteraction.map { MeshSourcePresentationEvaluatedBodies($0.evaluatedDocument) }
        let occurrence: SceneNodeHierarchy.Occurrence
        do {
            guard let index, let source = try index.occurrence(for: item.occurrenceID, in: document),
                  source.sceneNodeID == sceneNodeID, source.isVisible,
                  item.worldTransform.values == source.worldTransform.matrix.values else {
                return .unavailable(.occurrencePlacementMismatch)
            }
            occurrence = source
        } catch is CancellationError { return .unavailable(.cancelled) }
        catch { return .unavailable(.occurrencePlacementMismatch) }
        guard let sceneNode = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID],
              document.productMetadata.sceneNodes[sceneNodeID] != nil else {
            return .unavailable(.missingSceneNode)
        }
        guard let object = sceneNode.object,
              let selection = object.geometryRepresentations.selection,
              selection.presentation == item.representationID,
              let presentation = object.geometryRepresentations.representations[item.representationID],
              presentation.id == item.representationID,
              presentation.source == item.reference else {
            return .unavailable(.presentationSelectionMismatch)
        }

        guard sourceID == document.id.description else {
            return .unavailable(.sourceDocumentMismatch)
        }
        guard let outputUUID = UUID(uuidString: outputID) else {
            return .unavailable(.invalidOutputIdentifier)
        }
        let featureID = item.sourceFeatureID.flatMap { UUID(uuidString: $0) }.map { FeatureID($0) } ?? FeatureID(outputUUID)
        guard document.cadDocument.designGraph.nodes[featureID] != nil else {
            return .unavailable(.missingFeature)
        }
        guard sceneNode.reference == .body(featureID) else {
            return .unavailable(.sceneNodeReferenceMismatch)
        }
        guard let cadInteraction else {
            return .unavailable(.missingCADInteractionContext)
        }
        guard cadInteraction.matches(document: document, generation: generation) else {
            return .unavailable(.staleCADInteractionContext)
        }

        // A caller resolving many items hands one index of the evaluation's bodies; a single
        // resolution builds its own.
        let bodyIDs = (index ?? MeshSourcePresentationEvaluatedBodies(cadInteraction.evaluatedDocument))
            .bodyIDs(for: featureID)
        let bodyID: BodyID
        if let bodyWitness = item.sourceBodyID, let uuid = UUID(uuidString: bodyWitness) {
            bodyID = BodyID(uuid)
            guard bodyIDs.contains(bodyID), item.sourceFeatureID == featureID.description,
                  let role = item.outputRole,
                  cadInteraction.evaluatedDocument.subshapes.entries.contains(where: {
                      $0.key.featureID == featureID && "\($0.key.role)#\($0.key.ordinal)" == role && $0.value == .body(bodyID)
                  }) else { return .unavailable(.missingEvaluatedBody) }
        } else {
            guard bodyIDs.count == 1, let uniqueBody = bodyIDs.first else {
                return .unavailable(.missingEvaluatedBody)
            }
            bodyID = uniqueBody
        }

        guard FeatureID(outputUUID) == featureID || BodyID(outputUUID) == bodyID else {
            return .unavailable(.sceneNodeReferenceMismatch)
        }
        do {
            guard let mesh = cadInteraction.evaluatedDocument.meshes[bodyID],
                  try Self.matchesOriginalMesh(item.mesh, mesh) else {
                return .unavailable(.displayedMeshMismatch)
            }
        } catch is CancellationError {
            return .unavailable(.cancelled)
        } catch {
            return .unavailable(.displayedMeshMismatch)
        }

        return .available(
            MeshSourcePresentationCADAffordanceContext(
                occurrenceID: item.occurrenceID,
                sceneNodeID: sceneNodeID,
                featureID: featureID,
                bodyID: bodyID,
                generation: generation,
                representationID: item.representationID,
                sourceReference: item.reference
            )
        )
    }
    /// The converter preserves vertex ordinals and names each face by original triangle ordinal.
    /// Borrowed immutable buffers are compared once when admitting the presentation.
    private static func matchesOriginalMesh(_ source: MeshSource, _ mesh: Mesh) throws -> Bool {
        try Task.checkCancellation()
        guard mesh.indices.count.isMultiple(of: 3),
              source.vertexIDs.count == mesh.positions.count,
              source.vertexPositions.count == mesh.positions.count,
              source.faceIDs.count == mesh.indices.count / 3,
              source.faceCornerRanges.count == source.faceIDs.count,
              source.cornerVertexIDs.count == mesh.indices.count else { return false }
        for index in mesh.positions.indices {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            let point = mesh.positions[index]
            let displayed = source.vertexPositions[index]
            guard source.vertexIDs[index].rawValue == UInt64(index),
                  displayed.x == point.x, displayed.y == point.y, displayed.z == point.z else { return false }
        }
        for triangle in 0..<source.faceIDs.count {
            if triangle.isMultiple(of: 1024) { try Task.checkCancellation() }
            let offset = triangle * 3
            let range = source.faceCornerRanges[triangle]
            guard source.faceIDs[triangle].rawValue == UInt64(triangle),
                  range.start == offset, range.count == 3 else { return false }
            for corner in 0..<3 {
                guard source.cornerVertexIDs[offset + corner].rawValue == UInt64(mesh.indices[offset + corner]) else {
                    return false
                }
            }
        }
        try Task.checkCancellation()
        return true
    }
}
