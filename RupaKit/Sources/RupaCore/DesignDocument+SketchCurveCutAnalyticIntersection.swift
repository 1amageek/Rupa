import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func cutFractionsForLineLineIntersection(
        target: CutCurveLineSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve line cutter must intersect the target line; parallel or overlapping lines are unsupported."
            )
        }

        let deltaX = cutter.startX - target.startX
        let deltaY = cutter.startY - target.startY
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction > tolerance,
              targetFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve intersection must fall inside the target curve segment, not on its endpoint."
            )
        }
        if extendsCutter == false {
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
        }
        return [targetFraction]
    }

    func cutFractionsForLineCircleIntersection(
        target: CutCurveLineSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = target.startX - circle.centerX
        let offsetY = target.startY - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return rawFractions.filter { fraction in
            guard fraction > tolerance,
                  fraction < 1.0 - tolerance else {
                return false
            }
            guard let arc else {
                return true
            }
            let pointX = target.startX + targetX * fraction
            let pointY = target.startY + targetY * fraction
            let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
            return cutCurveAngleIsOnArc(angle, startAngle: arc.startAngle, endAngle: arc.endAngle)
        }
    }

    func cutFractionsForArcLineIntersection(
        target: CutCurveArc,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.circle.centerX
        let offsetY = cutter.startY - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let targetFractions = rawCutterFractions.compactMap { cutterFraction -> Double? in
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
        if targetFractions.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return targetFractions
    }

    func cutFractionsForArcCircleIntersection(
        target: CutCurveArc,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target.circle,
            circle
        )
        return points.compactMap { point -> Double? in
            let targetAngle = atan2(
                point.y - target.circle.centerY,
                point.x - target.circle.centerX
            )
            guard cutCurveAngleIsOnArc(
                targetAngle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveArcFraction(for: targetAngle, on: target)
        }
    }

    func cutAnglesForCircleLineIntersection(
        target: CutCurveCircle,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.centerX
        let offsetY = cutter.startY - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let angles = rawCutterFractions.compactMap { cutterFraction -> Double? in
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
        if angles.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return angles
    }

    func cutAnglesForCircleCircleIntersection(
        target: CutCurveCircle,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target,
            circle
        )
        return points.compactMap { point -> Double? in
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return atan2(point.y - target.centerY, point.x - target.centerX)
        }
    }

    func cutCurveCircleCircleIntersections(
        _ first: CutCurveCircle,
        _ second: CutCurveCircle
    ) throws -> [(x: Double, y: Double)] {
        let deltaX = second.centerX - first.centerX
        let deltaY = second.centerY - first.centerY
        let distance = hypot(deltaX, deltaY)
        let tolerance = 1.0e-10
        guard distance > tolerance else {
            if abs(first.radius - second.radius) <= tolerance {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve coincident circular curves do not create discrete intersections in the current source subset."
                )
            }
            return []
        }
        guard distance <= first.radius + second.radius + tolerance,
              distance >= abs(first.radius - second.radius) - tolerance else {
            return []
        }

        let firstRadiusSquared = first.radius * first.radius
        let secondRadiusSquared = second.radius * second.radius
        let distanceSquared = distance * distance
        let centerOffset = (firstRadiusSquared - secondRadiusSquared + distanceSquared) /
            (2.0 * distance)
        let heightSquared = firstRadiusSquared - centerOffset * centerOffset
        guard heightSquared >= -1.0e-14 else {
            return []
        }

        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let baseX = first.centerX + centerOffset * unitX
        let baseY = first.centerY + centerOffset * unitY
        let height = sqrt(max(heightSquared, 0.0))
        if height <= tolerance {
            return [(x: baseX, y: baseY)]
        }
        let perpendicularX = -unitY * height
        let perpendicularY = unitX * height
        return [
            (x: baseX + perpendicularX, y: baseY + perpendicularY),
            (x: baseX - perpendicularX, y: baseY - perpendicularY),
        ]
    }
}
