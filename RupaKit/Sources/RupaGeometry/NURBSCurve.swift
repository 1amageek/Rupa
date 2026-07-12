import Foundation

public struct NURBSCurve: Codable, Equatable, Sendable {
    public let degree: Int
    public let controlPoints: GeometryBuffer<GeometryPoint3D>
    public let weights: GeometryBuffer<Double>
    public let knots: GeometryBuffer<Double>

    public init(
        degree: Int,
        controlPoints: GeometryBuffer<GeometryPoint3D>,
        weights: GeometryBuffer<Double>,
        knots: GeometryBuffer<Double>
    ) throws {
        self.degree = degree
        self.controlPoints = controlPoints
        self.weights = weights
        self.knots = knots
        try validate()
    }

    public var domain: ClosedRange<Double> {
        knots[degree]...knots[controlPoints.count]
    }

    public func validate() throws {
        guard degree >= 1 else {
            throw NURBSCurveError(
                code: .invalidDegree,
                message: "NURBS curve degree must be at least one."
            )
        }
        guard controlPoints.count >= degree + 1 else {
            throw NURBSCurveError(
                code: .invalidControlPointCount,
                message: "NURBS curves require at least degree plus one control points."
            )
        }
        guard weights.count == controlPoints.count else {
            throw NURBSCurveError(
                code: .invalidWeight,
                message: "NURBS weights must match the control point count."
            )
        }
        guard knots.count == controlPoints.count + degree + 1 else {
            throw NURBSCurveError(
                code: .invalidKnotVector,
                message: "NURBS knot vectors must contain control point count plus degree plus one values."
            )
        }
        for point in controlPoints {
            try point.validate()
        }
        for weight in weights {
            guard weight.isFinite, weight > 0 else {
                throw NURBSCurveError(
                    code: .invalidWeight,
                    message: "NURBS weights must be finite and positive."
                )
            }
        }
        var previous: Double?
        for knot in knots {
            guard knot.isFinite else {
                throw NURBSCurveError(
                    code: .invalidKnotVector,
                    message: "NURBS knots must be finite."
                )
            }
            if let previous, knot < previous {
                throw NURBSCurveError(
                    code: .invalidKnotVector,
                    message: "NURBS knots must be non-decreasing."
                )
            }
            previous = knot
        }
        let domain = knots[degree]...knots[controlPoints.count]
        guard domain.lowerBound < domain.upperBound else {
            throw NURBSCurveError(
                code: .invalidKnotVector,
                message: "NURBS parameter domain must have positive length."
            )
        }
    }

    public func evaluate(at parameter: Double) throws -> GeometryPoint3D {
        guard parameter.isFinite else {
            throw NURBSCurveError(
                code: .parameterOutOfRange,
                message: "NURBS evaluation parameters must be finite."
            )
        }
        let domain = self.domain
        guard domain.contains(parameter) else {
            throw NURBSCurveError(
                code: .parameterOutOfRange,
                message: "NURBS evaluation parameter lies outside the curve domain."
            )
        }
        let span = findSpan(parameter)
        let basis = basisFunctions(span: span, parameter: parameter)
        var weightedX = 0.0
        var weightedY = 0.0
        var weightedZ = 0.0
        var weightSum = 0.0
        for localIndex in 0...degree {
            let controlPointIndex = span - degree + localIndex
            let weightedBasis = basis[localIndex] * weights[controlPointIndex]
            let point = controlPoints[controlPointIndex]
            weightedX += weightedBasis * point.x
            weightedY += weightedBasis * point.y
            weightedZ += weightedBasis * point.z
            weightSum += weightedBasis
        }
        guard weightSum.isFinite, weightSum > 0 else {
            throw NURBSCurveError(
                code: .zeroHomogeneousWeight,
                message: "NURBS evaluation produced a zero homogeneous weight."
            )
        }
        let point = GeometryPoint3D(
            x: weightedX / weightSum,
            y: weightedY / weightSum,
            z: weightedZ / weightSum
        )
        try point.validate()
        return point
    }

    public func sample(count: Int) throws -> [GeometryPoint3D] {
        guard count >= 2 else {
            throw NURBSCurveError(
                code: .invalidSampleCount,
                message: "NURBS sampling requires at least two samples."
            )
        }
        let domain = self.domain
        return try (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            return try evaluate(at: domain.lowerBound + (domain.upperBound - domain.lowerBound) * fraction)
        }
    }

    private func findSpan(_ parameter: Double) -> Int {
        let controlPointCount = controlPoints.count
        if parameter >= knots[controlPointCount] {
            return controlPointCount - 1
        }
        if parameter <= knots[degree] {
            return degree
        }
        var low = degree
        var high = controlPointCount
        var middle = (low + high) / 2
        while parameter < knots[middle] || parameter >= knots[middle + 1] {
            if parameter < knots[middle] {
                high = middle
            } else {
                low = middle
            }
            middle = (low + high) / 2
        }
        return middle
    }

    private func basisFunctions(span: Int, parameter: Double) -> [Double] {
        var basis = Array(repeating: 0.0, count: degree + 1)
        var left = Array(repeating: 0.0, count: degree + 1)
        var right = Array(repeating: 0.0, count: degree + 1)
        basis[0] = 1.0
        if degree == 0 {
            return basis
        }
        for currentDegree in 1...degree {
            left[currentDegree] = parameter - knots[span + 1 - currentDegree]
            right[currentDegree] = knots[span + currentDegree] - parameter
            var saved = 0.0
            for localIndex in 0..<currentDegree {
                let denominator = right[localIndex + 1] + left[currentDegree - localIndex]
                let temporary = denominator == 0 ? 0 : basis[localIndex] / denominator
                basis[localIndex] = saved + right[localIndex + 1] * temporary
                saved = left[currentDegree - localIndex] * temporary
            }
            basis[currentDegree] = saved
        }
        return basis
    }
}
