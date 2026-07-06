import Foundation
import SwiftCAD
import RupaCoreTypes

struct EditableExtrudeProfileLoop: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    private struct ArcElement: Equatable, Sendable {
        var center: Point
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var isReversed: Bool

        var storedStart: Point {
            Point(
                x: center.x + radius * cos(startAngle),
                y: center.y + radius * sin(startAngle)
            )
        }

        var storedEnd: Point {
            Point(
                x: center.x + radius * cos(endAngle),
                y: center.y + radius * sin(endAngle)
            )
        }

        var start: Point {
            isReversed ? storedEnd : storedStart
        }

        var end: Point {
            isReversed ? storedStart : storedEnd
        }

        func reversed() -> ArcElement {
            ArcElement(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                isReversed: !isReversed
            )
        }

        func tangentAtStart(tolerance: Double) throws -> Point {
            try tangent(at: loopStartAngle, tolerance: tolerance)
        }

        func tangentAtEnd(tolerance: Double) throws -> Point {
            try tangent(at: loopEndAngle, tolerance: tolerance)
        }

        func pointFromStart(
            distance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            try point(
                from: loopStartAngle,
                signedDistance: loopDirection * distance,
                operationName: operationName,
                tolerance: tolerance
            )
        }

        func pointFromEnd(
            distance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            try point(
                from: loopEndAngle,
                signedDistance: -loopDirection * distance,
                operationName: operationName,
                tolerance: tolerance
            )
        }

        func trimmed(
            from start: Point,
            to end: Point,
            operationName: String,
            tolerance: Double
        ) throws -> ArcElement {
            let startDistance = try pathDistanceFromStart(
                to: start,
                operationName: operationName,
                tolerance: tolerance
            )
            let endDistance = try pathDistanceFromStart(
                to: end,
                operationName: operationName,
                tolerance: tolerance
            )
            guard start.isClose(to: end, tolerance: tolerance) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) would collapse a profile arc."
                )
            }
            guard endDistance > startDistance + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) would collapse a profile arc."
                )
            }
            let loopStart = start.angle(relativeTo: center)
            let loopEnd = end.angle(relativeTo: center)
            let span = isReversed
                ? EditableExtrudeProfileLoop.positiveAngleSpan(
                    startAngle: loopEnd,
                    endAngle: loopStart
                )
                : EditableExtrudeProfileLoop.positiveAngleSpan(
                    startAngle: loopStart,
                    endAngle: loopEnd
                )
            guard radius * span > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) would collapse a profile arc."
                )
            }
            if isReversed {
                return ArcElement(
                    center: center,
                    radius: radius,
                    startAngle: loopEnd,
                    endAngle: EditableExtrudeProfileLoop.positiveAngleEnd(
                        startAngle: loopEnd,
                        endAngle: loopStart
                    ),
                    isReversed: true
                )
            }
            return ArcElement(
                center: center,
                radius: radius,
                startAngle: loopStart,
                endAngle: EditableExtrudeProfileLoop.positiveAngleEnd(
                    startAngle: loopStart,
                    endAngle: loopEnd
                ),
                isReversed: false
            )
        }

        func pathDistanceFromStart(
            to point: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Double {
            try validatePointOnCircle(point, operationName: operationName, tolerance: tolerance)
            let angle = point.angle(relativeTo: center)
            let span = isReversed
                ? EditableExtrudeProfileLoop.nonnegativeAngleSpan(
                    startAngle: angle,
                    endAngle: loopStartAngle
                )
                : EditableExtrudeProfileLoop.nonnegativeAngleSpan(
                    startAngle: loopStartAngle,
                    endAngle: angle
                )
            let distance = radius * span
            guard distance <= length + max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) produced a point outside the source arc."
                )
            }
            return min(distance, length)
        }

        func tangentPoint(
            forFilletCenter filletCenter: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            let direction = try center.unitVector(toward: filletCenter, tolerance: tolerance)
            let point = center + direction * radius
            _ = try pathDistanceFromStart(
                to: point,
                operationName: operationName,
                tolerance: tolerance
            )
            return point
        }

        func tangent(
            at point: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            _ = try pathDistanceFromStart(
                to: point,
                operationName: operationName,
                tolerance: tolerance
            )
            return try tangent(at: point.angle(relativeTo: center), tolerance: tolerance)
        }

        func offsetRadius(
            filletRadius: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Double {
            let radius = radius - loopDirection * filletRadius
            guard radius > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) radius would collapse a profile arc offset."
                )
            }
            return radius
        }

        private var loopStartAngle: Double {
            isReversed ? endAngle : startAngle
        }

        private var loopEndAngle: Double {
            isReversed ? startAngle : endAngle
        }

        private var loopDirection: Double {
            isReversed ? -1.0 : 1.0
        }

        var length: Double {
            radius * EditableExtrudeProfileLoop.positiveAngleSpan(
                startAngle: startAngle,
                endAngle: endAngle
            )
        }

        private func tangent(
            at angle: Double,
            tolerance: Double
        ) throws -> Point {
            try Point(
                x: loopDirection * -sin(angle),
                y: loopDirection * cos(angle)
            ).normalized(tolerance: tolerance)
        }

        private func point(
            from angle: Double,
            signedDistance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            guard length > abs(signedDistance) + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) distance would collapse a profile arc."
                )
            }
            let nextAngle = angle + signedDistance / radius
            return Point(
                x: center.x + radius * cos(nextAngle),
                y: center.y + radius * sin(nextAngle)
            )
        }

        private func validatePointOnCircle(
            _ point: Point,
            operationName: String,
            tolerance: Double
        ) throws {
            let radialDistance = center.distance(to: point)
            guard abs(radialDistance - radius) <= max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) produced a point outside the source arc."
                )
            }
        }
    }

    private enum Element: Equatable, Sendable {
        case line(start: Point, end: Point)
        case arc(ArcElement)

        var start: Point {
            switch self {
            case .line(let start, _):
                return start
            case .arc(let arc):
                return arc.start
            }
        }

        var end: Point {
            switch self {
            case .line(_, let end):
                return end
            case .arc(let arc):
                return arc.end
            }
        }

        func reversed() -> Element {
            switch self {
            case .line(let start, let end):
                return .line(start: end, end: start)
            case .arc(let arc):
                return .arc(arc.reversed())
            }
        }

        func pointFromStart(
            distance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            switch self {
            case .line(let start, let end):
                return try Self.linePoint(
                    from: start,
                    toward: end,
                    distance: distance,
                    operationName: operationName,
                    tolerance: tolerance
                )
            case .arc(let arc):
                return try arc.pointFromStart(
                    distance: distance,
                    operationName: operationName,
                    tolerance: tolerance
                )
            }
        }

        func pointFromEnd(
            distance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            switch self {
            case .line(let start, let end):
                return try Self.linePoint(
                    from: end,
                    toward: start,
                    distance: distance,
                    operationName: operationName,
                    tolerance: tolerance
                )
            case .arc(let arc):
                return try arc.pointFromEnd(
                    distance: distance,
                    operationName: operationName,
                    tolerance: tolerance
                )
            }
        }

        func tangentAtStart(tolerance: Double) throws -> Point {
            switch self {
            case .line(let start, let end):
                return try start.unitVector(toward: end, tolerance: tolerance)
            case .arc(let arc):
                return try arc.tangentAtStart(tolerance: tolerance)
            }
        }

        func tangentAtEnd(tolerance: Double) throws -> Point {
            switch self {
            case .line(let start, let end):
                return try start.unitVector(toward: end, tolerance: tolerance)
            case .arc(let arc):
                return try arc.tangentAtEnd(tolerance: tolerance)
            }
        }

        func pathDistanceFromStart(
            to point: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Double {
            switch self {
            case .line(let start, let end):
                return try Self.linePathDistance(
                    to: point,
                    lineStart: start,
                    lineEnd: end,
                    operationName: operationName,
                    tolerance: tolerance
                )
            case .arc(let arc):
                return try arc.pathDistanceFromStart(
                    to: point,
                    operationName: operationName,
                    tolerance: tolerance
                )
            }
        }

        func tangent(
            at point: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            switch self {
            case .line(let start, let end):
                _ = try Self.linePathDistance(
                    to: point,
                    lineStart: start,
                    lineEnd: end,
                    operationName: operationName,
                    tolerance: tolerance
                )
                return try start.unitVector(toward: end, tolerance: tolerance)
            case .arc(let arc):
                return try arc.tangent(
                    at: point,
                    operationName: operationName,
                    tolerance: tolerance
                )
            }
        }

        func length(operationName: String, tolerance: Double) throws -> Double {
            switch self {
            case .line(let start, let end):
                let length = start.distance(to: end)
                guard length > tolerance else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(operationName) contains a degenerate profile edge."
                    )
                }
                return length
            case .arc(let arc):
                return arc.length
            }
        }

        private static func linePoint(
            from start: Point,
            toward end: Point,
            distance: Double,
            operationName: String,
            tolerance: Double
        ) throws -> Point {
            let length = start.distance(to: end)
            guard length > distance + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) distance would collapse the profile loop."
                )
            }
            let ratio = distance / length
            return Point(
                x: start.x + (end.x - start.x) * ratio,
                y: start.y + (end.y - start.y) * ratio
            )
        }

        private static func linePathDistance(
            to point: Point,
            lineStart: Point,
            lineEnd: Point,
            operationName: String,
            tolerance: Double
        ) throws -> Double {
            let vector = lineStart.vector(to: lineEnd)
            let length = lineStart.distance(to: lineEnd)
            guard length > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) contains a degenerate profile edge."
                )
            }
            let pointVector = lineStart.vector(to: point)
            let cross = abs(vector.cross(pointVector))
            guard cross <= max(tolerance, length * tolerance) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) produced a point outside the source edge."
                )
            }
            let distance = pointVector.dot(vector) / length
            guard distance >= -tolerance, distance <= length + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) produced a point outside the source edge."
                )
            }
            return min(max(distance, 0.0), length)
        }
    }

    private struct CornerReplacement: Equatable, Sendable {
        var incoming: Point
        var outgoing: Point
        var inserted: Element
    }

    private struct CornerElements: Equatable, Sendable {
        var previous: Element
        var current: Element
    }

    private struct OffsetLine: Equatable, Sendable {
        var point: Point
        var direction: Point
    }

    private struct OffsetCircle: Equatable, Sendable {
        var center: Point
        var radius: Double
    }

    private struct FilletCandidate: Equatable, Sendable {
        var center: Point
        var incoming: Point
        var outgoing: Point
    }

    var plane: SketchPlane
    var vertices: [Point]
    private var elements: [Element]

    private init(
        plane: SketchPlane,
        elements: [Element]
    ) {
        self.plane = plane
        self.elements = elements
        self.vertices = elements.map(\.start)
    }

    static func editableLoop(
        in sketch: Sketch,
        document: DesignDocument,
        operationName: String
    ) throws -> EditableExtrudeProfileLoop {
        try ensureRewritableSketch(sketch, operationName: operationName)
        if sketch.entities.values.allSatisfy({ entity in
            if case .line = entity {
                return true
            }
            return false
        }) {
            return try lineLoop(
                in: sketch,
                document: document,
                operationName: operationName
            )
        }
        return try curveLoop(
            in: sketch,
            document: document,
            operationName: operationName
        )
    }

    static func lineLoop(
        in sketch: Sketch,
        document: DesignDocument,
        operationName: String
    ) throws -> EditableExtrudeProfileLoop {
        var segments: [(start: Point, end: Point)] = []
        for entity in sketch.entities.values {
            guard case .line(let line) = entity else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a line-only closed profile loop."
                )
            }
            segments.append(
                (
                    start: try point(line.start, document: document),
                    end: try point(line.end, document: document)
                )
            )
        }
        guard segments.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least three profile edges."
            )
        }
        var vertices = try orderedVertices(from: segments, operationName: operationName)
        if signedArea(of: vertices) < 0.0 {
            vertices.reverse()
        }
        return EditableExtrudeProfileLoop(
            plane: sketch.plane,
            elements: lineElements(from: vertices)
        )
    }

    private static func curveLoop(
        in sketch: Sketch,
        document: DesignDocument,
        operationName: String
    ) throws -> EditableExtrudeProfileLoop {
        var elements: [Element] = []
        for entity in sketch.entities.values {
            switch entity {
            case .line(let line):
                elements.append(
                    .line(
                        start: try point(line.start, document: document),
                        end: try point(line.end, document: document)
                    )
                )
            case .arc(let arc):
                elements.append(
                    .arc(try arcElement(arc, document: document))
                )
            case .circle, .point, .spline:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a closed profile loop made of lines and arcs."
                )
            }
        }
        guard elements.count >= 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least three profile edges."
            )
        }

        var orderedElements = try orderedElements(
            from: elements,
            operationName: operationName
        )
        if signedArea(of: orderedElements.map(\.start)) < 0.0 {
            orderedElements = orderedElements.reversed().map { $0.reversed() }
        }
        return EditableExtrudeProfileLoop(
            plane: sketch.plane,
            elements: orderedElements
        )
    }

    func closestVertexIndex(
        to point: Point,
        tolerance: Double = 1.0e-8
    ) -> Int? {
        var result: (index: Int, distance: Double)?
        for index in vertices.indices {
            let distance = vertices[index].distance(to: point)
            guard distance <= tolerance else {
                continue
            }
            if let current = result, current.distance <= distance {
                continue
            }
            result = (index, distance)
        }
        return result?.index
    }

    func chamferedSketch(
        targetVertexIndices: Set<Int>,
        distance: Double,
        operationName: String
    ) throws -> Sketch {
        guard distance.isFinite, distance > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) distance must be greater than zero."
            )
        }
        guard !targetVertexIndices.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one profile vertex."
            )
        }
        guard targetVertexIndices.allSatisfy({ vertices.indices.contains($0) }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not a vertex in the editable profile loop."
            )
        }

        let tolerance = 1.0e-9
        var replacements: [Int: CornerReplacement] = [:]
        for index in targetVertexIndices {
            replacements[index] = try chamferReplacement(
                at: index,
                distance: distance,
                operationName: operationName,
                tolerance: tolerance
            )
        }
        return try replacingCorners(
            replacements,
            operationName: operationName,
            tolerance: tolerance
        )
    }

    func filletedSketch(
        targetVertexIndices: Set<Int>,
        radius: Double,
        operationName: String
    ) throws -> Sketch {
        guard radius.isFinite, radius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) radius must be greater than zero."
            )
        }
        guard !targetVertexIndices.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one profile vertex."
            )
        }
        guard targetVertexIndices.allSatisfy({ vertices.indices.contains($0) }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not a vertex in the editable profile loop."
            )
        }

        let tolerance = 1.0e-9
        var replacements: [Int: CornerReplacement] = [:]
        for index in targetVertexIndices {
            replacements[index] = try filletReplacement(
                at: index,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            )
        }
        return try replacingCorners(
            replacements,
            operationName: operationName,
            tolerance: tolerance
        )
    }

    func movedVertexSketch(
        targetVertexIndex: Int,
        deltaX: Double,
        deltaY: Double,
        operationName: String
    ) throws -> Sketch {
        guard vertices.indices.contains(targetVertexIndex) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not a vertex in the editable profile loop."
            )
        }
        guard abs(deltaX) > 1.0e-12 || abs(deltaY) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) delta must not be zero."
            )
        }

        let tolerance = 1.0e-9
        _ = try lineCornerPoints(
            at: targetVertexIndex,
            operationName: operationName,
            tolerance: tolerance
        )
        try ensureMovableLineCornerPreservesAdjacentArcs(
            at: targetVertexIndex,
            operationName: operationName
        )
        let moved = Point(
            x: vertices[targetVertexIndex].x + deltaX,
            y: vertices[targetVertexIndex].y + deltaY
        )
        var nextElements: [Element] = []
        for index in elements.indices {
            let nextIndex = (index + 1) % elements.count
            let element = elements[index]
            let start = index == targetVertexIndex ? moved : element.start
            let end = nextIndex == targetVertexIndex ? moved : element.end
            switch element {
            case .line:
                appendLine(
                    from: start,
                    to: end,
                    to: &nextElements,
                    tolerance: tolerance
                )
            case .arc:
                guard index != targetVertexIndex,
                      nextIndex != targetVertexIndex else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(operationName) currently supports vertices between two line segments in curve profile loops."
                    )
                }
                nextElements.append(element)
            }
        }
        guard nextElements.count == elements.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) would collapse a profile edge."
            )
        }
        return Self.elementSketch(
            plane: plane,
            elements: nextElements,
            tolerance: tolerance
        )
    }

    private static func ensureRewritableSketch(
        _ sketch: Sketch,
        operationName: String
    ) throws {
        guard sketch.dimensions.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot rewrite profile loops that contain sketch dimensions."
            )
        }
        for entity in sketch.entities.values {
            guard entity.usesLiteralExpressions else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) cannot rewrite profile loops that contain parameterized expressions."
                )
            }
        }
        for constraint in sketch.constraints {
            try validateRewriteSafeConstraint(
                constraint,
                in: sketch,
                operationName: operationName
            )
        }
    }

    private static func validateRewriteSafeConstraint(
        _ constraint: SketchConstraint,
        in sketch: Sketch,
        operationName: String
    ) throws {
        switch constraint {
        case .coincident(let first, let second):
            guard isEndpointReference(first),
                  isEndpointReference(second) else {
                throw unsupportedRewriteConstraint(operationName)
            }
        case .horizontal(let entityID), .vertical(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line = entity else {
                throw unsupportedRewriteConstraint(operationName)
            }
        case .parallel,
             .perpendicular,
             .equalLength,
             .tangent,
             .concentric,
             .equalRadius,
             .smoothSplineControlPoint,
             .splineEndpointTangent,
             .tangentSplineEndpoints,
             .smoothSplineEndpoints,
             .fixed:
            throw unsupportedRewriteConstraint(operationName)
        }
    }

    private static func unsupportedRewriteConstraint(_ operationName: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(operationName) cannot rewrite profile loops that contain unsupported sketch constraints."
        )
    }

    private static func isEndpointReference(_ reference: SketchReference) -> Bool {
        switch reference {
        case .lineStart, .lineEnd, .arcStart, .arcEnd:
            return true
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return false
        }
    }

    private static func point(
        _ point: SketchPoint,
        document: DesignDocument
    ) throws -> Point {
        let x = try document.cadDocument.parameters.resolvedValue(for: point.x)
        let y = try document.cadDocument.parameters.resolvedValue(for: point.y)
        guard x.kind == .length, y.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "Profile point coordinates must resolve to lengths."
            )
        }
        guard x.value.isFinite, y.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Profile point coordinates must be finite."
            )
        }
        return Point(x: x.value, y: y.value)
    }

    private static func orderedVertices(
        from segments: [(start: Point, end: Point)],
        operationName: String
    ) throws -> [Point] {
        let tolerance = 1.0e-8
        var remaining = Array(segments.dropFirst())
        var vertices = [segments[0].start]
        var current = segments[0].end

        while !remaining.isEmpty {
            guard let matchIndex = remaining.firstIndex(where: { segment in
                segment.start.isClose(to: current, tolerance: tolerance)
                    || segment.end.isClose(to: current, tolerance: tolerance)
            }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a connected closed profile loop."
                )
            }
            let match = remaining.remove(at: matchIndex)
            appendDistinct(current, to: &vertices, tolerance: tolerance)
            current = match.start.isClose(to: current, tolerance: tolerance) ? match.end : match.start
        }

        guard current.isClose(to: vertices[0], tolerance: tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a closed profile loop."
            )
        }
        return vertices
    }

    private static func orderedElements(
        from elements: [Element],
        operationName: String
    ) throws -> [Element] {
        let tolerance = 1.0e-8
        var remaining = Array(elements.dropFirst())
        var ordered = [elements[0]]
        var current = elements[0].end

        while !remaining.isEmpty {
            guard let matchIndex = remaining.firstIndex(where: { element in
                element.start.isClose(to: current, tolerance: tolerance)
                    || element.end.isClose(to: current, tolerance: tolerance)
            }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a connected closed profile loop."
                )
            }
            let match = remaining.remove(at: matchIndex)
            if match.start.isClose(to: current, tolerance: tolerance) {
                ordered.append(match)
                current = match.end
            } else {
                let reversed = match.reversed()
                ordered.append(reversed)
                current = reversed.end
            }
        }

        guard current.isClose(to: ordered[0].start, tolerance: tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a closed profile loop."
            )
        }
        return ordered
    }

    private static func lineElements(from vertices: [Point]) -> [Element] {
        vertices.indices.map { index in
            let nextIndex = (index + 1) % vertices.count
            return .line(start: vertices[index], end: vertices[nextIndex])
        }
    }

    private static func arcElement(
        _ arc: SketchArc,
        document: DesignDocument
    ) throws -> ArcElement {
        let center = try point(arc.center, document: document)
        let radius = try length(arc.radius, document: document, owner: "Profile arc radius")
        let startAngle = try angle(arc.startAngle, document: document, owner: "Profile arc start angle")
        let endAngle = try angle(arc.endAngle, document: document, owner: "Profile arc end angle")
        guard radius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Profile arc radius must be greater than zero."
            )
        }
        return ArcElement(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: positiveAngleEnd(startAngle: startAngle, endAngle: endAngle),
            isReversed: false
        )
    }

    private static func length(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be finite."
            )
        }
        return quantity.value
    }

    private static func angle(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be finite."
            )
        }
        return quantity.value
    }

    private static func lineSketch(
        plane: SketchPlane,
        vertices: [Point],
        tolerance: Double
    ) -> Sketch {
        var entities: [SketchEntityID: SketchEntity] = [:]
        var lineIDs: [SketchEntityID] = []
        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let lineID = SketchEntityID()
            lineIDs.append(lineID)
            entities[lineID] = .line(
                SketchLine(
                    start: sketchPoint(vertices[index]),
                    end: sketchPoint(vertices[nextIndex])
                )
            )
        }

        var constraints: [SketchConstraint] = []
        for index in lineIDs.indices {
            let lineID = lineIDs[index]
            let nextLineID = lineIDs[(index + 1) % lineIDs.count]
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            if nearlyEqual(start.y, end.y, tolerance: tolerance) {
                constraints.append(.horizontal(lineID))
            } else if nearlyEqual(start.x, end.x, tolerance: tolerance) {
                constraints.append(.vertical(lineID))
            }
            constraints.append(.coincident(.lineEnd(lineID), .lineStart(nextLineID)))
        }

        return Sketch(plane: plane, entities: entities, constraints: constraints)
    }

    private func chamferReplacement(
        at index: Int,
        distance: Double,
        operationName: String,
        tolerance: Double
    ) throws -> CornerReplacement {
        let corner = try cornerElements(
            at: index,
            operationName: operationName,
            tolerance: tolerance
        )
        let incoming = try corner.previous.pointFromEnd(
            distance: distance,
            operationName: operationName,
            tolerance: tolerance
        )
        let outgoing = try corner.current.pointFromStart(
            distance: distance,
            operationName: operationName,
            tolerance: tolerance
        )
        return CornerReplacement(
            incoming: incoming,
            outgoing: outgoing,
            inserted: .line(start: incoming, end: outgoing)
        )
    }

    private func filletReplacement(
        at index: Int,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> CornerReplacement {
        let corner = try cornerElements(
            at: index,
            operationName: operationName,
            tolerance: tolerance
        )
        if case .line = corner.previous,
           case .line = corner.current {
            return try lineLineFilletReplacement(
                at: index,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            )
        }
        return try curveFilletReplacement(
            corner: corner,
            radius: radius,
            operationName: operationName,
            tolerance: tolerance
        )
    }

    private func lineLineFilletReplacement(
        at index: Int,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> CornerReplacement {
        let points = try lineCornerPoints(
            at: index,
            operationName: operationName,
            tolerance: tolerance
        )
        let incomingDirection = try points.current.unitVector(toward: points.previous, tolerance: tolerance)
        let outgoingDirection = try points.current.unitVector(toward: points.next, tolerance: tolerance)
        let incomingEdge = points.current.distance(to: points.previous)
        let outgoingEdge = points.current.distance(to: points.next)
        let pathIn = points.previous.vector(to: points.current)
        let pathOut = points.current.vector(to: points.next)
        guard pathIn.cross(pathOut) > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports convex profile vertices."
            )
        }

        let dotProduct = min(max(incomingDirection.dot(outgoingDirection), -1.0), 1.0)
        let angle = acos(dotProduct)
        guard angle > tolerance, angle < Double.pi - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot fillet a degenerate profile vertex."
            )
        }
        let tangentDistance = radius / tan(angle / 2.0)
        guard incomingEdge > tangentDistance + tolerance,
              outgoingEdge > tangentDistance + tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) radius would collapse the profile loop."
            )
        }

        let bisector = try (incomingDirection + outgoingDirection).normalized(tolerance: tolerance)
        let centerDistance = radius / sin(angle / 2.0)
        let center = points.current + bisector * centerDistance
        let incoming = points.current + incomingDirection * tangentDistance
        let outgoing = points.current + outgoingDirection * tangentDistance
        let startAngle = incoming.angle(relativeTo: center)
        let endAngle = outgoing.angle(relativeTo: center)
        return CornerReplacement(
            incoming: incoming,
            outgoing: outgoing,
            inserted: .arc(
                ArcElement(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: Self.positiveAngleEnd(
                        startAngle: startAngle,
                        endAngle: endAngle
                    ),
                    isReversed: false
                )
            )
        )
    }

    private func curveFilletReplacement(
        corner: CornerElements,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> CornerReplacement {
        let incomingTangent = try corner.previous.tangentAtEnd(tolerance: tolerance)
        let outgoingTangent = try corner.current.tangentAtStart(tolerance: tolerance)
        guard incomingTangent.cross(outgoingTangent) > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a non-tangent convex profile corner for curve fillets."
            )
        }

        let candidates = try curveFilletCandidates(
            corner: corner,
            radius: radius,
            operationName: operationName,
            tolerance: tolerance
        )
        for candidate in candidates {
            if let replacement = try validCurveFilletReplacement(
                candidate,
                corner: corner,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            ) {
                return replacement
            }
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) cannot construct a tangent fillet for this profile corner."
        )
    }

    private func curveFilletCandidates(
        corner: CornerElements,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> [FilletCandidate] {
        switch (corner.previous, corner.current) {
        case (.line(let lineStart, let lineEnd), .arc(let arc)):
            return try lineArcFilletCandidates(
                lineStart: lineStart,
                lineEnd: lineEnd,
                arc: arc,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            ).map { candidate in
                FilletCandidate(
                    center: candidate.center,
                    incoming: candidate.linePoint,
                    outgoing: candidate.arcPoint
                )
            }
        case (.arc(let arc), .line(let lineStart, let lineEnd)):
            return try lineArcFilletCandidates(
                lineStart: lineStart,
                lineEnd: lineEnd,
                arc: arc,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            ).map { candidate in
                FilletCandidate(
                    center: candidate.center,
                    incoming: candidate.arcPoint,
                    outgoing: candidate.linePoint
                )
            }
        case (.arc(let previousArc), .arc(let currentArc)):
            return try arcArcFilletCandidates(
                previousArc: previousArc,
                currentArc: currentArc,
                radius: radius,
                operationName: operationName,
                tolerance: tolerance
            ).map { candidate in
                FilletCandidate(
                    center: candidate.center,
                    incoming: candidate.previousArcPoint,
                    outgoing: candidate.currentArcPoint
                )
            }
        case (.line, .line):
            return []
        }
    }

    private func lineArcFilletCandidates(
        lineStart: Point,
        lineEnd: Point,
        arc: ArcElement,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> [(center: Point, linePoint: Point, arcPoint: Point)] {
        let direction = try lineStart.unitVector(toward: lineEnd, tolerance: tolerance)
        let offsetLine = OffsetLine(
            point: lineStart + direction.leftNormal * radius,
            direction: direction
        )
        let offsetCircle = OffsetCircle(
            center: arc.center,
            radius: try arc.offsetRadius(
                filletRadius: radius,
                operationName: operationName,
                tolerance: tolerance
            )
        )
        let centers = try lineCircleIntersections(
            line: offsetLine,
            circle: offsetCircle,
            tolerance: tolerance
        )
        var candidates: [(center: Point, linePoint: Point, arcPoint: Point)] = []
        for center in centers {
            do {
                candidates.append(
                    (
                        center: center,
                        linePoint: try project(
                            center,
                            ontoLineFrom: lineStart,
                            to: lineEnd,
                            tolerance: tolerance
                        ),
                        arcPoint: try arc.tangentPoint(
                            forFilletCenter: center,
                            operationName: operationName,
                            tolerance: tolerance
                        )
                    )
                )
            } catch let error as EditorError where error.code == .commandInvalid {
                continue
            } catch {
                throw error
            }
        }
        return candidates
    }

    private func arcArcFilletCandidates(
        previousArc: ArcElement,
        currentArc: ArcElement,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> [(center: Point, previousArcPoint: Point, currentArcPoint: Point)] {
        let previousOffsetCircle = OffsetCircle(
            center: previousArc.center,
            radius: try previousArc.offsetRadius(
                filletRadius: radius,
                operationName: operationName,
                tolerance: tolerance
            )
        )
        let currentOffsetCircle = OffsetCircle(
            center: currentArc.center,
            radius: try currentArc.offsetRadius(
                filletRadius: radius,
                operationName: operationName,
                tolerance: tolerance
            )
        )
        let centers = try circleCircleIntersections(
            first: previousOffsetCircle,
            second: currentOffsetCircle,
            tolerance: tolerance
        )
        var candidates: [(center: Point, previousArcPoint: Point, currentArcPoint: Point)] = []
        for center in centers {
            do {
                candidates.append(
                    (
                        center: center,
                        previousArcPoint: try previousArc.tangentPoint(
                            forFilletCenter: center,
                            operationName: operationName,
                            tolerance: tolerance
                        ),
                        currentArcPoint: try currentArc.tangentPoint(
                            forFilletCenter: center,
                            operationName: operationName,
                            tolerance: tolerance
                        )
                    )
                )
            } catch let error as EditorError where error.code == .commandInvalid {
                continue
            } catch {
                throw error
            }
        }
        return candidates
    }

    private func validCurveFilletReplacement(
        _ candidate: FilletCandidate,
        corner: CornerElements,
        radius: Double,
        operationName: String,
        tolerance: Double
    ) throws -> CornerReplacement? {
        let previousLength = try corner.previous.length(
            operationName: operationName,
            tolerance: tolerance
        )
        let currentLength = try corner.current.length(
            operationName: operationName,
            tolerance: tolerance
        )
        let incomingDistance = try corner.previous.pathDistanceFromStart(
            to: candidate.incoming,
            operationName: operationName,
            tolerance: tolerance
        )
        let outgoingDistance = try corner.current.pathDistanceFromStart(
            to: candidate.outgoing,
            operationName: operationName,
            tolerance: tolerance
        )
        guard incomingDistance > tolerance,
              previousLength - incomingDistance > tolerance,
              outgoingDistance > tolerance,
              currentLength - outgoingDistance > tolerance else {
            return nil
        }

        let inserted = ArcElement(
            center: candidate.center,
            radius: radius,
            startAngle: candidate.incoming.angle(relativeTo: candidate.center),
            endAngle: Self.positiveAngleEnd(
                startAngle: candidate.incoming.angle(relativeTo: candidate.center),
                endAngle: candidate.outgoing.angle(relativeTo: candidate.center)
            ),
            isReversed: false
        )
        let previousTangent = try corner.previous.tangent(
            at: candidate.incoming,
            operationName: operationName,
            tolerance: tolerance
        )
        let currentTangent = try corner.current.tangent(
            at: candidate.outgoing,
            operationName: operationName,
            tolerance: tolerance
        )
        let insertedStartTangent = try inserted.tangentAtStart(tolerance: tolerance)
        let insertedEndTangent = try inserted.tangentAtEnd(tolerance: tolerance)
        guard previousTangent.dot(insertedStartTangent) > 0.0,
              currentTangent.dot(insertedEndTangent) > 0.0 else {
            return nil
        }
        return CornerReplacement(
            incoming: candidate.incoming,
            outgoing: candidate.outgoing,
            inserted: .arc(inserted)
        )
    }

    private func lineCircleIntersections(
        line: OffsetLine,
        circle: OffsetCircle,
        tolerance: Double
    ) throws -> [Point] {
        let delta = line.point.vector(to: circle.center)
        let projection = delta.dot(line.direction)
        let distanceSquared = delta.dot(delta) - projection * projection
        let radiusSquared = circle.radius * circle.radius
        let discriminant = radiusSquared - distanceSquared
        guard discriminant >= -tolerance else {
            return []
        }
        if abs(discriminant) <= tolerance {
            return [line.point + line.direction * projection]
        }
        let root = discriminant.squareRoot()
        return [
            line.point + line.direction * (projection - root),
            line.point + line.direction * (projection + root),
        ]
    }

    private func circleCircleIntersections(
        first: OffsetCircle,
        second: OffsetCircle,
        tolerance: Double
    ) throws -> [Point] {
        let centerVector = first.center.vector(to: second.center)
        let centerDistance = first.center.distance(to: second.center)
        guard centerDistance > tolerance else {
            return []
        }
        guard centerDistance <= first.radius + second.radius + tolerance,
              centerDistance >= abs(first.radius - second.radius) - tolerance else {
            return []
        }

        let direction = try centerVector.normalized(tolerance: tolerance)
        let firstRadiusSquared = first.radius * first.radius
        let secondRadiusSquared = second.radius * second.radius
        let along = (
            firstRadiusSquared - secondRadiusSquared + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let heightSquared = firstRadiusSquared - along * along
        guard heightSquared >= -tolerance else {
            return []
        }

        let base = first.center + direction * along
        if abs(heightSquared) <= tolerance {
            return [base]
        }
        let height = heightSquared.squareRoot()
        let normal = direction.leftNormal
        return [
            base + normal * height,
            base + normal * -height,
        ]
    }

    private func project(
        _ point: Point,
        ontoLineFrom lineStart: Point,
        to lineEnd: Point,
        tolerance: Double
    ) throws -> Point {
        let direction = try lineStart.unitVector(toward: lineEnd, tolerance: tolerance)
        let distance = lineStart.vector(to: point).dot(direction)
        return lineStart + direction * distance
    }

    private func cornerElements(
        at index: Int,
        operationName: String,
        tolerance: Double
    ) throws -> CornerElements {
        let previousIndex = (index + elements.count - 1) % elements.count
        let previousElement = elements[previousIndex]
        let currentElement = elements[index]
        guard previousElement.end.isClose(to: currentElement.start, tolerance: tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a connected source profile corner."
            )
        }
        return CornerElements(
            previous: previousElement,
            current: currentElement
        )
    }

    private func lineCornerPoints(
        at index: Int,
        operationName: String,
        tolerance: Double
    ) throws -> (previous: Point, current: Point, next: Point) {
        let previousIndex = (index + elements.count - 1) % elements.count
        let previousElement = elements[previousIndex]
        let currentElement = elements[index]
        guard case .line(let previousStart, let previousEnd) = previousElement,
              case .line(let currentStart, let currentEnd) = currentElement,
              previousEnd.isClose(to: currentStart, tolerance: tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports vertices between two line segments in curve profile loops."
            )
        }
        return (
            previous: previousStart,
            current: currentStart,
            next: currentEnd
        )
    }

    private func ensureMovableLineCornerPreservesAdjacentArcs(
        at index: Int,
        operationName: String
    ) throws {
        let previousIndex = (index + elements.count - 1) % elements.count
        let beforePreviousIndex = (previousIndex + elements.count - 1) % elements.count
        let nextIndex = (index + 1) % elements.count
        if case .arc = elements[beforePreviousIndex] {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot move a sharp vertex when the adjacent line is tangent to an existing arc."
            )
        }
        if case .arc = elements[nextIndex] {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot move a sharp vertex when the adjacent line is tangent to an existing arc."
            )
        }
    }

    private func replacingCorners(
        _ replacements: [Int: CornerReplacement],
        operationName: String,
        tolerance: Double
    ) throws -> Sketch {
        var nextElements: [Element] = []
        for index in elements.indices {
            let nextIndex = (index + 1) % elements.count
            let element = elements[index]
            let start = replacements[index]?.outgoing ?? element.start
            let end = replacements[nextIndex]?.incoming ?? element.end

            try appendTrimmedElement(
                element,
                start: start,
                end: end,
                to: &nextElements,
                operationName: operationName,
                tolerance: tolerance
            )

            if let inserted = replacements[nextIndex]?.inserted {
                nextElements.append(inserted)
            }
        }

        guard nextElements.count >= 4 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) produced an invalid profile loop."
            )
        }
        return Self.elementSketch(
            plane: plane,
            elements: nextElements,
            tolerance: tolerance
        )
    }

    private func appendTrimmedElement(
        _ element: Element,
        start: Point,
        end: Point,
        to elements: inout [Element],
        operationName: String,
        tolerance: Double
    ) throws {
        switch element {
        case .line(let originalStart, let originalEnd):
            try appendTrimmedLine(
                originalStart: originalStart,
                originalEnd: originalEnd,
                start: start,
                end: end,
                to: &elements,
                operationName: operationName,
                tolerance: tolerance
            )
        case .arc(let arc):
            elements.append(
                .arc(
                    try arc.trimmed(
                        from: start,
                        to: end,
                        operationName: operationName,
                        tolerance: tolerance
                    )
                )
            )
        }
    }

    private func appendTrimmedLine(
        originalStart: Point,
        originalEnd: Point,
        start: Point,
        end: Point,
        to elements: inout [Element],
        operationName: String,
        tolerance: Double
    ) throws {
        guard start.isClose(to: end, tolerance: tolerance) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) would collapse a profile edge."
            )
        }
        let startParameter = try lineParameter(
            for: start,
            lineStart: originalStart,
            lineEnd: originalEnd,
            operationName: operationName,
            tolerance: tolerance
        )
        let endParameter = try lineParameter(
            for: end,
            lineStart: originalStart,
            lineEnd: originalEnd,
            operationName: operationName,
            tolerance: tolerance
        )
        guard endParameter > startParameter + tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) would collapse a profile edge."
            )
        }
        elements.append(.line(start: start, end: end))
    }

    private func lineParameter(
        for point: Point,
        lineStart: Point,
        lineEnd: Point,
        operationName: String,
        tolerance: Double
    ) throws -> Double {
        let vector = lineStart.vector(to: lineEnd)
        let lengthSquared = vector.dot(vector)
        guard lengthSquared > tolerance * tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) contains a degenerate profile edge."
            )
        }
        return lineStart.vector(to: point).dot(vector) / lengthSquared
    }

    private static func elementSketch(
        plane: SketchPlane,
        elements: [Element],
        tolerance: Double
    ) -> Sketch {
        var entities: [SketchEntityID: SketchEntity] = [:]
        var references: [(start: SketchReference, end: SketchReference)] = []
        var constraints: [SketchConstraint] = []

        for element in elements {
            let entityID = SketchEntityID()
            switch element {
            case let .line(start, end):
                entities[entityID] = .line(
                    SketchLine(
                        start: sketchPoint(start),
                        end: sketchPoint(end)
                    )
                )
                references.append((start: .lineStart(entityID), end: .lineEnd(entityID)))
                if nearlyEqual(start.y, end.y, tolerance: tolerance) {
                    constraints.append(.horizontal(entityID))
                } else if nearlyEqual(start.x, end.x, tolerance: tolerance) {
                    constraints.append(.vertical(entityID))
                }
            case let .arc(arc):
                entities[entityID] = .arc(
                    SketchArc(
                        center: sketchPoint(arc.center),
                        radius: .length(arc.radius, .meter),
                        startAngle: .angle(arc.startAngle, .radian),
                        endAngle: .angle(arc.endAngle, .radian)
                    )
                )
                references.append(
                    arc.isReversed
                        ? (start: .arcEnd(entityID), end: .arcStart(entityID))
                        : (start: .arcStart(entityID), end: .arcEnd(entityID))
                )
            }
        }

        for index in references.indices {
            constraints.append(
                .coincident(
                    references[index].end,
                    references[(index + 1) % references.count].start
                )
            )
        }
        return Sketch(plane: plane, entities: entities, constraints: constraints)
    }

    private func appendLine(
        from start: Point,
        to end: Point,
        to elements: inout [Element],
        tolerance: Double
    ) {
        guard start.isClose(to: end, tolerance: tolerance) == false else {
            return
        }
        elements.append(.line(start: start, end: end))
    }

    private static func sketchPoint(_ point: Point) -> SketchPoint {
        SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
    }

    private static func appendDistinct(
        _ point: Point,
        to points: inout [Point],
        tolerance: Double
    ) {
        guard points.last?.isClose(to: point, tolerance: tolerance) != true else {
            return
        }
        points.append(point)
    }

    private static func nearlyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func signedArea(of vertices: [Point]) -> Double {
        guard let origin = vertices.first else {
            return 0.0
        }
        var area = 0.0
        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            // Rebase to a local origin so the winding sign stays correct when the
            // loop sits far from the world origin; a raw shoelace on ~1e12
            // coordinates cancels to a random-sign value and silently reverses
            // the loop orientation. Signed area is translation invariant.
            let currentX = vertices[index].x - origin.x
            let currentY = vertices[index].y - origin.y
            let nextX = vertices[nextIndex].x - origin.x
            let nextY = vertices[nextIndex].y - origin.y
            area += currentX * nextY - nextX * currentY
        }
        return area / 2.0
    }

    private static func positiveAngleEnd(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        startAngle + positiveAngleSpan(startAngle: startAngle, endAngle: endAngle)
    }

    private static func positiveAngleSpan(
        startAngle: Double,
        endAngle: Double
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

    private static func nonnegativeAngleSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span < 0.0 {
            span += fullCircle
        }
        while span >= fullCircle {
            span -= fullCircle
        }
        return span
    }
}

private extension EditableExtrudeProfileLoop.Point {
    static func + (
        lhs: EditableExtrudeProfileLoop.Point,
        rhs: EditableExtrudeProfileLoop.Point
    ) -> EditableExtrudeProfileLoop.Point {
        EditableExtrudeProfileLoop.Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func * (
        lhs: EditableExtrudeProfileLoop.Point,
        rhs: Double
    ) -> EditableExtrudeProfileLoop.Point {
        EditableExtrudeProfileLoop.Point(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    func distance(to other: EditableExtrudeProfileLoop.Point) -> Double {
        let deltaX = other.x - x
        let deltaY = other.y - y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    func isClose(
        to other: EditableExtrudeProfileLoop.Point,
        tolerance: Double
    ) -> Bool {
        distance(to: other) <= tolerance
    }

    func point(
        toward other: EditableExtrudeProfileLoop.Point,
        distance: Double,
        tolerance: Double
    ) throws -> EditableExtrudeProfileLoop.Point {
        let length = self.distance(to: other)
        guard length > distance + tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer distance would collapse the profile loop."
            )
        }
        let ratio = distance / length
        return EditableExtrudeProfileLoop.Point(
            x: x + (other.x - x) * ratio,
            y: y + (other.y - y) * ratio
        )
    }

    func vector(to other: EditableExtrudeProfileLoop.Point) -> EditableExtrudeProfileLoop.Point {
        EditableExtrudeProfileLoop.Point(x: other.x - x, y: other.y - y)
    }

    func unitVector(
        toward other: EditableExtrudeProfileLoop.Point,
        tolerance: Double
    ) throws -> EditableExtrudeProfileLoop.Point {
        try vector(to: other).normalized(tolerance: tolerance)
    }

    func normalized(tolerance: Double) throws -> EditableExtrudeProfileLoop.Point {
        let length = (x * x + y * y).squareRoot()
        guard length > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Profile loop contains a degenerate edge."
            )
        }
        return EditableExtrudeProfileLoop.Point(x: x / length, y: y / length)
    }

    var leftNormal: EditableExtrudeProfileLoop.Point {
        EditableExtrudeProfileLoop.Point(x: -y, y: x)
    }

    func dot(_ other: EditableExtrudeProfileLoop.Point) -> Double {
        x * other.x + y * other.y
    }

    func cross(_ other: EditableExtrudeProfileLoop.Point) -> Double {
        x * other.y - y * other.x
    }

    func angle(relativeTo center: EditableExtrudeProfileLoop.Point) -> Double {
        atan2(y - center.y, x - center.x)
    }
}

private extension SketchEntity {
    var usesLiteralExpressions: Bool {
        switch self {
        case .point(let point):
            return point.usesLiteralExpressions
        case .line(let line):
            return line.start.usesLiteralExpressions
                && line.end.usesLiteralExpressions
        case .circle(let circle):
            return circle.center.usesLiteralExpressions
                && circle.radius.isLiteral
        case .arc(let arc):
            return arc.center.usesLiteralExpressions
                && arc.radius.isLiteral
                && arc.startAngle.isLiteral
                && arc.endAngle.isLiteral
        case .spline(let spline):
            return spline.controlPoints.allSatisfy(\.usesLiteralExpressions)
        }
    }
}

private extension SketchPoint {
    var usesLiteralExpressions: Bool {
        x.isLiteral && y.isLiteral
    }
}

private extension CADExpression {
    var isLiteral: Bool {
        switch self {
        case .constant:
            return true
        case .reference, .variable:
            return false
        case .add(let left, let right),
             .subtract(let left, let right),
             .multiply(let left, let right),
             .divide(let left, let right):
            return left.isLiteral && right.isLiteral
        case .sin(let argument),
             .cos(let argument),
             .tan(let argument):
            return argument.isLiteral
        }
    }
}
