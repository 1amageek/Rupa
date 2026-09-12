struct ViewportActiveInteractionDrags: Equatable {
    private var activeDrag: ViewportActiveInteractionDragState?

    init(
        affordance: ViewportAffordanceDragState? = nil,
        sketchCurveHandle: ViewportSketchCurveHandleDragState? = nil,
        sketchDimension: ViewportSketchDimensionDragState? = nil,
        sketchPointHandle: ViewportSketchPointHandleDragState? = nil,
        splineControlPoint: ViewportSplineControlPointDragState? = nil,
        splineControlPointSlide: ViewportSplineControlPointSlideDragState? = nil,
        polySplineSurfaceVertexSlide: ViewportPolySplineSurfaceVertexSlideDragState? = nil,
        surfaceControlPointSlide: ViewportSurfaceControlPointSlideDragState? = nil,
        surfaceFrame: ViewportSurfaceFrameDragState? = nil,
        regionOffset: ViewportRegionOffsetDragState? = nil,
        edgeOffset: ViewportEdgeOffsetDragState? = nil,
        slotWidth: ViewportSlotWidthDragState? = nil,
        sketchVertexOffset: ViewportSketchVertexOffsetDragState? = nil,
        patternArrayLinearAxis: ViewportPatternArrayLinearAxisDragState? = nil,
        independentCopyExtrudeDistance: ViewportIndependentCopyExtrudeDistanceDragState? = nil,
        independentCopyBodyDimension: ViewportIndependentCopyBodyDimensionDragState? = nil
    ) {
        activeDrag = ViewportActiveInteractionDragCandidates(
            affordance: affordance,
            sketchCurveHandle: sketchCurveHandle,
            sketchDimension: sketchDimension,
            sketchPointHandle: sketchPointHandle,
            splineControlPoint: splineControlPoint,
            splineControlPointSlide: splineControlPointSlide,
            polySplineSurfaceVertexSlide: polySplineSurfaceVertexSlide,
            surfaceControlPointSlide: surfaceControlPointSlide,
            surfaceFrame: surfaceFrame,
            regionOffset: regionOffset,
            edgeOffset: edgeOffset,
            slotWidth: slotWidth,
            sketchVertexOffset: sketchVertexOffset,
            patternArrayLinearAxis: patternArrayLinearAxis,
            independentCopyExtrudeDistance: independentCopyExtrudeDistance,
            independentCopyBodyDimension: independentCopyBodyDimension
        ).firstActiveDrag
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
