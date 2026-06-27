import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func rebuiltSketchSplineByPointCount(
        _ spline: SketchSpline,
        controlPointCount: Int,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard controlPointCount >= 4,
              (controlPointCount - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Points method requires a 3n + 1 control point count of at least 4."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let rebuiltSegmentCount = (controlPointCount - 1) / 3
        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: rebuiltSegmentCount
                ),
            ],
            tangentWeight: 1.0,
            owner: owner
        )
    }

    func rebuiltSketchSplineByRefit(
        _ spline: SketchSpline,
        tolerance: CADExpression,
        keepsCorners: Bool,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let toleranceMeters = try resolvedPositiveLengthValue(
            tolerance,
            owner: "\(owner) Refit tolerance"
        )
        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let intervals: [SketchSplineRebuildInterval]
        if keepsCorners {
            intervals = try refitIntervalsKeepingCorners(
                originalControlPoints,
                originalSegmentCount: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
        } else {
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: 0.0,
                endFraction: 1.0,
                originalSegmentSpan: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
            intervals = [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: segmentCount
                ),
            ]
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: intervals,
            tangentWeight: 1.0,
            owner: owner
        )
    }

    func rebuiltSketchSplineByExplicitControl(
        _ spline: SketchSpline,
        degree: Int,
        spanCount: Int,
        weight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard degree == 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control currently supports degree 3 cubic Bezier output; degree \(degree) requires a B-spline/NURBS source model."
            )
        }
        guard spanCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control requires at least one span."
            )
        }
        guard weight.isFinite,
              weight >= 0.0,
              weight <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control weight must be between 0 and 1."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: spanCount
                ),
            ],
            tangentWeight: weight,
            owner: owner
        )
    }

    private func rebuiltSketchSpline(
        from spline: SketchSpline,
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        tangentWeight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = intervals.reduce(0) { $0 + $1.segmentCount }
        guard rebuiltSegmentCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least one rebuilt span."
            )
        }
        var rebuiltControlPoints: [SketchPoint] = []
        rebuiltControlPoints.reserveCapacity(rebuiltSegmentCount * 3 + 1)
        var indexMap: [Int: Int] = [:]

        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }

            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let handles = sketchSplineRebuildHandles(
                    start: start,
                    end: end,
                    span: span,
                    tangentWeight: tangentWeight
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(
                        sketchPoint(x: start.point.x, y: start.point.y)
                    )
                    mapOriginalKnotIfAligned(
                        fraction: startFraction,
                        originalSegmentCount: originalSegmentCount,
                        rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                        into: &indexMap
                    )
                }
                rebuiltControlPoints.append(sketchPoint(x: handles.first.x, y: handles.first.y))
                rebuiltControlPoints.append(sketchPoint(x: handles.second.x, y: handles.second.y))
                rebuiltControlPoints.append(sketchPoint(x: end.point.x, y: end.point.y))
                mapOriginalKnotIfAligned(
                    fraction: endFraction,
                    originalSegmentCount: originalSegmentCount,
                    rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                    into: &indexMap
                )
            }
        }

        let rebuiltSpline = SketchSpline(
            controlPoints: rebuiltControlPoints,
            isClosed: spline.isClosed
        )
        try validateSpline(rebuiltSpline, owner: owner)
        let rebuiltControlPointValues = try resolvedSplineControlPoints(
            rebuiltSpline,
            owner: owner
        )
        let deviation = try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPointValues,
            startFraction: 0.0,
            endFraction: 1.0
        )
        return RebuiltSketchSpline(
            spline: rebuiltSpline,
            originalControlPointCount: originalControlPoints.count,
            rebuiltControlPointCount: rebuiltControlPoints.count,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount,
            deviation: deviation,
            controlPointIndexMap: indexMap
        )
    }

    private func sketchSplineRebuildHandles(
        start: SketchSplineRebuildSample,
        end: SketchSplineRebuildSample,
        span: Double,
        tangentWeight: Double
    ) -> (first: CADCore.Point2D, second: CADCore.Point2D) {
        let chord = CADCore.Point2D(
            x: end.point.x - start.point.x,
            y: end.point.y - start.point.y
        )
        let chordFirst = CADCore.Point2D(
            x: start.point.x + chord.x / 3.0,
            y: start.point.y + chord.y / 3.0
        )
        let chordSecond = CADCore.Point2D(
            x: end.point.x - chord.x / 3.0,
            y: end.point.y - chord.y / 3.0
        )
        let tangentFirst = CADCore.Point2D(
            x: start.point.x + start.derivative.x * span / 3.0,
            y: start.point.y + start.derivative.y * span / 3.0
        )
        let tangentSecond = CADCore.Point2D(
            x: end.point.x - end.derivative.x * span / 3.0,
            y: end.point.y - end.derivative.y * span / 3.0
        )
        return (
            first: interpolate(
                from: chordFirst,
                to: tangentFirst,
                fraction: tangentWeight
            ),
            second: interpolate(
                from: chordSecond,
                to: tangentSecond,
                fraction: tangentWeight
            )
        )
    }

    func interpolate(
        from first: CADCore.Point2D,
        to second: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        CADCore.Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func refitIntervalsKeepingCorners(
        _ originalControlPoints: [CADCore.Point2D],
        originalSegmentCount: Int,
        tolerance: Double,
        owner: String
    ) throws -> [SketchSplineRebuildInterval] {
        let cornerBoundaries = cornerKnotSegmentBoundaries(
            originalControlPoints
        )
        var boundaries = [0]
        boundaries.append(contentsOf: cornerBoundaries)
        boundaries.append(originalSegmentCount)

        var intervals: [SketchSplineRebuildInterval] = []
        intervals.reserveCapacity(boundaries.count - 1)
        for index in 0 ..< boundaries.count - 1 {
            let startBoundary = boundaries[index]
            let endBoundary = boundaries[index + 1]
            let span = endBoundary - startBoundary
            guard span > 0 else {
                continue
            }
            let startFraction = Double(startBoundary) / Double(originalSegmentCount)
            let endFraction = Double(endBoundary) / Double(originalSegmentCount)
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: startFraction,
                endFraction: endFraction,
                originalSegmentSpan: span,
                tolerance: tolerance,
                owner: owner
            )
            intervals.append(
                SketchSplineRebuildInterval(
                    startFraction: startFraction,
                    endFraction: endFraction,
                    segmentCount: segmentCount
                )
            )
        }
        return intervals
    }

    private func refitSegmentCount(
        originalControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double,
        originalSegmentSpan: Int,
        tolerance: Double,
        owner: String
    ) throws -> Int {
        for segmentCount in 1 ... originalSegmentSpan {
            let candidateControlPoints = try rebuiltSketchSplineControlPoints(
                originalControlPoints: originalControlPoints,
                intervals: [
                    SketchSplineRebuildInterval(
                        startFraction: startFraction,
                        endFraction: endFraction,
                        segmentCount: segmentCount
                    ),
                ],
                owner: owner
            )
            let deviation = try maxSketchSplineDeviation(
                originalControlPoints: originalControlPoints,
                rebuiltControlPoints: candidateControlPoints,
                startFraction: startFraction,
                endFraction: endFraction
            )
            if deviation <= tolerance {
                return segmentCount
            }
        }
        return originalSegmentSpan
    }

    private func rebuiltSketchSplineControlPoints(
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        owner: String
    ) throws -> [CADCore.Point2D] {
        var rebuiltControlPoints: [CADCore.Point2D] = []
        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }
            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let firstHandle = CADCore.Point2D(
                    x: start.point.x + start.derivative.x * span / 3.0,
                    y: start.point.y + start.derivative.y * span / 3.0
                )
                let secondHandle = CADCore.Point2D(
                    x: end.point.x - end.derivative.x * span / 3.0,
                    y: end.point.y - end.derivative.y * span / 3.0
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(start.point)
                }
                rebuiltControlPoints.append(firstHandle)
                rebuiltControlPoints.append(secondHandle)
                rebuiltControlPoints.append(end.point)
            }
        }
        return rebuiltControlPoints
    }

    private func maxSketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> Double {
        try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPoints,
            startFraction: startFraction,
            endFraction: endFraction
        ).maximumDistance
    }

    private func cornerKnotSegmentBoundaries(
        _ controlPoints: [CADCore.Point2D]
    ) -> [Int] {
        let segmentCount = (controlPoints.count - 1) / 3
        guard segmentCount > 1 else {
            return []
        }

        var boundaries: [Int] = []
        for segmentBoundary in 1 ..< segmentCount {
            let knotIndex = segmentBoundary * 3
            let incoming = CADCore.Point2D(
                x: controlPoints[knotIndex].x - controlPoints[knotIndex - 1].x,
                y: controlPoints[knotIndex].y - controlPoints[knotIndex - 1].y
            )
            let outgoing = CADCore.Point2D(
                x: controlPoints[knotIndex + 1].x - controlPoints[knotIndex].x,
                y: controlPoints[knotIndex + 1].y - controlPoints[knotIndex].y
            )
            if isCornerBetweenSplineHandles(incoming: incoming, outgoing: outgoing) {
                boundaries.append(segmentBoundary)
            }
        }
        return boundaries
    }

    private func isCornerBetweenSplineHandles(
        incoming: CADCore.Point2D,
        outgoing: CADCore.Point2D
    ) -> Bool {
        let incomingLength = vectorLength(incoming)
        let outgoingLength = vectorLength(outgoing)
        let tinyLength = 1.0e-12
        guard incomingLength > tinyLength,
              outgoingLength > tinyLength else {
            return true
        }
        let dot = (incoming.x * outgoing.x + incoming.y * outgoing.y)
            / (incomingLength * outgoingLength)
        let clampedDot = min(max(dot, -1.0), 1.0)
        return clampedDot < cos(1.0e-4)
    }

    private func distance(
        _ first: CADCore.Point2D,
        _ second: CADCore.Point2D
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func vectorLength(_ vector: CADCore.Point2D) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y)
    }

    private func mapOriginalKnotIfAligned(
        fraction: Double,
        originalSegmentCount: Int,
        rebuiltControlPointIndex: Int,
        into indexMap: inout [Int: Int]
    ) {
        let scaled = fraction * Double(originalSegmentCount)
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) <= 1.0e-9 else {
            return
        }
        let segmentBoundary = Int(rounded)
        guard segmentBoundary >= 0,
              segmentBoundary <= originalSegmentCount else {
            return
        }
        indexMap[segmentBoundary * 3] = rebuiltControlPointIndex
    }

    private func resolvedSplineControlPoints(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CADCore.Point2D] {
        try spline.controlPoints.enumerated().map { index, point in
            let resolved = try resolvedRebuildPoint(
                point,
                owner: "\(owner) control point \(index + 1)"
            )
            return CADCore.Point2D(x: resolved.x, y: resolved.y)
        }
    }

    private func resolvedRebuildPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    private func sketchSplineRebuildSample(
        on controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> SketchSplineRebuildSample {
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
        let segmentIndex: Int
        let localFraction: Double
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            segmentIndex = 0
            localFraction = 0.0
        } else if scaledFraction >= Double(segmentCount) {
            segmentIndex = segmentCount - 1
            localFraction = 1.0
        } else if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                segmentIndex = max(0, boundary - 1)
                localFraction = 1.0
            case .after:
                segmentIndex = min(segmentCount - 1, boundary)
                localFraction = 0.0
            }
        } else {
            segmentIndex = max(0, Int(floor(scaledFraction)))
            localFraction = scaledFraction - Double(segmentIndex)
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let localDerivative = cubicBezierDerivative(
            p0,
            p1,
            p2,
            p3,
            fraction: localFraction
        )
        return SketchSplineRebuildSample(
            point: cubicBezierPoint(
                p0,
                p1,
                p2,
                p3,
                fraction: localFraction
            ),
            derivative: CADCore.Point2D(
                x: localDerivative.x * Double(segmentCount),
                y: localDerivative.y * Double(segmentCount)
            )
        )
    }

    private func cubicBezierPoint(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        let inverseSquared = inverse * inverse
        let fractionSquared = fraction * fraction
        let inverseCubed = inverseSquared * inverse
        let fractionCubed = fractionSquared * fraction
        return CADCore.Point2D(
            x: inverseCubed * p0.x
                + 3.0 * inverseSquared * fraction * p1.x
                + 3.0 * inverse * fractionSquared * p2.x
                + fractionCubed * p3.x,
            y: inverseCubed * p0.y
                + 3.0 * inverseSquared * fraction * p1.y
                + 3.0 * inverse * fractionSquared * p2.y
                + fractionCubed * p3.y
        )
    }

    private func cubicBezierDerivative(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        return CADCore.Point2D(
            x: 3.0 * inverse * inverse * (p1.x - p0.x)
                + 6.0 * inverse * fraction * (p2.x - p1.x)
                + 3.0 * fraction * fraction * (p3.x - p2.x),
            y: 3.0 * inverse * inverse * (p1.y - p0.y)
                + 6.0 * inverse * fraction * (p2.y - p1.y)
                + 3.0 * fraction * fraction * (p3.y - p2.y)
        )
    }
}
