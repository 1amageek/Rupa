import Foundation
import SwiftCAD

public struct MeasurementAnchorWorldPointResolver: Sendable {
    public struct ResolvedAnchor: Codable, Equatable, Sendable {
        public var role: MeasurementAnchor.Role
        public var kind: MeasurementAnchor.Kind
        public var worldPoint: Point3D

        public init(
            role: MeasurementAnchor.Role,
            kind: MeasurementAnchor.Kind,
            worldPoint: Point3D
        ) {
            self.role = role
            self.kind = kind
            self.worldPoint = worldPoint
        }
    }

    private let curveSampler: SketchCurveSampler

    public init(curveSampler: SketchCurveSampler = SketchCurveSampler()) {
        self.curveSampler = curveSampler
    }

    public func resolvedAnchor(
        _ anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot? = nil
    ) throws -> ResolvedAnchor? {
        guard let worldPoint = try worldPoint(
            for: anchor,
            in: document,
            topology: topology
        ) else {
            return nil
        }
        return ResolvedAnchor(
            role: anchor.role,
            kind: anchor.kind,
            worldPoint: worldPoint
        )
    }

    public func worldPoint(
        for anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot? = nil
    ) throws -> Point3D? {
        try anchor.validate()
        let (sourceSceneNodeID, transform) = try placement(for: anchor, in: document)
        let resolvedWorldPoint: Point3D?
        switch anchor.kind {
        case .worldPoint:
            resolvedWorldPoint = anchor.localPoint ?? anchor.worldPoint
        case .sketchReference:
            guard let sketchReference = anchor.sketchReference else {
                return nil
            }
            resolvedWorldPoint = try worldPoint(
                for: sketchReference,
                in: document
            )
        case .sketchCurveParameter:
            guard let sketchCurveParameter = anchor.sketchCurveParameter else {
                return nil
            }
            resolvedWorldPoint = try worldPoint(
                for: sketchCurveParameter,
                in: document
            )
        case .topologyReference:
            guard var topologyReference = anchor.topologyReference,
                  let topology else {
                return nil
            }
            if let sourceSceneNodeID { topologyReference.sceneNodeID = sourceSceneNodeID }
            resolvedWorldPoint = worldPoint(
                for: topologyReference,
                role: anchor.role,
                in: topology
            )
        case .topologyEdgeParameter:
            guard var topologyEdgeParameter = anchor.topologyEdgeParameter,
                  let topology else {
                return nil
            }
            if let sourceSceneNodeID { topologyEdgeParameter.sceneNodeID = sourceSceneNodeID }
            resolvedWorldPoint = try worldPoint(
                for: topologyEdgeParameter,
                in: topology
            )
        }
        guard let point = resolvedWorldPoint,
              isFinite(point) else {
            return nil
        }
        return try transform.applied(to: point)
    }

    /// The anchor's placement: the scene node whose source geometry it names and the world
    /// transform of the node or occurrence that places that geometry.
    private func placement(
        for anchor: MeasurementAnchor,
        in document: DesignDocument
    ) throws -> (sourceSceneNodeID: SceneNodeID?, transform: Transform3D) {
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        // A sketch anchor without an explicit node is placed by the node presenting its sketch;
        // an unpresented sketch has no product placement and stays in the world frame.
        let sketchFeatureID = anchor.sketchReference?.featureID ?? anchor.sketchCurveParameter?.featureID
        let placementID = anchor.sceneNodeID
            ?? anchor.topologyReference?.sceneNodeID
            ?? anchor.topologyEdgeParameter?.sceneNodeID
            ?? sketchFeatureID.flatMap { hierarchy.presentingSceneNodeID(for: $0) }
        var transform = Transform3D.identity
        var sourceSceneNodeID = placementID
        if let placementID {
            if let occurrenceID = anchor.occurrenceID {
                guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }),
                      occurrence.sceneNodeID == placementID else {
                    throw EditorError(code: .referenceUnresolved,
                        message: "Measurement occurrence no longer matches its retained scene node.")
                }
                sourceSceneNodeID = occurrence.sourceSceneNodeID
                transform = occurrence.worldTransform
            } else {
                if anchor.kind != .worldPoint,
                   hierarchy.node(placementID)?.reference?.componentInstanceID != nil {
                    throw EditorError(code: .referenceUnresolved,
                        message: "Component geometry measurement requires an explicit occurrence.")
                }
                transform = try hierarchy.worldTransform(of: placementID)
            }
            if let featureID = anchor.sketchReference?.featureID ?? anchor.sketchCurveParameter?.featureID,
               let sourceSceneNodeID,
               hierarchy.node(sourceSceneNodeID)?.reference?.featureID != featureID {
                throw EditorError(code: .referenceUnresolved,
                    message: "Measurement sketch does not match its retained placement source.")
            }
        }
        return (sourceSceneNodeID, transform)
    }

    /// The topology entry a topology anchor names together with the world transform placing it.
    public func placedTopologyEntry(
        for anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> (entry: TopologySummaryResult.Entry, transform: Transform3D)? {
        try anchor.validate()
        guard var topologyReference = anchor.topologyReference else {
            return nil
        }
        let (sourceSceneNodeID, transform) = try placement(for: anchor, in: document)
        if let sourceSceneNodeID { topologyReference.sceneNodeID = sourceSceneNodeID }
        return topologyEntry(for: topologyReference, in: topology).map { ($0, transform) }
    }

    /// The length of a topology edge as placed in the world: the kernel's arc length of the
    /// edge curve's affine image under the anchor placement.
    public func placedEdgeLengthMeters(
        for anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> Double? {
        guard let placed = try placedTopologyEntry(for: anchor, in: document, topology: topology),
              placed.entry.kind == .edge else {
            return nil
        }
        guard let affine = try placed.transform.coordinateMap(to: .identity) else {
            return placed.entry.lengthMeters
        }
        guard let stableReference = placed.entry.stableReference,
              let evaluatedDocument = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved,
                message: "Placed edge length requires the evaluated edge.")
        }
        let tolerance = ModelingTolerance.standard
        let resolved = try EdgeQueryEvaluator(tolerance: tolerance).resolve(
            EdgeReference(subshape: stableReference), in: evaluatedDocument
        )
        let image = try Curve3D.affineImage(AffineImageCurve3D(
            source: resolved.curve, transform: affine, tolerance: tolerance
        ))
        let span = try ScalarInterval(
            lower: min(resolved.startParameter, resolved.endParameter),
            upper: max(resolved.startParameter, resolved.endParameter)
        )
        let length = try DefaultCurveArcLengthResolver().enclosure(
            of: image, over: span, tolerance: tolerance
        ).midpoint
        guard length.isFinite, length > tolerance.distance else {
            throw EditorError(code: .commandFailed, message: "Placed edge length is not representable.")
        }
        return length
    }

    /// The area of a planar topology face as placed in the world. The summary area exists only
    /// for planar faces, whose placed area scales by the area ratio of the placed face plane.
    public func placedFaceAreaSquareMeters(
        for anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> Double? {
        guard let placed = try placedTopologyEntry(for: anchor, in: document, topology: topology),
              placed.entry.kind == .face,
              let area = placed.entry.areaSquareMeters else {
            return nil
        }
        if placed.transform == .identity {
            return area
        }
        guard let normal = placed.entry.normal else {
            throw EditorError(code: .referenceUnresolved,
                message: "Placed face area requires the planar face normal.")
        }
        let tolerance = ModelingTolerance.standard.distance
        let n = try Vector3D(x: normal.x, y: normal.y, z: normal.z).normalized(tolerance: tolerance)
        let seed: Vector3D = abs(n.x) < 0.9 ? .unitX : .unitY
        let u = try n.cross(seed).normalized(tolerance: tolerance)
        let v = n.cross(u)
        let scale = try placed.transform.applyingLinearPart(to: u)
            .cross(placed.transform.applyingLinearPart(to: v)).length
        let placedArea = area * scale
        guard placedArea.isFinite, placedArea > 0 else {
            throw EditorError(code: .commandFailed, message: "Placed face area is not representable.")
        }
        return placedArea
    }

    private func worldPoint(
        for anchor: MeasurementSketchAnchor,
        in document: DesignDocument
    ) throws -> Point3D? {
        guard let feature = document.cadDocument.designGraph.nodes[anchor.featureID],
              case .sketch(let sketch) = feature.operation,
              let localPoint = try localPoint(
                  for: anchor.reference,
                  in: sketch,
                  parameters: document.cadDocument.parameters
              ) else {
            return nil
        }
        let sourceSystem = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        return sourceSystem.point(from: localPoint)
    }

    private func worldPoint(
        for anchor: MeasurementSketchCurveAnchor,
        in document: DesignDocument
    ) throws -> Point3D? {
        guard let feature = document.cadDocument.designGraph.nodes[anchor.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[anchor.entityID],
              let localPoint = try localPoint(
                  for: entity,
                  parameter: anchor.parameter,
                  parameters: document.cadDocument.parameters
              ) else {
            return nil
        }
        let sourceSystem = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        return sourceSystem.point(from: localPoint)
    }

    private func localPoint(
        for reference: SketchReference,
        in sketch: Sketch,
        parameters: ParameterTable
    ) throws -> Point2D? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                return nil
            }
            return try localPoint(from: point, parameters: parameters)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                return nil
            }
            return try localPoint(from: line.start, parameters: parameters)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                return nil
            }
            return try localPoint(from: line.end, parameters: parameters)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                return nil
            }
            return try localPoint(from: circle.center, parameters: parameters)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                return nil
            }
            return try localPoint(from: arc.center, parameters: parameters)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                return nil
            }
            return try arcEndpoint(
                arc,
                angle: arc.startAngle,
                parameters: parameters
            )
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                return nil
            }
            return try arcEndpoint(
                arc,
                angle: arc.endAngle,
                parameters: parameters
            )
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                return nil
            }
            return try localPoint(
                from: spline.controlPoints[index],
                parameters: parameters
            )
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    private func localPoint(
        for entity: SketchEntity,
        parameter: Double,
        parameters: ParameterTable
    ) throws -> Point2D? {
        guard let normalizedParameter = normalizedParameter(parameter) else {
            return nil
        }
        switch entity {
        case .point:
            return nil
        case let .line(line):
            return try linePoint(
                line,
                parameter: normalizedParameter,
                parameters: parameters
            )
        case let .circle(circle):
            return try circlePoint(
                circle,
                parameter: normalizedParameter,
                parameters: parameters
            )
        case let .arc(arc):
            return try arcPoint(
                arc,
                parameter: normalizedParameter,
                parameters: parameters
            )
        case let .spline(spline):
            return try splinePoint(
                spline,
                parameter: normalizedParameter,
                parameters: parameters
            )
        }
    }

    private func linePoint(
        _ line: SketchLine,
        parameter: Double,
        parameters: ParameterTable
    ) throws -> Point2D {
        let start = try localPoint(from: line.start, parameters: parameters)
        let end = try localPoint(from: line.end, parameters: parameters)
        return Point2D(
            x: start.x + (end.x - start.x) * parameter,
            y: start.y + (end.y - start.y) * parameter
        )
    }

    private func circlePoint(
        _ circle: SketchCircle,
        parameter: Double,
        parameters: ParameterTable
    ) throws -> Point2D? {
        let center = try localPoint(from: circle.center, parameters: parameters)
        let radius = try resolvedValue(circle.radius, kind: .length, parameters: parameters)
        guard radius.isFinite,
              radius > 1.0e-12 else {
            return nil
        }
        return offset(center, radius: radius, angle: parameter * Double.pi * 2.0)
    }

    private func arcPoint(
        _ arc: SketchArc,
        parameter: Double,
        parameters: ParameterTable
    ) throws -> Point2D? {
        let center = try localPoint(from: arc.center, parameters: parameters)
        let radius = try resolvedValue(arc.radius, kind: .length, parameters: parameters)
        let startAngle = try resolvedValue(arc.startAngle, kind: .angle, parameters: parameters)
        let endAngle = try resolvedValue(arc.endAngle, kind: .angle, parameters: parameters)
        guard radius.isFinite,
              radius > 1.0e-12,
              startAngle.isFinite,
              endAngle.isFinite else {
            return nil
        }
        let angle = startAngle + normalizedArcSpan(
            startAngle: startAngle,
            endAngle: endAngle
        ) * parameter
        return offset(center, radius: radius, angle: angle)
    }

    private func splinePoint(
        _ spline: SketchSpline,
        parameter: Double,
        parameters: ParameterTable
    ) throws -> Point2D? {
        let controlPoints = try spline.controlPoints.map { point in
            try localPoint(from: point, parameters: parameters)
        }
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return nil
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = parameter * Double(segmentCount)
        let segmentIndex: Int
        let localParameter: Double
        if parameter >= 1.0 {
            segmentIndex = segmentCount - 1
            localParameter = 1.0
        } else {
            segmentIndex = min(max(Int(floor(scaledParameter)), 0), segmentCount - 1)
            localParameter = scaledParameter - Double(segmentIndex)
        }
        return curveSampler.splineSegmentSample(
            for: controlPoints,
            segmentIndex: segmentIndex,
            t: localParameter
        )?.point
    }

    private func arcEndpoint(
        _ arc: SketchArc,
        angle: CADExpression,
        parameters: ParameterTable
    ) throws -> Point2D {
        let center = try localPoint(from: arc.center, parameters: parameters)
        let radius = try resolvedValue(arc.radius, kind: .length, parameters: parameters)
        let resolvedAngle = try resolvedValue(angle, kind: .angle, parameters: parameters)
        return offset(center, radius: radius, angle: resolvedAngle)
    }

    private func worldPoint(
        for anchor: MeasurementTopologyAnchor,
        role: MeasurementAnchor.Role,
        in topology: TopologySnapshot
    ) -> Point3D? {
        guard let entry = topologyEntry(for: anchor, in: topology) else {
            return nil
        }
        switch entry.kind {
        case .body:
            return nil
        case .face:
            return entry.center.map { point3D($0) }
        case .edge:
            guard let start = entry.start,
                  let end = entry.end else {
                return nil
            }
            switch role {
            case .start:
                return point3D(start)
            case .end:
                return point3D(end)
            case .point, .center:
                // The kernel's point halfway along the edge curve, not the chord midpoint.
                return entry.midpoint.map { point3D($0) }
            }
        case .vertex:
            return (entry.start ?? entry.center).map { point3D($0) }
        }
    }

    /// The exact point at a normalized edge parameter, evaluated by Swift-CAD's edge query on the
    /// same evaluation the topology snapshot summarizes.
    private func worldPoint(
        for anchor: MeasurementTopologyEdgeAnchor,
        in topology: TopologySnapshot
    ) throws -> Point3D? {
        guard let parameter = normalizedParameter(anchor.parameter),
              let entry = topologyEdgeEntry(for: anchor, in: topology),
              let stableReference = entry.stableReference,
              let evaluatedDocument = topology.evaluatedDocument else {
            return nil
        }
        let evaluator = EdgeQueryEvaluator(tolerance: .standard)
        let edge = EdgeReference(subshape: stableReference)
        let resolved = try evaluator.resolve(edge, in: evaluatedDocument)
        let curveParameter = resolved.startParameter + (resolved.endParameter - resolved.startParameter) * parameter
        let frame = try evaluator.frame(
            at: EdgeParameterReference(edge: edge, parameter: curveParameter),
            in: evaluatedDocument
        )
        return isFinite(frame.point) ? frame.point : nil
    }

    private func topologyEntry(
        for anchor: MeasurementTopologyAnchor,
        in topology: TopologySnapshot
    ) -> TopologySummaryResult.Entry? {
        topology.entries.first { entry in
            guard entry.kind == anchor.kind,
                  entry.subshapeID == anchor.subshapeID,
                  let target = entry.selectionTarget() else {
                return false
            }
            return target.sceneNodeID == anchor.sceneNodeID &&
                target.component == anchor.component
        }
    }

    private func topologyEdgeEntry(
        for anchor: MeasurementTopologyEdgeAnchor,
        in topology: TopologySnapshot
    ) -> TopologySummaryResult.Entry? {
        topology.entries.first { entry in
            guard entry.kind == .edge,
                  entry.subshapeID == anchor.subshapeID,
                  let target = entry.selectionTarget() else {
                return false
            }
            return target.sceneNodeID == anchor.sceneNodeID &&
                target.component == anchor.component
        }
    }

    private func point3D(
        _ point: TopologySummaryResult.Entry.Point
    ) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func normalizedParameter(_ parameter: Double) -> Double? {
        guard parameter.isFinite,
              parameter >= 0.0,
              parameter <= 1.0 else {
            return nil
        }
        return parameter
    }

    private func localPoint(
        from point: SketchPoint,
        parameters: ParameterTable
    ) throws -> Point2D {
        Point2D(
            x: try resolvedValue(point.x, kind: .length, parameters: parameters),
            y: try resolvedValue(point.y, kind: .length, parameters: parameters)
        )
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Measurement anchor expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func offset(_ center: Point2D, radius: Double, angle: Double) -> Point2D {
        Point2D(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func isFinite(_ point: Point3D) -> Bool {
        do {
            try point.validate()
            return true
        } catch {
            return false
        }
    }
}
