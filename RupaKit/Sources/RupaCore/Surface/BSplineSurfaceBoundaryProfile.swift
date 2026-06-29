import SwiftCAD

struct BSplineSurfaceBoundaryProfile: Equatable, Sendable {
    var side: BSplineSurfaceBoundarySide
    var boundaryDirection: SurfaceParameterDirection
    var inwardDirection: SurfaceParameterDirection
    var boundaryDegree: Int
    var boundaryKnots: [Double]
    var inwardDegree: Int
    var inwardKnotsFromBoundary: [Double]
    var boundaryControlPointCount: Int
    var inwardControlPointCount: Int
    var isClamped: Bool

    var supportedContinuityLevels: [SurfaceBoundaryContinuityLevel] {
        guard boundaryControlPointCount >= 2, isClamped else {
            return []
        }
        var levels: [SurfaceBoundaryContinuityLevel] = [.g0]
        if inwardControlPointCount >= 2 {
            levels.append(.g1)
        }
        if inwardControlPointCount >= 3, inwardDegree >= 2 {
            levels.append(.g2)
        }
        return levels
    }
}

struct BSplineSurfaceBoundaryProfileBuilder: Sendable {
    func profile(
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D
    ) -> BSplineSurfaceBoundaryProfile {
        let boundaryBasis = boundaryBasis(for: side, in: surface)
        let inwardProfile = inwardKnotProfile(for: side, in: surface)
        return BSplineSurfaceBoundaryProfile(
            side: side,
            boundaryDirection: side.boundaryDirection,
            inwardDirection: side.inwardDirection,
            boundaryDegree: boundaryBasis.degree,
            boundaryKnots: boundaryBasis.knots,
            inwardDegree: inwardProfile.degree,
            inwardKnotsFromBoundary: inwardProfile.knots,
            boundaryControlPointCount: boundaryControlPointCount(for: side, in: surface),
            inwardControlPointCount: inwardControlPointCount(for: side, in: surface),
            isClamped: isClampedBoundary(side, in: surface)
        )
    }

    func boundaryControlPointCount(
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

    func inwardControlPointCount(
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

    func inwardDegree(
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

    func isClampedBoundary(
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

    func knotVectorsMatch(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= ModelingTolerance.standard.distance }
    }

    func inwardKnotProfile(
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
}

extension SurfaceBoundaryContinuityLevel {
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
