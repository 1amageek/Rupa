import SwiftCAD
import RupaCoreTypes

/// Resolves actual scene occurrences and original evaluated body lineage for drawing consumers.
public struct DefaultDrawingOccurrencePlacementResolver: DrawingOccurrencePlacementResolving {
    public init() {}

    public func placements(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                           maximumOccurrences: Int, maximumPlacements: Int) throws -> [DrawingOccurrenceBodyPlacement] {
        try Task.checkCancellation()
        guard evaluated.document == document.cadDocument,
              document.productMetadata.savedViews[savedView.id] == savedView,
              maximumOccurrences > 0, maximumPlacements > 0 else {
            throw EditorError(code: .commandInvalid,
                message: "Drawing placements require the current saved view and positive capacities.")
        }
        try savedView.validate(sceneNodes: document.productMetadata.sceneNodes,
            constructionPlanes: document.productMetadata.constructionPlanes)
        let occurrences = try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOriginalOccurrences()
        guard occurrences.count <= maximumOccurrences else {
            throw EditorError(code: .commandInvalid, message: "Drawing occurrence capacity is exhausted.")
        }
        var bodiesByFeature: [FeatureID: Set<BodyID>] = [:]
        for (identity, reference) in evaluated.subshapes.entries {
            try Task.checkCancellation()
            if case .body(let bodyID) = reference {
                guard evaluated.brep.bodies[bodyID] != nil else {
                    throw EditorError(code: .referenceUnresolved, message: "Drawing body lineage has a missing original body.")
                }
                bodiesByFeature[identity.featureID, default: []].insert(bodyID)
            }
        }
        let visible = Set(savedView.visibility.visibleSceneNodeIDs)
        let hidden = Set(savedView.visibility.hiddenSceneNodeIDs)
        var result: [DrawingOccurrenceBodyPlacement] = []
        var wordUsage = DrawingLegacyPlacementAdmission()
        for occurrence in occurrences {
            try Task.checkCancellation()
            guard occurrence.isVisible,
                  !hidden.contains(occurrence.sceneNodeID), !hidden.contains(occurrence.sourceSceneNodeID),
                  visible.isEmpty || visible.contains(occurrence.sceneNodeID) || visible.contains(occurrence.sourceSceneNodeID),
                  let node = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID],
                  let reference = node.reference, reference.kind == .body || reference.kind == .feature,
                  let featureID = reference.featureID else { continue }
            let placement = try ScenePlacement(occurrence.worldTransform)
            let transform = try AffineTransform3D(
                basisX: placement.vector(Vector3D(x: 1, y: 0, z: 0)),
                basisY: placement.vector(Vector3D(x: 0, y: 1, z: 0)),
                basisZ: placement.vector(Vector3D(x: 0, y: 0, z: 1)), translation: placement.translation)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The legacy public drawing resolver
            // retains exact original words under its existing cancellation-only policy.
            // Complete bounded page invocation requires forwarding one caller ledger
            // through hierarchy expansion and this original factor preparation.
            let word = try DrawingOriginalPlacementWordBuilder().word(from: occurrence, usage: &wordUsage)
            for bodyID in (bodiesByFeature[featureID] ?? []).sorted() {
                guard result.count < maximumPlacements else {
                    throw EditorError(code: .commandInvalid, message: "Drawing body placement capacity is exhausted.")
                }
                result.append(DrawingOccurrenceBodyPlacement(occurrenceID: occurrence.id,
                    sceneNodeID: occurrence.sceneNodeID, sourceSceneNodeID: occurrence.sourceSceneNodeID,
                    featureID: featureID, placement: placement,
                    original: try BRepDrawingPlacement(identity: occurrence.id.description, bodyID: bodyID, operationWord: word, displayTransform: transform)))
            }
        }
        return result
    }
}
