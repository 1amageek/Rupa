import Foundation
import SwiftCAD
import RupaCoreTypes

struct CurvePatternPathSampler: Sendable {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    func geometry(
        points: [Point3D],
        referenceNormal: Vector3D
    ) throws -> Geometry {
        try Geometry(
            evaluator: .polyline(try PolylinePath(points: points, tolerance: tolerance)),
            referenceNormal: referenceNormal,
            tolerance: tolerance
        )
    }

    func geometry(
        for curve: EvaluatedCurve,
        referenceNormal: Vector3D
    ) throws -> Geometry {
        if let exactEvaluator = try exactEvaluator(for: curve) {
            return try Geometry(
                evaluator: exactEvaluator,
                referenceNormal: referenceNormal,
                tolerance: tolerance
            )
        }
        return try geometry(points: curve.points, referenceNormal: referenceNormal)
    }

    private func exactEvaluator(for curve: EvaluatedCurve) throws -> Evaluator? {
        guard let exactCurve = curve.exactCurve else {
            return nil
        }
        switch exactCurve {
        case .line(let line):
            guard case .closed(let start, let end) = curve.parameterDomain else {
                return nil
            }
            return .line(try ExactLinePath(
                line: line,
                startParameter: start,
                endParameter: end,
                tolerance: tolerance
            ))
        case .circle(let circle):
            switch curve.parameterDomain {
            case .closed(let start, let end):
                return .circle(try ExactCirclePath(
                    circle: circle,
                    startParameter: start,
                    endParameter: end,
                    tolerance: tolerance
                ))
            case .periodic(let period):
                guard curve.isClosed,
                      let first = curve.points.first else {
                    return nil
                }
                let start = try circleParameter(for: first, on: circle)
                return .circle(try ExactCirclePath(
                    circle: circle,
                    startParameter: start,
                    endParameter: start + period,
                    tolerance: tolerance
                ))
            case .unbounded:
                return nil
            }
        case .bSpline:
            return nil
        }
    }

    private func circleParameter(
        for point: Point3D,
        on circle: Circle3D
    ) throws -> Double {
        let (u, v) = try circleBasis(for: circle)
        let offset = point - circle.center
        return atan2(offset.dot(v), offset.dot(u))
    }

    private func circleBasis(for circle: Circle3D) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    struct Geometry: Sendable {
        var referenceNormal: Vector3D
        private let evaluator: Evaluator

        var totalLength: Double {
            evaluator.totalLength
        }

        var origin: Point3D {
            evaluator.origin
        }

        fileprivate init(
            evaluator: Evaluator,
            referenceNormal: Vector3D,
            tolerance: ModelingTolerance
        ) throws {
            try referenceNormal.validate()
            self.referenceNormal = try referenceNormal.normalized(tolerance: tolerance.distance)
            self.evaluator = evaluator
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            try evaluator.sample(at: distance, tolerance: tolerance)
        }
    }

    struct Sample: Sendable {
        var point: Point3D
        var tangent: Vector3D
    }

    fileprivate enum Evaluator: Sendable {
        case polyline(PolylinePath)
        case line(ExactLinePath)
        case circle(ExactCirclePath)

        var totalLength: Double {
            switch self {
            case .polyline(let path):
                path.totalLength
            case .line(let path):
                path.totalLength
            case .circle(let path):
                path.totalLength
            }
        }

        var origin: Point3D {
            switch self {
            case .polyline(let path):
                path.origin
            case .line(let path):
                path.origin
            case .circle(let path):
                path.origin
            }
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            switch self {
            case .polyline(let path):
                try path.sample(at: distance, tolerance: tolerance)
            case .line(let path):
                try path.sample(at: distance, tolerance: tolerance)
            case .circle(let path):
                try path.sample(at: distance, tolerance: tolerance)
            }
        }
    }

    fileprivate struct PolylinePath: Sendable {
        var points: [Point3D]
        var cumulativeLengths: [Double]
        var totalLength: Double

        var origin: Point3D {
            points[0]
        }

        init(
            points: [Point3D],
            tolerance: ModelingTolerance
        ) throws {
            guard points.count >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array paths must contain at least two points."
                )
            }
            var cumulativeLengths = [0.0]
            cumulativeLengths.reserveCapacity(points.count)
            var totalLength = 0.0
            for index in 1 ..< points.count {
                let segmentLength = (points[index] - points[index - 1]).length
                guard segmentLength > tolerance.distance else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Curve pattern array paths must not contain degenerate spans."
                    )
                }
                totalLength += segmentLength
                cumulativeLengths.append(totalLength)
            }
            guard totalLength > tolerance.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array paths must have positive length."
                )
            }
            self.points = points
            self.cumulativeLengths = cumulativeLengths
            self.totalLength = totalLength
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            let clampedDistance = min(max(distance, 0.0), totalLength)
            let spanIndex = spanIndex(containing: clampedDistance)
            let startLength = cumulativeLengths[spanIndex - 1]
            let endLength = cumulativeLengths[spanIndex]
            let spanLength = endLength - startLength
            let localParameter = spanLength > tolerance.distance
                ? (clampedDistance - startLength) / spanLength
                : 0.0
            let start = points[spanIndex - 1]
            let end = points[spanIndex]
            let tangent = try (end - start).normalized(tolerance: tolerance.distance)
            let point = start + ((end - start) * localParameter)
            return Sample(point: point, tangent: tangent)
        }

        private func spanIndex(containing distance: Double) -> Int {
            if distance <= 0.0 {
                return 1
            }
            for index in 1 ..< cumulativeLengths.count where distance <= cumulativeLengths[index] {
                return index
            }
            return cumulativeLengths.count - 1
        }
    }

    fileprivate struct ExactLinePath: Sendable {
        var line: Line3D
        var startParameter: Double
        var directionSign: Double
        var totalLength: Double
        var origin: Point3D

        init(
            line: Line3D,
            startParameter: Double,
            endParameter: Double,
            tolerance: ModelingTolerance
        ) throws {
            try line.validate(tolerance: tolerance)
            guard startParameter.isFinite,
                  endParameter.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array line path parameters must be finite."
                )
            }
            let span = endParameter - startParameter
            let length = abs(span)
            guard length > tolerance.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array line paths must have positive length."
                )
            }
            self.line = line
            self.startParameter = startParameter
            self.directionSign = span >= 0.0 ? 1.0 : -1.0
            self.totalLength = length
            self.origin = line.origin + (line.direction * startParameter)
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            let clampedDistance = min(max(distance, 0.0), totalLength)
            let parameter = startParameter + directionSign * clampedDistance
            let point = line.origin + (line.direction * parameter)
            let tangent = line.direction * directionSign
            try tangent.validateUnitLength(tolerance: tolerance)
            return Sample(point: point, tangent: tangent)
        }
    }

    fileprivate struct ExactCirclePath: Sendable {
        var circle: Circle3D
        var startParameter: Double
        var directionSign: Double
        var totalLength: Double
        var origin: Point3D

        init(
            circle: Circle3D,
            startParameter: Double,
            endParameter: Double,
            tolerance: ModelingTolerance
        ) throws {
            try circle.validate(tolerance: tolerance)
            guard startParameter.isFinite,
                  endParameter.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array circular path parameters must be finite."
                )
            }
            let span = endParameter - startParameter
            let angle = abs(span)
            guard angle > tolerance.angle else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array circular paths must have positive angular span."
                )
            }
            let length = circle.radius * angle
            guard length > tolerance.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array circular paths must have positive length."
                )
            }
            let geometry = try Curve3D.circle(circle).differentialGeometry(at: startParameter, tolerance: tolerance)
            self.circle = circle
            self.startParameter = startParameter
            self.directionSign = span >= 0.0 ? 1.0 : -1.0
            self.totalLength = length
            self.origin = geometry.position
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            let clampedDistance = min(max(distance, 0.0), totalLength)
            let parameter = startParameter + directionSign * (clampedDistance / circle.radius)
            let geometry = try Curve3D.circle(circle).differentialGeometry(at: parameter, tolerance: tolerance)
            let tangent = geometry.tangent * directionSign
            try tangent.validateUnitLength(tolerance: tolerance)
            return Sample(point: geometry.position, tangent: tangent)
        }
    }
}
