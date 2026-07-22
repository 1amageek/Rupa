import Foundation
import SwiftCAD
import RupaCoreTypes

struct OffsetRegionBuilder: Sendable {
    struct Result: Sendable {
        var sketch: Sketch
        var areaSquareMeters: Double
        var boundaryPointCount: Int
        var boundaryPoints: [Point2D]
    }

    private struct OffsetLine: Sendable {
        var start: Point2D
        var end: Point2D
        var point: Point2D
        var direction: Point2D
        var normal: Point2D
    }

    private enum RegionEntity: Sendable {
        case line(start: Point2D, end: Point2D)
        case arc(center: Point2D, radius: Double, startAngle: Double, endAngle: Double)
    }

    private enum CornerConnection: Sendable {
        case rounded(entry: Point2D, exit: Point2D)
        case miter(Point2D)

        var entry: Point2D {
            switch self {
            case .rounded(let entry, _):
                entry
            case .miter(let point):
                point
            }
        }

        var exit: Point2D {
            switch self {
            case .rounded(_, let exit):
                exit
            case .miter(let point):
                point
            }
        }
    }

    private let tolerance: Double

    init(tolerance: Double = 1.0e-9) {
        self.tolerance = tolerance
    }

    func buildOffset(
        profile: Profile,
        gapFill: OffsetCurveGapFill,
        distanceMeters: Double
    ) throws -> Result {
        guard abs(distanceMeters) > tolerance * tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region distance must not be zero."
            )
        }
        guard profile.boundarySegments.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region requires a closed region with at least three boundary segments."
            )
        }
        guard profile.boundarySegments.allSatisfy(\.isLineSegment) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region currently supports closed regions whose exact boundary segments are all lines."
            )
        }
        let summary: ProfileRegionSummary
        do {
            summary = try ProfileRegionAnalyzer(
                tolerance: ModelingTolerance(distance: tolerance, angle: 1.0e-9)
            ).summary(for: profile)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region requires a finite, non-degenerate source region."
            )
        }

        let sourcePoints = summary.points
        guard sourcePoints.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region requires at least three boundary points."
            )
        }

        let sourceSignedArea = Self.signedArea(of: sourcePoints)
        let areaTolerance = tolerance * tolerance
        guard abs(sourceSignedArea) > areaTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region source region area is too small."
            )
        }
        try validateSimpleBoundary(
            sourcePoints,
            context: "Offset Region source region"
        )
        let offsetLines = try offsetLines(
            for: sourcePoints,
            sourceSignedArea: sourceSignedArea,
            distanceMeters: distanceMeters
        )
        let entities = try offsetEntities(
            sourcePoints: sourcePoints,
            offsetLines: offsetLines,
            sourceSignedArea: sourceSignedArea,
            gapFill: gapFill,
            radius: abs(distanceMeters)
        )
        let offsetPoints = try polygonValidationPoints(
            sourcePoints: sourcePoints,
            offsetLines: offsetLines,
            sourceSignedArea: sourceSignedArea,
            gapFill: gapFill
        )
        try validateSimpleBoundary(
            offsetPoints,
            context: "Offset Region result"
        )
        let offsetSignedArea = Self.signedArea(of: offsetPoints)
        guard abs(offsetSignedArea) > areaTolerance,
              offsetSignedArea * sourceSignedArea > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region distance would collapse or invert the source region."
            )
        }

        return Result(
            sketch: sketch(
                plane: profile.plane,
                entities: entities
            ),
            areaSquareMeters: abs(offsetSignedArea),
            boundaryPointCount: offsetPoints.count,
            boundaryPoints: offsetPoints
        )
    }

    func buildCombinedOffset(
        profiles: [Profile],
        gapFill: OffsetCurveGapFill,
        distanceMeters: Double
    ) throws -> Result {
        guard profiles.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region requires at least two selected regions."
            )
        }
        let plane = profiles[0].plane
        guard profiles.allSatisfy({ $0.plane == plane }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region requires selected regions on the same sketch plane."
            )
        }

        let results = try profiles.map { profile in
            try buildOffset(
                profile: profile,
                gapFill: gapFill,
                distanceMeters: distanceMeters
            )
        }
        let componentResults = try combinedComponentResults(
            results,
            plane: plane,
            gapFill: gapFill
        )

        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []
        for result in componentResults {
            try appendRemappedSketch(
                result.sketch,
                to: &entities,
                constraints: &constraints
            )
        }

        return Result(
            sketch: Sketch(
                plane: plane,
                entities: entities,
                constraints: constraints
            ),
            areaSquareMeters: componentResults.reduce(0.0) { $0 + $1.areaSquareMeters },
            boundaryPointCount: componentResults.reduce(0) { $0 + $1.boundaryPointCount },
            boundaryPoints: componentResults.flatMap(\.boundaryPoints)
        )
    }

    private func validateSimpleBoundary(
        _ points: [Point2D],
        context: String
    ) throws {
        guard points.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(context) requires at least three boundary points."
            )
        }
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            guard distance(current, next) > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(context) contains a collapsed edge."
                )
            }
        }
        for leftIndex in points.indices {
            let leftStart = points[leftIndex]
            let leftEnd = points[(leftIndex + 1) % points.count]
            for rightIndex in points.indices where rightIndex > leftIndex {
                let isAdjacent = rightIndex == leftIndex + 1 ||
                    (leftIndex == 0 && rightIndex == points.count - 1)
                guard isAdjacent == false else {
                    continue
                }
                let rightStart = points[rightIndex]
                let rightEnd = points[(rightIndex + 1) % points.count]
                if segmentsIntersectOrTouch(leftStart, leftEnd, rightStart, rightEnd) {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(context) must not self-intersect."
                    )
                }
            }
        }
        guard abs(Self.signedArea(of: points)) > tolerance * tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(context) area is too small."
            )
        }
    }

    private func isConvexCorner(
        at index: Int,
        in points: [Point2D],
        signedArea: Double
    ) -> Bool {
        let previous = points[(index + points.count - 1) % points.count]
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let incoming = Point2D(
            x: current.x - previous.x,
            y: current.y - previous.y
        )
        let outgoing = Point2D(
            x: next.x - current.x,
            y: next.y - current.y
        )
        return isConvexTurn(
            incoming: incoming,
            outgoing: outgoing,
            windingSign: signedArea >= 0.0 ? 1.0 : -1.0,
            incomingLength: hypot(incoming.x, incoming.y),
            outgoingLength: hypot(outgoing.x, outgoing.y)
        )
    }

    private func isConvexTurn(
        incoming: Point2D,
        outgoing: Point2D,
        windingSign: Double,
        incomingLength: Double,
        outgoingLength: Double
    ) -> Bool {
        let turn = Self.cross(incoming, outgoing) * windingSign
        let turnTolerance = tolerance * max(incomingLength * outgoingLength, tolerance)
        return turn > turnTolerance
    }

    private func offsetLines(
        for points: [Point2D],
        sourceSignedArea: Double,
        distanceMeters: Double
    ) throws -> [OffsetLine] {
        try points.indices.map { index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let deltaX = next.x - current.x
            let deltaY = next.y - current.y
            let length = hypot(deltaX, deltaY)
            guard length > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Offset Region source boundary contains a collapsed edge."
                )
            }

            let direction = Point2D(x: deltaX / length, y: deltaY / length)
            let leftNormal = Point2D(x: -direction.y, y: direction.x)
            let outwardNormal = sourceSignedArea > 0.0
                ? Point2D(x: -leftNormal.x, y: -leftNormal.y)
                : leftNormal
            let offsetPoint = Point2D(
                x: current.x + outwardNormal.x * distanceMeters,
                y: current.y + outwardNormal.y * distanceMeters
            )
            let offsetNext = Point2D(
                x: next.x + outwardNormal.x * distanceMeters,
                y: next.y + outwardNormal.y * distanceMeters
            )
            return OffsetLine(
                start: offsetPoint,
                end: offsetNext,
                point: offsetPoint,
                direction: direction,
                normal: outwardNormal
            )
        }
    }

    private func offsetEntities(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double,
        gapFill: OffsetCurveGapFill,
        radius: Double
    ) throws -> [RegionEntity] {
        switch gapFill {
        case .natural:
            let points = try miterPoints(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines
            )
            return points.indices.map { index in
                .line(
                    start: points[index],
                    end: points[(index + 1) % points.count]
                )
            }
        case .linear:
            let points = try linearPoints(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines,
                sourceSignedArea: sourceSignedArea
            )
            return points.indices.map { index in
                .line(
                    start: points[index],
                    end: points[(index + 1) % points.count]
                )
            }
        case .round:
            return try roundedEntities(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines,
                sourceSignedArea: sourceSignedArea,
                radius: radius
            )
        }
    }

    private func polygonValidationPoints(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double,
        gapFill: OffsetCurveGapFill
    ) throws -> [Point2D] {
        switch gapFill {
        case .natural:
            return try miterPoints(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines
            )
        case .linear:
            return try linearPoints(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines,
                sourceSignedArea: sourceSignedArea
            )
        case .round:
            return try roundedValidationPoints(
                sourcePoints: sourcePoints,
                offsetLines: offsetLines,
                sourceSignedArea: sourceSignedArea
            )
        }
    }

    private func miterPoints(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine]
    ) throws -> [Point2D] {
        try sourcePoints.indices.map { index in
            try miterPoint(
                at: index,
                sourcePoints: sourcePoints,
                offsetLines: offsetLines
            )
        }
    }

    private func linearPoints(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double
    ) throws -> [Point2D] {
        try sourcePoints.indices.flatMap { index -> [Point2D] in
            if isConvexCorner(
                at: index,
                in: sourcePoints,
                signedArea: sourceSignedArea
            ) {
                let previous = offsetLines[(index + offsetLines.count - 1) % offsetLines.count]
                let current = offsetLines[index]
                return [previous.end, current.start]
            }
            return [
                try miterPoint(
                    at: index,
                    sourcePoints: sourcePoints,
                    offsetLines: offsetLines
                ),
            ]
        }
    }

    private func roundedEntities(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double,
        radius: Double
    ) throws -> [RegionEntity] {
        guard radius > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region round gap fill requires a non-zero corner radius."
            )
        }
        let connections = try roundedCornerConnections(
            sourcePoints: sourcePoints,
            offsetLines: offsetLines,
            sourceSignedArea: sourceSignedArea
        )
        var entities: [RegionEntity] = []
        for index in offsetLines.indices {
            let nextIndex = (index + 1) % offsetLines.count
            let lineStart = connections[index].exit
            let lineEnd = connections[nextIndex].entry
            if distance(lineStart, lineEnd) > tolerance {
                entities.append(.line(start: lineStart, end: lineEnd))
            }
            if case .rounded = connections[nextIndex] {
                let corner = sourcePoints[nextIndex]
                entities.append(.arc(
                    center: corner,
                    radius: radius,
                    startAngle: Self.angle(from: corner, to: lineEnd),
                    endAngle: Self.angle(from: corner, to: connections[nextIndex].exit)
                ))
            }
        }
        guard entities.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region round gap fill produced too few boundary entities."
            )
        }
        return entities
    }

    private func roundedCornerConnections(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double
    ) throws -> [CornerConnection] {
        try sourcePoints.indices.map { index in
            if isConvexCorner(
                at: index,
                in: sourcePoints,
                signedArea: sourceSignedArea
            ) {
                let previous = offsetLines[(index + offsetLines.count - 1) % offsetLines.count]
                let current = offsetLines[index]
                return .rounded(entry: previous.end, exit: current.start)
            }
            return try .miter(miterPoint(
                at: index,
                sourcePoints: sourcePoints,
                offsetLines: offsetLines
            ))
        }
    }

    private func roundedValidationPoints(
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine],
        sourceSignedArea: Double
    ) throws -> [Point2D] {
        let connections = try roundedCornerConnections(
            sourcePoints: sourcePoints,
            offsetLines: offsetLines,
            sourceSignedArea: sourceSignedArea
        )
        var points: [Point2D] = []
        for index in offsetLines.indices {
            let nextIndex = (index + 1) % offsetLines.count
            appendBoundaryPoint(connections[index].exit, to: &points)
            appendBoundaryPoint(connections[nextIndex].entry, to: &points)
            if case .rounded = connections[nextIndex] {
                appendBoundaryPoint(connections[nextIndex].exit, to: &points)
            }
        }
        if let first = points.first,
           let last = points.last,
           distance(first, last) <= tolerance {
            points.removeLast()
        }
        return points
    }

    private func appendBoundaryPoint(_ point: Point2D, to points: inout [Point2D]) {
        if let last = points.last,
           distance(last, point) <= tolerance {
            return
        }
        points.append(point)
    }

    private func miterPoint(
        at index: Int,
        sourcePoints: [Point2D],
        offsetLines: [OffsetLine]
    ) throws -> Point2D {
        let previous = offsetLines[(index + offsetLines.count - 1) % offsetLines.count]
        let current = offsetLines[index]
        let denominator = Self.cross(previous.direction, current.direction)
        if abs(denominator) <= tolerance {
            let normalDelta = hypot(
                previous.normal.x - current.normal.x,
                previous.normal.y - current.normal.y
            )
            guard normalDelta <= tolerance * 10.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Offset Region source boundary contains unsupported parallel adjacent edges."
                )
            }
            let offsetDelta = Point2D(
                x: current.point.x - sourcePoints[index].x,
                y: current.point.y - sourcePoints[index].y
            )
            let signedOffset = offsetDelta.x * current.normal.x + offsetDelta.y * current.normal.y
            return Point2D(
                x: sourcePoints[index].x + current.normal.x * signedOffset,
                y: sourcePoints[index].y + current.normal.y * signedOffset
            )
        }

        let delta = Point2D(
            x: current.point.x - previous.point.x,
            y: current.point.y - previous.point.y
        )
        let t = Self.cross(delta, current.direction) / denominator
        return Point2D(
            x: previous.point.x + previous.direction.x * t,
            y: previous.point.y + previous.direction.y * t
        )
    }

    private func sketch(
        plane: SketchPlane,
        entities regionEntities: [RegionEntity]
    ) -> Sketch {
        let entityIDs = regionEntities.map { _ in SketchEntityID() }
        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []

        for index in regionEntities.indices {
            let entityID = entityIDs[index]
            let nextEntityID = entityIDs[(index + 1) % entityIDs.count]
            switch regionEntities[index] {
            case .line(let start, let end):
                entities[entityID] = .line(SketchLine(
                    start: Self.sketchPoint(start),
                    end: Self.sketchPoint(end)
                ))
                if abs(start.y - end.y) <= tolerance {
                    constraints.append(.horizontal(entityID))
                }
                if abs(start.x - end.x) <= tolerance {
                    constraints.append(.vertical(entityID))
                }
            case .arc(let center, let radius, let startAngle, let endAngle):
                entities[entityID] = .arc(SketchArc(
                    center: Self.sketchPoint(center),
                    radius: .length(radius, .meter),
                    startAngle: .angle(startAngle, .radian),
                    endAngle: .angle(endAngle, .radian)
                ))
            }
            constraints.append(.coincident(
                endReference(for: regionEntities[index], entityID: entityID),
                startReference(for: regionEntities[(index + 1) % regionEntities.count], entityID: nextEntityID)
            ))
        }

        return Sketch(
            plane: plane,
            entities: entities,
            constraints: constraints
        )
    }

    private func combinedComponentResults(
        _ results: [Result],
        plane: SketchPlane,
        gapFill: OffsetCurveGapFill
    ) throws -> [Result] {
        let components = connectedLoopComponents(results.map(\.boundaryPoints))
        return try components.map { component in
            if component.count == 1, let index = component.first {
                return results[index]
            }
            guard gapFill != .round else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Combined Offset Region with Round gap fill requires curved polygon union support when offset loops overlap or touch."
                )
            }
            let loops = component.map { results[$0].boundaryPoints }
            return try buildPolygonUnionResult(
                loops: loops,
                plane: plane
            )
        }
    }

    private func connectedLoopComponents(_ loops: [[Point2D]]) -> [[Int]] {
        guard loops.isEmpty == false else {
            return []
        }
        var adjacency: [Set<Int>] = Array(
            repeating: Set<Int>(),
            count: loops.count
        )
        for leftIndex in loops.indices {
            for rightIndex in loops.indices where rightIndex > leftIndex {
                guard loopsOverlapOrTouch(loops[leftIndex], loops[rightIndex]) else {
                    continue
                }
                adjacency[leftIndex].insert(rightIndex)
                adjacency[rightIndex].insert(leftIndex)
            }
        }

        var visited = Set<Int>()
        var components: [[Int]] = []
        for index in loops.indices {
            guard visited.insert(index).inserted else {
                continue
            }
            var component: [Int] = []
            var stack = [index]
            while let current = stack.popLast() {
                component.append(current)
                for next in adjacency[current] {
                    if visited.insert(next).inserted {
                        stack.append(next)
                    }
                }
            }
            components.append(component.sorted())
        }
        return components
    }

    private struct BoundarySegment: Sendable {
        var start: Point2D
        var end: Point2D
    }

    private struct BoundarySegmentKey: Hashable {
        var startX: Int64
        var startY: Int64
        var endX: Int64
        var endY: Int64
    }

    private func buildPolygonUnionResult(
        loops: [[Point2D]],
        plane: SketchPlane
    ) throws -> Result {
        let unionLoops = try polygonUnionLoops(loops)
        guard unionLoops.count == 1, let boundary = unionLoops.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region polygon union currently requires one outer boundary without holes."
            )
        }
        let area = abs(Self.signedArea(of: boundary))
        return Result(
            sketch: sketch(
                plane: plane,
                entities: boundary.indices.map { index in
                    .line(
                        start: boundary[index],
                        end: boundary[(index + 1) % boundary.count]
                    )
                }
            ),
            areaSquareMeters: area,
            boundaryPointCount: boundary.count,
            boundaryPoints: boundary
        )
    }

    private func polygonUnionLoops(_ loops: [[Point2D]]) throws -> [[Point2D]] {
        let sourceSegments = loops.flatMap { loop in
            loop.indices.map { index in
                BoundarySegment(
                    start: loop[index],
                    end: loop[(index + 1) % loop.count]
                )
            }
        }
        var boundarySegments: [BoundarySegment] = []
        var seenSegmentKeys = Set<BoundarySegmentKey>()

        for segment in sourceSegments {
            let splitPoints = splitPointsForSegment(
                segment,
                against: sourceSegments
            )
            for index in 0..<(splitPoints.count - 1) {
                let start = splitPoints[index]
                let end = splitPoints[index + 1]
                guard distance(start, end) > tolerance else {
                    continue
                }
                guard let boundarySegment = boundarySegment(
                    start: start,
                    end: end,
                    sourceLoops: loops
                ) else {
                    continue
                }
                let key = segmentKey(
                    start: boundarySegment.start,
                    end: boundarySegment.end
                )
                guard seenSegmentKeys.insert(key).inserted else {
                    continue
                }
                boundarySegments.append(boundarySegment)
            }
        }

        guard boundarySegments.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region polygon union produced no boundary."
            )
        }
        return try orderedBoundaryLoops(from: boundarySegments)
    }

    private func splitPointsForSegment(
        _ segment: BoundarySegment,
        against sourceSegments: [BoundarySegment]
    ) -> [Point2D] {
        let length = distance(segment.start, segment.end)
        guard length > tolerance else {
            return []
        }
        let direction = Point2D(
            x: (segment.end.x - segment.start.x) / length,
            y: (segment.end.y - segment.start.y) / length
        )
        var points = [segment.start, segment.end]
        for other in sourceSegments {
            if isCollinear(segment, other) {
                if isPoint(other.start, onSegmentFrom: segment.start, to: segment.end) {
                    points.append(other.start)
                }
                if isPoint(other.end, onSegmentFrom: segment.start, to: segment.end) {
                    points.append(other.end)
                }
                continue
            }
            if let intersection = segmentIntersection(segment, other),
               isPoint(intersection, onSegmentFrom: segment.start, to: segment.end) {
                points.append(intersection)
            }
        }

        return uniquePoints(points)
            .sorted { left, right in
                projection(of: left, origin: segment.start, direction: direction)
                    < projection(of: right, origin: segment.start, direction: direction)
            }
    }

    private func boundarySegment(
        start: Point2D,
        end: Point2D,
        sourceLoops: [[Point2D]]
    ) -> BoundarySegment? {
        let length = distance(start, end)
        guard length > tolerance else {
            return nil
        }
        let direction = Point2D(
            x: (end.x - start.x) / length,
            y: (end.y - start.y) / length
        )
        let normal = Point2D(x: -direction.y, y: direction.x)
        let midpoint = Point2D(
            x: (start.x + end.x) * 0.5,
            y: (start.y + end.y) * 0.5
        )
        let sampleDistance = max(tolerance * 100.0, length * 1.0e-8)
        let leftSample = Point2D(
            x: midpoint.x + normal.x * sampleDistance,
            y: midpoint.y + normal.y * sampleDistance
        )
        let rightSample = Point2D(
            x: midpoint.x - normal.x * sampleDistance,
            y: midpoint.y - normal.y * sampleDistance
        )
        let leftInside = containsPoint(leftSample, inAny: sourceLoops)
        let rightInside = containsPoint(rightSample, inAny: sourceLoops)
        guard leftInside != rightInside else {
            return nil
        }
        if leftInside {
            return BoundarySegment(start: start, end: end)
        }
        return BoundarySegment(start: end, end: start)
    }

    private func orderedBoundaryLoops(from segments: [BoundarySegment]) throws -> [[Point2D]] {
        var remaining = segments
        var loops: [[Point2D]] = []
        while let first = remaining.first {
            remaining.removeFirst()
            var points = [first.start, first.end]
            var current = first.end
            var guardCount = 0
            while distance(current, points[0]) > tolerance {
                guardCount += 1
                guard guardCount <= segments.count + 1 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Combined Offset Region polygon union boundary could not be ordered."
                    )
                }
                guard let nextIndex = remaining.firstIndex(where: { distance($0.start, current) <= tolerance }) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Combined Offset Region polygon union boundary is open."
                    )
                }
                let next = remaining.remove(at: nextIndex)
                points.append(next.end)
                current = next.end
            }
            if let last = points.last, distance(last, points[0]) <= tolerance {
                points.removeLast()
            }
            let simplified = try simplifiedBoundaryLoop(points)
            if abs(Self.signedArea(of: simplified)) > tolerance * tolerance {
                loops.append(Self.signedArea(of: simplified) > 0.0 ? simplified : Array(simplified.reversed()))
            }
        }
        return loops.sorted { abs(Self.signedArea(of: $0)) > abs(Self.signedArea(of: $1)) }
    }

    private func simplifiedBoundaryLoop(_ points: [Point2D]) throws -> [Point2D] {
        var simplified = uniqueConsecutivePoints(points)
        var didRemove = true
        while didRemove, simplified.count > 3 {
            didRemove = false
            for index in simplified.indices {
                let previous = simplified[(index + simplified.count - 1) % simplified.count]
                let current = simplified[index]
                let next = simplified[(index + 1) % simplified.count]
                if distance(previous, current) <= tolerance || distance(current, next) <= tolerance {
                    simplified.remove(at: index)
                    didRemove = true
                    break
                }
                if abs(orientation(previous, current, next)) <= tolerance * max(distance(previous, next), 1.0) {
                    simplified.remove(at: index)
                    didRemove = true
                    break
                }
            }
        }
        guard simplified.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region polygon union collapsed to fewer than three boundary points."
            )
        }
        return simplified
    }

    private func segmentIntersection(
        _ first: BoundarySegment,
        _ second: BoundarySegment
    ) -> Point2D? {
        let firstDirection = Point2D(
            x: first.end.x - first.start.x,
            y: first.end.y - first.start.y
        )
        let secondDirection = Point2D(
            x: second.end.x - second.start.x,
            y: second.end.y - second.start.y
        )
        let denominator = Self.cross(firstDirection, secondDirection)
        guard abs(denominator) > tolerance * tolerance else {
            return nil
        }
        let delta = Point2D(
            x: second.start.x - first.start.x,
            y: second.start.y - first.start.y
        )
        let firstParameter = Self.cross(delta, secondDirection) / denominator
        let secondParameter = Self.cross(delta, firstDirection) / denominator
        guard firstParameter >= -tolerance,
              firstParameter <= 1.0 + tolerance,
              secondParameter >= -tolerance,
              secondParameter <= 1.0 + tolerance else {
            return nil
        }
        return Point2D(
            x: first.start.x + firstDirection.x * firstParameter,
            y: first.start.y + firstDirection.y * firstParameter
        )
    }

    private func isCollinear(
        _ first: BoundarySegment,
        _ second: BoundarySegment
    ) -> Bool {
        let firstTolerance = orientationTolerance(from: first.start, to: first.end)
        return abs(orientation(first.start, first.end, second.start)) <= firstTolerance
            && abs(orientation(first.start, first.end, second.end)) <= firstTolerance
    }

    private func containsPoint(
        _ point: Point2D,
        inAny loops: [[Point2D]]
    ) -> Bool {
        loops.contains { loop in
            containsPoint(point, in: loop)
        }
    }

    private func uniquePoints(_ points: [Point2D]) -> [Point2D] {
        var unique: [Point2D] = []
        for point in points {
            guard unique.contains(where: { distance($0, point) <= tolerance }) == false else {
                continue
            }
            unique.append(point)
        }
        return unique
    }

    private func uniqueConsecutivePoints(_ points: [Point2D]) -> [Point2D] {
        var unique: [Point2D] = []
        for point in points {
            guard let last = unique.last,
                  distance(last, point) <= tolerance else {
                unique.append(point)
                continue
            }
        }
        if unique.count > 1,
           let first = unique.first,
           let last = unique.last,
           distance(first, last) <= tolerance {
            unique.removeLast()
        }
        return unique
    }

    private func segmentKey(
        start: Point2D,
        end: Point2D
    ) -> BoundarySegmentKey {
        BoundarySegmentKey(
            startX: quantized(start.x),
            startY: quantized(start.y),
            endX: quantized(end.x),
            endY: quantized(end.y)
        )
    }

    private func quantized(_ value: Double) -> Int64 {
        // Clamp instead of trapping: at site-planning scale a coordinate (~1e12)
        // divided by the nanometer tolerance overflows Int64 (1e12 / 1e-9 = 1e21
        // > Int64.max). The quantized value is only a coincidence-dedup key, and
        // coordinate precision at that magnitude is already coarser than the
        // tolerance, so clamping is safe where the raw conversion would crash.
        let scaled = (value / tolerance).rounded()
        guard scaled.isFinite else {
            return 0
        }
        if scaled >= Double(Int64.max) {
            return Int64.max
        }
        if scaled <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(scaled)
    }

    private func appendRemappedSketch(
        _ sketch: Sketch,
        to entities: inout [SketchEntityID: SketchEntity],
        constraints: inout [SketchConstraint]
    ) throws {
        var idMap: [SketchEntityID: SketchEntityID] = [:]
        var allocatedIDs = Set(entities.keys)
        for sourceID in sketch.entities.keys {
            var remappedID = SketchEntityID()
            while allocatedIDs.contains(remappedID) {
                remappedID = SketchEntityID()
            }
            allocatedIDs.insert(remappedID)
            idMap[sourceID] = remappedID
        }

        for (sourceID, entity) in sketch.entities {
            entities[try remappedEntityID(sourceID, idMap: idMap)] = entity
        }
        for constraint in sketch.constraints {
            constraints.append(try remappedConstraint(constraint, idMap: idMap))
        }
    }

    private func remappedConstraint(
        _ constraint: SketchConstraint,
        idMap: [SketchEntityID: SketchEntityID]
    ) throws -> SketchConstraint {
        switch constraint {
        case .coincident(let first, let second):
            return .coincident(
                try remappedReference(first, idMap: idMap),
                try remappedReference(second, idMap: idMap)
            )
        case .horizontal(let entityID):
            return .horizontal(try remappedEntityID(entityID, idMap: idMap))
        case .vertical(let entityID):
            return .vertical(try remappedEntityID(entityID, idMap: idMap))
        case .parallel(let first, let second):
            return .parallel(
                try remappedEntityID(first, idMap: idMap),
                try remappedEntityID(second, idMap: idMap)
            )
        case .perpendicular(let first, let second):
            return .perpendicular(
                try remappedEntityID(first, idMap: idMap),
                try remappedEntityID(second, idMap: idMap)
            )
        case .equalLength(let first, let second):
            return .equalLength(
                try remappedEntityID(first, idMap: idMap),
                try remappedEntityID(second, idMap: idMap)
            )
        case .tangent(let tangency):
            return .tangent(try remappedTangency(tangency, idMap: idMap))
        case .concentric(let first, let second):
            return .concentric(
                try remappedEntityID(first, idMap: idMap),
                try remappedEntityID(second, idMap: idMap)
            )
        case .equalRadius(let first, let second):
            return .equalRadius(
                try remappedEntityID(first, idMap: idMap),
                try remappedEntityID(second, idMap: idMap)
            )
        case .smoothSplineControlPoint(let entityID, let index):
            return .smoothSplineControlPoint(
                entity: try remappedEntityID(entityID, idMap: idMap),
                index: index
            )
        case .splineEndpointTangent(let tangency):
            return .splineEndpointTangent(
                SketchSplineLineTangencyConstraint(
                    splineEndpoint: try remappedSplineEndpointReference(
                        tangency.splineEndpoint,
                        idMap: idMap
                    ),
                    line: try remappedEntityID(tangency.line, idMap: idMap),
                    orientation: tangency.orientation
                )
            )
        case .tangentSplineEndpoints(let tangency):
            return .tangentSplineEndpoints(
                SketchSplineEndpointTangencyConstraint(
                    first: try remappedSplineEndpointReference(tangency.first, idMap: idMap),
                    second: try remappedSplineEndpointReference(tangency.second, idMap: idMap),
                    orientation: tangency.orientation
                )
            )
        case .smoothSplineEndpoints(let tangency):
            return .smoothSplineEndpoints(
                SketchSplineEndpointTangencyConstraint(
                    first: try remappedSplineEndpointReference(tangency.first, idMap: idMap),
                    second: try remappedSplineEndpointReference(tangency.second, idMap: idMap),
                    orientation: tangency.orientation
                )
            )
        case .fixed(let reference):
            return .fixed(try remappedReference(reference, idMap: idMap))
        }
    }

    private func remappedTangency(
        _ tangency: SketchTangencyConstraint,
        idMap: [SketchEntityID: SketchEntityID]
    ) throws -> SketchTangencyConstraint {
        switch tangency {
        case let .lineCircular(line, circular, side):
            return .lineCircular(
                line: try remappedEntityID(line, idMap: idMap),
                circular: try remappedEntityID(circular, idMap: idMap),
                side: side
            )
        case let .circularCircular(first, second, contact):
            return .circularCircular(
                first: try remappedEntityID(first, idMap: idMap),
                second: try remappedEntityID(second, idMap: idMap),
                contact: contact
            )
        }
    }

    private func remappedReference(
        _ reference: SketchReference,
        idMap: [SketchEntityID: SketchEntityID]
    ) throws -> SketchReference {
        switch reference {
        case .entity(let entityID):
            return .entity(try remappedEntityID(entityID, idMap: idMap))
        case .lineStart(let entityID):
            return .lineStart(try remappedEntityID(entityID, idMap: idMap))
        case .lineEnd(let entityID):
            return .lineEnd(try remappedEntityID(entityID, idMap: idMap))
        case .circleCenter(let entityID):
            return .circleCenter(try remappedEntityID(entityID, idMap: idMap))
        case .circleRadius(let entityID):
            return .circleRadius(try remappedEntityID(entityID, idMap: idMap))
        case .arcCenter(let entityID):
            return .arcCenter(try remappedEntityID(entityID, idMap: idMap))
        case .arcStart(let entityID):
            return .arcStart(try remappedEntityID(entityID, idMap: idMap))
        case .arcEnd(let entityID):
            return .arcEnd(try remappedEntityID(entityID, idMap: idMap))
        case .arcRadius(let entityID):
            return .arcRadius(try remappedEntityID(entityID, idMap: idMap))
        case .splineControlPoint(let entityID, let index):
            return .splineControlPoint(
                entity: try remappedEntityID(entityID, idMap: idMap),
                index: index
            )
        }
    }

    private func remappedSplineEndpointReference(
        _ reference: SketchSplineEndpointReference,
        idMap: [SketchEntityID: SketchEntityID]
    ) throws -> SketchSplineEndpointReference {
        SketchSplineEndpointReference(
            splineID: try remappedEntityID(reference.splineID, idMap: idMap),
            endpoint: reference.endpoint
        )
    }

    private func remappedEntityID(
        _ entityID: SketchEntityID,
        idMap: [SketchEntityID: SketchEntityID]
    ) throws -> SketchEntityID {
        guard let remappedID = idMap[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Combined Offset Region produced an invalid internal sketch reference."
            )
        }
        return remappedID
    }

    private func loopsOverlapOrTouch(
        _ left: [Point2D],
        _ right: [Point2D]
    ) -> Bool {
        guard left.count >= 3, right.count >= 3 else {
            return true
        }

        for leftIndex in left.indices {
            let leftStart = left[leftIndex]
            let leftEnd = left[(leftIndex + 1) % left.count]
            for rightIndex in right.indices {
                let rightStart = right[rightIndex]
                let rightEnd = right[(rightIndex + 1) % right.count]
                if segmentsIntersectOrTouch(leftStart, leftEnd, rightStart, rightEnd) {
                    return true
                }
            }
        }

        return containsPoint(right[0], in: left) || containsPoint(left[0], in: right)
    }

    private func segmentsIntersectOrTouch(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D
    ) -> Bool {
        let firstTolerance = orientationTolerance(from: firstStart, to: firstEnd)
        let secondTolerance = orientationTolerance(from: secondStart, to: secondEnd)
        let firstSecondStart = orientation(firstStart, firstEnd, secondStart)
        let firstSecondEnd = orientation(firstStart, firstEnd, secondEnd)
        let secondFirstStart = orientation(secondStart, secondEnd, firstStart)
        let secondFirstEnd = orientation(secondStart, secondEnd, firstEnd)

        if abs(firstSecondStart) <= firstTolerance, isPoint(secondStart, onSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(firstSecondEnd) <= firstTolerance, isPoint(secondEnd, onSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(secondFirstStart) <= secondTolerance, isPoint(firstStart, onSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        if abs(secondFirstEnd) <= secondTolerance, isPoint(firstEnd, onSegmentFrom: secondStart, to: secondEnd) {
            return true
        }

        return valuesHaveOppositeSigns(firstSecondStart, firstSecondEnd, tolerance: firstTolerance)
            && valuesHaveOppositeSigns(secondFirstStart, secondFirstEnd, tolerance: secondTolerance)
    }

    private func containsPoint(
        _ point: Point2D,
        in polygon: [Point2D]
    ) -> Bool {
        var isInside = false
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if abs(orientation(start, end, point)) <= orientationTolerance(from: start, to: end),
               isPoint(point, onSegmentFrom: start, to: end) {
                return true
            }
            let crossesRay = (start.y > point.y) != (end.y > point.y)
            guard crossesRay else {
                continue
            }
            let intersectionX = start.x + (point.y - start.y) * (end.x - start.x) / (end.y - start.y)
            if intersectionX >= point.x - tolerance {
                isInside.toggle()
            }
        }
        return isInside
    }

    private func projection(
        of point: Point2D,
        origin: Point2D,
        direction: Point2D
    ) -> Double {
        (point.x - origin.x) * direction.x + (point.y - origin.y) * direction.y
    }

    private func distance(
        _ first: Point2D,
        _ second: Point2D
    ) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func orientation(
        _ start: Point2D,
        _ end: Point2D,
        _ point: Point2D
    ) -> Double {
        Self.cross(
            Point2D(x: end.x - start.x, y: end.y - start.y),
            Point2D(x: point.x - start.x, y: point.y - start.y)
        )
    }

    private func orientationTolerance(
        from start: Point2D,
        to end: Point2D
    ) -> Double {
        tolerance * max(distance(start, end), tolerance)
    }

    private func valuesHaveOppositeSigns(
        _ left: Double,
        _ right: Double,
        tolerance: Double
    ) -> Bool {
        (left > tolerance && right < -tolerance) ||
            (left < -tolerance && right > tolerance)
    }

    private func isPoint(
        _ point: Point2D,
        onSegmentFrom start: Point2D,
        to end: Point2D
    ) -> Bool {
        point.x >= min(start.x, end.x) - tolerance
            && point.x <= max(start.x, end.x) + tolerance
            && point.y >= min(start.y, end.y) - tolerance
            && point.y <= max(start.y, end.y) + tolerance
    }

    private func startReference(
        for entity: RegionEntity,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch entity {
        case .line:
            return .lineStart(entityID)
        case .arc:
            return .arcStart(entityID)
        }
    }

    private func endReference(
        for entity: RegionEntity,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch entity {
        case .line:
            return .lineEnd(entityID)
        case .arc:
            return .arcEnd(entityID)
        }
    }

    private static func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
    }

    private static func signedArea(of points: [Point2D]) -> Double {
        guard let origin = points.first else {
            return 0.0
        }
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            // Rebase to a local origin so the winding sign and area stay correct
            // far from the world origin; a raw shoelace on ~1e12 coordinates
            // cancels to a random-sign value, inverting the offset direction and
            // convexity classification. Signed area is translation invariant.
            let currentX = current.x - origin.x
            let currentY = current.y - origin.y
            let nextX = next.x - origin.x
            let nextY = next.y - origin.y
            twiceArea += currentX * nextY - nextX * currentY
        }
        return twiceArea * 0.5
    }

    private static func cross(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private static func angle(from center: Point2D, to point: Point2D) -> Double {
        atan2(point.y - center.y, point.x - center.x)
    }
}

private extension ProfileBoundarySegment {
    var isLineSegment: Bool {
        if case .line = self {
            return true
        }
        return false
    }
}
