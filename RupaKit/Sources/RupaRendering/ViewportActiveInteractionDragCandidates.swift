struct ViewportActiveInteractionDragCandidates {
    var affordance: ViewportAffordanceDragState? = nil
    var sketchCurveHandle: ViewportSketchCurveHandleDragState? = nil
    var sketchDimension: ViewportSketchDimensionDragState? = nil
    var sketchPointHandle: ViewportSketchPointHandleDragState? = nil
    var splineControlPoint: ViewportSplineControlPointDragState? = nil
    var splineControlPointSlide: ViewportSplineControlPointSlideDragState? = nil
    var polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? = nil
    var surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? = nil
    var surfaceFrame: ViewportSurfaceFrameDragState? = nil
    var regionOffset: ViewportRegionOffsetDragState? = nil
    var edgeOffset: ViewportEdgeOffsetDragState? = nil
    var slotWidth: ViewportSlotWidthDragState? = nil
    var sketchVertexOffset: ViewportSketchVertexOffsetDragState? = nil
    var patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? = nil
    var independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? = nil
    var independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? = nil

    var firstActiveDrag: ViewportActiveInteractionDragState? {
        ViewportActiveInteractionDragKind.finishPrecedence.compactMap(state(for:)).first
    }

    func state(for kind: ViewportActiveInteractionDragKind) -> ViewportActiveInteractionDragState? {
        switch kind {
        case .sketchCurveHandle:
            sketchCurveHandle.map(ViewportActiveInteractionDragState.sketchCurveHandle)
        case .sketchDimension:
            sketchDimension.map(ViewportActiveInteractionDragState.sketchDimension)
        case .sketchPointHandle:
            sketchPointHandle.map(ViewportActiveInteractionDragState.sketchPointHandle)
        case .splineControlPointSlide:
            splineControlPointSlide.map(ViewportActiveInteractionDragState.splineControlPointSlide)
        case .polySplineSurfaceVertexSlide:
            polySplineSurfaceVertexSlide.map(ViewportActiveInteractionDragState.polySplineSurfaceVertexSlide)
        case .surfaceControlPointSlide:
            surfaceControlPointSlide.map(ViewportActiveInteractionDragState.surfaceControlPointSlide)
        case .surfaceFrame:
            surfaceFrame.map(ViewportActiveInteractionDragState.surfaceFrame)
        case .splineControlPoint:
            splineControlPoint.map(ViewportActiveInteractionDragState.splineControlPoint)
        case .edgeOffset:
            edgeOffset.map(ViewportActiveInteractionDragState.edgeOffset)
        case .slotWidth:
            slotWidth.map(ViewportActiveInteractionDragState.slotWidth)
        case .independentCopyExtrudeDistance:
            independentCopyExtrudeDistance.map(ViewportActiveInteractionDragState.independentCopyExtrudeDistance)
        case .independentCopyBodyDimension:
            independentCopyBodyDimension.map(ViewportActiveInteractionDragState.independentCopyBodyDimension)
        case .patternArrayLinearAxis:
            patternArrayLinearAxis.map(ViewportActiveInteractionDragState.patternArrayLinearAxis)
        case .sketchVertexOffset:
            sketchVertexOffset.map(ViewportActiveInteractionDragState.sketchVertexOffset)
        case .regionOffset:
            regionOffset.map(ViewportActiveInteractionDragState.regionOffset)
        case .affordance:
            affordance.map(ViewportActiveInteractionDragState.affordance)
        }
    }
}
