import SwiftCAD

/// Immutable exact native quarter traversals and their original paper action.
struct OriginalDrawingAngularSector: Sendable {
    let spans: [OriginalCurveRootSpan3D]
    let operationWord: OriginalAffineOperationWord
    let isCounterclockwise: Bool
    let originalCenter: Point2D
    let originalFirst: Point2D
    let originalSecond: Point2D

    private struct Admission: RationalAlgebraAdmitting {
        let work: @Sendable (Int) throws -> Void
        let storage: @Sendable (Int) throws -> Void
        let maximumDepth: Int
        mutating func consumeExactWork(_ count: Int) throws { try work(count) }
        mutating func retainExactStorage(_ words: Int) throws {
            let bytes = words.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard words >= 0, !bytes.overflow else { throw OriginalDrawingAngularSector.invalid("Angular exact storage overflowed.") }
            try storage(bytes.partialValue)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth else { throw OriginalDrawingAngularSector.invalid("Angular original root depth is exhausted.") }
            try work(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    }

    private struct Ray {
        let x: ExactRationalCoefficient
        let y: ExactRationalCoefficient
        let quarter: Int
    }

    init(annotation: DrawingProjectionResult.Annotation, radius: Double,
         options: DrawingGeometricPageOptions, paperTolerance: ModelingTolerance,
         usage: inout DrawingExchangeUsage) throws {
        try usage.check(); try paperTolerance.validate()
        guard annotation.kind == .angle, let degrees = annotation.measurementDegrees, degrees.isFinite,
              annotation.anchors.count >= 3, radius.isFinite, radius > 0 else {
            throw Self.invalid("Angular layout needs a current original angle and positive paper radius.")
        }
        var admission = Admission(work: usage.preparationWorkCallback,
            storage: usage.preparationStorageCallback, maximumDepth: usage.maximumAlgebraicDepth)
        let center: DrawingProjectionResult.AnnotationAnchor
        let first: DrawingProjectionResult.AnnotationAnchor
        let second: DrawingProjectionResult.AnnotationAnchor
        if let explicitCenter = annotation.anchors.first(where: { $0.role == .center }) {
            center = explicitCenter
            var firstSide: DrawingProjectionResult.AnnotationAnchor?
            var secondSide: DrawingProjectionResult.AnnotationAnchor?
            for anchor in annotation.anchors {
                try admission.consumeExactWork(1)
                if anchor.role == .center { continue }
                if firstSide == nil { firstSide = anchor }
                else if secondSide == nil { secondSide = anchor }
            }
            guard let a = firstSide, let b = secondSide else {
                throw Self.invalid("Angular center has no two original side anchors.")
            }
            first = a; second = b
        } else {
            first = annotation.anchors[0]; center = annotation.anchors[1]; second = annotation.anchors[2]
        }
        let a = try Self.ray(first.point2D, from: center.point2D, usage: &admission)
        let b = try Self.ray(second.point2D, from: center.point2D, usage: &admission)
        let cross = try a.x.multiplied(by: b.y, usage: &admission)
            .subtracting(a.y.multiplied(by: b.x, usage: &admission), usage: &admission)
        if cross.isZero {
            let dot = try a.x.multiplied(by: b.x, usage: &admission)
                .adding(a.y.multiplied(by: b.y, usage: &admission), usage: &admission)
            guard dot.isNegative else { throw Self.invalid("Angular projected rays coincide.") }
        }
        let forward = !cross.isNegative
        let startRay = forward ? a : b, endRay = forward ? b : a
        let distance = (paperTolerance.distance / max(1, radius)).nextDown
        guard distance.isFinite, distance > 0 else { throw Self.invalid("Angular source precision is exhausted.") }
        let sourceTolerance = ModelingTolerance(distance: distance, angle: paperTolerance.angle,
            relative: paperTolerance.relative)
        let bytes = 4 * MemoryLayout<OriginalCurveRootSpan3D>.stride
        try usage.charge(bytes: bytes)
        var pieces: [OriginalCurveRootSpan3D] = []; pieces.reserveCapacity(4)
        var quarter = startRay.quarter
        for ordinal in 0..<4 {
            try admission.consumeExactWork(1)
            let source = try Self.quarter(quarter, usage: &usage)
            let start = ordinal == 0 ? try Self.endpoint(startRay, source: source,
                tolerance: sourceTolerance, usage: &admission) : .authored(0)
            let isLast = quarter == endRay.quarter
            let end = isLast ? try Self.endpoint(endRay, source: source,
                tolerance: sourceTolerance, usage: &admission) : .authored(1)
            // An axis belongs to the next quarter's lower endpoint. A zero final
            // quarter adds no curve while preserving the preceding exact axis end.
            let zeroFinal: Bool
            if isLast, case .authored(0) = end, ordinal > 0 { zeroFinal = true }
            else { zeroFinal = false }
            if !zeroFinal {
                pieces.append(try OriginalCurveRootSpan3D(source: .bSpline(source),
                    start: start, end: end, nativeSpanIndex: 2,
                    maximumParameterWidth: distance, maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                    tolerance: sourceTolerance, storageByteStride: MemoryLayout<UInt32>.stride,
                    usage: &admission, maximumSpanCount: 1,
                    remainingSourceDepth: min(32, usage.maximumNesting),
                    maximumAlgebraicDepth: usage.maximumAlgebraicDepth))
            }
            if isLast { break }
            quarter = (quarter + 1) % 4
        }
        guard !pieces.isEmpty else { throw Self.invalid("Angular original sector has no positive traversal.") }
        // Smaller clockwise sectors are authored by reversing the admitted
        // counterclockwise source traversal, not by reconstructing its endpoints.
        if !forward {
            pieces.reverse()
            for index in pieces.indices { pieces[index] = pieces[index].reversed() }
        }
        let qRadius = try ExactRationalCoefficient.originalDouble(radius, usage: &admission)
        let gain = try ExactRationalCoefficient.originalDouble(options.pointsPerMeter, usage: &admission)
        let tx = try ExactRationalCoefficient.originalDouble(center.point2D.x, usage: &admission)
            .multiplied(by: gain, usage: &admission)
            .adding(.originalDouble(options.translation.x, usage: &admission), usage: &admission)
        let ty = try ExactRationalCoefficient.originalDouble(center.point2D.y, usage: &admission)
            .multiplied(by: gain, usage: &admission)
            .adding(.originalDouble(options.translation.y, usage: &admission), usage: &admission)
        try usage.charge(bytes: 12 * MemoryLayout<ExactRationalCoefficient>.stride + MemoryLayout<OriginalAffineOperation>.stride)
        let coefficients: [ExactRationalCoefficient] = [qRadius, .zero, .zero, tx,
            .zero, qRadius, .zero, ty, .zero, .zero, .one, .zero]
        let action = try OriginalRationalAffineSource(coefficients: coefficients, usage: &admission)
        operationWord = try OriginalAffineOperationWord(factors: [.rationalForward(action)], usage: &admission)
        spans = pieces; isCounterclockwise = forward
        originalCenter = center.point2D; originalFirst = first.point2D; originalSecond = second.point2D
    }

    private static func ray(_ point: Point2D, from center: Point2D, usage: inout Admission) throws -> Ray {
        let x = try ExactRationalCoefficient.originalDouble(point.x, usage: &usage)
            .subtracting(.originalDouble(center.x, usage: &usage), usage: &usage)
        let y = try ExactRationalCoefficient.originalDouble(point.y, usage: &usage)
            .subtracting(.originalDouble(center.y, usage: &usage), usage: &usage)
        guard !x.isZero || !y.isZero else { throw invalid("Angular original side collapses onto its center.") }
        let quarter = x.isPositive && !y.isNegative ? 0 : y.isPositive && !x.isPositive ? 1 :
            x.isNegative && !y.isPositive ? 2 : 3
        return Ray(x: x, y: y, quarter: quarter)
    }

    private static func quarter(_ ordinal: Int, usage: inout DrawingExchangeUsage) throws -> BSplineCurve3D {
        try usage.charge(work: 3, bytes: 3 * MemoryLayout<Point3D>.stride + 9 * MemoryLayout<Double>.stride)
        func rotated(_ x: Double, _ y: Double) -> Point3D {
            switch ordinal {
            case 0: return Point3D(x: x, y: y, z: 0)
            case 1: return Point3D(x: -y, y: x, z: 0)
            case 2: return Point3D(x: -x, y: -y, z: 0)
            default: return Point3D(x: y, y: -x, z: 0)
            }
        }
        return BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1],
            controlPoints: [rotated(1,0),rotated(1,1),rotated(0,1)], weights: [1,1,2])
    }

    private static func endpoint(_ ray: Ray, source: BSplineCurve3D,
        tolerance: ModelingTolerance, usage: inout Admission) throws -> OriginalCurveRootEndpoint {
        let x: ExactRationalCoefficient, y: ExactRationalCoefficient
        switch ray.quarter {
        case 0: x = ray.x; y = ray.y
        case 1: x = ray.y; y = ray.x.negated
        case 2: x = ray.x.negated; y = ray.y.negated
        default: x = ray.y.negated; y = ray.x
        }
        guard x.isPositive, !y.isNegative else { throw invalid("Angular positive ray is outside its owning quarter.") }
        if y.isZero { return .authored(0) }
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let polynomial = try t.scaled(by: two.multiplied(by: x, usage: &usage), usage: &usage)
            .subtracting(one.subtracting(t.multiplied(by: t, usage: &usage), usage: &usage)
                .scaled(by: y, usage: &usage), usage: &usage)
        let roots = try ExactUnivariateRootIsolator().isolate(polynomial, lower: .zero, upper: .one,
            maximumDepth: usage.maximumDepth, usage: &usage)
        guard roots.count == 1, let root = roots.first else { throw invalid("Angular original ray has no unique quarter incidence.") }
        return .algebraic(try OriginalCurveRootBoundary(source: source, spanIndex: 2,
            constraint: .parameterPolynomial(polynomial), isolation: root,
            maximumSubdivisionDepth: usage.maximumDepth, tolerance: tolerance, usage: &usage))
    }

    private static func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
