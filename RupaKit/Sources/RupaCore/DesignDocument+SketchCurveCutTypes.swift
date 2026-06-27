import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct CutCurveLineSegment {
        var startX: Double
        var startY: Double
        var endX: Double
        var endY: Double
    }

    struct CutCurveCircle {
        var centerX: Double
        var centerY: Double
        var radius: Double
    }

    struct CutCurveArc {
        var circle: CutCurveCircle
        var startAngle: Double
        var endAngle: Double
    }

    static let cutCurveSplineSamplesPerSegment = 64
    typealias CutCurveSplineSampleSegment = (
        start: CurveEvaluationSample,
        end: CurveEvaluationSample
    )
}
