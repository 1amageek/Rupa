import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Rebuilds every Bridge Curve of `featureID` from its source's current geometry and
    /// tensions, so a bridge keeps its continuity whatever edit moved its sources.
    ///
    /// Bridges are rebuilt after the bridges their ends lie on, so a bridge on a bridge meets the
    /// regenerated curve; bridges that depend on each other in a cycle fail the edit. The
    /// constraints a bridge owns are rewritten with it, and every other reference to its end
    /// control points (constraints, dimensions, other bridges' ends, measurement anchors) follows
    /// the regenerated last index. A reference to an interior control point of a bridge has no
    /// meaning once the bridge is rebuilt, so it fails the edit rather than silently naming
    /// another point. `metadata` is the caller's copy: it is committed only with the sketch.
    func regenerateBridgeCurves(
        featureID: FeatureID,
        sketch: inout Sketch,
        metadata: inout ProductMetadata
    ) throws {
        let resolver = SketchCurveEndpointResolver()
        for sourceID in try bridgeRegenerationOrder(featureID: featureID, metadata: metadata) {
            guard let source = metadata.bridgeCurveSources[sourceID] else {
                throw EditorError(code: .referenceUnresolved, message: "Bridge curve source could not be resolved.")
            }
            guard case .spline(let previous) = sketch.entities[source.entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve source must point to a generated spline."
                )
            }
            guard let first = try resolver.sample(for: source.firstEndpoint, sketch: sketch, document: self),
                  let second = try resolver.sample(for: source.secondEndpoint, sketch: sketch, document: self) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
                )
            }
            let spline = try bridgeSpline(
                first: first,
                second: second,
                continuity: source.continuity,
                firstTension: source.firstEndpoint.tension,
                secondTension: source.secondEndpoint.tension,
                sketch: sketch
            )
            try validateSplineForm(spline, owner: "Bridge curve")
            removeBridgeOwnedConstraints(
                bridgeID: source.entityID,
                lastControlPointIndex: previous.controlPoints.count - 1,
                firstSample: first,
                secondSample: second,
                from: &sketch
            )
            try remapBridgeControlPointReferences(
                bridgeID: source.entityID,
                featureID: featureID,
                previousCount: previous.controlPoints.count,
                regeneratedCount: spline.controlPoints.count,
                sketch: &sketch,
                metadata: &metadata
            )
            sketch.entities[source.entityID] = .spline(spline)
            for constraint in bridgeOwnedConstraints(
                bridgeID: source.entityID,
                lastControlPointIndex: spline.controlPoints.count - 1,
                firstSample: first,
                secondSample: second
            ) {
                appendBridgeConstraint(constraint, to: &sketch)
            }
        }
    }

    /// The bridge sources of `featureID`, each after the bridges its ends lie on; ties in
    /// source ID order so the result does not depend on dictionary order.
    private func bridgeRegenerationOrder(
        featureID: FeatureID,
        metadata: ProductMetadata
    ) throws -> [BridgeCurveSourceID] {
        let sources = metadata.bridgeCurveSources.values
            .filter { $0.featureID == featureID }
            .sorted { $0.id.description < $1.id.description }
        let sourceByEntity = Dictionary(uniqueKeysWithValues: sources.map { ($0.entityID, $0.id) })
        var dependencies: [BridgeCurveSourceID: Set<BridgeCurveSourceID>] = [:]
        for source in sources {
            dependencies[source.id] = Set(sourceByEntity.compactMap { entityID, dependencyID in
                dependencyID != source.id
                    && (bridgeEndpointReferencesEntity(source.firstEndpoint, entityID: entityID)
                        || bridgeEndpointReferencesEntity(source.secondEndpoint, entityID: entityID))
                    ? dependencyID : nil
            })
        }
        var ordered: [BridgeCurveSourceID] = []
        var placed: Set<BridgeCurveSourceID> = []
        while ordered.count < sources.count {
            guard let next = sources.first(where: { source in
                placed.contains(source.id) == false
                    && (dependencies[source.id] ?? []).isSubset(of: placed)
            }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Bridge curves cannot be regenerated because their ends lie on each other in a cycle."
                )
            }
            ordered.append(next.id)
            placed.insert(next.id)
        }
        return ordered
    }

    /// Renumbers every reference to an end control point of bridge `bridgeID` from
    /// `previousCount` to `regeneratedCount` points; an interior reference fails.
    private func remapBridgeControlPointReferences(
        bridgeID: SketchEntityID,
        featureID: FeatureID,
        previousCount: Int,
        regeneratedCount: Int,
        sketch: inout Sketch,
        metadata: inout ProductMetadata
    ) throws {
        func mapped(_ reference: SketchReference, owner: String) throws -> SketchReference {
            guard case .splineControlPoint(bridgeID, let index) = reference else {
                return reference
            }
            if index == 0 {
                return reference
            }
            if index == previousCount - 1 {
                return .splineControlPoint(entity: bridgeID, index: regeneratedCount - 1)
            }
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) names interior control point \(index) of a generated Bridge Curve, which is rebuilt from its source; remove it and refer to the bridge's ends."
            )
        }
        sketch.constraints = try sketch.constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try mapped(first, owner: "A sketch constraint"),
                    try mapped(second, owner: "A sketch constraint")
                )
            case .fixed(let reference):
                return .fixed(try mapped(reference, owner: "A sketch constraint"))
            case .horizontal, .vertical, .parallel, .perpendicular, .equalLength, .tangent, .concentric,
                 .equalRadius, .smoothSplineControlPoint, .splineEndpointTangent, .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                return constraint
            }
        }
        sketch.dimensions = try sketch.dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try mapped(from, owner: "A sketch dimension"),
                    to: try mapped(to, owner: "A sketch dimension"),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try mapped(from, owner: "A sketch dimension"),
                    to: try mapped(to, owner: "A sketch dimension"),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
        for (sourceID, var source) in metadata.bridgeCurveSources where source.featureID == featureID {
            source.firstEndpoint.reference = try mapped(source.firstEndpoint.reference, owner: "A Bridge Curve end")
            source.secondEndpoint.reference = try mapped(source.secondEndpoint.reference, owner: "A Bridge Curve end")
            metadata.bridgeCurveSources[sourceID] = source
        }
        for (measurementID, var measurement) in metadata.measurements {
            var changed = false
            for index in measurement.anchors.indices {
                guard var anchor = measurement.anchors[index].sketchReference, anchor.featureID == featureID else {
                    continue
                }
                let reference = try mapped(anchor.reference, owner: "A measurement anchor")
                if reference != anchor.reference {
                    anchor.reference = reference
                    measurement.anchors[index].sketchReference = anchor
                    changed = true
                }
            }
            if changed {
                metadata.measurements[measurementID] = measurement
            }
        }
    }

    /// Rebuilds the Bridge Curves of every sketch after a change outside any one sketch (a
    /// document parameter can move a source or set a tension), replacing only the sketches whose
    /// bridges changed, and commits the sketches and their metadata together.
    mutating func regenerateAllBridgeCurves() throws {
        let featureIDs = Set(productMetadata.bridgeCurveSources.values.map(\.featureID))
            .sorted { $0.description < $1.description }
        guard featureIDs.isEmpty == false else {
            return
        }
        var updatedCADDocument = cadDocument
        var updatedMetadata = productMetadata
        for featureID in featureIDs {
            guard var feature = updatedCADDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve sources must point to existing sketch features."
                )
            }
            var regenerated = sketch
            try regenerateBridgeCurves(featureID: featureID, sketch: &regenerated, metadata: &updatedMetadata)
            guard regenerated != sketch else {
                continue
            }
            feature.operation = .sketch(regenerated)
            do {
                try updatedCADDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
            } catch {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve regeneration produced invalid sketch geometry: \(error)."
                )
            }
        }
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
    }

    /// A Bridge Curve is derived from its source: an edit of its control points would be undone
    /// by the next regeneration, so it is refused and the bridge is shaped by its parameters.
    func validateNotGeneratedBridgeCurve(featureID: FeatureID, entityID: SketchEntityID, operationName: String) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: {
            $0.featureID == featureID && $0.entityID == entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot edit a generated Bridge Curve; change its tensions or continuity instead."
            )
        }
    }

    /// A sketch constraint may relate a Bridge Curve's end points to other geometry, but not
    /// restate its continuity (the source owns it) nor name its interior control points (they
    /// are rebuilt from the source).
    func validateSketchConstraintOnBridgeCurves(
        _ constraint: SketchConstraint,
        featureID: FeatureID,
        sketch: Sketch,
        owner: String
    ) throws {
        for source in productMetadata.bridgeCurveSources.values where source.featureID == featureID {
            if constraintStatesBridgeContinuity(constraint, bridgeID: source.entityID) {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cannot set a generated Bridge Curve's continuity; change the bridge's continuity instead."
                )
            }
            guard case .spline(let bridge) = sketch.entities[source.entityID] else {
                continue
            }
            let references: [SketchReference] = switch constraint {
            case .coincident(let first, let second): [first, second]
            case .fixed(let reference): [reference]
            case .horizontal, .vertical, .parallel, .perpendicular, .equalLength, .tangent, .concentric,
                 .equalRadius, .smoothSplineControlPoint, .splineEndpointTangent, .tangentSplineEndpoints,
                 .smoothSplineEndpoints: []
            }
            for reference in references {
                if case .splineControlPoint(source.entityID, let index) = reference,
                   index != 0, index != bridge.controlPoints.count - 1 {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot name an interior control point of a generated Bridge Curve; refer to its ends."
                    )
                }
            }
        }
    }
}
