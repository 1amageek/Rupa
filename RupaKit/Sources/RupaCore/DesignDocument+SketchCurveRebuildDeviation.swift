import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func sketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> SketchSplineRebuildDeviation {
        guard endFraction > startFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild generated an invalid deviation range."
            )
        }
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = (rebuiltControlPoints.count - 1) / 3
        let boundaries = sketchSplineDeviationBoundaries(
            startFraction: startFraction,
            endFraction: endFraction,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount
        )

        var maximumSquaredDistance = 0.0
        var maximumDistanceFraction = startFraction
        var squaredDistanceIntegral = 0.0
        var criticalPointCount = 0
        var evaluatedIntervalCount = 0

        for index in 0 ..< boundaries.count - 1 {
            let intervalStart = boundaries[index]
            let intervalEnd = boundaries[index + 1]
            guard intervalEnd > intervalStart + 1.0e-14 else {
                continue
            }
            let originalSegment = try cubicBezierSubcurve(
                controlPoints: originalControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let rebuiltSegment = try cubicBezierSubcurve(
                controlPoints: rebuiltControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let intervalDeviation = analyticCubicBezierDeviation(
                original: originalSegment,
                rebuilt: rebuiltSegment,
                globalStartFraction: intervalStart,
                globalEndFraction: intervalEnd
            )
            evaluatedIntervalCount += 1
            criticalPointCount += intervalDeviation.criticalPointCount
            squaredDistanceIntegral += intervalDeviation.squaredDistanceIntegral
            if intervalDeviation.maximumSquaredDistance > maximumSquaredDistance {
                maximumSquaredDistance = intervalDeviation.maximumSquaredDistance
                maximumDistanceFraction = intervalDeviation.maximumDistanceFraction
            }
        }
        let rangeLength = endFraction - startFraction
        let meanSquaredDistance = squaredDistanceIntegral / rangeLength
        return SketchSplineRebuildDeviation(
            maximumDistance: sqrt(max(0.0, maximumSquaredDistance)),
            rootMeanSquareDistance: sqrt(max(0.0, meanSquaredDistance)),
            maximumDistanceFraction: maximumDistanceFraction,
            evaluatedIntervalCount: evaluatedIntervalCount,
            criticalPointCount: criticalPointCount
        )
    }

    private func sketchSplineDeviationBoundaries(
        startFraction: Double,
        endFraction: Double,
        originalSegmentCount: Int,
        rebuiltSegmentCount: Int
    ) -> [Double] {
        var boundaries = [startFraction, endFraction]
        appendSplineSegmentBoundaries(
            segmentCount: originalSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        appendSplineSegmentBoundaries(
            segmentCount: rebuiltSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        return sortedUniqueFractions(boundaries)
    }

    private func appendSplineSegmentBoundaries(
        segmentCount: Int,
        startFraction: Double,
        endFraction: Double,
        to boundaries: inout [Double]
    ) {
        guard segmentCount > 1 else {
            return
        }
        for boundaryIndex in 1 ..< segmentCount {
            let boundary = Double(boundaryIndex) / Double(segmentCount)
            if boundary > startFraction + 1.0e-12,
               boundary < endFraction - 1.0e-12 {
                boundaries.append(boundary)
            }
        }
    }

    private func sortedUniqueFractions(_ fractions: [Double]) -> [Double] {
        var unique: [Double] = []
        for fraction in fractions.sorted() {
            if unique.last.map({ abs($0 - fraction) <= 1.0e-12 }) == true {
                continue
            }
            unique.append(fraction)
        }
        return unique
    }

    private func cubicBezierSubcurve(
        controlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> CubicBezierSegment2D {
        let start = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: startFraction,
            side: .after
        )
        let end = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: endFraction,
            side: .before
        )
        guard start.segmentIndex == end.segmentIndex,
              end.localFraction > start.localFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild deviation interval must stay inside one cubic span."
            )
        }

        let segmentStart = start.segmentIndex * 3
        var segment = CubicBezierSegment2D(
            p0: controlPoints[segmentStart],
            p1: controlPoints[segmentStart + 1],
            p2: controlPoints[segmentStart + 2],
            p3: controlPoints[segmentStart + 3]
        )
        if start.localFraction > 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: start.localFraction
            ).right
        }
        let remainingLength = 1.0 - start.localFraction
        let endInTrimmedSegment = (end.localFraction - start.localFraction) / remainingLength
        if endInTrimmedSegment < 1.0 - 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: endInTrimmedSegment
            ).left
        }
        return segment
    }

    private func cubicSplineSegmentLocation(
        controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> CubicSplineSegmentLocation {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            return CubicSplineSegmentLocation(segmentIndex: 0, localFraction: 0.0)
        }
        if scaledFraction >= Double(segmentCount) {
            return CubicSplineSegmentLocation(segmentIndex: segmentCount - 1, localFraction: 1.0)
        }
        if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                return CubicSplineSegmentLocation(
                    segmentIndex: max(0, boundary - 1),
                    localFraction: 1.0
                )
            case .after:
                return CubicSplineSegmentLocation(
                    segmentIndex: min(segmentCount - 1, boundary),
                    localFraction: 0.0
                )
            }
        }
        let segmentIndex = max(0, Int(floor(scaledFraction)))
        return CubicSplineSegmentLocation(
            segmentIndex: segmentIndex,
            localFraction: scaledFraction - Double(segmentIndex)
        )
    }

    private func splitCubicBezier(
        _ segment: CubicBezierSegment2D,
        fraction: Double
    ) -> (left: CubicBezierSegment2D, right: CubicBezierSegment2D) {
        let q0 = interpolate(from: segment.p0, to: segment.p1, fraction: fraction)
        let q1 = interpolate(from: segment.p1, to: segment.p2, fraction: fraction)
        let q2 = interpolate(from: segment.p2, to: segment.p3, fraction: fraction)
        let r0 = interpolate(from: q0, to: q1, fraction: fraction)
        let r1 = interpolate(from: q1, to: q2, fraction: fraction)
        let s = interpolate(from: r0, to: r1, fraction: fraction)
        return (
            left: CubicBezierSegment2D(p0: segment.p0, p1: q0, p2: r0, p3: s),
            right: CubicBezierSegment2D(p0: s, p1: r1, p2: q2, p3: segment.p3)
        )
    }

    private func analyticCubicBezierDeviation(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D,
        globalStartFraction: Double,
        globalEndFraction: Double
    ) -> AnalyticCubicBezierDeviation {
        let squaredDistance = squaredDistancePolynomial(
            original: original,
            rebuilt: rebuilt
        )
        let derivative = polynomialDerivative(squaredDistance)
        let roots = polynomialRootsInUnitInterval(derivative)
            .filter { $0 > 1.0e-10 && $0 < 1.0 - 1.0e-10 }
        let candidates = [0.0, 1.0] + roots
        var maximumSquaredDistance = 0.0
        var maximumLocalFraction = 0.0
        for candidate in candidates {
            let value = max(0.0, polynomialEvaluate(squaredDistance, at: candidate))
            if value > maximumSquaredDistance {
                maximumSquaredDistance = value
                maximumLocalFraction = candidate
            }
        }
        let intervalLength = globalEndFraction - globalStartFraction
        let squaredDistanceIntegral = intervalLength
            * max(0.0, polynomialUnitIntegral(squaredDistance))
        return AnalyticCubicBezierDeviation(
            maximumSquaredDistance: maximumSquaredDistance,
            maximumDistanceFraction: globalStartFraction
                + intervalLength * maximumLocalFraction,
            squaredDistanceIntegral: squaredDistanceIntegral,
            criticalPointCount: roots.count
        )
    }

    private func squaredDistancePolynomial(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D
    ) -> [Double] {
        let originalX = cubicBezierPowerCoefficients(
            original.p0.x,
            original.p1.x,
            original.p2.x,
            original.p3.x
        )
        let originalY = cubicBezierPowerCoefficients(
            original.p0.y,
            original.p1.y,
            original.p2.y,
            original.p3.y
        )
        let rebuiltX = cubicBezierPowerCoefficients(
            rebuilt.p0.x,
            rebuilt.p1.x,
            rebuilt.p2.x,
            rebuilt.p3.x
        )
        let rebuiltY = cubicBezierPowerCoefficients(
            rebuilt.p0.y,
            rebuilt.p1.y,
            rebuilt.p2.y,
            rebuilt.p3.y
        )
        let deltaX = zip(originalX, rebuiltX).map { $0 - $1 }
        let deltaY = zip(originalY, rebuiltY).map { $0 - $1 }
        return polynomialAdd(
            polynomialMultiply(deltaX, deltaX),
            polynomialMultiply(deltaY, deltaY)
        )
    }

    private func cubicBezierPowerCoefficients(
        _ p0: Double,
        _ p1: Double,
        _ p2: Double,
        _ p3: Double
    ) -> [Double] {
        [
            p0,
            -3.0 * p0 + 3.0 * p1,
            3.0 * p0 - 6.0 * p1 + 3.0 * p2,
            -p0 + 3.0 * p1 - 3.0 * p2 + p3,
        ]
    }

    private func polynomialAdd(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        var result = Array(repeating: 0.0, count: count)
        for index in lhs.indices {
            result[index] += lhs[index]
        }
        for index in rhs.indices {
            result[index] += rhs[index]
        }
        return result
    }

    private func polynomialMultiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.isEmpty == false,
              rhs.isEmpty == false else {
            return []
        }
        var result = Array(repeating: 0.0, count: lhs.count + rhs.count - 1)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func polynomialDerivative(_ coefficients: [Double]) -> [Double] {
        guard coefficients.count > 1 else {
            return [0.0]
        }
        return coefficients.dropFirst().enumerated().map { index, coefficient in
            coefficient * Double(index + 1)
        }
    }

    private func polynomialUnitIntegral(_ coefficients: [Double]) -> Double {
        coefficients.enumerated().reduce(0.0) { partial, element in
            partial + element.element / Double(element.offset + 1)
        }
    }

    private func polynomialEvaluate(
        _ coefficients: [Double],
        at fraction: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * fraction + coefficient
        }
    }

    private func polynomialRootsInUnitInterval(_ coefficients: [Double]) -> [Double] {
        let trimmed = trimmedPolynomial(coefficients)
        let degree = trimmed.count - 1
        guard degree > 0 else {
            return []
        }
        let valueTolerance = polynomialValueTolerance(trimmed)
        if degree == 1 {
            let root = -trimmed[0] / trimmed[1]
            guard root >= -1.0e-12,
                  root <= 1.0 + 1.0e-12 else {
                return []
            }
            return [min(max(root, 0.0), 1.0)]
        }

        let criticalPoints = polynomialRootsInUnitInterval(
            polynomialDerivative(trimmed)
        )
        let splitPoints = sortedUniqueFractions([0.0] + criticalPoints + [1.0])
        var roots: [Double] = []
        for point in splitPoints where abs(polynomialEvaluate(trimmed, at: point)) <= valueTolerance {
            roots.append(point)
        }
        for index in 0 ..< splitPoints.count - 1 {
            let start = splitPoints[index]
            let end = splitPoints[index + 1]
            guard end > start + 1.0e-12 else {
                continue
            }
            let startValue = polynomialEvaluate(trimmed, at: start)
            let endValue = polynomialEvaluate(trimmed, at: end)
            if startValue * endValue < 0.0 {
                roots.append(
                    bisectedPolynomialRoot(
                        trimmed,
                        lower: start,
                        upper: end,
                        lowerValue: startValue,
                        tolerance: valueTolerance
                    )
                )
            }
        }
        return sortedUniqueFractions(
            roots.map { min(max($0, 0.0), 1.0) }
        )
    }

    private func bisectedPolynomialRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double,
        lowerValue: Double,
        tolerance: Double
    ) -> Double {
        var low = lower
        var high = upper
        var lowValue = lowerValue
        for _ in 0 ..< 80 {
            let mid = (low + high) * 0.5
            let midValue = polynomialEvaluate(coefficients, at: mid)
            if abs(midValue) <= tolerance || high - low <= 1.0e-13 {
                return mid
            }
            if lowValue * midValue <= 0.0 {
                high = mid
            } else {
                low = mid
                lowValue = midValue
            }
        }
        return (low + high) * 0.5
    }

    private func trimmedPolynomial(_ coefficients: [Double]) -> [Double] {
        var trimmed = coefficients
        let tolerance = polynomialValueTolerance(coefficients)
        while trimmed.count > 1,
              abs(trimmed.last ?? 0.0) <= tolerance {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func polynomialValueTolerance(_ coefficients: [Double]) -> Double {
        max(1.0e-24, (coefficients.map { abs($0) }.max() ?? 0.0) * 1.0e-12)
    }

}
