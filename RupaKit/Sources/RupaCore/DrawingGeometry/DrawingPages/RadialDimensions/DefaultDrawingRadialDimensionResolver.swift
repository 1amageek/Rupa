import SwiftCAD
import RupaCoreTypes

/// Binds a current generated edge or evaluated sketch circle to its original law.
public struct DefaultDrawingRadialDimensionResolver: DrawingRadialDimensionResolving {
    private let circles: any OriginalCircularMeasuring
    public init(circles: any OriginalCircularMeasuring = DefaultOriginalCircularMeasurer()) { self.circles = circles }

    public func resolve(_ measurement: MeasurementAnnotation,
        document: DesignDocument, evaluated: EvaluatedDocument,
        projection: DrawingOccurrenceProjection, options: DrawingGeometricPageOptions,
        usage: inout DrawingExchangeUsage) throws -> DrawingRadialDimensionMeasurement {
        try usage.check(); try projection.validateCurrent(document: document, evaluated: evaluated)
        guard measurement.kind == .radius || measurement.kind == .diameter,
            measurement.anchors.count == 1, let anchor = measurement.anchors.first else {
            throw invalid("Original radial edge measurement requires one radius or diameter anchor.")
        }
        var topologyAnchor = anchor
        if let parameter = anchor.topologyEdgeParameter, anchor.kind == .topologyEdgeParameter {
            topologyAnchor = MeasurementAnchor(kind: .topologyReference, role: anchor.role,
                sceneNodeID: anchor.sceneNodeID, occurrenceID: anchor.occurrenceID,
                topologyReference: MeasurementTopologyAnchor(sceneNodeID: parameter.sceneNodeID,
                    component: parameter.component, kind: .edge, subshapeID: parameter.subshapeID,
                    referenceID: parameter.referenceID))
        }
        if anchor.kind == .sketchReference || anchor.kind == .sketchCurveParameter {
            return try sketch(measurement, anchor: anchor, document: document,
                evaluated: evaluated, projection: projection, options: options, usage: &usage)
        }
        guard topologyAnchor.kind == .topologyReference,
            let binding = topologyAnchor.topologyReference, binding.kind == .edge,
            let subshapeID = GeneratedSubshapeIdentity.subshapeID(from: binding.subshapeID),
            binding.component == .edge(SelectionComponentID.generatedTopology(subshapeID)) else {
            throw invalid("Single radial dimension requires the current original generated edge reference.")
        }
        let tolerance = evaluated.configuration.tolerance
        let work = usage.preparationWorkCallback, bytes = usage.preparationStorageCallback
        let edge = try EdgeQueryEvaluator(tolerance: tolerance).resolveCurrentOriginalGeometry(
            subshapeID, in: evaluated,
            maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
            remainingSourceDepth: min(16, usage.maximumNesting),
            consumeWork: { _ in try work(1) }, consumeStorage: bytes,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
        var selected: Int?
        for index in projection.uses.indices {
            try usage.charge(work: 1)
            let use = projection.uses[index]
            guard use.original.edge.edgeID == edge.edgeID,
                use.featureID == subshapeID.featureID else { continue }
            let placementID = anchor.sceneNodeID ?? binding.sceneNodeID
            if let occurrenceID = anchor.occurrenceID {
                guard use.occurrenceID == occurrenceID, use.sceneNodeID == placementID else { continue }
            } else {
                guard use.sourceSceneNodeID == placementID, use.sceneNodeID == use.sourceSceneNodeID else { continue }
            }
            if let selected {
                let first = projection.uses[selected]
                guard first.occurrenceID == use.occurrenceID,
                    first.original.bodyID == use.original.bodyID else {
                    throw invalid("Original radial edge occurs in multiple visible body placements.")
                }
            } else { selected = index }
        }
        guard let selected else { throw invalid("Original radial edge has no visible current occurrence.") }
        let use = projection.uses[selected]
        let placement = projection.exchangeProjection.uses[selected].placement
        guard let word = placement.operationWord else {
            throw invalid("Original radial occurrence has no retained authored placement word.")
        }
        let original: OriginalCircularMeasurement
        if let parameter = anchor.topologyEdgeParameter, anchor.kind == .topologyEdgeParameter {
            original = try circles.measure(edge.curve, from: edge.startParameter, to: edge.endParameter,
                atNormalizedBoundaryParameter: parameter.parameter, placement: word, tolerance: tolerance,
                maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                remainingSourceDepth: min(16, usage.maximumNesting), maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
                consumeWork: { _ in try work(1) }, consumeStorage: bytes)
        } else {
            original = try circles.measure(edge.curve, at: edge.startParameter, placement: word,
                tolerance: tolerance, maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                remainingSourceDepth: min(16, usage.maximumNesting), maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
                consumeWork: { _ in try work(1) }, consumeStorage: bytes)
        }
        return try finish(measurement, anchor: anchor, original: original,
            occurrenceID: use.occurrenceID, bodyID: use.original.bodyID,
            sourceFeatureID: nil, sourceSketchEntityID: nil,
            projection: projection, options: options, usage: &usage)
    }

    private func sketch(_ measurement: MeasurementAnnotation, anchor: MeasurementAnchor,
        document: DesignDocument, evaluated: EvaluatedDocument,
        projection: DrawingOccurrenceProjection, options: DrawingGeometricPageOptions,
        usage: inout DrawingExchangeUsage) throws -> DrawingRadialDimensionMeasurement {
        let featureID: FeatureID, entityID: SketchEntityID
        var normalized: Double?
        var selectsEnd = false
        if let value = anchor.sketchCurveParameter, anchor.kind == .sketchCurveParameter {
            featureID = value.featureID; entityID = value.entityID; normalized = value.parameter
        } else if let value = anchor.sketchReference, anchor.kind == .sketchReference {
            featureID = value.featureID
            switch value.reference {
            case .entity(let id), .circleCenter(let id), .circleRadius(let id),
                .arcCenter(let id), .arcRadius(let id), .arcStart(let id): entityID = id
            case .arcEnd(let id): entityID = id; selectsEnd = true
            default: throw invalid("Original radial sketch reference does not name a circle or arc.")
            }
        } else { throw invalid("Original radial sketch anchor has no source reference.") }
        try usage.charge(work: 1)
        guard let node = evaluated.document.designGraph.nodes[featureID], !node.isSuppressed,
            case .sketch(let sketch) = node.operation, let entity = sketch.entities[entityID],
            let outputs = evaluated.curves[featureID] else {
            throw invalid("Original radial sketch feature/entity is not current.")
        }
        switch entity {
        case .circle, .arc: break
        default: throw invalid("Original radial sketch entity is not circular.")
        }
        if normalized != nil, case .circle = entity {
            // FIXME(INCOMPLETE_IMPLEMENTATION): A sketch circle's normalized local
            // angle is not always the evaluated native circle phase (ZX and authored
            // plane U directions differ). This explicit parameter path needs the
            // retained original phase chart before boundary/source publication.
            switch sketch.plane {
            case .xy, .yz: break
            default: throw invalid("Original sketch-circle parameter needs its retained plane phase chart.")
            }
        }
        var selectedCurve: Int?
        for index in outputs.indices {
            try usage.charge(work: 1)
            if outputs[index].source == .sketchEntity(entityID) {
                guard selectedCurve == nil, outputs[index].sourceFeatureID == featureID else {
                    throw invalid("Original sketch curve has ambiguous or foreign evaluated source binding.")
                }
                selectedCurve = index
            }
        }
        guard let selectedCurve else { throw invalid("Original sketch circle has no evaluated law.") }
        let tolerance = evaluated.configuration.tolerance
        let work = usage.preparationWorkCallback, bytes = usage.preparationStorageCallback
        let source = try outputs[selectedCurve].validateOriginalGeometry(tolerance: tolerance,
            maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
            remainingSourceDepth: min(16, usage.maximumNesting),
            consumeWork: { _ in try work(1) }, consumeStorage: bytes,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
        let occurrences = try SceneNodeHierarchy.originalDrawingOccurrences(
            in: document.productMetadata, usage: &usage)
        var selectedOccurrence: Int?
        var presentingNode: SceneNodeID?
        for (id, candidate) in document.productMetadata.sceneNodes {
            try usage.charge(work: 1)
            if candidate.reference?.featureID == featureID {
                guard presentingNode == nil else { throw invalid("Original sketch has multiple presenting nodes.") }
                presentingNode = id
            }
        }
        func contains(_ id: SceneNodeID, in values: [SceneNodeID], usage: inout DrawingExchangeUsage) throws -> Bool {
            for value in values { try usage.charge(work: 1); if value == id { return true } }
            return false
        }
        for index in occurrences.indices {
            try usage.charge(work: 1)
            let occurrence = occurrences[index]
            guard let presentingNode, occurrence.sourceSceneNodeID == presentingNode, occurrence.isVisible else { continue }
            if let explicit = anchor.occurrenceID {
                guard occurrence.id == explicit,
                    anchor.sceneNodeID.map({ $0 == occurrence.sceneNodeID }) ?? true else { continue }
            } else {
                guard occurrence.sceneNodeID == occurrence.sourceSceneNodeID,
                    anchor.sceneNodeID.map({ $0 == occurrence.sourceSceneNodeID }) ?? true else { continue }
            }
            let hidden = projection.savedView.visibility.hiddenSceneNodeIDs
            if try contains(occurrence.sceneNodeID, in: hidden, usage: &usage) { continue }
            if try contains(occurrence.sourceSceneNodeID, in: hidden, usage: &usage) { continue }
            let visible = projection.savedView.visibility.visibleSceneNodeIDs
            if !visible.isEmpty {
                let ownerVisible = try contains(occurrence.sceneNodeID, in: visible, usage: &usage)
                let sourceVisible = try contains(occurrence.sourceSceneNodeID, in: visible, usage: &usage)
                if !ownerVisible && !sourceVisible { continue }
            }
            guard selectedOccurrence == nil else { throw invalid("Original sketch radial occurrence is ambiguous.") }
            selectedOccurrence = index
        }
        let placement: OriginalAffineOperationWord?
        let occurrenceID: SceneOccurrenceID?
        if let selectedOccurrence {
            let occurrence = occurrences[selectedOccurrence]
            var admission = DrawingSourceAlgebraAdmission(usage: usage)
            placement = try DrawingOriginalPlacementWordBuilder().word(
                factors: occurrence.originalTransformFactors, usage: &admission)
            occurrenceID = occurrence.id
        } else {
            guard presentingNode == nil, anchor.sceneNodeID == nil, anchor.occurrenceID == nil else {
                throw invalid("Original sketch radial anchor has no visible matching occurrence.")
            }
            placement = nil; occurrenceID = nil
        }
        let original: OriginalCircularMeasurement
        if let normalized {
            original = try circles.measure(source.curve, from: source.startParameter, to: source.endParameter,
                atNormalizedBoundaryParameter: normalized, placement: placement, tolerance: tolerance,
                maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                remainingSourceDepth: min(16, usage.maximumNesting), maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
                consumeWork: { _ in try work(1) }, consumeStorage: bytes)
        } else {
            original = try circles.measure(source.curve,
                at: selectsEnd ? source.endParameter : source.startParameter,
                placement: placement, tolerance: tolerance,
                maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                remainingSourceDepth: min(16, usage.maximumNesting), maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
                consumeWork: { _ in try work(1) }, consumeStorage: bytes)
        }
        return try finish(measurement, anchor: anchor, original: original,
            occurrenceID: occurrenceID, bodyID: nil, sourceFeatureID: featureID,
            sourceSketchEntityID: entityID, projection: projection, options: options, usage: &usage)
    }

    private func finish(_ measurement: MeasurementAnnotation, anchor: MeasurementAnchor,
        original: OriginalCircularMeasurement, occurrenceID: SceneOccurrenceID?, bodyID: BodyID?,
        sourceFeatureID: FeatureID?, sourceSketchEntityID: SketchEntityID?,
        projection: DrawingOccurrenceProjection, options: DrawingGeometricPageOptions,
        usage: inout DrawingExchangeUsage) throws -> DrawingRadialDimensionMeasurement {
        let frame = projection.original.frame
        let center = try original.projectedCenter(on: frame)
        let boundary = try original.projectedBoundary(on: frame)
        func point(_ box: CoordinateEnclosure2D) throws -> Point2D {
            let value = Point2D(x: box.x.midpoint, y: box.y.midpoint)
            let error = (max(abs(value.x - box.x.lower), abs(box.x.upper - value.x))
                + max(abs(value.y - box.y.lower), abs(box.y.upper - value.y))).nextUp
            let paperError = (error * options.pointsPerMeter).nextUp
            guard paperError.isFinite, paperError <= (options.maximumCurveDeviation / 4).nextDown else {
                throw invalid("Original radial projection uncertainty exceeds paper precision.")
            }
            _ = try DrawingPaperMapper(options: options).map(value, sourceError: error)
            return value
        }
        func world(_ box: CoordinateEnclosure3D) -> Point3D {
            Point3D(x: box.x.midpoint, y: box.y.midpoint, z: box.z.midpoint)
        }
        let radius = try measurement.kind == .diameter ? original.diameterEnclosure() : original.radiusEnclosure
        let measured = radius.midpoint
        let uncertainty = max(abs(measured - radius.lower), abs(radius.upper - measured)).nextUp
        guard measured.isFinite,
            (uncertainty * options.pointsPerMeter).nextUp <= (options.maximumCurveDeviation / 4).nextDown else {
            throw invalid("Original radial metric exceeds paper precision.")
        }
        try usage.charge(bytes: 2 * MemoryLayout<DrawingProjectionResult.AnnotationAnchor>.stride
            + MemoryLayout<DrawingRadialDimensionMeasurement>.stride + 160)
        let anchors: [DrawingProjectionResult.AnnotationAnchor] = [.init(role: .center, kind: anchor.kind, worldPoint: world(original.centerEnclosure), point2D: try point(center)),
            .init(role: .point, kind: anchor.kind, worldPoint: world(original.boundaryPointEnclosure), point2D: try point(boundary))]
        let label = try measurement.labelPosition.map { try frame.project($0) } ?? anchors[1].point2D
        let text = LengthDisplayText.readableLengthString(fromMeters: measured,
            preferredUnit: projection.savedView.displayScale.displayUnit, maximumFractionDigits: 3)
        let resolved = DrawingProjectionResult.Annotation(id: measurement.id.description + ":drawing",
            measurementID: measurement.id, sceneNodeID: measurement.sceneNodeID, name: measurement.name,
            kind: measurement.kind, anchors: anchors, labelWorldPoint: measurement.labelPosition,
            labelPoint2D: label, measurementMeters: measured, displayText: text)
        return DrawingRadialDimensionMeasurement(annotation: resolved, original: original,
            occurrenceID: occurrenceID, bodyID: bodyID, sourceFeatureID: sourceFeatureID,
            sourceSketchEntityID: sourceSketchEntityID,
            projectedCenter: center, projectedBoundary: boundary)
    }
    private func invalid(_ message: String) -> EditorError { EditorError(code: .referenceUnresolved, message: message) }
}
