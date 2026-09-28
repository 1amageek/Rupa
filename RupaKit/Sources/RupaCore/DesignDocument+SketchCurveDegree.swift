import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Raise Curve Degree on every target curve, as one step: a spline is raised exactly by
    /// Swift-CAD on its own parameter (every Bezier segment one degree up, joined at its breaks),
    /// and a line becomes a degree-2 spline through its ends and middle. An arc or a circle has no
    /// exact non-rational spline and a generated Bridge Curve takes its degree from its
    /// continuities, so each is refused. References to the curve's ends and joints follow them;
    /// a reference to any other control point, or a relation only a line can carry, refuses the
    /// command with the document unchanged.
    public mutating func raiseSketchCurveDegree(
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "Raise Curve Degree requires at least one sketch curve.")
        }
        var entitiesByFeature: [FeatureID: [SketchEntityID]] = [:]
        for target in targets {
            let selection = try editableSketchEntity(for: target, operationName: "Raise Curve Degree")
            try validateNotGeneratedBridgeCurve(
                featureID: selection.featureID,
                entityID: selection.entityID,
                operationName: "Raise Curve Degree"
            )
            entitiesByFeature[selection.featureID, default: []].append(selection.entityID)
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        for featureID in entitiesByFeature.keys.sorted(by: { $0.description < $1.description }) {
            guard var feature = cadDocument.designGraph.nodes[featureID],
                  case .sketch(var sketch) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "Raise Curve Degree requires an editable sketch feature.")
            }
            var metadata = productMetadata
            for entityID in Set(entitiesByFeature[featureID] ?? []).sorted(by: { $0.description < $1.description }) {
                try raiseDegree(of: entityID, featureID: featureID, sketch: &sketch, metadata: &metadata)
            }
            productMetadata = metadata
            if sketch.entities.count == 1 {
                try setSketchObjectType(featureID: featureID, typeID: .spline, objectRegistry: objectRegistry)
            } else {
                try markSketchObjectAsSourceEdited(featureID: featureID)
            }
            try commitSketchEntityEdit(
                featureID: featureID,
                feature: &feature,
                sketch: sketch,
                objectRegistry: objectRegistry,
                errorOwner: "Raise Curve Degree"
            )
        }
        didCommit = true
    }

    private func raiseDegree(
        of entityID: SketchEntityID,
        featureID: FeatureID,
        sketch: inout Sketch,
        metadata: inout ProductMetadata
    ) throws {
        let owner = "Raise Curve Degree"
        switch sketch.entities[entityID] {
        case .spline(let spline):
            guard spline.degree < SketchSpline.maximumDegree else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner): a sketch spline's degree is at most \(SketchSpline.maximumDegree)."
                )
            }
            let raised: SketchSpline
            do {
                raised = try SketchSplineRefinement().degreeElevated(spline)
            } catch let error as SketchError {
                throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
            }
            try validateSplineForm(raised, owner: owner)
            // The curve passes through the same points at the same knots: each old joint maps to
            // the raised joint at its knot value.
            let oldKnots = try splineKnots(spline, owner: owner)
            let newKnots = try splineKnots(raised, owner: owner)
            var jointMap: [Int: Int] = [:]
            for oldIndex in spline.jointIndices {
                let value = knotValue(ofJoint: oldIndex, in: spline, knots: oldKnots)
                if let newIndex = raised.jointIndices.first(where: { knotValue(ofJoint: $0, in: raised, knots: newKnots) == value }) {
                    jointMap[oldIndex] = newIndex
                }
            }
            sketch.entities[entityID] = .spline(raised)
            try rewriteSketchReferences(featureID: featureID, sketch: &sketch, metadata: &metadata) { reference in
                guard case .splineControlPoint(entityID, let index) = reference else { return reference }
                guard let mapped = jointMap[index] else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) moves every control point between the spline's joints; remove the relations on control point \(index) first."
                    )
                }
                return .splineControlPoint(entity: entityID, index: mapped)
            } smoothJoint: { id, index in
                guard id == entityID else { return index }
                guard let mapped = jointMap[index] else {
                    throw EditorError(code: .commandInvalid, message: "\(owner) found a smooth constraint off the spline's joints.")
                }
                return mapped
            }
        case .line(let line):
            try validateLineRelationsForRaise(entityID: entityID, sketch: sketch, owner: owner)
            let start = try resolvedSketchPoint(line.start, owner: "\(owner) line start")
            let end = try resolvedSketchPoint(line.end, owner: "\(owner) line end")
            guard hypot(end.x - start.x, end.y - start.y) > 1.0e-12 else {
                throw EditorError(code: .commandInvalid, message: "\(owner) requires a line with non-zero length.")
            }
            // A line is a degree-1 curve; raised, it is the degree-2 Bezier with its middle as the
            // control point, on the same parameter.
            sketch.entities[entityID] = .spline(SketchSpline(
                controlPoints: [line.start, interpolatedSketchPoint(line.start, line.end, fraction: .scalar(0.5)), line.end],
                degree: 2
            ))
            try rewriteSketchReferences(featureID: featureID, sketch: &sketch, metadata: &metadata) { reference in
                switch reference {
                case .lineStart(entityID): .splineControlPoint(entity: entityID, index: 0)
                case .lineEnd(entityID): .splineControlPoint(entity: entityID, index: 2)
                default: reference
                }
            } smoothJoint: { _, index in index }
        case .arc, .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) takes lines and splines: an arc or a circle has no exact spline without weights."
            )
        case .point, nil:
            throw EditorError(code: .commandInvalid, message: "\(owner) requires a line or spline curve.")
        }
    }

    /// Relations a line carries that a spline cannot: its orientation and its relations to other
    /// lines and circles refuse the raise.
    private func validateLineRelationsForRaise(entityID: SketchEntityID, sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            let lineOnly: Bool = switch constraint {
            case .horizontal(let id), .vertical(let id): id == entityID
            case .parallel(let first, let second), .perpendicular(let first, let second), .equalLength(let first, let second):
                first == entityID || second == entityID
            case .tangent(.lineCircular(let line, _, _)): line == entityID
            case .splineEndpointTangent(let tangency): tangency.line == entityID
            case .tangent(.circularCircular), .coincident, .fixed, .concentric, .equalRadius, .smoothSplineControlPoint,
                 .tangentSplineEndpoints, .smoothSplineEndpoints: false
            }
            if lineOnly {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot keep a relation only a line carries; remove it first.")
            }
        }
    }

    private func splineKnots(_ spline: SketchSpline, owner: String) throws -> [Double] {
        guard let knots = spline.knotVector else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the spline's knots could not be resolved.")
        }
        return knots
    }

    /// The knot where a clamped B-spline passes through joint control point `index`.
    private func knotValue(ofJoint index: Int, in spline: SketchSpline, knots: [Double]) -> Double {
        index == spline.controlPoints.count - 1 ? knots[knots.count - 1] : knots[index + 1]
    }

    /// Rewrites every stored reference of `featureID`'s sketch through `map`: constraints,
    /// dimensions, bridge ends (and their trim records' untrimmed ends) and measurement anchors;
    /// `smoothJoint` renumbers a joint smoothness constraint's index.
    func rewriteSketchReferences(
        featureID: FeatureID,
        sketch: inout Sketch,
        metadata: inout ProductMetadata,
        _ map: (SketchReference) throws -> SketchReference,
        smoothJoint: (SketchEntityID, Int) throws -> Int
    ) throws {
        sketch.constraints = try sketch.constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second): .coincident(try map(first), try map(second))
            case .fixed(let reference): .fixed(try map(reference))
            case .smoothSplineControlPoint(let id, let index): .smoothSplineControlPoint(entity: id, index: try smoothJoint(id, index))
            case .horizontal, .vertical, .parallel, .perpendicular, .equalLength, .tangent, .concentric, .equalRadius,
                 .splineEndpointTangent, .tangentSplineEndpoints, .smoothSplineEndpoints: constraint
            }
        }
        sketch.dimensions = try sketch.dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value): .distance(from: try map(from), to: try map(to), value: value)
            case .angle(let from, let to, let value): .angle(from: try map(from), to: try map(to), value: value)
            case .radius, .diameter: dimension
            }
        }
        for (sourceID, var source) in metadata.bridgeCurveSources where source.featureID == featureID {
            source.firstEndpoint.reference = try map(source.firstEndpoint.reference)
            source.secondEndpoint.reference = try map(source.secondEndpoint.reference)
            if var record = source.trimRecord {
                record.untrimmedFirstEndpoint.reference = try map(record.untrimmedFirstEndpoint.reference)
                record.untrimmedSecondEndpoint.reference = try map(record.untrimmedSecondEndpoint.reference)
                source.trimRecord = record
            }
            metadata.bridgeCurveSources[sourceID] = source
        }
        for (measurementID, var measurement) in metadata.measurements {
            for index in measurement.anchors.indices {
                guard var anchor = measurement.anchors[index].sketchReference, anchor.featureID == featureID else { continue }
                anchor.reference = try map(anchor.reference)
                measurement.anchors[index].sketchReference = anchor
            }
            metadata.measurements[measurementID] = measurement
        }
    }

    /// Convert Vertex: the spline stops passing through interior joint `index`, which stays as an
    /// ordinary control point pulling the curve. Its knot's multiplicity drops from the degree to
    /// one and the d − 1 control points around it that shaped the joint go, so the spline keeps
    /// its degree and gains explicit knots. The curve changes by design; references to the removed
    /// points refuse the command.
    public mutating func convertSketchSplineVertex(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let owner = "Convert Vertex"
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchControlPointReference else {
            throw EditorError(code: .commandInvalid, message: "\(owner) requires a spline vertex.")
        }
        let selection = try editableSketchEntity(
            for: SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(.sketchEntity(featureID: reference.featureID, entityID: reference.entityID))
            ),
            operationName: owner
        )
        try validateNotGeneratedBridgeCurve(featureID: selection.featureID, entityID: selection.entityID, operationName: owner)
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(code: .commandInvalid, message: "\(owner) requires a spline vertex.")
        }
        let joint = reference.index
        let joints = spline.jointIndices
        guard joints.dropFirst().dropLast().contains(joint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) takes an interior vertex the spline passes through; its ends stay on the curve."
            )
        }
        guard spline.degree >= 2 else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs a spline of degree 2 or more.")
        }
        let knots = try splineKnots(spline, owner: owner)
        let degree = spline.degree
        // Joint point `joint` sits at knot `joint + 1`, the first of `degree` equal knots; keep one.
        let removedKnots = Set((joint + 2)...(joint + degree))
        let after = (degree - 1) / 2, before = degree - 1 - after
        let removedPoints = Set(Array((joint - before)..<joint) + Array((joint + 1)..<(joint + 1 + after)))
        guard removedPoints.allSatisfy({ $0 > 0 && $0 < spline.controlPoints.count - 1 }) else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the vertex is too close to the spline's ends.")
        }
        var converted = spline
        converted.controlPoints = spline.controlPoints.enumerated().filter { !removedPoints.contains($0.offset) }.map(\.element)
        converted.knots = knots.enumerated().filter { !removedKnots.contains($0.offset) }.map(\.element)
        try validateSplineForm(converted, owner: owner)

        var sketch = selection.sketch
        var metadata = productMetadata
        sketch.entities[selection.entityID] = .spline(converted)
        let kept = spline.controlPoints.indices.filter { !removedPoints.contains($0) }
        let newIndex = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($0.element, $0.offset) })
        let entityID = selection.entityID
        try rewriteSketchReferences(featureID: selection.featureID, sketch: &sketch, metadata: &metadata) { reference in
            guard case .splineControlPoint(entityID, let index) = reference else { return reference }
            guard let mapped = newIndex[index] else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) removes control point \(index), which a relation names; remove it first."
                )
            }
            return .splineControlPoint(entity: entityID, index: mapped)
        } smoothJoint: { id, index in
            guard id == entityID else { return index }
            guard index != joint, let mapped = newIndex[index] else {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot keep the vertex's smooth constraint; remove it first.")
            }
            return mapped
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata = metadata
        if sketch.entities.count > 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        var feature = selection.feature
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: owner
        )
        didCommit = true
    }
}
