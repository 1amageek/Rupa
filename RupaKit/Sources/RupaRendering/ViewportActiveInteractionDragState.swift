enum ViewportActiveInteractionDragState: Equatable {
    case sketchCurveHandle(ViewportSketchCurveHandleDragState)
    case sketchDimension(ViewportSketchDimensionDragState)
    case sketchPointHandle(ViewportSketchPointHandleDragState)
    case bridgeCurveEndpoint(ViewportBridgeCurveEndpointDragState)
    case splineControlPointSlide(ViewportSplineControlPointSlideDragState)
    case polySplineSurfaceVertexSlide(ViewportPolySplineSurfaceVertexSlideDragState)
    case surfaceControlPointSlide(ViewportSurfaceControlPointSlideDragState)
    case surfaceFrame(ViewportSurfaceFrameDragState)
    case splineControlPoint(ViewportSplineControlPointDragState)
    case polySplineSurfaceVertex(ViewportPolySplineSurfaceVertexDragState)
    case surfaceControlPoint(ViewportSurfaceControlPointDragState)
    case surfaceTrimEndpoint(ViewportSurfaceTrimEndpointDragState)
    case surfaceTrimControlPoint(ViewportSurfaceTrimControlPointDragState)
    case edgeOffset(ViewportEdgeOffsetDragState)
    case slotWidth(ViewportSlotWidthDragState)
    case independentCopyExtrudeDistance(ViewportIndependentCopyExtrudeDistanceDragState)
    case independentCopyBodyDimension(ViewportIndependentCopyBodyDimensionDragState)
    case patternArrayLinearAxis(ViewportPatternArrayLinearAxisDragState)
    case patternArrayRadialAngle(ViewportPatternArrayRadialAngleDragState)
    case patternArrayCopyCount(ViewportPatternArrayCopyCountDragState)
    case patternArrayCurveExtent(ViewportPatternArrayCurveExtentDragState)
    case patternArrayCurvePathPoint(ViewportPatternArrayCurvePathPointDragState)
    case constructionPlane(ViewportConstructionPlaneHandleDragState)
    case sketchVertexOffset(ViewportSketchVertexOffsetDragState)
    case regionOffset(ViewportRegionOffsetDragState)
    case affordance(ViewportAffordanceDragState)

    var kind: ViewportActiveInteractionDragKind {
        switch self {
        case .sketchCurveHandle:
            .sketchCurveHandle
        case .sketchDimension:
            .sketchDimension
        case .sketchPointHandle:
            .sketchPointHandle
        case .bridgeCurveEndpoint:
            .bridgeCurveEndpoint
        case .splineControlPointSlide:
            .splineControlPointSlide
        case .polySplineSurfaceVertexSlide:
            .polySplineSurfaceVertexSlide
        case .surfaceControlPointSlide:
            .surfaceControlPointSlide
        case .surfaceFrame:
            .surfaceFrame
        case .splineControlPoint:
            .splineControlPoint
        case .polySplineSurfaceVertex:
            .polySplineSurfaceVertex
        case .surfaceControlPoint:
            .surfaceControlPoint
        case .surfaceTrimEndpoint:
            .surfaceTrimEndpoint
        case .surfaceTrimControlPoint:
            .surfaceTrimControlPoint
        case .edgeOffset:
            .edgeOffset
        case .slotWidth:
            .slotWidth
        case .independentCopyExtrudeDistance:
            .independentCopyExtrudeDistance
        case .independentCopyBodyDimension:
            .independentCopyBodyDimension
        case .patternArrayLinearAxis:
            .patternArrayLinearAxis
        case .patternArrayRadialAngle:
            .patternArrayRadialAngle
        case .patternArrayCopyCount:
            .patternArrayCopyCount
        case .patternArrayCurveExtent:
            .patternArrayCurveExtent
        case .patternArrayCurvePathPoint:
            .patternArrayCurvePathPoint
        case .constructionPlane:
            .constructionPlane
        case .sketchVertexOffset:
            .sketchVertexOffset
        case .regionOffset:
            .regionOffset
        case .affordance:
            .affordance
        }
    }

    var interactionTarget: ViewportInteractionTarget {
        switch self {
        case .sketchCurveHandle(let state):
            .sketchCurveHandle(state.target)
        case .sketchDimension(let state):
            .sketchDimension(state.target)
        case .sketchPointHandle(let state):
            .sketchPointHandle(state.target)
        case .bridgeCurveEndpoint(let state):
            .bridgeCurveEndpoint(state.target)
        case .splineControlPointSlide(let state):
            .splineControlPointSlide(state.target)
        case .polySplineSurfaceVertexSlide(let state):
            .polySplineSurfaceVertexSlide(state.target)
        case .surfaceControlPointSlide(let state):
            .surfaceControlPointSlide(state.target)
        case .surfaceFrame(let state):
            .surfaceFrame(state.target)
        case .splineControlPoint(let state):
            .splineControlPoint(state.target)
        case .polySplineSurfaceVertex(let state):
            .polySplineSurfaceVertex(state.target)
        case .surfaceControlPoint(let state):
            .surfaceControlPoint(state.target)
        case .surfaceTrimEndpoint(let state):
            .surfaceTrimEndpoint(state.target)
        case .surfaceTrimControlPoint(let state):
            .surfaceTrimControlPoint(state.target)
        case .edgeOffset(let state):
            .edgeOffset(state.target)
        case .slotWidth(let state):
            .slotWidth(state.target)
        case .independentCopyExtrudeDistance(let state):
            .independentCopyExtrudeDistance(state.target)
        case .independentCopyBodyDimension(let state):
            .independentCopyBodyDimension(state.target)
        case .patternArrayLinearAxis(let state):
            .patternArrayLinearAxis(state.target)
        case .patternArrayRadialAngle(let state):
            .patternArrayRadialAngle(state.target)
        case .patternArrayCopyCount(let state):
            .patternArrayCopyCount(state.target)
        case .patternArrayCurveExtent(let state):
            .patternArrayCurveExtent(state.target)
        case .patternArrayCurvePathPoint(let state):
            .patternArrayCurvePathPoint(state.target)
        case .constructionPlane(let state):
            .constructionPlane(state.target)
        case .sketchVertexOffset(let state):
            .sketchVertexOffset(state.target)
        case .regionOffset(let state):
            .regionOffset(state.target)
        case .affordance(let state):
            .affordance(state.target)
        }
    }

    var sketchCurveHandle: ViewportSketchCurveHandleDragState? {
        if case .sketchCurveHandle(let state) = self { state } else { nil }
    }

    var sketchDimension: ViewportSketchDimensionDragState? {
        if case .sketchDimension(let state) = self { state } else { nil }
    }

    var sketchPointHandle: ViewportSketchPointHandleDragState? {
        if case .sketchPointHandle(let state) = self { state } else { nil }
    }

    var bridgeCurveEndpoint: ViewportBridgeCurveEndpointDragState? {
        if case .bridgeCurveEndpoint(let state) = self { state } else { nil }
    }

    var splineControlPointSlide: ViewportSplineControlPointSlideDragState? {
        if case .splineControlPointSlide(let state) = self { state } else { nil }
    }

    var polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? {
        if case .polySplineSurfaceVertexSlide(let state) = self { state } else { nil }
    }

    var surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? {
        if case .surfaceControlPointSlide(let state) = self { state } else { nil }
    }

    var surfaceFrame: ViewportSurfaceFrameDragState? {
        if case .surfaceFrame(let state) = self { state } else { nil }
    }

    var splineControlPoint: ViewportSplineControlPointDragState? {
        if case .splineControlPoint(let state) = self { state } else { nil }
    }

    var polySplineSurfaceVertex: ViewportPolySplineSurfaceVertexDragState? {
        if case .polySplineSurfaceVertex(let state) = self { state } else { nil }
    }

    var surfaceControlPoint: ViewportSurfaceControlPointDragState? {
        if case .surfaceControlPoint(let state) = self { state } else { nil }
    }

    var surfaceTrimEndpoint: ViewportSurfaceTrimEndpointDragState? {
        if case .surfaceTrimEndpoint(let state) = self { state } else { nil }
    }

    var surfaceTrimControlPoint: ViewportSurfaceTrimControlPointDragState? {
        if case .surfaceTrimControlPoint(let state) = self { state } else { nil }
    }

    var edgeOffset: ViewportEdgeOffsetDragState? {
        if case .edgeOffset(let state) = self { state } else { nil }
    }

    var slotWidth: ViewportSlotWidthDragState? {
        if case .slotWidth(let state) = self { state } else { nil }
    }

    var independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? {
        if case .independentCopyExtrudeDistance(let state) = self { state } else { nil }
    }

    var independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? {
        if case .independentCopyBodyDimension(let state) = self { state } else { nil }
    }

    var patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? {
        if case .patternArrayLinearAxis(let state) = self { state } else { nil }
    }

    var patternArrayRadialAngle: ViewportPatternArrayRadialAngleDragState? {
        if case .patternArrayRadialAngle(let state) = self { state } else { nil }
    }

    var patternArrayCopyCount: ViewportPatternArrayCopyCountDragState? {
        if case .patternArrayCopyCount(let state) = self { state } else { nil }
    }

    var patternArrayCurveExtent: ViewportPatternArrayCurveExtentDragState? {
        if case .patternArrayCurveExtent(let state) = self { state } else { nil }
    }

    var patternArrayCurvePathPoint: ViewportPatternArrayCurvePathPointDragState? {
        if case .patternArrayCurvePathPoint(let state) = self { state } else { nil }
    }

    var constructionPlane: ViewportConstructionPlaneHandleDragState? {
        if case .constructionPlane(let state) = self { state } else { nil }
    }

    var sketchVertexOffset: ViewportSketchVertexOffsetDragState? {
        if case .sketchVertexOffset(let state) = self { state } else { nil }
    }

    var regionOffset: ViewportRegionOffsetDragState? {
        if case .regionOffset(let state) = self { state } else { nil }
    }

    var affordance: ViewportAffordanceDragState? {
        if case .affordance(let state) = self { state } else { nil }
    }
}
