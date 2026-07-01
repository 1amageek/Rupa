import Foundation
import RupaCoreTypes

public struct WorkspaceScaleDefaults: Equatable, Sendable {
    public static let standard = WorkspaceScaleDefaults(ruler: .standard(for: .millimeter))

    public let baseFeatureMeters: Double
    public let sketchWidthMeters: Double
    public let sketchHeightMeters: Double
    public let sketchDepthMeters: Double
    public let cylinderDepthMeters: Double
    public let placedRectangleWidthMeters: Double
    public let placedRectangleHeightMeters: Double
    public let placedSolidSideMeters: Double
    public let curveRadiusMeters: Double
    public let splineHalfWidthMeters: Double
    public let splineBowMeters: Double
    public let maximumSplineBowMeters: Double

    public init(ruler: RulerConfiguration) {
        let normalizedRuler = ruler.normalizedForWorkspaceScale()
        let baseFeatureMeters = Self.baseFeatureMeters(for: normalizedRuler)
        self.baseFeatureMeters = baseFeatureMeters
        self.sketchWidthMeters = baseFeatureMeters
        self.sketchHeightMeters = baseFeatureMeters * 0.5
        self.sketchDepthMeters = baseFeatureMeters * 0.25
        self.cylinderDepthMeters = baseFeatureMeters * 0.5
        self.placedRectangleWidthMeters = baseFeatureMeters
        self.placedRectangleHeightMeters = baseFeatureMeters
        self.placedSolidSideMeters = baseFeatureMeters
        self.curveRadiusMeters = baseFeatureMeters * 0.3
        self.splineHalfWidthMeters = baseFeatureMeters * 0.5
        self.splineBowMeters = baseFeatureMeters * 0.3
        self.maximumSplineBowMeters = baseFeatureMeters * 0.6
    }

    private static func baseFeatureMeters(for ruler: RulerConfiguration) -> Double {
        let unitScaleMeters = ruler.displayUnit.meters(from: 40.0)
        let gridScaleMeters = ruler.majorTickMeters * 4.0
        let spanScaleMeters = ruler.visibleSpanMeters * 0.04
        let fitLimitMeters = max(
            ruler.visibleSpanMeters * 0.25,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        let candidateMeters = max(unitScaleMeters, gridScaleMeters, spanScaleMeters)
        return min(candidateMeters, fitLimitMeters)
    }
}

public extension DesignDocument {
    var workspaceScaleDefaults: WorkspaceScaleDefaults {
        WorkspaceScaleDefaults(ruler: ruler)
    }
}
