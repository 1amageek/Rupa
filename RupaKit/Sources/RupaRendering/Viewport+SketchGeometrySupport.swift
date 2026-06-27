import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

extension Array where Element == ViewportSketchPrimitive {
    func firstLine(with entityID: SketchEntityID) -> (start: CGPoint, end: CGPoint)? {
        for primitive in self {
            guard case .line(let primitiveEntityID, let start, let end) = primitive,
                  primitiveEntityID == entityID else {
                continue
            }
            return (start, end)
        }
        return nil
    }

    func firstArc(
        with entityID: SketchEntityID
    ) -> (
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    )? {
        for primitive in self {
            guard case .arc(
                let primitiveEntityID,
                let center,
                let radiusMeters,
                let startAngleRadians,
                let endAngleRadians
            ) = primitive,
                  primitiveEntityID == entityID else {
                continue
            }
            return (center, radiusMeters, startAngleRadians, endAngleRadians)
        }
        return nil
    }

    func firstSpline(
        with entityID: SketchEntityID
    ) -> (
        points: [CGPoint],
        controlPoints: [CGPoint],
        sketchPlane: SketchPlane
    )? {
        for primitive in self {
            guard case .spline(
                let primitiveEntityID,
                let points,
                let controlPoints,
                let sketchPlane
            ) = primitive,
                  primitiveEntityID == entityID else {
                continue
            }
            return (points, controlPoints, sketchPlane)
        }
        return nil
    }
}

func projectedArcPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    layout: ViewportLayout,
    segmentCount: Int
) -> [CGPoint] {
    arcSamplePoints(
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        endAngleRadians: endAngleRadians,
        segmentCount: segmentCount
    ).map { layout.project($0) }
}

func arcSamplePoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    segmentCount: Int
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let count = max(segmentCount, 2)
    return (0 ... count).map { index in
        let ratio = Double(index) / Double(count)
        let angle = startAngleRadians + span * ratio
        return CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

func arcBoundsPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let angles = arcBoundsAngles(startAngle: startAngleRadians, span: span)
    return angles.map { angle in
        CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

func arcBoundsAngles(startAngle: Double, span: Double) -> [Double] {
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

func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
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

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var corners: [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
        ]
    }

    var handlePoints: [CGPoint] {
        corners + [
            CGPoint(x: midX, y: minY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: minX, y: midY),
            CGPoint(x: maxX, y: midY),
        ]
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-12 else {
            return distance(to: start)
        }

        let t = max(
            0.0,
            min(
                1.0,
                ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared
            )
        )
        let projection = CGPoint(
            x: start.x + t * dx,
            y: start.y + t * dy
        )
        return distance(to: projection)
    }

    func distanceToPolyline(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else {
            return .infinity
        }
        var bestDistance = CGFloat.infinity
        for index in 1 ..< points.count {
            bestDistance = min(
                bestDistance,
                distanceToSegment(start: points[index - 1], end: points[index])
            )
        }
        return bestDistance
    }
}
