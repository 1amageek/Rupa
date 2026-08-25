import SwiftCAD

struct CurvePatternPathSampler: Sendable {
    private let tolerance: ModelingTolerance
    private let evaluator: EvaluatedCurvePathEvaluator

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
        self.evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
    }

    func geometry(
        points: [Point3D],
        referenceNormal: Vector3D
    ) throws -> Geometry {
        try Geometry(
            path: evaluator.prepare(points: points),
            referenceNormal: referenceNormal,
            evaluator: evaluator,
            tolerance: tolerance
        )
    }

    func geometry(
        for curve: EvaluatedCurve,
        referenceNormal: Vector3D
    ) throws -> Geometry {
        try Geometry(
            path: evaluator.prepare(curve),
            referenceNormal: referenceNormal,
            evaluator: evaluator,
            tolerance: tolerance
        )
    }

    struct Geometry: Sendable {
        var referenceNormal: Vector3D
        private let path: PreparedEvaluatedCurvePath
        private let evaluator: EvaluatedCurvePathEvaluator

        var totalLength: Double {
            path.totalLength
        }

        var origin: Point3D {
            path.origin
        }

        fileprivate init(
            path: PreparedEvaluatedCurvePath,
            referenceNormal: Vector3D,
            evaluator: EvaluatedCurvePathEvaluator,
            tolerance: ModelingTolerance
        ) throws {
            try referenceNormal.validate()
            self.referenceNormal = try referenceNormal.normalized(
                tolerance: tolerance.distance
            )
            self.path = path
            self.evaluator = evaluator
        }

        func sample(
            at distance: Double,
            tolerance: ModelingTolerance
        ) throws -> Sample {
            let result = try evaluator.sample(at: distance, on: path)
            return Sample(point: result.point, tangent: result.tangent)
        }
    }

    struct Sample: Sendable {
        var point: Point3D
        var tangent: Vector3D
    }
}
