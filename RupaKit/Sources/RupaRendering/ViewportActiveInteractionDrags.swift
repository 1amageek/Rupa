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
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.affordance), replacing: .affordance)
        }
    }

    var sketchCurveHandle: ViewportSketchCurveHandleDragState? {
        get { activeDrag?.sketchCurveHandle }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.sketchCurveHandle),
                replacing: .sketchCurveHandle
            )
        }
    }

    var sketchDimension: ViewportSketchDimensionDragState? {
        get { activeDrag?.sketchDimension }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.sketchDimension), replacing: .sketchDimension)
        }
    }

    var sketchPointHandle: ViewportSketchPointHandleDragState? {
        get { activeDrag?.sketchPointHandle }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.sketchPointHandle),
                replacing: .sketchPointHandle
            )
        }
    }

    var bridgeCurveEndpoint: ViewportBridgeCurveEndpointDragState? {
        get { activeDrag?.bridgeCurveEndpoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.bridgeCurveEndpoint),
                replacing: .bridgeCurveEndpoint
            )
        }
    }

    var splineControlPoint: ViewportSplineControlPointDragState? {
        get { activeDrag?.splineControlPoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.splineControlPoint),
                replacing: .splineControlPoint
            )
        }
    }

    var splineControlPointSlide: ViewportSplineControlPointSlideDragState? {
        get { activeDrag?.splineControlPointSlide }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.splineControlPointSlide),
                replacing: .splineControlPointSlide
            )
        }
    }

    var polySplineSurfaceVertex: ViewportPolySplineSurfaceVertexDragState? {
        get { activeDrag?.polySplineSurfaceVertex }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.polySplineSurfaceVertex),
                replacing: .polySplineSurfaceVertex
            )
        }
    }

    var surfaceControlPoint: ViewportSurfaceControlPointDragState? {
        get { activeDrag?.surfaceControlPoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.surfaceControlPoint),
                replacing: .surfaceControlPoint
            )
        }
    }

    var surfaceTrimEndpoint: ViewportSurfaceTrimEndpointDragState? {
        get { activeDrag?.surfaceTrimEndpoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.surfaceTrimEndpoint),
                replacing: .surfaceTrimEndpoint
            )
        }
    }

    var surfaceTrimControlPoint: ViewportSurfaceTrimControlPointDragState? {
        get { activeDrag?.surfaceTrimControlPoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.surfaceTrimControlPoint),
                replacing: .surfaceTrimControlPoint
            )
        }
    }

    var polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? {
        get { activeDrag?.polySplineSurfaceVertexSlide }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.polySplineSurfaceVertexSlide),
                replacing: .polySplineSurfaceVertexSlide
            )
        }
    }

    var surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? {
        get { activeDrag?.surfaceControlPointSlide }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.surfaceControlPointSlide),
                replacing: .surfaceControlPointSlide
            )
        }
    }

    var surfaceFrame: ViewportSurfaceFrameDragState? {
        get { activeDrag?.surfaceFrame }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.surfaceFrame), replacing: .surfaceFrame)
        }
    }

    var regionOffset: ViewportRegionOffsetDragState? {
        get { activeDrag?.regionOffset }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.regionOffset), replacing: .regionOffset)
        }
    }

    var edgeOffset: ViewportEdgeOffsetDragState? {
        get { activeDrag?.edgeOffset }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.edgeOffset), replacing: .edgeOffset)
        }
    }

    var slotWidth: ViewportSlotWidthDragState? {
        get { activeDrag?.slotWidth }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.slotWidth), replacing: .slotWidth)
        }
    }

    var sketchVertexOffset: ViewportSketchVertexOffsetDragState? {
        get { activeDrag?.sketchVertexOffset }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.sketchVertexOffset),
                replacing: .sketchVertexOffset
            )
        }
    }

    var patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? {
        get { activeDrag?.patternArrayLinearAxis }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.patternArrayLinearAxis),
                replacing: .patternArrayLinearAxis
            )
        }
    }

    var independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? {
        get { activeDrag?.independentCopyExtrudeDistance }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.independentCopyExtrudeDistance),
                replacing: .independentCopyExtrudeDistance
            )
        }
    }

    var independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? {
        get { activeDrag?.independentCopyBodyDimension }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.independentCopyBodyDimension),
                replacing: .independentCopyBodyDimension
            )
        }
    }

    var patternArrayRadialAngle: ViewportPatternArrayRadialAngleDragState? {
        get { activeDrag?.patternArrayRadialAngle }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.patternArrayRadialAngle),
                replacing: .patternArrayRadialAngle
            )
        }
    }

    var patternArrayCopyCount: ViewportPatternArrayCopyCountDragState? {
        get { activeDrag?.patternArrayCopyCount }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.patternArrayCopyCount),
                replacing: .patternArrayCopyCount
            )
        }
    }

    var patternArrayCurveExtent: ViewportPatternArrayCurveExtentDragState? {
        get { activeDrag?.patternArrayCurveExtent }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.patternArrayCurveExtent),
                replacing: .patternArrayCurveExtent
            )
        }
    }

    var patternArrayCurvePathPoint: ViewportPatternArrayCurvePathPointDragState? {
        get { activeDrag?.patternArrayCurvePathPoint }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.patternArrayCurvePathPoint),
                replacing: .patternArrayCurvePathPoint
            )
        }
    }

    var constructionPlane: ViewportConstructionPlaneHandleDragState? {
        get { activeDrag?.constructionPlane }
        set {
            setActiveDrag(
                newValue.map(ViewportActiveInteractionDragState.constructionPlane),
                replacing: .constructionPlane
            )
        }
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

    private mutating func setActiveDrag(
        _ newActiveDrag: ViewportActiveInteractionDragState?,
        replacing kind: ViewportActiveInteractionDragKind
    ) {
        guard let newActiveDrag else {
            if activeDrag?.kind == kind {
                activeDrag = nil
            }
            return
        }
        activeDrag = newActiveDrag
    }
}
