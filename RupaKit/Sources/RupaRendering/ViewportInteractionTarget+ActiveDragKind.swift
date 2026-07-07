extension ViewportInteractionTarget {
    var activeDragKind: ViewportActiveInteractionDragKind? {
        switch self {
        case .sketchCurveHandle:
            .sketchCurveHandle
        case .sketchDimension:
            .sketchDimension
        case .sketchPointHandle:
            .sketchPointHandle
        case .bridgeCurveEndpoint:
            .bridgeCurveEndpoint
        case .splineControlPoint:
            .splineControlPoint
        case .splineControlPointSlide:
            .splineControlPointSlide
        case .polySplineSurfaceVertex:
            .polySplineSurfaceVertex
        case .polySplineSurfaceVertexSlide:
            .polySplineSurfaceVertexSlide
        case .surfaceControlPoint:
            .surfaceControlPoint
        case .surfaceControlPointSlide:
            .surfaceControlPointSlide
        case .surfaceTrimEndpoint:
            .surfaceTrimEndpoint
        case .surfaceTrimControlPoint:
            .surfaceTrimControlPoint
        case .surfaceFrame:
            .surfaceFrame
        case .regionOffset:
            .regionOffset
        case .edgeOffset:
            .edgeOffset
        case .slotWidth:
            .slotWidth
        case .sketchVertexOffset:
            .sketchVertexOffset
        case .patternArrayLinearAxis:
            .patternArrayLinearAxis
        case .independentCopyExtrudeDistance:
            .independentCopyExtrudeDistance
        case .independentCopyBodyDimension:
            .independentCopyBodyDimension
        case .patternArrayRadialAngle:
            .patternArrayRadialAngle
        case .patternArrayCopyCount:
            .patternArrayCopyCount
        case .patternArrayCurveExtent:
            .patternArrayCurveExtent
        case .patternArrayCurvePathPoint:
            .patternArrayCurvePathPoint
        case .patternArrayOutputMode:
            nil
        case .constructionPlane:
            .constructionPlane
        case .affordance:
            .affordance
        }
    }
}
