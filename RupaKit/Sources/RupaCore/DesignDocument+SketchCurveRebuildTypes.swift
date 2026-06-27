import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct RebuiltSketchSpline {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var rebuiltControlPointCount: Int
        var originalSegmentCount: Int
        var rebuiltSegmentCount: Int
        var deviation: SketchSplineRebuildDeviation
        var controlPointIndexMap: [Int: Int]

        var changesControlPointCount: Bool {
            originalControlPointCount != rebuiltControlPointCount
        }
    }

    struct SketchSplineRebuildDeviation {
        var maximumDistance: Double
        var rootMeanSquareDistance: Double
        var maximumDistanceFraction: Double
        var evaluatedIntervalCount: Int
        var criticalPointCount: Int
    }

    struct SketchSplineRebuildSample {
        var point: CADCore.Point2D
        var derivative: CADCore.Point2D
    }

    enum SketchSplineRebuildSampleSide {
        case before
        case after
    }

    struct SketchSplineRebuildInterval {
        var startFraction: Double
        var endFraction: Double
        var segmentCount: Int
    }

    struct CubicBezierSegment2D {
        var p0: CADCore.Point2D
        var p1: CADCore.Point2D
        var p2: CADCore.Point2D
        var p3: CADCore.Point2D
    }

    struct CubicSplineSegmentLocation {
        var segmentIndex: Int
        var localFraction: Double
    }

    struct AnalyticCubicBezierDeviation {
        var maximumSquaredDistance: Double
        var maximumDistanceFraction: Double
        var squaredDistanceIntegral: Double
        var criticalPointCount: Int
    }
}
