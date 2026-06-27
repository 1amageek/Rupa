import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct SketchLineJoinPlan {
        var retainedEntityID: SketchEntityID
        var removedEntityID: SketchEntityID
        var retainedOriginalLine: SketchLine
        var restoredOriginalLine: SketchLine
        var retainedLine: SketchLine
        var retainedSharedReference: SketchReference
        var removedSharedReference: SketchReference
        var removedOuterReference: SketchReference
        var migratedRemovedOuterReference: SketchReference
    }

    struct SketchCurveGroupJoinPlan {
        var memberEntityIDs: [SketchEntityID]
        var firstJoinedReference: SketchReference
        var secondJoinedReference: SketchReference
        var continuity: SketchCurveJoinContinuity
    }

    func resolvedJoinCurvePoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    var joinCurveEndpointToleranceSquared: Double {
        let tolerance = max(ModelingTolerance.standard.distance, 1.0e-12)
        return tolerance * tolerance
    }

    func bridgeEndpointReferencesAnyJoinEntity(
        _ endpoint: BridgeCurveEndpoint,
        affectedEntityIDs: Set<SketchEntityID>
    ) -> Bool {
        affectedEntityIDs.contains(where: { entityID in
            bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID)
        })
    }
}
