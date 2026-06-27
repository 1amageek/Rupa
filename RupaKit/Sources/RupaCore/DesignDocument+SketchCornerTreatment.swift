import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func applySketchCornerTreatment(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget? = nil,
        distance: CADExpression,
        treatment: SketchCornerTreatment,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolvedDistance = try resolvedPositiveLengthValue(
            distance,
            owner: "Sketch corner treatment distance"
        )
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Sketch corner treatment"
        )
        let corner = try sketchCornerTreatmentSelection(
            target: target,
            adjacentTarget: adjacentTarget,
            selection: selection
        )
        try validateSketchCornerTreatment(
            selection: selection,
            corner: corner
        )

        let insertedEntityID = SketchEntityID()
        let result = try sketchCornerTreatmentResult(
            corner: corner,
            distance: resolvedDistance,
            treatment: treatment,
            insertedEntityID: insertedEntityID
        )

        var sketch = selection.sketch
        sketch.entities[corner.selectedEndpoint.entityID] = result.selectedEntity
        sketch.entities[corner.adjacentEndpoint.entityID] = result.adjacentEntity
        sketch.entities[insertedEntityID] = result.insertedEntity
        sketch.constraints = constraintsAfterSketchCornerTreatment(
            sketch.constraints,
            corner: corner,
            result: result
        )
        sketch.dimensions = try dimensionsAfterSketchCornerTreatment(
            sketch.dimensions,
            affectedEntityIDs: [
                corner.selectedEndpoint.entityID,
                corner.adjacentEndpoint.entityID,
            ],
            in: sketch
        )

        var feature = selection.feature
        try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch corner treatment"
        )
        return insertedEntityID
    }

    private struct SketchCornerTreatmentSelection {
        var selectedEndpoint: SketchCurveEndpoint
        var adjacentEndpoint: SketchCurveEndpoint
        var selectedEntity: SketchEntity
        var adjacentEntity: SketchEntity
    }

    private struct SketchCornerTreatmentResult {
        var selectedEntity: SketchEntity
        var adjacentEntity: SketchEntity
        var insertedEntity: SketchEntity
        var selectedInsertedReference: SketchReference
        var adjacentInsertedReference: SketchReference
    }

    private func sketchCornerTreatmentSelection(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget?,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        if let adjacentTarget {
            return try sketchCornerTreatmentSelectionFromCurvePair(
                target: target,
                adjacentTarget: adjacentTarget,
                selection: selection
            )
        }
        return try sketchCornerTreatmentSelectionFromEndpoint(
            target: target,
            selection: selection
        )
    }

    private func sketchCornerTreatmentSelectionFromEndpoint(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchPointHandleReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment requires a selected source curve endpoint."
            )
        }
        guard reference.featureID == selection.featureID,
              reference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment endpoint target does not match the selected source curve."
            )
        }
        let selectedEndpoint: SketchCurveEndpoint
        switch reference.handle {
        case .lineStart:
            selectedEndpoint = .line(LineEndpoint(entityID: reference.entityID, isStart: true))
        case .lineEnd:
            selectedEndpoint = .line(LineEndpoint(entityID: reference.entityID, isStart: false))
        case .arcStart:
            selectedEndpoint = .arc(ArcEndpoint(entityID: reference.entityID, isStart: true))
        case .arcEnd:
            selectedEndpoint = .arc(ArcEndpoint(entityID: reference.entityID, isStart: false))
        case .point,
             .circleCenter,
             .arcCenter:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires a line or arc endpoint."
            )
        }
        guard isSupportedOffsetVertexCurveEntity(selection.entity, endpoint: selectedEndpoint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment currently supports connected line or arc endpoints."
            )
        }
        let adjacent = try adjacentSketchCurveEndpoint(
            to: selectedEndpoint.reference,
            in: selection.sketch,
            owner: "Sketch corner treatment"
        )
        guard adjacent.endpoint.entityID != selectedEndpoint.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires two distinct source curves."
            )
        }
        return SketchCornerTreatmentSelection(
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacent.endpoint,
            selectedEntity: selection.entity,
            adjacentEntity: adjacent.entity
        )
    }

    private func sketchCornerTreatmentSelectionFromCurvePair(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        let adjacentSelection = try editableSketchEntityBase(
            for: adjacentTarget,
            operationName: "Sketch corner treatment"
        )
        guard adjacentSelection.featureID == selection.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment curve-pair targets must belong to the same sketch."
            )
        }
        guard adjacentSelection.entityID != selection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires two distinct source curves."
            )
        }
        let selectedEndpoints = try sketchCornerTreatmentCandidateEndpoints(
            target: target,
            selection: selection
        )
        let adjacentEndpoints = try sketchCornerTreatmentCandidateEndpoints(
            target: adjacentTarget,
            selection: adjacentSelection
        )
        var matches: [(selected: SketchCurveEndpoint, adjacent: SketchCurveEndpoint)] = []
        for selectedEndpoint in selectedEndpoints {
            for adjacentEndpoint in adjacentEndpoints where sketchCornerTreatmentReferencesAreCoincident(
                selectedEndpoint.reference,
                adjacentEndpoint.reference,
                in: selection.sketch
            ) {
                matches.append((selectedEndpoint, adjacentEndpoint))
            }
        }
        guard matches.count == 1,
              let match = matches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment curve-pair targets must share exactly one connected line or arc endpoint."
            )
        }
        return SketchCornerTreatmentSelection(
            selectedEndpoint: match.selected,
            adjacentEndpoint: match.adjacent,
            selectedEntity: selection.entity,
            adjacentEntity: adjacentSelection.entity
        )
    }

    private func sketchCornerTreatmentCandidateEndpoints(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> [SketchCurveEndpoint] {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment requires sketch entity targets."
            )
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Sketch corner treatment endpoint target does not match the selected source curve."
                )
            }
            switch reference.handle {
            case .lineStart:
                return [.line(LineEndpoint(entityID: reference.entityID, isStart: true))]
            case .lineEnd:
                return [.line(LineEndpoint(entityID: reference.entityID, isStart: false))]
            case .arcStart:
                return [.arc(ArcEndpoint(entityID: reference.entityID, isStart: true))]
            case .arcEnd:
                return [.arc(ArcEndpoint(entityID: reference.entityID, isStart: false))]
            case .point,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch corner treatment requires line or arc curve endpoints."
                )
            }
        }
        guard let reference = componentID.sketchEntityReference,
              reference.featureID == selection.featureID,
              reference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment curve-pair selection requires source curve targets."
            )
        }
        let endpoints = sketchCornerTreatmentEndpoints(
            entityID: reference.entityID,
            entity: selection.entity
        )
        guard endpoints.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment currently supports source line or arc curve targets."
            )
        }
        return endpoints
    }

    private func sketchCornerTreatmentEndpoints(
        entityID: SketchEntityID,
        entity: SketchEntity
    ) -> [SketchCurveEndpoint] {
        switch entity {
        case .line:
            [
                .line(LineEndpoint(entityID: entityID, isStart: true)),
                .line(LineEndpoint(entityID: entityID, isStart: false)),
            ]
        case .arc:
            [
                .arc(ArcEndpoint(entityID: entityID, isStart: true)),
                .arc(ArcEndpoint(entityID: entityID, isStart: false)),
            ]
        case .point,
             .circle,
             .spline:
            []
        }
    }

    private func sketchCornerTreatmentReferencesAreCoincident(
        _ first: SketchReference,
        _ second: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        sketch.constraints.contains { constraint in
            guard case .coincident(let lhs, let rhs) = constraint else {
                return false
            }
            return (lhs == first && rhs == second) || (lhs == second && rhs == first)
        }
    }

    private func validateSketchCornerTreatment(
        selection: EditableSketchEntitySelection,
        corner: SketchCornerTreatmentSelection
    ) throws {
        let affectedEntityIDs: Set<SketchEntityID> = [
            corner.selectedEndpoint.entityID,
            corner.adjacentEndpoint.entityID,
        ]
        for entityID in affectedEntityIDs {
            guard productMetadata.bridgeCurveSources.values.contains(where: { source in
                source.featureID == selection.featureID && source.entityID == entityID
            }) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch corner treatment cannot edit a generated Bridge Curve source."
                )
            }
        }
        for constraint in selection.sketch.constraints where sketchCornerTreatmentBlocksConstraint(
            constraint,
            affectedEntityIDs: affectedEntityIDs,
            selectedReference: corner.selectedEndpoint.reference,
            adjacentReference: corner.adjacentEndpoint.reference
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment cannot preserve unsupported constraints attached to the changing corner yet."
            )
        }
    }

    private func sketchCornerTreatmentResult(
        corner: SketchCornerTreatmentSelection,
        distance: Double,
        treatment: SketchCornerTreatment,
        insertedEntityID: SketchEntityID
    ) throws -> SketchCornerTreatmentResult {
        let selectedGeometry = try sketchCornerEndpointGeometry(
            corner.selectedEntity,
            endpoint: corner.selectedEndpoint,
            owner: "Sketch corner treatment selected curve"
        )
        let adjacentGeometry = try sketchCornerEndpointGeometry(
            corner.adjacentEntity,
            endpoint: corner.adjacentEndpoint,
            owner: "Sketch corner treatment adjacent curve"
        )
        let vertexDistance = selectedGeometry.vertex.distance(to: adjacentGeometry.vertex)
        guard vertexDistance <= ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires coincident curve endpoints."
            )
        }

        let selectedPoint: SketchCornerPoint
        let adjacentPoint: SketchCornerPoint
        let insertedEntity: SketchEntity
        let selectedInsertedReference: SketchReference
        let adjacentInsertedReference: SketchReference
        switch treatment {
        case .fillet:
            let candidate = try sketchCornerFilletCandidate(
                selectedGeometry: selectedGeometry,
                adjacentGeometry: adjacentGeometry,
                radius: distance
            )
            selectedPoint = candidate.selectedPoint
            adjacentPoint = candidate.adjacentPoint
            let fillet = try sketchCornerFilletEntity(
                center: candidate.center,
                selectedPoint: candidate.selectedPoint,
                adjacentPoint: candidate.adjacentPoint,
                radius: distance,
                insertedEntityID: insertedEntityID
            )
            insertedEntity = fillet.entity
            selectedInsertedReference = fillet.selectedReference
            adjacentInsertedReference = fillet.adjacentReference
        case .chamfer:
            selectedPoint = try sketchCornerTreatmentPoint(
                from: selectedGeometry,
                distance: distance
            )
            adjacentPoint = try sketchCornerTreatmentPoint(
                from: adjacentGeometry,
                distance: distance
            )
            insertedEntity = .line(SketchLine(
                start: literalSketchPoint(selectedPoint),
                end: literalSketchPoint(adjacentPoint)
            ))
            selectedInsertedReference = .lineStart(insertedEntityID)
            adjacentInsertedReference = .lineEnd(insertedEntityID)
        }

        let selectedEntity = try curveBySettingEndpoint(
            corner.selectedEntity,
            geometry: selectedGeometry,
            point: selectedPoint,
            owner: "Sketch corner treatment selected curve"
        )
        let adjacentEntity = try curveBySettingEndpoint(
            corner.adjacentEntity,
            geometry: adjacentGeometry,
            point: adjacentPoint,
            owner: "Sketch corner treatment adjacent curve"
        )
        return SketchCornerTreatmentResult(
            selectedEntity: selectedEntity,
            adjacentEntity: adjacentEntity,
            insertedEntity: insertedEntity,
            selectedInsertedReference: selectedInsertedReference,
            adjacentInsertedReference: adjacentInsertedReference
        )
    }

    private func constraintsAfterSketchCornerTreatment(
        _ constraints: [SketchConstraint],
        corner: SketchCornerTreatmentSelection,
        result: SketchCornerTreatmentResult
    ) -> [SketchConstraint] {
        var updated = constraints.filter { constraint in
            isOriginalSketchCornerCoincidence(
                constraint,
                selectedReference: corner.selectedEndpoint.reference,
                adjacentReference: corner.adjacentEndpoint.reference
            ) == false
        }
        updated.append(.coincident(
            corner.selectedEndpoint.reference,
            result.selectedInsertedReference
        ))
        updated.append(.coincident(
            result.adjacentInsertedReference,
            corner.adjacentEndpoint.reference
        ))
        return updated
    }

    private func dimensionsAfterSketchCornerTreatment(
        _ dimensions: [SketchDimension],
        affectedEntityIDs: Set<SketchEntityID>,
        in sketch: Sketch
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            guard dimensionReferencesAny(dimension, entityIDs: affectedEntityIDs) else {
                return dimension
            }
            return try refreshedSketchDimension(
                dimension,
                in: sketch,
                owner: "Sketch corner treatment dimension migration"
            )
        }
    }

    private func sketchCornerTreatmentBlocksConstraint(
        _ constraint: SketchConstraint,
        affectedEntityIDs: Set<SketchEntityID>,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        if isOriginalSketchCornerCoincidence(
            constraint,
            selectedReference: selectedReference,
            adjacentReference: adjacentReference
        ) {
            return false
        }
        switch constraint {
        case .horizontal,
             .vertical:
            return false
        case .coincident(let first, let second):
            return sketchCornerTreatmentReferenceIsMoved(
                first,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            ) || sketchCornerTreatmentReferenceIsMoved(
                second,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            )
        case .fixed(let reference):
            return sketchCornerTreatmentReferenceIsMoved(
                reference,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            )
        case .parallel,
             .perpendicular:
            return false
        case .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return affectedEntityIDs.contains(first) || affectedEntityIDs.contains(second)
        case .smoothSplineControlPoint(let entityID, _):
            return affectedEntityIDs.contains(entityID)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return affectedEntityIDs.contains(splineID) || affectedEntityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return affectedEntityIDs.contains(first.splineID) ||
                affectedEntityIDs.contains(second.splineID)
        }
    }

    private func sketchCornerTreatmentReferenceIsMoved(
        _ reference: SketchReference,
        affectedEntityIDs: Set<SketchEntityID>,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        if reference == selectedReference || reference == adjacentReference {
            return true
        }
        switch reference {
        case .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return affectedEntityIDs.contains(id)
        case .lineStart,
             .lineEnd,
             .arcStart,
             .arcEnd:
            return false
        }
    }

    private func isOriginalSketchCornerCoincidence(
        _ constraint: SketchConstraint,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        guard case .coincident(let first, let second) = constraint else {
            return false
        }
        return (first == selectedReference && second == adjacentReference) ||
            (first == adjacentReference && second == selectedReference)
    }

    private func curveBySettingEndpoint(
        _ entity: SketchEntity,
        geometry: SketchCornerEndpointGeometry,
        point: SketchCornerPoint,
        owner: String
    ) throws -> SketchEntity {
        switch (entity, geometry.endpoint) {
        case (.line(let line), .line(let endpoint)):
            return .line(lineBySettingEndpoint(
                line,
                endpoint: endpoint,
                point: literalSketchPoint(point)
            ))
        case (.arc(let arc), .arc(let endpoint)):
            guard let arcGeometry = geometry.arc else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) is missing arc geometry."
                )
            }
            let angle = try arcGeometry.storageAngle(
                for: point,
                owner: owner,
                tolerance: ModelingTolerance.standard.distance
            )
            let updated = endpoint.isStart
                ? SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: .angle(angle, .radian),
                    endAngle: arc.endAngle
                )
                : SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    endAngle: .angle(angle, .radian)
                )
            try validateArc(updated, owner: owner)
            return .arc(updated)
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }
}
