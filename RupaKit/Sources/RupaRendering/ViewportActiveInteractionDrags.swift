struct ViewportActiveInteractionDrags: Equatable {
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

    var hasActiveDrag: Bool {
        affordance != nil
            || sketchCurveHandle != nil
            || sketchDimension != nil
            || sketchPointHandle != nil
            || bridgeCurveEndpoint != nil
            || splineControlPoint != nil
            || splineControlPointSlide != nil
            || polySplineSurfaceVertex != nil
            || surfaceControlPoint != nil
            || surfaceTrimEndpoint != nil
            || surfaceTrimControlPoint != nil
            || polySplineSurfaceVertexSlide != nil
            || surfaceControlPointSlide != nil
            || surfaceFrame != nil
            || regionOffset != nil
            || edgeOffset != nil
            || slotWidth != nil
            || sketchVertexOffset != nil
            || patternArrayLinearAxis != nil
            || independentCopyExtrudeDistance != nil
            || independentCopyBodyDimension != nil
            || patternArrayRadialAngle != nil
            || patternArrayCopyCount != nil
            || patternArrayCurveExtent != nil
            || patternArrayCurvePathPoint != nil
            || constructionPlane != nil
    }

    mutating func clear(except preservedTarget: ViewportInteractionTarget? = nil) {
        if !keeps(affordance, as: { .affordance($0.target) }, preservedTarget: preservedTarget) {
            affordance = nil
        }
        if !keeps(sketchCurveHandle, as: { .sketchCurveHandle($0.target) }, preservedTarget: preservedTarget) {
            sketchCurveHandle = nil
        }
        if !keeps(sketchDimension, as: { .sketchDimension($0.target) }, preservedTarget: preservedTarget) {
            sketchDimension = nil
        }
        if !keeps(sketchPointHandle, as: { .sketchPointHandle($0.target) }, preservedTarget: preservedTarget) {
            sketchPointHandle = nil
        }
        if !keeps(bridgeCurveEndpoint, as: { .bridgeCurveEndpoint($0.target) }, preservedTarget: preservedTarget) {
            bridgeCurveEndpoint = nil
        }
        if !keeps(splineControlPoint, as: { .splineControlPoint($0.target) }, preservedTarget: preservedTarget) {
            splineControlPoint = nil
        }
        if !keeps(
            splineControlPointSlide,
            as: { .splineControlPointSlide($0.target) },
            preservedTarget: preservedTarget
        ) {
            splineControlPointSlide = nil
        }
        if !keeps(
            polySplineSurfaceVertex,
            as: { .polySplineSurfaceVertex($0.target) },
            preservedTarget: preservedTarget
        ) {
            polySplineSurfaceVertex = nil
        }
        if !keeps(surfaceControlPoint, as: { .surfaceControlPoint($0.target) }, preservedTarget: preservedTarget) {
            surfaceControlPoint = nil
        }
        if !keeps(surfaceTrimEndpoint, as: { .surfaceTrimEndpoint($0.target) }, preservedTarget: preservedTarget) {
            surfaceTrimEndpoint = nil
        }
        if !keeps(
            surfaceTrimControlPoint,
            as: { .surfaceTrimControlPoint($0.target) },
            preservedTarget: preservedTarget
        ) {
            surfaceTrimControlPoint = nil
        }
        if !keeps(
            polySplineSurfaceVertexSlide,
            as: { .polySplineSurfaceVertexSlide($0.target) },
            preservedTarget: preservedTarget
        ) {
            polySplineSurfaceVertexSlide = nil
        }
        if !keeps(
            surfaceControlPointSlide,
            as: { .surfaceControlPointSlide($0.target) },
            preservedTarget: preservedTarget
        ) {
            surfaceControlPointSlide = nil
        }
        if !keeps(surfaceFrame, as: { .surfaceFrame($0.target) }, preservedTarget: preservedTarget) {
            surfaceFrame = nil
        }
        if !keeps(regionOffset, as: { .regionOffset($0.target) }, preservedTarget: preservedTarget) {
            regionOffset = nil
        }
        if !keeps(edgeOffset, as: { .edgeOffset($0.target) }, preservedTarget: preservedTarget) {
            edgeOffset = nil
        }
        if !keeps(slotWidth, as: { .slotWidth($0.target) }, preservedTarget: preservedTarget) {
            slotWidth = nil
        }
        if !keeps(sketchVertexOffset, as: { .sketchVertexOffset($0.target) }, preservedTarget: preservedTarget) {
            sketchVertexOffset = nil
        }
        if !keeps(
            patternArrayLinearAxis,
            as: { .patternArrayLinearAxis($0.target) },
            preservedTarget: preservedTarget
        ) {
            patternArrayLinearAxis = nil
        }
        if !keeps(
            independentCopyExtrudeDistance,
            as: { .independentCopyExtrudeDistance($0.target) },
            preservedTarget: preservedTarget
        ) {
            independentCopyExtrudeDistance = nil
        }
        if !keeps(
            independentCopyBodyDimension,
            as: { .independentCopyBodyDimension($0.target) },
            preservedTarget: preservedTarget
        ) {
            independentCopyBodyDimension = nil
        }
        if !keeps(
            patternArrayRadialAngle,
            as: { .patternArrayRadialAngle($0.target) },
            preservedTarget: preservedTarget
        ) {
            patternArrayRadialAngle = nil
        }
        if !keeps(
            patternArrayCopyCount,
            as: { .patternArrayCopyCount($0.target) },
            preservedTarget: preservedTarget
        ) {
            patternArrayCopyCount = nil
        }
        if !keeps(
            patternArrayCurveExtent,
            as: { .patternArrayCurveExtent($0.target) },
            preservedTarget: preservedTarget
        ) {
            patternArrayCurveExtent = nil
        }
        if !keeps(
            patternArrayCurvePathPoint,
            as: { .patternArrayCurvePathPoint($0.target) },
            preservedTarget: preservedTarget
        ) {
            patternArrayCurvePathPoint = nil
        }
        if !keeps(constructionPlane, as: { .constructionPlane($0.target) }, preservedTarget: preservedTarget) {
            constructionPlane = nil
        }
    }

    private func keeps<State>(
        _ state: State?,
        as interactionTarget: (State) -> ViewportInteractionTarget,
        preservedTarget: ViewportInteractionTarget?
    ) -> Bool {
        state.map(interactionTarget) == preservedTarget
    }
}
