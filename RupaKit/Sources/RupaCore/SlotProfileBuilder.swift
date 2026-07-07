import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SlotProfileBuilder: Sendable {
    public static let defaultSplineSamplesPerSegment = 32

    public struct PathPoint: Sendable, Equatable {
        public var point: SketchPoint
        public var resolved: Point2D

        public init(point: SketchPoint, resolved: Point2D) {
            self.point = point
            self.resolved = resolved
        }
    }

    public struct Result: Sendable {
        public var sketch: Sketch
        public var pathLength: Double
        public var width: Double
        public var capRadius: Double

        public init(
            sketch: Sketch,
            pathLength: Double,
            width: Double,
            capRadius: Double
        ) {
            self.sketch = sketch
            self.pathLength = pathLength
            self.width = width
            self.capRadius = capRadius
        }
    }

    public enum CurvePathSegment: Sendable, Equatable {
        case line(LinePathSegment)
        case arc(ArcPathSegment)

        public var start: Point2D {
            switch self {
            case .line(let line):
                line.start
            case .arc(let arc):
                arc.start
            }
        }

        public var end: Point2D {
            switch self {
            case .line(let line):
                line.end
            case .arc(let arc):
                arc.end
            }
        }

        var length: Double {
            switch self {
            case .line(let line):
                line.length
            case .arc(let arc):
                arc.length
            }
        }

        var isLineSegment: Bool {
            switch self {
            case .line:
                return true
            case .arc:
                return false
            }
        }
    }

    public struct SampledSplinePath: Sendable, Equatable {
        public var points: [Point2D]
        public var samplesPerSegment: Int

        public init(
            points: [Point2D],
            samplesPerSegment: Int
        ) {
            self.points = points
            self.samplesPerSegment = max(samplesPerSegment, 1)
        }
    }

    public struct LinePathSegment: Sendable, Equatable {
        public var start: Point2D
        public var end: Point2D

        public init(start: Point2D, end: Point2D) {
            self.start = start
            self.end = end
        }

        var length: Double {
            hypot(end.x - start.x, end.y - start.y)
        }
    }

    public struct ArcPathSegment: Sendable, Equatable {
        public var center: Point2D
        public var radius: Double
        public var startAngle: Double
        public var endAngle: Double
        public var sweepSign: Double

        public init(
            center: Point2D,
            radius: Double,
            startAngle: Double,
            endAngle: Double,
            sweepSign: Double
        ) {
            self.center = center
            self.radius = radius
            self.startAngle = startAngle
            self.endAngle = endAngle
            self.sweepSign = sweepSign >= 0.0 ? 1.0 : -1.0
        }

        var start: Point2D {
            point(at: startAngle, radius: radius)
        }

        var end: Point2D {
            point(at: endAngle, radius: radius)
        }

        var length: Double {
            radius * abs(directedAngleSpan(
                startAngle: startAngle,
                endAngle: endAngle,
                sign: sweepSign
            ))
        }

        private func point(at angle: Double, radius: Double) -> Point2D {
            Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private let distanceTolerance: Double

    public init(distanceTolerance: Double = 1.0e-12) {
        self.distanceTolerance = distanceTolerance
    }

    public func buildLineSlot(
        source: SketchLine,
        plane: SketchPlane,
        resolvedStart: Point2D,
        resolvedEnd: Point2D,
        width: CADExpression,
        resolvedWidth: Double
    ) throws -> Result {
        try buildLineChainSlot(
            points: [
                PathPoint(point: source.start, resolved: resolvedStart),
                PathPoint(point: source.end, resolved: resolvedEnd),
            ],
            plane: plane,
            width: width,
            resolvedWidth: resolvedWidth
        )
    }

    public func buildLineChainSlot(
        points: [PathPoint],
        plane: SketchPlane,
        width: CADExpression,
        resolvedWidth: Double
    ) throws -> Result {
        guard resolvedWidth.isFinite, resolvedWidth > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot width must be greater than zero."
            )
        }
        guard points.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires at least one open source curve segment."
            )
        }

        let segments = try lineSegments(from: points)
        try validateSourcePath(points: points, segments: segments)
        let halfWidth = CADExpression.divide(width, .scalar(2.0))
        let halfResolvedWidth = resolvedWidth / 2.0
        let leftPoints = try offsetPoints(
            from: points,
            segments: segments,
            side: 1.0,
            halfWidth: halfWidth
        )
        let rightPoints = try offsetPoints(
            from: points,
            segments: segments,
            side: -1.0,
            halfWidth: halfWidth
        )
        let resolvedLeftPoints = try resolvedOffsetPoints(
            from: points,
            segments: segments,
            side: 1.0,
            halfWidth: halfResolvedWidth
        )
        let resolvedRightPoints = try resolvedOffsetPoints(
            from: points,
            segments: segments,
            side: -1.0,
            halfWidth: halfResolvedWidth
        )
        try validateSlotBoundary(leftPoints: resolvedLeftPoints, rightPoints: resolvedRightPoints)

        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []
        var leftLineIDs: [SketchEntityID] = []
        var rightLineIDs: [SketchEntityID] = []
        for index in segments.indices {
            let lineID = SketchEntityID()
            leftLineIDs.append(lineID)
            entities[lineID] = .line(SketchLine(start: leftPoints[index], end: leftPoints[index + 1]))
        }
        for index in segments.indices.reversed() {
            let lineID = SketchEntityID()
            rightLineIDs.append(lineID)
            entities[lineID] = .line(SketchLine(start: rightPoints[index + 1], end: rightPoints[index]))
        }
        let endCapID = SketchEntityID()
        let startCapID = SketchEntityID()
        let firstNormalAngle = atan2(segments[0].normalY, segments[0].normalX)
        let lastNormalAngle = atan2(segments[segments.count - 1].normalY, segments[segments.count - 1].normalX)
        entities[endCapID] = .arc(SketchArc(
            center: points[points.count - 1].point,
            radius: halfWidth,
            startAngle: .angle(lastNormalAngle + Double.pi, .radian),
            endAngle: .angle(lastNormalAngle + Double.pi * 2.0, .radian)
        ))
        entities[startCapID] = .arc(SketchArc(
            center: points[0].point,
            radius: halfWidth,
            startAngle: .angle(firstNormalAngle, .radian),
            endAngle: .angle(firstNormalAngle + Double.pi, .radian)
        ))

        for index in 0..<(leftLineIDs.count - 1) {
            constraints.append(.coincident(.lineEnd(leftLineIDs[index]), .lineStart(leftLineIDs[index + 1])))
        }
        for index in 0..<(rightLineIDs.count - 1) {
            constraints.append(.coincident(.lineEnd(rightLineIDs[index]), .lineStart(rightLineIDs[index + 1])))
        }
        guard let firstLeftLineID = leftLineIDs.first,
              let lastLeftLineID = leftLineIDs.last,
              let firstRightLineID = rightLineIDs.first,
              let lastRightLineID = rightLineIDs.last else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires at least one open source curve segment."
            )
        }
        // Cap arc endpoints: the end cap runs from (lastNormal + pi) — the right
        // boundary end — to lastNormal — the left boundary end; the start cap
        // runs from firstNormal — the left boundary start — to (firstNormal + pi)
        // — the right boundary start. Pair arcStart/arcEnd accordingly (the
        // curve-chain builder is the reference); swapping them binds points a
        // full slot width apart and poisons constraint-driven edits.
        constraints.append(contentsOf: [
            .coincident(.lineEnd(lastLeftLineID), .arcEnd(endCapID)),
            .coincident(.arcStart(endCapID), .lineStart(firstRightLineID)),
            .coincident(.lineEnd(lastRightLineID), .arcEnd(startCapID)),
            .coincident(.arcStart(startCapID), .lineStart(firstLeftLineID)),
            .equalRadius(endCapID, startCapID),
            .tangent(lastLeftLineID, endCapID),
            .tangent(endCapID, firstRightLineID),
            .tangent(lastRightLineID, startCapID),
            .tangent(startCapID, firstLeftLineID),
        ])
        for pair in zip(leftLineIDs, rightLineIDs.reversed()) {
            constraints.append(.parallel(pair.0, pair.1))
        }

        let sketch = Sketch(
            plane: plane,
            entities: entities,
            constraints: constraints
        )

        return Result(
            sketch: sketch,
            pathLength: segments.reduce(0.0) { $0 + $1.length },
            width: resolvedWidth,
            capRadius: resolvedWidth / 2.0
        )
    }

    public func buildArcSlot(
        source: SketchArc,
        plane: SketchPlane,
        resolvedRadius: Double,
        resolvedStartAngle: Double,
        resolvedEndAngle: Double,
        width: CADExpression,
        resolvedWidth: Double
    ) throws -> Result {
        guard resolvedWidth.isFinite, resolvedWidth > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot width must be greater than zero."
            )
        }
        guard resolvedRadius.isFinite, resolvedRadius > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source arc radius must be greater than zero."
            )
        }
        let span = try normalizedArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )
        guard span < Double.pi * 2.0 - distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; full-circle arc targets are closed."
            )
        }

        let halfWidth = CADExpression.divide(width, .scalar(2.0))
        let halfResolvedWidth = resolvedWidth / 2.0
        guard resolvedRadius - halfResolvedWidth > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot width collapses the inner arc radius."
            )
        }

        let outerArcID = SketchEntityID()
        let innerArcID = SketchEntityID()
        let endCapID = SketchEntityID()
        let startCapID = SketchEntityID()
        let outerRadius = CADExpression.add(source.radius, halfWidth)
        let innerRadius = CADExpression.subtract(source.radius, halfWidth)
        let startCapCenter = arcPoint(
            center: source.center,
            radius: source.radius,
            angle: source.startAngle
        )
        let endCapCenter = arcPoint(
            center: source.center,
            radius: source.radius,
            angle: source.endAngle
        )

        let sketch = Sketch(
            plane: plane,
            entities: [
                outerArcID: .arc(SketchArc(
                    center: source.center,
                    radius: outerRadius,
                    startAngle: source.startAngle,
                    endAngle: source.endAngle
                )),
                endCapID: .arc(SketchArc(
                    center: endCapCenter,
                    radius: halfWidth,
                    startAngle: source.endAngle,
                    endAngle: CADExpression.add(source.endAngle, .angle(Double.pi, .radian))
                )),
                innerArcID: .arc(SketchArc(
                    center: source.center,
                    radius: innerRadius,
                    startAngle: source.startAngle,
                    endAngle: source.endAngle
                )),
                startCapID: .arc(SketchArc(
                    center: startCapCenter,
                    radius: halfWidth,
                    startAngle: CADExpression.add(source.startAngle, .angle(Double.pi, .radian)),
                    endAngle: source.startAngle
                )),
            ],
            constraints: [
                .coincident(.arcEnd(outerArcID), .arcStart(endCapID)),
                .coincident(.arcEnd(endCapID), .arcEnd(innerArcID)),
                .coincident(.arcStart(innerArcID), .arcStart(startCapID)),
                .coincident(.arcEnd(startCapID), .arcStart(outerArcID)),
                .concentric(outerArcID, innerArcID),
                .equalRadius(endCapID, startCapID),
            ]
        )

        return Result(
            sketch: sketch,
            pathLength: resolvedRadius * span,
            width: resolvedWidth,
            capRadius: halfResolvedWidth
        )
    }

    public func buildCurveChainSlot(
        segments: [CurvePathSegment],
        plane: SketchPlane,
        width: CADExpression,
        resolvedWidth: Double
    ) throws -> Result {
        guard resolvedWidth.isFinite, resolvedWidth > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot width must be greater than zero."
            )
        }
        guard segments.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires at least one open source curve segment."
            )
        }
        try validateCurveChain(segments)

        let halfWidth = resolvedWidth / 2.0
        let leftElements = try offsetElements(
            from: segments,
            side: 1.0,
            distance: halfWidth
        )
        let rightElements = try offsetElements(
            from: segments,
            side: -1.0,
            distance: halfWidth
        )
        let rightBoundaryElements = rightElements.reversed().map(reversedElement)

        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []
        let leftIDs = try appendOffsetElements(leftElements, to: &entities)
        let rightIDs = try appendOffsetElements(rightBoundaryElements, to: &entities)
        guard let leftFirstID = leftIDs.first,
              let leftLastID = leftIDs.last,
              let rightFirstID = rightIDs.first,
              let rightLastID = rightIDs.last,
              let sourceStart = segments.first?.start,
              let sourceEnd = segments.last?.end,
              let leftStart = leftElements.first?.start,
              let leftEnd = leftElements.last?.end,
              let rightStart = rightElements.first?.start,
              let rightEnd = rightElements.last?.end else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires at least one open source curve segment."
            )
        }
        try validateSampledBoundary(
            leftElements: leftElements,
            rightElements: rightElements,
            startCenter: sourceStart,
            endCenter: sourceEnd
        )

        let endCapID = SketchEntityID()
        let startCapID = SketchEntityID()
        entities[endCapID] = try capArc(
            center: sourceEnd,
            start: rightEnd,
            end: leftEnd,
            radius: halfWidth
        )
        entities[startCapID] = try capArc(
            center: sourceStart,
            start: leftStart,
            end: rightStart,
            radius: halfWidth
        )

        constraints.append(contentsOf: offsetElementContinuity(ids: leftIDs, elements: leftElements))
        constraints.append(contentsOf: offsetElementContinuity(ids: rightIDs, elements: rightBoundaryElements))
        constraints.append(contentsOf: [
            .coincident(endReference(for: leftElements[leftElements.count - 1], id: leftLastID), .arcEnd(endCapID)),
            .coincident(.arcStart(endCapID), startReference(for: rightBoundaryElements[0], id: rightFirstID)),
            .coincident(endReference(for: rightBoundaryElements[rightBoundaryElements.count - 1], id: rightLastID), .arcEnd(startCapID)),
            .coincident(.arcStart(startCapID), startReference(for: leftElements[0], id: leftFirstID)),
            .equalRadius(endCapID, startCapID),
        ])

        let sketch = Sketch(
            plane: plane,
            entities: entities,
            constraints: constraints
        )
        return Result(
            sketch: sketch,
            pathLength: segments.reduce(0.0) { $0 + $1.length },
            width: resolvedWidth,
            capRadius: halfWidth
        )
    }

    public func buildSampledSplineSlot(
        path: SampledSplinePath,
        plane: SketchPlane,
        width: CADExpression,
        resolvedWidth: Double
    ) throws -> Result {
        guard path.points.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot spline source requires at least two sampled points."
            )
        }
        let points = path.points.map { point in
            PathPoint(point: sketchPoint(point), resolved: point)
        }
        return try buildLineChainSlot(
            points: points,
            plane: plane,
            width: width,
            resolvedWidth: resolvedWidth
        )
    }

    private func lineSegments(from points: [PathPoint]) throws -> [LineSegment] {
        try zip(points, points.dropFirst()).map { start, end in
            let deltaX = end.resolved.x - start.resolved.x
            let deltaY = end.resolved.y - start.resolved.y
            let length = sqrt(deltaX * deltaX + deltaY * deltaY)
            guard length > distanceTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line length must be greater than zero."
                )
            }
            let unitX = deltaX / length
            let unitY = deltaY / length
            return LineSegment(
                start: start.resolved,
                end: end.resolved,
                unitX: unitX,
                unitY: unitY,
                normalX: -unitY,
                normalY: unitX,
                length: length
            )
        }
    }

    private func validateSourcePath(
        points: [PathPoint],
        segments: [LineSegment]
    ) throws {
        for firstIndex in segments.indices {
            for secondIndex in segments.indices where secondIndex > firstIndex + 1 {
                guard segmentsIntersect(
                    segments[firstIndex].start,
                    segments[firstIndex].end,
                    segments[secondIndex].start,
                    segments[secondIndex].end
                ) == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source curve must be open and not self-intersecting."
                    )
                }
            }
        }
        guard squaredDistance(points[0].resolved, points[points.count - 1].resolved) > distanceTolerance * distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed line chains are not supported."
            )
        }
    }

    private func offsetPoints(
        from points: [PathPoint],
        segments: [LineSegment],
        side: Double,
        halfWidth: CADExpression
    ) throws -> [SketchPoint] {
        try points.indices.map { index in
            let displacement = try offsetDisplacement(at: index, segments: segments, side: side)
            return offset(points[index].point, displacementX: displacement.x, displacementY: displacement.y, halfWidth: halfWidth)
        }
    }

    private func resolvedOffsetPoints(
        from points: [PathPoint],
        segments: [LineSegment],
        side: Double,
        halfWidth: Double
    ) throws -> [Point2D] {
        try points.indices.map { index in
            let displacement = try offsetDisplacement(at: index, segments: segments, side: side)
            return Point2D(
                x: points[index].resolved.x + displacement.x * halfWidth,
                y: points[index].resolved.y + displacement.y * halfWidth
            )
        }
    }

    private func offsetDisplacement(
        at index: Int,
        segments: [LineSegment],
        side: Double
    ) throws -> (x: Double, y: Double) {
        if index == 0 {
            return (segments[0].normalX * side, segments[0].normalY * side)
        }
        if index == segments.count {
            let segment = segments[segments.count - 1]
            return (segment.normalX * side, segment.normalY * side)
        }

        let previous = segments[index - 1]
        let next = segments[index]
        let denominator = cross(
            previous.unitX,
            previous.unitY,
            next.unitX,
            next.unitY
        )
        guard abs(denominator) > distanceTolerance else {
            let dot = previous.unitX * next.unitX + previous.unitY * next.unitY
            guard dot > 0.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line chain must not reverse direction at a connected vertex."
                )
            }
            return (previous.normalX * side, previous.normalY * side)
        }
        let deltaX = (next.normalX - previous.normalX) * side
        let deltaY = (next.normalY - previous.normalY) * side
        let scale = cross(deltaX, deltaY, next.unitX, next.unitY) / denominator
        return (
            (previous.normalX * side) + previous.unitX * scale,
            (previous.normalY * side) + previous.unitY * scale
        )
    }

    private func validateSlotBoundary(
        leftPoints: [Point2D],
        rightPoints: [Point2D]
    ) throws {
        let boundary = leftPoints + rightPoints.reversed()
        for firstIndex in 0..<boundary.count {
            let firstStart = boundary[firstIndex]
            let firstEnd = boundary[(firstIndex + 1) % boundary.count]
            for secondIndex in (firstIndex + 1)..<boundary.count {
                if areAdjacentBoundaryEdges(firstIndex, secondIndex, count: boundary.count) {
                    continue
                }
                let secondStart = boundary[secondIndex]
                let secondEnd = boundary[(secondIndex + 1) % boundary.count]
                guard segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot width creates a self-intersecting profile."
                    )
                }
            }
        }
    }

    private func areAdjacentBoundaryEdges(
        _ firstIndex: Int,
        _ secondIndex: Int,
        count: Int
    ) -> Bool {
        firstIndex == secondIndex
            || (firstIndex + 1) % count == secondIndex
            || (secondIndex + 1) % count == firstIndex
    }

    private func segmentsIntersect(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D
    ) -> Bool {
        let firstDirection = Point2D(x: firstEnd.x - firstStart.x, y: firstEnd.y - firstStart.y)
        let secondDirection = Point2D(x: secondEnd.x - secondStart.x, y: secondEnd.y - secondStart.y)
        let denominator = cross(firstDirection.x, firstDirection.y, secondDirection.x, secondDirection.y)
        let delta = Point2D(x: secondStart.x - firstStart.x, y: secondStart.y - firstStart.y)
        if abs(denominator) <= distanceTolerance {
            guard abs(cross(delta.x, delta.y, firstDirection.x, firstDirection.y)) <= distanceTolerance else {
                return false
            }
            return rangesOverlap(
                firstStart.x,
                firstEnd.x,
                secondStart.x,
                secondEnd.x
            ) && rangesOverlap(
                firstStart.y,
                firstEnd.y,
                secondStart.y,
                secondEnd.y
            )
        }
        let firstAmount = cross(delta.x, delta.y, secondDirection.x, secondDirection.y) / denominator
        let secondAmount = cross(delta.x, delta.y, firstDirection.x, firstDirection.y) / denominator
        return firstAmount >= -distanceTolerance
            && firstAmount <= 1.0 + distanceTolerance
            && secondAmount >= -distanceTolerance
            && secondAmount <= 1.0 + distanceTolerance
    }

    private func rangesOverlap(
        _ firstStart: Double,
        _ firstEnd: Double,
        _ secondStart: Double,
        _ secondEnd: Double
    ) -> Bool {
        max(min(firstStart, firstEnd), min(secondStart, secondEnd))
            <= min(max(firstStart, firstEnd), max(secondStart, secondEnd)) + distanceTolerance
    }

    private func squaredDistance(_ first: Point2D, _ second: Point2D) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private func cross(
        _ firstX: Double,
        _ firstY: Double,
        _ secondX: Double,
        _ secondY: Double
    ) -> Double {
        firstX * secondY - firstY * secondX
    }

    private func offset(
        _ point: SketchPoint,
        displacementX: Double,
        displacementY: Double,
        halfWidth: CADExpression
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(.scalar(displacementX), halfWidth)),
            y: .add(point.y, .multiply(.scalar(displacementY), halfWidth))
        )
    }

    private func arcPoint(
        center: SketchPoint,
        radius: CADExpression,
        angle: CADExpression
    ) -> SketchPoint {
        SketchPoint(
            x: .add(center.x, .multiply(radius, .cos(angle))),
            y: .add(center.y, .multiply(radius, .sin(angle)))
        )
    }

    private func normalizedArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        guard startAngle.isFinite, endAngle.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source arc angles must be finite."
            )
        }
        let fullCircle = Double.pi * 2.0
        // Remainder-based normalization stays O(1) for arbitrarily large angle
        // expressions; +/- 2*pi loops hang on huge-but-finite values.
        var span = (endAngle - startAngle - distanceTolerance)
            .truncatingRemainder(dividingBy: fullCircle)
        if span <= 0.0 {
            span += fullCircle
        }
        span += distanceTolerance
        guard span > distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source arc span must be greater than zero."
            )
        }
        return min(span, fullCircle)
    }

    private func validateCurveChain(_ segments: [CurvePathSegment]) throws {
        for index in segments.indices {
            guard segments[index].length > distanceTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source curve segment length must be greater than zero."
                )
            }
            if case .arc(let arc) = segments[index] {
                guard arc.radius > distanceTolerance else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source arc radius must be greater than zero."
                    )
                }
                let span = abs(directedAngleSpan(
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    sign: arc.sweepSign
                ))
                guard span < Double.pi * 2.0 - distanceTolerance else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot requires an open curve; full-circle arc targets are closed."
                    )
                }
            }
            if index > 0 {
                let previousEnd = segments[index - 1].end
                let nextStart = segments[index].start
                guard squaredDistance(previousEnd, nextStart) <= distanceTolerance * distanceTolerance * 100.0 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source curve chain must be connected."
                    )
                }
            }
        }
        guard let first = segments.first,
              let last = segments.last,
              squaredDistance(first.start, last.end) > distanceTolerance * distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed curve chains are not supported."
            )
        }
        try validateSourceSampledPath(segments)
    }

    private func offsetElements(
        from segments: [CurvePathSegment],
        side: Double,
        distance: Double
    ) throws -> [OffsetElement] {
        var elements = try segments.map { segment in
            try offsetElement(from: segment, side: side, distance: distance)
        }
        guard elements.isEmpty == false else {
            return []
        }
        if elements.count > 1 {
            for index in 0..<(elements.count - 1) {
                let target = midpoint(elements[index].end, elements[index + 1].start)
                let join = try intersection(
                    elements[index],
                    elements[index + 1],
                    target: target
                )
                let previousEndSpan = elements[index].arcAngleSpan
                let previousStartSpan = elements[index + 1].arcAngleSpan
                elements[index].setEnd(join)
                elements[index + 1].setStart(join)
                // Trimming to a neighbor intersection must only shorten an arc.
                // A join landing just past an arc's far endpoint wraps the
                // directed span to nearly a full circle, silently inflating a
                // short offset arc into an almost-complete circle.
                try validateTrimmedArcSpan(elements[index], previousSpan: previousEndSpan)
                try validateTrimmedArcSpan(elements[index + 1], previousSpan: previousStartSpan)
            }
        }
        return elements
    }


    private func validateTrimmedArcSpan(
        _ element: OffsetElement,
        previousSpan: Double?
    ) throws {
        guard let previousSpan, let trimmedSpan = element.arcAngleSpan else {
            return
        }
        guard trimmedSpan <= previousSpan + 1.0e-6 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot offset arc trim wrapped past the arc endpoint; the slot width is too large for the source arc."
            )
        }
    }

    private func offsetElement(
        from segment: CurvePathSegment,
        side: Double,
        distance: Double
    ) throws -> OffsetElement {
        switch segment {
        case .line(let line):
            let deltaX = line.end.x - line.start.x
            let deltaY = line.end.y - line.start.y
            let length = hypot(deltaX, deltaY)
            guard length > distanceTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line length must be greater than zero."
                )
            }
            let normalX = -deltaY / length
            let normalY = deltaX / length
            let offset = Point2D(x: normalX * side * distance, y: normalY * side * distance)
            return .line(OffsetLine(
                start: add(line.start, offset),
                end: add(line.end, offset)
            ))
        case .arc(let arc):
            let radius = arc.radius - side * distance * arc.sweepSign
            guard radius > distanceTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot width collapses the inner arc radius."
                )
            }
            return .arc(OffsetArc(
                center: arc.center,
                radius: radius,
                startAngle: arc.startAngle,
                endAngle: arc.endAngle,
                sweepSign: arc.sweepSign
            ))
        }
    }

    private func appendOffsetElements(
        _ elements: [OffsetElement],
        to entities: inout [SketchEntityID: SketchEntity]
    ) throws -> [SketchEntityID] {
        try elements.map { element in
            let entityID = SketchEntityID()
            switch element {
            case .line(let line):
                entities[entityID] = .line(SketchLine(
                    start: sketchPoint(line.start),
                    end: sketchPoint(line.end)
                ))
            case .arc(let arc):
                entities[entityID] = .arc(try sketchArc(arc))
            }
            return entityID
        }
    }

    private func reversedElement(_ element: OffsetElement) -> OffsetElement {
        switch element {
        case .line(let line):
            return .line(OffsetLine(start: line.end, end: line.start))
        case .arc(let arc):
            return .arc(OffsetArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.endAngle,
                endAngle: arc.startAngle,
                sweepSign: -arc.sweepSign
            ))
        }
    }

    private func offsetElementContinuity(
        ids: [SketchEntityID],
        elements: [OffsetElement]
    ) -> [SketchConstraint] {
        guard ids.count >= 2 else {
            return []
        }
        return (0..<(ids.count - 1)).map { index in
            .coincident(
                endReference(for: elements[index], id: ids[index]),
                startReference(for: elements[index + 1], id: ids[index + 1])
            )
        }
    }

    private func startReference(
        for element: OffsetElement,
        id: SketchEntityID
    ) -> SketchReference {
        switch element {
        case .line:
            return .lineStart(id)
        case .arc(let arc):
            return arc.sweepSign >= 0.0 ? .arcStart(id) : .arcEnd(id)
        }
    }

    private func endReference(
        for element: OffsetElement,
        id: SketchEntityID
    ) -> SketchReference {
        switch element {
        case .line:
            return .lineEnd(id)
        case .arc(let arc):
            return arc.sweepSign >= 0.0 ? .arcEnd(id) : .arcStart(id)
        }
    }

    private func sketchArc(_ arc: OffsetArc) throws -> SketchArc {
        let span = directedAngleSpan(
            startAngle: arc.startAngle,
            endAngle: arc.endAngle,
            sign: arc.sweepSign
        )
        guard abs(span) > distanceTolerance,
              abs(span) < Double.pi * 2.0 - distanceTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot produced an invalid arc segment."
            )
        }
        if span >= 0.0 {
            return SketchArc(
                center: sketchPoint(arc.center),
                radius: .length(arc.radius, .meter),
                startAngle: .angle(arc.startAngle, .radian),
                endAngle: .angle(arc.startAngle + span, .radian)
            )
        }
        return SketchArc(
            center: sketchPoint(arc.center),
            radius: .length(arc.radius, .meter),
            startAngle: .angle(arc.endAngle, .radian),
            endAngle: .angle(arc.endAngle - span, .radian)
        )
    }

    private func capArc(
        center: Point2D,
        start: Point2D,
        end: Point2D,
        radius: Double
    ) throws -> SketchEntity {
        let radiusTolerance = max(distanceTolerance * 100.0, radius * 1.0e-9)
        let startRadius = hypot(start.x - center.x, start.y - center.y)
        let endRadius = hypot(end.x - center.x, end.y - center.y)
        let diameter = radius * 2.0
        guard abs(startRadius - radius) <= radiusTolerance,
              abs(endRadius - radius) <= radiusTolerance,
              abs(hypot(end.x - start.x, end.y - start.y) - diameter) <= radiusTolerance * 2.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot produced an invalid tangent cap."
            )
        }
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let span = semicircleSpan(center: center, startAngle: startAngle, end: end, radius: radius)
        return .arc(SketchArc(
            center: sketchPoint(center),
            radius: .length(radius, .meter),
            startAngle: .angle(startAngle, .radian),
            endAngle: .angle(startAngle + span, .radian)
        ))
    }

    private func intersection(
        _ first: OffsetElement,
        _ second: OffsetElement,
        target: Point2D
    ) throws -> Point2D {
        let points: [Point2D]
        switch (first, second) {
        case (.line(let firstLine), .line(let secondLine)):
            guard let intersection = try lineLineJoin(firstLine, secondLine, target: target) else {
                throw disconnectedSlotError()
            }
            return intersection
        case (.line(let line), .arc(let arc)):
            points = lineCircleIntersections(line: line, circle: arc.circle)
        case (.arc(let arc), .line(let line)):
            points = lineCircleIntersections(line: line, circle: arc.circle)
        case (.arc(let firstArc), .arc(let secondArc)):
            points = circleCircleIntersections(firstArc.circle, secondArc.circle)
        }
        guard let point = points.min(by: {
            squaredDistance($0, target) < squaredDistance($1, target)
        }) else {
            throw disconnectedSlotError()
        }
        return point
    }

    private func lineLineJoin(
        _ first: OffsetLine,
        _ second: OffsetLine,
        target: Point2D
    ) throws -> Point2D? {
        let firstDirection = subtract(first.end, first.start)
        let secondDirection = subtract(second.end, second.start)
        let denominator = cross(firstDirection.x, firstDirection.y, secondDirection.x, secondDirection.y)
        if abs(denominator) <= distanceTolerance {
            let delta = subtract(second.start, first.start)
            guard abs(cross(delta.x, delta.y, firstDirection.x, firstDirection.y)) <= distanceTolerance else {
                return nil
            }
            let dot = firstDirection.x * secondDirection.x + firstDirection.y * secondDirection.y
            guard dot > -distanceTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source curve chain must not reverse direction at a connected vertex."
                )
            }
            return target
        }
        let delta = subtract(second.start, first.start)
        let amount = cross(delta.x, delta.y, secondDirection.x, secondDirection.y) / denominator
        return Point2D(
            x: first.start.x + firstDirection.x * amount,
            y: first.start.y + firstDirection.y * amount
        )
    }

    private func lineCircleIntersections(
        line: OffsetLine,
        circle: OffsetCircle
    ) -> [Point2D] {
        let direction = subtract(line.end, line.start)
        let length = hypot(direction.x, direction.y)
        guard length > distanceTolerance else {
            return []
        }
        let unit = Point2D(x: direction.x / length, y: direction.y / length)
        let fromCenter = subtract(line.start, circle.center)
        let projection = -(fromCenter.x * unit.x + fromCenter.y * unit.y)
        let closest = Point2D(
            x: line.start.x + unit.x * projection,
            y: line.start.y + unit.y * projection
        )
        let distanceSquared = squaredDistance(closest, circle.center)
        let radiusSquared = circle.radius * circle.radius
        guard distanceSquared <= radiusSquared + distanceTolerance else {
            return []
        }
        let offset = sqrt(max(radiusSquared - distanceSquared, 0.0))
        if offset <= distanceTolerance {
            return [closest]
        }
        return [
            Point2D(x: closest.x + unit.x * offset, y: closest.y + unit.y * offset),
            Point2D(x: closest.x - unit.x * offset, y: closest.y - unit.y * offset),
        ]
    }

    private func circleCircleIntersections(
        _ first: OffsetCircle,
        _ second: OffsetCircle
    ) -> [Point2D] {
        let delta = subtract(second.center, first.center)
        let distance = hypot(delta.x, delta.y)
        guard distance > distanceTolerance else {
            return []
        }
        guard distance <= first.radius + second.radius + distanceTolerance,
              distance + min(first.radius, second.radius) + distanceTolerance >= max(first.radius, second.radius) else {
            return []
        }
        let a = (first.radius * first.radius - second.radius * second.radius + distance * distance) / (2.0 * distance)
        let hSquared = first.radius * first.radius - a * a
        guard hSquared >= -distanceTolerance else {
            return []
        }
        let base = Point2D(
            x: first.center.x + delta.x * a / distance,
            y: first.center.y + delta.y * a / distance
        )
        let h = sqrt(max(hSquared, 0.0))
        let normal = Point2D(x: -delta.y / distance, y: delta.x / distance)
        if h <= distanceTolerance {
            return [base]
        }
        return [
            Point2D(x: base.x + normal.x * h, y: base.y + normal.y * h),
            Point2D(x: base.x - normal.x * h, y: base.y - normal.y * h),
        ]
    }

    private func validateSourceSampledPath(_ segments: [CurvePathSegment]) throws {
        let points = sampledPoints(for: segments)
        guard points.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source curve segment length must be greater than zero."
            )
        }
        for firstIndex in 0..<(points.count - 1) {
            let firstStart = points[firstIndex]
            let firstEnd = points[firstIndex + 1]
            for secondIndex in (firstIndex + 1)..<(points.count - 1) {
                if secondIndex == firstIndex + 1 {
                    continue
                }
                let secondStart = points[secondIndex]
                let secondEnd = points[secondIndex + 1]
                guard segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source curve must be open and not self-intersecting."
                    )
                }
            }
        }
    }

    private func validateSampledBoundary(
        leftElements: [OffsetElement],
        rightElements: [OffsetElement],
        startCenter: Point2D,
        endCenter: Point2D
    ) throws {
        let boundary = sampledSlotBoundary(
            leftElements: leftElements,
            rightElements: rightElements,
            startCenter: startCenter,
            endCenter: endCenter
        )
        guard boundary.count >= 4 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot produced a degenerate profile."
            )
        }
        for firstIndex in 0..<boundary.count {
            let firstStart = boundary[firstIndex]
            let firstEnd = boundary[(firstIndex + 1) % boundary.count]
            for secondIndex in (firstIndex + 1)..<boundary.count {
                if areAdjacentBoundaryEdges(firstIndex, secondIndex, count: boundary.count) {
                    continue
                }
                let secondStart = boundary[secondIndex]
                let secondEnd = boundary[(secondIndex + 1) % boundary.count]
                guard segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot width creates a self-intersecting profile."
                    )
                }
            }
        }
    }

    private func sampledSlotBoundary(
        leftElements: [OffsetElement],
        rightElements: [OffsetElement],
        startCenter: Point2D,
        endCenter: Point2D
    ) -> [Point2D] {
        guard let leftEnd = leftElements.last?.end,
              let rightEnd = rightElements.last?.end,
              let rightStart = rightElements.first?.start,
              let leftStart = leftElements.first?.start else {
            return []
        }

        var boundary: [Point2D] = []
        appendSampledPath(sampledPoints(for: leftElements), to: &boundary)
        appendSampledPath(
            Array(sampledCapPoints(center: endCenter, start: rightEnd, end: leftEnd).reversed()),
            to: &boundary
        )
        appendSampledPath(Array(sampledPoints(for: rightElements).reversed()), to: &boundary)
        appendSampledPath(
            Array(sampledCapPoints(center: startCenter, start: leftStart, end: rightStart).reversed()),
            to: &boundary
        )
        if let first = boundary.first,
           let last = boundary.last,
           squaredDistance(first, last) <= distanceTolerance * distanceTolerance {
            boundary.removeLast()
        }
        return boundary
    }

    private func appendSampledPath(
        _ path: [Point2D],
        to boundary: inout [Point2D]
    ) {
        for point in path {
            if let last = boundary.last,
               squaredDistance(last, point) <= distanceTolerance * distanceTolerance {
                continue
            }
            boundary.append(point)
        }
    }

    private func sampledPoints(for segments: [CurvePathSegment]) -> [Point2D] {
        var points: [Point2D] = []
        for segment in segments {
            let samples = sampledPoints(for: segment)
            if points.isEmpty {
                points.append(contentsOf: samples)
            } else {
                points.append(contentsOf: samples.dropFirst())
            }
        }
        return points
    }

    private func sampledPoints(for segment: CurvePathSegment) -> [Point2D] {
        switch segment {
        case .line(let line):
            return [line.start, line.end]
        case .arc(let arc):
            let span = directedAngleSpan(
                startAngle: arc.startAngle,
                endAngle: arc.endAngle,
                sign: arc.sweepSign
            )
            let count = max(4, Int(ceil(abs(span) / (Double.pi / 16.0))))
            return (0...count).map { index in
                let ratio = Double(index) / Double(count)
                let angle = arc.startAngle + span * ratio
                return Point2D(
                    x: arc.center.x + cos(angle) * arc.radius,
                    y: arc.center.y + sin(angle) * arc.radius
                )
            }
        }
    }

    private func sampledPoints(for elements: [OffsetElement]) -> [Point2D] {
        var points: [Point2D] = []
        for element in elements {
            let samples = sampledPoints(for: element)
            if points.isEmpty {
                points.append(contentsOf: samples)
            } else {
                points.append(contentsOf: samples.dropFirst())
            }
        }
        return points
    }

    private func sampledPoints(for element: OffsetElement) -> [Point2D] {
        switch element {
        case .line(let line):
            return [line.start, line.end]
        case .arc(let arc):
            let span = directedAngleSpan(
                startAngle: arc.startAngle,
                endAngle: arc.endAngle,
                sign: arc.sweepSign
            )
            let count = max(4, Int(ceil(abs(span) / (Double.pi / 16.0))))
            return (0...count).map { index in
                let ratio = Double(index) / Double(count)
                let angle = arc.startAngle + span * ratio
                return Point2D(
                    x: arc.center.x + cos(angle) * arc.radius,
                    y: arc.center.y + sin(angle) * arc.radius
                )
            }
        }
    }

    private func sampledCapPoints(
        center: Point2D,
        start: Point2D,
        end: Point2D
    ) -> [Point2D] {
        let radius = hypot(start.x - center.x, start.y - center.y)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let span = semicircleSpan(center: center, startAngle: startAngle, end: end, radius: radius)
        return (0...8).map { index in
            let ratio = Double(index) / 8.0
            let angle = startAngle + span * ratio
            return Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func semicircleSpan(
        center: Point2D,
        startAngle: Double,
        end: Point2D,
        radius: Double
    ) -> Double {
        let positiveEnd = Point2D(
            x: center.x + cos(startAngle + Double.pi) * radius,
            y: center.y + sin(startAngle + Double.pi) * radius
        )
        let negativeEnd = Point2D(
            x: center.x + cos(startAngle - Double.pi) * radius,
            y: center.y + sin(startAngle - Double.pi) * radius
        )
        return squaredDistance(positiveEnd, end) <= squaredDistance(negativeEnd, end)
            ? Double.pi
            : -Double.pi
    }

    private func disconnectedSlotError() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Slot width creates disconnected offset curve joins."
        )
    }

    private func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
    }

    private func midpoint(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(
            x: (first.x + second.x) / 2.0,
            y: (first.y + second.y) / 2.0
        )
    }

    private func add(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(x: first.x + second.x, y: first.y + second.y)
    }

    private func subtract(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(x: first.x - second.x, y: first.y - second.y)
    }

    private enum OffsetElement: Sendable, Equatable {
        case line(OffsetLine)
        case arc(OffsetArc)

        var start: Point2D {
            switch self {
            case .line(let line):
                line.start
            case .arc(let arc):
                arc.start
            }
        }

        var end: Point2D {
            switch self {
            case .line(let line):
                line.end
            case .arc(let arc):
                arc.end
            }
        }

        mutating func setStart(_ point: Point2D) {
            switch self {
            case .line(var line):
                line.start = point
                self = .line(line)
            case .arc(var arc):
                arc.setStart(point)
                self = .arc(arc)
            }
        }

        mutating func setEnd(_ point: Point2D) {
            switch self {
            case .line(var line):
                line.end = point
                self = .line(line)
            case .arc(var arc):
                arc.setEnd(point)
                self = .arc(arc)
            }
        }

        var arcAngleSpan: Double? {
            switch self {
            case .line:
                nil
            case .arc(let arc):
                abs(directedAngleSpan(
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    sign: arc.sweepSign
                ))
            }
        }
    }

    private struct OffsetLine: Sendable, Equatable {
        var start: Point2D
        var end: Point2D
    }

    private struct OffsetCircle: Sendable, Equatable {
        var center: Point2D
        var radius: Double
    }

    private struct OffsetArc: Sendable, Equatable {
        var center: Point2D
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var sweepSign: Double

        var circle: OffsetCircle {
            OffsetCircle(center: center, radius: radius)
        }

        var start: Point2D {
            point(at: startAngle)
        }

        var end: Point2D {
            point(at: endAngle)
        }

        mutating func setStart(_ point: Point2D) {
            startAngle = atan2(point.y - center.y, point.x - center.x)
        }

        mutating func setEnd(_ point: Point2D) {
            endAngle = atan2(point.y - center.y, point.x - center.x)
        }

        private func point(at angle: Double) -> Point2D {
            Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private struct LineSegment: Sendable {
        var start: Point2D
        var end: Point2D
        var unitX: Double
        var unitY: Double
        var normalX: Double
        var normalY: Double
        var length: Double
    }
}

private func directedAngleSpan(
    startAngle: Double,
    endAngle: Double,
    sign: Double
) -> Double {
    let fullCircle = Double.pi * 2.0
    // Remainder-based normalization stays O(1) for arbitrarily large angle
    // expressions; +/- 2*pi loops hang on huge-but-finite values.
    if sign >= 0.0 {
        var span = (endAngle - startAngle).truncatingRemainder(dividingBy: fullCircle)
        if span <= 0.0 {
            span += fullCircle
        }
        return span
    }
    var span = (startAngle - endAngle).truncatingRemainder(dividingBy: fullCircle)
    if span <= 0.0 {
        span += fullCircle
    }
    return -span
}
