import Foundation
import SwiftCAD
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene

public struct MeshSourcePresentationCADAffordanceResolver: MeshSourcePresentationCADAffordanceResolving {
    public init() {}

    public func resolve(
        item: UniversalViewportSceneItem,
        navigation: MeshSourcePresentationNavigationMap,
        document: DesignDocument,
        generation: DocumentGeneration,
        cadInteraction: DocumentEvaluationContext?
    ) -> MeshSourcePresentationCADAffordanceAvailability {
        guard case let .cad(sourceID, outputID) = item.reference else {
            return .unavailable(.nonCADPresentation)
        }

        guard let sceneNodeID = navigation.sceneNodeID(for: item.occurrenceID) else {
            return .unavailable(.missingNavigation)
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
        guard let cadInteraction else {
            return .unavailable(.missingCADInteractionContext)
        }
        guard cadInteraction.matches(document: document, generation: generation) else {
            return .unavailable(.staleCADInteractionContext)
        }

        let evaluatedDocument = cadInteraction.evaluatedDocument
        let bodyIDs = bodyIDs(
            for: featureID,
            in: evaluatedDocument
        )
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

    private func bodyIDs(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) -> [BodyID] {
        var bodyIDs: [BodyID] = []
        for (subshapeID, reference) in evaluatedDocument.subshapes.entries {
            guard subshapeID.featureID == featureID,
                  case let .body(bodyID) = reference,
                  evaluatedDocument.brep.bodies[bodyID] != nil else {
                continue
            }
            if bodyIDs.contains(bodyID) == false {
                bodyIDs.append(bodyID)
            }
        }
        return bodyIDs
    }
}
