import Foundation
import SwiftCAD

public extension ModelingTolerance {
    static func recommended(
        forVisibleSpanMeters visibleSpanMeters: Double
    ) -> ModelingTolerance {
        let distance = clampedRecommendedDistanceTolerance(
            visibleSpanMeters * 1.0e-9
        )
        return ModelingTolerance(
            distance: distance,
            angle: Self.standard.angle
        )
    }

    private static func clampedRecommendedDistanceTolerance(_ value: Double) -> Double {
        guard value.isFinite else {
            return Self.standard.distance
        }
        return min(max(value, 1.0e-8), 1.0e-3)
    }
}
