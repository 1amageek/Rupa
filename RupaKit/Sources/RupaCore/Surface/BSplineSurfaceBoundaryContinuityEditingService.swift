import SwiftCAD
import RupaCoreTypes

struct BSplineSurfaceBoundaryContinuityEditingService: Sendable {
    func updatedFeature(
        matching target: BSplineSurfaceFeature,
        targetSide: BSplineSurfaceBoundarySide,
        to reference: BSplineSurfaceFeature,
        referenceSide: BSplineSurfaceBoundarySide,
        level: SurfaceBoundaryContinuityLevel,
        matchSide: SurfaceBoundaryMatchSide,
        referenceDirection: SurfaceBoundaryReferenceDirection,
        owner: String
    ) throws -> BSplineSurfaceFeature {
        try target.validate()
        try reference.validate()
        try validateCompatibility(
            target: target.surface,
            targetSide: targetSide,
            reference: reference.surface,
            referenceSide: referenceSide,
            level: level,
            owner: owner
        )

        let resolvedReferenceDirection = try resolvedReferenceDirection(
            target: target.surface,
            targetSide: targetSide,
            reference: reference.surface,
            referenceSide: referenceSide,
            requestedDirection: referenceDirection,
            owner: owner
        )
        let resolvedSide: ResolvedMatchSide = level.requiresFirstDerivative
            ? try resolvedMatchSide(
                target: target.surface,
                targetSide: targetSide,
                reference: reference.surface,
                referenceSide: referenceSide,
                referenceDirection: resolvedReferenceDirection,
                requestedSide: matchSide
            )
            : .same

        let targetFirstDerivativeCoefficients = try level.requiresFirstDerivative
            ? firstInwardDerivativeCoefficients(
                side: targetSide,
                surface: target.surface,
                owner: owner
            )
            : nil
        let referenceFirstDerivativeCoefficients = try level.requiresFirstDerivative
            ? firstInwardDerivativeCoefficients(
                side: referenceSide,
                surface: reference.surface,
                owner: owner
            )
            : nil
        let targetSecondDerivativeCoefficients = try level.requiresSecondDerivative
            ? secondInwardDerivativeCoefficients(
                side: targetSide,
                surface: target.surface,
                owner: owner
            )
            : nil
        let referenceSecondDerivativeCoefficients = try level.requiresSecondDerivative
            ? secondInwardDerivativeCoefficients(
                side: referenceSide,
                surface: reference.surface,
                owner: owner
            )
            : nil

        var updatedFeature = target
        let boundaryCount = boundaryControlPointCount(for: targetSide, in: target.surface)
        for ordinal in 0..<boundaryCount {
            let referenceOrdinal = resolvedReferenceDirection == .reversed
                ? boundaryCount - 1 - ordinal
                : ordinal
            let referenceBoundary = homogeneousControlPoint(
                atBoundaryOrdinal: referenceOrdinal,
                inwardOffset: 0,
                side: referenceSide,
                surface: reference.surface
            )
            try setHomogeneousControlPoint(
                referenceBoundary,
                atBoundaryOrdinal: ordinal,
                inwardOffset: 0,
                side: targetSide,
                surface: &updatedFeature.surface,
                owner: owner
            )

            var targetFirstInward: HomogeneousControlPoint?
            if level.requiresFirstDerivative {
                guard let targetFirstDerivativeCoefficients,
                      let referenceFirstDerivativeCoefficients else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) G1 continuity requires resolved first derivative coefficients."
                    )
                }
                let referenceFirstInward = homogeneousControlPoint(
                    atBoundaryOrdinal: referenceOrdinal,
                    inwardOffset: 1,
                    side: referenceSide,
                    surface: reference.surface
                )
                let referenceFirstDerivative = referenceBoundary * referenceFirstDerivativeCoefficients.boundary
                    + referenceFirstInward * referenceFirstDerivativeCoefficients.firstInward
                let targetInward = try (
                    referenceFirstDerivative * resolvedSide.sign
                        - referenceBoundary * targetFirstDerivativeCoefficients.boundary
                ).divided(
                    by: targetFirstDerivativeCoefficients.firstInward,
                    owner: "\(owner) first derivative coefficient"
                )
                targetFirstInward = targetInward
                try setHomogeneousControlPoint(
                    targetInward,
                    atBoundaryOrdinal: ordinal,
                    inwardOffset: 1,
                    side: targetSide,
                    surface: &updatedFeature.surface,
                    owner: owner
                )
            }

            if level.requiresSecondDerivative {
                guard let targetFirstInward else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) G2 continuity requires a resolved first derivative row."
                    )
                }
                guard let targetSecondDerivativeCoefficients,
                      let referenceSecondDerivativeCoefficients else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) G2 continuity requires resolved second derivative coefficients."
                    )
                }
                let referenceFirstInward = homogeneousControlPoint(
                    atBoundaryOrdinal: referenceOrdinal,
                    inwardOffset: 1,
                    side: referenceSide,
                    surface: reference.surface
                )
                let referenceSecondInward = homogeneousControlPoint(
                    atBoundaryOrdinal: referenceOrdinal,
                    inwardOffset: 2,
                    side: referenceSide,
                    surface: reference.surface
                )
                let referenceSecondDerivative =
                    referenceBoundary * referenceSecondDerivativeCoefficients.boundary
                    + referenceFirstInward * referenceSecondDerivativeCoefficients.firstInward
                    + referenceSecondInward * referenceSecondDerivativeCoefficients.secondInward
                let targetSecondInward = try (
                    referenceSecondDerivative
                        - referenceBoundary * targetSecondDerivativeCoefficients.boundary
                        - targetFirstInward * targetSecondDerivativeCoefficients.firstInward
                ).divided(
                    by: targetSecondDerivativeCoefficients.secondInward,
                    owner: "\(owner) second derivative coefficient"
                )
                try setHomogeneousControlPoint(
                    targetSecondInward,
                    atBoundaryOrdinal: ordinal,
                    inwardOffset: 2,
                    side: targetSide,
                    surface: &updatedFeature.surface,
                    owner: owner
                )
            }
        }

        try updatedFeature.validate()
        return updatedFeature
    }

    private func validateCompatibility(
        target: BSplineSurface3D,
        targetSide: BSplineSurfaceBoundarySide,
        reference: BSplineSurface3D,
        referenceSide: BSplineSurfaceBoundarySide,
        level: SurfaceBoundaryContinuityLevel,
        owner: String
    ) throws {
        let targetBoundaryCount = boundaryControlPointCount(for: targetSide, in: target)
        let referenceBoundaryCount = boundaryControlPointCount(for: referenceSide, in: reference)
        guard targetBoundaryCount == referenceBoundaryCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires matching boundary control point counts."
            )
        }
        guard targetBoundaryCount >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires non-collapsed surface boundaries."
            )
        }
        guard isClampedBoundary(targetSide, in: target),
              isClampedBoundary(referenceSide, in: reference) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires clamped outer boundaries so control rows map to surface boundaries."
            )
        }

        let targetBasis = boundaryBasis(for: targetSide, in: target)
        let referenceBasis = boundaryBasis(for: referenceSide, in: reference)
        guard targetBasis.degree == referenceBasis.degree,
              knotVectorsMatch(targetBasis.knots, referenceBasis.knots) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires matching boundary degree and knot vectors."
            )
        }

        if level.requiresFirstDerivative {
            guard inwardControlPointCount(for: targetSide, in: target) >= 2,
                  inwardControlPointCount(for: referenceSide, in: reference) >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) G1 continuity requires at least two control rows across each boundary."
                )
            }
        }

        if level.requiresSecondDerivative {
            guard inwardControlPointCount(for: targetSide, in: target) >= 3,
                  inwardControlPointCount(for: referenceSide, in: reference) >= 3 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) G2 continuity requires at least three control rows across each boundary."
                )
            }
            guard inwardDegree(for: targetSide, in: target) >= 2,
                  inwardDegree(for: referenceSide, in: reference) >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) G2 continuity requires quadratic or higher degree across each boundary."
                )
            }
        }
    }

    private struct FirstDerivativeCoefficients {
        var boundary: Double
        var firstInward: Double
    }

    private struct SecondDerivativeCoefficients {
        var boundary: Double
        var firstInward: Double
        var secondInward: Double
    }

    private func resolvedReferenceDirection(
        target: BSplineSurface3D,
        targetSide: BSplineSurfaceBoundarySide,
        reference: BSplineSurface3D,
        referenceSide: BSplineSurfaceBoundarySide,
        requestedDirection: SurfaceBoundaryReferenceDirection,
        owner: String
    ) throws -> SurfaceBoundaryReferenceDirection {
        switch requestedDirection {
        case .forward, .reversed:
            return requestedDirection
        case .automatic:
            let targetFirst = point(atBoundaryOrdinal: 0, inwardOffset: 0, side: targetSide, surface: target)
            let targetLast = point(
                atBoundaryOrdinal: boundaryControlPointCount(for: targetSide, in: target) - 1,
                inwardOffset: 0,
                side: targetSide,
                surface: target
            )
            let referenceFirst = point(atBoundaryOrdinal: 0, inwardOffset: 0, side: referenceSide, surface: reference)
            let referenceLast = point(
                atBoundaryOrdinal: boundaryControlPointCount(for: referenceSide, in: reference) - 1,
                inwardOffset: 0,
                side: referenceSide,
                surface: reference
            )
            let forwardDistance = distance(targetFirst, referenceFirst) + distance(targetLast, referenceLast)
            let reversedDistance = distance(targetFirst, referenceLast) + distance(targetLast, referenceFirst)
            guard forwardDistance.isFinite, reversedDistance.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not infer finite boundary endpoint distances."
                )
            }
            return reversedDistance < forwardDistance ? .reversed : .forward
        }
    }

    private func resolvedMatchSide(
        target: BSplineSurface3D,
        targetSide: BSplineSurfaceBoundarySide,
        reference: BSplineSurface3D,
        referenceSide: BSplineSurfaceBoundarySide,
        referenceDirection: SurfaceBoundaryReferenceDirection,
        requestedSide: SurfaceBoundaryMatchSide
    ) throws -> ResolvedMatchSide {
        switch requestedSide {
        case .same:
            return .same
        case .opposite:
            return .opposite
        case .automatic:
            let sampleOrdinal = boundaryControlPointCount(for: targetSide, in: target) / 2
            let referenceOrdinal = referenceDirection == .reversed
                ? boundaryControlPointCount(for: referenceSide, in: reference) - 1 - sampleOrdinal
                : sampleOrdinal
            let targetBoundary = point(
                atBoundaryOrdinal: sampleOrdinal,
                inwardOffset: 0,
                side: targetSide,
                surface: target
            )
            let targetInward = point(
                atBoundaryOrdinal: sampleOrdinal,
                inwardOffset: 1,
                side: targetSide,
                surface: target
            ) - targetBoundary
            let referenceBoundary = point(
                atBoundaryOrdinal: referenceOrdinal,
                inwardOffset: 0,
                side: referenceSide,
                surface: reference
            )
            let referenceInward = point(
                atBoundaryOrdinal: referenceOrdinal,
                inwardOffset: 1,
                side: referenceSide,
                surface: reference
            ) - referenceBoundary
            return targetInward.dot(referenceInward) < 0.0 ? .opposite : .same
        }
    }

    private enum ResolvedMatchSide {
        case same
        case opposite

        var sign: Double {
            switch self {
            case .same:
                return 1.0
            case .opposite:
                return -1.0
            }
        }
    }

    private struct HomogeneousControlPoint {
        var point: Vector3D
        var weight: Double

        init(point: Point3D, weight: Double) {
            self.point = Vector3D(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight
            )
            self.weight = weight
        }

        init(point: Vector3D, weight: Double) {
            self.point = point
            self.weight = weight
        }

        func dehomogenized(owner: String) throws -> (point: Point3D, weight: Double) {
            guard weight.isFinite,
                  weight > Double.ulpOfOne,
                  point.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a non-positive or non-finite rational weight."
                )
            }
            let vector = point / weight
            guard vector.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a non-finite rational control point."
                )
            }
            return (
                Point3D(x: vector.x, y: vector.y, z: vector.z),
                weight
            )
        }

        func divided(by scalar: Double, owner: String) throws -> HomogeneousControlPoint {
            guard scalar.isFinite, abs(scalar) > Double.ulpOfOne else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) must be finite and non-zero."
                )
            }
            return HomogeneousControlPoint(point: point / scalar, weight: weight / scalar)
        }

        static func + (lhs: HomogeneousControlPoint, rhs: HomogeneousControlPoint)
            -> HomogeneousControlPoint {
            HomogeneousControlPoint(point: lhs.point + rhs.point, weight: lhs.weight + rhs.weight)
        }

        static func - (lhs: HomogeneousControlPoint, rhs: HomogeneousControlPoint)
            -> HomogeneousControlPoint {
            HomogeneousControlPoint(point: lhs.point - rhs.point, weight: lhs.weight - rhs.weight)
        }

        static func * (lhs: HomogeneousControlPoint, rhs: Double) -> HomogeneousControlPoint {
            HomogeneousControlPoint(point: lhs.point * rhs, weight: lhs.weight * rhs)
        }
    }

    private func boundaryBasis(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> (degree: Int, knots: [Double]) {
        switch side.boundaryDirection {
        case .u:
            return (surface.uDegree, surface.uKnots)
        case .v:
            return (surface.vDegree, surface.vKnots)
        }
    }

    private func inwardBasis(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> (degree: Int, knots: [Double]) {
        switch side.inwardDirection {
        case .u:
            return (surface.uDegree, surface.uKnots)
        case .v:
            return (surface.vDegree, surface.vKnots)
        }
    }

    private func inwardDegree(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> Int {
        switch side.inwardDirection {
        case .u:
            return surface.uDegree
        case .v:
            return surface.vDegree
        }
    }

    private func firstInwardDerivativeCoefficients(
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D,
        owner: String
    ) throws -> FirstDerivativeCoefficients {
        let profile = inwardKnotProfile(for: side, in: surface)
        let denominator = try positiveDifference(
            profile.knots[profile.degree + 1],
            profile.knots[1],
            owner: "\(owner) first derivative knot span"
        )
        let scale = Double(profile.degree) / denominator
        return FirstDerivativeCoefficients(
            boundary: -scale,
            firstInward: scale
        )
    }

    private func secondInwardDerivativeCoefficients(
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D,
        owner: String
    ) throws -> SecondDerivativeCoefficients {
        let profile = inwardKnotProfile(for: side, in: surface)
        guard profile.degree >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) G2 continuity requires quadratic or higher degree across each boundary."
            )
        }
        let firstDerivativeDenominator = try positiveDifference(
            profile.knots[profile.degree + 1],
            profile.knots[1],
            owner: "\(owner) first derivative knot span"
        )
        let secondDerivativeDenominator = try positiveDifference(
            profile.knots[profile.degree + 2],
            profile.knots[2],
            owner: "\(owner) second derivative knot span"
        )
        let derivativeCurveDenominator = try positiveDifference(
            profile.knots[profile.degree + 1],
            profile.knots[2],
            owner: "\(owner) derivative-curve knot span"
        )
        let firstScale = Double(profile.degree) / firstDerivativeDenominator
        let secondScale = Double(profile.degree) / secondDerivativeDenominator
        let derivativeCurveScale = Double(profile.degree - 1) / derivativeCurveDenominator
        return SecondDerivativeCoefficients(
            boundary: derivativeCurveScale * firstScale,
            firstInward: derivativeCurveScale * (-firstScale - secondScale),
            secondInward: derivativeCurveScale * secondScale
        )
    }

    private func positiveDifference(_ lhs: Double, _ rhs: Double, owner: String) throws -> Double {
        let value = lhs - rhs
        guard value.isFinite,
              value > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be positive."
            )
        }
        return value
    }

    private func inwardKnotProfile(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> (degree: Int, knots: [Double]) {
        let basis = inwardBasis(for: side, in: surface)
        guard side.usesReversedInwardParameter else {
            return basis
        }
        let lowerBound = basis.knots[basis.degree]
        let upperBound = basis.knots[basis.knots.count - basis.degree - 1]
        return (
            basis.degree,
            basis.knots.reversed().map { lowerBound + upperBound - $0 }
        )
    }

    private func isClampedBoundary(
        _ side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> Bool {
        let profile = inwardKnotProfile(for: side, in: surface)
        guard profile.knots.indices.contains(profile.degree + 1) else {
            return false
        }
        let boundaryValue = profile.knots[profile.degree]
        let multiplicity = profile.knots.reduce(0) { count, knot in
            abs(knot - boundaryValue) <= ModelingTolerance.standard.distance ? count + 1 : count
        }
        return multiplicity == profile.degree + 1
            && profile.knots[profile.degree + 1] > boundaryValue + ModelingTolerance.standard.distance
    }

    private func boundaryControlPointCount(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> Int {
        switch side.boundaryDirection {
        case .u:
            return surface.uControlPointCount
        case .v:
            return surface.vControlPointCount
        }
    }

    private func inwardControlPointCount(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> Int {
        switch side.inwardDirection {
        case .u:
            return surface.uControlPointCount
        case .v:
            return surface.vControlPointCount
        }
    }

    private func knotVectorsMatch(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= ModelingTolerance.standard.distance }
    }

    private func homogeneousControlPoint(
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D
    ) -> HomogeneousControlPoint {
        HomogeneousControlPoint(
            point: point(
                atBoundaryOrdinal: ordinal,
                inwardOffset: inwardOffset,
                side: side,
                surface: surface
            ),
            weight: weight(
                atBoundaryOrdinal: ordinal,
                inwardOffset: inwardOffset,
                side: side,
                surface: surface
            )
        )
    }

    private func point(
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D
    ) -> Point3D {
        switch side {
        case .vMin, .vMax:
            return surface.controlPoints[side.inwardIndex(offset: inwardOffset, in: surface)][ordinal]
        case .uMin, .uMax:
            return surface.controlPoints[ordinal][side.inwardIndex(offset: inwardOffset, in: surface)]
        }
    }

    private func setHomogeneousControlPoint(
        _ controlPoint: HomogeneousControlPoint,
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: inout BSplineSurface3D,
        owner: String
    ) throws {
        let dehomogenized = try controlPoint.dehomogenized(owner: owner)
        setPoint(
            dehomogenized.point,
            atBoundaryOrdinal: ordinal,
            inwardOffset: inwardOffset,
            side: side,
            surface: &surface
        )
        setWeight(
            dehomogenized.weight,
            atBoundaryOrdinal: ordinal,
            inwardOffset: inwardOffset,
            side: side,
            surface: &surface
        )
    }

    private func setPoint(
        _ point: Point3D,
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: inout BSplineSurface3D
    ) {
        switch side {
        case .vMin, .vMax:
            surface.controlPoints[side.inwardIndex(offset: inwardOffset, in: surface)][ordinal] = point
        case .uMin, .uMax:
            surface.controlPoints[ordinal][side.inwardIndex(offset: inwardOffset, in: surface)] = point
        }
    }

    private func weight(
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D
    ) -> Double {
        switch side {
        case .vMin, .vMax:
            return surface.weights[side.inwardIndex(offset: inwardOffset, in: surface)][ordinal]
        case .uMin, .uMax:
            return surface.weights[ordinal][side.inwardIndex(offset: inwardOffset, in: surface)]
        }
    }

    private func setWeight(
        _ weight: Double,
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: inout BSplineSurface3D
    ) {
        switch side {
        case .vMin, .vMax:
            surface.weights[side.inwardIndex(offset: inwardOffset, in: surface)][ordinal] = weight
        case .uMin, .uMax:
            surface.weights[ordinal][side.inwardIndex(offset: inwardOffset, in: surface)] = weight
        }
    }

    private func distance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        (lhs - rhs).length
    }
}

private extension SurfaceBoundaryContinuityLevel {
    var requiresFirstDerivative: Bool {
        switch self {
        case .g0:
            return false
        case .g1, .g2:
            return true
        }
    }

    var requiresSecondDerivative: Bool {
        switch self {
        case .g0, .g1:
            return false
        case .g2:
            return true
        }
    }
}
