import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportSlotWidthAffordanceService {
    func candidate(
        for target: ViewportSlotWidthSourceTarget,
        primitives: [ViewportSketchPrimitive],
        widthMeters: Double,
        layout: ViewportLayout
    ) -> ViewportSlotWidthAffordanceCandidate? {
        guard let primitive = primitives.first(where: { $0.entityID == target.entityID }),
              let geometry = geometry(for: primitive, widthMeters: widthMeters, layout: layout) else {
            return nil
        }
        return ViewportSlotWidthAffordanceCandidate(
            target: ViewportSlotWidthHandleTarget(
                featureID: target.featureID,
                entityID: target.entityID,
                target: target.target,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    func geometry(
        for primitive: ViewportSketchPrimitive,
        widthMeters: Double,
        layout: ViewportLayout
    ) -> ViewportSlotWidthAffordanceGeometry? {
        switch primitive {
        case .line(_, let start, let end):
            return ViewportSlotWidthAffordanceGeometry(
                lineStart: start,
                lineEnd: end,
                widthMeters: widthMeters,
                layout: layout
            )
        case .arc(_, let center, let radiusMeters, let startAngleRadians, let endAngleRadians):
            return arcGeometry(
                center: center,
                radiusMeters: radiusMeters,
                startAngleRadians: startAngleRadians,
                endAngleRadians: endAngleRadians,
                widthMeters: widthMeters,
                layout: layout
            )
        case .spline(_, let points, _, _):
            return polylineGeometry(
                points: points,
                widthMeters: widthMeters,
                layout: layout
            )
        case .point,
             .circle:
            return nil
        }
    }

    private func arcGeometry(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        widthMeters: Double,
        layout: ViewportLayout
    ) -> ViewportSlotWidthAffordanceGeometry? {
        guard radiusMeters.isFinite, radiusMeters > 1.0e-12 else {
            return nil
        }
        let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
        guard span.isFinite, span > 1.0e-12 else {
            return nil
        }
        let angle = startAngleRadians + span * 0.5
        let radius = CGFloat(radiusMeters)
        let point = CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
        let tangent = CGPoint(
            x: -sin(CGFloat(angle)),
            y: cos(CGFloat(angle))
        )
        return ViewportSlotWidthAffordanceGeometry(
            baseModelPoint: point,
            modelDirection: normal(to: tangent),
            widthMeters: widthMeters,
            layout: layout
        )
    }

    private func polylineGeometry(
        points: [CGPoint],
        widthMeters: Double,
        layout: ViewportLayout
    ) -> ViewportSlotWidthAffordanceGeometry? {
        guard let frame = midpointFrame(points: points) else {
            return nil
        }
        return ViewportSlotWidthAffordanceGeometry(
            baseModelPoint: frame.point,
            modelDirection: normal(to: frame.tangent),
            widthMeters: widthMeters,
            layout: layout
        )
    }

    private func midpointFrame(points: [CGPoint]) -> (point: CGPoint, tangent: CGPoint)? {
        guard points.count >= 2 else {
            return nil
        }
        var lengths: [CGFloat] = []
        var totalLength: CGFloat = 0.0
        for index in 1 ..< points.count {
            let length = points[index - 1].distance(to: points[index])
            lengths.append(length)
            totalLength += length
        }
        guard totalLength > 1.0e-12 else {
            return nil
        }

        let targetLength = totalLength * 0.5
        var traversedLength: CGFloat = 0.0
        for index in 1 ..< points.count {
            let segmentLength = lengths[index - 1]
            guard segmentLength > 1.0e-12 else {
                continue
            }
            if traversedLength + segmentLength >= targetLength {
                let fraction = (targetLength - traversedLength) / segmentLength
                let start = points[index - 1]
                let end = points[index]
                return (
                    CGPoint(
                        x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction
                    ),
                    CGPoint(
                        x: (end.x - start.x) / segmentLength,
                        y: (end.y - start.y) / segmentLength
                    )
                )
            }
            traversedLength += segmentLength
        }

        let start = points[points.count - 2]
        let end = points[points.count - 1]
        let length = start.distance(to: end)
        guard length > 1.0e-12 else {
            return nil
        }
        return (
            end,
            CGPoint(
                x: (end.x - start.x) / length,
                y: (end.y - start.y) / length
            )
        )
    }

    private func normal(to tangent: CGPoint) -> CGPoint {
        CGPoint(x: -tangent.y, y: tangent.x)
    }
}
