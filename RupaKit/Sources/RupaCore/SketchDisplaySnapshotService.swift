import Foundation
import SwiftCAD

public struct SketchDisplaySnapshotService: Sendable {
    public init() {}

    public func snapshots(document: DesignDocument) -> [FeatureID: SketchDisplaySnapshot] {
        let graph = document.cadDocument.designGraph
        let parameters = document.cadDocument.parameters
        var snapshots: [FeatureID: SketchDisplaySnapshot] = [:]
        for featureID in graph.order {
            guard let feature = graph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation,
                  let snapshot = snapshot(
                      featureID: featureID,
                      sketch: sketch,
                      parameters: parameters
                  ) else {
                continue
            }
            snapshots[featureID] = snapshot
        }
        return snapshots
    }

    func resolvedLength(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) -> Double? {
        do {
            let quantity = try parameters.resolvedValue(for: expression)
            guard quantity.kind == .length else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    func resolvedAngle(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) -> Double? {
        do {
            let quantity = try parameters.resolvedValue(for: expression)
            guard quantity.kind == .angle else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    func resolvedScalar(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) -> Double? {
        do {
            let quantity = try parameters.resolvedValue(for: expression)
            guard quantity.kind == .scalar else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    private func snapshot(
        featureID: FeatureID,
        sketch: Sketch,
        parameters: ParameterTable
    ) -> SketchDisplaySnapshot? {
        guard let bounds = bounds(
            for: sketch,
            parameters: parameters
        ) else {
            return nil
        }
        return SketchDisplaySnapshot(
            featureID: featureID,
            plane: sketch.plane,
            bounds: bounds,
            primitives: primitives(
                for: sketch,
                parameters: parameters
            ),
            regions: regions(
                for: sketch,
                featureID: featureID,
                parameters: parameters
            ),
            singleCircleProfileRadiusMeters: singleCircleProfileRadius(
                for: sketch,
                parameters: parameters
            ),
            straightOpenPathVector: straightOpenPathVector(
                for: sketch,
                parameters: parameters
            )
        )
    }

    private func bounds(
        for sketch: Sketch,
        parameters: ParameterTable
    ) -> SketchDisplaySnapshot.Bounds? {
        let points = sketch.entities.values.flatMap { entity in
            entityBoundsPoints(
                for: entity,
                plane: sketch.plane,
                parameters: parameters
            )
        }
        guard let firstPoint = points.first else {
            return nil
        }

        var minX = firstPoint.x
        var minY = firstPoint.y
        var maxX = firstPoint.x
        var maxY = firstPoint.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        return SketchDisplaySnapshot.Bounds(
            minX: minX,
            minY: minY,
            maxX: minX + max(width, 0.001),
            maxY: minY + max(height, 0.001)
        )
    }

    private func primitives(
        for sketch: Sketch,
        parameters: ParameterTable
    ) -> [SketchDisplaySnapshot.Primitive] {
        sketch.entities.compactMap { entityID, entity in
            switch entity {
            case .point(let point):
                guard let resolved = resolvedDisplayPoint(
                    point,
                    plane: sketch.plane,
                    parameters: parameters
                ) else {
                    return nil
                }
                return .point(entityID: entityID, point: resolved)
            case .line(let line):
                guard let start = resolvedDisplayPoint(
                    line.start,
                    plane: sketch.plane,
                    parameters: parameters
                ),
                      let end = resolvedDisplayPoint(
                          line.end,
                          plane: sketch.plane,
                          parameters: parameters
                      ) else {
                    return nil
                }
                return .line(entityID: entityID, start: start, end: end)
            case .circle(let circle):
                guard let center = resolvedDisplayPoint(
                    circle.center,
                    plane: sketch.plane,
                    parameters: parameters
                ),
                      let radius = resolvedLength(circle.radius, parameters: parameters) else {
                    return nil
                }
                return .circle(entityID: entityID, center: center, radiusMeters: radius)
            case .arc(let arc):
                guard let center = resolvedDisplayPoint(
                    arc.center,
                    plane: sketch.plane,
                    parameters: parameters
                ),
                      let radius = resolvedLength(arc.radius, parameters: parameters),
                      let startAngle = resolvedAngle(arc.startAngle, parameters: parameters),
                      let endAngle = resolvedAngle(arc.endAngle, parameters: parameters) else {
                    return nil
                }
                return .arc(
                    entityID: entityID,
                    center: center,
                    radiusMeters: radius,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                )
            case .spline(let spline):
                let controlPoints = resolvedSplineControlPoints(
                    spline,
                    plane: sketch.plane,
                    parameters: parameters
                )
                let points = splineSamplePoints(controlPoints: controlPoints)
                guard points.count >= 2 else {
                    return nil
                }
                return .spline(
                    entityID: entityID,
                    points: points,
                    controlPoints: controlPoints,
                    sketchPlane: sketch.plane
                )
            }
        }
    }

    private func regions(
        for sketch: Sketch,
        featureID: FeatureID,
        parameters: ParameterTable
    ) -> [SketchDisplaySnapshot.Region] {
        let profiles: [CADProfile]
        do {
            let resolvedParameters = try ParameterResolver().resolve(parameters)
            profiles = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: resolvedParameters
            )
        } catch {
            return []
        }

        let regionAnalyzer = ProfileRegionAnalyzer()
        return profiles.enumerated().compactMap { profileIndex, profile in
            let summary: ProfileRegionSummary
            do {
                summary = try regionAnalyzer.summary(for: profile)
            } catch {
                return nil
            }
            let points = summary.points.map { displayPoint(from: $0, on: profile.plane) }
            guard points.count >= 3 else {
                return nil
            }
            return SketchDisplaySnapshot.Region(
                componentID: .profileRegion(
                    featureID: featureID,
                    profileIndex: profileIndex
                ),
                points: points
            )
        }
    }

    private func singleCircleProfileRadius(
        for sketch: Sketch,
        parameters: ParameterTable
    ) -> Double? {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first,
              case .circle(let circle) = entity else {
            return nil
        }
        return resolvedLength(circle.radius, parameters: parameters)
    }

    private func entityBoundsPoints(
        for entity: SketchEntity,
        plane: SketchPlane,
        parameters: ParameterTable
    ) -> [Point2D] {
        switch entity {
        case .point(let point):
            guard let resolved = resolvedDisplayPoint(
                point,
                plane: plane,
                parameters: parameters
            ) else {
                return []
            }
            return [resolved]
        case .line(let line):
            guard let start = resolvedDisplayPoint(
                line.start,
                plane: plane,
                parameters: parameters
            ),
                  let end = resolvedDisplayPoint(
                      line.end,
                      plane: plane,
                      parameters: parameters
                  ) else {
                return []
            }
            return [start, end]
        case .circle(let circle):
            guard let center = resolvedDisplayPoint(
                circle.center,
                plane: plane,
                parameters: parameters
            ),
                  let radius = resolvedLength(circle.radius, parameters: parameters) else {
                return []
            }
            return [
                Point2D(x: center.x - radius, y: center.y - radius),
                Point2D(x: center.x + radius, y: center.y + radius),
            ]
        case .arc(let arc):
            guard let center = resolvedDisplayPoint(
                arc.center,
                plane: plane,
                parameters: parameters
            ),
                  let radius = resolvedLength(arc.radius, parameters: parameters),
                  let startAngle = resolvedAngle(arc.startAngle, parameters: parameters),
                  let endAngle = resolvedAngle(arc.endAngle, parameters: parameters) else {
                return []
            }
            return arcBoundsPoints(
                center: center,
                radiusMeters: radius,
                startAngleRadians: startAngle,
                endAngleRadians: endAngle
            )
        case .spline(let spline):
            return splineSamplePoints(
                controlPoints: resolvedSplineControlPoints(
                    spline,
                    plane: plane,
                    parameters: parameters
                )
            )
        }
    }

    private func resolvedSplineControlPoints(
        _ spline: SketchSpline,
        plane: SketchPlane,
        parameters: ParameterTable
    ) -> [Point2D] {
        guard spline.controlPoints.count >= 4,
              (spline.controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let controlPoints = spline.controlPoints.compactMap { point in
            resolvedDisplayPoint(
                point,
                plane: plane,
                parameters: parameters
            )
        }
        guard controlPoints.count == spline.controlPoints.count else {
            return []
        }
        return controlPoints
    }

    private func splineSamplePoints(controlPoints: [Point2D]) -> [Point2D] {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        var samples: [Point2D] = []
        let samplesPerSegment = 32
        for segmentStart in stride(from: 0, to: controlPoints.count - 1, by: 3) {
            let p0 = controlPoints[segmentStart]
            let p1 = controlPoints[segmentStart + 1]
            let p2 = controlPoints[segmentStart + 2]
            let p3 = controlPoints[segmentStart + 3]
            for index in 0 ... samplesPerSegment {
                if segmentStart > 0, index == 0 {
                    continue
                }
                let t = Double(index) / Double(samplesPerSegment)
                samples.append(cubicBezierPoint(p0, p1, p2, p3, t: t))
            }
        }
        return samples
    }

    private func cubicBezierPoint(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        t: Double
    ) -> Point2D {
        let oneMinusT = 1.0 - t
        let b0 = oneMinusT * oneMinusT * oneMinusT
        let b1 = 3.0 * oneMinusT * oneMinusT * t
        let b2 = 3.0 * oneMinusT * t * t
        let b3 = t * t * t
        return Point2D(
            x: p0.x * b0 + p1.x * b1 + p2.x * b2 + p3.x * b3,
            y: p0.y * b0 + p1.y * b1 + p2.y * b2 + p3.y * b3
        )
    }

    private func resolvedDisplayPoint(
        _ point: SketchPoint,
        plane: SketchPlane,
        parameters: ParameterTable
    ) -> Point2D? {
        guard let localPoint = resolvedPoint(point, parameters: parameters) else {
            return nil
        }
        return displayPoint(from: localPoint, on: plane)
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        parameters: ParameterTable
    ) -> Point2D? {
        guard let x = resolvedLength(point.x, parameters: parameters),
              let y = resolvedLength(point.y, parameters: parameters) else {
            return nil
        }
        return Point2D(x: x, y: y)
    }

    private func displayPoint(
        from localPoint: Point2D,
        on plane: SketchPlane
    ) -> Point2D {
        switch plane {
        case .xy, .yz, .plane:
            return localPoint
        case .zx:
            return Point2D(
                x: localPoint.y,
                y: localPoint.x
            )
        }
    }

    private func straightOpenPathVector(
        for sketch: Sketch,
        parameters: ParameterTable
    ) -> Vector3D? {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first,
              case .line(let line) = entity,
              let start = resolvedPoint(line.start, parameters: parameters),
              let end = resolvedPoint(line.end, parameters: parameters) else {
            return nil
        }
        do {
            let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketch.plane)
            let startPoint = coordinateSystem.point(from: start)
            let endPoint = coordinateSystem.point(from: end)
            let vector = Vector3D(
                x: endPoint.x - startPoint.x,
                y: endPoint.y - startPoint.y,
                z: endPoint.z - startPoint.z
            )
            return vector.length > 1.0e-9 ? vector : nil
        } catch {
            return nil
        }
    }

    private func arcBoundsPoints(
        center: Point2D,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> [Point2D] {
        let radius = max(radiusMeters, 1.0e-12)
        let span = normalizedArcSpan(
            startAngle: startAngleRadians,
            endAngle: endAngleRadians
        )
        let angles = arcBoundsAngles(startAngle: startAngleRadians, span: span)
        return angles.map { angle in
            Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func arcBoundsAngles(startAngle: Double, span: Double) -> [Double] {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var angles = [startAngle, startAngle + span]
        for baseAngle in [0.0, Double.pi / 2.0, Double.pi, Double.pi * 1.5, fullCircle] {
            var angle = baseAngle
            while angle < startAngle - tolerance {
                angle += fullCircle
            }
            if angle <= startAngle + span + tolerance {
                angles.append(angle)
            }
        }
        return angles
    }

    private func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngle - startAngle
        while span <= tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }
}
