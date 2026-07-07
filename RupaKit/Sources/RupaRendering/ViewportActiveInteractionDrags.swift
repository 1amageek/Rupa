struct ViewportActiveInteractionDrags: Equatable {
    private var activeDrag: ViewportActiveInteractionDragState?

    init(
        affordance: ViewportAffordanceDragState? = nil,
        sketchCurveHandle: ViewportSketchCurveHandleDragState? = nil,
        sketchDimension: ViewportSketchDimensionDragState? = nil,
        sketchPointHandle: ViewportSketchPointHandleDragState? = nil,
        bridgeCurveEndpoint: ViewportBridgeCurveEndpointDragState? = nil,
        splineControlPoint: ViewportSplineControlPointDragState? = nil,
        splineControlPointSlide: ViewportSplineControlPointSlideDragState? = nil,
        polySplineSurfaceVertex: ViewportPolySplineSurfaceVertexDragState? = nil,
        surfaceControlPoint: ViewportSurfaceControlPointDragState? = nil,
        surfaceTrimEndpoint: ViewportSurfaceTrimEndpointDragState? = nil,
        surfaceTrimControlPoint: ViewportSurfaceTrimControlPointDragState? = nil,
        polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? = nil,
        surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? = nil,
        surfaceFrame: ViewportSurfaceFrameDragState? = nil,
        regionOffset: ViewportRegionOffsetDragState? = nil,
        edgeOffset: ViewportEdgeOffsetDragState? = nil,
        slotWidth: ViewportSlotWidthDragState? = nil,
        sketchVertexOffset: ViewportSketchVertexOffsetDragState? = nil,
        patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? = nil,
        independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? = nil,
        independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? = nil,
        patternArrayRadialAngle: ViewportPatternArrayRadialAngleDragState? = nil,
        patternArrayCopyCount: ViewportPatternArrayCopyCountDragState? = nil,
        patternArrayCurveExtent: ViewportPatternArrayCurveExtentDragState? = nil,
        patternArrayCurvePathPoint: ViewportPatternArrayCurvePathPointDragState? = nil,
        constructionPlane: ViewportConstructionPlaneHandleDragState? = nil
    ) {
        activeDrag = [
            sketchCurveHandle.map(ViewportActiveInteractionDragState.sketchCurveHandle),
            sketchDimension.map(ViewportActiveInteractionDragState.sketchDimension),
            sketchPointHandle.map(ViewportActiveInteractionDragState.sketchPointHandle),
            bridgeCurveEndpoint.map(ViewportActiveInteractionDragState.bridgeCurveEndpoint),
            splineControlPointSlide.map(ViewportActiveInteractionDragState.splineControlPointSlide),
            polySplineSurfaceVertexSlide.map(ViewportActiveInteractionDragState.polySplineSurfaceVertexSlide),
            surfaceControlPointSlide.map(ViewportActiveInteractionDragState.surfaceControlPointSlide),
            surfaceFrame.map(ViewportActiveInteractionDragState.surfaceFrame),
            splineControlPoint.map(ViewportActiveInteractionDragState.splineControlPoint),
            polySplineSurfaceVertex.map(ViewportActiveInteractionDragState.polySplineSurfaceVertex),
            surfaceControlPoint.map(ViewportActiveInteractionDragState.surfaceControlPoint),
            surfaceTrimEndpoint.map(ViewportActiveInteractionDragState.surfaceTrimEndpoint),
            surfaceTrimControlPoint.map(ViewportActiveInteractionDragState.surfaceTrimControlPoint),
            edgeOffset.map(ViewportActiveInteractionDragState.edgeOffset),
            slotWidth.map(ViewportActiveInteractionDragState.slotWidth),
            independentCopyExtrudeDistance.map(ViewportActiveInteractionDragState.independentCopyExtrudeDistance),
            independentCopyBodyDimension.map(ViewportActiveInteractionDragState.independentCopyBodyDimension),
            patternArrayLinearAxis.map(ViewportActiveInteractionDragState.patternArrayLinearAxis),
            patternArrayRadialAngle.map(ViewportActiveInteractionDragState.patternArrayRadialAngle),
            patternArrayCopyCount.map(ViewportActiveInteractionDragState.patternArrayCopyCount),
            patternArrayCurveExtent.map(ViewportActiveInteractionDragState.patternArrayCurveExtent),
            patternArrayCurvePathPoint.map(ViewportActiveInteractionDragState.patternArrayCurvePathPoint),
            constructionPlane.map(ViewportActiveInteractionDragState.constructionPlane),
            sketchVertexOffset.map(ViewportActiveInteractionDragState.sketchVertexOffset),
            regionOffset.map(ViewportActiveInteractionDragState.regionOffset),
            affordance.map(ViewportActiveInteractionDragState.affordance),
        ].compactMap { $0 }.first
    }

    var affordance: ViewportAffordanceDragState? {
        get { activeDrag?.affordance }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.affordance) }
    }

    var sketchCurveHandle: ViewportSketchCurveHandleDragState? {
        get { activeDrag?.sketchCurveHandle }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.sketchCurveHandle) }
    }

    var sketchDimension: ViewportSketchDimensionDragState? {
        get { activeDrag?.sketchDimension }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.sketchDimension) }
    }

    var sketchPointHandle: ViewportSketchPointHandleDragState? {
        get { activeDrag?.sketchPointHandle }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.sketchPointHandle) }
    }

    var bridgeCurveEndpoint: ViewportBridgeCurveEndpointDragState? {
        get { activeDrag?.bridgeCurveEndpoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.bridgeCurveEndpoint) }
    }

    var splineControlPoint: ViewportSplineControlPointDragState? {
        get { activeDrag?.splineControlPoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.splineControlPoint) }
    }

    var splineControlPointSlide: ViewportSplineControlPointSlideDragState? {
        get { activeDrag?.splineControlPointSlide }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.splineControlPointSlide) }
    }

    var polySplineSurfaceVertex: ViewportPolySplineSurfaceVertexDragState? {
        get { activeDrag?.polySplineSurfaceVertex }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.polySplineSurfaceVertex) }
    }

    var surfaceControlPoint: ViewportSurfaceControlPointDragState? {
        get { activeDrag?.surfaceControlPoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.surfaceControlPoint) }
    }

    var surfaceTrimEndpoint: ViewportSurfaceTrimEndpointDragState? {
        get { activeDrag?.surfaceTrimEndpoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.surfaceTrimEndpoint) }
    }

    var surfaceTrimControlPoint: ViewportSurfaceTrimControlPointDragState? {
        get { activeDrag?.surfaceTrimControlPoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.surfaceTrimControlPoint) }
    }

    var polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? {
        get { activeDrag?.polySplineSurfaceVertexSlide }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.polySplineSurfaceVertexSlide) }
    }

    var surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? {
        get { activeDrag?.surfaceControlPointSlide }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.surfaceControlPointSlide) }
    }

    var surfaceFrame: ViewportSurfaceFrameDragState? {
        get { activeDrag?.surfaceFrame }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.surfaceFrame) }
    }

    var regionOffset: ViewportRegionOffsetDragState? {
        get { activeDrag?.regionOffset }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.regionOffset) }
    }

    var edgeOffset: ViewportEdgeOffsetDragState? {
        get { activeDrag?.edgeOffset }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.edgeOffset) }
    }

    var slotWidth: ViewportSlotWidthDragState? {
        get { activeDrag?.slotWidth }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.slotWidth) }
    }

    var sketchVertexOffset: ViewportSketchVertexOffsetDragState? {
        get { activeDrag?.sketchVertexOffset }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.sketchVertexOffset) }
    }

    var patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? {
        get { activeDrag?.patternArrayLinearAxis }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.patternArrayLinearAxis) }
    }

    var independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? {
        get { activeDrag?.independentCopyExtrudeDistance }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.independentCopyExtrudeDistance) }
    }

    var independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? {
        get { activeDrag?.independentCopyBodyDimension }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.independentCopyBodyDimension) }
    }

    var patternArrayRadialAngle: ViewportPatternArrayRadialAngleDragState? {
        get { activeDrag?.patternArrayRadialAngle }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.patternArrayRadialAngle) }
    }

    var patternArrayCopyCount: ViewportPatternArrayCopyCountDragState? {
        get { activeDrag?.patternArrayCopyCount }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.patternArrayCopyCount) }
    }

    var patternArrayCurveExtent: ViewportPatternArrayCurveExtentDragState? {
        get { activeDrag?.patternArrayCurveExtent }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.patternArrayCurveExtent) }
    }

    var patternArrayCurvePathPoint: ViewportPatternArrayCurvePathPointDragState? {
        get { activeDrag?.patternArrayCurvePathPoint }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.patternArrayCurvePathPoint) }
    }

    var constructionPlane: ViewportConstructionPlaneHandleDragState? {
        get { activeDrag?.constructionPlane }
        set { activeDrag = newValue.map(ViewportActiveInteractionDragState.constructionPlane) }
    }

    var hasActiveDrag: Bool {
        activeDrag != nil
    }

    var nextFinishKind: ViewportActiveInteractionDragKind? {
        activeDrag?.kind
    }

    mutating func clear(except preservedTarget: ViewportInteractionTarget? = nil) {
        if activeDrag?.interactionTarget != preservedTarget {
            activeDrag = nil
        }
    }
}
