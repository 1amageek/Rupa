import Foundation
import SwiftCAD

public struct CircleAwareSketchProfileExtractor: SketchProfileExtracting {
    private let resolver: ParameterResolving
    private let tolerance: ModelingTolerance
    private let circleSegmentCount: Int
    private let circleSegmentCountsByFeatureID: [FeatureID: Int]

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        tolerance: ModelingTolerance = .standard,
        circleSegmentCount: Int = 64,
        circleSegmentCountsByFeatureID: [FeatureID: Int] = [:]
    ) {
        self.resolver = resolver
        self.tolerance = tolerance
        self.circleSegmentCount = max(circleSegmentCount, 3)
        self.circleSegmentCountsByFeatureID = circleSegmentCountsByFeatureID.mapValues { max($0, 3) }
    }

    public func extractProfiles(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [Profile] {
        try tolerance.validate()
        var lines: [ResolvedSketchLine] = []
        var circles: [ResolvedSketchCircle] = []
        for (entityID, entity) in sketch.entities.sorted(by: { $0.key.description < $1.key.description }) {
            switch entity {
            case let .line(line):
                lines.append(ResolvedSketchLine(
                    id: entityID,
                    start: try resolve(line.start, parameters: parameters),
                    end: try resolve(line.end, parameters: parameters)
                ))
            case .point:
                throw SketchError.unsupportedProfile("Point entities are not supported in profile extraction.")
            case let .circle(circle):
                circles.append(ResolvedSketchCircle(
                    id: entityID,
                    center: try resolve(circle.center, parameters: parameters),
                    radius: try resolvePositiveLength(circle.radius, parameters: parameters)
                ))
            }
        }

        if let circle = circles.first, circles.count == 1, lines.isEmpty {
            let vertices = try circlePoints(
                for: circle,
                segmentCount: circleSegmentCount(for: sourceFeatureID)
            ).map { point in
                try mapTo3D(point, on: sketch.plane)
            }
            return [Profile(sourceFeatureID: sourceFeatureID, plane: sketch.plane, vertices: vertices)]
        }

        guard circles.isEmpty else {
            throw SketchError.unsupportedProfile("Mixed or multiple circle profiles are not supported.")
        }
        guard !lines.isEmpty else {
            throw SketchError.emptyProfile
        }

        let orderedPoints = try normalizedSupportedLoop(from: try orderClosedLoop(lines))
        let vertices = try orderedPoints.map { point in
            try mapTo3D(point, on: sketch.plane)
        }
        return [Profile(sourceFeatureID: sourceFeatureID, plane: sketch.plane, vertices: vertices)]
    }

    private func resolve(_ point: SketchPoint, parameters: ResolvedParameterTable) throws -> Point2D {
        let x = try resolver.evaluate(point.x, parameters: parameters, variables: [:])
        let y = try resolver.evaluate(point.y, parameters: parameters, variables: [:])
        guard x.kind == .length else {
            throw UnitError.expectedQuantity(operation: "sketch.x", expected: .length, actual: x.kind)
        }
        guard y.kind == .length else {
            throw UnitError.expectedQuantity(operation: "sketch.y", expected: .length, actual: y.kind)
        }
        return Point2D(x: x.value, y: y.value)
    }

    private func resolvePositiveLength(
        _ expression: CADExpression,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let value = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard value.kind == .length else {
            throw UnitError.expectedQuantity(operation: "circle.radius", expected: .length, actual: value.kind)
        }
        guard value.value.isFinite, value.value > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return value.value
    }

    private func circleSegmentCount(for featureID: FeatureID) -> Int {
        circleSegmentCountsByFeatureID[featureID] ?? circleSegmentCount
    }

    private func circlePoints(
        for circle: ResolvedSketchCircle,
        segmentCount: Int
    ) -> [Point2D] {
        (0..<segmentCount).map { index in
            let angle = Double(index) / Double(segmentCount) * 2.0 * Double.pi
            return Point2D(
                x: circle.center.x + cos(angle) * circle.radius,
                y: circle.center.y + sin(angle) * circle.radius
            )
        }
    }

    private func orderClosedLoop(_ lines: [ResolvedSketchLine]) throws -> [Point2D] {
        var unused = lines
        guard let first = unused.first else {
            throw SketchError.emptyProfile
        }
        unused.removeFirst()

        var ordered: [Point2D] = [first.start, first.end]
        var current = first.end

        while !unused.isEmpty {
            guard let matchIndex = unused.firstIndex(where: {
                isClose($0.start, current) || isClose($0.end, current)
            }) else {
                throw SketchError.openProfile
            }

            let match = unused.remove(at: matchIndex)
            if isClose(match.start, current) {
                current = match.end
                ordered.append(match.end)
            } else {
                current = match.start
                ordered.append(match.start)
            }
        }

        guard let start = ordered.first, isClose(start, current) else {
            throw SketchError.openProfile
        }
        ordered.removeLast()
        guard ordered.count >= 3 else {
            throw SketchError.openProfile
        }
        return ordered
    }

    private func normalizedSupportedLoop(from points: [Point2D]) throws -> [Point2D] {
        let area = signedArea(of: points)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(area) > areaTolerance else {
            throw SketchError.degenerateProfile
        }

        let normalized = area > 0.0 ? points : Array(points.reversed())
        try validateConvex(normalized)
        return normalized
    }

    private func validateConvex(_ points: [Point2D]) throws {
        let areaTolerance = tolerance.distance * tolerance.distance
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let first = Point2D(x: current.x - previous.x, y: current.y - previous.y)
            let second = Point2D(x: next.x - current.x, y: next.y - current.y)
            let cross = first.x * second.y - first.y * second.x
            if cross < -areaTolerance {
                throw SketchError.unsupportedProfile("Concave profiles are not supported.")
            }
            if abs(cross) <= areaTolerance {
                throw SketchError.degenerateProfile
            }
        }
    }

    private func signedArea(of points: [Point2D]) -> Double {
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea / 2.0
    }

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
    }

    private func mapTo3D(_ point: Point2D, on plane: SketchPlane) throws -> Point3D {
        switch plane {
        case .xy:
            return Point3D(x: point.x, y: point.y, z: 0.0)
        case .yz:
            return Point3D(x: 0.0, y: point.x, z: point.y)
        case .zx:
            return Point3D(x: point.y, y: 0.0, z: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return plane.origin + (u * point.x) + (v * point.y)
        }
    }
}

private struct ResolvedSketchLine {
    var id: SketchEntityID
    var start: Point2D
    var end: Point2D
}

private struct ResolvedSketchCircle {
    var id: SketchEntityID
    var center: Point2D
    var radius: Double
}
