import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// A Bridge Curve between curves that do not share a sketch (Bridge Curve across sketches,
    /// Bridge Edge): Swift-CAD's bridge solver joins the two ends in world space, each read as
    /// exact geometry (a sketch curve in its sketch's frame carried by an affine image of its
    /// placed plane, an edge's curve carried by its body's placement), leaving the first end
    /// outward and arriving at the second against its outward direction. A bridge lying in one
    /// plane is kept exactly as a sketch spline on that plane; one that does not is a spatial
    /// path of one cubic span, exact up to G1 at both ends (degree three), and higher
    /// continuities off one plane are refused. Not associative: the ends are read once. Returns
    /// the created feature.
    @discardableResult
    public mutating func createSpatialBridgeCurve(
        first: SpatialBridgeEnd,
        second: SpatialBridgeEnd,
        continuity: BridgeCurveContinuity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let owner = "Bridge Curve"
        let tolerance = modelingSettings.tolerance
        let start = try spatialBridgeFrame(first, owner: owner)
        let end = try spatialBridgeFrame(second, owner: owner)
        let chord = (end.point - start.point).length
        func constraint(
            _ frame: (curve: Curve3D, parameter: Double, point: Point3D, outward: Vector3D, derivative: Vector3D),
            direction: Vector3D, level: BridgeCurveEndpointContinuity
        ) -> CurveBridgeEndpointConstraint {
            CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(
                    curve: frame.curve, parameter: frame.parameter,
                    orientation: frame.derivative.dot(direction) >= 0 ? .forward : .reversed
                ),
                requiredLevel: spatialContinuityLevel(level),
                derivativeMagnitude: level == .g0 ? nil : chord
            )
        }
        let request = CurveBridgeRequest(
            start: constraint(start, direction: start.outward, level: continuity.first),
            end: constraint(end, direction: end.outward * -1, level: continuity.second),
            continuityTolerances: .standard(modelingTolerance: tolerance)
        )
        let result: CurveBridgeResult
        do {
            result = try CurveBridgeSolver(modelingTolerance: tolerance).solve(request)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let points = result.curve.controlPoints
        if let plane = Self.commonPlane(of: points, tolerance: tolerance.distance) {
            let system = try SketchPlaneCoordinateSystem(plane: .plane(plane))
            let spline = SketchSpline(
                controlPoints: points.map { point in
                    let local = system.project(point).point
                    return sketchPoint(x: local.x, y: local.y)
                },
                degree: result.curve.degree
            )
            return try appendSketchFeature(
                name: "Bridge", sketch: Sketch(plane: .plane(plane), entities: [SketchEntityID(): .spline(spline)]),
                geometryRole: .curve, worldTransform: .identity, objectRegistry: objectRegistry
            )
        }
        // Off one plane the bridge is a spatial path, whose spans are cubic: a bridge of degree
        // three or less is one span exactly (raised to a cubic), a higher one cannot be held.
        let cubic: [Point3D]
        switch points.count - 1 {
        case 1:
            let d = points[1] - points[0]
            cubic = [points[0], points[0] + d * (1.0 / 3), points[0] + d * (2.0 / 3), points[1]]
        case 2:
            cubic = [points[0], points[0] + (points[1] - points[0]) * (2.0 / 3),
                     points[2] + (points[1] - points[2]) * (2.0 / 3), points[2]]
        case 3:
            cubic = points
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner): a bridge off one plane is kept as a cubic path, which cannot hold G2 or G3; use G1, or curves on one plane."
            )
        }
        let path = SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: cubic[0], outgoing: cubic[1] - cubic[0]),
            SpatialPathKnot(position: cubic[3], incoming: cubic[2] - cubic[3]),
        ])
        try path.validate(tolerance: tolerance)
        return try createWorldSpatialPath(name: "Bridge", path: path, objectRegistry: objectRegistry)
    }

    /// The nearest ends of two curves or edges, for Bridge on a selection of two.
    public func spatialBridgeEnds(joining targets: [SelectionTarget]) throws -> (SpatialBridgeEnd, SpatialBridgeEnd) {
        guard targets.count == 2 else {
            throw EditorError(code: .commandInvalid, message: "Bridge Curve joins two curves or edges.")
        }
        var best: (distance: Double, ends: (SpatialBridgeEnd, SpatialBridgeEnd))?
        for a in [0.0, 1.0] {
            for b in [0.0, 1.0] {
                let first = SpatialBridgeEnd(target: targets[0], fraction: a)
                let second = SpatialBridgeEnd(target: targets[1], fraction: b)
                let distance = (try spatialBridgeFrame(first, owner: "Bridge Curve").point
                    - (try spatialBridgeFrame(second, owner: "Bridge Curve").point)).length
                if best == nil || distance < best!.distance { best = (distance, (first, second)) }
            }
        }
        return best!.ends
    }

    /// A bridge end as exact world geometry: the curve, its parameter at the end's fraction, the
    /// point there, the outward direction the bridge leaves along, and the curve's derivative.
    private func spatialBridgeFrame(
        _ end: SpatialBridgeEnd, owner: String
    ) throws -> (curve: Curve3D, parameter: Double, point: Point3D, outward: Vector3D, derivative: Vector3D) {
        guard end.fraction.isFinite, end.fraction >= 0, end.fraction <= 1 else {
            throw EditorError(code: .commandInvalid, message: "\(owner) end must lie on its curve.")
        }
        let tolerance = modelingSettings.tolerance
        let curve: Curve3D
        let parameter: Double
        switch end.target.component {
        case .sketchEntity:
            let selection = try editableSketchEntity(for: end.target, operationName: owner)
            let local = try localSketchCurve(selection.entity, fraction: end.fraction, owner: owner)
            // The sketch's local frame (x, y, 0) carried to its placed plane in the world.
            let system = try placedSketchSystem(for: end.target, plane: selection.sketch.plane)
            curve = .affineImage(try AffineImageCurve3D(
                source: local.curve,
                transform: try AffineTransform3D(
                    basisX: system.u, basisY: system.v, basisZ: system.normal,
                    translation: system.origin - Point3D(x: 0, y: 0, z: 0)
                ),
                tolerance: tolerance
            ))
            parameter = local.parameter
        case .edge:
            let topology = try TopologySnapshotService().snapshot(document: self)
            guard let evaluated = topology.evaluatedDocument,
                  let entry = topology.entries.first(where: { $0.kind == .edge && $0.selectionTarget() == end.target }),
                  let reference = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) edge is not an edge of an evaluated body.")
            }
            let edge = try EdgeQueryEvaluator(tolerance: tolerance).resolve(EdgeReference(subshape: reference), in: evaluated)
            let v = try worldPlacement(of: end.target.sceneNodeID).matrix.values
            curve = .affineImage(try AffineImageCurve3D(
                source: edge.curve,
                transform: try AffineTransform3D(
                    basisX: Vector3D(x: v[0], y: v[4], z: v[8]), basisY: Vector3D(x: v[1], y: v[5], z: v[9]),
                    basisZ: Vector3D(x: v[2], y: v[6], z: v[10]), translation: Vector3D(x: v[3], y: v[7], z: v[11])
                ),
                tolerance: tolerance
            ))
            parameter = edge.startParameter + (edge.endParameter - edge.startParameter) * end.fraction
        default:
            throw EditorError(code: .commandInvalid, message: "\(owner) ends lie on sketch curves or body edges.")
        }
        let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        let derivative = geometry.firstDerivative
        let outward = end.fraction >= 0.5 ? derivative : derivative * -1
        return (curve, parameter, geometry.position, try outward.normalized(tolerance: tolerance.distance), derivative)
    }

    /// A sketch curve as exact geometry in its sketch's own coordinates (z = 0), with the
    /// parameter at `fraction`: a line on its arc length, an arc's or circle's circle on its
    /// angle, a spline on its own knots.
    private func localSketchCurve(_ entity: SketchEntity, fraction: Double, owner: String) throws -> (curve: Curve3D, parameter: Double) {
        switch entity {
        case .line(let line):
            let start = try resolvedSketchPoint(line.start, owner: "\(owner) line start")
            let end = try resolvedSketchPoint(line.end, owner: "\(owner) line end")
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else {
                throw EditorError(code: .commandInvalid, message: "\(owner) line must not be degenerate.")
            }
            return (.line(Line3D(
                origin: Point3D(x: start.x, y: start.y, z: 0),
                direction: Vector3D(x: (end.x - start.x) / length, y: (end.y - start.y) / length, z: 0)
            )), fraction * length)
        case .arc(let arc):
            let center = try resolvedSketchPoint(arc.center, owner: "\(owner) arc center")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end")
            return (.circle(Circle3D(center: Point3D(x: center.x, y: center.y, z: 0), normal: .unitZ,
                                     radius: try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius"))),
                    startAngle + fraction * positiveArcSpan(startAngle: startAngle, endAngle: endAngle))
        case .circle(let circle):
            let center = try resolvedSketchPoint(circle.center, owner: "\(owner) circle center")
            return (.circle(Circle3D(center: Point3D(x: center.x, y: center.y, z: 0), normal: .unitZ,
                                     radius: try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius"))),
                    fraction * 2 * Double.pi)
        case .spline(let spline):
            let planar = try resolvedSketchSplineCurve(spline, owner: owner)
            return (.bSpline(BSplineCurve3D(
                degree: planar.degree, knots: planar.bSpline.knots,
                controlPoints: planar.bSpline.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }
            )), planar.parameter(ofFraction: fraction))
        case .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) ends lie on curves, not points.")
        }
    }

    private func spatialContinuityLevel(_ continuity: BridgeCurveEndpointContinuity) -> CurveContinuityLevel {
        switch continuity {
        case .g0: .positional
        case .g1: .tangent
        case .g2: .curvature
        case .g3: .curvatureVariation
        }
    }

    /// A plane through every point within `tolerance`, or nil when they span space; collinear
    /// points take a plane through their line.
    static func commonPlane(of points: [Point3D], tolerance: Double) -> Plane3D? {
        guard let origin = points.first else { return nil }
        let offsets = points.map { $0 - origin }
        guard let far = offsets.max(by: { $0.length < $1.length }), far.length > tolerance else { return nil }
        let axis = far * (1 / far.length)
        let normal: Vector3D
        if let across = offsets.map({ axis.cross($0) }).max(by: { $0.length < $1.length }), across.length > tolerance {
            normal = across * (1 / across.length)
        } else {
            // Collinear: any plane through the line.
            let helper = abs(axis.z) < 0.9 ? Vector3D(x: 0, y: 0, z: 1) : Vector3D(x: 1, y: 0, z: 0)
            let across = axis.cross(helper)
            normal = across * (1 / across.length)
        }
        guard offsets.allSatisfy({ abs($0.dot(normal)) <= tolerance }) else { return nil }
        return Plane3D(origin: origin, normal: normal)
    }
}

extension DesignDocument {
    /// Where a view ray through the pointer lands on the sketch curve `target` names, as the
    /// fraction of its parameter nearest the ray's point on the sketch's plane: a Bridge Curve
    /// end placed by clicking.
    public func sketchCurveFraction(alongRay origin: Point3D, direction: Vector3D, on target: SelectionTarget) throws -> Double {
        let selection = try editableSketchEntity(for: target, operationName: "Bridge Curve")
        let point = try sketchPlanePoint(alongRay: origin, direction: direction, on: target)
        return try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
    }

    /// Bridge Curve between two ends placed by clicking: ends on one sketch make an associative
    /// sketch Bridge Curve at their parameters; others make a spatial bridge.
    @discardableResult
    public mutating func createBridgeCurve(
        clicked first: SpatialBridgeEnd,
        _ second: SpatialBridgeEnd,
        continuity: BridgeCurveContinuity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        if case .sketchEntity(let a) = first.target.component, case .sketchEntity(let b) = second.target.component,
           let firstReference = a.sketchEntityReference, let secondReference = b.sketchEntityReference,
           firstReference.featureID == secondReference.featureID, first.target.sceneNodeID == second.target.sceneNodeID {
            try createBridgeCurve(
                featureID: firstReference.featureID,
                firstEndpoint: BridgeCurveEndpoint(reference: .entity(firstReference.entityID), parameter: .scalar(first.fraction)),
                secondEndpoint: BridgeCurveEndpoint(reference: .entity(secondReference.entityID), parameter: .scalar(second.fraction)),
                continuity: continuity,
                objectRegistry: objectRegistry
            )
            return firstReference.featureID
        }
        return try createSpatialBridgeCurve(first: first, second: second, continuity: continuity, objectRegistry: objectRegistry)
    }
}
