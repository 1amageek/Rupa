import Foundation
import RupaCore
import SwiftCAD

/// Validates profile regions derived from exact constraint source geometry.
enum CADConstraintDerivedRegionOracle {
    static func validate(
        source: SketchEntitySnapshot,
        expected: CADConstraintChallengeInput,
        expectedPlane: SketchPlane,
        sourceFeatureID: String,
        sceneNodeID: String?,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        switch expected.relation {
        case .concentric:
            try validateConcentricAnnulus(
                source: source,
                expected: expected,
                expectedPlane: expectedPlane,
                sourceFeatureID: sourceFeatureID,
                sceneNodeID: sceneNodeID,
                tolerance: tolerance
            )
        case .equalRadius:
            try validateEqualRadiusDisks(
                source: source,
                expected: expected,
                expectedPlane: expectedPlane,
                sourceFeatureID: sourceFeatureID,
                sceneNodeID: sceneNodeID,
                tolerance: tolerance
            )
        default:
            guard source.counts.regionCount == 0, source.regions.isEmpty else {
                throw mismatch("A non-circular constraint produced unexpected derived regions.")
            }
        }
    }

    private static func validateEqualRadiusDisks(
        source: SketchEntitySnapshot,
        expected: CADConstraintChallengeInput,
        expectedPlane: SketchPlane,
        sourceFeatureID: String,
        sceneNodeID: String?,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        guard case .circle(let first) = expected.first,
              let secondGeometry = expected.second,
              case .circle(let second) = secondGeometry else {
            throw mismatch("An equal-radius expectation requires two circles.")
        }
        guard let sourceFeatureUUID = UUID(uuidString: sourceFeatureID) else {
            throw mismatch("The derived equal-radius disks have a malformed source feature identifier.")
        }
        let firstWorldCenter = first.center.meters
        let secondWorldCenter = second.center.meters
        let localCenters = [
            Point2D(x: 0.0, y: 0.0),
            Point2D(
                x: secondWorldCenter.x - firstWorldCenter.x,
                y: secondWorldCenter.y - firstWorldCenter.y
            ),
        ]
        let circles = [first, second]
        guard source.counts.regionCount == circles.count,
              source.regions.count == circles.count else {
            throw mismatch("The equal-radius source must produce exactly two disk regions.")
        }
        for index in circles.indices {
            let circle = circles[index]
            let center = localCenters[index]
            let region = source.regions[index]
            let expectedSelectionComponentID = SelectionComponentID.profileRegion(
                featureID: FeatureID(sourceFeatureUUID),
                profileIndex: index
            ).rawValue
            guard region.sourceFeatureID == sourceFeatureID,
                  region.sceneNodeID == sceneNodeID,
                  region.profileIndex == index,
                  region.selectionComponentID == expectedSelectionComponentID,
                  region.plane == expectedPlane,
                  tolerance.acceptsLinear(expected: center.x, observed: region.center.x),
                  tolerance.acceptsLinear(expected: center.y, observed: region.center.y),
                  acceptsDiskArea(
                      observed: region.areaSquareMeters,
                      radius: circle.radius.meters,
                      tolerance: tolerance.modelingTolerance
                  ),
                  region.boundarySegmentCount == 1,
                  region.boundaryPointCount == region.boundaryPoints.count,
                  region.boundaryPointCount >= 3,
                  region.boundaryPoints.allSatisfy({ point in
                      tolerance.acceptsLinear(
                          expected: circle.radius.meters,
                          observed: hypot(point.x - center.x, point.y - center.y)
                      )
                  }) else {
                throw mismatch("A derived equal-radius disk has incorrect source, order, selection, plane, center, area, or boundary evidence.")
            }
        }
    }

    private static func validateConcentricAnnulus(
        source: SketchEntitySnapshot,
        expected: CADConstraintChallengeInput,
        expectedPlane: SketchPlane,
        sourceFeatureID: String,
        sceneNodeID: String?,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        guard case .circle(let first) = expected.first,
              let secondGeometry = expected.second,
              case .circle(let second) = secondGeometry else {
            throw mismatch("A concentric expectation requires two circles.")
        }
        guard first.center.meters == second.center.meters else {
            throw mismatch("A concentric annulus expectation requires one shared center.")
        }
        let outerRadius = max(first.radius.meters, second.radius.meters)
        let innerRadius = min(first.radius.meters, second.radius.meters)
        let expectedArea = Double.pi * (
            outerRadius * outerRadius - innerRadius * innerRadius
        )
        guard let sourceFeatureUUID = UUID(uuidString: sourceFeatureID) else {
            throw mismatch("The derived concentric annulus has a malformed source feature identifier.")
        }
        let expectedSelectionComponentID = SelectionComponentID.profileRegion(
            featureID: FeatureID(sourceFeatureUUID),
            profileIndex: 0
        ).rawValue
        guard source.counts.regionCount == 1,
              source.regions.count == 1,
              let region = source.regions.first,
              region.sourceFeatureID == sourceFeatureID,
              region.sceneNodeID == sceneNodeID,
              region.profileIndex == 0,
              region.selectionComponentID == expectedSelectionComponentID,
              region.plane == expectedPlane,
              abs(region.center.x) <= tolerance.modelingTolerance.distance,
              abs(region.center.y) <= tolerance.modelingTolerance.distance,
              acceptsArea(
                  expected: expectedArea,
                  observed: region.areaSquareMeters,
                  outerRadius: outerRadius,
                  innerRadius: innerRadius,
                  tolerance: tolerance.modelingTolerance
              ),
              region.boundarySegmentCount == 1,
              region.boundaryPointCount == region.boundaryPoints.count,
              region.boundaryPointCount >= 3,
              region.boundaryPoints.allSatisfy({ point in
                  tolerance.acceptsLinear(
                      expected: outerRadius,
                      observed: hypot(point.x, point.y)
                  )
              }) else {
            throw mismatch("The derived concentric annulus is missing or has incorrect source, plane, center, area, or boundary evidence.")
        }
    }

    private static func acceptsArea(
        expected: Double,
        observed: Double,
        outerRadius: Double,
        innerRadius: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let outerBounds = acceptedRadiusBounds(expected: outerRadius, tolerance: tolerance)
        let innerBounds = acceptedRadiusBounds(expected: innerRadius, tolerance: tolerance)
        let minimumArea = Double.pi * max(
            0.0,
            outerBounds.lowerBound * outerBounds.lowerBound
                - innerBounds.upperBound * innerBounds.upperBound
        )
        let maximumArea = Double.pi * max(
            0.0,
            outerBounds.upperBound * outerBounds.upperBound
                - innerBounds.lowerBound * innerBounds.lowerBound
        )
        return observed >= minimumArea && observed <= maximumArea
    }

    private static func acceptsDiskArea(
        observed: Double,
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard observed.isFinite else { return false }
        let radiusBounds = acceptedRadiusBounds(expected: radius, tolerance: tolerance)
        let minimumArea = Double.pi * radiusBounds.lowerBound * radiusBounds.lowerBound
        let maximumArea = Double.pi * radiusBounds.upperBound * radiusBounds.upperBound
        return observed >= minimumArea && observed <= maximumArea
    }

    private static func acceptedRadiusBounds(
        expected: Double,
        tolerance: ModelingTolerance
    ) -> ClosedRange<Double> {
        let baseScale = max(1.0, abs(expected))
        let baseLimit = max(tolerance.distance, tolerance.relative * baseScale)
        let lowerBound = max(0.0, expected - baseLimit)

        var relativeUpperBound = expected + tolerance.relative * baseScale
        if tolerance.relative < 1.0 {
            let scaledUpperBound = expected / (1.0 - tolerance.relative)
            if scaledUpperBound >= baseScale {
                relativeUpperBound = max(relativeUpperBound, scaledUpperBound)
            }
        }
        let upperBound = max(expected + tolerance.distance, relativeUpperBound)
        return lowerBound...upperBound
    }

    private static func mismatch(_ reason: String) -> CADConstraintOracleError {
        .mismatch(reason)
    }
}
