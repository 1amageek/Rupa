import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct SketchCornerFilletCandidate {
        var center: SketchCornerPoint
        var selectedPoint: SketchCornerPoint
        var adjacentPoint: SketchCornerPoint
        var score: Double
    }

    private enum SketchCornerOffsetPrimitive {
        case line(point: SketchCornerPoint, direction: SketchCornerPoint)
        case circle(center: SketchCornerPoint, radius: Double)
    }

    func sketchCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        if case .line = selectedGeometry.entity,
           case .line = adjacentGeometry.entity {
            return try sketchLineLineCornerFilletCandidate(
                selectedGeometry: selectedGeometry,
                adjacentGeometry: adjacentGeometry,
                radius: radius
            )
        }
        return try sketchCurveCornerFilletCandidate(
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry,
            radius: radius
        )
    }

    func sketchLineLineCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        let dot = selectedGeometry.unit.dot(adjacentGeometry.unit)
        let angle = acos(min(max(dot, -1.0), 1.0))
        guard angle > ModelingTolerance.standard.angle,
              abs(Double.pi - angle) > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires a non-collinear line corner."
            )
        }
        let tangent = tan(angle / 2.0)
        guard tangent > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner fillet radius is invalid for the selected corner."
            )
        }
        let trimDistance = radius / tangent
        try validateSketchCornerTrimDistance(
            trimDistance,
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry
        )
        let bisector = try selectedGeometry.unit.adding(adjacentGeometry.unit).normalized(
            owner: "Sketch corner fillet bisector",
            tolerance: ModelingTolerance.standard.distance
        )
        let sine = sin(angle / 2.0)
        guard sine > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner fillet radius is invalid for the selected corner."
            )
        }
        let centerDistance = radius / sine
        let center = selectedGeometry.vertex.adding(bisector.scaled(by: centerDistance))
        return SketchCornerFilletCandidate(
            center: center,
            selectedPoint: try sketchCornerTreatmentPoint(from: selectedGeometry, distance: trimDistance),
            adjacentPoint: try sketchCornerTreatmentPoint(from: adjacentGeometry, distance: trimDistance),
            score: trimDistance + trimDistance
        )
    }

    private func sketchCurveCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        let selectedPrimitives = try sketchCornerOffsetPrimitives(
            for: selectedGeometry,
            radius: radius
        )
        let adjacentPrimitives = try sketchCornerOffsetPrimitives(
            for: adjacentGeometry,
            radius: radius
        )
        let tolerance = max(ModelingTolerance.standard.distance, radius * 1.0e-8)
        var candidates: [SketchCornerFilletCandidate] = []
        for selectedPrimitive in selectedPrimitives {
            for adjacentPrimitive in adjacentPrimitives {
                let centers = try sketchCornerOffsetIntersections(
                    first: selectedPrimitive,
                    second: adjacentPrimitive,
                    tolerance: tolerance
                )
                for center in centers {
                    let selectedPoints = try sketchCornerFilletTangentPoints(
                        center: center,
                        geometry: selectedGeometry,
                        radius: radius,
                        tolerance: tolerance
                    )
                    let adjacentPoints = try sketchCornerFilletTangentPoints(
                        center: center,
                        geometry: adjacentGeometry,
                        radius: radius,
                        tolerance: tolerance
                    )
                    for selectedPoint in selectedPoints {
                        for adjacentPoint in adjacentPoints {
                            do {
                                if let candidate = try validSketchCornerFilletCandidate(
                                    center: center,
                                    selectedPoint: selectedPoint,
                                    adjacentPoint: adjacentPoint,
                                    selectedGeometry: selectedGeometry,
                                    adjacentGeometry: adjacentGeometry,
                                    tolerance: tolerance
                                ) {
                                    candidates.append(candidate)
                                }
                            } catch let error as EditorError where error.code == .commandInvalid {
                                continue
                            } catch {
                                throw error
                            }
                        }
                    }
                }
            }
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment cannot construct a tangent fillet for the selected source curves."
            )
        }
        return best
    }

    private func validSketchCornerFilletCandidate(
        center: SketchCornerPoint,
        selectedPoint: SketchCornerPoint,
        adjacentPoint: SketchCornerPoint,
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        tolerance: Double
    ) throws -> SketchCornerFilletCandidate? {
        let selectedDistance = try sketchCornerPathDistance(
            fromEndpointOf: selectedGeometry,
            to: selectedPoint,
            owner: "Sketch corner fillet selected tangent point",
            tolerance: tolerance
        )
        let adjacentDistance = try sketchCornerPathDistance(
            fromEndpointOf: adjacentGeometry,
            to: adjacentPoint,
            owner: "Sketch corner fillet adjacent tangent point",
            tolerance: tolerance
        )
        guard selectedDistance > tolerance,
              adjacentDistance > tolerance,
              selectedGeometry.length - selectedDistance > tolerance,
              adjacentGeometry.length - adjacentDistance > tolerance else {
            return nil
        }
        return SketchCornerFilletCandidate(
            center: center,
            selectedPoint: selectedPoint,
            adjacentPoint: adjacentPoint,
            score: selectedDistance + adjacentDistance
        )
    }

    private func sketchCornerOffsetPrimitives(
        for geometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> [SketchCornerOffsetPrimitive] {
        if let arc = geometry.arc {
            var radii = [arc.radius + radius]
            let innerRadius = abs(arc.radius - radius)
            if innerRadius > ModelingTolerance.standard.distance,
               radii.contains(where: { abs($0 - innerRadius) <= ModelingTolerance.standard.distance }) == false {
                radii.append(innerRadius)
            }
            return radii.map {
                .circle(center: arc.center, radius: $0)
            }
        }
        let normal = geometry.unit.leftNormal
        return [
            .line(point: geometry.vertex.adding(normal.scaled(by: radius)), direction: geometry.unit),
            .line(point: geometry.vertex.adding(normal.scaled(by: -radius)), direction: geometry.unit),
        ]
    }

    private func sketchCornerOffsetIntersections(
        first: SketchCornerOffsetPrimitive,
        second: SketchCornerOffsetPrimitive,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        switch (first, second) {
        case (.line(let firstPoint, let firstDirection), .circle(let center, let radius)):
            return sketchCornerLineCircleIntersections(
                linePoint: firstPoint,
                lineDirection: firstDirection,
                circleCenter: center,
                circleRadius: radius,
                tolerance: tolerance
            )
        case (.circle, .line):
            return try sketchCornerOffsetIntersections(
                first: second,
                second: first,
                tolerance: tolerance
            )
        case (.circle(let firstCenter, let firstRadius), .circle(let secondCenter, let secondRadius)):
            return try sketchCornerCircleCircleIntersections(
                firstCenter: firstCenter,
                firstRadius: firstRadius,
                secondCenter: secondCenter,
                secondRadius: secondRadius,
                tolerance: tolerance
            )
        case (.line, .line):
            return []
        }
    }

    private func sketchCornerLineCircleIntersections(
        linePoint: SketchCornerPoint,
        lineDirection: SketchCornerPoint,
        circleCenter: SketchCornerPoint,
        circleRadius: Double,
        tolerance: Double
    ) -> [SketchCornerPoint] {
        let delta = circleCenter.subtracting(linePoint)
        let projection = delta.dot(lineDirection)
        let distanceSquared = delta.dot(delta) - projection * projection
        let radiusSquared = circleRadius * circleRadius
        let discriminant = radiusSquared - distanceSquared
        guard discriminant >= -tolerance else {
            return []
        }
        if abs(discriminant) <= tolerance {
            return [linePoint.adding(lineDirection.scaled(by: projection))]
        }
        let root = discriminant.squareRoot()
        return [
            linePoint.adding(lineDirection.scaled(by: projection - root)),
            linePoint.adding(lineDirection.scaled(by: projection + root)),
        ]
    }

    private func sketchCornerCircleCircleIntersections(
        firstCenter: SketchCornerPoint,
        firstRadius: Double,
        secondCenter: SketchCornerPoint,
        secondRadius: Double,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        let centerVector = secondCenter.subtracting(firstCenter)
        let centerDistance = firstCenter.distance(to: secondCenter)
        guard centerDistance > tolerance else {
            return []
        }
        guard centerDistance <= firstRadius + secondRadius + tolerance,
              centerDistance >= abs(firstRadius - secondRadius) - tolerance else {
            return []
        }
        let direction = try centerVector.normalized(
            owner: "Sketch corner circle intersection",
            tolerance: tolerance
        )
        let along = (
            firstRadius * firstRadius - secondRadius * secondRadius + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let heightSquared = firstRadius * firstRadius - along * along
        guard heightSquared >= -tolerance else {
            return []
        }
        let base = firstCenter.adding(direction.scaled(by: along))
        if abs(heightSquared) <= tolerance {
            return [base]
        }
        let normal = direction.leftNormal
        let height = heightSquared.squareRoot()
        return [
            base.adding(normal.scaled(by: height)),
            base.adding(normal.scaled(by: -height)),
        ]
    }

    private func sketchCornerFilletTangentPoints(
        center: SketchCornerPoint,
        geometry: SketchCornerEndpointGeometry,
        radius: Double,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        if let arc = geometry.arc {
            let radial = center.subtracting(arc.center)
            let unit: SketchCornerPoint
            do {
                unit = try radial.normalized(
                    owner: "Sketch corner arc tangent",
                    tolerance: tolerance
                )
            } catch let error as EditorError where error.code == .commandInvalid {
                return []
            } catch {
                throw error
            }
            var points: [SketchCornerPoint] = []
            for point in [
                arc.center.adding(unit.scaled(by: arc.radius)),
                arc.center.adding(unit.scaled(by: -arc.radius)),
            ] {
                guard abs(point.distance(to: center) - radius) <= max(tolerance, radius * 1.0e-8) else {
                    continue
                }
                do {
                    _ = try sketchCornerPathDistance(
                        fromEndpointOf: geometry,
                        to: point,
                        owner: "Sketch corner arc tangent",
                        tolerance: tolerance
                    )
                    points.append(point)
                } catch let error as EditorError where error.code == .commandInvalid {
                    continue
                } catch {
                    throw error
                }
            }
            return points
        }
        let distance = center.subtracting(geometry.vertex).dot(geometry.unit)
        let point = geometry.vertex.adding(geometry.unit.scaled(by: distance))
        guard abs(point.distance(to: center) - radius) <= max(tolerance, radius * 1.0e-8) else {
            return []
        }
        return [point]
    }

    func sketchCornerFilletEntity(
        center: SketchCornerPoint,
        selectedPoint: SketchCornerPoint,
        adjacentPoint: SketchCornerPoint,
        radius: Double,
        insertedEntityID: SketchEntityID
    ) throws -> (
        entity: SketchEntity,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) {
        let selectedAngle = atan2(selectedPoint.y - center.y, selectedPoint.x - center.x)
        let adjacentAngle = atan2(adjacentPoint.y - center.y, adjacentPoint.x - center.x)
        let selectedToAdjacentSpan = normalizedPositiveAngleSpan(
            from: selectedAngle,
            to: adjacentAngle
        )

        let startAngle: Double
        let endAngle: Double
        let selectedReference: SketchReference
        let adjacentReference: SketchReference
        if selectedToAdjacentSpan <= Double.pi {
            startAngle = selectedAngle
            endAngle = adjacentAngle
            selectedReference = .arcStart(insertedEntityID)
            adjacentReference = .arcEnd(insertedEntityID)
        } else {
            startAngle = adjacentAngle
            endAngle = selectedAngle
            selectedReference = .arcEnd(insertedEntityID)
            adjacentReference = .arcStart(insertedEntityID)
        }
        _ = try normalizedPartialArcSpan(
            startAngle: startAngle,
            endAngle: endAngle
        )

        return (
            entity: .arc(SketchArc(
                center: literalSketchPoint(center),
                radius: .length(radius, .meter),
                startAngle: .angle(startAngle, .radian),
                endAngle: .angle(endAngle, .radian)
            )),
            selectedReference: selectedReference,
            adjacentReference: adjacentReference
        )
    }

    private func normalizedPositiveAngleSpan(
        from startAngle: Double,
        to endAngle: Double
    ) -> Double {
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
}
