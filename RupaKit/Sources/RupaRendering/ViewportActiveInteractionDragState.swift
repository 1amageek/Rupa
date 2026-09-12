enum ViewportActiveInteractionDragState: Equatable {
    case sketchCurveHandle(ViewportSketchCurveHandleDragState)
    case sketchDimension(ViewportSketchDimensionDragState)
    case sketchPointHandle(ViewportSketchPointHandleDragState)
    case splineControlPointSlide(ViewportSplineControlPointSlideDragState)
    case polySplineSurfaceVertexSlide(ViewportPolySplineSurfaceVertexSlideDragState)
    case surfaceControlPointSlide(ViewportSurfaceControlPointSlideDragState)
    case surfaceFrame(ViewportSurfaceFrameDragState)
    case splineControlPoint(ViewportSplineControlPointDragState)
    case edgeOffset(ViewportEdgeOffsetDragState)
    case slotWidth(ViewportSlotWidthDragState)
    case independentCopyExtrudeDistance(ViewportIndependentCopyExtrudeDistanceDragState)
    case independentCopyBodyDimension(ViewportIndependentCopyBodyDimensionDragState)
    case patternArrayLinearAxis(ViewportPatternArrayLinearAxisDragState)
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
