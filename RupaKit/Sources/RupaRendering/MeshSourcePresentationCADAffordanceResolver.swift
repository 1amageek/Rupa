import Foundation
import SwiftCAD
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene

/// Every feature's evaluated bodies, from one pass over an evaluation's subshape table: resolving
/// each presented item scanned the whole table, so a scene of many items was quadratic.
public struct MeshSourcePresentationEvaluatedBodies: Sendable {
    private let bodyIDsByFeatureID: [FeatureID: [BodyID]]

    public init(_ evaluatedDocument: EvaluatedDocument) {
        var bodyIDsByFeatureID: [FeatureID: [BodyID]] = [:]
        for (subshapeID, reference) in evaluatedDocument.subshapes.entries {
            guard case let .body(bodyID) = reference,
                  evaluatedDocument.brep.bodies[bodyID] != nil else {
                continue
            }
            if bodyIDsByFeatureID[subshapeID.featureID, default: []].contains(bodyID) == false {
                bodyIDsByFeatureID[subshapeID.featureID, default: []].append(bodyID)
            }
        }
        self.bodyIDsByFeatureID = bodyIDsByFeatureID
    }

    public func bodyIDs(for featureID: FeatureID) -> [BodyID] {
        bodyIDsByFeatureID[featureID] ?? []
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

        guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID] else {
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
        let featureID = FeatureID(outputUUID)
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
        let bodyIDs = (evaluatedBodies ?? MeshSourcePresentationEvaluatedBodies(cadInteraction.evaluatedDocument))
            .bodyIDs(for: featureID)
        guard bodyIDs.count == 1, let bodyID = bodyIDs.first else {
            if bodyIDs.isEmpty {
                return .unavailable(.missingEvaluatedBody)
            }
            return .unavailable(.ambiguousEvaluatedBody)
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
}
