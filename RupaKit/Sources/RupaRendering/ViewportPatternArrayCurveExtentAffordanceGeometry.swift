import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPatternArrayCurveExtentAffordanceGeometry: Equatable {
    var samples: [Sample]
    var baseDistanceMeters: Double
    var totalLengthMeters: Double
    var minimumDistanceMeters: Double

    init?(
        path: PatternArrayCurvePathGeometry,
        distributionLength: Double,
        layout: ViewportLayout,
        sampleCount: Int = 80,
        minimumDistanceMeters: Double = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
    ) {
        guard distributionLength.isFinite,
              distributionLength > 0.0,
              path.totalLength.isFinite,
              path.totalLength > minimumDistanceMeters,
              sampleCount >= 2,
              minimumDistanceMeters.isFinite,
              minimumDistanceMeters > 0.0 else {
            return nil
        }
        var samples: [Sample] = []
        samples.reserveCapacity(sampleCount + 1)
        do {
            for index in 0 ... sampleCount {
                let distance = path.totalLength * Double(index) / Double(sampleCount)
                let point = try path.sample(at: distance).point
                samples.append(Sample(
                    distanceMeters: distance,
                    projectedPoint: layout.project(point)
                ))
            }
        } catch {
            return nil
        }
        guard samples.count >= 2 else {
            return nil
        }
        self.samples = samples
        self.baseDistanceMeters = min(max(distributionLength, minimumDistanceMeters), path.totalLength)
        self.totalLengthMeters = path.totalLength
        self.minimumDistanceMeters = minimumDistanceMeters
    }

    var baseRatio: Double {
        baseDistanceMeters / totalLengthMeters
    }

    var pathPoints: [CGPoint] {
        samples.map(\.projectedPoint)
    }

    func projectedTip(distanceMeters: Double? = nil) -> CGPoint {
        projectedPoint(at: distanceMeters ?? baseDistanceMeters)
    }

    func projectedExtentPoints(distanceMeters: Double? = nil) -> [CGPoint] {
        let distance = min(max(distanceMeters ?? baseDistanceMeters, 0.0), totalLengthMeters)
        var points: [CGPoint] = []
        points.reserveCapacity(samples.count)
        for sample in samples {
            if sample.distanceMeters < distance {
                points.append(sample.projectedPoint)
            } else {
                break
            }
        }
        let tip = projectedPoint(at: distance)
        if points.last.map({ $0.distance(to: tip) > 1.0e-9 }) ?? true {
            points.append(tip)
        }
        return points.count >= 2 ? points : Array(samples.prefix(2).map(\.projectedPoint))
    }

    func extentDistance(
        current: CGPoint
    ) -> Double {
        min(max(nearestDistance(to: current), minimumDistanceMeters), totalLengthMeters)
    }

    func extentRatio(
        current: CGPoint
    ) -> Double {
        extentDistance(current: current) / totalLengthMeters
    }

    private func projectedPoint(at distanceMeters: Double) -> CGPoint {
        let distance = min(max(distanceMeters, 0.0), totalLengthMeters)
        for index in 1 ..< samples.count {
            let previous = samples[index - 1]
            let next = samples[index]
            guard distance <= next.distanceMeters else {
                continue
            }
            let span = next.distanceMeters - previous.distanceMeters
            let ratio = span > minimumDistanceMeters
                ? CGFloat((distance - previous.distanceMeters) / span)
                : 0.0
            return CGPoint(
                x: previous.projectedPoint.x + (next.projectedPoint.x - previous.projectedPoint.x) * ratio,
                y: previous.projectedPoint.y + (next.projectedPoint.y - previous.projectedPoint.y) * ratio
            )
        }
        return samples.last?.projectedPoint ?? .zero
    }

    private func nearestDistance(to point: CGPoint) -> Double {
        var bestDistance = samples.first?.distanceMeters ?? 0.0
        var bestScreenDistance = CGFloat.infinity
        for index in 1 ..< samples.count {
            let previous = samples[index - 1]
            let next = samples[index]
            let projection = projectedDistance(
                point: point,
                start: previous,
                end: next
            )
            if projection.screenDistance < bestScreenDistance {
                bestScreenDistance = projection.screenDistance
                bestDistance = projection.distanceMeters
            }
        }
        return bestDistance
    }

    private func projectedDistance(
        point: CGPoint,
        start: Sample,
        end: Sample
    ) -> (distanceMeters: Double, screenDistance: CGFloat) {
        let dx = end.projectedPoint.x - start.projectedPoint.x
        let dy = end.projectedPoint.y - start.projectedPoint.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-12 else {
            return (
                start.distanceMeters,
                point.distance(to: start.projectedPoint)
            )
        }
        let t = max(
            0.0,
            min(
                1.0,
                ((point.x - start.projectedPoint.x) * dx + (point.y - start.projectedPoint.y) * dy) / lengthSquared
            )
        )
        let projected = CGPoint(
            x: start.projectedPoint.x + dx * t,
            y: start.projectedPoint.y + dy * t
        )
        let distance = start.distanceMeters
            + (end.distanceMeters - start.distanceMeters) * Double(t)
        return (distance, point.distance(to: projected))
    }

    struct Sample: Equatable {
        var distanceMeters: Double
        var projectedPoint: CGPoint
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
