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
        let resolvedWorldPoint: Point3D?
        switch anchor.kind {
        case .worldPoint:
            resolvedWorldPoint = anchor.worldPoint
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
            guard let topologyReference = anchor.topologyReference,
                  let topology else {
                return nil
            }
            resolvedWorldPoint = worldPoint(
                for: topologyReference,
                role: anchor.role,
                in: topology
            )
        case .topologyEdgeParameter:
            guard let topologyEdgeParameter = anchor.topologyEdgeParameter,
                  let topology else {
                return nil
            }
            resolvedWorldPoint = worldPoint(
                for: topologyEdgeParameter,
                in: topology
            )
        }
        guard let worldPoint = resolvedWorldPoint,
              isFinite(worldPoint) else {
            return nil
        }
        return worldPoint
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
                return Point3D(
                    x: (start.x + end.x) * 0.5,
                    y: (start.y + end.y) * 0.5,
                    z: (start.z + end.z) * 0.5
                )
            }
        case .vertex:
            return (entry.start ?? entry.center).map { point3D($0) }
        }
    }

    private func worldPoint(
        for anchor: MeasurementTopologyEdgeAnchor,
        in topology: TopologySnapshot
    ) -> Point3D? {
        guard let parameter = normalizedParameter(anchor.parameter),
              let entry = topologyEdgeEntry(for: anchor, in: topology) else {
            return nil
        }
        switch entry.curveKind {
        case "line":
            return lineEdgeWorldPoint(for: entry, parameter: parameter)
        case "circle":
            return circleEdgeWorldPoint(for: entry, parameter: parameter)
        default:
            return nil
        }
    }

    private func lineEdgeWorldPoint(
        for entry: TopologySummaryResult.Entry,
        parameter: Double
    ) -> Point3D? {
        guard let origin = entry.curveOrigin,
              let direction = entry.curveDirection,
              let range = entry.edgeParameterRange,
              range.start.isFinite,
              range.end.isFinite else {
            return nil
        }
        let curveParameter = range.start + (range.end - range.start) * parameter
        guard curveParameter.isFinite else {
            return nil
        }
        let point = Point3D(
            x: origin.x + direction.x * curveParameter,
            y: origin.y + direction.y * curveParameter,
            z: origin.z + direction.z * curveParameter
        )
        guard isFinite(point) else {
            return nil
        }
        return point
    }

    private func circleEdgeWorldPoint(
        for entry: TopologySummaryResult.Entry,
        parameter: Double
    ) -> Point3D? {
        guard let center = entry.curveCenter,
              let xAxis = entry.curveParameterXAxis,
              let yAxis = entry.curveParameterYAxis,
              let radius = entry.curveRadius,
              let range = entry.edgeParameterRange,
              radius.isFinite,
              radius > 1.0e-12,
              range.start.isFinite,
              range.end.isFinite else {
            return nil
        }
        let curveParameter = range.start + (range.end - range.start) * parameter
        guard curveParameter.isFinite else {
            return nil
        }
        let cosine = cos(curveParameter)
        let sine = sin(curveParameter)
        let point = Point3D(
            x: center.x + (xAxis.x * cosine + yAxis.x * sine) * radius,
            y: center.y + (xAxis.y * cosine + yAxis.y * sine) * radius,
            z: center.z + (xAxis.z * cosine + yAxis.z * sine) * radius
        )
        guard isFinite(point) else {
            return nil
        }
        return point
    }

    private func topologyEntry(
        for anchor: MeasurementTopologyAnchor,
        in topology: TopologySnapshot
    ) -> TopologySummaryResult.Entry? {
        topology.entries.first { entry in
            guard entry.kind == anchor.kind,
                  entry.persistentName == anchor.persistentName,
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
                  entry.persistentName == anchor.persistentName,
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
