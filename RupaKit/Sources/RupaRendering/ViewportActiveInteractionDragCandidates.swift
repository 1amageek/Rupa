struct ViewportActiveInteractionDragCandidates {
    var affordance: ViewportAffordanceDragState? = nil
    var sketchCurveHandle: ViewportSketchCurveHandleDragState? = nil
    var sketchDimension: ViewportSketchDimensionDragState? = nil
    var sketchPointHandle: ViewportSketchPointHandleDragState? = nil
    var bridgeCurveEndpoint: ViewportBridgeCurveEndpointDragState? = nil
    var splineControlPoint: ViewportSplineControlPointDragState? = nil
    var splineControlPointSlide: ViewportSplineControlPointSlideDragState? = nil
    var polySplineSurfaceVertex: ViewportPolySplineSurfaceVertexDragState? = nil
    var surfaceControlPoint: ViewportSurfaceControlPointDragState? = nil
    var surfaceTrimEndpoint: ViewportSurfaceTrimEndpointDragState? = nil
    var surfaceTrimControlPoint: ViewportSurfaceTrimControlPointDragState? = nil
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
    var patternArrayRadialAngle: ViewportPatternArrayRadialAngleDragState? = nil
    var patternArrayCopyCount: ViewportPatternArrayCopyCountDragState? = nil
    var patternArrayCurveExtent: ViewportPatternArrayCurveExtentDragState? = nil
    var patternArrayCurvePathPoint: ViewportPatternArrayCurvePathPointDragState? = nil
    var constructionPlane: ViewportConstructionPlaneHandleDragState? = nil

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
        case .bridgeCurveEndpoint:
            bridgeCurveEndpoint.map(ViewportActiveInteractionDragState.bridgeCurveEndpoint)
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
        case .polySplineSurfaceVertex:
            polySplineSurfaceVertex.map(ViewportActiveInteractionDragState.polySplineSurfaceVertex)
        case .surfaceControlPoint:
            surfaceControlPoint.map(ViewportActiveInteractionDragState.surfaceControlPoint)
        case .surfaceTrimEndpoint:
            surfaceTrimEndpoint.map(ViewportActiveInteractionDragState.surfaceTrimEndpoint)
        case .surfaceTrimControlPoint:
            surfaceTrimControlPoint.map(ViewportActiveInteractionDragState.surfaceTrimControlPoint)
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
        case .patternArrayRadialAngle:
            patternArrayRadialAngle.map(ViewportActiveInteractionDragState.patternArrayRadialAngle)
        case .patternArrayCopyCount:
            patternArrayCopyCount.map(ViewportActiveInteractionDragState.patternArrayCopyCount)
        case .patternArrayCurveExtent:
            patternArrayCurveExtent.map(ViewportActiveInteractionDragState.patternArrayCurveExtent)
        case .patternArrayCurvePathPoint:
            patternArrayCurvePathPoint.map(ViewportActiveInteractionDragState.patternArrayCurvePathPoint)
        case .constructionPlane:
            constructionPlane.map(ViewportActiveInteractionDragState.constructionPlane)
        case .sketchVertexOffset:
            sketchVertexOffset.map(ViewportActiveInteractionDragState.sketchVertexOffset)
        case .regionOffset:
            regionOffset.map(ViewportActiveInteractionDragState.regionOffset)
        case .affordance:
            affordance.map(ViewportActiveInteractionDragState.affordance)
        }
    }
}
