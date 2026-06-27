import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func joinedCurveSourceIfPresent(
        for selection: EditableSketchEntitySelection
    ) throws -> JoinedCurveSource? {
        let matches = productMetadata.joinedCurveSources.values.filter { source in
            source.featureID == selection.featureID &&
                source.retainedEntityID == selection.entityID
        }
        guard matches.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve found duplicate joined-curve ownership metadata for the selected source curve."
            )
        }
        return matches.first
    }

        func joinedCurveGroupSourceIfPresent(
        for selection: EditableSketchEntitySelection
    ) throws -> JoinedCurveGroupSource? {
        let matches = productMetadata.joinedCurveGroupSources.values.filter { source in
            source.featureID == selection.featureID &&
                source.memberEntityIDs.contains(selection.entityID)
        }
        guard matches.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve found duplicate joined-curve ownership metadata for the selected source curve."
            )
        }
        return matches.first
    }

        func validateSketchLineUnjoin(
        _ source: JoinedCurveSource,
        currentLine: SketchLine,
        sketch: Sketch
    ) throws {
        guard sketch.entities[source.restoredEntityID] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a source line because its original entity ID is already in use."
            )
        }
        guard try sketchLinesMatch(
            currentLine,
            source.joinedLine,
            owner: "Unjoin Curve joined line"
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined line after its geometry changed."
            )
        }
        guard sketch.constraints == source.constraintsAfterJoin,
              sketch.dimensions == source.dimensionsAfterJoin else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined line after its constraints or dimensions changed."
            )
        }
        for bridgeSource in productMetadata.bridgeCurveSources.values where bridgeSource.featureID == source.featureID {
            guard bridgeEndpointReferencesEntity(bridgeSource.firstEndpoint, entityID: source.retainedEntityID) == false,
                  bridgeEndpointReferencesEntity(bridgeSource.secondEndpoint, entityID: source.retainedEntityID) == false,
                  bridgeSource.entityID != source.retainedEntityID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Unjoin Curve cannot preserve generated Bridge Curve source metadata for joined lines yet."
                )
            }
        }
        _ = try resolvedLineMetrics(source.retainedOriginalLine, owner: "Unjoin Curve retained result")
        _ = try resolvedLineMetrics(source.restoredOriginalLine, owner: "Unjoin Curve restored result")
    }

        func validateSketchCurveGroupUnjoin(
        _ source: JoinedCurveGroupSource,
        sketch: Sketch
    ) throws {
        for entityID in source.memberEntityIDs {
            guard sketch.entities[entityID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Unjoin Curve cannot restore a joined curve group after a member source curve was removed."
                )
            }
        }
        guard sketch.constraints == source.constraintsAfterJoin,
              sketch.dimensions == source.dimensionsAfterJoin else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined curve group after its constraints or dimensions changed."
            )
        }
        let affectedEntityIDs = Set(source.memberEntityIDs)
        for bridgeSource in productMetadata.bridgeCurveSources.values where bridgeSource.featureID == source.featureID {
            guard bridgeEndpointReferencesAnyJoinEntity(
                bridgeSource.firstEndpoint,
                affectedEntityIDs: affectedEntityIDs
            ) == false,
            bridgeEndpointReferencesAnyJoinEntity(
                bridgeSource.secondEndpoint,
                affectedEntityIDs: affectedEntityIDs
            ) == false,
            affectedEntityIDs.contains(bridgeSource.entityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Unjoin Curve cannot preserve generated Bridge Curve source metadata for joined curves yet."
                )
            }
        }
    }

        private func sketchLinesMatch(
        _ first: SketchLine,
        _ second: SketchLine,
        owner: String
    ) throws -> Bool {
        let firstStart = try resolvedJoinCurvePoint(first.start, owner: "\(owner) first start")
        let firstEnd = try resolvedJoinCurvePoint(first.end, owner: "\(owner) first end")
        let secondStart = try resolvedJoinCurvePoint(second.start, owner: "\(owner) second start")
        let secondEnd = try resolvedJoinCurvePoint(second.end, owner: "\(owner) second end")
        return squaredDistance(firstStart, secondStart) <= joinCurveEndpointToleranceSquared &&
            squaredDistance(firstEnd, secondEnd) <= joinCurveEndpointToleranceSquared
    }}
