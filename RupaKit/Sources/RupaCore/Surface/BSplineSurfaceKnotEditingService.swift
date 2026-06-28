import SwiftCAD
import RupaCoreTypes

struct BSplineSurfaceKnotEditingService: Sendable {
    func updatedFeature(
        insertingKnot direction: SurfaceParameterDirection,
        value: Double,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> BSplineSurfaceFeature {
        guard value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a finite knot value."
            )
        }
        var updatedFeature = feature
        do {
            updatedFeature.surface = try feature.surface.insertingKnot(
                direction: direction,
                value: value
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) could not insert the B-spline surface knot: \(error)."
            )
        }
        try updatedFeature.validate()
        return updatedFeature
    }

    func updatedFeature(
        settingValue value: Double,
        for reference: SurfaceKnotReference,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> BSplineSurfaceFeature {
        guard value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a finite knot value."
            )
        }

        var updatedFeature = feature
        switch reference.direction {
        case .u:
            updatedFeature.surface.uKnots = try updatedKnots(
                feature.surface.uKnots,
                degree: feature.surface.uDegree,
                index: reference.knotIndex,
                value: value,
                owner: owner
            )
        case .v:
            updatedFeature.surface.vKnots = try updatedKnots(
                feature.surface.vKnots,
                degree: feature.surface.vDegree,
                index: reference.knotIndex,
                value: value,
                owner: owner
            )
        }
        try updatedFeature.validate()
        return updatedFeature
    }

    private func updatedKnots(
        _ knots: [Double],
        degree: Int,
        index: Int,
        value: Double,
        owner: String
    ) throws -> [Double] {
        guard knots.indices.contains(index) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface knot."
            )
        }
        let firstInteriorKnotIndex = degree + 1
        let lastInteriorKnotIndex = knots.count - degree - 2
        guard firstInteriorKnotIndex <= lastInteriorKnotIndex,
              (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(index) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can edit only interior B-spline surface knots."
            )
        }
        let lowerBound = knots[index - 1]
        let upperBound = knots[index + 1]
        guard value > lowerBound, value < upperBound else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must keep the knot value strictly between neighboring knots."
            )
        }
        var updatedKnots = knots
        updatedKnots[index] = value
        return updatedKnots
    }
}
