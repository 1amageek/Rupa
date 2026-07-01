import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

public struct Viewport: View {
    private static let projectionAnimationDuration: TimeInterval = 0.34

    @State private var activeCanvasDrag: ViewportActiveDrag?
    @State private var activeAffordanceDrag: ViewportAffordanceDragState?
    @State private var activeSketchCurveHandleDrag: ViewportSketchCurveHandleDragState?
    @State private var activeSketchDimensionDrag: ViewportSketchDimensionDragState?
    @State private var activeSketchPointHandleDrag: ViewportSketchPointHandleDragState?
    @State private var activeBridgeCurveEndpointDrag: ViewportBridgeCurveEndpointDragState?
    @State private var activeSplineControlPointDrag: ViewportSplineControlPointDragState?
    @State private var activeSplineControlPointSlideDrag: ViewportSplineControlPointSlideDragState?
    @State private var activePolySplineSurfaceVertexDrag: ViewportPolySplineSurfaceVertexDragState?
    @State private var activeSurfaceControlPointDrag: ViewportSurfaceControlPointDragState?
    @State private var activeSurfaceTrimEndpointDrag: ViewportSurfaceTrimEndpointDragState?
    @State private var activeSurfaceTrimControlPointDrag: ViewportSurfaceTrimControlPointDragState?
    @State private var activePolySplineSurfaceVertexSlideDrag: ViewportPolySplineSurfaceVertexSlideDragState?
    @State private var activeSurfaceControlPointSlideDrag: ViewportSurfaceControlPointSlideDragState?
    @State private var activeSurfaceFrameDrag: ViewportSurfaceFrameDragState?
    @State private var activeRegionOffsetDrag: ViewportRegionOffsetDragState?
    @State private var activeEdgeOffsetDrag: ViewportEdgeOffsetDragState?
    @State private var activeSlotWidthDrag: ViewportSlotWidthDragState?
    @State private var activeSketchVertexOffsetDrag: ViewportSketchVertexOffsetDragState?
    @State private var activePatternArrayLinearAxisDrag: ViewportPatternArrayLinearAxisDragState?
    @State private var activeIndependentCopyExtrudeDistanceDrag: ViewportIndependentCopyExtrudeDistanceDragState?
    @State private var activeIndependentCopyBodyDimensionDrag: ViewportIndependentCopyBodyDimensionDragState?
    @State private var activePatternArrayRadialAngleDrag: ViewportPatternArrayRadialAngleDragState?
    @State private var activePatternArrayCopyCountDrag: ViewportPatternArrayCopyCountDragState?
    @State private var activePatternArrayCurveExtentDrag: ViewportPatternArrayCurveExtentDragState?
    @State private var activePatternArrayCurvePathPointDrag: ViewportPatternArrayCurvePathPointDragState?
    @State private var camera: ViewportCamera = .identity
    @State private var editedBodies: [FeatureID: ViewportObjectEditState] = [:]
    @State private var hoveredAffordance: ViewportAffordanceTarget?
    @State private var hoveredSketchCurveHandle: ViewportSketchCurveHandleTarget?
    @State private var hoveredSketchDimension: ViewportSketchDimensionTarget?
    @State private var hoveredSketchPointHandle: ViewportSketchPointHandleTarget?
    @State private var hoveredBridgeCurveEndpointHandle: ViewportBridgeCurveEndpointHandleTarget?
    @State private var hoveredSplineControlPoint: ViewportSplineControlPointHandleTarget?
    @State private var hoveredSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget?
    @State private var hoveredPolySplineSurfaceVertex: ViewportPolySplineSurfaceVertexHandleTarget?
    @State private var hoveredSurfaceControlPoint: ViewportSurfaceControlPointHandleTarget?
    @State private var hoveredSurfaceTrimEndpoint: ViewportSurfaceTrimEndpointHandleTarget?
    @State private var hoveredSurfaceTrimControlPoint: ViewportSurfaceTrimControlPointHandleTarget?
    @State private var hoveredPolySplineSurfaceVertexSlideHandle: ViewportPolySplineSurfaceVertexSlideHandleTarget?
    @State private var hoveredSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget?
    @State private var hoveredSurfaceFrameHandle: ViewportSurfaceFrameHandleTarget?
    @State private var hoveredRegionOffsetHandle: ViewportRegionOffsetHandleTarget?
    @State private var hoveredEdgeOffsetHandle: ViewportEdgeOffsetHandleTarget?
    @State private var hoveredSlotWidthHandle: ViewportSlotWidthHandleTarget?
    @State private var hoveredSketchVertexOffsetHandle: ViewportSketchVertexOffsetHandleTarget?
    @State private var hoveredPatternArrayLinearAxisHandle: ViewportPatternArrayLinearAxisHandleTarget?
    @State private var hoveredIndependentCopyExtrudeDistanceHandle: ViewportIndependentCopyExtrudeDistanceHandleTarget?
    @State private var hoveredIndependentCopyBodyDimensionHandle: ViewportIndependentCopyBodyDimensionHandleTarget?
    @State private var hoveredPatternArrayRadialAngleHandle: ViewportPatternArrayRadialAngleHandleTarget?
    @State private var hoveredPatternArrayCopyCountHandle: ViewportPatternArrayCopyCountHandleTarget?
    @State private var hoveredPatternArrayCurveExtentHandle: ViewportPatternArrayCurveExtentHandleTarget?
    @State private var hoveredPatternArrayCurvePathPointHandle: ViewportPatternArrayCurvePathPointHandleTarget?
    @State private var hoveredPatternArrayOutputModeHandle: ViewportPatternArrayOutputModeHandleTarget?
    @State private var pendingAffordance: ViewportAffordanceTarget?
    @State private var pendingSketchCurveHandle: ViewportSketchCurveHandleTarget?
    @State private var pendingSketchDimension: ViewportSketchDimensionTarget?
    @State private var pendingSketchPointHandle: ViewportSketchPointHandleTarget?
    @State private var pendingBridgeCurveEndpointHandle: ViewportBridgeCurveEndpointHandleTarget?
    @State private var pendingSplineControlPoint: ViewportSplineControlPointHandleTarget?
    @State private var pendingSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget?
    @State private var pendingPolySplineSurfaceVertex: ViewportPolySplineSurfaceVertexHandleTarget?
    @State private var pendingSurfaceControlPoint: ViewportSurfaceControlPointHandleTarget?
    @State private var pendingSurfaceTrimEndpoint: ViewportSurfaceTrimEndpointHandleTarget?
    @State private var pendingSurfaceTrimControlPoint: ViewportSurfaceTrimControlPointHandleTarget?
    @State private var pendingPolySplineSurfaceVertexSlideHandle: ViewportPolySplineSurfaceVertexSlideHandleTarget?
    @State private var pendingSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget?
    @State private var pendingSurfaceFrameHandle: ViewportSurfaceFrameHandleTarget?
    @State private var pendingRegionOffsetHandle: ViewportRegionOffsetHandleTarget?
    @State private var pendingEdgeOffsetHandle: ViewportEdgeOffsetHandleTarget?
    @State private var pendingSlotWidthHandle: ViewportSlotWidthHandleTarget?
    @State private var pendingSketchVertexOffsetHandle: ViewportSketchVertexOffsetHandleTarget?
    @State private var pendingPatternArrayLinearAxisHandle: ViewportPatternArrayLinearAxisHandleTarget?
    @State private var pendingIndependentCopyExtrudeDistanceHandle: ViewportIndependentCopyExtrudeDistanceHandleTarget?
    @State private var pendingIndependentCopyBodyDimensionHandle: ViewportIndependentCopyBodyDimensionHandleTarget?
    @State private var pendingPatternArrayRadialAngleHandle: ViewportPatternArrayRadialAngleHandleTarget?
    @State private var pendingPatternArrayCopyCountHandle: ViewportPatternArrayCopyCountHandleTarget?
    @State private var pendingPatternArrayCurveExtentHandle: ViewportPatternArrayCurveExtentHandleTarget?
    @State private var pendingPatternArrayCurvePathPointHandle: ViewportPatternArrayCurvePathPointHandleTarget?
    @State private var pendingPatternArrayOutputModeHandle: ViewportPatternArrayOutputModeHandleTarget?
    @State private var orbitBasis: ViewportProjectionBasis?
    @State private var projectionTransition: ViewportProjectionTransition?
    @State private var modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    @State private var reportedSnapCandidateKind: RupaCore.SnapCandidateKind?
    @State private var selectedAxis: ViewportCoordinateAxis?
    @State private var hoveredCanvasHit: ViewportHit?
    @State private var hoveredModelPoint: Point2D?
    @State private var identityHitResolver = ViewportIdentityHitResolver()

    private let document: DesignDocument
    private let currentEvaluation: DocumentEvaluationContext?
    private let documentGeneration: DocumentGeneration?
    private let evaluationCache: EvaluatedDocumentCache?
    private let objectRegistry: ObjectTypeRegistry
    private let evaluationStatus: EvaluationStatus
    private let renderInvalidation: RenderInvalidation
    private let selection: SelectionModel
    private let selectionDragPreviewTargets: [SelectionTarget]
    private let patternArrayCurvePathReplacementPreviewRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest?
    private let surfaceAnalysis: SurfaceAnalysisResult?
    private let surfaceAnalysisOptions: ViewportSurfaceAnalysisOptions
    private let surfaceContinuity: RupaCore.SurfaceContinuityResult?
    private let curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay]
    private let pointDisplays: [SelectionComponentID: PointDisplay]
    private let snapResolutionOptions: SnapResolutionOptions?
    private let canvasDragPreviewKind: ViewportCanvasDragPreviewKind?
    private let canvasDragAxisConstraint: SketchAxisConstraint?
    private let canvasDragSketchPlaneOverride: SketchPlane?
    private let projectionRequest: ViewportProjectionRequest?
    private let selectionHitPolicy: ViewportSelectionHitPolicy
    private let bottomChromeReservedHeight: CGFloat
    private let hoverClearSignal: Int
    private let showsConstructionPlaneHover: Bool
    private let allowsSelectionRectangle: Bool
    private let allowsObjectAffordances: Bool
    private let slotWidthMeters: Double
    private let sketchVertexOffsetDistanceMeters: Double
    private let edgeOffsetDistanceMeters: Double
    private let onPick: ((ViewportCanvasTarget) -> Void)?
    private let onCanvasDrag: ((ViewportModelDrag) -> Void)?
    private let onShiftScroll: ((ViewportScrollDirection) -> Bool)?
    private let onReferenceLineAnchor: ((Point2D) -> Bool)?
    private let onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)?
    private let onSelectionDragPreview: ((ViewportSelectionDragTarget) -> Void)?
    private let onVertexDrag: ((ViewportVertexDragTarget) -> Void)?
    private let onFaceDrag: ((ViewportFaceDragTarget) -> Void)?
    private let onEdgeChamferDrag: ((ViewportEdgeChamferDragTarget) -> Void)?
    private let onEdgeFilletDrag: ((ViewportEdgeFilletDragTarget) -> Void)?
    private let onRegionOffsetDrag: ((ViewportRegionOffsetDragTarget) -> Void)?
    private let onEdgeOffsetDrag: ((ViewportEdgeOffsetDragTarget) -> Void)?
    private let onSlotWidthDrag: ((ViewportSlotWidthDragTarget) -> Void)?
    private let onSketchVertexOffsetDrag: ((ViewportSketchVertexOffsetDragTarget) -> Void)?
    private let onPatternArrayLinearAxisDrag: ((ViewportPatternArrayLinearAxisDragTarget) -> Void)?
    private let onIndependentCopyExtrudeDistanceDrag: ((ViewportIndependentCopyExtrudeDistanceDragTarget) -> Void)?
    private let onIndependentCopyBodyDimensionDrag: ((ViewportIndependentCopyBodyDimensionDragTarget) -> Void)?
    private let onPatternArrayRadialAngleDrag: ((ViewportPatternArrayRadialAngleDragTarget) -> Void)?
    private let onPatternArrayCopyCountDrag: ((ViewportPatternArrayCopyCountDragTarget) -> Void)?
    private let onPatternArrayCurveExtentDrag: ((ViewportPatternArrayCurveExtentDragTarget) -> Void)?
    private let onPatternArrayCurvePathPointDrag: ((ViewportPatternArrayCurvePathPointDragTarget) -> Void)?
    private let onPatternArrayOutputModeChange: ((ViewportPatternArrayOutputModeTarget) -> Void)?
    private let onSketchCurveHandleDrag: ((ViewportSketchCurveHandleDragTarget) -> Void)?
    private let onSketchDimensionDrag: ((ViewportSketchDimensionDragTarget) -> Void)?
    private let onSketchPointHandleDrag: ((ViewportSketchPointHandleDragTarget) -> Void)?
    private let onBridgeCurveEndpointDrag: ((ViewportBridgeCurveEndpointDragTarget) -> Void)?
    private let onSplineControlPointDrag: ((ViewportSplineControlPointDragTarget) -> Void)?
    private let onSplineControlPointSlideDrag: ((ViewportSplineControlPointSlideDragTarget) -> Void)?
    private let onPolySplineSurfaceVertexDrag: ((ViewportPolySplineSurfaceVertexDragTarget) -> Void)?
    private let onSurfaceControlPointDrag: ((ViewportSurfaceControlPointDragTarget) -> Void)?
    private let onSurfaceTrimEndpointDrag: ((ViewportSurfaceTrimEndpointDragTarget) -> Void)?
    private let onSurfaceTrimControlPointDrag: ((ViewportSurfaceTrimControlPointDragTarget) -> Void)?
    private let onPolySplineSurfaceVertexSlideDrag: ((ViewportPolySplineSurfaceVertexSlideDragTarget) -> Void)?
    private let onSurfaceControlPointSlideDrag: ((ViewportSurfaceControlPointSlideDragTarget) -> Void)?
    private let onSurfaceFrameDrag: ((ViewportSurfaceFrameDragTarget) -> Void)?
    private let onCommandConfirm: (() -> Void)?
    private let onHover: ((ViewportHit?) -> Void)?
    private let onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)?
    private let onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)?

    public init(
        document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext? = nil,
        documentGeneration: DocumentGeneration? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        evaluationStatus: EvaluationStatus = .notEvaluated,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        selection: SelectionModel = .empty,
        selectionDragPreviewTargets: [SelectionTarget] = [],
        patternArrayCurvePathReplacementPreviewRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest? = nil,
        surfaceAnalysis: SurfaceAnalysisResult? = nil,
        surfaceAnalysisOptions: ViewportSurfaceAnalysisOptions = ViewportSurfaceAnalysisOptions(),
        surfaceContinuity: RupaCore.SurfaceContinuityResult? = nil,
        curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay] = [:],
        pointDisplays: [SelectionComponentID: PointDisplay] = [:],
        snapResolutionOptions: SnapResolutionOptions? = nil,
        canvasDragPreviewKind: ViewportCanvasDragPreviewKind? = .rectangle(widthMeters: nil, heightMeters: nil),
        canvasDragAxisConstraint: SketchAxisConstraint? = nil,
        canvasDragSketchPlaneOverride: SketchPlane? = nil,
        projectionRequest: ViewportProjectionRequest? = nil,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all,
        bottomChromeReservedHeight: CGFloat = 0.0,
        hoverClearSignal: Int = 0,
        showsConstructionPlaneHover: Bool = false,
        allowsSelectionRectangle: Bool = false,
        allowsObjectAffordances: Bool = true,
        slotWidthMeters: Double? = nil,
        sketchVertexOffsetDistanceMeters: Double? = nil,
        edgeOffsetDistanceMeters: Double? = nil,
        onPick: ((ViewportCanvasTarget) -> Void)? = nil,
        onCanvasDrag: ((ViewportModelDrag) -> Void)? = nil,
        onShiftScroll: ((ViewportScrollDirection) -> Bool)? = nil,
        onReferenceLineAnchor: ((Point2D) -> Bool)? = nil,
        onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onSelectionDragPreview: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onVertexDrag: ((ViewportVertexDragTarget) -> Void)? = nil,
        onFaceDrag: ((ViewportFaceDragTarget) -> Void)? = nil,
        onEdgeChamferDrag: ((ViewportEdgeChamferDragTarget) -> Void)? = nil,
        onEdgeFilletDrag: ((ViewportEdgeFilletDragTarget) -> Void)? = nil,
        onRegionOffsetDrag: ((ViewportRegionOffsetDragTarget) -> Void)? = nil,
        onEdgeOffsetDrag: ((ViewportEdgeOffsetDragTarget) -> Void)? = nil,
        onSlotWidthDrag: ((ViewportSlotWidthDragTarget) -> Void)? = nil,
        onSketchVertexOffsetDrag: ((ViewportSketchVertexOffsetDragTarget) -> Void)? = nil,
        onPatternArrayLinearAxisDrag: ((ViewportPatternArrayLinearAxisDragTarget) -> Void)? = nil,
        onIndependentCopyExtrudeDistanceDrag: ((ViewportIndependentCopyExtrudeDistanceDragTarget) -> Void)? = nil,
        onIndependentCopyBodyDimensionDrag: ((ViewportIndependentCopyBodyDimensionDragTarget) -> Void)? = nil,
        onPatternArrayRadialAngleDrag: ((ViewportPatternArrayRadialAngleDragTarget) -> Void)? = nil,
        onPatternArrayCopyCountDrag: ((ViewportPatternArrayCopyCountDragTarget) -> Void)? = nil,
        onPatternArrayCurveExtentDrag: ((ViewportPatternArrayCurveExtentDragTarget) -> Void)? = nil,
        onPatternArrayCurvePathPointDrag: ((ViewportPatternArrayCurvePathPointDragTarget) -> Void)? = nil,
        onPatternArrayOutputModeChange: ((ViewportPatternArrayOutputModeTarget) -> Void)? = nil,
        onSketchCurveHandleDrag: ((ViewportSketchCurveHandleDragTarget) -> Void)? = nil,
        onSketchDimensionDrag: ((ViewportSketchDimensionDragTarget) -> Void)? = nil,
        onSketchPointHandleDrag: ((ViewportSketchPointHandleDragTarget) -> Void)? = nil,
        onBridgeCurveEndpointDrag: ((ViewportBridgeCurveEndpointDragTarget) -> Void)? = nil,
        onSplineControlPointDrag: ((ViewportSplineControlPointDragTarget) -> Void)? = nil,
        onSplineControlPointSlideDrag: ((ViewportSplineControlPointSlideDragTarget) -> Void)? = nil,
        onPolySplineSurfaceVertexDrag: ((ViewportPolySplineSurfaceVertexDragTarget) -> Void)? = nil,
        onSurfaceControlPointDrag: ((ViewportSurfaceControlPointDragTarget) -> Void)? = nil,
        onSurfaceTrimEndpointDrag: ((ViewportSurfaceTrimEndpointDragTarget) -> Void)? = nil,
        onSurfaceTrimControlPointDrag: ((ViewportSurfaceTrimControlPointDragTarget) -> Void)? = nil,
        onPolySplineSurfaceVertexSlideDrag: ((ViewportPolySplineSurfaceVertexSlideDragTarget) -> Void)? = nil,
        onSurfaceControlPointSlideDrag: ((ViewportSurfaceControlPointSlideDragTarget) -> Void)? = nil,
        onSurfaceFrameDrag: ((ViewportSurfaceFrameDragTarget) -> Void)? = nil,
        onCommandConfirm: (() -> Void)? = nil,
        onHover: ((ViewportHit?) -> Void)? = nil,
        onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)? = nil,
        onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)? = nil
    ) {
        self.document = document
        self.currentEvaluation = currentEvaluation
        self.documentGeneration = documentGeneration
        self.evaluationCache = evaluationCache
        self.objectRegistry = objectRegistry
        self.evaluationStatus = evaluationStatus
        self.renderInvalidation = renderInvalidation
        self.selection = selection
        self.selectionDragPreviewTargets = selectionDragPreviewTargets
        self.patternArrayCurvePathReplacementPreviewRequest = patternArrayCurvePathReplacementPreviewRequest
        self.surfaceAnalysis = surfaceAnalysis
        self.surfaceAnalysisOptions = surfaceAnalysisOptions
        self.surfaceContinuity = surfaceContinuity
        self.curveCurvatureDisplays = curveCurvatureDisplays
        self.pointDisplays = pointDisplays
        self.snapResolutionOptions = snapResolutionOptions
        self.canvasDragPreviewKind = canvasDragPreviewKind
        self.canvasDragAxisConstraint = canvasDragAxisConstraint
        self.canvasDragSketchPlaneOverride = canvasDragSketchPlaneOverride
        self.projectionRequest = projectionRequest
        self.selectionHitPolicy = selectionHitPolicy
        self.bottomChromeReservedHeight = max(0.0, bottomChromeReservedHeight)
        self.hoverClearSignal = hoverClearSignal
        self.showsConstructionPlaneHover = showsConstructionPlaneHover
        self.allowsSelectionRectangle = allowsSelectionRectangle
        self.allowsObjectAffordances = allowsObjectAffordances
        let interactionScaleDefaults = ViewportInteractionScaleDefaults(ruler: document.ruler)
        self.slotWidthMeters = slotWidthMeters ?? interactionScaleDefaults.slotWidthMeters
        self.sketchVertexOffsetDistanceMeters = sketchVertexOffsetDistanceMeters
            ?? interactionScaleDefaults.operationStepMeters
        self.edgeOffsetDistanceMeters = edgeOffsetDistanceMeters
            ?? interactionScaleDefaults.operationStepMeters
        self.onPick = onPick
        self.onCanvasDrag = onCanvasDrag
        self.onShiftScroll = onShiftScroll
        self.onReferenceLineAnchor = onReferenceLineAnchor
        self.onSelectionDrag = onSelectionDrag
        self.onSelectionDragPreview = onSelectionDragPreview
        self.onVertexDrag = onVertexDrag
        self.onFaceDrag = onFaceDrag
        self.onEdgeChamferDrag = onEdgeChamferDrag
        self.onEdgeFilletDrag = onEdgeFilletDrag
        self.onRegionOffsetDrag = onRegionOffsetDrag
        self.onEdgeOffsetDrag = onEdgeOffsetDrag
        self.onSlotWidthDrag = onSlotWidthDrag
        self.onSketchVertexOffsetDrag = onSketchVertexOffsetDrag
        self.onPatternArrayLinearAxisDrag = onPatternArrayLinearAxisDrag
        self.onIndependentCopyExtrudeDistanceDrag = onIndependentCopyExtrudeDistanceDrag
        self.onIndependentCopyBodyDimensionDrag = onIndependentCopyBodyDimensionDrag
        self.onPatternArrayRadialAngleDrag = onPatternArrayRadialAngleDrag
        self.onPatternArrayCopyCountDrag = onPatternArrayCopyCountDrag
        self.onPatternArrayCurveExtentDrag = onPatternArrayCurveExtentDrag
        self.onPatternArrayCurvePathPointDrag = onPatternArrayCurvePathPointDrag
        self.onPatternArrayOutputModeChange = onPatternArrayOutputModeChange
        self.onSketchCurveHandleDrag = onSketchCurveHandleDrag
        self.onSketchDimensionDrag = onSketchDimensionDrag
        self.onSketchPointHandleDrag = onSketchPointHandleDrag
        self.onBridgeCurveEndpointDrag = onBridgeCurveEndpointDrag
        self.onSplineControlPointDrag = onSplineControlPointDrag
        self.onSplineControlPointSlideDrag = onSplineControlPointSlideDrag
        self.onPolySplineSurfaceVertexDrag = onPolySplineSurfaceVertexDrag
        self.onSurfaceControlPointDrag = onSurfaceControlPointDrag
        self.onSurfaceTrimEndpointDrag = onSurfaceTrimEndpointDrag
        self.onSurfaceTrimControlPointDrag = onSurfaceTrimControlPointDrag
        self.onPolySplineSurfaceVertexSlideDrag = onPolySplineSurfaceVertexSlideDrag
        self.onSurfaceControlPointSlideDrag = onSurfaceControlPointSlideDrag
        self.onSurfaceFrameDrag = onSurfaceFrameDrag
        self.onCommandConfirm = onCommandConfirm
        self.onHover = onHover
        self.onSnapCandidateKindChange = onSnapCandidateKindChange
        self.onProjectionBasisChange = onProjectionBasisChange
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let basis = projectionBasis(at: timeline.date)
                let chromeLayout = ViewportCanvasChromeLayout(
                    viewportSize: proxy.size,
                    bottomReservedHeight: bottomChromeReservedHeight
                )
                let projectedGrid = ViewportProjectedGrid(
                    document: document,
                    size: proxy.size,
                    camera: camera,
                    basis: basis
                )

                Canvas { context, size in
                    drawGrid(projectedGrid, in: &context)
                    drawAxes(in: &context, size: size, camera: camera, basis: basis)
                    drawModel(in: &context, size: size, camera: camera, basis: basis)
                    drawReferenceLines(in: &context, size: size, camera: camera, basis: basis)
                }
                .background(ViewportTheme.background)
                .id(renderInvalidation)
                .accessibilityIdentifier("CanvasViewport")
                .accessibilityLabel("Canvas viewport")
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    viewportBadge(scaleReadout: projectedGrid.scaleReadout)
                        .frame(
                            width: ViewportCanvasChromeLayout.viewportBadgeSize.width,
                            height: ViewportCanvasChromeLayout.viewportBadgeSize.height,
                            alignment: .leading
                        )
                        .padding(.top, ViewportCanvasChromeLayout.viewportBadgePadding)
                        .padding(.leading, ViewportCanvasChromeLayout.viewportBadgePadding)
                        .zIndex(2.0)
                        .onHover { isHovered in
                            if isHovered {
                                clearCanvasHover()
                            }
                        }
                }
                .overlay {
                    canvasDragPlaceholderOverlay(basis: basis)
                }
                .overlay {
                    selectionAffordanceAccessibilityMarker
                }
                .overlay {
                    gridAccessibilityMarkers(readout: projectedGrid.scaleReadout)
                }
                .overlay {
                    ViewportInputSurface(
                        onPress: { point, size, _ in
                            beginViewportPress(at: point, size: size)
                        },
                        onPick: { point, size, intent in
                            pick(at: point, size: size, selectionIntent: intent)
                        },
                        onCanvasDrag: { start, end, size, intent in
                            handleCanvasDrag(
                                from: start,
                                to: end,
                                size: size,
                                selectionIntent: intent
                            )
                        },
                        onDragPreview: { start, current, size in
                            updateCanvasDragPlaceholder(
                                from: start,
                                to: current,
                                size: size
                            )
                        },
                        onHover: { point, size in
                            if let point {
                                hover(at: point, size: size)
                            } else {
                                clearCanvasHover()
                            }
                        },
                        onPan: { delta in
                            panCanvas(by: delta)
                        },
                        onZoom: { factor, anchor, size in
                            zoomCanvas(by: factor, anchor: anchor, size: size)
                        },
                        onOrbit: { delta in
                            orbitViewport(by: delta)
                        },
                        onModifierFlagsChange: { flags, size in
                            modifierFlags = flags
                            refreshSnapCandidateKind(size: size)
                        },
                        onSecondaryClick: { _, _ in
                            onCommandConfirm?()
                        },
                        onShiftScroll: { direction in
                            onShiftScroll?(direction) ?? false
                        },
                        onShiftTap: { point, size in
                            captureReferenceLineAnchor(at: point, size: size)
                        },
                        inputExclusionRects: chromeLayout.inputExclusionRects
                    )
                    .accessibilityHidden(true)
                }
                .overlay {
                    faceAccessibilityMarkers(size: proxy.size, basis: basis)
                }
                .overlay {
                    edgeAccessibilityMarkers(size: proxy.size, basis: basis)
                }
                .overlay(alignment: .bottom) {
                    ViewportAxisTriad(
                        selectedAxis: selectedAxis,
                        basis: basis,
                        onResetView: {
                            resetViewportCamera()
                        },
                        onSelectAxis: { axis in
                            selectProjectionAxis(axis)
                        }
                    )
                    .padding(
                        .bottom,
                        ViewportCanvasChromeLayout.axisBottomPadding + bottomChromeReservedHeight
                    )
                    .zIndex(2.0)
                    .onHover { isHovered in
                        if isHovered {
                            clearCanvasHover()
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onChange(of: snapResolutionOptions) { _, _ in
                refreshSnapCandidateKind(size: proxy.size)
            }
            .onChange(of: hoverClearSignal) { _, _ in
                clearCanvasHover()
            }
        }
        .onAppear {
            if let projectionRequest {
                applyProjectionRequest(projectionRequest)
            } else {
                publishProjectionBasis(currentProjectionBasis)
            }
        }
        .onChange(of: projectionRequest) { _, nextRequest in
            if let nextRequest {
                applyProjectionRequest(nextRequest)
            }
        }
    }

    private func gridAccessibilityMarkers(
        readout: ViewportProjectedGrid.ScaleReadout
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasCoordinateGrid")
                .accessibilityLabel("Coordinate aligned grid")
                .accessibilityValue(readout.accessibilityText)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasGridRuler")
                .accessibilityLabel("In-plane grid ruler")
                .accessibilityValue(readout.accessibilityText)
        }
        .allowsHitTesting(false)
    }

    private func faceAccessibilityMarkers(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) -> some View {
        let markers = bodyFaceAccessibilityMarkers(size: size, basis: basis)
        return ZStack {
            ForEach(markers) { marker in
                Button {
                    onPick?(
                        ViewportCanvasTarget(
                            hit: marker.hit,
                            modelPoint: marker.modelPoint,
                            sketchPlane: marker.sketchPlane,
                            selectionIntent: .replace
                        )
                    )
                } label: {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 10.0, height: 10.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(marker.point)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasBodyFace.\(marker.face.rawValue)")
                .accessibilityLabel("\(marker.face.rawValue) body face")
                .accessibilityValue(marker.face.rawValue)
            }
        }
    }

    private func edgeAccessibilityMarkers(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) -> some View {
        let markers = bodyEdgeAccessibilityMarkers(size: size, basis: basis)
        return ZStack {
            ForEach(markers) { marker in
                Button {
                    onPick?(
                        ViewportCanvasTarget(
                            hit: marker.hit,
                            modelPoint: marker.modelPoint,
                            sketchPlane: marker.sketchPlane,
                            selectionIntent: .replace
                        )
                    )
                } label: {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 12.0, height: 12.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(marker.point)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasBodyEdge.\(marker.edge.rawValue)")
                .accessibilityLabel("\(marker.edge.rawValue) body edge")
                .accessibilityValue(marker.edge.rawValue)
            }
        }
    }

    @ViewBuilder private func canvasDragPlaceholderOverlay(
        basis: ViewportProjectionBasis
    ) -> some View {
        if let activeCanvasDrag {
            ZStack {
                Canvas { context, size in
                    switch activeCanvasDrag.kind {
                    case .creation(let previewKind):
                        drawCanvasDragPreview(
                            activeCanvasDrag,
                            previewKind: previewKind,
                            in: &context,
                            size: size,
                            basis: basis
                        )
                    case .selection:
                        drawSelectionDragRectangle(activeCanvasDrag, in: &context)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 1.0, height: 1.0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(activeCanvasDrag.accessibilityIdentifier)
                    .accessibilityLabel(activeCanvasDrag.accessibilityLabel)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var selectionAffordanceAccessibilityMarker: some View {
        if hasSelectedAffordance {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasSelectionAffordance")
                .accessibilityLabel("Selected target affordance")
                .allowsHitTesting(false)
        }
    }

    private var hasSelectedAffordance: Bool {
        allowsObjectAffordances && !selectedObjectFeatureIDs().isEmpty
    }

    private func viewportBadge(
        scaleReadout: ViewportProjectedGrid.ScaleReadout
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .symbolRenderingMode(.hierarchical)
            Text(document.displayUnit.symbol)
                .font(.system(.caption, design: .monospaced))
            Divider()
                .frame(height: 12)
            Text(scaleReadout.compactText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            Divider()
                .frame(height: 12)
            Text(statusTitle)
                .font(.caption)
                .lineLimit(1)
            Divider()
                .frame(height: 12)
            Text("\(Int((camera.zoom * 100.0).rounded()))%")
                .font(.system(.caption, design: .monospaced))
            if featureCount > 0 {
                Divider()
                    .frame(height: 12)
                Text("\(featureCount) features")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(
            width: ViewportCanvasChromeLayout.viewportBadgeSize.width,
            height: ViewportCanvasChromeLayout.viewportBadgeSize.height,
            alignment: .leading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var featureCount: Int {
        document.cadDocument.designGraph.order.count
    }

    private var currentProjectionBasis: ViewportProjectionBasis {
        projectionBasis(at: Date())
    }

    private func publishProjectionBasis(_ basis: ViewportProjectionBasis) {
        onProjectionBasisChange?(basis)
    }

    private func projectionBasis(at date: Date) -> ViewportProjectionBasis {
        guard let projectionTransition else {
            if let orbitBasis {
                return orbitBasis
            }
            return targetProjectionBasis(for: selectedAxis)
        }
        return projectionTransition.basis(at: date)
    }

    private func targetProjectionBasis(for axis: ViewportCoordinateAxis?) -> ViewportProjectionBasis {
        guard let axis else {
            return .isometric
        }
        return .axisFront(axis)
    }

    private func applyProjectionRequest(_ request: ViewportProjectionRequest) {
        transitionProjection(
            to: request.basis,
            selectedAxis: nil,
            storesOrbitBasis: true
        )
    }

    private var statusTitle: String {
        switch evaluationStatus {
        case .notEvaluated:
            "Not evaluated"
        case .valid:
            if let generation = renderInvalidation.generation {
                "Gen \(generation.value)"
            } else {
                "Valid"
            }
        case .failed:
            "Invalid"
        }
    }

    private func drawGrid(
        _ grid: ViewportProjectedGrid,
        in context: inout GraphicsContext
    ) {
        var minorPath = Path()
        var majorPath = Path()
        var originPath = Path()

        for line in grid.lines {
            if line.isOrigin {
                originPath.move(to: line.start)
                originPath.addLine(to: line.end)
            } else if line.isMajor {
                majorPath.move(to: line.start)
                majorPath.addLine(to: line.end)
            } else {
                minorPath.move(to: line.start)
                minorPath.addLine(to: line.end)
            }
        }

        context.stroke(minorPath, with: .color(ViewportTheme.gridMinor), lineWidth: 0.45)
        context.stroke(majorPath, with: .color(ViewportTheme.gridMajor), lineWidth: 0.85)
        context.stroke(originPath, with: .color(ViewportTheme.gridOrigin), lineWidth: 1.05)
        drawGridScaleLabels(grid.scaleLabels, in: &context)
    }

    private func drawGridScaleLabels(
        _ labels: [ViewportProjectedGrid.ScaleLabel],
        in context: inout GraphicsContext
    ) {
        for label in labels {
            context.draw(
                Text(label.text)
                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                    .foregroundStyle(ViewportTheme.gridScaleLabel),
                at: label.position,
                anchor: .center
            )
        }
    }

    private func makeScene() -> ViewportScene {
        ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        )
    }

    private func makeSceneContext(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) -> ViewportSceneContext {
        ViewportSceneContext(
            document: document,
            documentGeneration: documentGeneration,
            size: size,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            evaluationCache: evaluationCache,
            camera: camera,
            basis: basis
        )
    }

    private func makeCoordinateMapper(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) -> ViewportModelCoordinateMapper {
        ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache,
            camera: camera,
            basis: basis
        )
    }

    private func makeLayout(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) -> ViewportLayout {
        makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: basis
        ).layout
    }

    private func drawAxes(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: basis
        )
        let origin = layout.project(.zero)
        let basis = layout.basis
        let planeExtent = hypot(size.width, size.height) * 1.10

        drawAxisLine(
            from: basis.endpoint(from: origin, axis: .x, length: -planeExtent),
            to: basis.endpoint(from: origin, axis: .x, length: planeExtent),
            color: ViewportCoordinateAxis.x.color,
            label: ViewportCoordinateAxis.x.label,
            in: &context
        )
        drawAxisLine(
            from: basis.endpoint(from: origin, axis: .z, length: -planeExtent),
            to: basis.endpoint(from: origin, axis: .z, length: planeExtent),
            color: ViewportCoordinateAxis.z.color,
            label: ViewportCoordinateAxis.z.label,
            in: &context
        )
    }

    private func drawAxisLine(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        label: String,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(path, with: .color(color.opacity(0.46)), lineWidth: 1.5)
        drawAxisLabel(
            label,
            at: CGPoint(x: end.x + 12.0, y: end.y - 8.0),
            color: color,
            in: &context
        )
    }

    private func drawAxisLabel(
        _ label: String,
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        context.draw(
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(0.78)),
            at: point
        )
    }

    private func drawModel(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: basis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let selectedObjectFeatureIDs = selectedObjectFeatureIDs()
        let selectedObjectSceneNodeIDs = sceneNodeIDs(for: objectSelectionTargets())
        let previewObjectFeatureIDs = featureIDs(for: objectSelectionTargets(in: selectionDragPreviewTargets))
        let previewObjectSceneNodeIDs = sceneNodeIDs(for: objectSelectionTargets(in: selectionDragPreviewTargets))
        let selectedTargetFeatureIDs = selectedTargetFeatureIDs()
        let selectedFaceTargets = selectedFaceTargets()
        let previewFaceTargets = faceSelectionTargets(in: selectionDragPreviewTargets)
        let hoveredFaceTarget = hoveredFaceTarget()
        let selectedEdgeTargets = selectedEdgeTargets()
        let previewEdgeTargets = edgeSelectionTargets(in: selectionDragPreviewTargets)
        let hoveredEdgeTarget = hoveredEdgeTarget()
        let selectedVertexTargets = selectedVertexTargets()
        let previewVertexTargets = vertexSelectionTargets(in: selectionDragPreviewTargets)
        let hoveredVertexTarget = hoveredVertexTarget()
        let selectedSketchEntityTargets = selectedSketchEntityTargets()
        let previewSketchEntityTargets = sketchEntitySelectionTargets(in: selectionDragPreviewTargets)
        let selectedSplineControlPointIDs = selectedSplineControlPointIdentities()
        let selectedSplineControlPointGroups = selectedSplineControlPointGroups()
        let selectedSlotWidthSourceTargets = selectedSlotWidthSourceTargets()
        let selectedSketchVertexOffsetSourceTargets = selectedSketchVertexOffsetSourceTargets()
        let hoveredSketchEntityTarget = hoveredSketchEntityTarget()
        let selectedSketchRegionTargets = selectedSketchRegionTargets()
        let previewSketchRegionTargets = sketchRegionSelectionTargets(in: selectionDragPreviewTargets)
        let hoveredSketchRegionTarget = hoveredSketchRegionTarget()
        let hoveredFeatureIDs = hoveredFeatureIDs()
        let hoveredSceneNodeIDs = hoveredSceneNodeIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedObjectFeatureIDs)
        let patternArrayPreviews = ViewportPatternArrayPreviewService().previews(
            document: document,
            scene: scene,
            selection: selection
        )
        let usesSelectionGroup = selectedBodyItems.count > 1
        let suppressedSketchFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedTargetFeatureIDs
        )
        let showsConstructionHighlight = showsConstructionPlaneHover
            && hoveredAffordance == nil
            && pendingAffordance == nil
            && activeAffordanceDrag == nil
        let constructionHit = showsConstructionHighlight ? hoveredCanvasHit : nil
        let constructionModelPoint = showsConstructionHighlight ? hoveredModelPoint : nil

        if constructionHit?.bodyFace == nil,
           constructionHit?.bodyEdge == nil,
           constructionHit?.bodyVertex == nil,
           let constructionModelPoint {
            drawZeroCoordinateFieldHighlight(
                around: constructionModelPoint,
                in: &context,
                layout: layout
            )
        }

        for item in scene.items {
            if case .body = item.kind {
                drawBody(
                    item,
                    in: &context,
                    layout: layout,
                    isSelected: isObjectItem(
                        item,
                        selectedByFeatureIDs: selectedObjectFeatureIDs,
                        selectedBySceneNodeIDs: selectedObjectSceneNodeIDs
                    ) && !usesSelectionGroup,
                    isHovered: hoveredFeatureIDs.contains(item.featureID)
                        || previewObjectFeatureIDs.contains(item.featureID)
                        || item.sceneNodeID.map(hoveredSceneNodeIDs.contains) == true
                        || item.sceneNodeID.map(previewObjectSceneNodeIDs.contains) == true
                )
            }
        }

        for item in scene.items {
            if case .sketch = item.kind,
               !suppressedSketchFeatureIDs.contains(item.featureID) {
                drawSketchRegionHighlights(
                    item,
                    selectedRegionIDs: sketchRegionIDs(
                        in: selectedSketchRegionTargets,
                        featureID: item.featureID
                    ),
                    hoveredRegionIDs: sketchRegionIDs(
                        in: previewSketchRegionTargets
                            + (hoveredSketchRegionTarget.map { [$0] } ?? []),
                        featureID: item.featureID
                    ),
                    layout: layout,
                    in: &context
                )
                drawSketch(
                    item,
                    in: &context,
                    layout: layout,
                    isSelected: isObjectItem(
                        item,
                        selectedByFeatureIDs: selectedObjectFeatureIDs,
                        selectedBySceneNodeIDs: selectedObjectSceneNodeIDs
                    ),
                    isHovered: hoveredFeatureIDs.contains(item.featureID)
                        || item.sceneNodeID.map(hoveredSceneNodeIDs.contains) == true,
                    selectedEntityIDs: sketchEntityIDs(
                        in: selectedSketchEntityTargets,
                        featureID: item.featureID
                    ),
                    selectedSplineControlPointIDs: selectedSplineControlPointIDs,
                    hoveredEntityIDs: sketchEntityIDs(
                        in: previewSketchEntityTargets
                            + (hoveredSketchEntityTarget.map { [$0] } ?? []),
                        featureID: item.featureID
                    )
                )
            }
        }

        drawPatternArrayPreviews(
            patternArrayPreviews,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayCurvePathReplacementPreview(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayLinearAxisAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawIndependentCopyExtrudeDistanceAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawIndependentCopyBodyDimensionAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayRadialAngleAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayCopyCountAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayCurveExtentAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayCurvePathPointAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPatternArrayOutputModeAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawRegionOffsetAffordances(
            targets: selectedSketchRegionTargets,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawSlotWidthAffordances(
            targets: selectedSlotWidthSourceTargets,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawSketchVertexOffsetAffordances(
            targets: selectedSketchVertexOffsetSourceTargets,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawSplineControlPointSlideAffordances(
            groups: selectedSplineControlPointGroups,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawPolySplineSurfaceVertexSlideAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceControlPointSlideAffordances(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawActivePolySplineSurfaceVertexSlidePreview(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawActiveSurfaceControlPointSlidePreview(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawFaceHighlights(
            targets: selectedFaceTargets,
            style: .selected,
            scene: scene,
            layout: layout,
            in: &context
        )

        if let hoveredFaceTarget {
            drawFaceHighlights(
                targets: [hoveredFaceTarget],
                style: .hovered,
                scene: scene,
                layout: layout,
                in: &context
            )
        }
        drawFaceHighlights(
            targets: previewFaceTargets,
            style: .hovered,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawEdgeHighlights(
            targets: selectedEdgeTargets,
            style: .selected,
            scene: scene,
            layout: layout,
            in: &context
        )
        drawEdgeOffsetAffordances(
            targets: selectedEdgeTargets,
            scene: scene,
            layout: layout,
            in: &context
        )

        if let hoveredEdgeTarget {
            drawEdgeHighlights(
                targets: [hoveredEdgeTarget],
                style: .hovered,
                scene: scene,
                layout: layout,
                in: &context
            )
        }
        drawEdgeHighlights(
            targets: previewEdgeTargets,
            style: .hovered,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawVertexHighlights(
            targets: selectedVertexTargets,
            style: .selected,
            scene: scene,
            layout: layout,
            in: &context
        )

        if let hoveredVertexTarget {
            drawVertexHighlights(
                targets: [hoveredVertexTarget],
                style: .hovered,
                scene: scene,
                layout: layout,
                in: &context
            )
        }
        drawVertexHighlights(
            targets: previewVertexTargets,
            style: .hovered,
            scene: scene,
            layout: layout,
            in: &context
        )

        drawGeneratedTopologyHighlights(
            targets: selection.selectedTargets,
            style: .selected,
            scene: scene,
            layout: layout,
            in: &context
        )
        for target in bridgeCurveEndpointHandleTargets(in: scene, layout: layout) {
            drawBridgeCurveEndpointHandle(
                target,
                style: .selected,
                in: &context
            )
        }
        drawActiveBridgeCurveEndpointDrag(in: &context)
        if let hoveredBridgeCurveEndpointHandle {
            drawBridgeCurveEndpointHandle(
                hoveredBridgeCurveEndpointHandle,
                style: .hovered,
                in: &context
            )
        }
        if onPolySplineSurfaceVertexDrag != nil {
            let topologyVertices = polySplineSurfaceTopologyVertices(in: scene)
            for target in polySplineSurfaceVertexHandleTargets(in: scene) {
                drawPolySplineSurfaceVertexHandle(
                    target,
                    style: .selected,
                    topologyVertices: topologyVertices,
                    layout: layout,
                    in: &context
                )
            }
            drawActivePolySplineSurfaceVertexDrag(
                in: &context,
                layout: layout
            )
            if let hoveredPolySplineSurfaceVertex {
                drawPolySplineSurfaceVertexHandle(
                    hoveredPolySplineSurfaceVertex,
                    style: .hovered,
                    topologyVertices: topologyVertices,
                    layout: layout,
                    in: &context
                )
            }
        }
        if onSurfaceControlPointDrag != nil {
            for target in surfaceControlPointHandleTargets(in: scene) {
                drawSurfaceControlPointHandle(
                    target,
                    style: .selected,
                    layout: layout,
                    in: &context
                )
            }
            drawActiveSurfaceControlPointDrag(in: &context, layout: layout)
            if let hoveredSurfaceControlPoint {
                drawSurfaceControlPointHandle(
                    hoveredSurfaceControlPoint,
                    style: .hovered,
                    layout: layout,
                    in: &context
                )
            }
        }
        if onSurfaceTrimEndpointDrag != nil {
            for target in surfaceTrimEndpointHandleTargets(in: scene) {
                drawSurfaceTrimEndpointHandle(
                    target,
                    style: .selected,
                    layout: layout,
                    in: &context
                )
            }
            drawActiveSurfaceTrimEndpointDrag(in: &context, layout: layout)
            if let hoveredSurfaceTrimEndpoint {
                drawSurfaceTrimEndpointHandle(
                    hoveredSurfaceTrimEndpoint,
                    style: .hovered,
                    layout: layout,
                    in: &context
                )
            }
        }
        if onSurfaceTrimControlPointDrag != nil {
            for target in surfaceTrimControlPointHandleTargets(in: scene) {
                drawSurfaceTrimControlPointHandle(
                    target,
                    style: .selected,
                    layout: layout,
                    in: &context
                )
            }
            drawActiveSurfaceTrimControlPointDrag(in: &context, layout: layout)
            if let hoveredSurfaceTrimControlPoint {
                drawSurfaceTrimControlPointHandle(
                    hoveredSurfaceTrimControlPoint,
                    style: .hovered,
                    layout: layout,
                    in: &context
                )
            }
        }

        if let hoveredTarget = selection.hoveredTarget {
            drawGeneratedTopologyHighlights(
                targets: [hoveredTarget],
                style: .hovered,
                scene: scene,
                layout: layout,
                in: &context
            )
        }
        drawGeneratedTopologyHighlights(
            targets: selectionDragPreviewTargets,
            style: .hovered,
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceControlPointDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceTrimEndpointDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceTrimControlPointDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceTrimKnotDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceTrimSpanDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceFrameDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )

        drawSurfaceAnalysisOverlay(
            in: &context,
            layout: layout
        )

        drawSurfaceContinuityOverlay(
            in: &context,
            scene: scene,
            layout: layout
        )

        drawSnapOverlay(
            in: &context,
            layout: layout
        )

        if let constructionHit,
           constructionHit.bodyFace != nil {
            drawConstructionFaceHighlight(
                hit: constructionHit,
                scene: scene,
                layout: layout,
                in: &context
            )
        }

        if allowsObjectAffordances {
            drawSelectionAffordances(
                in: &context,
                scene: scene,
                layout: layout,
                selectedFeatureIDs: selectedObjectFeatureIDs
            )
        }
    }

    private func drawSurfaceAnalysisOverlay(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let overlay = ViewportSurfaceAnalysisOverlay.build(
            result: surfaceAnalysis,
            selection: selection,
            document: document,
            options: surfaceAnalysisOptions
        )
        guard overlay.items.isEmpty == false ||
            overlay.principalDirectionItems.isEmpty == false ||
            overlay.boundaryItems.isEmpty == false else {
            return
        }
        for item in overlay.boundaryItems {
            drawSurfaceAnalysisBoundaryItem(item, in: &context, layout: layout)
        }
        let diagonal = max(Double(hypot(layout.modelBounds.width, layout.modelBounds.height)), 1.0e-6)
        let maxAbsNormalCurvature = overlay.items.map { abs($0.normalCurvature) }.max() ?? 0.0
        if maxAbsNormalCurvature > 1.0e-12 {
            let scale = diagonal * 0.16 / maxAbsNormalCurvature
            for item in overlay.items {
                drawSurfaceAnalysisOverlayItem(
                    item,
                    scale: scale,
                    in: &context,
                    layout: layout
                )
            }
        }

        let maxAbsPrincipalCurvature = overlay.principalDirectionItems.flatMap { item in
            [abs(item.minimumPrincipalCurvature), abs(item.maximumPrincipalCurvature)]
        }.max() ?? 0.0
        guard maxAbsPrincipalCurvature > 1.0e-12 else {
            return
        }
        let principalScale = diagonal * 0.10 / maxAbsPrincipalCurvature
        for item in overlay.principalDirectionItems {
            drawSurfaceAnalysisPrincipalDirectionItem(
                item,
                scale: principalScale,
                in: &context,
                layout: layout
            )
        }
    }

    private func drawSnapOverlay(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let probe = snapOverlayProbe(layout: layout),
              let result = snapResolution(
                  for: probe.point,
                  referencePoint: probe.referencePoint
              ),
              let candidate = result.selectedCandidate,
              shouldDrawSnapOverlay(for: candidate) else {
            return
        }
        let projectedPoint = layout.project(
            CGPoint(x: result.resolvedPoint.x, y: result.resolvedPoint.y)
        )
        let markerRect = CGRect(
            x: projectedPoint.x - 4.0,
            y: projectedPoint.y - 4.0,
            width: 8.0,
            height: 8.0
        )
        let markerPath = Path(ellipseIn: markerRect)
        let accent = Color.cyan
        context.fill(markerPath, with: .color(accent.opacity(0.22)))
        context.stroke(markerPath, with: .color(accent.opacity(0.92)), lineWidth: 1.5)

        var crosshair = Path()
        crosshair.move(to: CGPoint(x: projectedPoint.x - 9.0, y: projectedPoint.y))
        crosshair.addLine(to: CGPoint(x: projectedPoint.x - 5.0, y: projectedPoint.y))
        crosshair.move(to: CGPoint(x: projectedPoint.x + 5.0, y: projectedPoint.y))
        crosshair.addLine(to: CGPoint(x: projectedPoint.x + 9.0, y: projectedPoint.y))
        crosshair.move(to: CGPoint(x: projectedPoint.x, y: projectedPoint.y - 9.0))
        crosshair.addLine(to: CGPoint(x: projectedPoint.x, y: projectedPoint.y - 5.0))
        crosshair.move(to: CGPoint(x: projectedPoint.x, y: projectedPoint.y + 5.0))
        crosshair.addLine(to: CGPoint(x: projectedPoint.x, y: projectedPoint.y + 9.0))
        context.stroke(crosshair, with: .color(accent.opacity(0.84)), lineWidth: 1.0)

        if shouldDrawSnapLabel(for: candidate) {
            let label = Text(candidate.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white)
            let labelPoint = CGPoint(x: projectedPoint.x + 14.0, y: projectedPoint.y - 15.0)
            let backgroundRect = CGRect(
                x: labelPoint.x - 7.0,
                y: labelPoint.y - 10.0,
                width: max(CGFloat(candidate.label.count) * 6.4 + 14.0, 34.0),
                height: 20.0
            )
            context.fill(
                Path(roundedRect: backgroundRect, cornerRadius: 6.0),
                with: .color(Color.black.opacity(0.72))
            )
            context.stroke(
                Path(roundedRect: backgroundRect, cornerRadius: 6.0),
                with: .color(accent.opacity(0.45)),
                lineWidth: 1.0
            )
            context.draw(label, at: labelPoint, anchor: .leading)
        }
    }

    private func shouldDrawSnapOverlay(for candidate: SnapCandidate) -> Bool {
        ViewportSnapOverlayPolicy.drawsOverlay(
            kind: candidate.kind,
            context: snapOverlayContext
        )
    }

    private func shouldDrawSnapLabel(for candidate: SnapCandidate) -> Bool {
        ViewportSnapOverlayPolicy.drawsLabel(
            kind: candidate.kind,
            context: snapOverlayContext
        )
    }

    private var snapOverlayContext: ViewportSnapOverlayContext {
        ViewportSnapOverlayContext(activeCanvasDrag: activeCanvasDrag)
    }

    private func drawReferenceLines(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        guard let anchors = snapResolutionOptions?.referenceLineAnchors,
              !anchors.isEmpty else {
            return
        }
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: basis
        )
        let layout = mapper.layout
        let span = max(layout.modelBounds.width, layout.modelBounds.height, 1.0e-3)
        let minX = layout.modelBounds.minX - span
        let maxX = layout.modelBounds.maxX + span
        let minY = layout.modelBounds.minY - span
        let maxY = layout.modelBounds.maxY + span
        let lineColor = Color.cyan.opacity(0.36)
        let anchorColor = Color.cyan.opacity(0.88)
        let style = StrokeStyle(lineWidth: 1.0, dash: [5.0, 4.0])

        for anchor in anchors {
            var guidePath = Path()
            guidePath.move(
                to: layout.project(
                    CGPoint(x: minX, y: CGFloat(anchor.point.y))
                )
            )
            guidePath.addLine(
                to: layout.project(
                    CGPoint(x: maxX, y: CGFloat(anchor.point.y))
                )
            )
            guidePath.move(
                to: layout.project(
                    CGPoint(x: CGFloat(anchor.point.x), y: minY)
                )
            )
            guidePath.addLine(
                to: layout.project(
                    CGPoint(x: CGFloat(anchor.point.x), y: maxY)
                )
            )
            context.stroke(guidePath, with: .color(lineColor), style: style)

            let projectedAnchor = layout.project(
                CGPoint(x: CGFloat(anchor.point.x), y: CGFloat(anchor.point.y))
            )
            let anchorRect = CGRect(
                x: projectedAnchor.x - 3.0,
                y: projectedAnchor.y - 3.0,
                width: 6.0,
                height: 6.0
            )
            context.fill(Path(ellipseIn: anchorRect), with: .color(anchorColor))
        }
    }

    private func snapOverlayProbe(layout: ViewportLayout) -> (point: Point2D, referencePoint: Point2D?)? {
        if let activeCanvasDrag {
            guard case .creation = activeCanvasDrag.kind else {
                return nil
            }
            let start = layout.unproject(activeCanvasDrag.startLocation)
            let current = layout.unproject(activeCanvasDrag.currentLocation)
            let startPoint = Point2D(x: Double(start.x), y: Double(start.y))
            let currentPoint = Point2D(x: Double(current.x), y: Double(current.y))
            let sketchPlane = activeCanvasDrag.sketchPlane ?? canvasDragSketchPlane(for: hoveredCanvasHit)
            let constrainedPoint = canvasDragAxisConstraint?.constrainedCanvasPoint(
                currentPoint,
                from: startPoint,
                on: sketchPlane
            ) ?? currentPoint
            return (
                point: constrainedPoint,
                referencePoint: startPoint
            )
        }
        guard let hoveredModelPoint else {
            return nil
        }
        return (point: hoveredModelPoint, referencePoint: nil)
    }

    private func snapResolution(
        for point: Point2D,
        referencePoint: Point2D? = nil
    ) -> SnapResolutionResult? {
        guard var snapResolutionOptions else {
            return nil
        }
        if modifierFlags.containsControl {
            snapResolutionOptions.objectTargetingOverride = .forceEnabled
        }
        snapResolutionOptions.referencePoint = referencePoint
        do {
            let result = try SnapResolver().resolve(
                point: point,
                in: document,
                options: snapResolutionOptions
            )
            return result.selectedCandidate == nil ? nil : result
        } catch {
            return nil
        }
    }

    private func publishSnapCandidateKind(_ kind: RupaCore.SnapCandidateKind?) {
        guard reportedSnapCandidateKind != kind else {
            return
        }
        reportedSnapCandidateKind = kind
        onSnapCandidateKindChange?(kind)
    }

    private func refreshSnapCandidateKind(size: CGSize) {
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        guard let probe = snapOverlayProbe(layout: mapper.layout),
              let result = snapResolution(
                  for: probe.point,
                  referencePoint: probe.referencePoint
              ) else {
            publishSnapCandidateKind(nil)
            return
        }
        publishSnapCandidateKind(
            ViewportSnapOverlayPolicy.publishedKind(
                result.selectedCandidate?.kind,
                context: snapOverlayContext
            )
        )
    }

    private func captureReferenceLineAnchor(at point: CGPoint, size: CGSize) -> Bool {
        guard let onReferenceLineAnchor else {
            return false
        }
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let modelPoint = mapper.modelPoint(for: point)
        guard let resolution = snapResolution(for: modelPoint),
              let selectedCandidate = resolution.selectedCandidate,
              selectedCandidate.kind.isReferenceLineAnchorSource else {
            return false
        }
        return onReferenceLineAnchor(selectedCandidate.point)
    }

    private func drawSurfaceAnalysisBoundaryItem(
        _ item: ViewportSurfaceAnalysisOverlay.BoundaryItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let first = item.points.first else {
            return
        }
        var path = Path()
        path.move(to: layout.project(first))
        for point in item.points.dropFirst() {
            path.addLine(to: layout.project(point))
        }
        if item.isClosed {
            path.closeSubpath()
        }
        context.stroke(
            path,
            with: .color(surfaceAnalysisBoundaryColor(for: item).opacity(0.78)),
            lineWidth: item.role == .outer ? 1.25 : 1.0
        )
    }

    private func surfaceAnalysisBoundaryColor(
        for item: ViewportSurfaceAnalysisOverlay.BoundaryItem
    ) -> Color {
        switch item.role {
        case .outer:
            return ViewportTheme.surfaceAnalysisBoundaryOuter
        case .inner:
            return ViewportTheme.surfaceAnalysisBoundaryInner
        }
    }

    private func drawSurfaceAnalysisOverlayItem(
        _ item: ViewportSurfaceAnalysisOverlay.Item,
        scale: Double,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let start = layout.project(item.position)
        let endPoint = Point3D(
            x: item.position.x + item.normal.x * item.normalCurvature * scale,
            y: item.position.y + item.normal.y * item.normalCurvature * scale,
            z: item.position.z + item.normal.z * item.normalCurvature * scale
        )
        let end = layout.project(endPoint)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(surfaceAnalysisColor(for: item).opacity(0.48)),
            lineWidth: item.direction == .u ? 0.85 : 0.7
        )
    }

    private func surfaceAnalysisColor(
        for item: ViewportSurfaceAnalysisOverlay.Item
    ) -> Color {
        switch item.direction {
        case .u:
            return ViewportTheme.surfaceAnalysisU
        case .v:
            return ViewportTheme.surfaceAnalysisV
        }
    }

    private func drawSurfaceAnalysisPrincipalDirectionItem(
        _ item: ViewportSurfaceAnalysisOverlay.PrincipalDirectionItem,
        scale: Double,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        drawSurfaceAnalysisPrincipalDirectionSegment(
            position: item.position,
            direction: item.minimumPrincipalDirection,
            curvature: item.minimumPrincipalCurvature,
            color: ViewportTheme.surfaceAnalysisPrincipalMinimum,
            scale: scale,
            in: &context,
            layout: layout
        )
        drawSurfaceAnalysisPrincipalDirectionSegment(
            position: item.position,
            direction: item.maximumPrincipalDirection,
            curvature: item.maximumPrincipalCurvature,
            color: ViewportTheme.surfaceAnalysisPrincipalMaximum,
            scale: scale,
            in: &context,
            layout: layout
        )
    }

    private func drawSurfaceAnalysisPrincipalDirectionSegment(
        position: Point3D,
        direction: Vector3D,
        curvature: Double,
        color: Color,
        scale: Double,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let halfLength = abs(curvature) * scale * 0.5
        guard halfLength > 1.0e-12, direction.length > 1.0e-12 else {
            return
        }
        let offset = Vector3D(
            x: direction.x * halfLength,
            y: direction.y * halfLength,
            z: direction.z * halfLength
        )
        let start = layout.project(Point3D(
            x: position.x - offset.x,
            y: position.y - offset.y,
            z: position.z - offset.z
        ))
        let end = layout.project(Point3D(
            x: position.x + offset.x,
            y: position.y + offset.y,
            z: position.z + offset.z
        ))
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color.opacity(0.52)),
            lineWidth: 0.75
        )
    }

    private func drawSurfaceContinuityOverlay(
        in context: inout GraphicsContext,
        scene: ViewportScene,
        layout: ViewportLayout
    ) {
        let overlay = ViewportSurfaceContinuityOverlay.build(
            result: surfaceContinuity,
            scene: scene,
            selection: selection,
            document: document
        )
        guard overlay.items.isEmpty == false else {
            return
        }

        for item in overlay.items {
            drawSurfaceContinuityOverlayItem(
                item,
                in: &context,
                layout: layout
            )
        }
    }

    private func drawSurfaceContinuityOverlayItem(
        _ item: ViewportSurfaceContinuityOverlay.Item,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let start = layout.project(item.start)
        let end = layout.project(item.end)
        let midpoint = layout.project(item.midpoint)
        let color = surfaceContinuityColor(for: item)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color.opacity(0.94)),
            style: StrokeStyle(
                lineWidth: item.requiresCurvatureContinuitySolve ? 4.0 : 3.2,
                lineCap: .round,
                dash: item.requiresCurvatureContinuitySolve ? [6.0, 4.0] : []
            )
        )
        drawTransformHandle(at: start, style: .vertex, isHighlighted: true, in: &context)
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
        drawSurfaceContinuityLabel(
            surfaceContinuityLabel(for: item),
            at: CGPoint(x: midpoint.x, y: midpoint.y - 18.0),
            color: color,
            in: &context
        )
    }

    private func drawSurfaceContinuityLabel(
        _ label: String,
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let rect = surfaceContinuityLabelRect(for: label, at: point)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 6.0),
            with: .color(Color(red: 0.07, green: 0.085, blue: 0.09).opacity(0.90))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 6.0),
            with: .color(color.opacity(0.88)),
            lineWidth: 1.0
        )
        context.draw(
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(ViewportTheme.dimensionText),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func surfaceContinuityLabelRect(for label: String, at point: CGPoint) -> CGRect {
        let width = max(44.0, CGFloat(label.count) * 6.2 + 14.0)
        let height: CGFloat = 20.0
        return CGRect(
            x: point.x - width / 2.0,
            y: point.y - height / 2.0,
            width: width,
            height: height
        )
    }

    private func surfaceContinuityColor(
        for item: ViewportSurfaceContinuityOverlay.Item
    ) -> Color {
        if item.requiresCurvatureContinuitySolve {
            return ViewportTheme.surfaceContinuitySolveRequired
        }
        switch item.continuity {
        case .disconnected:
            return ViewportTheme.surfaceContinuityDisconnected
        case .g0:
            return ViewportTheme.surfaceContinuityPosition
        case .g1:
            return ViewportTheme.surfaceContinuityTangent
        case .g2:
            return ViewportTheme.surfaceContinuityCurvature
        }
    }

    private func surfaceContinuityLabel(
        for item: ViewportSurfaceContinuityOverlay.Item
    ) -> String {
        let title: String
        switch item.continuity {
        case .disconnected:
            title = "DISCONNECTED"
        case .g0:
            title = "G0"
        case .g1:
            title = "G1"
        case .g2:
            title = "G2"
        }
        guard item.requiresCurvatureContinuitySolve else {
            return title
        }
        return "\(title) / G2 required"
    }

    private func suppressedSketchFeatureIDs(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> Set<FeatureID> {
        Set(
            scene.items.compactMap { item -> FeatureID? in
                guard case .body = item.kind,
                      selectedFeatureIDs.contains(item.featureID) || editedBodies[item.featureID] != nil else {
                    return nil
                }
                return item.sourceFeatureID
            }
        )
    }

    private func sceneBySuppressingSketches(
        _ scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> ViewportScene {
        let suppressedFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        guard !suppressedFeatureIDs.isEmpty else {
            return scene
        }
        return ViewportScene(
            items: scene.items.filter { item in
                if case .sketch = item.kind {
                    return !suppressedFeatureIDs.contains(item.featureID)
                }
                return true
            }
        )
    }

    private func drawSketchRegionHighlights(
        _ item: ViewportSceneItem,
        selectedRegionIDs: Set<SelectionComponentID>,
        hoveredRegionIDs: Set<SelectionComponentID>,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard selectedRegionIDs.isEmpty == false || hoveredRegionIDs.isEmpty == false else {
            return
        }
        for region in item.sketchRegions {
            let isSelected = selectedRegionIDs.contains(region.componentID)
            let isHovered = hoveredRegionIDs.contains(region.componentID)
            guard isSelected || isHovered else {
                continue
            }
            let projectedPoints = region.points.map(layout.project)
            guard projectedPoints.count >= 3 else {
                continue
            }
            let color = isSelected ? ViewportTheme.selection : ViewportTheme.hover
            let fillOpacity = isSelected ? 0.16 : 0.10
            let strokeOpacity = isSelected ? 0.86 : 0.66
            let lineWidth = isSelected ? 2.2 : 1.6
            let highlightPath = path(for: projectedPoints)
            context.fill(highlightPath, with: .color(color.opacity(fillOpacity)))
            context.stroke(
                highlightPath,
                with: .color(color.opacity(strokeOpacity)),
                lineWidth: lineWidth
            )
        }
    }

    private func drawRegionOffsetAffordances(
        targets: [ViewportSketchRegionSelectionTarget],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onRegionOffsetDrag != nil, targets.isEmpty == false else {
            return
        }
        for candidate in regionOffsetAffordanceCandidates(
            targets: targets,
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activeRegionOffsetDrag?.target.identity == identity
                ? activeRegionOffsetDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredRegionOffsetHandle?.identity == identity
                || pendingRegionOffsetHandle?.identity == identity
                || activeRegionOffsetDrag?.target.identity == identity
            drawRegionOffsetAffordance(
                candidate,
                distanceMeters: dragDistance,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawRegionOffsetAffordance(
        _ candidate: ViewportRegionOffsetAffordanceCandidate,
        distanceMeters: Double?,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters ?? 0.0
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard let distanceMeters else {
            return
        }
        let label = "\(distanceMeters < 0.0 ? "-" : "")\(formattedViewportLength(abs(distanceMeters)))"
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            label,
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: true,
            in: &context
        )
    }

    private func drawEdgeOffsetAffordances(
        targets: [ViewportEdgeSelectionTarget],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onEdgeOffsetDrag != nil, targets.isEmpty == false else {
            return
        }
        for candidate in edgeOffsetAffordanceCandidates(
            targets: targets,
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activeEdgeOffsetDrag?.target.identity == identity
                ? activeEdgeOffsetDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredEdgeOffsetHandle?.identity == identity
                || pendingEdgeOffsetHandle?.identity == identity
                || activeEdgeOffsetDrag?.target.identity == identity
            drawEdgeOffsetAffordance(
                candidate,
                distanceMeters: dragDistance ?? candidate.geometry.baseDistanceMeters,
                showsLabel: dragDistance != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawEdgeOffsetAffordance(
        _ candidate: ViewportEdgeOffsetAffordanceCandidate,
        distanceMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let start = candidate.geometry.baseProjectedPoint
        let end = candidate.geometry.projectedTip(distanceMeters: distanceMeters)
        let previewSegment = candidate.geometry.previewSegment(distanceMeters: distanceMeters)
        var previewPath = Path()
        previewPath.move(to: previewSegment.start)
        previewPath.addLine(to: previewSegment.end)
        context.stroke(
            previewPath,
            with: .color(Color.black.opacity(isHighlighted ? 0.42 : 0.28)),
            style: StrokeStyle(lineWidth: isHighlighted ? 4.8 : 3.4, lineCap: .round)
        )
        context.stroke(
            previewPath,
            with: .color(ViewportTheme.surfaceEdit.opacity(isHighlighted ? 0.96 : 0.72)),
            style: StrokeStyle(lineWidth: isHighlighted ? 2.4 : 1.7, lineCap: .round, dash: [5.0, 4.0])
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            formattedViewportLength(distanceMeters),
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawSlotWidthAffordances(
        targets: [ViewportSlotWidthSourceTarget],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onSlotWidthDrag != nil, targets.isEmpty == false else {
            return
        }
        for candidate in slotWidthAffordanceCandidates(
            targets: targets,
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragWidth = activeSlotWidthDrag?.target.identity == identity
                ? activeSlotWidthDrag?.widthMeters
                : nil
            let isHighlighted = hoveredSlotWidthHandle?.identity == identity
                || pendingSlotWidthHandle?.identity == identity
                || activeSlotWidthDrag?.target.identity == identity
            drawSlotWidthAffordance(
                candidate,
                widthMeters: dragWidth ?? slotWidthMeters,
                showsLabel: dragWidth != nil || isHighlighted,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawSlotWidthAffordance(
        _ candidate: ViewportSlotWidthAffordanceCandidate,
        widthMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            widthMeters: widthMeters
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            formattedViewportLength(widthMeters),
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawSketchVertexOffsetAffordances(
        targets: [ViewportSketchVertexOffsetSourceTarget],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onSketchVertexOffsetDrag != nil, targets.isEmpty == false else {
            return
        }
        for candidate in sketchVertexOffsetAffordanceCandidates(
            targets: targets,
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activeSketchVertexOffsetDrag?.target.identity == identity
                ? activeSketchVertexOffsetDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredSketchVertexOffsetHandle?.identity == identity
                || pendingSketchVertexOffsetHandle?.identity == identity
                || activeSketchVertexOffsetDrag?.target.identity == identity
            drawSketchVertexOffsetAffordance(
                candidate,
                distanceMeters: dragDistance ?? sketchVertexOffsetDistanceMeters,
                showsLabel: dragDistance != nil || isHighlighted,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawSketchVertexOffsetAffordance(
        _ candidate: ViewportSketchVertexOffsetAffordanceCandidate,
        distanceMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .vertex,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            formattedViewportLength(distanceMeters),
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawSplineControlPointSlideAffordances(
        groups: [ViewportSplineControlPointGroup],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onSplineControlPointSlideDrag != nil, groups.isEmpty == false else {
            return
        }
        for candidate in splineControlPointSlideAffordanceCandidates(
            groups: groups,
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activeSplineControlPointSlideDrag?.target.identity == identity
                ? activeSplineControlPointSlideDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredSplineControlPointSlideHandle?.identity == identity
                || pendingSplineControlPointSlideHandle?.identity == identity
                || activeSplineControlPointSlideDrag?.target.identity == identity
            let showsOriginalComparison = modifierFlags.containsControl
                && activeSplineControlPointSlideDrag?.target.identity == identity
            drawSplineControlPointSlideAffordance(
                candidate,
                distanceMeters: dragDistance,
                showsOriginalComparison: showsOriginalComparison,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawSplineControlPointSlideAffordance(
        _ candidate: ViewportSplineControlPointSlideAffordanceCandidate,
        distanceMeters: Double?,
        showsOriginalComparison: Bool,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .vertex,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard let distanceMeters else {
            return
        }
        let labelPrefix = showsOriginalComparison ? "Original " : ""
        let label = "\(labelPrefix)\(slideDirectionTitle(candidate.target.direction)) \(formattedViewportLength(abs(distanceMeters)))"
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            label,
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: true,
            in: &context
        )
    }

    private func drawPolySplineSurfaceVertexSlideAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPolySplineSurfaceVertexSlideDrag != nil else {
            return
        }
        for candidate in polySplineSurfaceVertexSlideAffordanceCandidates(
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activePolySplineSurfaceVertexSlideDrag?.target.identity == identity
                ? activePolySplineSurfaceVertexSlideDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredPolySplineSurfaceVertexSlideHandle?.identity == identity
                || pendingPolySplineSurfaceVertexSlideHandle?.identity == identity
                || activePolySplineSurfaceVertexSlideDrag?.target.identity == identity
            let showsOriginalComparison = modifierFlags.containsControl
                && activePolySplineSurfaceVertexSlideDrag?.target.identity == identity
            drawPolySplineSurfaceVertexSlideAffordance(
                candidate,
                distanceMeters: dragDistance,
                showsOriginalComparison: showsOriginalComparison,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawPolySplineSurfaceVertexSlideAffordance(
        _ candidate: ViewportPolySplineSurfaceVertexSlideAffordanceCandidate,
        distanceMeters: Double?,
        showsOriginalComparison: Bool,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .vertex,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard let distanceMeters else {
            return
        }
        let labelPrefix = showsOriginalComparison ? "Original " : ""
        let label = "\(labelPrefix)\(slideDirectionTitle(candidate.target.direction)) \(formattedViewportLength(abs(distanceMeters)))"
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            label,
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: true,
            in: &context
        )
    }

    private func drawSurfaceControlPointSlideAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onSurfaceControlPointSlideDrag != nil else {
            return
        }
        for candidate in surfaceControlPointSlideAffordanceCandidates(
            scene: scene,
            layout: layout
        ) {
            let identity = candidate.target.identity
            let dragDistance = activeSurfaceControlPointSlideDrag?.target.identity == identity
                ? activeSurfaceControlPointSlideDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredSurfaceControlPointSlideHandle?.identity == identity
                || pendingSurfaceControlPointSlideHandle?.identity == identity
                || activeSurfaceControlPointSlideDrag?.target.identity == identity
            let showsOriginalComparison = modifierFlags.containsControl
                && activeSurfaceControlPointSlideDrag?.target.identity == identity
            drawSurfaceControlPointSlideAffordance(
                candidate,
                distanceMeters: dragDistance,
                showsOriginalComparison: showsOriginalComparison,
                isHighlighted: isHighlighted,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawSurfaceControlPointSlideAffordance(
        _ candidate: ViewportSurfaceControlPointSlideAffordanceCandidate,
        distanceMeters: Double?,
        showsOriginalComparison: Bool,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(candidate.geometry.baseModelPoint)
        let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        )
        drawArrow(
            from: start,
            to: end,
            color: ViewportTheme.surfaceEdit,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .vertex,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard let distanceMeters else {
            return
        }
        let labelPrefix = showsOriginalComparison ? "Original " : ""
        let label = "\(labelPrefix)\(slideDirectionTitle(candidate.target.direction)) \(formattedViewportLength(abs(distanceMeters)))"
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            label,
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: ViewportTheme.surfaceEdit,
            isHighlighted: true,
            in: &context
        )
    }

    private func drawActivePolySplineSurfaceVertexSlidePreview(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let activePolySplineSurfaceVertexSlideDrag else {
            return
        }
        let targetSet = Set(activePolySplineSurfaceVertexSlideDrag.target.targets)
        let selectedInputs = polySplineSurfaceVertexSlideInputs(in: scene).filter { input in
            targetSet.contains(input.selectionTarget)
        }
        guard let previewVertices = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewVertices(
            selectedVertices: selectedInputs,
            topologyVertices: polySplineSurfaceTopologyVertices(in: scene),
            direction: activePolySplineSurfaceVertexSlideDrag.target.direction,
            distanceMeters: activePolySplineSurfaceVertexSlideDrag.distanceMeters
        ) else {
            return
        }
        let showsOriginalComparison = modifierFlags.containsControl
        let color = ViewportTheme.surfaceEdit
        if let previewSurfaces = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewSurfaces(
            selectedVertices: selectedInputs,
            topologyVertices: polySplineSurfaceTopologyVertices(in: scene),
            direction: activePolySplineSurfaceVertexSlideDrag.target.direction,
            distanceMeters: activePolySplineSurfaceVertexSlideDrag.distanceMeters
        ) {
            for surface in previewSurfaces {
                drawPolySplineSurfaceVertexSlidePreviewMesh(
                    showsOriginalComparison ? surface.originalMesh : surface.movedMesh,
                    color: color,
                    showsOriginalComparison: showsOriginalComparison,
                    layout: layout,
                    in: &context
                )
            }
        }
        for vertex in previewVertices {
            let original = layout.project(vertex.originalPoint)
            let displayedPoint = showsOriginalComparison ? vertex.originalPoint : vertex.movedPoint
            let displayed = layout.project(displayedPoint)
            if !showsOriginalComparison {
                var path = Path()
                path.move(to: original)
                path.addLine(to: displayed)
                context.stroke(
                    path,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5.0, 4.0])
                )
            }
            drawTransformHandle(
                at: displayed,
                style: .vertex,
                isHighlighted: true,
                in: &context
            )
        }
    }

    private func drawActiveSurfaceControlPointSlidePreview(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let activeSurfaceControlPointSlideDrag else {
            return
        }
        let targetSet = Set(activeSurfaceControlPointSlideDrag.target.targets)
        let selectedInputs = surfaceControlPointSlideInputs(in: scene).filter { input in
            targetSet.contains(input.target)
        }
        guard let previewVertices = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewControlPoints(
            selectedControlPoints: selectedInputs,
            topologyVertices: polySplineSurfaceTopologyVertices(in: scene),
            direction: activeSurfaceControlPointSlideDrag.target.direction,
            distanceMeters: activeSurfaceControlPointSlideDrag.distanceMeters
        ) else {
            return
        }
        let showsOriginalComparison = modifierFlags.containsControl
        let color = ViewportTheme.surfaceEdit
        for vertex in previewVertices {
            let original = layout.project(vertex.originalPoint)
            let displayedPoint = showsOriginalComparison ? vertex.originalPoint : vertex.movedPoint
            let displayed = layout.project(displayedPoint)
            if !showsOriginalComparison {
                var path = Path()
                path.move(to: original)
                path.addLine(to: displayed)
                context.stroke(
                    path,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5.0, 4.0])
                )
            }
            drawTransformHandle(
                at: displayed,
                style: .vertex,
                isHighlighted: true,
                in: &context
            )
        }
    }

    private func drawPolySplineSurfaceVertexSlidePreviewMesh(
        _ mesh: ViewportBodyMesh,
        color: Color,
        showsOriginalComparison: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let fillOpacity = showsOriginalComparison ? 0.06 : 0.20
        let strokeOpacity = showsOriginalComparison ? 0.82 : 0.58
        var index = 0
        while index + 2 < mesh.indices.count {
            let firstIndex = Int(mesh.indices[index])
            let secondIndex = Int(mesh.indices[index + 1])
            let thirdIndex = Int(mesh.indices[index + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                index += 3
                continue
            }

            var path = Path()
            path.move(to: layout.project(mesh.positions[firstIndex]))
            path.addLine(to: layout.project(mesh.positions[secondIndex]))
            path.addLine(to: layout.project(mesh.positions[thirdIndex]))
            path.closeSubpath()
            if !showsOriginalComparison {
                context.fill(path, with: .color(color.opacity(fillOpacity)))
            }
            context.stroke(
                path,
                with: .color(color.opacity(strokeOpacity)),
                style: StrokeStyle(
                    lineWidth: showsOriginalComparison ? 1.2 : 0.85,
                    lineJoin: .round,
                    dash: showsOriginalComparison ? [4.0, 4.0] : []
                )
            )
            index += 3
        }
    }

    private func slideDirectionTitle(_ direction: SplineControlPointSlideDirection) -> String {
        switch direction {
        case .positiveU:
            return "U+"
        case .negativeU:
            return "U-"
        case .normal:
            return "N"
        }
    }

    private func slideDirectionTitle(_ direction: PolySplineSurfaceVertexSlideDirection) -> String {
        switch direction {
        case .positiveU:
            return "U+"
        case .negativeU:
            return "U-"
        case .normal:
            return "N"
        case .positiveV:
            return "V+"
        case .negativeV:
            return "V-"
        }
    }

    private func surfaceFrameAxisTitle(_ axis: ViewportSurfaceFrameAxis) -> String {
        switch axis {
        case .u:
            return "U"
        case .v:
            return "V"
        case .normal:
            return "N"
        }
    }

    private func drawSketch(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        selectedEntityIDs: Set<SketchEntityID> = [],
        selectedSplineControlPointIDs: Set<ViewportSplineControlPointIdentity> = [],
        hoveredEntityIDs: Set<SketchEntityID> = []
    ) {
        guard case .sketch(let primitives) = item.kind else {
            return
        }

        for primitive in primitives {
            let isEntitySelected = selectedEntityIDs.contains(primitive.entityID)
            let isEntityHovered = hoveredEntityIDs.contains(primitive.entityID)
            let strokeColor = if isEntitySelected || isSelected {
                ViewportTheme.selection
            } else if isEntityHovered || isHovered {
                ViewportTheme.hover
            } else {
                ViewportTheme.sketch
            }
            let strokeWidth: CGFloat = if isEntitySelected || isSelected {
                4.0
            } else if isEntityHovered || isHovered {
                3.4
            } else {
                2.5
            }
            switch primitive {
            case .point(let entityID, let point):
                let displayedPoint = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .point,
                    point: point
                )
                let projected = layout.project(displayedPoint)
                let rect = CGRect(
                    x: projected.x - 3.0,
                    y: projected.y - 3.0,
                    width: 6.0,
                    height: 6.0
                )
                context.fill(Path(ellipseIn: rect), with: .color(strokeColor.opacity(0.92)))
                if isEntitySelected || isEntityHovered {
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .point,
                        point: displayedPoint,
                        layout: layout,
                        in: &context
                    )
                }
            case .line(let entityID, let start, let end):
                let displayedStart = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .lineStart,
                    point: start
                )
                let displayedEnd = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .lineEnd,
                    point: end
                )
                let displayedLine = displayedSketchDimensionLine(
                    featureID: item.featureID,
                    entityID: entityID,
                    start: displayedStart,
                    end: displayedEnd
                )
                var path = Path()
                path.move(to: layout.project(displayedLine.start))
                path.addLine(to: layout.project(displayedLine.end))
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
                let showsPointDisplay = showsPointDisplay(
                    featureID: item.featureID,
                    entityID: entityID,
                    isSelected: isEntitySelected,
                    isHovered: isEntityHovered
                )
                if showsPointDisplay {
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .lineStart,
                        point: displayedLine.start,
                        layout: layout,
                        in: &context
                    )
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .lineEnd,
                        point: displayedLine.end,
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected {
                    drawLineDimensionCallout(
                        featureID: item.featureID,
                        entityID: entityID,
                        start: displayedLine.start,
                        end: displayedLine.end,
                        layout: layout,
                        color: strokeColor,
                        in: &context
                    )
                }
            case .circle(let entityID, let circleCenter, let radiusMeters):
                let displayedCenter = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .circleCenter,
                    point: circleCenter
                )
                let displayedRadius = displayedSketchCurveRadius(
                    featureID: item.featureID,
                    entityID: entityID,
                    fallbackRadiusMeters: radiusMeters
                )
                let path = projectedCirclePath(
                    center: displayedCenter,
                    radiusMeters: displayedRadius,
                    layout: layout
                )
                context.fill(path, with: .color(strokeColor.opacity(isEntitySelected || isSelected ? 0.16 : 0.10)))
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
                let curvatureDisplay = curveCurvatureDisplay(
                    featureID: item.featureID,
                    entityID: entityID
                )
                let showsPointDisplay = showsPointDisplay(
                    featureID: item.featureID,
                    entityID: entityID,
                    isSelected: isEntitySelected,
                    isHovered: isEntityHovered
                )
                if showsPointDisplay {
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .circleCenter,
                        point: displayedCenter,
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected || isEntityHovered {
                    drawSketchCurveHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .circleRadius,
                        point: circleRadiusHandlePoint(
                            center: displayedCenter,
                            radiusMeters: displayedRadius
                        ),
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected || isEntityHovered || curvatureDisplay != nil {
                    drawCurveCurvatureComb(
                        primitive: .circle(
                            entityID: entityID,
                            center: displayedCenter,
                            radiusMeters: displayedRadius
                        ),
                        combScale: curvatureDisplay?.combScale ?? CurveCurvatureDisplay.defaultCombScale,
                        color: strokeColor,
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected {
                    drawCircleDimensionCallout(
                        featureID: item.featureID,
                        entityID: entityID,
                        center: displayedCenter,
                        radiusMeters: displayedRadius,
                        layout: layout,
                        color: strokeColor,
                        in: &context
                    )
                }
            case .arc(let entityID, let center, let radiusMeters, let startAngle, let endAngle):
                let displayedCenter = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .arcCenter,
                    point: center
                )
                let displayedArc = displayedSketchArcParameters(
                    featureID: item.featureID,
                    entityID: entityID,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                )
                let path = projectedArcPath(
                    center: displayedCenter,
                    radiusMeters: displayedArc.radiusMeters,
                    startAngleRadians: displayedArc.startAngleRadians,
                    endAngleRadians: displayedArc.endAngleRadians,
                    layout: layout
                )
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
                let displayedArcStart = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .arcStart,
                    point: pointOnSketchCircle(
                        center: displayedCenter,
                        radiusMeters: displayedArc.radiusMeters,
                        angleRadians: displayedArc.startAngleRadians
                    )
                )
                let displayedArcEnd = displayedSketchPointHandlePoint(
                    featureID: item.featureID,
                    entityID: entityID,
                    handle: .arcEnd,
                    point: pointOnSketchCircle(
                        center: displayedCenter,
                        radiusMeters: displayedArc.radiusMeters,
                        angleRadians: displayedArc.endAngleRadians
                    )
                )
                let curvatureDisplay = curveCurvatureDisplay(
                    featureID: item.featureID,
                    entityID: entityID
                )
                let showsPointDisplay = showsPointDisplay(
                    featureID: item.featureID,
                    entityID: entityID,
                    isSelected: isEntitySelected,
                    isHovered: isEntityHovered
                )
                if showsPointDisplay {
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcCenter,
                        point: displayedCenter,
                        layout: layout,
                        in: &context
                    )
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcStart,
                        point: displayedArcStart,
                        layout: layout,
                        in: &context
                    )
                    drawSketchPointHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcEnd,
                        point: displayedArcEnd,
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected || isEntityHovered {
                    drawSketchCurveHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcRadius,
                        point: arcRadiusHandlePoint(
                            center: displayedCenter,
                            radiusMeters: displayedArc.radiusMeters,
                            startAngleRadians: displayedArc.startAngleRadians,
                            endAngleRadians: displayedArc.endAngleRadians
                        ),
                        layout: layout,
                        in: &context
                    )
                    drawSketchCurveHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcStartAngle,
                        point: pointOnSketchCircle(
                            center: displayedCenter,
                            radiusMeters: displayedArc.radiusMeters,
                            angleRadians: displayedArc.startAngleRadians
                        ),
                        layout: layout,
                        in: &context
                    )
                    drawSketchCurveHandle(
                        featureID: item.featureID,
                        entityID: entityID,
                        handle: .arcEndAngle,
                        point: pointOnSketchCircle(
                            center: displayedCenter,
                            radiusMeters: displayedArc.radiusMeters,
                            angleRadians: displayedArc.endAngleRadians
                        ),
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected || isEntityHovered || curvatureDisplay != nil {
                    drawCurveCurvatureComb(
                        primitive: .arc(
                            entityID: entityID,
                            center: displayedCenter,
                            radiusMeters: displayedArc.radiusMeters,
                            startAngleRadians: displayedArc.startAngleRadians,
                            endAngleRadians: displayedArc.endAngleRadians
                        ),
                        combScale: curvatureDisplay?.combScale ?? CurveCurvatureDisplay.defaultCombScale,
                        color: strokeColor,
                        layout: layout,
                        in: &context
                    )
                }
                if isEntitySelected {
                    drawArcDimensionCallout(
                        featureID: item.featureID,
                        entityID: entityID,
                        center: displayedCenter,
                        radiusMeters: displayedArc.radiusMeters,
                        startAngleRadians: displayedArc.startAngleRadians,
                        endAngleRadians: displayedArc.endAngleRadians,
                        layout: layout,
                        color: strokeColor,
                        in: &context
                    )
                }
            case .spline(let entityID, let points, let controlPoints, let sketchPlane):
                let displayedControlPoints = displayedSplineControlPoints(
                    featureID: item.featureID,
                    entityID: entityID,
                    controlPoints: controlPoints
                )
                let displayedPoints = displayedControlPoints == controlPoints
                    ? points
                    : splineSamplePoints(controlPoints: displayedControlPoints)
                guard displayedPoints.count >= 2 else {
                    continue
                }
                var path = Path()
                path.move(to: layout.project(displayedPoints[0]))
                for point in displayedPoints.dropFirst() {
                    path.addLine(to: layout.project(point))
                }
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
                let curvatureDisplay = curveCurvatureDisplay(
                    featureID: item.featureID,
                    entityID: entityID
                )
                if isEntitySelected || isEntityHovered || curvatureDisplay != nil {
                    drawCurveCurvatureComb(
                        primitive: .spline(
                            entityID: entityID,
                            points: displayedPoints,
                            controlPoints: displayedControlPoints,
                            sketchPlane: sketchPlane
                        ),
                        combScale: curvatureDisplay?.combScale ?? CurveCurvatureDisplay.defaultCombScale,
                        color: strokeColor,
                        layout: layout,
                        in: &context
                    )
                }
                if showsPointDisplay(
                    featureID: item.featureID,
                    entityID: entityID,
                    isSelected: isEntitySelected,
                    isHovered: isEntityHovered
                ) {
                    drawSplineControlPointHandles(
                        featureID: item.featureID,
                        entityID: entityID,
                        controlPoints: displayedControlPoints,
                        color: strokeColor,
                        layout: layout,
                        selectedControlPointIDs: selectedSplineControlPointIDs,
                        in: &context
                    )
                }
            }
        }
    }

    private func displayedSketchCurveRadius(
        featureID: FeatureID,
        entityID: SketchEntityID,
        fallbackRadiusMeters: Double
    ) -> Double {
        let identity = ViewportSketchCurveHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: .circleRadius
        )
        guard activeSketchCurveHandleDrag?.target.identity == identity,
              let radiusMeters = activeSketchCurveHandleDrag?.radiusMeters else {
            let dimensionIdentity = ViewportSketchDimensionIdentity(
                featureID: featureID,
                entityID: entityID,
                kind: .radius
            )
            guard activeSketchDimensionDrag?.target.identity == dimensionIdentity,
                  let dimensionValue = activeSketchDimensionDrag?.value else {
                return fallbackRadiusMeters
            }
            return dimensionValue
        }
        return radiusMeters
    }

    private func displayedSketchDimensionLine(
        featureID: FeatureID,
        entityID: SketchEntityID,
        start: CGPoint,
        end: CGPoint
    ) -> (start: CGPoint, end: CGPoint) {
        let identity = ViewportSketchDimensionIdentity(
            featureID: featureID,
            entityID: entityID,
            kind: .length
        )
        guard activeSketchDimensionDrag?.target.identity == identity,
              let lengthValue = activeSketchDimensionDrag?.value else {
            let angleIdentity = ViewportSketchDimensionIdentity(
                featureID: featureID,
                entityID: entityID,
                kind: .angle
            )
            guard activeSketchDimensionDrag?.target.identity == angleIdentity,
                  let angleValue = activeSketchDimensionDrag?.value else {
                return (start, end)
            }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let currentLength = hypot(dx, dy)
            guard currentLength > 1.0e-12 else {
                return (start, end)
            }
            let length = CGFloat(currentLength)
            return (
                start,
                CGPoint(
                    x: start.x + cos(CGFloat(angleValue)) * length,
                    y: start.y + sin(CGFloat(angleValue)) * length
                )
            )
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let currentLength = hypot(dx, dy)
        guard currentLength > 1.0e-12 else {
            return (start, end)
        }
        let length = CGFloat(max(lengthValue, 1.0e-9))
        return (
            start,
            CGPoint(
                x: start.x + dx / currentLength * length,
                y: start.y + dy / currentLength * length
            )
        )
    }

    private func displayedSketchArcParameters(
        featureID: FeatureID,
        entityID: SketchEntityID,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> (radiusMeters: Double, startAngleRadians: Double, endAngleRadians: Double) {
        guard let activeSketchCurveHandleDrag,
              activeSketchCurveHandleDrag.target.featureID == featureID,
              activeSketchCurveHandleDrag.target.entityID == entityID else {
            let dimensionIdentity = ViewportSketchDimensionIdentity(
                featureID: featureID,
                entityID: entityID,
                kind: .radius
            )
            guard activeSketchDimensionDrag?.target.identity == dimensionIdentity,
                  let dimensionValue = activeSketchDimensionDrag?.value else {
                let angleIdentity = ViewportSketchDimensionIdentity(
                    featureID: featureID,
                    entityID: entityID,
                    kind: .angle
                )
                guard activeSketchDimensionDrag?.target.identity == angleIdentity,
                      let angleValue = activeSketchDimensionDrag?.value else {
                    return (radiusMeters, startAngleRadians, endAngleRadians)
                }
                return (radiusMeters, startAngleRadians, startAngleRadians + angleValue)
            }
            return (dimensionValue, startAngleRadians, endAngleRadians)
        }
        return (
            activeSketchCurveHandleDrag.radiusMeters ?? radiusMeters,
            activeSketchCurveHandleDrag.startAngleRadians ?? startAngleRadians,
            activeSketchCurveHandleDrag.endAngleRadians ?? endAngleRadians
        )
    }

    private func drawSketchCurveHandle(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: ViewportSketchCurveHandleKind,
        point: CGPoint,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        drawTransformHandle(
            at: layout.project(point),
            style: .vertex,
            isHighlighted: isSketchCurveHandleHighlighted(
                featureID: featureID,
                entityID: entityID,
                handle: handle
            ),
            in: &context
        )
    }

    private func isSketchCurveHandleHighlighted(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: ViewportSketchCurveHandleKind
    ) -> Bool {
        let identity = ViewportSketchCurveHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
        return activeSketchCurveHandleDrag?.target.identity == identity
            || hoveredSketchCurveHandle?.identity == identity
    }

    private func isSketchDimensionHighlighted(
        featureID: FeatureID,
        entityID: SketchEntityID,
        kind: SketchEntityDimensionKind
    ) -> Bool {
        let identity = ViewportSketchDimensionIdentity(
            featureID: featureID,
            entityID: entityID,
            kind: kind
        )
        return activeSketchDimensionDrag?.target.identity == identity
            || hoveredSketchDimension?.identity == identity
    }

    private func circleRadiusHandlePoint(
        center: CGPoint,
        radiusMeters: Double
    ) -> CGPoint {
        pointOnSketchCircle(
            center: center,
            radiusMeters: radiusMeters,
            angleRadians: 0.0
        )
    }

    private func arcRadiusHandlePoint(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> CGPoint {
        let midpointAngle = startAngleRadians
            + normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians) / 2.0
        return pointOnSketchCircle(
            center: center,
            radiusMeters: radiusMeters,
            angleRadians: midpointAngle
        )
    }

    private func pointOnSketchCircle(
        center: CGPoint,
        radiusMeters: Double,
        angleRadians: Double
    ) -> CGPoint {
        let radius = CGFloat(max(radiusMeters, 1.0e-12))
        return CGPoint(
            x: center.x + cos(CGFloat(angleRadians)) * radius,
            y: center.y + sin(CGFloat(angleRadians)) * radius
        )
    }

    private func drawLineDimensionCallout(
        featureID: FeatureID,
        entityID: SketchEntityID,
        start: CGPoint,
        end: CGPoint,
        layout: ViewportLayout,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let projectedStart = layout.project(start)
        let projectedEnd = layout.project(end)
        let midpoint = lineDimensionMidpoint(start: projectedStart, end: projectedEnd)
        let labelPoint = lineDimensionLabelPoint(start: projectedStart, end: projectedEnd)
        drawDimensionLeader(from: midpoint, to: labelPoint, color: color, in: &context)
        let length = hypot(Double(end.x - start.x), Double(end.y - start.y))
        let angle = atan2(Double(end.y - start.y), Double(end.x - start.x))
        drawDimensionLabel(
            "L \(formattedViewportLength(length)) / A \(formattedViewportAngle(angle))",
            at: labelPoint,
            color: color,
            isHighlighted: isSketchDimensionHighlighted(
                featureID: featureID,
                entityID: entityID,
                kind: .length
            ) || isSketchDimensionHighlighted(
                featureID: featureID,
                entityID: entityID,
                kind: .angle
            ),
            in: &context
        )
    }

    private func drawCircleDimensionCallout(
        featureID: FeatureID,
        entityID: SketchEntityID,
        center: CGPoint,
        radiusMeters: Double,
        layout: ViewportLayout,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let radiusPoint = circleRadiusHandlePoint(
            center: center,
            radiusMeters: radiusMeters
        )
        let projectedCenter = layout.project(center)
        let projectedRadius = layout.project(radiusPoint)
        drawDimensionLeader(from: projectedCenter, to: projectedRadius, color: color, in: &context)
        drawDimensionLabel(
            "R \(formattedViewportLength(radiusMeters))",
            at: circleDimensionLabelPoint(radiusPoint: projectedRadius),
            color: color,
            isHighlighted: isSketchDimensionHighlighted(
                featureID: featureID,
                entityID: entityID,
                kind: .radius
            ),
            in: &context
        )
    }

    private func drawArcDimensionCallout(
        featureID: FeatureID,
        entityID: SketchEntityID,
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        layout: ViewportLayout,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
        let radiusPoint = arcRadiusHandlePoint(
            center: center,
            radiusMeters: radiusMeters,
            startAngleRadians: startAngleRadians,
            endAngleRadians: endAngleRadians
        )
        let projectedCenter = layout.project(center)
        let projectedRadius = layout.project(radiusPoint)
        let labelPoint = arcDimensionLabelPoint(center: projectedCenter, radiusPoint: projectedRadius)
        drawDimensionLeader(from: projectedCenter, to: projectedRadius, color: color, in: &context)
        drawDimensionLeader(from: projectedRadius, to: labelPoint, color: color, in: &context)
        drawDimensionLabel(
            "R \(formattedViewportLength(radiusMeters)) / A \(formattedViewportAngle(span))",
            at: labelPoint,
            color: color,
            isHighlighted: isSketchDimensionHighlighted(
                featureID: featureID,
                entityID: entityID,
                kind: .radius
            ) || isSketchDimensionHighlighted(
                featureID: featureID,
                entityID: entityID,
                kind: .angle
            ),
            in: &context
        )
    }

    private func drawDimensionLeader(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color.opacity(0.52)),
            style: StrokeStyle(lineWidth: 1.0, dash: [3.0, 3.0])
        )
    }

    private func drawDimensionLabel(
        _ label: String,
        at point: CGPoint,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let rect = dimensionLabelRect(for: label, at: point)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 7.0),
            with: .color(
                isHighlighted
                    ? ViewportTheme.dimensionLabelBackgroundHighlighted
                    : ViewportTheme.dimensionLabelBackground
            )
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 7.0),
            with: .color(color.opacity(isHighlighted ? 0.95 : 0.68)),
            lineWidth: isHighlighted ? 1.4 : 0.9
        )
        context.draw(
            Text(label)
                .font(.system(size: 11.0, weight: .semibold, design: .rounded))
                .foregroundStyle(ViewportTheme.dimensionText),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func dimensionLabelRect(for label: String, at point: CGPoint) -> CGRect {
        let width = max(52.0, CGFloat(label.count) * 6.4 + 16.0)
        let height: CGFloat = 22.0
        return CGRect(
            x: point.x - width / 2.0,
            y: point.y - height / 2.0,
            width: width,
            height: height
        )
    }

    private func lineDimensionMidpoint(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2.0,
            y: (start.y + end.y) / 2.0
        )
    }

    private func lineDimensionLabelPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        let midpoint = lineDimensionMidpoint(start: start, end: end)
        let direction = normalizedVector(
            from: start,
            to: end,
            fallback: CGVector(dx: 1.0, dy: 0.0)
        )
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        return CGPoint(
            x: midpoint.x + normal.dx * 26.0,
            y: midpoint.y + normal.dy * 26.0
        )
    }

    private func circleDimensionLabelPoint(radiusPoint: CGPoint) -> CGPoint {
        CGPoint(x: radiusPoint.x + 34.0, y: radiusPoint.y - 18.0)
    }

    private func arcDimensionLabelPoint(center: CGPoint, radiusPoint: CGPoint) -> CGPoint {
        let direction = normalizedVector(
            from: center,
            to: radiusPoint,
            fallback: CGVector(dx: 1.0, dy: 0.0)
        )
        return CGPoint(
            x: radiusPoint.x + direction.dx * 34.0,
            y: radiusPoint.y + direction.dy * 34.0
        )
    }

    private func formattedViewportLength(_ meters: Double) -> String {
        ViewportLengthLabelFormatter.string(
            fromMeters: meters,
            preferredUnit: document.displayUnit
        )
    }

    private func formattedViewportAngle(_ radians: Double) -> String {
        let degrees = radians * 180.0 / Double.pi
        return "\(degrees.formatted(.number.precision(.fractionLength(0...1)))) deg"
    }

    private func normalizedVector(
        from start: CGPoint,
        to end: CGPoint,
        fallback: CGVector
    ) -> CGVector {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1.0e-9 else {
            return fallback
        }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private func displayedSketchPointHandlePoint(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle,
        point: CGPoint
    ) -> CGPoint {
        let identity = ViewportSketchPointHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
        guard activeSketchPointHandleDrag?.target.identity == identity,
              let viewportDelta = activeSketchPointHandleDrag?.viewportDelta else {
            return point
        }
        return CGPoint(
            x: point.x + viewportDelta.x,
            y: point.y + viewportDelta.y
        )
    }

    private func drawSketchPointHandle(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle,
        point: CGPoint,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        drawTransformHandle(
            at: layout.project(point),
            style: .vertex,
            isHighlighted: isSketchPointHandleHighlighted(
                featureID: featureID,
                entityID: entityID,
                handle: handle
            ),
            in: &context
        )
    }

    private func isSketchPointHandleHighlighted(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle
    ) -> Bool {
        let identity = ViewportSketchPointHandleIdentity(
            featureID: featureID,
            entityID: entityID,
            handle: handle
        )
        return activeSketchPointHandleDrag?.target.identity == identity
            || hoveredSketchPointHandle?.identity == identity
    }

    private func displayedSplineControlPoints(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPoints: [CGPoint]
    ) -> [CGPoint] {
        if let activeSplineControlPointDrag,
           activeSplineControlPointDrag.target.featureID == featureID,
           activeSplineControlPointDrag.target.entityID == entityID,
           controlPoints.indices.contains(activeSplineControlPointDrag.target.controlPointIndex) {
            var updatedControlPoints = controlPoints
            updatedControlPoints[activeSplineControlPointDrag.target.controlPointIndex].x += activeSplineControlPointDrag.viewportDelta.x
            updatedControlPoints[activeSplineControlPointDrag.target.controlPointIndex].y += activeSplineControlPointDrag.viewportDelta.y
            return updatedControlPoints
        }

        guard let activeSplineControlPointSlideDrag,
              !modifierFlags.containsControl,
              activeSplineControlPointSlideDrag.target.featureID == featureID,
              activeSplineControlPointSlideDrag.target.entityID == entityID,
              let previewControlPoints = ViewportSplineControlPointSlideAffordanceGeometry.previewControlPoints(
                controlPoints: controlPoints,
                selectedIndexes: activeSplineControlPointSlideDrag.target.controlPointIndexes,
                direction: activeSplineControlPointSlideDrag.target.direction,
                distanceMeters: activeSplineControlPointSlideDrag.distanceMeters
              ) else {
            return controlPoints
        }
        return previewControlPoints
    }

    private func drawSplineControlPointHandles(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPoints: [CGPoint],
        color: Color,
        layout: ViewportLayout,
        selectedControlPointIDs: Set<ViewportSplineControlPointIdentity>,
        in context: inout GraphicsContext
    ) {
        guard !controlPoints.isEmpty else {
            return
        }
        var controlPath = Path()
        controlPath.move(to: layout.project(controlPoints[0]))
        for point in controlPoints.dropFirst() {
            controlPath.addLine(to: layout.project(point))
        }
        context.stroke(
            controlPath,
            with: .color(color.opacity(0.38)),
            style: StrokeStyle(lineWidth: 1.1, dash: [4.0, 3.0])
        )
        for (index, point) in controlPoints.enumerated() {
            drawTransformHandle(
                at: layout.project(point),
                style: .vertex,
                isHighlighted: isSplineControlPointHighlighted(
                    featureID: featureID,
                    entityID: entityID,
                    controlPointIndex: index,
                    selectedControlPointIDs: selectedControlPointIDs
                ),
                in: &context
            )
        }
    }

    private func drawCurveCurvatureComb(
        primitive: ViewportSketchPrimitive,
        combScale: Double,
        color _: Color,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let comb = ViewportCurveCurvatureComb(primitive: primitive) else {
            return
        }
        let scale = comb.displayScale(scaleFactor: combScale)
        guard scale > 0.0 else {
            return
        }

        var spinePath = Path()
        var hasSpineStart = false
        for sample in comb.samples {
            let samplePoint = CGPoint(
                x: CGFloat(sample.point.x),
                y: CGFloat(sample.point.y)
            )
            let end = CGPoint(
                x: CGFloat(sample.point.x + sample.normal.x * sample.curvature * scale),
                y: CGFloat(sample.point.y + sample.normal.y * sample.curvature * scale)
            )
            let projectedPoint = layout.project(samplePoint)
            let projectedEnd = layout.project(end)
            var combLine = Path()
            combLine.move(to: projectedPoint)
            combLine.addLine(to: projectedEnd)
            context.stroke(
                combLine,
                with: .color(.white.opacity(0.58)),
                lineWidth: 0.8
            )

            if hasSpineStart {
                spinePath.addLine(to: projectedEnd)
            } else {
                spinePath.move(to: projectedEnd)
                hasSpineStart = true
            }
        }
        context.stroke(
            spinePath,
            with: .color(.red.opacity(0.72)),
            style: StrokeStyle(lineWidth: 1.0, dash: [2.0, 3.0])
        )
    }

    private func curveCurvatureDisplay(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) -> CurveCurvatureDisplay? {
        curveCurvatureDisplays[
            .sketchEntity(featureID: featureID, entityID: entityID)
        ]
    }

    private func pointDisplay(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) -> PointDisplay? {
        pointDisplays[
            .sketchEntity(featureID: featureID, entityID: entityID)
        ]
    }

    private func showsPointDisplay(
        featureID: FeatureID,
        entityID: SketchEntityID,
        isSelected: Bool,
        isHovered: Bool
    ) -> Bool {
        if let display = pointDisplay(featureID: featureID, entityID: entityID) {
            return display.isVisible
        }
        return isSelected || isHovered
    }

    private func allowsPointHandleInteraction(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) -> Bool {
        pointDisplay(featureID: featureID, entityID: entityID)?.mode != .hidden
    }

    private func sketchControlPointHitPolicy(
        for scene: ViewportScene
    ) -> ViewportSketchControlPointHitPolicy {
        var targets: Set<ViewportSketchControlPointHitPolicy.Target> = []
        for item in scene.items {
            guard case .sketch(let primitives) = item.kind else {
                continue
            }
            for primitive in primitives {
                guard case .spline(let entityID, _, _, _) = primitive,
                      allowsPointHandleInteraction(
                        featureID: item.featureID,
                        entityID: entityID
                      ) else {
                    continue
                }
                targets.insert(
                    ViewportSketchControlPointHitPolicy.Target(
                        featureID: item.featureID,
                        entityID: entityID
                    )
                )
            }
        }
        return .only(targets)
    }

    private func isSplineControlPointHighlighted(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPointIndex: Int,
        selectedControlPointIDs: Set<ViewportSplineControlPointIdentity>
    ) -> Bool {
        let target = ViewportSplineControlPointIdentity(
            featureID: featureID,
            entityID: entityID,
            controlPointIndex: controlPointIndex
        )
        return selectedControlPointIDs.contains(target)
            || activeSplineControlPointDrag?.target.identity == target
            || hoveredSplineControlPoint?.identity == target
    }

    private func splineSamplePoints(controlPoints: [CGPoint]) -> [CGPoint] {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        var samples: [CGPoint] = []
        let samplesPerSegment = 32
        for segmentStart in stride(from: 0, to: controlPoints.count - 1, by: 3) {
            let p0 = controlPoints[segmentStart]
            let p1 = controlPoints[segmentStart + 1]
            let p2 = controlPoints[segmentStart + 2]
            let p3 = controlPoints[segmentStart + 3]
            for index in 0 ... samplesPerSegment {
                if segmentStart > 0, index == 0 {
                    continue
                }
                let t = CGFloat(index) / CGFloat(samplesPerSegment)
                samples.append(cubicBezierPoint(p0, p1, p2, p3, t: t))
            }
        }
        return samples
    }

    private func cubicBezierPoint(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let oneMinusT = 1.0 - t
        let b0 = oneMinusT * oneMinusT * oneMinusT
        let b1 = 3.0 * oneMinusT * oneMinusT * t
        let b2 = 3.0 * oneMinusT * t * t
        let b3 = t * t * t
        return CGPoint(
            x: p0.x * b0 + p1.x * b1 + p2.x * b2 + p3.x * b3,
            y: p0.y * b0 + p1.y * b1 + p2.y * b2 + p3.y * b3
        )
    }

    private func projectedCirclePath(
        center: CGPoint,
        radiusMeters: Double,
        layout: ViewportLayout
    ) -> Path {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        var path = Path()

        for index in 0 ... 96 {
            let angle = CGFloat(index) / 96.0 * CGFloat.pi * 2.0
            let modelPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let projectedPoint = layout.project(modelPoint)
            if index == 0 {
                path.move(to: projectedPoint)
            } else {
                path.addLine(to: projectedPoint)
            }
        }
        path.closeSubpath()
        return path
    }

    private func projectedArcPath(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        layout: ViewportLayout
    ) -> Path {
        var path = Path()
        for (index, projectedPoint) in projectedArcPoints(
            center: center,
            radiusMeters: radiusMeters,
            startAngleRadians: startAngleRadians,
            endAngleRadians: endAngleRadians,
            layout: layout,
            segmentCount: 96
        ).enumerated() {
            if index == 0 {
                path.move(to: projectedPoint)
            } else {
                path.addLine(to: projectedPoint)
            }
        }
        return path
    }

    private func drawBody(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool
    ) {
        guard case .body(let component) = item.kind else {
            return
        }
        if let mesh = component.mesh {
            drawBodyMesh(
                mesh,
                item: item,
                in: &context,
                layout: layout,
                isSelected: isSelected,
                isHovered: isHovered
            )
            return
        }
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        let fillColor = isSelected ? ViewportTheme.selection : ViewportTheme.bodySurface
        drawProjectedBox(
            edit.projectedBox(layout: layout),
            color: fillColor,
            isHighlighted: isSelected || isHovered,
            fillOpacity: isSelected ? 0.44 : 0.52,
            in: &context
        )
    }

    private func drawBodyMesh(
        _ mesh: ViewportBodyMesh,
        item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool
    ) {
        let baseColor = isSelected ? ViewportTheme.selection : ViewportTheme.bodySurface
        let fillOpacity = isSelected ? 0.28 : 0.22
        let strokeOpacity = isSelected || isHovered ? 0.62 : 0.26
        var index = 0
        while index + 2 < mesh.indices.count {
            let firstIndex = Int(mesh.indices[index])
            let secondIndex = Int(mesh.indices[index + 1])
            let thirdIndex = Int(mesh.indices[index + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                index += 3
                continue
            }

            var path = Path()
            path.move(to: layout.project(mesh.positions[firstIndex], in: item))
            path.addLine(to: layout.project(mesh.positions[secondIndex], in: item))
            path.addLine(to: layout.project(mesh.positions[thirdIndex], in: item))
            path.closeSubpath()
            context.fill(path, with: .color(baseColor.opacity(fillOpacity)))
            context.stroke(path, with: .color(baseColor.opacity(strokeOpacity)), lineWidth: isSelected ? 1.1 : 0.7)
            index += 3
        }
    }

    private func bodyProjection(
        for item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> ViewportBodyProjection? {
        guard case .body = item.kind else {
            return nil
        }
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        return edit.projectedBodyProjection(layout: layout)
    }

    private func drawZeroCoordinateFieldHighlight(
        around modelPoint: Point2D,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard modelPoint.x.isFinite,
              modelPoint.y.isFinite else {
            return
        }

        let step = constructionFieldStep(for: layout)
        let minX = floor(CGFloat(modelPoint.x) / step) * step
        let minY = floor(CGFloat(modelPoint.y) / step) * step
        let fieldBounds = CGRect(
            x: minX,
            y: minY,
            width: step,
            height: step
        )
        let footprint = layout.projectedFootprint(fieldBounds)
        let highlightPath = path(for: footprint)

        context.fill(highlightPath, with: .color(Color.cyan.opacity(0.12)))
        context.stroke(highlightPath, with: .color(Color.cyan.opacity(0.62)), lineWidth: 1.6)
    }

    private func constructionFieldStep(for layout: ViewportLayout) -> CGFloat {
        var step = max(CGFloat(document.ruler.majorTickMeters), 1.0e-12)
        while step * layout.scale < 42.0 {
            step *= 2.0
        }
        return step
    }

    private func drawConstructionFaceHighlight(
        hit: ViewportHit,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let face = hit.bodyFace,
              let item = scene.items.first(where: { item in
                  if let sceneNodeID = hit.sceneNodeID {
                      return item.sceneNodeID == sceneNodeID && item.featureID == hit.featureID
                  }
                  return item.featureID == hit.featureID
              }),
              let projection = bodyProjection(for: item, layout: layout) else {
            return
        }

        let footprint = projection.footprint(for: face)
        let highlightPath = path(for: footprint)
        context.fill(highlightPath, with: .color(Color.cyan.opacity(0.22)))
        context.stroke(highlightPath, with: .color(Color.cyan.opacity(0.96)), lineWidth: 2.4)
    }

    private func drawFaceHighlights(
        targets: [ViewportFaceSelectionTarget],
        style: ViewportFaceHighlightStyle,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for target in targets {
            guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }

            let footprint = projection.footprint(for: target.face)
            let highlightPath = path(for: footprint)
            let color = style.color
            context.fill(highlightPath, with: .color(color.opacity(style.fillOpacity)))
            context.stroke(highlightPath, with: .color(color.opacity(style.strokeOpacity)), lineWidth: style.lineWidth)
        }
    }

    private func drawEdgeHighlights(
        targets: [ViewportEdgeSelectionTarget],
        style: ViewportFaceHighlightStyle,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for target in targets {
            guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }

            let segment = projection.segment(for: target.edge)
            var path = Path()
            path.move(to: segment.start)
            path.addLine(to: segment.end)
            let color = style.color
            context.stroke(path, with: .color(color.opacity(style.strokeOpacity)), lineWidth: style.lineWidth + 1.8)
            drawTransformHandle(at: segment.start, style: .vertex, isHighlighted: true, in: &context)
            drawTransformHandle(at: segment.end, style: .vertex, isHighlighted: true, in: &context)
            if style == .selected, onEdgeFilletDrag != nil {
                drawEdgeFilletHandle(
                    at: edgeFilletHandlePoint(projection: projection, edge: target.edge),
                    isHighlighted: isEdgeFilletAffordanceHovered(
                        featureID: target.featureID,
                        edge: target.edge
                    ),
                    in: &context
                )
            }
        }
    }

    private func drawVertexHighlights(
        targets: [ViewportVertexSelectionTarget],
        style: ViewportFaceHighlightStyle,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for target in targets {
            guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }

            let point = projection.point(for: target.vertex)
            drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
            let radius: CGFloat = style == .selected ? 9.0 : 7.0
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(style.color.opacity(style.strokeOpacity)),
                lineWidth: style.lineWidth
            )
        }
    }

    private func drawGeneratedTopologyHighlights(
        targets: [SelectionTarget],
        style: ViewportFaceHighlightStyle,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for target in targets {
            guard let item = sceneItem(for: target, in: scene),
                  case .body(let component) = item.kind,
                  let topology = component.topology else {
                continue
            }
            switch target.component {
            case .object, .sketchEntity, .region, .constructionPlane:
                continue
            case .face(let componentID):
                guard componentID.generatedTopologyPersistentName != nil,
                      let face = topology.faces.first(where: { $0.componentID == componentID }) else {
                    continue
                }
                drawGeneratedFaceHighlight(
                    face,
                    item: item,
                    style: style,
                    layout: layout,
                    in: &context
                )
            case .edge(let componentID):
                guard componentID.generatedTopologyPersistentName != nil,
                      let edge = topology.edges.first(where: { $0.componentID == componentID }) else {
                    continue
                }
                drawGeneratedEdgeHighlight(
                    edge,
                    item: item,
                    style: style,
                    layout: layout,
                    in: &context
                )
            case .vertex(let componentID):
                guard componentID.generatedTopologyPersistentName != nil,
                      let vertex = topology.vertices.first(where: { $0.componentID == componentID }) else {
                    continue
                }
                drawGeneratedVertexHighlight(
                    vertex,
                    item: item,
                    style: style,
                    layout: layout,
                    in: &context
                )
            }
        }
    }

    private func drawGeneratedFaceHighlight(
        _ face: ViewportBodyTopology.Face,
        item: ViewportSceneItem,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let polygon = face.points.map { layout.project($0, in: item) }
        let highlightPath = path(for: polygon)
        context.fill(highlightPath, with: .color(style.color.opacity(style.fillOpacity)))
        context.stroke(
            highlightPath,
            with: .color(style.color.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
    }

    private func drawGeneratedEdgeHighlight(
        _ edge: ViewportBodyTopology.Edge,
        item: ViewportSceneItem,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let start = layout.project(edge.start, in: item)
        let end = layout.project(edge.end, in: item)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(style.color.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth + 1.8
        )
        drawTransformHandle(at: start, style: .vertex, isHighlighted: true, in: &context)
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
    }

    private func drawGeneratedVertexHighlight(
        _ vertex: ViewportBodyTopology.Vertex,
        item: ViewportSceneItem,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(vertex.point, in: item)
        drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
        let radius: CGFloat = style == .selected ? 9.0 : 7.0
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(style.color.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
    }

    private func drawSurfaceControlPointDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceControlPointDisplays {
                drawSurfaceControlPointDisplay(
                    display,
                    item: item,
                    layout: layout,
                    isSelected: selection.selectedReferences.contains(display.selectionReference),
                    isHovered: selection.hoveredReference == display.selectionReference,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceControlPointDisplay(
        _ display: ViewportSurfaceControlPointDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(display.point, in: item)
        let baseSize: CGFloat = display.isBoundary ? 7.0 : 8.6
        let size: CGFloat = if isSelected {
            baseSize + 4.0
        } else if isHovered {
            baseSize + 2.4
        } else {
            baseSize
        }
        let color = isSelected ? ViewportTheme.selection : (isHovered ? ViewportTheme.hover : ViewportTheme.surfaceEdit)
        let rect = CGRect(
            x: point.x - size / 2.0,
            y: point.y - size / 2.0,
            width: size,
            height: size
        )
        let path = Path(roundedRect: rect, cornerRadius: 1.6)
        context.fill(path, with: .color(color.opacity(isSelected || isHovered ? 0.92 : 0.78)))
        context.stroke(
            path,
            with: .color(Color.black.opacity(isSelected || isHovered ? 0.62 : 0.48)),
            lineWidth: isSelected ? 1.4 : 0.9
        )
        if display.isBoundary == false {
            let ringRect = rect.insetBy(dx: -2.4, dy: -2.4)
            context.stroke(
                Path(ellipseIn: ringRect),
                with: .color(color.opacity(isSelected || isHovered ? 0.56 : 0.38)),
                lineWidth: isSelected ? 1.4 : 1.0
            )
        }
    }

    private func drawSurfaceTrimEndpointDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceTrimEndpointDisplays {
                drawSurfaceTrimEndpointDisplay(
                    display,
                    item: item,
                    layout: layout,
                    isSelected: selection.selectedReferences.contains(display.selectionReference),
                    isHovered: selection.hoveredReference == display.selectionReference,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceTrimEndpointDisplay(
        _ display: ViewportSurfaceTrimEndpointDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(display.point, in: item)
        let size: CGFloat = if isSelected {
            10.0
        } else if isHovered {
            8.4
        } else {
            6.6
        }
        let color = isSelected ? ViewportTheme.selection : (isHovered ? ViewportTheme.hover : ViewportTheme.surfaceEdit)
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - size / 2.0))
        path.addLine(to: CGPoint(x: point.x + size / 2.0, y: point.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y + size / 2.0))
        path.addLine(to: CGPoint(x: point.x - size / 2.0, y: point.y))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(isSelected || isHovered ? 0.9 : 0.64)))
        context.stroke(
            path,
            with: .color(Color.black.opacity(isSelected || isHovered ? 0.64 : 0.46)),
            lineWidth: isSelected ? 1.3 : 0.85
        )
    }

    private func drawSurfaceTrimControlPointDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceTrimControlPointDisplays {
                drawSurfaceTrimControlPointDisplay(
                    display,
                    item: item,
                    layout: layout,
                    isSelected: selection.selectedReferences.contains(display.selectionReference),
                    isHovered: selection.hoveredReference == display.selectionReference,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceTrimControlPointDisplay(
        _ display: ViewportSurfaceTrimControlPointDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(display.point, in: item)
        let radius: CGFloat = if isSelected {
            5.8
        } else if isHovered {
            4.8
        } else {
            3.8
        }
        let color = isSelected ? ViewportTheme.selection : (isHovered ? ViewportTheme.hover : ViewportTheme.surfaceEdit)
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .color(color.opacity(isSelected || isHovered ? 0.86 : 0.58))
        )
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: -2.0, dy: -2.0)),
            with: .color(color.opacity(isSelected || isHovered ? 0.52 : 0.34)),
            lineWidth: isSelected ? 1.25 : 0.9
        )
        let tickLength = radius + 2.2
        var tickPath = Path()
        tickPath.move(to: CGPoint(x: point.x - tickLength, y: point.y))
        tickPath.addLine(to: CGPoint(x: point.x + tickLength, y: point.y))
        tickPath.move(to: CGPoint(x: point.x, y: point.y - tickLength))
        tickPath.addLine(to: CGPoint(x: point.x, y: point.y + tickLength))
        context.stroke(
            tickPath,
            with: .color(Color.black.opacity(isSelected || isHovered ? 0.48 : 0.32)),
            lineWidth: isSelected ? 1.0 : 0.7
        )
    }

    private func drawSurfaceTrimKnotDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceTrimKnotDisplays {
                drawSurfaceTrimKnotDisplay(
                    display,
                    item: item,
                    layout: layout,
                    isSelected: selection.selectedReferences.contains(display.selectionReference),
                    isHovered: selection.hoveredReference == display.selectionReference,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceTrimKnotDisplay(
        _ display: ViewportSurfaceTrimKnotDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(display.point, in: item)
        let size: CGFloat = if isSelected {
            8.8
        } else if isHovered {
            7.4
        } else {
            5.4
        }
        let color = isSelected ? ViewportTheme.selection : (isHovered ? ViewportTheme.hover : ViewportTheme.surfaceEdit)
        let rect = CGRect(
            x: point.x - size * 0.5,
            y: point.y - size * 0.5,
            width: size,
            height: size
        )
        context.fill(
            Path(rect),
            with: .color(color.opacity(isSelected || isHovered ? 0.86 : 0.5))
        )
        context.stroke(
            Path(rect),
            with: .color(Color.black.opacity(isSelected || isHovered ? 0.58 : 0.34)),
            lineWidth: isSelected ? 1.2 : 0.8
        )
    }

    private func drawSurfaceTrimSpanDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceTrimSpanDisplays {
                drawSurfaceTrimSpanDisplay(
                    display,
                    item: item,
                    layout: layout,
                    isSelected: selection.selectedReferences.contains(display.selectionReference),
                    isHovered: selection.hoveredReference == display.selectionReference,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceTrimSpanDisplay(
        _ display: ViewportSurfaceTrimSpanDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        let point = layout.project(display.point, in: item)
        let radius: CGFloat = if isSelected {
            4.8
        } else if isHovered {
            4.0
        } else {
            2.9
        }
        let color = isSelected ? ViewportTheme.selection : (isHovered ? ViewportTheme.hover : ViewportTheme.surfaceEdit)
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(color.opacity(isSelected || isHovered ? 0.86 : 0.54)),
            lineWidth: isSelected ? 1.4 : 0.9
        )
    }

    private func drawSurfaceFrameDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let dragTargets = selectedSurfaceFrameControlPointReferences()
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceFrameDisplays {
                drawSurfaceFrameDisplay(
                    display,
                    item: item,
                    dragTargets: dragTargets,
                    layout: layout,
                    in: &context
                )
            }
        }
    }

    private func drawSurfaceFrameDisplay(
        _ display: ViewportSurfaceFrameDisplay,
        item: ViewportSceneItem,
        dragTargets: [SelectionReference],
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let origin = layout.project(display.position, in: item)
        drawSurfaceFrameAxis(
            origin: origin,
            direction: display.uAxis,
            item: item,
            display: display,
            axis: .u,
            dragTargets: dragTargets,
            layout: layout,
            color: ViewportCoordinateAxis.x.color,
            in: &context
        )
        drawSurfaceFrameAxis(
            origin: origin,
            direction: display.vAxis,
            item: item,
            display: display,
            axis: .v,
            dragTargets: dragTargets,
            layout: layout,
            color: ViewportCoordinateAxis.y.color,
            in: &context
        )
        drawSurfaceFrameAxis(
            origin: origin,
            direction: display.normal,
            item: item,
            display: display,
            axis: .normal,
            dragTargets: dragTargets,
            layout: layout,
            color: ViewportCoordinateAxis.z.color,
            in: &context
        )
        let radius: CGFloat = 3.4
        let rect = CGRect(
            x: origin.x - radius,
            y: origin.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .color(ViewportTheme.surfaceEdit.opacity(0.82))
        )
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: -1.7, dy: -1.7)),
            with: .color(Color.black.opacity(0.42)),
            lineWidth: 0.9
        )
    }

    private func drawSurfaceFrameAxis(
        origin: CGPoint,
        direction: Vector3D,
        item: ViewportSceneItem,
        display: ViewportSurfaceFrameDisplay,
        axis: ViewportSurfaceFrameAxis,
        dragTargets: [SelectionReference],
        layout: ViewportLayout,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let identity = ViewportSurfaceFrameHandleIdentity(
            targets: dragTargets,
            displayID: display.id,
            axis: axis
        )
        let dragDistance = activeSurfaceFrameDrag?.target.identity == identity
            ? activeSurfaceFrameDrag?.distanceMeters
            : nil
        let isHighlighted = hoveredSurfaceFrameHandle?.identity == identity
            || pendingSurfaceFrameHandle?.identity == identity
            || activeSurfaceFrameDrag?.target.identity == identity
        guard let end = surfaceFrameAxisEnd(
            origin: origin,
            direction: direction,
            item: item,
            display: display,
            distanceMeters: dragDistance,
            layout: layout
        ) else {
            return
        }
        var path = Path()
        path.move(to: origin)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color.opacity(isHighlighted ? 0.96 : 0.82)),
            style: StrokeStyle(lineWidth: isHighlighted ? 3.0 : 2.0, lineCap: .round)
        )
        let headRadius: CGFloat = isHighlighted ? 3.6 : 2.4
        let headRect = CGRect(
            x: end.x - headRadius,
            y: end.y - headRadius,
            width: headRadius * 2.0,
            height: headRadius * 2.0
        )
        context.fill(Path(ellipseIn: headRect), with: .color(color.opacity(0.88)))

        guard let dragDistance else {
            return
        }
        let vector = CGVector(dx: end.x - origin.x, dy: end.y - origin.y)
        let direction2D = vector.length > 1.0e-9 ? vector.normalized : CGVector(dx: 1.0, dy: 0.0)
        let normal2D = CGVector(dx: -direction2D.dy, dy: direction2D.dx)
        drawDimensionLabel(
            "\(surfaceFrameAxisTitle(axis)) \(formattedViewportLength(abs(dragDistance)))",
            at: CGPoint(
                x: end.x + normal2D.dx * 18.0 + direction2D.dx * 8.0,
                y: end.y + normal2D.dy * 18.0 + direction2D.dy * 8.0
            ),
            color: color,
            isHighlighted: true,
            in: &context
        )
    }

    private func surfaceFrameAxisEnd(
        origin: CGPoint,
        direction: Vector3D,
        item: ViewportSceneItem,
        display: ViewportSurfaceFrameDisplay,
        distanceMeters: Double? = nil,
        layout: ViewportLayout
    ) -> CGPoint? {
        if let distanceMeters {
            let basePoint = item.modelTransform.viewportTransformedPoint(display.position)
            let modelDirection = item.modelTransform.viewportTransformedVector(direction)
            let projected = layout.project(Point3D(
                x: basePoint.x + modelDirection.x * distanceMeters,
                y: basePoint.y + modelDirection.y * distanceMeters,
                z: basePoint.z + modelDirection.z * distanceMeters
            ))
            return projected
        }
        let modelScale = Double(max(max(item.modelBounds.width, item.modelBounds.height), 1.0e-6)) * 0.08
        let axisPoint = Point3D(
            x: display.position.x + direction.x * modelScale,
            y: display.position.y + direction.y * modelScale,
            z: display.position.z + direction.z * modelScale
        )
        let projected = layout.project(axisPoint, in: item)
        let dx = projected.x - origin.x
        let dy = projected.y - origin.y
        let length = hypot(dx, dy)
        guard length >= 1.0 else {
            return nil
        }
        let viewportLength: CGFloat = 36.0
        return CGPoint(
            x: origin.x + dx / length * viewportLength,
            y: origin.y + dy / length * viewportLength
        )
    }

    private func drawActiveSurfaceControlPointDrag(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let activeSurfaceControlPointDrag else {
            return
        }
        let geometry = activeSurfaceControlPointDrag.target.geometry
        let start = geometry.projectedPoint(layout: layout)
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceControlPointDrag.delta)
        let end = layout.project(movedPoint)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(activeSurfaceControlPointDrag.target.dragMode.color.opacity(0.86)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5.0, 4.0])
        )
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
    }

    private func drawSurfaceControlPointHandle(
        _ target: ViewportSurfaceControlPointHandleTarget,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = target.geometry.projectedPoint(layout: layout)
        drawSurfaceControlPointAxisHandles(
            target,
            highlightedMode: target.dragMode,
            layout: layout,
            in: &context
        )
        drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
        let radius: CGFloat = style == .selected ? 10.5 : 8.0
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(ViewportTheme.surfaceEdit.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
    }

    private func drawActiveSurfaceTrimEndpointDrag(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let activeSurfaceTrimEndpointDrag else {
            return
        }
        let geometry = activeSurfaceTrimEndpointDrag.target.geometry
        let start = geometry.projectedPoint(layout: layout)
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceTrimEndpointDrag.delta)
        let end = layout.project(movedPoint)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(ViewportTheme.surfaceEdit.opacity(0.86)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5.0, 4.0])
        )
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
    }

    private func drawBridgeCurveEndpointHandle(
        _ target: ViewportBridgeCurveEndpointHandleTarget,
        style: ViewportFaceHighlightStyle,
        in context: inout GraphicsContext
    ) {
        drawBridgeCurveEndpointHandle(
            point: target.projectedPoint,
            tangentTip: target.projectedTangentTip,
            style: style,
            in: &context
        )
    }

    private func drawActiveBridgeCurveEndpointDrag(
        in context: inout GraphicsContext
    ) {
        guard let activeBridgeCurveEndpointDrag else {
            return
        }
        var guide = Path()
        guide.move(to: activeBridgeCurveEndpointDrag.target.projectedPoint)
        guide.addLine(to: activeBridgeCurveEndpointDrag.projectedPoint)
        context.stroke(
            guide,
            with: .color(ViewportTheme.hover.opacity(0.72)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: [4.0, 4.0])
        )
        drawBridgeCurveEndpointHandle(
            point: activeBridgeCurveEndpointDrag.projectedPoint,
            tangentTip: activeBridgeCurveEndpointDrag.projectedTangentTip,
            style: .hovered,
            in: &context
        )
    }

    private func drawBridgeCurveEndpointHandle(
        point: CGPoint,
        tangentTip tip: CGPoint,
        style: ViewportFaceHighlightStyle,
        in context: inout GraphicsContext
    ) {
        var tangentPath = Path()
        tangentPath.move(to: point)
        tangentPath.addLine(to: tip)
        context.stroke(
            tangentPath,
            with: .color(style.color.opacity(style == .selected ? 0.70 : 0.92)),
            style: StrokeStyle(lineWidth: style == .selected ? 1.8 : 2.4, lineCap: .round, dash: [5.0, 3.5])
        )

        let radius: CGFloat = style == .selected ? 6.4 : 8.0
        let outerRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.fill(
            Path(ellipseIn: outerRect),
            with: .color(style.color.opacity(style == .selected ? 0.20 : 0.34))
        )
        context.stroke(
            Path(ellipseIn: outerRect),
            with: .color(style.color.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )

        let innerRadius: CGFloat = 2.4
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - innerRadius,
                y: point.y - innerRadius,
                width: innerRadius * 2.0,
                height: innerRadius * 2.0
            )),
            with: .color(.white.opacity(style == .selected ? 0.72 : 0.90))
        )
    }

    private func drawSurfaceTrimEndpointHandle(
        _ target: ViewportSurfaceTrimEndpointHandleTarget,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = target.geometry.projectedPoint(layout: layout)
        drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
        let radius: CGFloat = style == .selected ? 9.4 : 7.4
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - radius))
        path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        path.closeSubpath()
        context.stroke(
            path,
            with: .color(ViewportTheme.surfaceEdit.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
    }

    private func drawActiveSurfaceTrimControlPointDrag(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let activeSurfaceTrimControlPointDrag else {
            return
        }
        let geometry = activeSurfaceTrimControlPointDrag.target.geometry
        let start = geometry.projectedPoint(layout: layout)
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceTrimControlPointDrag.delta)
        let end = layout.project(movedPoint)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(ViewportTheme.surfaceEdit.opacity(0.86)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: [4.0, 4.0])
        )
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
    }

    private func drawSurfaceTrimControlPointHandle(
        _ target: ViewportSurfaceTrimControlPointHandleTarget,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = target.geometry.projectedPoint(layout: layout)
        drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
        let radius: CGFloat = style == .selected ? 8.8 : 6.8
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(ViewportTheme.surfaceEdit.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
        var tickPath = Path()
        tickPath.move(to: CGPoint(x: point.x - radius, y: point.y))
        tickPath.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        tickPath.move(to: CGPoint(x: point.x, y: point.y - radius))
        tickPath.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        context.stroke(
            tickPath,
            with: .color(ViewportTheme.surfaceEdit.opacity(style.strokeOpacity * 0.72)),
            lineWidth: max(style.lineWidth - 0.4, 0.8)
        )
    }

    private func drawSurfaceControlPointAxisHandles(
        _ target: ViewportSurfaceControlPointHandleTarget,
        highlightedMode: ViewportPolySplineSurfaceVertexDragMode,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let geometry = target.geometry
        let start = geometry.projectedPoint(layout: layout)
        for axis in ViewportCoordinateAxis.allCases {
            guard let end = geometry.axisEndpoint(
                axis: axis,
                viewportLength: surfaceControlPointAxisViewportLength,
                layout: layout
            ) else {
                continue
            }
            drawArrow(
                from: start,
                to: end,
                color: axis.color,
                isHighlighted: highlightedMode.isHighlighted(axis: axis),
                in: &context
            )
        }
    }

    private var surfaceControlPointAxisViewportLength: CGFloat {
        48.0
    }

    private func drawActivePolySplineSurfaceVertexDrag(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let activePolySplineSurfaceVertexDrag else {
            return
        }
        let geometry = activePolySplineSurfaceVertexDrag.target.geometry
        let start = geometry.projectedPoint(layout: layout)
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activePolySplineSurfaceVertexDrag.delta)
        let end = layout.project(movedPoint)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let strokeColor = activePolySplineSurfaceVertexDrag.target.dragMode.color
        context.stroke(
            path,
            with: .color(strokeColor.opacity(0.86)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5.0, 4.0])
        )
        drawTransformHandle(at: end, style: .vertex, isHighlighted: true, in: &context)
    }

    private func drawPolySplineSurfaceVertexHandle(
        _ target: ViewportPolySplineSurfaceVertexHandleTarget,
        style: ViewportFaceHighlightStyle,
        topologyVertices: [ViewportBodyTopology.Vertex],
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let geometry = target.geometry
        let point = geometry.projectedPoint(layout: layout)
        drawPolySplineSurfaceVertexAxisHandles(
            target,
            highlightedMode: target.dragMode,
            topologyVertices: topologyVertices,
            layout: layout,
            in: &context
        )
        drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
        let radius: CGFloat = style == .selected ? 9.0 : 7.0
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(ViewportTheme.surfaceEdit.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth
        )
    }

    private func drawPolySplineSurfaceVertexAxisHandles(
        _ target: ViewportPolySplineSurfaceVertexHandleTarget,
        highlightedMode: ViewportPolySplineSurfaceVertexDragMode,
        topologyVertices: [ViewportBodyTopology.Vertex],
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let geometry = target.geometry
        let start = geometry.projectedPoint(layout: layout)
        for axis in ViewportCoordinateAxis.allCases {
            guard let end = geometry.axisEndpoint(
                axis: axis,
                viewportLength: polySplineSurfaceVertexAxisViewportLength,
                layout: layout
            ) else {
                continue
            }
            drawArrow(
                from: start,
                to: end,
                color: axis.color,
                isHighlighted: highlightedMode.isHighlighted(axis: axis),
                in: &context
            )
        }
        for localAxis in ViewportPolySplineSurfaceVertexLocalAxis.allCases {
            guard let direction = polySplineSurfaceVertexLocalDirection(
                localAxis: localAxis,
                target: target,
                topologyVertices: topologyVertices
            ),
                  let end = polySplineSurfaceVertexLocalAxisEndpoint(
                      target: target,
                      direction: direction,
                      viewportLength: polySplineSurfaceVertexLocalAxisViewportLength,
                      layout: layout
                  ) else {
                continue
            }
            drawArrow(
                from: start,
                to: end,
                color: localAxis.color,
                isHighlighted: highlightedMode.isHighlighted(localAxis: localAxis),
                in: &context
            )
        }
    }

    private var polySplineSurfaceVertexAxisViewportLength: CGFloat {
        52.0
    }

    private var polySplineSurfaceVertexLocalAxisViewportLength: CGFloat {
        62.0
    }

    private func polySplineSurfaceVertexLocalAxisEndpoint(
        target: ViewportPolySplineSurfaceVertexHandleTarget,
        direction: Vector3D,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        target.geometry.localAxisEndpoint(
            direction: direction,
            viewportLength: viewportLength,
            layout: layout
        )
    }

    private func polySplineSurfaceVertexLocalDirection(
        localAxis: ViewportPolySplineSurfaceVertexLocalAxis,
        target: ViewportPolySplineSurfaceVertexHandleTarget,
        topologyVertices: [ViewportBodyTopology.Vertex]
    ) -> Vector3D? {
        guard let parsedTarget = PolySplineSurfaceVertexTarget.parse(componentID: target.componentID),
              parsedTarget.featureID == target.featureID else {
            return nil
        }
        return ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
            for: parsedTarget,
            direction: localAxis.slideDirection,
            topologyVertices: topologyVertices
        )
    }

    private func sceneItem(
        for target: SelectionTarget,
        in scene: ViewportScene
    ) -> ViewportSceneItem? {
        if case .constructionPlane(let sourceID) = target.component {
            guard document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.constructionPlaneID == sourceID else {
                return nil
            }
            return scene.items.first { $0.sceneNodeID == target.sceneNodeID }
        }
        if let directItem = scene.items.first(where: { item in
            item.sceneNodeID == target.sceneNodeID && itemContains(target.component, in: item)
        }) {
            return directItem
        }
        guard let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .body,
              let featureID = reference.featureID else {
            return nil
        }
        return scene.items.first { $0.featureID == featureID }
    }

    private func itemContains(
        _ component: SelectionComponent,
        in item: ViewportSceneItem
    ) -> Bool {
        switch component {
        case .object:
            return true
        case .face(let componentID):
            guard case .body(let bodyComponent) = item.kind else {
                return false
            }
            return bodyComponent.topology?.faces.contains { $0.componentID == componentID } == true
                || componentID.generatedTopologyPersistentName == nil
        case .edge(let componentID):
            guard case .body(let bodyComponent) = item.kind else {
                return false
            }
            return bodyComponent.topology?.edges.contains { $0.componentID == componentID } == true
                || componentID.generatedTopologyPersistentName == nil
        case .vertex(let componentID):
            guard case .body(let bodyComponent) = item.kind else {
                return false
            }
            return bodyComponent.topology?.vertices.contains { $0.componentID == componentID } == true
                || componentID.generatedTopologyPersistentName == nil
        case .sketchEntity(let componentID):
            guard case .sketch(let primitives) = item.kind else {
                return false
            }
            return primitives.contains { $0.entityID == componentID.sketchEntityBaseReference?.entityID }
        case .region(let componentID):
            return item.sketchRegions.contains { $0.componentID == componentID }
        case .constructionPlane:
            return false
        }
    }

    private func selectedGeneratedFaceSurfaceWorldPoint(
        at point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> Point3D? {
        guard let target = selection.primaryTarget,
              case .face(let componentID) = target.component,
              componentID.generatedTopologyPersistentName != nil,
              let item = sceneItem(for: target, in: scene),
              case .body(let component) = item.kind,
              let face = component.topology?.faces.first(where: { $0.componentID == componentID }) else {
            return nil
        }
        return ViewportFaceSurfacePointResolver().worldPoint(
            for: point,
            face: face,
            layout: layout
        )
    }

    private func edgeFilletHandlePoint(
        projection: ViewportBodyProjection,
        edge: ViewportBodyEdge
    ) -> CGPoint {
        let segment = projection.segment(for: edge)
        let center = CGPoint(
            x: (segment.start.x + segment.end.x) / 2.0,
            y: (segment.start.y + segment.end.y) / 2.0
        )
        let direction = edgeInwardDirection(projection: projection, edge: edge)
        return CGPoint(
            x: center.x + direction.dx * 18.0,
            y: center.y + direction.dy * 18.0
        )
    }

    private func edgeInwardDirection(
        projection: ViewportBodyProjection,
        edge: ViewportBodyEdge
    ) -> CGVector {
        let front = edgeInwardCorner(
            footprint: projection.frontFootprint,
            edge: edge
        )
        let back = edgeInwardCorner(
            footprint: projection.backFootprint,
            edge: edge
        )
        let direction = CGVector(
            dx: front.dx + back.dx,
            dy: front.dy + back.dy
        ).normalized
        guard direction.length > 1.0e-9 else {
            return CGVector(dx: 0.0, dy: -1.0)
        }
        return direction
    }

    private func edgeInwardCorner(
        footprint: ViewportProjectedRect,
        edge: ViewportBodyEdge
    ) -> CGVector {
        let corner: CGPoint
        let firstNeighbor: CGPoint
        let secondNeighbor: CGPoint
        switch edge {
        case .leftBottom:
            corner = footprint.bottomLeft
            firstNeighbor = footprint.bottomRight
            secondNeighbor = footprint.topLeft
        case .rightBottom:
            corner = footprint.bottomRight
            firstNeighbor = footprint.bottomLeft
            secondNeighbor = footprint.topRight
        case .rightTop:
            corner = footprint.topRight
            firstNeighbor = footprint.topLeft
            secondNeighbor = footprint.bottomRight
        case .leftTop:
            corner = footprint.topLeft
            firstNeighbor = footprint.topRight
            secondNeighbor = footprint.bottomLeft
        }
        let firstDirection = normalizedVector(
            from: corner,
            to: firstNeighbor,
            fallback: CGVector(dx: 0.0, dy: 0.0)
        )
        let secondDirection = normalizedVector(
            from: corner,
            to: secondNeighbor,
            fallback: CGVector(dx: 0.0, dy: 0.0)
        )
        return CGVector(
            dx: firstDirection.dx + secondDirection.dx,
            dy: firstDirection.dy + secondDirection.dy
        )
    }

    private func bodyFaceAccessibilityMarkers(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) -> [ViewportFaceAccessibilityMarker] {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: basis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout

        return scene.items.flatMap { item -> [ViewportFaceAccessibilityMarker] in
            guard case .body = item.kind,
                  let projection = bodyProjection(for: item, layout: layout) else {
                return []
            }
            return ViewportBodyFace.editableCases.map { face in
                let footprint = projection.footprint(for: face)
                let center = footprint.center
                let modelPoint = layout.unproject(center)
                let hit = ViewportHit(
                    featureID: item.featureID,
                    kind: .body,
                    bodyFace: face
                )
                return ViewportFaceAccessibilityMarker(
                    id: "\(item.id).\(face.rawValue)",
                    face: face,
                    hit: hit,
                    point: center,
                    modelPoint: Point2D(
                        x: Double(modelPoint.x),
                        y: Double(modelPoint.y)
                    ),
                    sketchPlane: constructionSketchPlane(for: hit)
                )
            }
        }
    }

    private func bodyEdgeAccessibilityMarkers(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) -> [ViewportEdgeAccessibilityMarker] {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: basis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout

        return scene.items.flatMap { item -> [ViewportEdgeAccessibilityMarker] in
            guard case .body = item.kind,
                  let projection = bodyProjection(for: item, layout: layout) else {
                return []
            }
            return ViewportBodyEdge.verticalCases.map { edge in
                let segment = projection.segment(for: edge)
                let center = CGPoint(
                    x: (segment.start.x + segment.end.x) / 2.0,
                    y: (segment.start.y + segment.end.y) / 2.0
                )
                let modelPoint = layout.unproject(center)
                let hit = ViewportHit(
                    featureID: item.featureID,
                    kind: .body,
                    bodyEdge: edge
                )
                return ViewportEdgeAccessibilityMarker(
                    id: "\(item.id).\(edge.rawValue)",
                    edge: edge,
                    hit: hit,
                    point: center,
                    modelPoint: Point2D(
                        x: Double(modelPoint.x),
                        y: Double(modelPoint.y)
                    ),
                    sketchPlane: constructionSketchPlane(for: hit)
                )
            }
        }
    }

    private func drawSelectionAffordances(
        in context: inout GraphicsContext,
        scene: ViewportScene,
        layout: ViewportLayout,
        selectedFeatureIDs: Set<FeatureID>
    ) {
        let suppressedFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        if selectedBodyItems.count > 1,
           let groupFeatureID = selectionGroupFeatureID(for: selectedBodyItems),
           let groupEdit = selectionGroupEditState(for: selectedBodyItems) {
            drawBodySelectionAffordance(
                edit: groupEdit,
                featureID: groupFeatureID,
                in: &context,
                layout: layout,
                drawsBoundingBox: true
            )
        }
        for item in scene.items where selectedFeatureIDs.contains(item.featureID) {
            if case .sketch = item.kind,
               suppressedFeatureIDs.contains(item.featureID) {
                continue
            }
            switch item.kind {
            case .body:
                guard selectedBodyItems.count <= 1 else {
                    continue
                }
                drawBodySelectionAffordance(item, in: &context, layout: layout)
            case .sketch:
                drawSketchSelectionAffordance(item, in: &context, layout: layout)
            }
        }
    }

    private func drawPatternArrayPreviews(
        _ previews: [ViewportPatternArrayPreview],
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard !previews.isEmpty else {
            return
        }
        let itemByID = Dictionary(uniqueKeysWithValues: scene.items.map { ($0.id, $0) })
        for preview in previews {
            drawPatternArrayPreview(
                preview,
                itemByID: itemByID,
                layout: layout,
                in: &context
            )
        }
    }

    private func drawPatternArrayCurvePathReplacementPreview(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let request = patternArrayCurvePathReplacementPreviewRequest,
              let preview = ViewportPatternArrayCurvePathReplacementPreviewService().preview(
                document: document,
                scene: scene,
                layout: layout,
                request: request
              ) else {
            return
        }
        let color = Color.green
        if preview.pathPoints.count >= 2 {
            context.stroke(
                polylinePath(for: preview.pathPoints),
                with: .color(color.opacity(0.36)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [7.0, 5.0])
            )
        }
        if preview.outputPoints.count >= 2 {
            context.stroke(
                polylinePath(for: preview.outputPoints),
                with: .color(color.opacity(0.52)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [4.0, 5.0])
            )
        }
        for (index, point) in preview.outputPoints.enumerated() {
            drawPatternArrayCurvePathReplacementPreviewMarker(
                at: point,
                label: "\(index + 1)",
                color: color,
                in: &context
            )
        }
        guard let firstPoint = preview.outputPoints.first else {
            return
        }
        let hiddenCount = max(preview.totalOutputCount - preview.outputPoints.count, 0)
        let suffix = hiddenCount > 0 ? " +\(hiddenCount)" : ""
        drawPatternArraySmallLabel(
            "Path Preview \(preview.title) \(preview.totalOutputCount)\(suffix)",
            at: CGPoint(x: firstPoint.x, y: firstPoint.y - 34.0),
            color: color,
            in: &context
        )
    }

    private func drawPatternArrayCurvePathReplacementPreviewMarker(
        at point: CGPoint,
        label: String,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let radius = 5.0
        var marker = Path()
        marker.move(to: CGPoint(x: point.x, y: point.y - radius))
        marker.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        marker.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        marker.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        marker.closeSubpath()
        context.fill(marker, with: .color(color.opacity(0.22)))
        context.stroke(marker, with: .color(color.opacity(0.9)), lineWidth: 1.2)
        drawPatternArraySmallLabel(
            label,
            at: CGPoint(x: point.x, y: point.y - 17.0),
            color: color,
            in: &context
        )
    }

    private func drawPatternArrayLinearAxisAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayLinearAxisDrag != nil else {
            return
        }
        let candidates = patternArrayLinearAxisAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragDistance = activePatternArrayLinearAxisDrag?.target.identity == identity
                ? activePatternArrayLinearAxisDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredPatternArrayLinearAxisHandle?.identity == identity
                || pendingPatternArrayLinearAxisHandle?.identity == identity
                || activePatternArrayLinearAxisDrag?.target.identity == identity
            drawPatternArrayLinearAxisAffordance(
                candidate,
                distanceMeters: dragDistance ?? candidate.geometry.baseDistanceMeters,
                showsLabel: dragDistance != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawPatternArrayLinearAxisAffordance(
        _ candidate: ViewportPatternArrayLinearAxisAffordanceCandidate,
        distanceMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let start = candidate.geometry.baseProjectedPoint
        let end = candidate.geometry.projectedTip(distanceMeters: distanceMeters)
        let color = Color.cyan
        drawArrow(
            from: start,
            to: end,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            "\(patternArrayLinearAxisSlotTitle(candidate.target.axisSlot)) \(candidate.target.distanceModeTitle) \(formattedViewportLength(distanceMeters))",
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func patternArrayLinearAxisSlotTitle(
        _ axisSlot: ViewportPatternArrayLinearAxisSlot
    ) -> String {
        switch axisSlot {
        case .first:
            "Axis 1"
        case .second:
            "Axis 2"
        case .radial:
            "Radius"
        }
    }

    private func drawIndependentCopyExtrudeDistanceAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onIndependentCopyExtrudeDistanceDrag != nil else {
            return
        }
        let candidates = independentCopyExtrudeDistanceAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragDistance = activeIndependentCopyExtrudeDistanceDrag?.target.identity == identity
                ? activeIndependentCopyExtrudeDistanceDrag?.distanceMeters
                : nil
            let isHighlighted = hoveredIndependentCopyExtrudeDistanceHandle?.identity == identity
                || pendingIndependentCopyExtrudeDistanceHandle?.identity == identity
                || activeIndependentCopyExtrudeDistanceDrag?.target.identity == identity
            drawIndependentCopyExtrudeDistanceAffordance(
                candidate,
                distanceMeters: dragDistance ?? candidate.geometry.baseDistanceMeters,
                showsLabel: dragDistance != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawIndependentCopyExtrudeDistanceAffordance(
        _ candidate: ViewportIndependentCopyExtrudeDistanceAffordanceCandidate,
        distanceMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let start = candidate.geometry.baseProjectedPoint
        let end = candidate.geometry.projectedTip(distanceMeters: distanceMeters)
        let color = Color.orange
        drawArrow(
            from: start,
            to: end,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            "Extrude \(formattedViewportLength(distanceMeters))",
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawIndependentCopyBodyDimensionAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onIndependentCopyBodyDimensionDrag != nil else {
            return
        }
        let candidates = independentCopyBodyDimensionAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragValue = activeIndependentCopyBodyDimensionDrag?.target.identity == identity
                ? activeIndependentCopyBodyDimensionDrag?.valueMeters
                : nil
            let isHighlighted = hoveredIndependentCopyBodyDimensionHandle?.identity == identity
                || pendingIndependentCopyBodyDimensionHandle?.identity == identity
                || activeIndependentCopyBodyDimensionDrag?.target.identity == identity
            drawIndependentCopyBodyDimensionAffordance(
                candidate,
                valueMeters: dragValue ?? candidate.geometry.baseDistanceMeters,
                showsLabel: dragValue != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawIndependentCopyBodyDimensionAffordance(
        _ candidate: ViewportIndependentCopyBodyDimensionAffordanceCandidate,
        valueMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let start = candidate.geometry.baseProjectedPoint
        let end = candidate.geometry.projectedTip(distanceMeters: valueMeters)
        let color = Color.cyan
        drawArrow(
            from: start,
            to: end,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            "\(candidate.target.label) \(formattedViewportLength(valueMeters))",
            at: CGPoint(
                x: end.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: end.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawPatternArrayRadialAngleAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayRadialAngleDrag != nil else {
            return
        }
        let candidates = patternArrayRadialAngleAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragAngle = activePatternArrayRadialAngleDrag?.target.identity == identity
                ? activePatternArrayRadialAngleDrag?.angleRadians
                : nil
            let isHighlighted = hoveredPatternArrayRadialAngleHandle?.identity == identity
                || pendingPatternArrayRadialAngleHandle?.identity == identity
                || activePatternArrayRadialAngleDrag?.target.identity == identity
            drawPatternArrayRadialAngleAffordance(
                candidate,
                angleRadians: dragAngle ?? candidate.geometry.baseAngleRadians,
                showsLabel: dragAngle != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawPatternArrayRadialAngleAffordance(
        _ candidate: ViewportPatternArrayRadialAngleAffordanceCandidate,
        angleRadians: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let points = candidate.geometry.projectedArcPoints(angleRadians: angleRadians)
        guard points.count >= 2 else {
            return
        }
        let color = Color.orange
        let center = candidate.geometry.centerProjectedPoint
        let start = candidate.geometry.startProjectedPoint
        let end = candidate.geometry.projectedTip(angleRadians: angleRadians)
        let arcPath = polylinePath(for: points)
        context.stroke(
            arcPath,
            with: .color(color.opacity(isHighlighted ? 0.9 : 0.55)),
            style: StrokeStyle(lineWidth: isHighlighted ? 2.4 : 1.6, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            Path { path in
                path.move(to: center)
                path.addLine(to: start)
                path.move(to: center)
                path.addLine(to: end)
            },
            with: .color(color.opacity(isHighlighted ? 0.55 : 0.32)),
            style: StrokeStyle(lineWidth: 1.0, dash: [5.0, 5.0])
        )
        drawTransformHandle(
            at: end,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let labelDirection = CGVector(dx: end.x - center.x, dy: end.y - center.y).normalized
        drawDimensionLabel(
            "Radial \(candidate.target.angleModeTitle) \(formattedViewportAngle(angleRadians))",
            at: CGPoint(
                x: end.x + labelDirection.dx * 18.0,
                y: end.y + labelDirection.dy * 18.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawPatternArrayCopyCountAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayCopyCountDrag != nil else {
            return
        }
        let candidates = patternArrayCopyCountAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragCopyCount = activePatternArrayCopyCountDrag?.target.identity == identity
                ? activePatternArrayCopyCountDrag?.copyCount
                : nil
            let copyCount = dragCopyCount ?? candidate.geometry.baseCopyCount
            let isHighlighted = hoveredPatternArrayCopyCountHandle?.identity == identity
                || pendingPatternArrayCopyCountHandle?.identity == identity
                || activePatternArrayCopyCountDrag?.target.identity == identity
            drawPatternArrayCopyCountAffordance(
                candidate,
                copyCount: copyCount,
                showsLabel: dragCopyCount != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawPatternArrayCopyCountAffordance(
        _ candidate: ViewportPatternArrayCopyCountAffordanceCandidate,
        copyCount: Int,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let points = candidate.geometry.guidePoints(copyCount: copyCount)
        guard points.count >= 2 else {
            return
        }
        let color = Color.purple
        context.stroke(
            polylinePath(for: points),
            with: .color(color.opacity(isHighlighted ? 0.85 : 0.42)),
            style: StrokeStyle(lineWidth: isHighlighted ? 2.2 : 1.4, lineCap: .round, lineJoin: .round, dash: [4.0, 5.0])
        )
        let handlePoint = candidate.geometry.handlePoint(copyCount: copyCount)
        drawTransformHandle(
            at: handlePoint,
            style: .vertex,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let firstPoint = points.first ?? handlePoint
        let direction = CGVector(dx: handlePoint.x - firstPoint.x, dy: handlePoint.y - firstPoint.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            "\(candidate.target.title) \(copyCount)",
            at: CGPoint(
                x: handlePoint.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: handlePoint.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawPatternArrayCurveExtentAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayCurveExtentDrag != nil else {
            return
        }
        let candidates = patternArrayCurveExtentAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let dragDistance = activePatternArrayCurveExtentDrag?.target.identity == identity
                ? activePatternArrayCurveExtentDrag?.distanceMeters
                : nil
            let distance = dragDistance ?? candidate.geometry.baseDistanceMeters
            let isHighlighted = hoveredPatternArrayCurveExtentHandle?.identity == identity
                || pendingPatternArrayCurveExtentHandle?.identity == identity
                || activePatternArrayCurveExtentDrag?.target.identity == identity
            drawPatternArrayCurveExtentAffordance(
                candidate,
                distanceMeters: distance,
                showsLabel: dragDistance != nil || isHighlighted,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawPatternArrayCurveExtentAffordance(
        _ candidate: ViewportPatternArrayCurveExtentAffordanceCandidate,
        distanceMeters: Double,
        showsLabel: Bool,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let color = Color.green
        let pathPoints = candidate.geometry.pathPoints
        if pathPoints.count >= 2 {
            context.stroke(
                polylinePath(for: pathPoints),
                with: .color(color.opacity(isHighlighted ? 0.34 : 0.2)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round, dash: [6.0, 5.0])
            )
        }
        let extentPoints = candidate.geometry.projectedExtentPoints(distanceMeters: distanceMeters)
        guard extentPoints.count >= 2 else {
            return
        }
        context.stroke(
            polylinePath(for: extentPoints),
            with: .color(color.opacity(isHighlighted ? 0.9 : 0.55)),
            style: StrokeStyle(lineWidth: isHighlighted ? 2.4 : 1.6, lineCap: .round, lineJoin: .round)
        )
        let tip = candidate.geometry.projectedTip(distanceMeters: distanceMeters)
        drawTransformHandle(
            at: tip,
            style: .faceCenter,
            isHighlighted: isHighlighted,
            in: &context
        )

        guard showsLabel else {
            return
        }
        let previous = extentPoints.dropLast().last ?? extentPoints.first ?? tip
        let direction = CGVector(dx: tip.x - previous.x, dy: tip.y - previous.y).normalized
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        drawDimensionLabel(
            patternArrayCurveExtentLabel(
                target: candidate.target,
                distanceMeters: distanceMeters
            ),
            at: CGPoint(
                x: tip.x + normal.dx * 20.0 + direction.dx * 10.0,
                y: tip.y + normal.dy * 20.0 + direction.dy * 10.0
            ),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func patternArrayCurveExtentLabel(
        target: ViewportPatternArrayCurveExtentHandleTarget,
        distanceMeters: Double
    ) -> String {
        switch target.extentMode {
        case .distance:
            "\(target.title) \(formattedViewportLength(distanceMeters))"
        case .ratio:
            "\(target.title) \(Int((distanceMeters / target.geometry.totalLengthMeters * 100.0).rounded()))%"
        }
    }

    private func drawPatternArrayCurvePathPointAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayCurvePathPointDrag != nil else {
            return
        }
        let candidates = patternArrayCurvePathPointAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        let color = Color.green
        var drawnSourceIDs: Set<PatternArraySourceID> = []
        for candidate in candidates {
            if drawnSourceIDs.insert(candidate.target.sourceID).inserted {
                let pathPoints = patternArrayCurvePathPointProjectedPath(
                    target: candidate.target,
                    layout: layout
                )
                if pathPoints.count >= 2 {
                    context.stroke(
                        polylinePath(for: pathPoints),
                        with: .color(color.opacity(0.4)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [5.0, 4.0])
                    )
                }
            }
            let identity = candidate.target.identity
            let dragPoint = activePatternArrayCurvePathPointDrag?.target.identity == identity
                ? activePatternArrayCurvePathPointDrag?.point
                : nil
            let projectedPoint = dragPoint.map(layout.project) ?? candidate.projectedPoint
            let isHighlighted = hoveredPatternArrayCurvePathPointHandle?.identity == identity
                || pendingPatternArrayCurvePathPointHandle?.identity == identity
                || activePatternArrayCurvePathPointDrag?.target.identity == identity
            drawTransformHandle(
                at: projectedPoint,
                style: .vertex,
                isHighlighted: isHighlighted,
                in: &context
            )
            guard isHighlighted else {
                continue
            }
            drawDimensionLabel(
                candidate.target.title,
                at: CGPoint(x: projectedPoint.x + 18.0, y: projectedPoint.y - 18.0),
                color: color,
                isHighlighted: true,
                in: &context
            )
        }
    }

    private func patternArrayCurvePathPointProjectedPath(
        target: ViewportPatternArrayCurvePathPointHandleTarget,
        layout: ViewportLayout
    ) -> [CGPoint] {
        target.pathPoints.enumerated().map { index, point in
            if activePatternArrayCurvePathPointDrag?.target.sourceID == target.sourceID,
               activePatternArrayCurvePathPointDrag?.target.pointIndex == index,
               let activePoint = activePatternArrayCurvePathPointDrag?.point {
                return layout.project(activePoint)
            }
            return layout.project(point)
        }
    }

    private func drawPatternArrayOutputModeAffordances(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard onPatternArrayOutputModeChange != nil else {
            return
        }
        let candidates = patternArrayOutputModeAffordanceCandidates(
            scene: scene,
            layout: layout
        )
        guard !candidates.isEmpty else {
            return
        }
        for candidate in candidates {
            let identity = candidate.target.identity
            let isHighlighted = hoveredPatternArrayOutputModeHandle?.identity == identity
                || pendingPatternArrayOutputModeHandle?.identity == identity
            drawDimensionLabel(
                isHighlighted ? candidate.target.highlightedTitle : candidate.target.title,
                at: candidate.center,
                color: .teal,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func drawPatternArrayPreview(
        _ preview: ViewportPatternArrayPreview,
        itemByID: [String: ViewportSceneItem],
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let outputs = drawablePatternArrayOutputs(preview.outputs)
        let outputCenters = outputs.compactMap { output -> (ViewportPatternArrayPreview.Output, CGPoint)? in
            guard let center = patternArrayOutputCenter(
                for: output,
                itemByID: itemByID,
                layout: layout
            ) else {
                return nil
            }
            return (output, center)
        }
        drawPatternArrayConnector(
            centers: outputCenters.map(\.1),
            in: &context
        )

        for output in outputs {
            drawPatternArrayOutput(
                output,
                itemByID: itemByID,
                layout: layout,
                in: &context
            )
        }

        if let firstCenter = outputCenters.first?.1 {
            drawPatternArrayCountLabel(
                preview,
                drawnOutputCount: outputs.count,
                at: CGPoint(x: firstCenter.x, y: firstCenter.y - 32.0),
                in: &context
            )
        }
    }

    private func drawablePatternArrayOutputs(
        _ outputs: [ViewportPatternArrayPreview.Output]
    ) -> [ViewportPatternArrayPreview.Output] {
        let maximumDecoratedOutputs = 128
        guard outputs.count > maximumDecoratedOutputs else {
            return outputs
        }
        var decoratedOutputs: [ViewportPatternArrayPreview.Output] = []
        decoratedOutputs.reserveCapacity(maximumDecoratedOutputs)
        var seenIndexes: Set<Int> = []
        for output in outputs where output.isSelected && decoratedOutputs.count < maximumDecoratedOutputs {
            seenIndexes.insert(output.index)
            decoratedOutputs.append(output)
        }
        for output in outputs where decoratedOutputs.count < maximumDecoratedOutputs {
            guard seenIndexes.insert(output.index).inserted else {
                continue
            }
            decoratedOutputs.append(output)
        }
        return decoratedOutputs.sorted { $0.index < $1.index }
    }

    private func drawPatternArrayOutput(
        _ output: ViewportPatternArrayPreview.Output,
        itemByID: [String: ViewportSceneItem],
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let color = output.isSelected ? Color.orange : Color.cyan
        for itemID in output.itemIDs {
            guard let item = itemByID[itemID] else {
                continue
            }
            drawPatternArrayItemOutline(
                item,
                color: color,
                isSelectedOutput: output.isSelected,
                layout: layout,
                in: &context
            )
        }
        guard let center = patternArrayOutputCenter(
            for: output,
            itemByID: itemByID,
            layout: layout
        ) else {
            return
        }
        drawPatternArrayOutputMarker(
            output,
            at: center,
            color: color,
            in: &context
        )
    }

    private func drawPatternArrayConnector(
        centers: [CGPoint],
        in context: inout GraphicsContext
    ) {
        guard centers.count > 1 else {
            return
        }
        var path = Path()
        path.move(to: centers[0])
        for center in centers.dropFirst() {
            path.addLine(to: center)
        }
        context.stroke(
            path,
            with: .color(Color.cyan.opacity(0.42)),
            style: StrokeStyle(lineWidth: 1.1, dash: [5.0, 5.0])
        )
    }

    private func drawPatternArrayItemOutline(
        _ item: ViewportSceneItem,
        color: Color,
        isSelectedOutput: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let outline = patternArrayItemOutlinePath(item, layout: layout)
        context.stroke(
            outline,
            with: .color(color.opacity(isSelectedOutput ? 0.88 : 0.50)),
            style: StrokeStyle(lineWidth: isSelectedOutput ? 1.45 : 1.05, dash: [6.0, 4.0])
        )
    }

    private func patternArrayItemOutlinePath(
        _ item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> Path {
        if let projection = layout.bodyProjection(for: item) {
            return patternArrayBodyOutlinePath(projection)
        }
        return patternArrayProjectedRectPath(layout.projectedFootprint(item.modelBounds))
    }

    private func patternArrayBodyOutlinePath(
        _ projection: ViewportBodyProjection
    ) -> Path {
        var path = Path()
        appendPatternArrayProjectedRect(projection.frontFootprint, to: &path)
        appendPatternArrayProjectedRect(projection.backFootprint, to: &path)
        let corners = [
            (projection.frontFootprint.bottomLeft, projection.backFootprint.bottomLeft),
            (projection.frontFootprint.bottomRight, projection.backFootprint.bottomRight),
            (projection.frontFootprint.topRight, projection.backFootprint.topRight),
            (projection.frontFootprint.topLeft, projection.backFootprint.topLeft),
        ]
        for edge in corners {
            path.move(to: edge.0)
            path.addLine(to: edge.1)
        }
        return path
    }

    private func patternArrayProjectedRectPath(
        _ rect: ViewportProjectedRect
    ) -> Path {
        var path = Path()
        appendPatternArrayProjectedRect(rect, to: &path)
        return path
    }

    private func appendPatternArrayProjectedRect(
        _ rect: ViewportProjectedRect,
        to path: inout Path
    ) {
        path.move(to: rect.bottomLeft)
        path.addLine(to: rect.bottomRight)
        path.addLine(to: rect.topRight)
        path.addLine(to: rect.topLeft)
        path.closeSubpath()
    }

    private func patternArrayOutputCenter(
        for output: ViewportPatternArrayPreview.Output,
        itemByID: [String: ViewportSceneItem],
        layout: ViewportLayout
    ) -> CGPoint? {
        let centers = output.itemIDs.compactMap { itemID -> CGPoint? in
            guard let item = itemByID[itemID] else {
                return nil
            }
            if let projection = layout.bodyProjection(for: item) {
                return projection.center
            }
            return layout.projectedFootprint(item.modelBounds).center
        }
        guard !centers.isEmpty else {
            return nil
        }
        let sum = centers.reduce(CGPoint.zero) { partial, center in
            CGPoint(x: partial.x + center.x, y: partial.y + center.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(centers.count),
            y: sum.y / CGFloat(centers.count)
        )
    }

    private func drawPatternArrayOutputMarker(
        _ output: ViewportPatternArrayPreview.Output,
        at center: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let radius: CGFloat = output.isSelected ? 5.2 : 4.0
        let markerRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.fill(Path(ellipseIn: markerRect), with: .color(color.opacity(0.28)))
        context.stroke(Path(ellipseIn: markerRect), with: .color(color.opacity(0.92)), lineWidth: 1.2)
        drawPatternArraySmallLabel(
            "#\(output.index + 1)",
            at: CGPoint(x: center.x, y: center.y - 16.0),
            color: color,
            in: &context
        )
    }

    private func drawPatternArrayCountLabel(
        _ preview: ViewportPatternArrayPreview,
        drawnOutputCount: Int,
        at point: CGPoint,
        in context: inout GraphicsContext
    ) {
        let hiddenCount = max(preview.outputs.count - drawnOutputCount, 0)
        let suffix = hiddenCount > 0 ? " +\(hiddenCount)" : ""
        drawPatternArraySmallLabel(
            "\(patternArrayDistributionTitle(preview.distributionKind)) \(preview.outputCount)\(suffix)",
            at: point,
            color: Color.cyan,
            in: &context
        )
    }

    private func drawPatternArraySmallLabel(
        _ label: String,
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let width = max(CGFloat(label.count) * 7.0 + 12.0, 22.0)
        let rect = CGRect(
            x: point.x - width / 2.0,
            y: point.y - 9.0,
            width: width,
            height: 18.0
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: 6.0),
            with: .color(Color.black.opacity(0.72))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 6.0),
            with: .color(color.opacity(0.72)),
            lineWidth: 0.8
        )
        context.draw(
            Text(label)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94)),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func patternArrayDistributionTitle(
        _ distributionKind: PatternArraySummary.DistributionKind
    ) -> String {
        switch distributionKind {
        case .rectangular:
            "Rectangular"
        case .radial:
            "Radial"
        case .curve:
            "Curve"
        }
    }

    private func drawBodySelectionAffordance(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        drawBodySelectionAffordance(
            edit: edit,
            featureID: item.featureID,
            in: &context,
            layout: layout,
            drawsBoundingBox: false
        )
    }

    private func drawBodySelectionAffordance(
        edit: ViewportObjectEditState,
        featureID: FeatureID,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        drawsBoundingBox: Bool
    ) {
        let projection = edit.projectedBodyProjection(layout: layout)
        let bodyBounds = projection.hitBounds
        let modelCenter = edit.centerPoint
        let center = edit.projectedPoint(modelCenter, layout: layout)
        let affordanceBasis = edit.projectedAxisBasis(layout: layout)
        let radius = max(28.0, min(72.0, min(bodyBounds.width, bodyBounds.height) * 0.38))

        if drawsBoundingBox {
            drawSelectionBoundingBox(edit, in: &context, layout: layout)
        }

        drawBasisRotationArcs(
            center: center,
            radius: radius,
            basis: affordanceBasis,
            highlightedAxis: highlightedRotationAxis(for: featureID),
            in: &context
        )

        let axisLength = bodyAffordanceAxisLength(for: radius)
        let endScaleLength = bodyAffordanceEndScaleLength(
            axisLength: axisLength,
            rotationRadius: radius
        )
        for axis in ViewportCoordinateAxis.allCases {
            drawProjectedMoveArrow(
                axis: axis,
                from: modelCenter,
                edit: edit,
                viewportLength: axisLength,
                layout: layout,
                color: axis.color,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .translate(axis)
                ),
                in: &context
            )

            drawTransformCube(
                at: modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: endScaleLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                edit: edit,
                style: .axisEndScale(axis),
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .oneSidedScale(axis)
                ),
                layout: layout,
                in: &context
            )

            drawProjectedSphere(
                at: modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: radius,
                        axis: axis,
                        layout: layout
                    )
                ),
                edit: edit,
                color: axis.color,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .centerScale(axis)
                ),
                layout: layout,
                in: &context
            )
        }

        drawPivotCube(at: modelCenter, edit: edit, layout: layout, in: &context)
        for handle in bodyFaceCenterHandles(edit, layout: layout) {
            drawProjectedFaceCircle(
                at: handle.position,
                face: handle.face,
                edit: edit,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .faceMove(handle.face)
                ),
                layout: layout,
                in: &context
            )
        }
        for handle in bodyVertexHandles(edit, layout: layout) {
            drawTransformCube(
                edit.projectedCube(
                    center: handle.position,
                    sideLength: handleSideLength(points: 10.0, layout: layout),
                    layout: layout
                ),
                style: .vertex,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .vertexMove(handle.vertex)
                ),
                in: &context
            )
        }
    }

    private func drawSelectionBoundingBox(
        _ edit: ViewportObjectEditState,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let box = edit.projectedBox(layout: layout)
        var path = Path()
        for edge in box.edges {
            path.move(to: edge.start)
            path.addLine(to: edge.end)
        }
        context.stroke(path, with: .color(Color.white.opacity(0.70)), lineWidth: 1.3)
        context.stroke(path, with: .color(Color.black.opacity(0.36)), lineWidth: 0.55)
    }

    private func drawSketchSelectionAffordance(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let footprint = layout.projectedFootprint(item.modelBounds)
        drawPlanarSelectionAffordance(
            for: footprint,
            basis: layout.basis,
            in: &context
        )
    }

    private func drawPlanarSelectionAffordance(
        for footprint: ViewportProjectedRect,
        basis: ViewportProjectionBasis,
        in context: inout GraphicsContext
    ) {
        let bounds = footprint.bounds
        let center = footprint.center
        let radius = max(24.0, min(64.0, min(bounds.width, bounds.height) * 0.58))

        drawBasisRotationArcs(
            center: center,
            radius: radius,
            basis: basis,
            highlightedAxis: nil,
            in: &context
        )
        drawMoveArrow(
            axis: .x,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.x.color,
            isHighlighted: false,
            in: &context
        )
        drawMoveArrow(
            axis: .y,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.y.color,
            isHighlighted: false,
            in: &context
        )
        drawMoveArrow(
            axis: .z,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.z.color,
            isHighlighted: false,
            in: &context
        )

        drawPivot(at: center, in: &context)
        for point in footprint.handlePoints {
            drawTransformHandle(at: point, style: .vertex, isHighlighted: false, in: &context)
        }
    }

    private func bodyVertexHandles(
        _ edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> [ViewportVertexHandle] {
        ViewportBodyVertex.allCases.map { vertex in
            let position = edit.position(for: vertex)
            return ViewportVertexHandle(
                vertex: vertex,
                position: position,
                point: edit.projectedPoint(position, layout: layout)
            )
        }
    }

    private func bodyFaceCenterHandles(
        _ edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> [ViewportFaceHandle] {
        ViewportBodyFace.editableCases.map { face in
            let position = edit.position(for: face)
            return ViewportFaceHandle(
                face: face,
                position: position,
                point: edit.projectedPoint(position, layout: layout)
            )
        }
    }

    private func bodyAffordanceAxisLength(for rotationRadius: CGFloat) -> CGFloat {
        max(72.0, min(132.0, rotationRadius * 1.9))
    }

    private func bodyAffordanceEndScaleLength(
        axisLength: CGFloat,
        rotationRadius: CGFloat
    ) -> CGFloat {
        min(axisLength - 14.0, max(rotationRadius + 18.0, axisLength - 24.0))
    }

    private func drawCanvasDragPreview(
        _ activeDrag: ViewportActiveDrag,
        previewKind: ViewportCanvasDragPreviewKind,
        in context: inout GraphicsContext,
        size: CGSize,
        basis: ViewportProjectionBasis
    ) {
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: basis
        )
        let sketchPlane = activeDrag.sketchPlane ?? canvasDragSketchPlane(for: hoveredCanvasHit)
        let drag = mapper.modelDrag(
            from: activeDrag.startLocation,
            to: activeDrag.currentLocation,
            sketchPlane: sketchPlane
        ).constrained(by: canvasDragAxisConstraint)
        guard let preview = ViewportCanvasDragPreview(
            kind: previewKind,
            drag: drag,
            layout: mapper.layout
        ) else {
            return
        }

        switch preview {
        case .rectangle(let placeholder):
            drawRectangleDragPreview(
                placeholder,
                basis: mapper.layout.basis,
                in: &context
            )
        case .polygon(let preview):
            drawPolygonDragPreview(preview, in: &context)
        case .arc(let preview):
            drawArcDragPreview(preview, in: &context)
        case .spline(let preview):
            drawSplineDragPreview(preview, in: &context)
        }
    }

    private func drawRectangleDragPreview(
        _ placeholder: ViewportCanvasDragPlaceholder,
        basis: ViewportProjectionBasis,
        in context: inout GraphicsContext
    ) {
        let placeholderPath = path(for: placeholder.footprint)
        context.fill(placeholderPath, with: .color(Color.black.opacity(0.48)))
        context.stroke(placeholderPath, with: .color(Color.white.opacity(0.36)), lineWidth: 1.2)
        context.stroke(placeholderPath, with: .color(Color.accentColor.opacity(0.36)), lineWidth: 1.0)

        drawPlanarSelectionAffordance(
            for: placeholder.footprint,
            basis: basis,
            in: &context
        )
    }

    private func drawPolygonDragPreview(
        _ preview: ViewportCanvasPolygonDragPreview,
        in context: inout GraphicsContext
    ) {
        let closedVertices = preview.projectedVertices + preview.projectedVertices.prefix(1)
        let polygonPath = polylinePath(for: closedVertices)
        let radiusPath = polylinePath(for: [
            preview.projectedCenter,
            preview.projectedRadiusEnd,
        ])
        context.stroke(
            radiusPath,
            with: .color(Color.white.opacity(0.26)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
        )
        context.fill(polygonPath, with: .color(Color.accentColor.opacity(0.10)))
        context.stroke(
            polygonPath,
            with: .color(Color.black.opacity(0.56)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            polygonPath,
            with: .color(Color.accentColor.opacity(0.92)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
        drawPreviewHandle(at: preview.projectedCenter, radius: 4.6, in: &context)
        for point in preview.projectedVertices {
            drawPreviewHandle(at: point, radius: 3.8, in: &context)
        }
    }

    private func drawArcDragPreview(
        _ preview: ViewportCanvasArcDragPreview,
        in context: inout GraphicsContext
    ) {
        let arcPath = polylinePath(for: preview.projectedPoints)
        let radiusPath = polylinePath(for: [
            preview.projectedCenter,
            preview.projectedRadiusEnd,
        ])
        context.stroke(
            radiusPath,
            with: .color(Color.white.opacity(0.28)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
        )
        context.stroke(
            arcPath,
            with: .color(Color.black.opacity(0.56)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            arcPath,
            with: .color(Color.accentColor.opacity(0.92)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
        drawPreviewHandle(at: preview.projectedCenter, radius: 4.6, in: &context)
        drawPreviewHandle(at: preview.projectedRadiusEnd, radius: 4.2, in: &context)
    }

    private func drawSplineDragPreview(
        _ preview: ViewportCanvasSplineDragPreview,
        in context: inout GraphicsContext
    ) {
        let curvePath = polylinePath(for: preview.projectedCurvePoints)
        let controlPath = polylinePath(for: preview.projectedControlPoints)
        context.stroke(
            controlPath,
            with: .color(Color.white.opacity(0.25)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round, dash: [4.0, 4.0])
        )
        context.stroke(
            curvePath,
            with: .color(Color.black.opacity(0.56)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            curvePath,
            with: .color(Color.accentColor.opacity(0.92)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
        for (index, point) in preview.projectedControlPoints.enumerated() {
            drawPreviewHandle(
                at: point,
                radius: index == 0 || index == preview.projectedControlPoints.count - 1 ? 4.4 : 3.4,
                in: &context
            )
        }
    }

    private func drawPreviewHandle(
        at point: CGPoint,
        radius: CGFloat,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(ViewportTheme.background.opacity(0.86)))
        context.stroke(path, with: .color(Color.white.opacity(0.78)), lineWidth: 1.0)
        context.stroke(path, with: .color(Color.accentColor.opacity(0.86)), lineWidth: 0.8)
    }

    private func drawSelectionDragRectangle(
        _ activeDrag: ViewportActiveDrag,
        in context: inout GraphicsContext
    ) {
        let rect = dragRect(from: activeDrag.startLocation, to: activeDrag.currentLocation)
        guard rect.width > 0.0, rect.height > 0.0 else {
            return
        }

        let path = Path(rect)
        context.fill(path, with: .color(Color.accentColor.opacity(0.12)))
        context.stroke(
            path,
            with: .color(Color.accentColor.opacity(0.88)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 3.0])
        )
    }

    private func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func path(for footprint: ViewportProjectedRect) -> Path {
        var path = Path()
        path.move(to: footprint.bottomLeft)
        path.addLine(to: footprint.bottomRight)
        path.addLine(to: footprint.topRight)
        path.addLine(to: footprint.topLeft)
        path.closeSubpath()
        return path
    }

    private func polylinePath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func drawRotationArc(
        center: CGPoint,
        radius: CGFloat,
        planeStart: CGVector,
        planeEnd: CGVector,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let points = projectedRotationArcPoints(
            center: center,
            radius: radius,
            planeStart: planeStart,
            planeEnd: planeEnd
        )
        guard let firstPoint = points.first else {
            return
        }

        var path = Path()
        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.92)),
            lineWidth: isHighlighted ? 4.2 : 2.6
        )
    }

    private func drawBasisRotationArcs(
        center: CGPoint,
        radius: CGFloat,
        basis: ViewportProjectionBasis,
        highlightedAxis: ViewportCoordinateAxis?,
        in context: inout GraphicsContext
    ) {
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.yDirection,
            to: basis.zDirection,
            color: ViewportCoordinateAxis.x.color,
            isHighlighted: highlightedAxis == .x,
            in: &context
        )
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.zDirection,
            to: basis.xDirection,
            color: ViewportCoordinateAxis.y.color,
            isHighlighted: highlightedAxis == .y,
            in: &context
        )
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.xDirection,
            to: basis.yDirection,
            color: ViewportCoordinateAxis.z.color,
            isHighlighted: highlightedAxis == .z,
            in: &context
        )
    }

    private func drawRotationArc(
        center: CGPoint,
        radius: CGFloat,
        from startDirection: CGVector,
        to endDirection: CGVector,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        drawRotationArc(
            center: center,
            radius: radius,
            planeStart: startDirection,
            planeEnd: endDirection,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func projectedRotationArcPoints(
        center: CGPoint,
        radius: CGFloat,
        planeStart: CGVector,
        planeEnd: CGVector,
        segmentCount: Int = 36
    ) -> [CGPoint] {
        (0 ... segmentCount).map { index in
            let progress = CGFloat(index) / CGFloat(segmentCount)
            let radians = progress * .pi / 2.0
            let startScale = cos(radians) * radius
            let endScale = sin(radians) * radius
            return CGPoint(
                x: center.x + planeStart.dx * startScale + planeEnd.dx * endScale,
                y: center.y + planeStart.dy * startScale + planeEnd.dy * endScale
            )
        }
    }

    private func drawMoveArrow(
        axis: ViewportCoordinateAxis,
        from start: CGPoint,
        length: CGFloat,
        basis: ViewportProjectionBasis,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        drawArrow(
            from: start,
            to: basis.endpoint(from: start, axis: axis, length: length),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(
            shaft,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.95)),
            lineWidth: isHighlighted ? 4.6 : 3.2
        )

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1.0)
        let unit = CGVector(dx: dx / length, dy: dy / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let base = CGPoint(x: end.x - unit.dx * 13.0, y: end.y - unit.dy * 13.0)

        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: base.x + normal.dx * 6.0, y: base.y + normal.dy * 6.0))
        head.addLine(to: CGPoint(x: base.x - normal.dx * 6.0, y: base.y - normal.dy * 6.0))
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(0.95)))
    }

    private func drawProjectedMoveArrow(
        axis: ViewportCoordinateAxis,
        from start: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        viewportLength: CGFloat,
        layout: ViewportLayout,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let fullLength = edit.modelLength(forViewportLength: viewportLength, axis: axis, layout: layout)
        let headLength = edit.modelLength(
            forViewportLength: isHighlighted ? 18.0 : 15.0,
            axis: axis,
            layout: layout
        )
        let shaftLength = max(fullLength - headLength * 0.7, 0.0)
        let shaftEnd = start.offset(axis: axis, amount: shaftLength)
        let end = start.offset(
            axis: axis,
            amount: fullLength
        )

        var shaft = Path()
        shaft.move(to: edit.projectedPoint(start, layout: layout))
        shaft.addLine(to: edit.projectedPoint(shaftEnd, layout: layout))
        context.stroke(
            shaft,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.95)),
            lineWidth: isHighlighted ? 4.6 : 3.2
        )

        drawProjectedArrowHeadCone(
            axis: axis,
            tip: end,
            edit: edit,
            headLength: headLength,
            baseRadius: handleSideLength(points: isHighlighted ? 8.4 : 6.8, layout: layout),
            layout: layout,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawProjectedArrowHeadCone(
        axis: ViewportCoordinateAxis,
        tip: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        headLength: CGFloat,
        baseRadius: CGFloat,
        layout: ViewportLayout,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let baseCenter = tip.offset(axis: axis, amount: -headLength)
        let perpendicularAxes = perpendicularAxes(for: axis)
        let segmentCount = 18
        let baseVertices = (0 ..< segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * 2.0 * CGFloat.pi
            return baseCenter
                .offset(axis: perpendicularAxes.first, amount: cos(angle) * baseRadius)
                .offset(axis: perpendicularAxes.second, amount: sin(angle) * baseRadius)
        }
        let projectedTip = edit.projectedPoint(tip, layout: layout)
        let projectedBase = baseVertices.map { edit.projectedPoint($0, layout: layout) }
        let sideOpacity = isHighlighted ? 0.88 : 0.76
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            context.fill(
                path(for: [projectedTip, projectedBase[index], projectedBase[nextIndex]]),
                with: .color(color.opacity(sideOpacity - Double(index % 3) * 0.05))
            )
        }
        context.fill(
            path(for: Array(projectedBase.reversed())),
            with: .color(color.opacity(isHighlighted ? 0.62 : 0.48))
        )
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            var path = Path()
            path.move(to: projectedBase[index])
            path.addLine(to: projectedBase[nextIndex])
            context.stroke(
                path,
                with: .color(Color.black.opacity(isHighlighted ? 0.48 : 0.34)),
                lineWidth: isHighlighted ? 1.2 : 0.8
            )
        }
        for index in stride(from: 0, to: segmentCount, by: 6) {
            var path = Path()
            path.move(to: projectedTip)
            path.addLine(to: projectedBase[index])
            context.stroke(
                path,
                with: .color(Color.black.opacity(isHighlighted ? 0.36 : 0.24)),
                lineWidth: isHighlighted ? 1.0 : 0.7
            )
        }
    }

    private func perpendicularAxes(
        for axis: ViewportCoordinateAxis
    ) -> (first: ViewportCoordinateAxis, second: ViewportCoordinateAxis) {
        switch axis {
        case .x:
            return (.y, .z)
        case .y:
            return (.z, .x)
        case .z:
            return (.x, .y)
        }
    }

    private func drawProjectedFaceCircle(
        at center: ViewportModelPoint3D,
        face: ViewportBodyFace,
        edit: ViewportObjectEditState,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let axes = facePlaneAxes(for: face)
        let radius = handleSideLength(points: isHighlighted ? 9.8 : 8.0, layout: layout)
        let points = projectedCirclePoints(
            center: center,
            firstAxis: axes.first,
            secondAxis: axes.second,
            radius: radius,
            edit: edit,
            layout: layout
        )
        let path = path(for: points)
        let color = isHighlighted ? Color.cyan : Color.gray
        context.fill(path, with: .color(color.opacity(isHighlighted ? 0.56 : 0.36)))
        context.stroke(
            path,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.78)),
            lineWidth: isHighlighted ? 2.0 : 1.2
        )
        context.stroke(
            path,
            with: .color(Color.black.opacity(isHighlighted ? 0.30 : 0.22)),
            lineWidth: 0.7
        )
    }

    private func drawProjectedSphere(
        at center: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        color: Color,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = edit.projectedPoint(center, layout: layout)
        let diameter: CGFloat = isHighlighted ? 13.5 : 10.5
        let rect = CGRect(
            x: point.x - diameter / 2.0,
            y: point.y - diameter / 2.0,
            width: diameter,
            height: diameter
        )
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(color.opacity(isHighlighted ? 0.96 : 0.78)))
        context.stroke(
            path,
            with: .color(Color.black.opacity(isHighlighted ? 0.38 : 0.28)),
            lineWidth: isHighlighted ? 1.3 : 0.9
        )
        let highlightDiameter = diameter * 0.34
        let highlightRect = CGRect(
            x: point.x - diameter * 0.22,
            y: point.y - diameter * 0.28,
            width: highlightDiameter,
            height: highlightDiameter
        )
        context.fill(
            Path(ellipseIn: highlightRect),
            with: .color(Color.white.opacity(isHighlighted ? 0.50 : 0.34))
        )
    }

    private func facePlaneAxes(
        for face: ViewportBodyFace
    ) -> (first: ViewportCoordinateAxis, second: ViewportCoordinateAxis) {
        switch face {
        case .front, .back:
            return (.x, .z)
        case .top, .bottom:
            return (.x, .y)
        case .left, .right, .side:
            return (.y, .z)
        }
    }

    private func projectedCirclePoints(
        center: ViewportModelPoint3D,
        firstAxis: ViewportCoordinateAxis,
        secondAxis: ViewportCoordinateAxis,
        radius: CGFloat,
        edit: ViewportObjectEditState,
        layout: ViewportLayout,
        segmentCount: Int = 36
    ) -> [CGPoint] {
        (0 ..< segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * 2.0 * CGFloat.pi
            let point = center
                .offset(axis: firstAxis, amount: cos(angle) * radius)
                .offset(axis: secondAxis, amount: sin(angle) * radius)
            return edit.projectedPoint(point, layout: layout)
        }
    }

    private func drawTransformHandle(
        at point: CGPoint,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        switch style {
        case .vertex:
            let size: CGFloat = isHighlighted ? 12.0 : 9.6
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(roundedRect: rect, cornerRadius: 1.8)
            context.fill(path, with: .color((isHighlighted ? Color.cyan : Color.gray).opacity(0.92)))
            context.stroke(path, with: .color(Color.black.opacity(0.42)), lineWidth: isHighlighted ? 1.4 : 1.0)
        case .faceCenter:
            let size: CGFloat = isHighlighted ? 11.0 : 8.4
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color((isHighlighted ? Color.cyan : Color.gray).opacity(0.76)))
            context.stroke(path, with: .color(Color.white.opacity(0.42)), lineWidth: 0.9)
            context.stroke(path, with: .color(Color.black.opacity(0.26)), lineWidth: 0.7)
        case .axisEndScale(let axis), .axisCenterScale(let axis):
            let size: CGFloat = isHighlighted ? 11.8 : 9.2
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(roundedRect: rect, cornerRadius: 2.0)
            context.fill(path, with: .color(axis.color.opacity(isHighlighted ? 1.0 : 0.84)))
            context.stroke(path, with: .color(Color.black.opacity(0.36)), lineWidth: isHighlighted ? 1.4 : 0.9)
        }
    }

    private func drawEdgeFilletHandle(
        at point: CGPoint,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let radius: CGFloat = isHighlighted ? 9.5 : 8.0
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(ViewportTheme.hover.opacity(isHighlighted ? 0.92 : 0.74)))
        context.stroke(path, with: .color(Color.black.opacity(0.40)), lineWidth: isHighlighted ? 1.4 : 1.0)
        context.stroke(
            Path { arc in
                arc.addArc(
                    center: point,
                    radius: radius * 0.54,
                    startAngle: .degrees(-8.0),
                    endAngle: .degrees(98.0),
                    clockwise: false
                )
            },
            with: .color(Color.white.opacity(0.82)),
            lineWidth: isHighlighted ? 1.8 : 1.3
        )
    }

    private func drawTransformCube(
        at point: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let sidePoints: CGFloat = switch style {
        case .vertex:
            isHighlighted ? 12.5 : 10.0
        case .faceCenter:
            isHighlighted ? 11.5 : 9.2
        case .axisEndScale, .axisCenterScale:
            isHighlighted ? 12.4 : 9.8
        }
        drawTransformCube(
            edit.projectedCube(
                center: point,
                sideLength: handleSideLength(points: sidePoints, layout: layout),
                layout: layout
            ),
            style: style,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawTransformCube(
        _ cube: ViewportProjectedBox,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let color = switch style {
        case .vertex:
            isHighlighted ? Color.cyan : Color.gray
        case .faceCenter:
            isHighlighted ? Color.cyan : Color.gray
        case .axisEndScale(let axis), .axisCenterScale(let axis):
            axis.color
        }
        drawProjectedBox(
            cube,
            color: color,
            isHighlighted: isHighlighted,
            fillOpacity: isHighlighted ? 0.78 : 0.58,
            in: &context
        )
    }

    private func drawPivot(at point: CGPoint, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 7.0, y: point.y - 7.0, width: 14.0, height: 14.0)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(Color.gray.opacity(0.72)))
        context.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 1.0)
    }

    private func drawPivotCube(
        at point: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        drawProjectedBox(
            edit.projectedCube(
                center: point,
                sideLength: handleSideLength(points: 12.0, layout: layout),
                layout: layout
            ),
            color: Color.gray,
            isHighlighted: false,
            fillOpacity: 0.62,
            in: &context
        )
    }

    private func drawProjectedBox(
        _ box: ViewportProjectedBox,
        color: Color,
        isHighlighted: Bool,
        fillOpacity: Double,
        in context: inout GraphicsContext
    ) {
        for (index, face) in box.faces.enumerated() {
            let opacity = fillOpacity * (0.72 + Double(index % 3) * 0.11)
            context.fill(
                path(for: face),
                with: .color(color.opacity(opacity))
            )
        }
        for edge in box.edges {
            var path = Path()
            path.move(to: edge.start)
            path.addLine(to: edge.end)
            context.stroke(
                path,
                with: .color((isHighlighted ? Color.white : Color.black).opacity(isHighlighted ? 0.58 : 0.42)),
                lineWidth: isHighlighted ? 1.35 : 0.85
            )
        }
    }

    private func path(for polygon: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = polygon.first else {
            return path
        }
        path.move(to: firstPoint)
        for point in polygon.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func handleSideLength(points: CGFloat, layout: ViewportLayout) -> CGFloat {
        points / max(layout.scale, 1.0e-9)
    }

    private func selectedObjectFeatureIDs() -> Set<FeatureID> {
        featureIDs(for: objectSelectionTargets())
    }

    private func selectedTargetFeatureIDs() -> Set<FeatureID> {
        featureIDs(for: selection.selectedTargets)
    }

    private func featureIDs(for targets: [SelectionTarget]) -> Set<FeatureID> {
        Set(
            targets.compactMap { target in
                document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID
            }
        )
    }

    private func sceneNodeIDs(for targets: [SelectionTarget]) -> Set<SceneNodeID> {
        Set(targets.map(\.sceneNodeID))
    }

    private func isObjectItem(
        _ item: ViewportSceneItem,
        selectedByFeatureIDs featureIDs: Set<FeatureID>,
        selectedBySceneNodeIDs sceneNodeIDs: Set<SceneNodeID>
    ) -> Bool {
        if let sceneNodeID = item.sceneNodeID,
           sceneNodeIDs.contains(sceneNodeID) {
            return true
        }
        return featureIDs.contains(item.featureID)
    }

    private func objectSelectionTargets() -> [SelectionTarget] {
        objectSelectionTargets(in: selection.selectedTargets)
    }

    private func objectSelectionTargets(in targets: [SelectionTarget]) -> [SelectionTarget] {
        targets.filter { target in
            if case .object = target.component {
                return true
            }
            return false
        }
    }

    private func selectedFaceTargets() -> [ViewportFaceSelectionTarget] {
        faceSelectionTargets(in: selection.selectedTargets)
    }

    private func faceSelectionTargets(in targets: [SelectionTarget]) -> [ViewportFaceSelectionTarget] {
        targets.compactMap { target in
            faceSelectionTarget(for: target)
        }
    }

    private func hoveredFaceTarget() -> ViewportFaceSelectionTarget? {
        guard let hoveredTarget = selection.hoveredTarget else {
            return nil
        }
        return faceSelectionTarget(for: hoveredTarget)
    }

    private func selectedEdgeTargets() -> [ViewportEdgeSelectionTarget] {
        edgeSelectionTargets(in: selection.selectedTargets)
    }

    private func edgeSelectionTargets(in targets: [SelectionTarget]) -> [ViewportEdgeSelectionTarget] {
        targets.compactMap { target in
            edgeSelectionTarget(for: target)
        }
    }

    private func hoveredEdgeTarget() -> ViewportEdgeSelectionTarget? {
        guard let hoveredTarget = selection.hoveredTarget else {
            return nil
        }
        return edgeSelectionTarget(for: hoveredTarget)
    }

    private func selectedVertexTargets() -> [ViewportVertexSelectionTarget] {
        vertexSelectionTargets(in: selection.selectedTargets)
    }

    private func vertexSelectionTargets(in targets: [SelectionTarget]) -> [ViewportVertexSelectionTarget] {
        targets.compactMap { target in
            vertexSelectionTarget(for: target)
        }
    }

    private func hoveredVertexTarget() -> ViewportVertexSelectionTarget? {
        guard let hoveredTarget = selection.hoveredTarget else {
            return nil
        }
        return vertexSelectionTarget(for: hoveredTarget)
    }

    private func selectedSketchEntityTargets() -> [ViewportSketchEntitySelectionTarget] {
        sketchEntitySelectionTargets(in: selection.selectedTargets)
    }

    private func sketchEntitySelectionTargets(in targets: [SelectionTarget]) -> [ViewportSketchEntitySelectionTarget] {
        targets.compactMap { target in
            sketchEntitySelectionTarget(for: target)
        }
    }

    private func selectedSplineControlPointIdentities() -> Set<ViewportSplineControlPointIdentity> {
        Set(
            selection.selectedTargets.compactMap { target in
                guard case .sketchEntity(let componentID) = target.component,
                      let reference = componentID.sketchControlPointReference,
                      let sceneNodeReference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                      sceneNodeReference.kind == .sketch,
                      sceneNodeReference.featureID == reference.featureID else {
                    return nil
                }
                return ViewportSplineControlPointIdentity(
                    featureID: reference.featureID,
                    entityID: reference.entityID,
                    controlPointIndex: reference.index
                )
            }
        )
    }

    private func selectedSplineControlPointGroups() -> [ViewportSplineControlPointGroup] {
        var groups: [ViewportSplineControlPointGroup] = []
        var groupIndexes: [ViewportSplineControlPointGroupKey: Int] = [:]

        for target in selection.selectedTargets {
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchControlPointReference,
                  let sceneNodeReference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  sceneNodeReference.kind == .sketch,
                  sceneNodeReference.featureID == reference.featureID else {
                continue
            }

            let key = ViewportSplineControlPointGroupKey(
                featureID: reference.featureID,
                entityID: reference.entityID
            )
            if let groupIndex = groupIndexes[key] {
                if groups[groupIndex].controlPointIndexes.contains(reference.index) == false {
                    groups[groupIndex].controlPointIndexes.append(reference.index)
                }
            } else {
                groupIndexes[key] = groups.count
                groups.append(
                    ViewportSplineControlPointGroup(
                        featureID: reference.featureID,
                        entityID: reference.entityID,
                        target: target,
                        controlPointIndexes: [reference.index]
                    )
                )
            }
        }

        return groups
    }

    private func selectedSlotWidthSourceTargets() -> [ViewportSlotWidthSourceTarget] {
        selection.selectedTargets.compactMap { target in
            slotWidthSourceTarget(for: target)
        }
    }

    private func selectedSketchVertexOffsetSourceTargets() -> [ViewportSketchVertexOffsetSourceTarget] {
        selection.selectedTargets.compactMap { target in
            sketchVertexOffsetSourceTarget(for: target)
        }
    }

    private func hoveredSketchEntityTarget() -> ViewportSketchEntitySelectionTarget? {
        guard let hoveredTarget = selection.hoveredTarget else {
            return nil
        }
        return sketchEntitySelectionTarget(for: hoveredTarget)
    }

    private func selectedSketchRegionTargets() -> [ViewportSketchRegionSelectionTarget] {
        sketchRegionSelectionTargets(in: selection.selectedTargets)
    }

    private func sketchRegionSelectionTargets(in targets: [SelectionTarget]) -> [ViewportSketchRegionSelectionTarget] {
        targets.compactMap { target in
            sketchRegionSelectionTarget(for: target)
        }
    }

    private func hoveredSketchRegionTarget() -> ViewportSketchRegionSelectionTarget? {
        guard let hoveredTarget = selection.hoveredTarget else {
            return nil
        }
        return sketchRegionSelectionTarget(for: hoveredTarget)
    }

    private func sketchEntitySelectionTarget(for target: SelectionTarget) -> ViewportSketchEntitySelectionTarget? {
        guard case .sketchEntity(let componentID) = target.component,
              let sketchReference = componentID.sketchEntityBaseReference,
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .sketch,
              reference.featureID == sketchReference.featureID else {
            return nil
        }
        return ViewportSketchEntitySelectionTarget(
            featureID: sketchReference.featureID,
            entityID: sketchReference.entityID
        )
    }

    private func slotWidthSourceTarget(for target: SelectionTarget) -> ViewportSlotWidthSourceTarget? {
        ViewportSlotWidthSourceTargetResolver(document: document)
            .sourceTarget(for: target)
    }

    private func sketchVertexOffsetSourceTarget(for target: SelectionTarget) -> ViewportSketchVertexOffsetSourceTarget? {
        guard case .sketchEntity(let componentID) = target.component,
              let sketchReference = componentID.sketchPointHandleReference,
              Self.isSketchVertexOffsetHandle(sketchReference.handle),
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .sketch,
              reference.featureID == sketchReference.featureID else {
            return nil
        }
        return ViewportSketchVertexOffsetSourceTarget(
            featureID: sketchReference.featureID,
            entityID: sketchReference.entityID,
            handle: sketchReference.handle,
            target: target
        )
    }

    private static func isSketchVertexOffsetHandle(_ handle: SketchEntityPointHandle) -> Bool {
        switch handle {
        case .lineStart, .lineEnd, .arcStart, .arcEnd:
            return true
        default:
            return false
        }
    }

    private func sketchRegionSelectionTarget(for target: SelectionTarget) -> ViewportSketchRegionSelectionTarget? {
        guard case .region(let componentID) = target.component,
              let regionReference = componentID.profileRegionReference,
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .sketch,
              reference.featureID == regionReference.featureID else {
            return nil
        }
        return ViewportSketchRegionSelectionTarget(
            featureID: regionReference.featureID,
            componentID: componentID,
            target: target
        )
    }

    private func regionOffsetAffordanceCandidates(
        targets: [ViewportSketchRegionSelectionTarget],
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportRegionOffsetAffordanceCandidate] {
        guard onRegionOffsetDrag != nil else {
            return []
        }
        return targets.compactMap { target in
            regionOffsetAffordanceCandidate(
                for: target,
                scene: scene,
                layout: layout
            )
        }
    }

    private func regionOffsetAffordanceCandidate(
        for target: ViewportSketchRegionSelectionTarget,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportRegionOffsetAffordanceCandidate? {
        guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
              let region = item.sketchRegions.first(where: { $0.componentID == target.componentID }),
              let geometry = ViewportRegionOffsetAffordanceGeometry(
                  points: region.points,
                  layout: layout
              ) else {
            return nil
        }
        return ViewportRegionOffsetAffordanceCandidate(
            target: ViewportRegionOffsetHandleTarget(
                featureID: target.featureID,
                componentID: target.componentID,
                target: target.target,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func edgeOffsetAffordanceCandidates(
        targets: [ViewportEdgeSelectionTarget],
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportEdgeOffsetAffordanceCandidate] {
        guard onEdgeOffsetDrag != nil else {
            return []
        }
        return targets.compactMap { target in
            edgeOffsetAffordanceCandidate(
                for: target,
                scene: scene,
                layout: layout
            )
        }
    }

    private func edgeOffsetAffordanceCandidate(
        for target: ViewportEdgeSelectionTarget,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportEdgeOffsetAffordanceCandidate? {
        guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
              let projection = bodyProjection(for: item, layout: layout) else {
            return nil
        }
        let segment = projection.segment(for: target.edge)
        let supportPoint = edgeOffsetSupportPoint(
            featureID: target.featureID,
            projection: projection
        )
        guard let geometry = ViewportEdgeOffsetAffordanceGeometry(
            edgeStart: segment.start,
            edgeEnd: segment.end,
            supportPoint: supportPoint,
            fallbackDirection: edgeInwardDirection(projection: projection, edge: target.edge),
            distanceMeters: edgeOffsetDistanceMeters,
            layout: layout
        ) else {
            return nil
        }
        return ViewportEdgeOffsetAffordanceCandidate(
            target: ViewportEdgeOffsetHandleTarget(
                featureID: target.featureID,
                edge: target.edge,
                target: target.target,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func edgeOffsetSupportPoint(
        featureID: FeatureID,
        projection: ViewportBodyProjection
    ) -> CGPoint? {
        let supportFaces = selection.selectedTargets.compactMap { target -> ViewportBodyFace? in
            guard case .face = target.component,
                  let faceTarget = faceSelectionTarget(for: target),
                  faceTarget.featureID == featureID else {
                return nil
            }
            return faceTarget.face
        }
        guard supportFaces.count == 1,
              let supportFace = supportFaces.first else {
            return nil
        }
        return projection.footprint(for: supportFace).center
    }

    private func slotWidthAffordanceCandidates(
        targets: [ViewportSlotWidthSourceTarget],
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSlotWidthAffordanceCandidate] {
        guard onSlotWidthDrag != nil else {
            return []
        }
        return targets.compactMap { target in
            slotWidthAffordanceCandidate(
                for: target,
                scene: scene,
                layout: layout
            )
        }
    }

    private func slotWidthAffordanceCandidate(
        for target: ViewportSlotWidthSourceTarget,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportSlotWidthAffordanceCandidate? {
        guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
              case .sketch(let primitives) = item.kind else {
            return nil
        }
        guard let primitive = displayedSlotWidthPrimitive(
            target: target,
            primitives: primitives,
            featureID: item.featureID
        ) else {
            return nil
        }

        return ViewportSlotWidthAffordanceService().candidate(
            for: target,
            primitives: [primitive],
            widthMeters: slotWidthMeters,
            layout: layout
        )
    }

    private func displayedSlotWidthPrimitive(
        target: ViewportSlotWidthSourceTarget,
        primitives: [ViewportSketchPrimitive],
        featureID: FeatureID
    ) -> ViewportSketchPrimitive? {
        if let line = primitives.firstLine(with: target.entityID) {
            let displayedStart = displayedSketchPointHandlePoint(
                featureID: featureID,
                entityID: target.entityID,
                handle: .lineStart,
                point: line.start
            )
            let displayedEnd = displayedSketchPointHandlePoint(
                featureID: featureID,
                entityID: target.entityID,
                handle: .lineEnd,
                point: line.end
            )
            let displayedLine = displayedSketchDimensionLine(
                featureID: featureID,
                entityID: target.entityID,
                start: displayedStart,
                end: displayedEnd
            )
            return .line(
                entityID: target.entityID,
                start: displayedLine.start,
                end: displayedLine.end
            )
        }

        if let arc = primitives.firstArc(with: target.entityID) {
            let displayedArc = displayedSketchArcParameters(
                featureID: featureID,
                entityID: target.entityID,
                radiusMeters: arc.radiusMeters,
                startAngleRadians: arc.startAngleRadians,
                endAngleRadians: arc.endAngleRadians
            )
            return .arc(
                entityID: target.entityID,
                center: arc.center,
                radiusMeters: displayedArc.radiusMeters,
                startAngleRadians: displayedArc.startAngleRadians,
                endAngleRadians: displayedArc.endAngleRadians
            )
        }

        if let spline = primitives.firstSpline(with: target.entityID) {
            return .spline(
                entityID: target.entityID,
                points: spline.points,
                controlPoints: spline.controlPoints,
                sketchPlane: spline.sketchPlane
            )
        }

        return nil
    }

    private func patternArrayLinearAxisAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayLinearAxisAffordanceCandidate] {
        guard onPatternArrayLinearAxisDrag != nil else {
            return []
        }
        return ViewportPatternArrayLinearAxisAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func independentCopyExtrudeDistanceAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyExtrudeDistanceAffordanceCandidate] {
        guard onIndependentCopyExtrudeDistanceDrag != nil else {
            return []
        }
        return ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func independentCopyBodyDimensionAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportIndependentCopyBodyDimensionAffordanceCandidate] {
        guard onIndependentCopyBodyDimensionDrag != nil else {
            return []
        }
        return ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func patternArrayRadialAngleAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayRadialAngleAffordanceCandidate] {
        guard onPatternArrayRadialAngleDrag != nil else {
            return []
        }
        return ViewportPatternArrayRadialAngleAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func patternArrayCopyCountAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        guard onPatternArrayCopyCountDrag != nil else {
            return []
        }
        return ViewportPatternArrayCopyCountAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func patternArrayCurveExtentAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCurveExtentAffordanceCandidate] {
        guard onPatternArrayCurveExtentDrag != nil else {
            return []
        }
        return ViewportPatternArrayCurveExtentAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func patternArrayCurvePathPointAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCurvePathPointAffordanceCandidate] {
        guard onPatternArrayCurvePathPointDrag != nil else {
            return []
        }
        return ViewportPatternArrayCurvePathPointAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func patternArrayOutputModeAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayOutputModeAffordanceCandidate] {
        guard onPatternArrayOutputModeChange != nil else {
            return []
        }
        return ViewportPatternArrayOutputModeAffordanceService().candidates(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        )
    }

    private func sketchVertexOffsetAffordanceCandidates(
        targets: [ViewportSketchVertexOffsetSourceTarget],
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSketchVertexOffsetAffordanceCandidate] {
        guard onSketchVertexOffsetDrag != nil else {
            return []
        }
        return targets.compactMap { target in
            sketchVertexOffsetAffordanceCandidate(
                for: target,
                scene: scene,
                layout: layout
            )
        }
    }

    private func sketchVertexOffsetAffordanceCandidate(
        for target: ViewportSketchVertexOffsetSourceTarget,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportSketchVertexOffsetAffordanceCandidate? {
        guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
              case .sketch(let primitives) = item.kind,
              let geometryInput = sketchVertexOffsetGeometryInput(
                  target: target,
                  item: item,
                  primitives: primitives
              ),
              let geometry = ViewportSketchVertexOffsetAffordanceGeometry(
                  baseModelPoint: geometryInput.baseModelPoint,
                  modelDirection: geometryInput.modelDirection,
                  distanceMeters: sketchVertexOffsetDistanceMeters,
                  layout: layout
              ) else {
            return nil
        }
        return ViewportSketchVertexOffsetAffordanceCandidate(
            target: ViewportSketchVertexOffsetHandleTarget(
                featureID: target.featureID,
                entityID: target.entityID,
                target: target.target,
                handle: target.handle,
                geometry: geometry
            ),
            geometry: geometry
        )
    }

    private func sketchVertexOffsetGeometryInput(
        target: ViewportSketchVertexOffsetSourceTarget,
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive]
    ) -> (baseModelPoint: CGPoint, modelDirection: CGPoint)? {
        switch target.handle {
        case .lineStart, .lineEnd:
            guard let line = primitives.firstLine(with: target.entityID) else {
                return nil
            }
            let displayedStart = displayedSketchPointHandlePoint(
                featureID: item.featureID,
                entityID: target.entityID,
                handle: .lineStart,
                point: line.start
            )
            let displayedEnd = displayedSketchPointHandlePoint(
                featureID: item.featureID,
                entityID: target.entityID,
                handle: .lineEnd,
                point: line.end
            )
            switch target.handle {
            case .lineStart:
                return (
                    displayedStart,
                    CGPoint(x: displayedEnd.x - displayedStart.x, y: displayedEnd.y - displayedStart.y)
                )
            case .lineEnd:
                return (
                    displayedEnd,
                    CGPoint(x: displayedStart.x - displayedEnd.x, y: displayedStart.y - displayedEnd.y)
                )
            default:
                return nil
            }
        case .arcStart, .arcEnd:
            guard let arc = primitives.firstArc(with: target.entityID) else {
                return nil
            }
            let displayedCenter = displayedSketchPointHandlePoint(
                featureID: item.featureID,
                entityID: target.entityID,
                handle: .arcCenter,
                point: arc.center
            )
            let displayedArc = displayedSketchArcParameters(
                featureID: item.featureID,
                entityID: target.entityID,
                radiusMeters: arc.radiusMeters,
                startAngleRadians: arc.startAngleRadians,
                endAngleRadians: arc.endAngleRadians
            )
            switch target.handle {
            case .arcStart:
                return (
                    pointOnSketchCircle(
                        center: displayedCenter,
                        radiusMeters: displayedArc.radiusMeters,
                        angleRadians: displayedArc.startAngleRadians
                    ),
                    CGPoint(
                        x: -sin(CGFloat(displayedArc.startAngleRadians)),
                        y: cos(CGFloat(displayedArc.startAngleRadians))
                    )
                )
            case .arcEnd:
                return (
                    pointOnSketchCircle(
                        center: displayedCenter,
                        radiusMeters: displayedArc.radiusMeters,
                        angleRadians: displayedArc.endAngleRadians
                    ),
                    CGPoint(
                        x: sin(CGFloat(displayedArc.endAngleRadians)),
                        y: -cos(CGFloat(displayedArc.endAngleRadians))
                    )
                )
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func splineControlPointSlideAffordanceCandidates(
        groups: [ViewportSplineControlPointGroup],
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSplineControlPointSlideAffordanceCandidate] {
        guard onSplineControlPointSlideDrag != nil else {
            return []
        }
        return groups.flatMap { group in
            splineControlPointSlideAffordanceCandidates(
                for: group,
                scene: scene,
                layout: layout
            )
        }
    }

    private func splineControlPointSlideAffordanceCandidates(
        for group: ViewportSplineControlPointGroup,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSplineControlPointSlideAffordanceCandidate] {
        guard let item = scene.items.first(where: { $0.featureID == group.featureID }),
              case .sketch(let primitives) = item.kind,
              let spline = primitives.firstSpline(with: group.entityID) else {
            return []
        }

        return SplineControlPointSlideDirection.allCases.compactMap { direction in
            guard let geometry = ViewportSplineControlPointSlideAffordanceGeometry(
                controlPoints: spline.controlPoints,
                selectedIndexes: group.controlPointIndexes,
                direction: direction,
                layout: layout
            ) else {
                return nil
            }
            let target = ViewportSplineControlPointSlideHandleTarget(
                featureID: group.featureID,
                entityID: group.entityID,
                target: group.target,
                controlPointIndexes: group.controlPointIndexes,
                direction: direction,
                geometry: geometry
            )
            return ViewportSplineControlPointSlideAffordanceCandidate(
                target: target,
                geometry: geometry
            )
        }
    }

    private func polySplineSurfaceVertexSlideAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportPolySplineSurfaceVertexSlideAffordanceCandidate] {
        guard onPolySplineSurfaceVertexSlideDrag != nil else {
            return []
        }
        let inputs = polySplineSurfaceVertexSlideInputs(in: scene)
        guard inputs.isEmpty == false else {
            return []
        }
        let topologyVertices = polySplineSurfaceTopologyVertices(in: scene)
        return PolySplineSurfaceVertexSlideDirection.allCases.compactMap { direction in
            guard let geometry = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
                selectedVertices: inputs,
                topologyVertices: topologyVertices,
                direction: direction,
                layout: layout
            ) else {
                return nil
            }
            let target = ViewportPolySplineSurfaceVertexSlideHandleTarget(
                targets: inputs.map(\.selectionTarget),
                direction: direction,
                geometry: geometry
            )
            return ViewportPolySplineSurfaceVertexSlideAffordanceCandidate(
                target: target,
                geometry: geometry
            )
        }
    }

    private func surfaceControlPointSlideAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSurfaceControlPointSlideAffordanceCandidate] {
        guard onSurfaceControlPointSlideDrag != nil else {
            return []
        }
        let inputs = surfaceControlPointSlideInputs(in: scene)
        guard inputs.isEmpty == false else {
            return []
        }
        let topologyVertices = polySplineSurfaceTopologyVertices(in: scene)
        return PolySplineSurfaceVertexSlideDirection.allCases.compactMap { direction in
            guard let geometry = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
                selectedControlPoints: inputs,
                topologyVertices: topologyVertices,
                direction: direction,
                layout: layout
            ) else {
                return nil
            }
            let target = ViewportSurfaceControlPointSlideHandleTarget(
                targets: inputs.map(\.target),
                direction: direction,
                geometry: geometry
            )
            return ViewportSurfaceControlPointSlideAffordanceCandidate(
                target: target,
                geometry: geometry
            )
        }
    }

    private func surfaceFrameAffordanceCandidates(
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportSurfaceFrameAffordanceCandidate] {
        guard onSurfaceFrameDrag != nil else {
            return []
        }
        let targets = selectedSurfaceFrameControlPointReferences()
        guard targets.isEmpty == false else {
            return []
        }
        return scene.items.flatMap { item -> [ViewportSurfaceFrameAffordanceCandidate] in
            guard case .body(let component) = item.kind else {
                return []
            }
            return component.surfaceFrameDisplays.flatMap { display -> [ViewportSurfaceFrameAffordanceCandidate] in
                ViewportSurfaceFrameAxis.allCases.compactMap { axis in
                    guard let geometry = ViewportSurfaceFrameAxisAffordanceGeometry(
                        display: display,
                        axis: axis,
                        modelTransform: item.modelTransform,
                        layout: layout
                    ) else {
                        return nil
                    }
                    let target = ViewportSurfaceFrameHandleTarget(
                        targets: targets,
                        query: display.query,
                        displayID: display.id,
                        axis: axis,
                        geometry: geometry
                    )
                    return ViewportSurfaceFrameAffordanceCandidate(
                        target: target,
                        geometry: geometry
                    )
                }
            }
        }
    }

    private func selectedSurfaceFrameControlPointReferences() -> [SelectionReference] {
        selection.selectedReferences.reversed().filter { reference in
            guard case .surface(.controlPoint) = reference else {
                return false
            }
            return true
        }
    }

    private func polySplineSurfaceTopologyVertices(
        in scene: ViewportScene
    ) -> [ViewportBodyTopology.Vertex] {
        scene.items.flatMap { item -> [ViewportBodyTopology.Vertex] in
            guard case .body(let component) = item.kind,
                  let topology = component.topology else {
                return []
            }
            return topology.vertices
        }
    }

    private func polySplineSurfaceVertexSlideInputs(
        in scene: ViewportScene
    ) -> [ViewportPolySplineSurfaceVertexSlideInput] {
        selection.selectedTargets.reversed().compactMap { selectionTarget in
            guard case .vertex(let componentID) = selectionTarget.component,
                  let parsedTarget = PolySplineSurfaceVertexTarget.parse(componentID: componentID),
                  let reference = document.productMetadata.sceneNodes[selectionTarget.sceneNodeID]?.reference,
                  reference.kind == .body,
                  let featureID = reference.featureID,
                  featureID == parsedTarget.featureID,
                  let item = scene.items.first(where: { $0.featureID == parsedTarget.featureID }),
                  case .body(let component) = item.kind,
                  let vertex = component.topology?.vertices.first(where: { $0.componentID == componentID }) else {
                return nil
            }
            return ViewportPolySplineSurfaceVertexSlideInput(
                target: parsedTarget,
                selectionTarget: selectionTarget,
                point: vertex.point,
                modelTransform: item.modelTransform
            )
        }
    }

    private func surfaceControlPointSlideInputs(
        in scene: ViewportScene
    ) -> [ViewportSurfaceControlPointSlideInput] {
        selection.selectedReferences.reversed().compactMap { reference in
            guard let patch = surfaceControlPointPatch(for: reference) else {
                return nil
            }
            for item in scene.items {
                guard item.featureID == patch.featureID,
                      case .body(let component) = item.kind,
                      let display = component.surfaceControlPointDisplays.first(where: { display in
                          display.selectionReference == reference
                      }) else {
                    continue
                }
                return ViewportSurfaceControlPointSlideInput(
                    target: reference,
                    featureID: patch.featureID,
                    patchID: patch.patchID,
                    point: display.point,
                    modelTransform: item.modelTransform
                )
            }
            return nil
        }
    }

    private func surfaceControlPointPatch(
        for reference: SelectionReference
    ) -> (featureID: FeatureID, patchID: Int)? {
        guard case .surface(.controlPoint(let controlPoint)) = reference else {
            return nil
        }
        var featureID: FeatureID?
        var generatedRole: String?
        var subshape: String?
        for component in controlPoint.surface.faceName.components {
            switch component {
            case .feature(let id):
                featureID = id
            case .generated(let value):
                generatedRole = value
            case .subshape(let value):
                subshape = value
            case .index:
                return nil
            }
        }
        guard generatedRole == "polySpline",
              let featureID,
              let subshape else {
            return nil
        }
        let parts = subshape.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "face" else {
            return nil
        }
        return (featureID, patchID)
    }

    private func sketchEntityIDs(
        in targets: [ViewportSketchEntitySelectionTarget],
        featureID: FeatureID
    ) -> Set<SketchEntityID> {
        Set(
            targets.compactMap { target in
                target.featureID == featureID ? target.entityID : nil
            }
        )
    }

    private func sketchRegionIDs(
        in targets: [ViewportSketchRegionSelectionTarget],
        featureID: FeatureID
    ) -> Set<SelectionComponentID> {
        Set(
            targets.compactMap { target in
                target.featureID == featureID ? target.componentID : nil
            }
        )
    }

    private func faceSelectionTarget(for target: SelectionTarget) -> ViewportFaceSelectionTarget? {
        guard case .face(let componentID) = target.component,
              let face = viewportBodyFace(for: componentID, target: target),
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .body,
              let featureID = reference.featureID else {
            return nil
        }
        return ViewportFaceSelectionTarget(featureID: featureID, face: face)
    }

    private func edgeSelectionTarget(for target: SelectionTarget) -> ViewportEdgeSelectionTarget? {
        guard case .edge(let componentID) = target.component,
              let edge = viewportBodyEdge(for: componentID, target: target),
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .body,
              let featureID = reference.featureID else {
            return nil
        }
        return ViewportEdgeSelectionTarget(featureID: featureID, edge: edge, target: target)
    }

    private func vertexSelectionTarget(for target: SelectionTarget) -> ViewportVertexSelectionTarget? {
        guard case .vertex(let componentID) = target.component,
              let vertex = viewportBodyVertex(for: componentID, target: target),
              let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              reference.kind == .body,
              let featureID = reference.featureID else {
            return nil
        }
        return ViewportVertexSelectionTarget(featureID: featureID, vertex: vertex)
    }

    private func viewportBodyFace(
        for componentID: SelectionComponentID,
        target: SelectionTarget
    ) -> ViewportBodyFace? {
        switch componentID {
        case .bodyFaceFront:
            return .front
        case .bodyFaceBack:
            return .back
        case .bodyFaceTop:
            return .top
        case .bodyFaceBottom:
            return .bottom
        case .bodyFaceLeft:
            return .left
        case .bodyFaceRight:
            return .right
        case .bodyFaceSide:
            return .side
        default:
            guard componentID.generatedTopologyPersistentName != nil else {
                return nil
            }
            do {
                let bodyFace = try GeneratedTopologySelectionResolver().bodyFace(
                    for: target,
                    in: document,
                    objectRegistry: objectRegistry,
                    operationName: "Viewport generated topology selection"
                )
                return viewportBodyFace(for: bodyFace)
            } catch {
                return nil
            }
        }
    }

    private func viewportBodyFace(for bodyFace: BodyFace) -> ViewportBodyFace {
        switch bodyFace {
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        case .side:
            return .side
        }
    }

    private func viewportBodyEdge(
        for componentID: SelectionComponentID,
        target: SelectionTarget
    ) -> ViewportBodyEdge? {
        switch componentID {
        case .bodyEdgeLeftBottom:
            return .leftBottom
        case .bodyEdgeRightBottom:
            return .rightBottom
        case .bodyEdgeRightTop:
            return .rightTop
        case .bodyEdgeLeftTop:
            return .leftTop
        default:
            guard componentID.generatedTopologyPersistentName != nil else {
                return nil
            }
            do {
                let cornerEdge = try GeneratedTopologySelectionResolver().cornerEdge(
                    for: target,
                    in: document,
                    objectRegistry: objectRegistry,
                    operationName: "Viewport generated topology selection"
                )
                return viewportBodyEdge(for: cornerEdge)
            } catch {
                return nil
            }
        }
    }

    private func viewportBodyEdge(for cornerEdge: BodyCornerEdge) -> ViewportBodyEdge {
        switch cornerEdge {
        case .leftBottom:
            return .leftBottom
        case .rightBottom:
            return .rightBottom
        case .rightTop:
            return .rightTop
        case .leftTop:
            return .leftTop
        }
    }

    private func viewportBodyVertex(
        for componentID: SelectionComponentID,
        target: SelectionTarget
    ) -> ViewportBodyVertex? {
        guard componentID.generatedTopologyPersistentName != nil else {
            return nil
        }
        do {
            let cornerVertex = try GeneratedTopologySelectionResolver().cornerVertex(
                for: target,
                in: document,
                objectRegistry: objectRegistry,
                operationName: "Viewport generated topology selection"
            )
            return viewportBodyVertex(for: cornerVertex)
        } catch {
            return nil
        }
    }

    private func viewportBodyVertex(for cornerVertex: BodyCornerVertex) -> ViewportBodyVertex {
        switch cornerVertex {
        case .frontBottomLeft:
            return .frontBottomLeft
        case .frontBottomRight:
            return .frontBottomRight
        case .frontTopRight:
            return .frontTopRight
        case .frontTopLeft:
            return .frontTopLeft
        case .backBottomLeft:
            return .backBottomLeft
        case .backBottomRight:
            return .backBottomRight
        case .backTopRight:
            return .backTopRight
        case .backTopLeft:
            return .backTopLeft
        }
    }

    private func selectedBodyItems(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> [ViewportSceneItem] {
        scene.items.filter { item in
            guard selectedFeatureIDs.contains(item.featureID),
                  case .body = item.kind else {
                return false
            }
            return true
        }
    }

    private func selectionGroupFeatureID(for bodyItems: [ViewportSceneItem]) -> FeatureID? {
        let bodyFeatureIDs = Set(bodyItems.map(\.featureID))
        return selection.selectedSceneNodeReferences(in: document)
            .compactMap(\.featureID)
            .last(where: { bodyFeatureIDs.contains($0) })
            ?? bodyItems.first?.featureID
    }

    private func selectionGroupEditState(for bodyItems: [ViewportSceneItem]) -> ViewportObjectEditState? {
        let edits = bodyItems.map { item in
            editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        }
        return selectionGroupEditState(for: edits)
    }

    private func selectionGroupEditState(for edits: [ViewportObjectEditState]) -> ViewportObjectEditState? {
        guard let first = edits.first else {
            return nil
        }
        return ViewportObjectEditState(
            xMin: edits.map(\.xMin).min() ?? first.xMin,
            xMax: edits.map(\.xMax).max() ?? first.xMax,
            yMin: edits.map(\.yMin).min() ?? first.yMin,
            yMax: edits.map(\.yMax).max() ?? first.yMax,
            zMin: edits.map(\.zMin).min() ?? first.zMin,
            zMax: edits.map(\.zMax).max() ?? first.zMax
        )
    }

    private func bodyEditStates(for bodyItems: [ViewportSceneItem]) -> [FeatureID: ViewportObjectEditState] {
        Dictionary(
            uniqueKeysWithValues: bodyItems.map { item in
                (
                    item.featureID,
                    editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
                )
            }
        )
    }

    private func hoveredFeatureIDs() -> Set<FeatureID> {
        if let hoveredTarget = selection.hoveredTarget {
            guard case .object = hoveredTarget.component,
                  let featureID = document.productMetadata.sceneNodes[hoveredTarget.sceneNodeID]?.reference?.featureID else {
                return []
            }
            return [featureID]
        }
        guard let hoveredSceneNodeID = selection.hoveredSceneNodeID,
              let featureID = document.productMetadata.sceneNodes[hoveredSceneNodeID]?.reference?.featureID else {
            return []
        }
        return [featureID]
    }

    private func hoveredSceneNodeIDs() -> Set<SceneNodeID> {
        if let hoveredTarget = selection.hoveredTarget,
           case .object = hoveredTarget.component {
            return [hoveredTarget.sceneNodeID]
        }
        return selection.hoveredSceneNodeID.map { [$0] } ?? []
    }

    private func isAffordanceHovered(
        featureID: FeatureID,
        action: ViewportAffordanceAction
    ) -> Bool {
        hoveredAffordance == ViewportAffordanceTarget(featureID: featureID, action: action)
    }

    private func isEdgeFilletAffordanceHovered(
        featureID: FeatureID,
        edge: ViewportBodyEdge
    ) -> Bool {
        guard let hoveredAffordance,
              hoveredAffordance.featureID == featureID,
              case .profileEdgeFillet(_, let hoveredEdge) = hoveredAffordance.action else {
            return false
        }
        return hoveredEdge == edge
    }

    private func highlightedRotationAxis(for featureID: FeatureID) -> ViewportCoordinateAxis? {
        guard let hoveredAffordance,
              hoveredAffordance.featureID == featureID,
              case .rotate(let axis) = hoveredAffordance.action else {
            return nil
        }
        return axis
    }

    private func updateCanvasDragPlaceholder(
        from start: CGPoint?,
        to current: CGPoint?,
        size: CGSize
    ) {
        defer {
            refreshSnapCandidateKind(size: size)
        }
        if start == nil || current == nil {
            clearPendingCanvasInteractionTargets()
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }
        if let start, let current, let pendingSketchCurveHandle {
            updateSketchCurveHandleDrag(
                target: pendingSketchCurveHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSketchCurveHandleDrag != nil {
            return
        }
        if let start, let current, let pendingSketchDimension {
            updateSketchDimensionDrag(
                target: pendingSketchDimension,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSketchDimensionDrag != nil {
            return
        }
        if let start, let current, let pendingSketchPointHandle {
            updateSketchPointHandleDrag(
                target: pendingSketchPointHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSketchPointHandleDrag != nil {
            return
        }
        if let start, let current, let pendingBridgeCurveEndpointHandle {
            updateBridgeCurveEndpointDrag(
                target: pendingBridgeCurveEndpointHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeBridgeCurveEndpointDrag != nil {
            return
        }
        if let start, let current, let pendingSplineControlPointSlideHandle {
            updateSplineControlPointSlideDrag(
                target: pendingSplineControlPointSlideHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSplineControlPointSlideDrag != nil {
            return
        }
        if let start, let current, let pendingPolySplineSurfaceVertexSlideHandle {
            updatePolySplineSurfaceVertexSlideDrag(
                target: pendingPolySplineSurfaceVertexSlideHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activePolySplineSurfaceVertexSlideDrag != nil {
            return
        }
        if let start, let current, let pendingSurfaceControlPointSlideHandle {
            updateSurfaceControlPointSlideDrag(
                target: pendingSurfaceControlPointSlideHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSurfaceControlPointSlideDrag != nil {
            return
        }
        if let start, let current, let pendingSurfaceFrameHandle {
            updateSurfaceFrameDrag(
                target: pendingSurfaceFrameHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSurfaceFrameDrag != nil {
            return
        }
        if let start, let current, let pendingSplineControlPoint {
            updateSplineControlPointDrag(
                target: pendingSplineControlPoint,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSplineControlPointDrag != nil {
            return
        }
        if let start, let current, let pendingPolySplineSurfaceVertex {
            updatePolySplineSurfaceVertexDrag(
                target: pendingPolySplineSurfaceVertex,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activePolySplineSurfaceVertexDrag != nil {
            return
        }
        if let start, let current, let pendingSurfaceControlPoint {
            updateSurfaceControlPointDrag(
                target: pendingSurfaceControlPoint,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSurfaceControlPointDrag != nil {
            return
        }
        if let start, let current, let pendingSurfaceTrimEndpoint {
            updateSurfaceTrimEndpointDrag(
                target: pendingSurfaceTrimEndpoint,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSurfaceTrimEndpointDrag != nil {
            return
        }
        if let start, let current, let pendingSurfaceTrimControlPoint {
            updateSurfaceTrimControlPointDrag(
                target: pendingSurfaceTrimControlPoint,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSurfaceTrimControlPointDrag != nil {
            return
        }
        if let start, let current, let pendingEdgeOffsetHandle {
            updateEdgeOffsetDrag(
                target: pendingEdgeOffsetHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeEdgeOffsetDrag != nil {
            return
        }
        if let start, let current, let pendingSlotWidthHandle {
            updateSlotWidthDrag(
                target: pendingSlotWidthHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSlotWidthDrag != nil {
            return
        }
        if let start, let current, let pendingIndependentCopyExtrudeDistanceHandle {
            updateIndependentCopyExtrudeDistanceDrag(
                target: pendingIndependentCopyExtrudeDistanceHandle,
                start: start,
                current: current
            )
            return
        }
        if activeIndependentCopyExtrudeDistanceDrag != nil {
            return
        }
        if let start, let current, let pendingIndependentCopyBodyDimensionHandle {
            updateIndependentCopyBodyDimensionDrag(
                target: pendingIndependentCopyBodyDimensionHandle,
                start: start,
                current: current
            )
            return
        }
        if activeIndependentCopyBodyDimensionDrag != nil {
            return
        }
        if let start, let current, let pendingPatternArrayLinearAxisHandle {
            updatePatternArrayLinearAxisDrag(
                target: pendingPatternArrayLinearAxisHandle,
                start: start,
                current: current
            )
            return
        }
        if activePatternArrayLinearAxisDrag != nil {
            return
        }
        if let start, let current, let pendingPatternArrayRadialAngleHandle {
            updatePatternArrayRadialAngleDrag(
                target: pendingPatternArrayRadialAngleHandle,
                start: start,
                current: current
            )
            return
        }
        if activePatternArrayRadialAngleDrag != nil {
            return
        }
        if let start, let current, let pendingPatternArrayCopyCountHandle {
            updatePatternArrayCopyCountDrag(
                target: pendingPatternArrayCopyCountHandle,
                start: start,
                current: current
            )
            return
        }
        if activePatternArrayCopyCountDrag != nil {
            return
        }
        if let start, let current, let pendingPatternArrayCurveExtentHandle {
            updatePatternArrayCurveExtentDrag(
                target: pendingPatternArrayCurveExtentHandle,
                start: start,
                current: current
            )
            return
        }
        if activePatternArrayCurveExtentDrag != nil {
            return
        }
        if let start, let current, let pendingPatternArrayCurvePathPointHandle {
            updatePatternArrayCurvePathPointDrag(
                target: pendingPatternArrayCurvePathPointHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activePatternArrayCurvePathPointDrag != nil {
            return
        }
        if let start, let current, let pendingSketchVertexOffsetHandle {
            updateSketchVertexOffsetDrag(
                target: pendingSketchVertexOffsetHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeSketchVertexOffsetDrag != nil {
            return
        }
        if let start, let current, let pendingRegionOffsetHandle {
            updateRegionOffsetDrag(
                target: pendingRegionOffsetHandle,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeRegionOffsetDrag != nil {
            return
        }
        if let start, let current, let pendingAffordance {
            updateAffordanceDrag(
                target: pendingAffordance,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeAffordanceDrag != nil {
            return
        }
        guard let start, let current else {
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }

        let dragDistance = hypot(current.x - start.x, current.y - start.y)
        guard dragDistance > 4.0 else {
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }

        if allowsSelectionRectangle {
            activeCanvasDrag = ViewportActiveDrag(
                startLocation: start,
                currentLocation: current,
                kind: .selection
            )
            publishSelectionDragPreview(from: start, to: current, size: size)
            return
        }

        guard let canvasDragPreviewKind, onCanvasDrag != nil else {
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }

        publishSelectionDragPreview(hits: [])
        activeCanvasDrag = ViewportActiveDrag(
            startLocation: start,
            currentLocation: current,
            kind: .creation(canvasDragPreviewKind),
            sketchPlane: canvasDragSketchPlane(for: hoveredCanvasHit)
        )
    }

    private func clearPendingCanvasInteractionTargets() {
        pendingAffordance = nil
        pendingSketchCurveHandle = nil
        pendingSketchDimension = nil
        pendingSketchPointHandle = nil
        pendingBridgeCurveEndpointHandle = nil
        pendingSplineControlPoint = nil
        pendingSplineControlPointSlideHandle = nil
        pendingPolySplineSurfaceVertex = nil
        pendingSurfaceControlPoint = nil
        pendingSurfaceTrimEndpoint = nil
        pendingSurfaceTrimControlPoint = nil
        pendingPolySplineSurfaceVertexSlideHandle = nil
        pendingSurfaceControlPointSlideHandle = nil
        pendingSurfaceFrameHandle = nil
        pendingRegionOffsetHandle = nil
        pendingEdgeOffsetHandle = nil
        pendingSlotWidthHandle = nil
        pendingSketchVertexOffsetHandle = nil
        pendingPatternArrayLinearAxisHandle = nil
        pendingIndependentCopyExtrudeDistanceHandle = nil
        pendingIndependentCopyBodyDimensionHandle = nil
        pendingPatternArrayRadialAngleHandle = nil
        pendingPatternArrayCopyCountHandle = nil
        pendingPatternArrayCurveExtentHandle = nil
        pendingPatternArrayCurvePathPointHandle = nil
        pendingPatternArrayOutputModeHandle = nil
        activeAffordanceDrag = nil
        activeSketchCurveHandleDrag = nil
        activeSketchDimensionDrag = nil
        activeSketchPointHandleDrag = nil
        activeBridgeCurveEndpointDrag = nil
        activeSplineControlPointDrag = nil
        activeSplineControlPointSlideDrag = nil
        activePolySplineSurfaceVertexDrag = nil
        activeSurfaceControlPointDrag = nil
        activeSurfaceTrimEndpointDrag = nil
        activeSurfaceTrimControlPointDrag = nil
        activePolySplineSurfaceVertexSlideDrag = nil
        activeSurfaceControlPointSlideDrag = nil
        activeSurfaceFrameDrag = nil
        activeRegionOffsetDrag = nil
        activeEdgeOffsetDrag = nil
        activeSlotWidthDrag = nil
        activeSketchVertexOffsetDrag = nil
        activePatternArrayLinearAxisDrag = nil
        activeIndependentCopyExtrudeDistanceDrag = nil
        activeIndependentCopyBodyDimensionDrag = nil
        activePatternArrayRadialAngleDrag = nil
        activePatternArrayCopyCountDrag = nil
        activePatternArrayCurveExtentDrag = nil
        activePatternArrayCurvePathPointDrag = nil
    }

    private func beginViewportPress(at point: CGPoint, size: CGSize) {
        if let sketchCurveHandleTarget = selectedSketchCurveHandleTarget(at: point, size: size) {
            pendingSketchCurveHandle = sketchCurveHandleTarget
            activeCanvasDrag = nil
            return
        }
        if let sketchPointHandleTarget = selectedSketchPointHandleTarget(at: point, size: size) {
            pendingSketchPointHandle = sketchPointHandleTarget
            activeCanvasDrag = nil
            return
        }
        if let sketchDimensionTarget = selectedSketchDimensionTarget(at: point, size: size) {
            pendingSketchDimension = sketchDimensionTarget
            activeCanvasDrag = nil
            return
        }
        if onBridgeCurveEndpointDrag != nil,
           let bridgeCurveEndpointTarget = selectedBridgeCurveEndpointTarget(at: point, size: size) {
            pendingBridgeCurveEndpointHandle = bridgeCurveEndpointTarget
            activeCanvasDrag = nil
            return
        }
        if let splineControlPointSlideTarget = selectedSplineControlPointSlideAffordanceTarget(at: point, size: size) {
            pendingSplineControlPointSlideHandle = splineControlPointSlideTarget
            activeCanvasDrag = nil
            return
        }
        if let polySplineSurfaceVertexSlideTarget = selectedPolySplineSurfaceVertexSlideAffordanceTarget(at: point, size: size) {
            pendingPolySplineSurfaceVertexSlideHandle = polySplineSurfaceVertexSlideTarget
            activeCanvasDrag = nil
            return
        }
        if let surfaceControlPointSlideTarget = selectedSurfaceControlPointSlideAffordanceTarget(at: point, size: size) {
            pendingSurfaceControlPointSlideHandle = surfaceControlPointSlideTarget
            activeCanvasDrag = nil
            return
        }
        if let surfaceFrameTarget = selectedSurfaceFrameAffordanceTarget(at: point, size: size) {
            pendingSurfaceFrameHandle = surfaceFrameTarget
            activeCanvasDrag = nil
            return
        }
        if let edgeOffsetTarget = selectedEdgeOffsetAffordanceTarget(at: point, size: size) {
            pendingEdgeOffsetHandle = edgeOffsetTarget
            activeCanvasDrag = nil
            return
        }
        if let slotWidthTarget = selectedSlotWidthAffordanceTarget(at: point, size: size) {
            pendingSlotWidthHandle = slotWidthTarget
            activeCanvasDrag = nil
            return
        }
        if let independentCopyExtrudeDistanceTarget = selectedIndependentCopyExtrudeDistanceAffordanceTarget(at: point, size: size) {
            pendingIndependentCopyExtrudeDistanceHandle = independentCopyExtrudeDistanceTarget
            activeCanvasDrag = nil
            return
        }
        if let independentCopyBodyDimensionTarget = selectedIndependentCopyBodyDimensionAffordanceTarget(at: point, size: size) {
            pendingIndependentCopyBodyDimensionHandle = independentCopyBodyDimensionTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayLinearAxisTarget = selectedPatternArrayLinearAxisAffordanceTarget(at: point, size: size) {
            pendingPatternArrayLinearAxisHandle = patternArrayLinearAxisTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayRadialAngleTarget = selectedPatternArrayRadialAngleAffordanceTarget(at: point, size: size) {
            pendingPatternArrayRadialAngleHandle = patternArrayRadialAngleTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayCopyCountTarget = selectedPatternArrayCopyCountAffordanceTarget(at: point, size: size) {
            pendingPatternArrayCopyCountHandle = patternArrayCopyCountTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayCurveExtentTarget = selectedPatternArrayCurveExtentAffordanceTarget(at: point, size: size) {
            pendingPatternArrayCurveExtentHandle = patternArrayCurveExtentTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayCurvePathPointTarget = selectedPatternArrayCurvePathPointAffordanceTarget(at: point, size: size) {
            pendingPatternArrayCurvePathPointHandle = patternArrayCurvePathPointTarget
            activeCanvasDrag = nil
            return
        }
        if let patternArrayOutputModeTarget = selectedPatternArrayOutputModeAffordanceTarget(at: point, size: size) {
            pendingPatternArrayOutputModeHandle = patternArrayOutputModeTarget
            activeCanvasDrag = nil
            return
        }
        if let sketchVertexOffsetTarget = selectedSketchVertexOffsetAffordanceTarget(at: point, size: size) {
            pendingSketchVertexOffsetHandle = sketchVertexOffsetTarget
            activeCanvasDrag = nil
            return
        }
        if let regionOffsetTarget = selectedRegionOffsetAffordanceTarget(at: point, size: size) {
            pendingRegionOffsetHandle = regionOffsetTarget
            activeCanvasDrag = nil
            return
        }
        if let splineControlPointTarget = selectedSplineControlPointTarget(at: point, size: size) {
            pendingSplineControlPoint = splineControlPointTarget
            activeCanvasDrag = nil
            return
        }
        if let polySplineSurfaceVertexTarget = selectedPolySplineSurfaceVertexTarget(at: point, size: size) {
            pendingPolySplineSurfaceVertex = polySplineSurfaceVertexTarget
            activeCanvasDrag = nil
            return
        }
        if let surfaceControlPointTarget = selectedSurfaceControlPointTarget(at: point, size: size) {
            pendingSurfaceControlPoint = surfaceControlPointTarget
            activeCanvasDrag = nil
            return
        }
        if let surfaceTrimEndpointTarget = selectedSurfaceTrimEndpointTarget(at: point, size: size) {
            pendingSurfaceTrimEndpoint = surfaceTrimEndpointTarget
            activeCanvasDrag = nil
            return
        }
        if let surfaceTrimControlPointTarget = selectedSurfaceTrimControlPointTarget(at: point, size: size) {
            pendingSurfaceTrimControlPoint = surfaceTrimControlPointTarget
            activeCanvasDrag = nil
            return
        }
        if let vertexTarget = selectedVertexAffordanceTarget(at: point, size: size) {
            pendingAffordance = vertexTarget
            activeCanvasDrag = nil
            return
        }
        if let faceTarget = selectedFaceAffordanceTarget(at: point, size: size) {
            pendingAffordance = faceTarget
            activeCanvasDrag = nil
            return
        }
        if let edgeFilletTarget = selectedEdgeFilletAffordanceTarget(at: point, size: size) {
            pendingAffordance = edgeFilletTarget
            activeCanvasDrag = nil
            return
        }
        if let edgeTarget = selectedEdgeAffordanceTarget(at: point, size: size) {
            pendingAffordance = edgeTarget
            activeCanvasDrag = nil
            return
        }
        guard allowsObjectAffordances else {
            pendingAffordance = nil
            return
        }
        pendingAffordance = affordanceTarget(at: point, size: size)
        if pendingAffordance != nil {
            activeCanvasDrag = nil
        }
    }

    private func selectedSketchCurveHandleTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSketchCurveHandleTarget? {
        guard onSketchCurveHandleDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        var bestTarget: (target: ViewportSketchCurveHandleTarget, distance: CGFloat)?
        for selectionTarget in selection.selectedTargets.reversed() {
            guard case .sketchEntity = selectionTarget.component,
                  let sketchTarget = sketchEntitySelectionTarget(for: selectionTarget),
                  let item = scene.items.first(where: { $0.featureID == sketchTarget.featureID }),
                  case .sketch(let primitives) = item.kind,
                  let sketchPlane = sketchPlane(forFeatureID: sketchTarget.featureID) else {
                continue
            }
            for primitive in primitives where primitive.entityID == sketchTarget.entityID {
                for handle in sketchCurveHandles(for: primitive) {
                    let distance = point.distance(to: layout.project(handle.point))
                    guard distance <= handleTolerance else {
                        continue
                    }
                    let candidate = ViewportSketchCurveHandleTarget(
                        featureID: sketchTarget.featureID,
                        entityID: sketchTarget.entityID,
                        target: selectionTarget,
                        handle: handle.handle,
                        sketchPlane: sketchPlane,
                        center: handle.center,
                        radiusMeters: handle.radiusMeters,
                        startAngleRadians: handle.startAngleRadians,
                        endAngleRadians: handle.endAngleRadians
                    )
                    if let current = bestTarget {
                        if distance < current.distance {
                            bestTarget = (candidate, distance)
                        }
                    } else {
                        bestTarget = (candidate, distance)
                    }
                }
            }
        }
        return bestTarget?.target
    }

    private func selectedSketchDimensionTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSketchDimensionTarget? {
        guard onSketchDimensionDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        var bestTarget: (target: ViewportSketchDimensionTarget, distance: CGFloat)?
        for selectionTarget in selection.selectedTargets.reversed() {
            guard case .sketchEntity = selectionTarget.component,
                  let sketchTarget = sketchEntitySelectionTarget(for: selectionTarget),
                  let item = scene.items.first(where: { $0.featureID == sketchTarget.featureID }),
                  case .sketch(let primitives) = item.kind,
                  let sketchPlane = sketchPlane(forFeatureID: sketchTarget.featureID) else {
                continue
            }
            for primitive in primitives where primitive.entityID == sketchTarget.entityID {
                for candidate in sketchDimensionCandidates(for: primitive, layout: layout) {
                    let hitRect = candidate.rect.insetBy(dx: -4.0, dy: -4.0)
                    guard hitRect.contains(point) else {
                        continue
                    }
                    let distance = point.distance(to: CGPoint(x: candidate.rect.midX, y: candidate.rect.midY))
                    let dimensionTarget = ViewportSketchDimensionTarget(
                        featureID: sketchTarget.featureID,
                        entityID: sketchTarget.entityID,
                        target: selectionTarget,
                        kind: candidate.kind,
                        sketchPlane: sketchPlane,
                        baselineValue: candidate.baselineValue,
                        start: candidate.start,
                        end: candidate.end,
                        center: candidate.center,
                        radiusMeters: candidate.radiusMeters,
                        startAngleRadians: candidate.startAngleRadians,
                        endAngleRadians: candidate.endAngleRadians
                    )
                    if let current = bestTarget {
                        if distance < current.distance {
                            bestTarget = (dimensionTarget, distance)
                        }
                    } else {
                        bestTarget = (dimensionTarget, distance)
                    }
                }
            }
        }
        return bestTarget?.target
    }

    private func sketchDimensionCandidates(
        for primitive: ViewportSketchPrimitive,
        layout: ViewportLayout
    ) -> [ViewportSketchDimensionCandidate] {
        switch primitive {
        case .line(_, let start, let end):
            let projectedStart = layout.project(start)
            let projectedEnd = layout.project(end)
            let length = hypot(Double(end.x - start.x), Double(end.y - start.y))
            let angle = atan2(Double(end.y - start.y), Double(end.x - start.x))
            let label = "L \(formattedViewportLength(length)) / A \(formattedViewportAngle(angle))"
            let labelPoint = lineDimensionLabelPoint(start: projectedStart, end: projectedEnd)
            let labelRect = dimensionLabelRect(for: label, at: labelPoint)
            let lengthRect = CGRect(
                x: labelRect.minX,
                y: labelRect.minY,
                width: labelRect.width / 2.0,
                height: labelRect.height
            )
            let angleRect = CGRect(
                x: labelRect.midX,
                y: labelRect.minY,
                width: labelRect.width / 2.0,
                height: labelRect.height
            )
            return [
                ViewportSketchDimensionCandidate(
                    kind: .length,
                    rect: lengthRect,
                    baselineValue: length,
                    start: start,
                    end: end,
                    center: nil,
                    radiusMeters: nil,
                    startAngleRadians: nil,
                    endAngleRadians: nil
                ),
                ViewportSketchDimensionCandidate(
                    kind: .angle,
                    rect: angleRect,
                    baselineValue: angle,
                    start: start,
                    end: end,
                    center: nil,
                    radiusMeters: nil,
                    startAngleRadians: nil,
                    endAngleRadians: nil
                ),
            ]
        case .circle(_, let center, let radiusMeters):
            let radiusPoint = layout.project(circleRadiusHandlePoint(center: center, radiusMeters: radiusMeters))
            let label = "R \(formattedViewportLength(radiusMeters))"
            let labelPoint = circleDimensionLabelPoint(radiusPoint: radiusPoint)
            return [
                ViewportSketchDimensionCandidate(
                    kind: .radius,
                    rect: dimensionLabelRect(for: label, at: labelPoint),
                    baselineValue: radiusMeters,
                    start: nil,
                    end: nil,
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: nil,
                    endAngleRadians: nil
                ),
            ]
        case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
            let span = normalizedArcSpan(startAngle: startAngle, endAngle: endAngle)
            let radiusPoint = arcRadiusHandlePoint(
                center: center,
                radiusMeters: radiusMeters,
                startAngleRadians: startAngle,
                endAngleRadians: endAngle
            )
            let projectedCenter = layout.project(center)
            let projectedRadius = layout.project(radiusPoint)
            let label = "R \(formattedViewportLength(radiusMeters)) / A \(formattedViewportAngle(span))"
            let labelPoint = arcDimensionLabelPoint(center: projectedCenter, radiusPoint: projectedRadius)
            let labelRect = dimensionLabelRect(for: label, at: labelPoint)
            let radiusRect = CGRect(
                x: labelRect.minX,
                y: labelRect.minY,
                width: labelRect.width / 2.0,
                height: labelRect.height
            )
            let angleRect = CGRect(
                x: labelRect.midX,
                y: labelRect.minY,
                width: labelRect.width / 2.0,
                height: labelRect.height
            )
            return [
                ViewportSketchDimensionCandidate(
                    kind: .radius,
                    rect: radiusRect,
                    baselineValue: radiusMeters,
                    start: nil,
                    end: nil,
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ),
                ViewportSketchDimensionCandidate(
                    kind: .angle,
                    rect: angleRect,
                    baselineValue: span,
                    start: nil,
                    end: nil,
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ),
            ]
        case .point, .spline:
            return []
        }
    }

    private func sketchCurveHandles(
        for primitive: ViewportSketchPrimitive
    ) -> [ViewportSketchCurveHandleCandidate] {
        switch primitive {
        case .circle(_, let center, let radiusMeters):
            return [
                ViewportSketchCurveHandleCandidate(
                    handle: .circleRadius,
                    point: circleRadiusHandlePoint(
                        center: center,
                        radiusMeters: radiusMeters
                    ),
                    center: center,
                    radiusMeters: radiusMeters
                ),
            ]
        case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
            return [
                ViewportSketchCurveHandleCandidate(
                    handle: .arcRadius,
                    point: arcRadiusHandlePoint(
                        center: center,
                        radiusMeters: radiusMeters,
                        startAngleRadians: startAngle,
                        endAngleRadians: endAngle
                    ),
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ),
                ViewportSketchCurveHandleCandidate(
                    handle: .arcStartAngle,
                    point: pointOnSketchCircle(
                        center: center,
                        radiusMeters: radiusMeters,
                        angleRadians: startAngle
                    ),
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ),
                ViewportSketchCurveHandleCandidate(
                    handle: .arcEndAngle,
                    point: pointOnSketchCircle(
                        center: center,
                        radiusMeters: radiusMeters,
                        angleRadians: endAngle
                    ),
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ),
            ]
        case .point, .line, .spline:
            return []
        }
    }

    private func selectedSketchPointHandleTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSketchPointHandleTarget? {
        guard onSketchPointHandleDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        for target in selection.selectedTargets.reversed() {
            guard case .sketchEntity = target.component,
                  let sketchTarget = sketchEntitySelectionTarget(for: target),
                  allowsPointHandleInteraction(
                    featureID: sketchTarget.featureID,
                    entityID: sketchTarget.entityID
                  ),
                  let item = scene.items.first(where: { $0.featureID == sketchTarget.featureID }),
                  case .sketch(let primitives) = item.kind,
                  let sketchPlane = sketchPlane(forFeatureID: sketchTarget.featureID) else {
                continue
            }
            for primitive in primitives where primitive.entityID == sketchTarget.entityID {
                for handle in sketchPointHandles(for: primitive).reversed() {
                    let projectedPoint = layout.project(handle.point)
                    guard point.distance(to: projectedPoint) <= handleTolerance else {
                        continue
                    }
                    return ViewportSketchPointHandleTarget(
                        featureID: sketchTarget.featureID,
                        entityID: sketchTarget.entityID,
                        target: target,
                        handle: handle.handle,
                        sketchPlane: sketchPlane
                    )
                }
            }
        }
        return nil
    }

    private func sketchPointHandles(
        for primitive: ViewportSketchPrimitive
    ) -> [(handle: SketchEntityPointHandle, point: CGPoint)] {
        switch primitive {
        case .point(_, let point):
            return [(handle: .point, point: point)]
        case .line(_, let start, let end):
            return [
                (handle: .lineStart, point: start),
                (handle: .lineEnd, point: end),
            ]
        case .circle(_, let center, _):
            return [(handle: .circleCenter, point: center)]
        case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
            return [
                (handle: .arcCenter, point: center),
                (
                    handle: .arcStart,
                    point: pointOnSketchCircle(
                        center: center,
                        radiusMeters: radiusMeters,
                        angleRadians: startAngle
                    )
                ),
                (
                    handle: .arcEnd,
                    point: pointOnSketchCircle(
                        center: center,
                        radiusMeters: radiusMeters,
                        angleRadians: endAngle
                    )
                ),
            ]
        case .spline:
            return []
        }
    }

    private func sketchPlane(forFeatureID featureID: FeatureID) -> SketchPlane? {
        guard let node = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = node.operation else {
            return nil
        }
        return sketch.plane
    }

    private func selectedSplineControlPointTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSplineControlPointHandleTarget? {
        guard onSplineControlPointDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        for target in selection.selectedTargets.reversed() {
            guard case .sketchEntity = target.component,
                  let sketchTarget = sketchEntitySelectionTarget(for: target),
                  allowsPointHandleInteraction(
                    featureID: sketchTarget.featureID,
                    entityID: sketchTarget.entityID
                  ),
                  let item = scene.items.first(where: { $0.featureID == sketchTarget.featureID }),
                  case .sketch(let primitives) = item.kind else {
                continue
            }
            for primitive in primitives {
                guard case .spline(
                    let entityID,
                    _,
                    let controlPoints,
                    let sketchPlane
                ) = primitive,
                      entityID == sketchTarget.entityID else {
                    continue
                }
                for index in controlPoints.indices.reversed() {
                    let projectedPoint = layout.project(controlPoints[index])
                    guard point.distance(to: projectedPoint) <= handleTolerance else {
                        continue
                    }
                    return ViewportSplineControlPointHandleTarget(
                        featureID: sketchTarget.featureID,
                        entityID: entityID,
                        target: target,
                        controlPointIndex: index,
                        sketchPlane: sketchPlane
                    )
                }
            }
        }
        return nil
    }

    private func selectedPolySplineSurfaceVertexTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPolySplineSurfaceVertexHandleTarget? {
        guard onPolySplineSurfaceVertexDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let topologyVertices = polySplineSurfaceTopologyVertices(in: scene)
        let handleTolerance: CGFloat = 12.0
        for target in polySplineSurfaceVertexHandleTargets(in: scene) {
            if let localAxisHit = polySplineSurfaceVertexLocalAxisHit(
                at: point,
                target: target,
                topologyVertices: topologyVertices,
                layout: layout
            ) {
                return ViewportPolySplineSurfaceVertexHandleTarget(
                    featureID: target.featureID,
                    target: target.target,
                    componentID: target.componentID,
                    point: target.point,
                    modelTransform: target.modelTransform,
                    dragMode: .localAxis(localAxisHit.axis, direction: localAxisHit.direction)
                )
            }
            if let axis = polySplineSurfaceVertexAxisHit(
                at: point,
                target: target,
                layout: layout
            ) {
                return ViewportPolySplineSurfaceVertexHandleTarget(
                    featureID: target.featureID,
                    target: target.target,
                    componentID: target.componentID,
                    point: target.point,
                    modelTransform: target.modelTransform,
                    dragMode: .axis(axis)
                )
            }
        }
        for target in polySplineSurfaceVertexHandleTargets(in: scene) {
            let projectedPoint = target.geometry.projectedPoint(layout: layout)
            guard point.distance(to: projectedPoint) <= handleTolerance else {
                continue
            }
            return target
        }
        return nil
    }

    private func selectedSurfaceControlPointTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSurfaceControlPointHandleTarget? {
        guard onSurfaceControlPointDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        for target in surfaceControlPointHandleTargets(in: scene) {
            if let axis = surfaceControlPointAxisHit(
                at: point,
                target: target,
                layout: layout
            ) {
                return ViewportSurfaceControlPointHandleTarget(
                    featureID: target.featureID,
                    target: target.target,
                    point: target.point,
                    modelTransform: target.modelTransform,
                    dragMode: .axis(axis)
                )
            }
        }
        for target in surfaceControlPointHandleTargets(in: scene) {
            let projectedPoint = target.geometry.projectedPoint(layout: layout)
            guard point.distance(to: projectedPoint) <= handleTolerance else {
                continue
            }
            return target
        }
        return nil
    }

    private func selectedSurfaceTrimEndpointTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSurfaceTrimEndpointHandleTarget? {
        guard onSurfaceTrimEndpointDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        var nearest: (target: ViewportSurfaceTrimEndpointHandleTarget, distance: CGFloat)?
        for target in surfaceTrimEndpointHandleTargets(in: scene) {
            let projectedPoint = target.geometry.projectedPoint(layout: layout)
            let distance = point.distance(to: projectedPoint)
            guard distance <= handleTolerance else {
                continue
            }
            if let current = nearest {
                if distance < current.distance {
                    nearest = (target, distance)
                }
            } else {
                nearest = (target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedBridgeCurveEndpointTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportBridgeCurveEndpointHandleTarget? {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let service = ViewportBridgeCurveEndpointAffordanceService()
        let candidates = service.candidatesOrEmpty(
            document: document,
            scene: sceneContext.scene,
            selection: selection,
            layout: sceneContext.layout
        )
        return service.target(at: point, candidates: candidates)
    }

    private func selectedSurfaceTrimControlPointTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSurfaceTrimControlPointHandleTarget? {
        guard onSurfaceTrimControlPointDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        var nearest: (target: ViewportSurfaceTrimControlPointHandleTarget, distance: CGFloat)?
        for target in surfaceTrimControlPointHandleTargets(in: scene) {
            let projectedPoint = target.geometry.projectedPoint(layout: layout)
            let distance = point.distance(to: projectedPoint)
            guard distance <= handleTolerance else {
                continue
            }
            if let current = nearest {
                if distance < current.distance {
                    nearest = (target, distance)
                }
            } else {
                nearest = (target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedPolySplineSurfaceVertexSlideAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPolySplineSurfaceVertexSlideHandleTarget? {
        guard onPolySplineSurfaceVertexSlideDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        var nearest: (target: ViewportPolySplineSurfaceVertexSlideHandleTarget, distance: CGFloat)?
        for candidate in polySplineSurfaceVertexSlideAffordanceCandidates(
            scene: scene,
            layout: layout
        ) {
            guard let distance = polySplineSurfaceVertexSlideAffordanceHitDistance(
                at: point,
                candidate: candidate,
                layout: layout
            ) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedSurfaceControlPointSlideAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSurfaceControlPointSlideHandleTarget? {
        guard onSurfaceControlPointSlideDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        var nearest: (target: ViewportSurfaceControlPointSlideHandleTarget, distance: CGFloat)?
        for candidate in surfaceControlPointSlideAffordanceCandidates(
            scene: scene,
            layout: layout
        ) {
            guard let distance = surfaceControlPointSlideAffordanceHitDistance(
                at: point,
                candidate: candidate,
                layout: layout
            ) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedSurfaceFrameAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSurfaceFrameHandleTarget? {
        guard onSurfaceFrameDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        var nearest: (target: ViewportSurfaceFrameHandleTarget, distance: CGFloat)?
        for candidate in surfaceFrameAffordanceCandidates(
            scene: scene,
            layout: layout
        ) {
            guard let distance = surfaceFrameAffordanceHitDistance(
                at: point,
                candidate: candidate,
                layout: layout
            ) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func polySplineSurfaceVertexSlideAffordanceHitDistance(
        at point: CGPoint,
        candidate: ViewportPolySplineSurfaceVertexSlideAffordanceCandidate,
        layout: ViewportLayout
    ) -> CGFloat? {
        let center = layout.project(candidate.geometry.baseModelPoint)
        let endpoint = candidate.geometry.projectedTip(layout: layout)
        let handleGap: CGFloat = 16.0
        let handleTolerance: CGFloat = 8.0
        let vector = CGVector(dx: endpoint.x - center.x, dy: endpoint.y - center.y)
        let length = vector.length
        guard length > handleGap + 1.0 else {
            return nil
        }
        let direction = vector.normalized
        let segmentStart = CGPoint(
            x: center.x + direction.dx * handleGap,
            y: center.y + direction.dy * handleGap
        )
        let distance = min(
            point.distance(to: endpoint),
            point.distanceToSegment(start: segmentStart, end: endpoint)
        )
        guard distance <= handleTolerance else {
            return nil
        }
        return distance
    }

    private func surfaceControlPointSlideAffordanceHitDistance(
        at point: CGPoint,
        candidate: ViewportSurfaceControlPointSlideAffordanceCandidate,
        layout: ViewportLayout
    ) -> CGFloat? {
        let center = layout.project(candidate.geometry.baseModelPoint)
        let endpoint = candidate.geometry.projectedTip(layout: layout)
        let handleGap: CGFloat = 16.0
        let handleTolerance: CGFloat = 8.0
        let vector = CGVector(dx: endpoint.x - center.x, dy: endpoint.y - center.y)
        let length = vector.length
        guard length > handleGap + 1.0 else {
            return nil
        }
        let direction = vector.normalized
        let segmentStart = CGPoint(
            x: center.x + direction.dx * handleGap,
            y: center.y + direction.dy * handleGap
        )
        let distance = min(
            point.distance(to: endpoint),
            point.distanceToSegment(start: segmentStart, end: endpoint)
        )
        guard distance <= handleTolerance else {
            return nil
        }
        return distance
    }

    private func surfaceFrameAffordanceHitDistance(
        at point: CGPoint,
        candidate: ViewportSurfaceFrameAffordanceCandidate,
        layout: ViewportLayout
    ) -> CGFloat? {
        let center = layout.project(candidate.geometry.baseModelPoint)
        let endpoint = candidate.geometry.projectedTip(layout: layout)
        let handleGap: CGFloat = 10.0
        let handleTolerance: CGFloat = 8.0
        let vector = CGVector(dx: endpoint.x - center.x, dy: endpoint.y - center.y)
        let length = vector.length
        guard length > handleGap + 1.0 else {
            return nil
        }
        let direction = vector.normalized
        let segmentStart = CGPoint(
            x: center.x + direction.dx * handleGap,
            y: center.y + direction.dy * handleGap
        )
        let distance = min(
            point.distance(to: endpoint),
            point.distanceToSegment(start: segmentStart, end: endpoint)
        )
        guard distance <= handleTolerance else {
            return nil
        }
        return distance
    }

    private func polySplineSurfaceVertexHandleTargets(
        in scene: ViewportScene
    ) -> [ViewportPolySplineSurfaceVertexHandleTarget] {
        selection.selectedTargets.reversed().compactMap { target in
            guard case .vertex(let componentID) = target.component,
                  isPolySplineSurfaceVertex(componentID),
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body,
                  let featureID = reference.featureID,
                  let item = scene.items.first(where: { $0.featureID == featureID }),
                  case .body(let component) = item.kind,
                  let vertex = component.topology?.vertices.first(where: { $0.componentID == componentID }) else {
                return nil
            }
            return ViewportPolySplineSurfaceVertexHandleTarget(
                featureID: featureID,
                target: target,
                componentID: componentID,
                point: vertex.point,
                modelTransform: item.modelTransform,
                dragMode: .planar
            )
        }
    }

    private func surfaceControlPointHandleTargets(
        in scene: ViewportScene
    ) -> [ViewportSurfaceControlPointHandleTarget] {
        selection.selectedReferences.reversed().compactMap { reference in
            guard case .surface(.controlPoint) = reference else {
                return nil
            }
            for item in scene.items {
                guard case .body(let component) = item.kind,
                      let display = component.surfaceControlPointDisplays.first(where: { display in
                          display.selectionReference == reference
                      }) else {
                    continue
                }
                return ViewportSurfaceControlPointHandleTarget(
                    featureID: item.featureID,
                    target: reference,
                    point: display.point,
                    modelTransform: item.modelTransform,
                    dragMode: .planar
                )
            }
            return nil
        }
    }

    private func surfaceTrimEndpointHandleTargets(
        in scene: ViewportScene
    ) -> [ViewportSurfaceTrimEndpointHandleTarget] {
        selection.selectedReferences.reversed().flatMap { reference -> [ViewportSurfaceTrimEndpointHandleTarget] in
            guard case .surface(.trim) = reference else {
                return []
            }
            for item in scene.items {
                guard case .body(let component) = item.kind else {
                    continue
                }
                let displays = component.surfaceTrimEndpointDisplays.filter { display in
                    display.selectionReference == reference
                }
                guard displays.isEmpty == false else {
                    continue
                }
                return displays.map { display in
                    ViewportSurfaceTrimEndpointHandleTarget(
                        featureID: item.featureID,
                        target: reference,
                        endpoint: display.endpoint,
                        point: display.point,
                        u: display.u,
                        v: display.v,
                        tangentU: display.tangentU,
                        tangentV: display.tangentV,
                        modelTransform: item.modelTransform
                    )
                }
            }
            return []
        }
    }

    private func bridgeCurveEndpointHandleTargets(
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportBridgeCurveEndpointHandleTarget] {
        ViewportBridgeCurveEndpointAffordanceService().candidatesOrEmpty(
            document: document,
            scene: scene,
            selection: selection,
            layout: layout
        ).map(\.target)
    }

    private func surfaceTrimControlPointHandleTargets(
        in scene: ViewportScene
    ) -> [ViewportSurfaceTrimControlPointHandleTarget] {
        selection.selectedReferences.reversed().flatMap { reference -> [ViewportSurfaceTrimControlPointHandleTarget] in
            guard case .surface(.trim) = reference else {
                return []
            }
            for item in scene.items {
                guard case .body(let component) = item.kind else {
                    continue
                }
                let displays = component.surfaceTrimControlPointDisplays.filter { display in
                    display.selectionReference == reference
                }
                guard displays.isEmpty == false else {
                    continue
                }
                return displays.map { display in
                    ViewportSurfaceTrimControlPointHandleTarget(
                        featureID: item.featureID,
                        target: reference,
                        controlPointIndex: display.controlPointIndex,
                        point: display.point,
                        u: display.u,
                        v: display.v,
                        tangentU: display.tangentU,
                        tangentV: display.tangentV,
                        modelTransform: item.modelTransform
                    )
                }
            }
            return []
        }
    }

    private func polySplineSurfaceVertexAxisHit(
        at point: CGPoint,
        target: ViewportPolySplineSurfaceVertexHandleTarget,
        layout: ViewportLayout
    ) -> ViewportCoordinateAxis? {
        let center = target.geometry.projectedPoint(layout: layout)
        var nearest: (axis: ViewportCoordinateAxis, distance: CGFloat)?
        for axis in ViewportCoordinateAxis.allCases {
            guard let endpoint = target.geometry.axisEndpoint(
                axis: axis,
                viewportLength: polySplineSurfaceVertexAxisViewportLength,
                layout: layout
            ),
                  let distance = polySplineSurfaceVertexHandleHitDistance(
                      at: point,
                      center: center,
                      endpoint: endpoint
                  ) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (axis, distance)
            }
        }
        return nearest?.axis
    }

    private func surfaceControlPointAxisHit(
        at point: CGPoint,
        target: ViewportSurfaceControlPointHandleTarget,
        layout: ViewportLayout
    ) -> ViewportCoordinateAxis? {
        let center = target.geometry.projectedPoint(layout: layout)
        var nearest: (axis: ViewportCoordinateAxis, distance: CGFloat)?
        for axis in ViewportCoordinateAxis.allCases {
            guard let endpoint = target.geometry.axisEndpoint(
                axis: axis,
                viewportLength: surfaceControlPointAxisViewportLength,
                layout: layout
            ),
                  let distance = polySplineSurfaceVertexHandleHitDistance(
                      at: point,
                      center: center,
                      endpoint: endpoint
                  ) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (axis, distance)
            }
        }
        return nearest?.axis
    }

    private func polySplineSurfaceVertexLocalAxisHit(
        at point: CGPoint,
        target: ViewportPolySplineSurfaceVertexHandleTarget,
        topologyVertices: [ViewportBodyTopology.Vertex],
        layout: ViewportLayout
    ) -> ViewportPolySplineSurfaceVertexLocalAxisHit? {
        let center = target.geometry.projectedPoint(layout: layout)
        var nearest: (hit: ViewportPolySplineSurfaceVertexLocalAxisHit, distance: CGFloat)?
        for localAxis in ViewportPolySplineSurfaceVertexLocalAxis.allCases {
            guard let direction = polySplineSurfaceVertexLocalDirection(
                localAxis: localAxis,
                target: target,
                topologyVertices: topologyVertices
            ),
                  let endpoint = polySplineSurfaceVertexLocalAxisEndpoint(
                      target: target,
                      direction: direction,
                      viewportLength: polySplineSurfaceVertexLocalAxisViewportLength,
                      layout: layout
                  ),
                  let distance = polySplineSurfaceVertexHandleHitDistance(
                      at: point,
                      center: center,
                      endpoint: endpoint
                  ) else {
                continue
            }
            let hit = ViewportPolySplineSurfaceVertexLocalAxisHit(
                axis: localAxis,
                direction: direction
            )
            if nearest == nil || distance < nearest!.distance {
                nearest = (hit, distance)
            }
        }
        return nearest?.hit
    }

    private func polySplineSurfaceVertexHandleHitDistance(
        at point: CGPoint,
        center: CGPoint,
        endpoint: CGPoint
    ) -> CGFloat? {
        let handleGap: CGFloat = 16.0
        let handleTolerance: CGFloat = 8.0
        let vector = CGVector(dx: endpoint.x - center.x, dy: endpoint.y - center.y)
        let length = vector.length
        guard length > handleGap + 1.0 else {
            return nil
        }
        let direction = vector.normalized
        let segmentStart = CGPoint(
            x: center.x + direction.dx * handleGap,
            y: center.y + direction.dy * handleGap
        )
        let distance = min(
            point.distance(to: endpoint),
            point.distanceToSegment(start: segmentStart, end: endpoint)
        )
        guard distance <= handleTolerance else {
            return nil
        }
        return distance
    }

    private func isPolySplineSurfaceVertex(_ componentID: SelectionComponentID) -> Bool {
        PolySplineSurfaceVertexTarget.parse(componentID: componentID) != nil
    }

    private func selectedVertexAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        guard onVertexDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        for target in selection.selectedTargets.reversed() {
            guard case .vertex = target.component,
                  let vertexTarget = vertexSelectionTarget(for: target),
                  let item = scene.items.first(where: { $0.featureID == vertexTarget.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }
            let handlePoint = projection.point(for: vertexTarget.vertex)
            guard point.distance(to: handlePoint) <= handleTolerance else {
                continue
            }
            return ViewportAffordanceTarget(
                featureID: vertexTarget.featureID,
                action: .profileCornerMove(target, vertexTarget.vertex)
            )
        }
        return nil
    }

    private func selectedFaceAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        guard onFaceDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        for target in selection.selectedTargets.reversed() {
            guard case .face = target.component,
                  let faceTarget = faceSelectionTarget(for: target),
                  ViewportProfileFaceDragMapping.supports(faceTarget.face),
                  let item = scene.items.first(where: { $0.featureID == faceTarget.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }
            let footprint = projection.footprint(for: faceTarget.face)
            guard footprint.contains(point, tolerance: 8.0) else {
                continue
            }
            return ViewportAffordanceTarget(
                featureID: faceTarget.featureID,
                action: .profileFaceMove(target, faceTarget.face)
            )
        }
        return nil
    }

    private func selectedEdgeAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        guard onEdgeChamferDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        for target in selection.selectedTargets.reversed() {
            guard case .edge = target.component,
                  let edgeTarget = edgeSelectionTarget(for: target),
                  let item = scene.items.first(where: { $0.featureID == edgeTarget.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }
            let segment = projection.segment(for: edgeTarget.edge)
            guard point.distanceToSegment(start: segment.start, end: segment.end) <= 10.0 else {
                continue
            }
            return ViewportAffordanceTarget(
                featureID: edgeTarget.featureID,
                action: .profileEdgeChamfer(target, edgeTarget.edge)
            )
        }
        return nil
    }

    private func selectedEdgeFilletAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        guard onEdgeFilletDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        for target in selection.selectedTargets.reversed() {
            guard case .edge = target.component,
                  let edgeTarget = edgeSelectionTarget(for: target),
                  let item = scene.items.first(where: { $0.featureID == edgeTarget.featureID }),
                  let projection = bodyProjection(for: item, layout: layout) else {
                continue
            }
            let handlePoint = edgeFilletHandlePoint(projection: projection, edge: edgeTarget.edge)
            guard point.distance(to: handlePoint) <= 10.0 else {
                continue
            }
            return ViewportAffordanceTarget(
                featureID: edgeTarget.featureID,
                action: .profileEdgeFillet(target, edgeTarget.edge)
            )
        }
        return nil
    }

    private func selectedRegionOffsetAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportRegionOffsetHandleTarget? {
        guard onRegionOffsetDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = regionOffsetAffordanceCandidates(
            targets: selectedSketchRegionTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            let start = layout.project(candidate.geometry.baseModelPoint)
            let end = candidate.geometry.projectedTip(layout: layout)
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedEdgeOffsetAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportEdgeOffsetHandleTarget? {
        guard onEdgeOffsetDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = edgeOffsetAffordanceCandidates(
            targets: selectedEdgeTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            let start = candidate.geometry.baseProjectedPoint
            let end = candidate.geometry.projectedTip()
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedSlotWidthAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSlotWidthHandleTarget? {
        guard onSlotWidthDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = slotWidthAffordanceCandidates(
            targets: selectedSlotWidthSourceTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            let start = layout.project(candidate.geometry.baseModelPoint)
            let end = candidate.geometry.projectedTip(layout: layout)
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayLinearAxisAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayLinearAxisHandleTarget? {
        guard onPatternArrayLinearAxisDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayLinearAxisAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let start = candidate.geometry.baseProjectedPoint
            let end = candidate.geometry.projectedTip()
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedIndependentCopyExtrudeDistanceAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportIndependentCopyExtrudeDistanceHandleTarget? {
        guard onIndependentCopyExtrudeDistanceDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = independentCopyExtrudeDistanceAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let start = candidate.geometry.baseProjectedPoint
            let end = candidate.geometry.projectedTip()
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedIndependentCopyBodyDimensionAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportIndependentCopyBodyDimensionHandleTarget? {
        guard onIndependentCopyBodyDimensionDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = independentCopyBodyDimensionAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let start = candidate.geometry.baseProjectedPoint
            let end = candidate.geometry.projectedTip()
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayRadialAngleAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayRadialAngleHandleTarget? {
        guard onPatternArrayRadialAngleDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayRadialAngleAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let arcPoints = candidate.geometry.projectedArcPoints()
            let arcHit = point.distanceToPolyline(arcPoints) <= 10.0
            let tipHit = point.distance(to: candidate.geometry.projectedTip()) <= 14.0
            if arcHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayCopyCountAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayCopyCountHandleTarget? {
        guard onPatternArrayCopyCountDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayCopyCountAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let handleHit = point.distance(to: candidate.geometry.handlePoint) <= 14.0
            let guideHit = point.distanceToPolyline(candidate.geometry.guidePoints()) <= 10.0
            if handleHit || guideHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayCurveExtentAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayCurveExtentHandleTarget? {
        guard onPatternArrayCurveExtentDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayCurveExtentAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let tipHit = point.distance(to: candidate.geometry.projectedTip()) <= 14.0
            let extentHit = point.distanceToPolyline(candidate.geometry.projectedExtentPoints()) <= 10.0
            if tipHit || extentHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayCurvePathPointAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayCurvePathPointHandleTarget? {
        guard onPatternArrayCurvePathPointDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayCurvePathPointAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            if point.distance(to: candidate.projectedPoint) <= 13.0 {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayOutputModeAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportPatternArrayOutputModeHandleTarget? {
        guard onPatternArrayOutputModeChange != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let candidates = patternArrayOutputModeAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            if candidate.hitRect.insetBy(dx: -6.0, dy: -6.0).contains(point) {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedSketchVertexOffsetAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSketchVertexOffsetHandleTarget? {
        guard onSketchVertexOffsetDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = sketchVertexOffsetAffordanceCandidates(
            targets: selectedSketchVertexOffsetSourceTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            let start = layout.project(candidate.geometry.baseModelPoint)
            let end = candidate.geometry.projectedTip(layout: layout)
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedSplineControlPointSlideAffordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportSplineControlPointSlideHandleTarget? {
        guard onSplineControlPointSlideDrag != nil else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = splineControlPointSlideAffordanceCandidates(
            groups: selectedSplineControlPointGroups(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            let start = layout.project(candidate.geometry.baseModelPoint)
            let end = candidate.geometry.projectedTip(layout: layout)
            let lineHit = point.distanceToSegment(start: start, end: end) <= 10.0
            let tipHit = point.distance(to: end) <= 14.0
            if lineHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func affordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        guard allowsObjectAffordances else {
            return nil
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        return affordanceTarget(at: point, scene: scene, layout: layout)
    }

    private func affordanceTarget(
        at point: CGPoint,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let selectedFeatureIDs = selectedObjectFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        if selectedBodyItems.count > 1,
           let groupFeatureID = selectionGroupFeatureID(for: selectedBodyItems),
           let groupEdit = selectionGroupEditState(for: selectedBodyItems) {
            return bodyAffordanceTarget(
                point: point,
                featureID: groupFeatureID,
                edit: groupEdit,
                layout: layout
            )
        }

        for item in scene.items.reversed() where selectedFeatureIDs.contains(item.featureID) {
            guard case .body = item.kind else {
                continue
            }
            if let target = bodyAffordanceTarget(
                point: point,
                item: item,
                layout: layout
            ) {
                return target
            }
        }
        return nil
    }

    private func bodyAffordanceTarget(
        point: CGPoint,
        item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        return bodyAffordanceTarget(
            point: point,
            featureID: item.featureID,
            edit: edit,
            layout: layout
        )
    }

    private func bodyAffordanceTarget(
        point: CGPoint,
        featureID: FeatureID,
        edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let bodyBounds = edit.projectedBodyProjection(layout: layout).hitBounds
        let modelCenter = edit.centerPoint
        let center = edit.projectedPoint(modelCenter, layout: layout)
        let affordanceBasis = edit.projectedAxisBasis(layout: layout)
        let radius = max(28.0, min(72.0, min(bodyBounds.width, bodyBounds.height) * 0.38))
        let axisLength = bodyAffordanceAxisLength(for: radius)
        let endScaleLength = bodyAffordanceEndScaleLength(
            axisLength: axisLength,
            rotationRadius: radius
        )
        let handleTolerance: CGFloat = 10.0

        for axis in ViewportCoordinateAxis.allCases {
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: endScaleLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distance(to: endpoint) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .oneSidedScale(axis))
            }

            let centerScalePoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: radius,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distance(to: centerScalePoint) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .centerScale(axis))
            }
        }

        for handle in bodyVertexHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .vertexMove(handle.vertex))
            }
        }

        for handle in bodyFaceCenterHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .faceMove(handle.face))
            }
        }

        if let axis = rotationAffordanceAxis(
            point: point,
            center: center,
            radius: radius,
            basis: affordanceBasis
        ) {
            return ViewportAffordanceTarget(featureID: featureID, action: .rotate(axis))
        }

        for axis in ViewportCoordinateAxis.allCases {
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: axisLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distanceToSegment(start: center, end: endpoint) <= 7.0 {
                return ViewportAffordanceTarget(featureID: featureID, action: .translate(axis))
            }
        }

        return nil
    }

    private func viewportHit(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportHit? {
        identityHitResolver.hitTest(
            point: point,
            in: scene,
            layout: layout,
            selectionHitPolicy: selectionHitPolicy
        )
    }

    private func polygonBounds(_ polygon: [CGPoint]) -> CGRect {
        var bounds = CGRect.null
        for point in polygon {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0))
        }
        return bounds
    }

    private func rotationAffordanceAxis(
        point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        basis: ViewportProjectionBasis
    ) -> ViewportCoordinateAxis? {
        let candidates: [(axis: ViewportCoordinateAxis, start: CGVector, end: CGVector)] = [
            (.x, basis.yDirection, basis.zDirection),
            (.y, basis.zDirection, basis.xDirection),
            (.z, basis.xDirection, basis.yDirection),
        ]
        var best: (axis: ViewportCoordinateAxis, distance: CGFloat)?
        for candidate in candidates {
            let distance = distanceToRotationArc(
                point: point,
                center: center,
                radius: radius,
                from: candidate.start,
                to: candidate.end
            )
            if let current = best {
                if distance < current.distance {
                    best = (candidate.axis, distance)
                }
            } else {
                best = (candidate.axis, distance)
            }
        }
        guard let best, best.distance <= 8.0 else {
            return nil
        }
        return best.axis
    }

    private func distanceToRotationArc(
        point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        from startDirection: CGVector,
        to endDirection: CGVector
    ) -> CGFloat {
        projectedRotationArcPoints(
            center: center,
            radius: radius,
            planeStart: startDirection,
            planeEnd: endDirection
        )
        .map { point.distance(to: $0) }
        .min() ?? CGFloat.greatestFiniteMagnitude
    }

    private func updateAffordanceDrag(
        target: ViewportAffordanceTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let selectedFeatureIDs = selectedObjectFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        let targetIsSelectionGroup = selectedBodyItems.count > 1
            && selectedBodyItems.contains { $0.featureID == target.featureID }

        let dragState: ViewportAffordanceDragState
        if let activeAffordanceDrag,
           activeAffordanceDrag.target == target {
            dragState = activeAffordanceDrag
        } else {
            let baseEdits: [FeatureID: ViewportObjectEditState]
            let baseGroupEdit: ViewportObjectEditState?
            if targetIsSelectionGroup {
                baseEdits = bodyEditStates(for: selectedBodyItems)
                baseGroupEdit = selectionGroupEditState(for: Array(baseEdits.values))
            } else {
                guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
                      case .body = item.kind else {
                    return
                }
                baseEdits = [
                    target.featureID: editedBodies[target.featureID] ?? ViewportObjectEditState(item: item)
                ]
                baseGroupEdit = nil
            }
            dragState = ViewportAffordanceDragState(
                target: target,
                startPoint: start,
                baseEdits: baseEdits,
                baseGroupEdit: baseGroupEdit
            )
            activeAffordanceDrag = dragState
        }

        if let baseGroupEdit = dragState.baseGroupEdit {
            let nextGroupEdit = baseGroupEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            )
            for (featureID, baseEdit) in dragState.baseEdits {
                editedBodies[featureID] = baseEdit.transformedFromGroup(
                    baseGroup: baseGroupEdit,
                    targetGroup: nextGroupEdit
                )
            }
        } else if let baseEdit = dragState.baseEdits[target.featureID] {
            editedBodies[target.featureID] = baseEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            )
        }
    }

    private func updateSplineControlPointDrag(
        target: ViewportSplineControlPointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let startPoint = layout.unproject(start)
        let currentPoint = layout.unproject(current)
        activeSplineControlPointDrag = ViewportSplineControlPointDragState(
            target: target,
            startPoint: start,
            viewportDelta: CGPoint(
                x: currentPoint.x - startPoint.x,
                y: currentPoint.y - startPoint.y
            )
        )
    }

    private func updateBridgeCurveEndpointDrag(
        target: ViewportBridgeCurveEndpointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta = target.geometry.localPlanarDelta(start: start, current: current, layout: layout)
        let nearPoint = Point2D(
            x: target.point.x + delta.x,
            y: target.point.y + delta.z
        )
        let projection: BridgeCurveEndpointParameterProjection
        do {
            projection = try BridgeCurveEndpointParameterProjectionService().projection(
                for: target.endpoint,
                featureID: target.featureID,
                near: nearPoint,
                in: document
            )
        } catch {
            activeBridgeCurveEndpointDrag = nil
            return
        }
        let projectedPoint = projectedBridgeCurveEndpointPoint(
            projection.point,
            modelTransform: target.modelTransform,
            layout: layout
        )
        activeBridgeCurveEndpointDrag = ViewportBridgeCurveEndpointDragState(
            target: target,
            startPoint: start,
            endpoint: projection.endpoint,
            parameter: projection.parameter,
            projectedPoint: projectedPoint,
            projectedTangentTip: ViewportBridgeCurveEndpointAffordanceService.projectedTangentTip(
                point: projection.point,
                outgoingTangent: projection.outgoingTangent,
                modelTransform: target.modelTransform,
                layout: layout
            )
        )
    }

    private func projectedBridgeCurveEndpointPoint(
        _ point: Point2D,
        modelTransform: Transform3D,
        layout: ViewportLayout
    ) -> CGPoint {
        layout.project(modelTransform.viewportTransformedPoint(Point3D(
            x: point.x,
            y: 0.0,
            z: point.y
        )))
    }

    private func updateSplineControlPointSlideDrag(
        target: ViewportSplineControlPointSlideHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeSplineControlPointSlideDrag = ViewportSplineControlPointSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.slideDistance(
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func updatePolySplineSurfaceVertexSlideDrag(
        target: ViewportPolySplineSurfaceVertexSlideHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activePolySplineSurfaceVertexSlideDrag = ViewportPolySplineSurfaceVertexSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.slideDistance(
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func updateSurfaceControlPointSlideDrag(
        target: ViewportSurfaceControlPointSlideHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeSurfaceControlPointSlideDrag = ViewportSurfaceControlPointSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.slideDistance(
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func updateSurfaceFrameDrag(
        target: ViewportSurfaceFrameHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeSurfaceFrameDrag = ViewportSurfaceFrameDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.dragDistance(
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func updatePolySplineSurfaceVertexDrag(
        target: ViewportPolySplineSurfaceVertexHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta: Point3D
        switch target.dragMode {
        case .planar:
            delta = target.geometry.localPlanarDelta(start: start, current: current, layout: layout)
        case .axis(let axis):
            delta = target.geometry.localDelta(
                axis: axis,
                start: start,
                current: current,
                layout: layout
            )
        case .localAxis(_, let direction):
            delta = target.geometry.localDelta(
                direction: direction,
                start: start,
                current: current,
                layout: layout
            )
        }
        activePolySplineSurfaceVertexDrag = ViewportPolySplineSurfaceVertexDragState(
            target: target,
            startPoint: start,
            delta: delta
        )
    }

    private func updateSurfaceControlPointDrag(
        target: ViewportSurfaceControlPointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta: Point3D
        switch target.dragMode {
        case .planar:
            delta = target.geometry.localPlanarDelta(start: start, current: current, layout: layout)
        case .axis(let axis):
            delta = target.geometry.localDelta(
                axis: axis,
                start: start,
                current: current,
                layout: layout
            )
        case .localAxis(_, let direction):
            delta = target.geometry.localDelta(
                direction: direction,
                start: start,
                current: current,
                layout: layout
            )
        }
        activeSurfaceControlPointDrag = ViewportSurfaceControlPointDragState(
            target: target,
            startPoint: start,
            delta: delta
        )
    }

    private func updateSurfaceTrimEndpointDrag(
        target: ViewportSurfaceTrimEndpointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta = target.geometry.localPlanarDelta(start: start, current: current, layout: layout)
        activeSurfaceTrimEndpointDrag = ViewportSurfaceTrimEndpointDragState(
            target: target,
            startPoint: start,
            delta: delta
        )
    }

    private func updateSurfaceTrimControlPointDrag(
        target: ViewportSurfaceTrimControlPointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta = target.geometry.localPlanarDelta(start: start, current: current, layout: layout)
        activeSurfaceTrimControlPointDrag = ViewportSurfaceTrimControlPointDragState(
            target: target,
            startPoint: start,
            delta: delta
        )
    }

    private func updateRegionOffsetDrag(
        target: ViewportRegionOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeRegionOffsetDrag = ViewportRegionOffsetDragState(
            target: target,
            startPoint: start,
            distanceMeters: regionOffsetDistance(
                target: target,
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func regionOffsetDistance(
        target: ViewportRegionOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        target.geometry.offsetDistance(
            start: start,
            current: current,
            layout: layout
        )
    }

    private func updateEdgeOffsetDrag(
        target: ViewportEdgeOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        activeEdgeOffsetDrag = ViewportEdgeOffsetDragState(
            target: target,
            startPoint: start,
            distanceMeters: edgeOffsetDistance(
                target: target,
                start: start,
                current: current
            )
        )
    }

    private func edgeOffsetDistance(
        target: ViewportEdgeOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) -> Double {
        target.geometry.offsetDistance(
            start: start,
            current: current
        )
    }

    private func updateSlotWidthDrag(
        target: ViewportSlotWidthHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeSlotWidthDrag = ViewportSlotWidthDragState(
            target: target,
            startPoint: start,
            widthMeters: slotWidth(
                target: target,
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func slotWidth(
        target: ViewportSlotWidthHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        target.geometry.slotWidth(
            start: start,
            current: current,
            layout: layout
        )
    }

    private func updatePatternArrayLinearAxisDrag(
        target: ViewportPatternArrayLinearAxisHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activePatternArrayLinearAxisDrag = ViewportPatternArrayLinearAxisDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.axisDistance(
                start: start,
                current: current
            )
        )
    }

    private func updateIndependentCopyExtrudeDistanceDrag(
        target: ViewportIndependentCopyExtrudeDistanceHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activeIndependentCopyExtrudeDistanceDrag = ViewportIndependentCopyExtrudeDistanceDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.axisDistance(
                start: start,
                current: current
            )
        )
    }

    private func updateIndependentCopyBodyDimensionDrag(
        target: ViewportIndependentCopyBodyDimensionHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activeIndependentCopyBodyDimensionDrag = ViewportIndependentCopyBodyDimensionDragState(
            target: target,
            startPoint: start,
            valueMeters: target.geometry.axisDistance(
                start: start,
                current: current
            )
        )
    }

    private func updatePatternArrayRadialAngleDrag(
        target: ViewportPatternArrayRadialAngleHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activePatternArrayRadialAngleDrag = ViewportPatternArrayRadialAngleDragState(
            target: target,
            startPoint: start,
            angleRadians: target.geometry.angleRadians(
                start: start,
                current: current
            )
        )
    }

    private func updatePatternArrayCopyCountDrag(
        target: ViewportPatternArrayCopyCountHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activePatternArrayCopyCountDrag = ViewportPatternArrayCopyCountDragState(
            target: target,
            startPoint: start,
            copyCount: target.geometry.copyCount(
                start: start,
                current: current
            )
        )
    }

    private func updatePatternArrayCurveExtentDrag(
        target: ViewportPatternArrayCurveExtentHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        activePatternArrayCurveExtentDrag = ViewportPatternArrayCurveExtentDragState(
            target: target,
            startPoint: start,
            distanceMeters: target.geometry.extentDistance(current: current)
        )
    }

    private func updatePatternArrayCurvePathPointDrag(
        target: ViewportPatternArrayCurvePathPointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let startPoint = layout.unproject(start)
        let currentPoint = layout.unproject(current)
        activePatternArrayCurvePathPointDrag = ViewportPatternArrayCurvePathPointDragState(
            target: target,
            startPoint: start,
            point: Point3D(
                x: target.basePoint.x + Double(currentPoint.x - startPoint.x),
                y: target.basePoint.y,
                z: target.basePoint.z + Double(currentPoint.y - startPoint.y)
            )
        )
    }

    private func updateSketchVertexOffsetDrag(
        target: ViewportSketchVertexOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeSketchVertexOffsetDrag = ViewportSketchVertexOffsetDragState(
            target: target,
            startPoint: start,
            distanceMeters: sketchVertexOffsetDistance(
                target: target,
                start: start,
                current: current,
                layout: layout
            )
        )
    }

    private func sketchVertexOffsetDistance(
        target: ViewportSketchVertexOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        target.geometry.offsetDistance(
            start: start,
            current: current,
            layout: layout
        )
    }

    private func updateSketchPointHandleDrag(
        target: ViewportSketchPointHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let startPoint = layout.unproject(start)
        let currentPoint = layout.unproject(current)
        activeSketchPointHandleDrag = ViewportSketchPointHandleDragState(
            target: target,
            startPoint: start,
            viewportDelta: CGPoint(
                x: currentPoint.x - startPoint.x,
                y: currentPoint.y - startPoint.y
            )
        )
    }

    private func updateSketchCurveHandleDrag(
        target: ViewportSketchCurveHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let currentPoint = layout.unproject(current)
        let values = sketchCurveHandleValues(
            target: target,
            currentViewportPoint: currentPoint
        )
        activeSketchCurveHandleDrag = ViewportSketchCurveHandleDragState(
            target: target,
            startPoint: start,
            radiusMeters: values.radiusMeters,
            startAngleRadians: values.startAngleRadians,
            endAngleRadians: values.endAngleRadians
        )
    }

    private func updateSketchDimensionDrag(
        target: ViewportSketchDimensionTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let startPoint = layout.unproject(start)
        let currentPoint = layout.unproject(current)
        let value = sketchDimensionValue(
            target: target,
            startViewportPoint: startPoint,
            currentViewportPoint: currentPoint
        )
        activeSketchDimensionDrag = ViewportSketchDimensionDragState(
            target: target,
            startPoint: start,
            value: value
        )
    }

    private func sketchCurveHandleValues(
        target: ViewportSketchCurveHandleTarget,
        currentViewportPoint: CGPoint
    ) -> (radiusMeters: Double?, startAngleRadians: Double?, endAngleRadians: Double?) {
        let currentPoint = localSketchPoint(
            fromViewportPoint: currentViewportPoint,
            sketchPlane: target.sketchPlane
        )
        let center = localSketchPoint(
            fromViewportPoint: target.center,
            sketchPlane: target.sketchPlane
        )
        let dx = Double(currentPoint.x - center.x)
        let dy = Double(currentPoint.y - center.y)
        let radius = max(hypot(dx, dy), 1.0e-9)
        let angle = atan2(dy, dx)
        switch target.handle {
        case .circleRadius, .arcRadius:
            return (radius, nil, nil)
        case .arcStartAngle:
            return (nil, angle, nil)
        case .arcEndAngle:
            return (nil, nil, angle)
        }
    }

    private func sketchDimensionValue(
        target: ViewportSketchDimensionTarget,
        startViewportPoint: CGPoint,
        currentViewportPoint: CGPoint
    ) -> Double {
        switch target.kind {
        case .length:
            guard let lineStart = target.start,
                  let lineEnd = target.end else {
                return target.baselineValue
            }
            let start = localSketchPoint(fromViewportPoint: lineStart, sketchPlane: target.sketchPlane)
            let end = localSketchPoint(fromViewportPoint: lineEnd, sketchPlane: target.sketchPlane)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 1.0e-12 else {
                return target.baselineValue
            }
            let viewportDelta = CGPoint(
                x: currentViewportPoint.x - startViewportPoint.x,
                y: currentViewportPoint.y - startViewportPoint.y
            )
            let delta = localSketchDelta(
                fromViewportDelta: viewportDelta,
                sketchPlane: target.sketchPlane
            )
            let unitX = dx / length
            let unitY = dy / length
            return max(target.baselineValue + Double(delta.x * unitX + delta.y * unitY), 1.0e-9)
        case .radius:
            guard let center = target.center else {
                return target.baselineValue
            }
            let current = localSketchPoint(
                fromViewportPoint: currentViewportPoint,
                sketchPlane: target.sketchPlane
            )
            let localCenter = localSketchPoint(
                fromViewportPoint: center,
                sketchPlane: target.sketchPlane
            )
            return max(hypot(Double(current.x - localCenter.x), Double(current.y - localCenter.y)), 1.0e-9)
        case .diameter:
            return target.baselineValue
        case .angle:
            if let lineStart = target.start,
               let lineEnd = target.end {
                let start = localSketchPoint(fromViewportPoint: lineStart, sketchPlane: target.sketchPlane)
                let end = localSketchPoint(fromViewportPoint: lineEnd, sketchPlane: target.sketchPlane)
                let dx = end.x - start.x
                let dy = end.y - start.y
                let length = hypot(dx, dy)
                guard length > 1.0e-12 else {
                    return target.baselineValue
                }
                let viewportDelta = CGPoint(
                    x: currentViewportPoint.x - startViewportPoint.x,
                    y: currentViewportPoint.y - startViewportPoint.y
                )
                let delta = localSketchDelta(
                    fromViewportDelta: viewportDelta,
                    sketchPlane: target.sketchPlane
                )
                let unitX = dx / length
                let unitY = dy / length
                let tangent = CGPoint(x: -unitY, y: unitX)
                let tangentialDistance = Double(delta.x * tangent.x + delta.y * tangent.y)
                return target.baselineValue + tangentialDistance / Double(length)
            }
            guard let radiusMeters = target.radiusMeters,
                  let endAngle = target.endAngleRadians else {
                return target.baselineValue
            }
            let viewportDelta = CGPoint(
                x: currentViewportPoint.x - startViewportPoint.x,
                y: currentViewportPoint.y - startViewportPoint.y
            )
            let delta = localSketchDelta(
                fromViewportDelta: viewportDelta,
                sketchPlane: target.sketchPlane
            )
            let tangent = CGPoint(
                x: -sin(CGFloat(endAngle)),
                y: cos(CGFloat(endAngle))
            )
            let tangentialDistance = Double(delta.x * tangent.x + delta.y * tangent.y)
            let deltaAngle = tangentialDistance / max(radiusMeters, 1.0e-9)
            let maximumPartialSpan = Double.pi * 2.0 - 1.0e-6
            return min(max(target.baselineValue + deltaAngle, 1.0e-9), maximumPartialSpan)
        }
    }

    private func pick(
        at point: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if pendingSketchCurveHandle != nil {
            pendingSketchCurveHandle = nil
            activeSketchCurveHandleDrag = nil
            return
        }
        if pendingSketchDimension != nil {
            pendingSketchDimension = nil
            activeSketchDimensionDrag = nil
            return
        }
        if pendingSketchPointHandle != nil {
            pendingSketchPointHandle = nil
            activeSketchPointHandleDrag = nil
            return
        }
        if pendingBridgeCurveEndpointHandle != nil {
            pendingBridgeCurveEndpointHandle = nil
            activeBridgeCurveEndpointDrag = nil
            activeCanvasDrag = nil
            return
        }
        if pendingSplineControlPointSlideHandle != nil {
            pendingSplineControlPointSlideHandle = nil
            activeSplineControlPointSlideDrag = nil
            return
        }
        if pendingPolySplineSurfaceVertexSlideHandle != nil {
            pendingPolySplineSurfaceVertexSlideHandle = nil
            activePolySplineSurfaceVertexSlideDrag = nil
            return
        }
        if pendingSurfaceControlPointSlideHandle != nil {
            pendingSurfaceControlPointSlideHandle = nil
            activeSurfaceControlPointSlideDrag = nil
            return
        }
        if pendingSurfaceFrameHandle != nil {
            pendingSurfaceFrameHandle = nil
            activeSurfaceFrameDrag = nil
            return
        }
        if pendingSplineControlPoint != nil {
            pendingSplineControlPoint = nil
            activeSplineControlPointDrag = nil
            return
        }
        if pendingPolySplineSurfaceVertex != nil {
            pendingPolySplineSurfaceVertex = nil
            activePolySplineSurfaceVertexDrag = nil
            return
        }
        if pendingSurfaceControlPoint != nil {
            pendingSurfaceControlPoint = nil
            activeSurfaceControlPointDrag = nil
            return
        }
        if pendingSurfaceTrimEndpoint != nil {
            pendingSurfaceTrimEndpoint = nil
            activeSurfaceTrimEndpointDrag = nil
            return
        }
        if pendingSurfaceTrimControlPoint != nil {
            pendingSurfaceTrimControlPoint = nil
            activeSurfaceTrimControlPointDrag = nil
            return
        }
        if pendingEdgeOffsetHandle != nil {
            pendingEdgeOffsetHandle = nil
            activeEdgeOffsetDrag = nil
            return
        }
        if pendingRegionOffsetHandle != nil {
            pendingRegionOffsetHandle = nil
            activeRegionOffsetDrag = nil
            return
        }
        if pendingSketchVertexOffsetHandle != nil {
            pendingSketchVertexOffsetHandle = nil
            activeSketchVertexOffsetDrag = nil
            return
        }
        if pendingIndependentCopyExtrudeDistanceHandle != nil {
            pendingIndependentCopyExtrudeDistanceHandle = nil
            activeIndependentCopyExtrudeDistanceDrag = nil
            return
        }
        if pendingIndependentCopyBodyDimensionHandle != nil {
            pendingIndependentCopyBodyDimensionHandle = nil
            activeIndependentCopyBodyDimensionDrag = nil
            return
        }
        if pendingPatternArrayLinearAxisHandle != nil {
            pendingPatternArrayLinearAxisHandle = nil
            activePatternArrayLinearAxisDrag = nil
            return
        }
        if pendingPatternArrayRadialAngleHandle != nil {
            pendingPatternArrayRadialAngleHandle = nil
            activePatternArrayRadialAngleDrag = nil
            return
        }
        if pendingPatternArrayCopyCountHandle != nil {
            pendingPatternArrayCopyCountHandle = nil
            activePatternArrayCopyCountDrag = nil
            return
        }
        if pendingPatternArrayCurveExtentHandle != nil {
            pendingPatternArrayCurveExtentHandle = nil
            activePatternArrayCurveExtentDrag = nil
            return
        }
        if pendingPatternArrayCurvePathPointHandle != nil {
            pendingPatternArrayCurvePathPointHandle = nil
            activePatternArrayCurvePathPointDrag = nil
            return
        }
        if let pendingPatternArrayOutputModeHandle {
            self.pendingPatternArrayOutputModeHandle = nil
            activeCanvasDrag = nil
            onPatternArrayOutputModeChange?(pendingPatternArrayOutputModeHandle.commitTarget)
            return
        }
        if pendingAffordance != nil {
            pendingAffordance = nil
            activeAffordanceDrag = nil
            return
        }
        guard let onPick else {
            return
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        let hit = viewportHit(
            point: point,
            in: sceneBySuppressingSketches(
                scene,
                selectedFeatureIDs: selectedTargetFeatureIDs()
            ),
            layout: mapper.layout
        )
        let sketchPlane = constructionSketchPlane(for: hit)
        onPick(
            ViewportCanvasTarget(
                hit: hit,
                modelPoint: mapper.modelPoint(for: point),
                modelWorldPoint: selectedGeneratedFaceSurfaceWorldPoint(
                    at: point,
                    in: scene,
                    layout: mapper.layout
                ),
                sketchPlane: sketchPlane,
                selectionIntent: selectionIntent,
                modifierFlags: modifierFlags
            )
        )
    }

    private func handleCanvasDrag(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if pendingSketchCurveHandle != nil || activeSketchCurveHandleDrag != nil {
            let sketchCurveHandleDragTarget = committedSketchCurveHandleDragTarget()
            pendingSketchCurveHandle = nil
            activeSketchCurveHandleDrag = nil
            activeCanvasDrag = nil
            if let sketchCurveHandleDragTarget {
                onSketchCurveHandleDrag?(sketchCurveHandleDragTarget)
            }
            return
        }
        if pendingSketchDimension != nil || activeSketchDimensionDrag != nil {
            let sketchDimensionDragTarget = committedSketchDimensionDragTarget()
            pendingSketchDimension = nil
            activeSketchDimensionDrag = nil
            activeCanvasDrag = nil
            if let sketchDimensionDragTarget {
                onSketchDimensionDrag?(sketchDimensionDragTarget)
            }
            return
        }
        if pendingSketchPointHandle != nil || activeSketchPointHandleDrag != nil {
            let sketchPointHandleDragTarget = committedSketchPointHandleDragTarget()
            pendingSketchPointHandle = nil
            activeSketchPointHandleDrag = nil
            activeCanvasDrag = nil
            if let sketchPointHandleDragTarget {
                onSketchPointHandleDrag?(sketchPointHandleDragTarget)
            }
            return
        }
        if pendingBridgeCurveEndpointHandle != nil || activeBridgeCurveEndpointDrag != nil {
            let bridgeCurveEndpointDragTarget = committedBridgeCurveEndpointDragTarget()
            pendingBridgeCurveEndpointHandle = nil
            activeBridgeCurveEndpointDrag = nil
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            if let bridgeCurveEndpointDragTarget {
                onBridgeCurveEndpointDrag?(bridgeCurveEndpointDragTarget)
            }
            return
        }
        if pendingSplineControlPointSlideHandle != nil || activeSplineControlPointSlideDrag != nil {
            let splineControlPointSlideDragTarget = committedSplineControlPointSlideDragTarget()
            pendingSplineControlPointSlideHandle = nil
            activeSplineControlPointSlideDrag = nil
            activeCanvasDrag = nil
            if let splineControlPointSlideDragTarget {
                onSplineControlPointSlideDrag?(splineControlPointSlideDragTarget)
            }
            return
        }
        if pendingPolySplineSurfaceVertexSlideHandle != nil || activePolySplineSurfaceVertexSlideDrag != nil {
            let polySplineSurfaceVertexSlideDragTarget = committedPolySplineSurfaceVertexSlideDragTarget()
            pendingPolySplineSurfaceVertexSlideHandle = nil
            activePolySplineSurfaceVertexSlideDrag = nil
            activeCanvasDrag = nil
            if let polySplineSurfaceVertexSlideDragTarget {
                onPolySplineSurfaceVertexSlideDrag?(polySplineSurfaceVertexSlideDragTarget)
            }
            return
        }
        if pendingSurfaceControlPointSlideHandle != nil || activeSurfaceControlPointSlideDrag != nil {
            let surfaceControlPointSlideDragTarget = committedSurfaceControlPointSlideDragTarget()
            pendingSurfaceControlPointSlideHandle = nil
            activeSurfaceControlPointSlideDrag = nil
            activeCanvasDrag = nil
            if let surfaceControlPointSlideDragTarget {
                onSurfaceControlPointSlideDrag?(surfaceControlPointSlideDragTarget)
            }
            return
        }
        if pendingSurfaceFrameHandle != nil || activeSurfaceFrameDrag != nil {
            let surfaceFrameDragTarget = committedSurfaceFrameDragTarget()
            pendingSurfaceFrameHandle = nil
            activeSurfaceFrameDrag = nil
            activeCanvasDrag = nil
            if let surfaceFrameDragTarget {
                onSurfaceFrameDrag?(surfaceFrameDragTarget)
            }
            return
        }
        if pendingSplineControlPoint != nil || activeSplineControlPointDrag != nil {
            let splineControlPointDragTarget = committedSplineControlPointDragTarget()
            pendingSplineControlPoint = nil
            activeSplineControlPointDrag = nil
            activeCanvasDrag = nil
            if let splineControlPointDragTarget {
                onSplineControlPointDrag?(splineControlPointDragTarget)
            }
            return
        }
        if pendingPolySplineSurfaceVertex != nil || activePolySplineSurfaceVertexDrag != nil {
            let polySplineSurfaceVertexDragTarget = committedPolySplineSurfaceVertexDragTarget()
            pendingPolySplineSurfaceVertex = nil
            activePolySplineSurfaceVertexDrag = nil
            activeCanvasDrag = nil
            if let polySplineSurfaceVertexDragTarget {
                onPolySplineSurfaceVertexDrag?(polySplineSurfaceVertexDragTarget)
            }
            return
        }
        if pendingSurfaceControlPoint != nil || activeSurfaceControlPointDrag != nil {
            let surfaceControlPointDragTarget = committedSurfaceControlPointDragTarget()
            pendingSurfaceControlPoint = nil
            activeSurfaceControlPointDrag = nil
            activeCanvasDrag = nil
            if let surfaceControlPointDragTarget {
                onSurfaceControlPointDrag?(surfaceControlPointDragTarget)
            }
            return
        }
        if pendingSurfaceTrimEndpoint != nil || activeSurfaceTrimEndpointDrag != nil {
            let surfaceTrimEndpointDragTarget = committedSurfaceTrimEndpointDragTarget()
            pendingSurfaceTrimEndpoint = nil
            activeSurfaceTrimEndpointDrag = nil
            activeCanvasDrag = nil
            if let surfaceTrimEndpointDragTarget {
                onSurfaceTrimEndpointDrag?(surfaceTrimEndpointDragTarget)
            }
            return
        }
        if pendingSurfaceTrimControlPoint != nil || activeSurfaceTrimControlPointDrag != nil {
            let surfaceTrimControlPointDragTarget = committedSurfaceTrimControlPointDragTarget()
            pendingSurfaceTrimControlPoint = nil
            activeSurfaceTrimControlPointDrag = nil
            activeCanvasDrag = nil
            if let surfaceTrimControlPointDragTarget {
                onSurfaceTrimControlPointDrag?(surfaceTrimControlPointDragTarget)
            }
            return
        }
        if pendingEdgeOffsetHandle != nil || activeEdgeOffsetDrag != nil {
            let edgeOffsetDragTarget = committedEdgeOffsetDragTarget()
            pendingEdgeOffsetHandle = nil
            activeEdgeOffsetDrag = nil
            activeCanvasDrag = nil
            if let edgeOffsetDragTarget {
                onEdgeOffsetDrag?(edgeOffsetDragTarget)
            }
            return
        }
        if pendingSlotWidthHandle != nil || activeSlotWidthDrag != nil {
            let slotWidthDragTarget = committedSlotWidthDragTarget()
            pendingSlotWidthHandle = nil
            activeSlotWidthDrag = nil
            activeCanvasDrag = nil
            if let slotWidthDragTarget {
                onSlotWidthDrag?(slotWidthDragTarget)
            }
            return
        }
        if pendingIndependentCopyExtrudeDistanceHandle != nil || activeIndependentCopyExtrudeDistanceDrag != nil {
            let independentCopyExtrudeDistanceDragTarget = committedIndependentCopyExtrudeDistanceDragTarget()
            pendingIndependentCopyExtrudeDistanceHandle = nil
            activeIndependentCopyExtrudeDistanceDrag = nil
            activeCanvasDrag = nil
            if let independentCopyExtrudeDistanceDragTarget {
                onIndependentCopyExtrudeDistanceDrag?(independentCopyExtrudeDistanceDragTarget)
            }
            return
        }
        if pendingIndependentCopyBodyDimensionHandle != nil || activeIndependentCopyBodyDimensionDrag != nil {
            let independentCopyBodyDimensionDragTarget = committedIndependentCopyBodyDimensionDragTarget()
            pendingIndependentCopyBodyDimensionHandle = nil
            activeIndependentCopyBodyDimensionDrag = nil
            activeCanvasDrag = nil
            if let independentCopyBodyDimensionDragTarget {
                onIndependentCopyBodyDimensionDrag?(independentCopyBodyDimensionDragTarget)
            }
            return
        }
        if pendingPatternArrayLinearAxisHandle != nil || activePatternArrayLinearAxisDrag != nil {
            let patternArrayLinearAxisDragTarget = committedPatternArrayLinearAxisDragTarget()
            pendingPatternArrayLinearAxisHandle = nil
            activePatternArrayLinearAxisDrag = nil
            activeCanvasDrag = nil
            if let patternArrayLinearAxisDragTarget {
                onPatternArrayLinearAxisDrag?(patternArrayLinearAxisDragTarget)
            }
            return
        }
        if pendingPatternArrayRadialAngleHandle != nil || activePatternArrayRadialAngleDrag != nil {
            let patternArrayRadialAngleDragTarget = committedPatternArrayRadialAngleDragTarget()
            pendingPatternArrayRadialAngleHandle = nil
            activePatternArrayRadialAngleDrag = nil
            activeCanvasDrag = nil
            if let patternArrayRadialAngleDragTarget {
                onPatternArrayRadialAngleDrag?(patternArrayRadialAngleDragTarget)
            }
            return
        }
        if pendingPatternArrayCopyCountHandle != nil || activePatternArrayCopyCountDrag != nil {
            let patternArrayCopyCountDragTarget = committedPatternArrayCopyCountDragTarget()
            pendingPatternArrayCopyCountHandle = nil
            activePatternArrayCopyCountDrag = nil
            activeCanvasDrag = nil
            if let patternArrayCopyCountDragTarget {
                onPatternArrayCopyCountDrag?(patternArrayCopyCountDragTarget)
            }
            return
        }
        if pendingPatternArrayCurveExtentHandle != nil || activePatternArrayCurveExtentDrag != nil {
            let patternArrayCurveExtentDragTarget = committedPatternArrayCurveExtentDragTarget()
            pendingPatternArrayCurveExtentHandle = nil
            activePatternArrayCurveExtentDrag = nil
            activeCanvasDrag = nil
            if let patternArrayCurveExtentDragTarget {
                onPatternArrayCurveExtentDrag?(patternArrayCurveExtentDragTarget)
            }
            return
        }
        if pendingPatternArrayCurvePathPointHandle != nil || activePatternArrayCurvePathPointDrag != nil {
            let patternArrayCurvePathPointDragTarget = committedPatternArrayCurvePathPointDragTarget()
            pendingPatternArrayCurvePathPointHandle = nil
            activePatternArrayCurvePathPointDrag = nil
            activeCanvasDrag = nil
            if let patternArrayCurvePathPointDragTarget {
                onPatternArrayCurvePathPointDrag?(patternArrayCurvePathPointDragTarget)
            }
            return
        }
        if pendingPatternArrayOutputModeHandle != nil {
            pendingPatternArrayOutputModeHandle = nil
            activeCanvasDrag = nil
            return
        }
        if pendingSketchVertexOffsetHandle != nil || activeSketchVertexOffsetDrag != nil {
            let sketchVertexOffsetDragTarget = committedSketchVertexOffsetDragTarget()
            pendingSketchVertexOffsetHandle = nil
            activeSketchVertexOffsetDrag = nil
            activeCanvasDrag = nil
            if let sketchVertexOffsetDragTarget {
                onSketchVertexOffsetDrag?(sketchVertexOffsetDragTarget)
            }
            return
        }
        if pendingRegionOffsetHandle != nil || activeRegionOffsetDrag != nil {
            let regionOffsetDragTarget = committedRegionOffsetDragTarget()
            pendingRegionOffsetHandle = nil
            activeRegionOffsetDrag = nil
            activeCanvasDrag = nil
            if let regionOffsetDragTarget {
                onRegionOffsetDrag?(regionOffsetDragTarget)
            }
            return
        }
        if pendingAffordance != nil || activeAffordanceDrag != nil {
            let vertexDragTarget = committedVertexDragTarget(to: end, size: size)
            let faceDragTarget = committedFaceDragTarget(to: end, size: size)
            let edgeChamferDragTarget = committedEdgeChamferDragTarget(to: end, size: size)
            let edgeFilletDragTarget = committedEdgeFilletDragTarget(to: end, size: size)
            pendingAffordance = nil
            activeAffordanceDrag = nil
            activeCanvasDrag = nil
            if let vertexDragTarget {
                editedBodies.removeValue(forKey: vertexDragTarget.featureID)
                onVertexDrag?(vertexDragTarget.target)
            }
            if let faceDragTarget {
                editedBodies.removeValue(forKey: faceDragTarget.featureID)
                onFaceDrag?(faceDragTarget.target)
            }
            if let edgeChamferDragTarget {
                editedBodies.removeValue(forKey: edgeChamferDragTarget.featureID)
                onEdgeChamferDrag?(edgeChamferDragTarget.target)
            }
            if let edgeFilletDragTarget {
                editedBodies.removeValue(forKey: edgeFilletDragTarget.featureID)
                onEdgeFilletDrag?(edgeFilletDragTarget.target)
            }
            return
        }
        defer {
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
        }
        if allowsSelectionRectangle {
            handleSelectionDrag(
                from: start,
                to: end,
                size: size,
                selectionIntent: selectionIntent
            )
            return
        }
        guard let onCanvasDrag else {
            return
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        let sketchPlane = activeCanvasDrag?.sketchPlane ?? canvasDragSketchPlane(for: hoveredCanvasHit)
        onCanvasDrag(
            mapper.modelDrag(
                from: start,
                to: end,
                sketchPlane: sketchPlane,
                modifierFlags: modifierFlags,
                startWorldPoint: selectedGeneratedFaceSurfaceWorldPoint(
                    at: start,
                    in: scene,
                    layout: mapper.layout
                ),
                endWorldPoint: selectedGeneratedFaceSurfaceWorldPoint(
                    at: end,
                    in: scene,
                    layout: mapper.layout
                )
            ).constrained(by: canvasDragAxisConstraint)
        )
    }

    private func committedSketchCurveHandleDragTarget() -> ViewportSketchCurveHandleDragTarget? {
        guard let activeSketchCurveHandleDrag else {
            return nil
        }
        let changedRadius = hasChanged(
            activeSketchCurveHandleDrag.radiusMeters,
            from: activeSketchCurveHandleDrag.target.radiusMeters
        )
        let changedStartAngle = hasChanged(
            activeSketchCurveHandleDrag.startAngleRadians,
            from: activeSketchCurveHandleDrag.target.startAngleRadians
        )
        let changedEndAngle = hasChanged(
            activeSketchCurveHandleDrag.endAngleRadians,
            from: activeSketchCurveHandleDrag.target.endAngleRadians
        )
        guard changedRadius || changedStartAngle || changedEndAngle else {
            return nil
        }
        return ViewportSketchCurveHandleDragTarget(
            target: activeSketchCurveHandleDrag.target.target,
            handle: activeSketchCurveHandleDrag.target.handle,
            radiusMeters: changedRadius ? activeSketchCurveHandleDrag.radiusMeters : nil,
            startAngleRadians: changedStartAngle ? activeSketchCurveHandleDrag.startAngleRadians : nil,
            endAngleRadians: changedEndAngle ? activeSketchCurveHandleDrag.endAngleRadians : nil
        )
    }

    private func hasChanged(_ candidate: Double?, from baseline: Double?) -> Bool {
        guard let candidate, let baseline else {
            return false
        }
        return abs(candidate - baseline) > 1.0e-12
    }

    private func committedSketchDimensionDragTarget() -> ViewportSketchDimensionDragTarget? {
        guard let activeSketchDimensionDrag,
              abs(activeSketchDimensionDrag.value - activeSketchDimensionDrag.target.baselineValue) > 1.0e-12 else {
            return nil
        }
        return ViewportSketchDimensionDragTarget(
            target: activeSketchDimensionDrag.target.target,
            kind: activeSketchDimensionDrag.target.kind,
            value: sketchDimensionExpression(
                for: activeSketchDimensionDrag.target.kind,
                value: activeSketchDimensionDrag.value
            )
        )
    }

    private func sketchDimensionExpression(
        for kind: SketchEntityDimensionKind,
        value: Double
    ) -> CADExpression {
        switch kind {
        case .length, .radius, .diameter:
            return .length(value, .meter)
        case .angle:
            return .angle(value, .radian)
        }
    }

    private func committedSketchPointHandleDragTarget() -> ViewportSketchPointHandleDragTarget? {
        guard let activeSketchPointHandleDrag else {
            return nil
        }
        let localDelta = localSketchDelta(
            fromViewportDelta: activeSketchPointHandleDrag.viewportDelta,
            sketchPlane: activeSketchPointHandleDrag.target.sketchPlane
        )
        guard abs(localDelta.x) > 1.0e-12 || abs(localDelta.y) > 1.0e-12 else {
            return nil
        }
        return ViewportSketchPointHandleDragTarget(
            target: activeSketchPointHandleDrag.target.target,
            handle: activeSketchPointHandleDrag.target.handle,
            deltaX: Double(localDelta.x),
            deltaY: Double(localDelta.y)
        )
    }

    private func committedSplineControlPointDragTarget() -> ViewportSplineControlPointDragTarget? {
        guard let activeSplineControlPointDrag else {
            return nil
        }
        let localDelta = localSketchDelta(
            fromViewportDelta: activeSplineControlPointDrag.viewportDelta,
            sketchPlane: activeSplineControlPointDrag.target.sketchPlane
        )
        guard abs(localDelta.x) > 1.0e-12 || abs(localDelta.y) > 1.0e-12 else {
            return nil
        }
        return ViewportSplineControlPointDragTarget(
            target: activeSplineControlPointDrag.target.target,
            controlPointIndex: activeSplineControlPointDrag.target.controlPointIndex,
            deltaX: Double(localDelta.x),
            deltaY: Double(localDelta.y)
        )
    }

    private func committedBridgeCurveEndpointDragTarget() -> ViewportBridgeCurveEndpointDragTarget? {
        guard let activeBridgeCurveEndpointDrag else {
            return nil
        }
        let currentParameter = resolvedBridgeCurveEndpointParameter(
            activeBridgeCurveEndpointDrag.target.endpoint,
            featureID: activeBridgeCurveEndpointDrag.target.featureID
        )
        if let currentParameter,
           abs(currentParameter - activeBridgeCurveEndpointDrag.parameter) <= 1.0e-8 {
            return nil
        }
        return ViewportBridgeCurveEndpointDragTarget(
            sourceID: activeBridgeCurveEndpointDrag.target.sourceID,
            role: activeBridgeCurveEndpointDrag.target.role,
            endpoint: activeBridgeCurveEndpointDrag.endpoint
        )
    }

    private func resolvedBridgeCurveEndpointParameter(
        _ endpoint: BridgeCurveEndpoint,
        featureID: FeatureID
    ) -> Double? {
        do {
            return try BridgeCurveEndpointParameterProjectionService().parameter(
                for: endpoint,
                featureID: featureID,
                in: document
            )
        } catch {
            return nil
        }
    }

    private func committedSplineControlPointSlideDragTarget() -> ViewportSplineControlPointSlideDragTarget? {
        guard let activeSplineControlPointSlideDrag else {
            return nil
        }
        let distance = activeSplineControlPointSlideDrag.distanceMeters
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return ViewportSplineControlPointSlideDragTarget(
            target: activeSplineControlPointSlideDrag.target.target,
            controlPointIndexes: activeSplineControlPointSlideDrag.target.controlPointIndexes,
            direction: activeSplineControlPointSlideDrag.target.direction,
            distance: distance
        )
    }

    private func committedPolySplineSurfaceVertexSlideDragTarget() -> ViewportPolySplineSurfaceVertexSlideDragTarget? {
        guard let activePolySplineSurfaceVertexSlideDrag else {
            return nil
        }
        let distance = activePolySplineSurfaceVertexSlideDrag.distanceMeters
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return ViewportPolySplineSurfaceVertexSlideDragTarget(
            targets: activePolySplineSurfaceVertexSlideDrag.target.targets,
            direction: activePolySplineSurfaceVertexSlideDrag.target.direction,
            distance: distance
        )
    }

    private func committedSurfaceControlPointSlideDragTarget() -> ViewportSurfaceControlPointSlideDragTarget? {
        guard let activeSurfaceControlPointSlideDrag else {
            return nil
        }
        let distance = activeSurfaceControlPointSlideDrag.distanceMeters
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return ViewportSurfaceControlPointSlideDragTarget(
            targets: activeSurfaceControlPointSlideDrag.target.targets,
            direction: activeSurfaceControlPointSlideDrag.target.direction,
            distance: distance
        )
    }

    private func committedSurfaceFrameDragTarget() -> ViewportSurfaceFrameDragTarget? {
        guard let activeSurfaceFrameDrag else {
            return nil
        }
        let distance = activeSurfaceFrameDrag.distanceMeters
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return ViewportSurfaceFrameDragTarget(
            targets: activeSurfaceFrameDrag.target.targets,
            query: activeSurfaceFrameDrag.target.query,
            axis: activeSurfaceFrameDrag.target.axis,
            distance: distance
        )
    }

    private func committedPolySplineSurfaceVertexDragTarget() -> ViewportPolySplineSurfaceVertexDragTarget? {
        guard let activePolySplineSurfaceVertexDrag else {
            return nil
        }
        let delta = activePolySplineSurfaceVertexDrag.delta
        guard abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 || abs(delta.z) > 1.0e-12 else {
            return nil
        }
        return ViewportPolySplineSurfaceVertexDragTarget(
            target: activePolySplineSurfaceVertexDrag.target.target,
            deltaX: delta.x,
            deltaY: delta.y,
            deltaZ: delta.z
        )
    }

    private func committedSurfaceControlPointDragTarget() -> ViewportSurfaceControlPointDragTarget? {
        guard let activeSurfaceControlPointDrag else {
            return nil
        }
        let delta = activeSurfaceControlPointDrag.delta
        guard abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 || abs(delta.z) > 1.0e-12 else {
            return nil
        }
        return ViewportSurfaceControlPointDragTarget(
            target: activeSurfaceControlPointDrag.target.target,
            deltaX: delta.x,
            deltaY: delta.y,
            deltaZ: delta.z
        )
    }

    private func committedSurfaceTrimEndpointDragTarget() -> ViewportSurfaceTrimEndpointDragTarget? {
        guard let activeSurfaceTrimEndpointDrag else {
            return nil
        }
        let delta = activeSurfaceTrimEndpointDrag.delta
        guard abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 || abs(delta.z) > 1.0e-12 else {
            return nil
        }
        guard let movedUV = movedSurfaceTrimEndpointUV(
            target: activeSurfaceTrimEndpointDrag.target,
            delta: delta
        ) else {
            return nil
        }
        return ViewportSurfaceTrimEndpointDragTarget(
            target: activeSurfaceTrimEndpointDrag.target.target,
            endpoint: activeSurfaceTrimEndpointDrag.target.endpoint,
            u: movedUV.u,
            v: movedUV.v
        )
    }

    private func committedSurfaceTrimControlPointDragTarget() -> ViewportSurfaceTrimControlPointDragTarget? {
        guard let activeSurfaceTrimControlPointDrag else {
            return nil
        }
        let delta = activeSurfaceTrimControlPointDrag.delta
        guard abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 || abs(delta.z) > 1.0e-12 else {
            return nil
        }
        guard let movedUV = movedSurfaceTrimControlPointUV(
            target: activeSurfaceTrimControlPointDrag.target,
            delta: delta
        ) else {
            return nil
        }
        return ViewportSurfaceTrimControlPointDragTarget(
            target: activeSurfaceTrimControlPointDrag.target.target,
            controlPointIndex: activeSurfaceTrimControlPointDrag.target.controlPointIndex,
            u: movedUV.u,
            v: movedUV.v
        )
    }

    private func movedSurfaceTrimEndpointUV(
        target: ViewportSurfaceTrimEndpointHandleTarget,
        delta: Point3D
    ) -> (u: Double, v: Double)? {
        movedSurfaceTrimUV(
            u: target.u,
            v: target.v,
            tangentU: target.tangentU,
            tangentV: target.tangentV,
            delta: delta
        )
    }

    private func movedSurfaceTrimControlPointUV(
        target: ViewportSurfaceTrimControlPointHandleTarget,
        delta: Point3D
    ) -> (u: Double, v: Double)? {
        movedSurfaceTrimUV(
            u: target.u,
            v: target.v,
            tangentU: target.tangentU,
            tangentV: target.tangentV,
            delta: delta
        )
    }

    private func movedSurfaceTrimUV(
        u: Double,
        v: Double,
        tangentU: Vector3D,
        tangentV: Vector3D,
        delta: Point3D
    ) -> (u: Double, v: Double)? {
        let move = Vector3D(x: delta.x, y: delta.y, z: delta.z)
        let uu = tangentU.dot(tangentU)
        let uv = tangentU.dot(tangentV)
        let vv = tangentV.dot(tangentV)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              abs(determinant) > 1.0e-18 else {
            return nil
        }
        let moveU = move.dot(tangentU)
        let moveV = move.dot(tangentV)
        let deltaU = (moveU * vv - moveV * uv) / determinant
        let deltaV = (uu * moveV - uv * moveU) / determinant
        let movedU = u + deltaU
        let movedV = v + deltaV
        guard movedU.isFinite,
              movedV.isFinite,
              abs(movedU - u) > 1.0e-12 || abs(movedV - v) > 1.0e-12 else {
            return nil
        }
        return (movedU, movedV)
    }

    private func committedRegionOffsetDragTarget() -> ViewportRegionOffsetDragTarget? {
        guard let activeRegionOffsetDrag else {
            return nil
        }
        let distance = activeRegionOffsetDrag.distanceMeters
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return ViewportRegionOffsetDragTarget(
            target: activeRegionOffsetDrag.target.target,
            distance: distance
        )
    }

    private func committedEdgeOffsetDragTarget() -> ViewportEdgeOffsetDragTarget? {
        guard let activeEdgeOffsetDrag else {
            return nil
        }
        let distance = activeEdgeOffsetDrag.distanceMeters
        guard abs(distance - activeEdgeOffsetDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        return ViewportEdgeOffsetDragTarget(
            target: activeEdgeOffsetDrag.target.target,
            distance: distance
        )
    }

    private func committedSlotWidthDragTarget() -> ViewportSlotWidthDragTarget? {
        guard let activeSlotWidthDrag else {
            return nil
        }
        let width = activeSlotWidthDrag.widthMeters
        guard abs(width - activeSlotWidthDrag.target.geometry.baseWidthMeters) > 1.0e-12 else {
            return nil
        }
        return ViewportSlotWidthDragTarget(
            target: activeSlotWidthDrag.target.target,
            width: width
        )
    }

    private func committedIndependentCopyExtrudeDistanceDragTarget() -> ViewportIndependentCopyExtrudeDistanceDragTarget? {
        guard let activeIndependentCopyExtrudeDistanceDrag else {
            return nil
        }
        let distance = activeIndependentCopyExtrudeDistanceDrag.distanceMeters
        guard abs(distance - activeIndependentCopyExtrudeDistanceDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        let localDistance = distance / activeIndependentCopyExtrudeDistanceDrag.target.valueScale
        guard localDistance.isFinite,
              localDistance > 0.0 else {
            return nil
        }
        return ViewportIndependentCopyExtrudeDistanceDragTarget(
            sourceID: activeIndependentCopyExtrudeDistanceDrag.target.sourceID,
            outputIndex: activeIndependentCopyExtrudeDistanceDrag.target.outputIndex,
            outputSceneNodeID: activeIndependentCopyExtrudeDistanceDrag.target.outputSceneNodeID,
            featureID: activeIndependentCopyExtrudeDistanceDrag.target.featureID,
            distance: localDistance
        )
    }

    private func committedIndependentCopyBodyDimensionDragTarget() -> ViewportIndependentCopyBodyDimensionDragTarget? {
        guard let activeIndependentCopyBodyDimensionDrag else {
            return nil
        }
        let displayValue = activeIndependentCopyBodyDimensionDrag.valueMeters
        guard abs(displayValue - activeIndependentCopyBodyDimensionDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        let localValue = displayValue / activeIndependentCopyBodyDimensionDrag.target.valueScale
        guard localValue.isFinite,
              localValue > 0.0 else {
            return nil
        }
        return ViewportIndependentCopyBodyDimensionDragTarget(
            sourceID: activeIndependentCopyBodyDimensionDrag.target.sourceID,
            outputIndex: activeIndependentCopyBodyDimensionDrag.target.outputIndex,
            outputSceneNodeID: activeIndependentCopyBodyDimensionDrag.target.outputSceneNodeID,
            featureID: activeIndependentCopyBodyDimensionDrag.target.featureID,
            kind: activeIndependentCopyBodyDimensionDrag.target.kind,
            value: localValue
        )
    }

    private func committedPatternArrayLinearAxisDragTarget() -> ViewportPatternArrayLinearAxisDragTarget? {
        guard let activePatternArrayLinearAxisDrag else {
            return nil
        }
        let distance = activePatternArrayLinearAxisDrag.distanceMeters
        guard abs(distance - activePatternArrayLinearAxisDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        return ViewportPatternArrayLinearAxisDragTarget(
            sourceID: activePatternArrayLinearAxisDrag.target.sourceID,
            axisSlot: activePatternArrayLinearAxisDrag.target.axisSlot,
            distance: distance
        )
    }

    private func committedPatternArrayRadialAngleDragTarget() -> ViewportPatternArrayRadialAngleDragTarget? {
        guard let activePatternArrayRadialAngleDrag else {
            return nil
        }
        let angleRadians = activePatternArrayRadialAngleDrag.angleRadians
        guard abs(angleRadians - activePatternArrayRadialAngleDrag.target.geometry.baseAngleRadians) > 1.0e-12 else {
            return nil
        }
        return ViewportPatternArrayRadialAngleDragTarget(
            sourceID: activePatternArrayRadialAngleDrag.target.sourceID,
            angleRadians: angleRadians
        )
    }

    private func committedPatternArrayCopyCountDragTarget() -> ViewportPatternArrayCopyCountDragTarget? {
        guard let activePatternArrayCopyCountDrag else {
            return nil
        }
        let copyCount = activePatternArrayCopyCountDrag.copyCount
        guard copyCount != activePatternArrayCopyCountDrag.target.geometry.baseCopyCount else {
            return nil
        }
        return ViewportPatternArrayCopyCountDragTarget(
            sourceID: activePatternArrayCopyCountDrag.target.sourceID,
            slot: activePatternArrayCopyCountDrag.target.slot,
            copyCount: copyCount
        )
    }

    private func committedPatternArrayCurveExtentDragTarget() -> ViewportPatternArrayCurveExtentDragTarget? {
        guard let activePatternArrayCurveExtentDrag else {
            return nil
        }
        let distanceMeters = activePatternArrayCurveExtentDrag.distanceMeters
        guard abs(distanceMeters - activePatternArrayCurveExtentDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        let extent: ViewportPatternArrayCurveExtentDragValue
        switch activePatternArrayCurveExtentDrag.target.extentMode {
        case .distance:
            extent = .distance(distanceMeters)
        case .ratio:
            extent = .ratio(distanceMeters / activePatternArrayCurveExtentDrag.target.geometry.totalLengthMeters)
        }
        return ViewportPatternArrayCurveExtentDragTarget(
            sourceID: activePatternArrayCurveExtentDrag.target.sourceID,
            extent: extent
        )
    }

    private func committedPatternArrayCurvePathPointDragTarget() -> ViewportPatternArrayCurvePathPointDragTarget? {
        guard let activePatternArrayCurvePathPointDrag else {
            return nil
        }
        let point = activePatternArrayCurvePathPointDrag.point
        guard point.x.isFinite,
              point.y.isFinite,
              point.z.isFinite,
              patternArrayCurvePathPointDistance(
                point,
                activePatternArrayCurvePathPointDrag.target.basePoint
              ) > 1.0e-12 else {
            return nil
        }
        return ViewportPatternArrayCurvePathPointDragTarget(
            sourceID: activePatternArrayCurvePathPointDrag.target.sourceID,
            pointIndex: activePatternArrayCurvePathPointDrag.target.pointIndex,
            point: point
        )
    }

    private func patternArrayCurvePathPointDistance(
        _ lhs: Point3D,
        _ rhs: Point3D
    ) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        let dz = lhs.z - rhs.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    private func committedSketchVertexOffsetDragTarget() -> ViewportSketchVertexOffsetDragTarget? {
        guard let activeSketchVertexOffsetDrag else {
            return nil
        }
        let distance = activeSketchVertexOffsetDrag.distanceMeters
        guard abs(distance - activeSketchVertexOffsetDrag.target.geometry.baseDistanceMeters) > 1.0e-12 else {
            return nil
        }
        return ViewportSketchVertexOffsetDragTarget(
            target: activeSketchVertexOffsetDrag.target.target,
            handle: activeSketchVertexOffsetDrag.target.handle,
            distance: distance
        )
    }

    private func localSketchDelta(
        fromViewportDelta delta: CGPoint,
        sketchPlane: SketchPlane
    ) -> CGPoint {
        switch sketchPlane {
        case .xy, .yz, .plane:
            return delta
        case .zx:
            return CGPoint(x: delta.y, y: delta.x)
        }
    }

    private func localSketchPoint(
        fromViewportPoint point: CGPoint,
        sketchPlane: SketchPlane
    ) -> CGPoint {
        switch sketchPlane {
        case .xy, .yz, .plane:
            return point
        case .zx:
            return CGPoint(x: point.y, y: point.x)
        }
    }

    private func committedVertexDragTarget(
        to end: CGPoint,
        size: CGSize
    ) -> (featureID: FeatureID, target: ViewportVertexDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileCornerMove(let target, _) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let delta = baseEdit.profileCornerDragDelta(
            start: activeAffordanceDrag.startPoint,
            current: end,
            layout: layout
        )
        guard abs(delta.x) > 1.0e-12 || abs(delta.y) > 1.0e-12 else {
            return nil
        }
        return (
            activeAffordanceDrag.target.featureID,
            ViewportVertexDragTarget(
                target: target,
                deltaX: Double(delta.x),
                deltaY: Double(delta.y)
            )
        )
    }

    private func committedFaceDragTarget(
        to end: CGPoint,
        size: CGSize
    ) -> (featureID: FeatureID, target: ViewportFaceDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileFaceMove(let target, let face) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        guard let distance = baseEdit.profileFaceDragDistance(
            face,
            start: activeAffordanceDrag.startPoint,
            current: end,
            layout: layout
        ) else {
            return nil
        }
        guard abs(distance) > 1.0e-12 else {
            return nil
        }
        return (
            activeAffordanceDrag.target.featureID,
            ViewportFaceDragTarget(
                target: target,
                distance: Double(distance)
            )
        )
    }

    private func committedEdgeChamferDragTarget(
        to end: CGPoint,
        size: CGSize
    ) -> (featureID: FeatureID, target: ViewportEdgeChamferDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileEdgeChamfer(let target, let edge) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        guard let distance = baseEdit.profileEdgeChamferDistance(
            edge,
            start: activeAffordanceDrag.startPoint,
            current: end,
            layout: layout
        ) else {
            return nil
        }
        guard distance > 1.0e-12 else {
            return nil
        }
        return (
            activeAffordanceDrag.target.featureID,
            ViewportEdgeChamferDragTarget(
                target: target,
                distance: Double(distance)
            )
        )
    }

    private func committedEdgeFilletDragTarget(
        to end: CGPoint,
        size: CGSize
    ) -> (featureID: FeatureID, target: ViewportEdgeFilletDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileEdgeFillet(let target, let edge) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        guard let radius = baseEdit.profileEdgeFilletRadius(
            edge,
            start: activeAffordanceDrag.startPoint,
            current: end,
            layout: layout
        ) else {
            return nil
        }
        guard radius > 1.0e-12 else {
            return nil
        }
        return (
            activeAffordanceDrag.target.featureID,
            ViewportEdgeFilletDragTarget(
                target: target,
                radius: Double(radius)
            )
        )
    }

    private func handleSelectionDrag(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        guard let onSelectionDrag else {
            return
        }
        onSelectionDrag(
            ViewportSelectionDragTarget(
                hits: selectionHits(
                    from: start,
                    to: end,
                    size: size
                ),
                selectionIntent: selectionIntent
            )
        )
    }

    private func publishSelectionDragPreview(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) {
        publishSelectionDragPreview(
            hits: selectionHits(
                from: start,
                to: end,
                size: size
            )
        )
    }

    private func publishSelectionDragPreview(hits: [ViewportHit]) {
        onSelectionDragPreview?(
            ViewportSelectionDragTarget(hits: hits)
        )
    }

    private func selectionHits(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) -> [ViewportHit] {
        let rect = dragRect(from: start, to: end)
        guard rect.width > 0.0, rect.height > 0.0 else {
            return []
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedTargetFeatureIDs()
        )
        return identityHitResolver.selectionHits(
            in: rect,
            scene: hitScene,
            layout: mapper.layout,
            sketchControlPointHitPolicy: sketchControlPointHitPolicy(for: hitScene),
            selectionHitPolicy: selectionHitPolicy
        )
    }

    private func hover(at point: CGPoint, size: CGSize) {
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        hoveredRegionOffsetHandle = nil
        hoveredEdgeOffsetHandle = nil
        hoveredSlotWidthHandle = nil
        hoveredSketchVertexOffsetHandle = nil
        hoveredPatternArrayLinearAxisHandle = nil
        hoveredIndependentCopyExtrudeDistanceHandle = nil
        hoveredIndependentCopyBodyDimensionHandle = nil
        hoveredPatternArrayRadialAngleHandle = nil
        hoveredPatternArrayCopyCountHandle = nil
        hoveredPatternArrayCurveExtentHandle = nil
        hoveredPatternArrayCurvePathPointHandle = nil
        hoveredPatternArrayOutputModeHandle = nil
        hoveredSplineControlPointSlideHandle = nil
        hoveredPolySplineSurfaceVertexSlideHandle = nil
        hoveredSurfaceControlPointSlideHandle = nil
        hoveredSurfaceFrameHandle = nil
        hoveredSurfaceControlPoint = nil
        hoveredSurfaceTrimEndpoint = nil
        hoveredSurfaceTrimControlPoint = nil
        hoveredBridgeCurveEndpointHandle = nil
        if let sketchCurveHandleTarget = selectedSketchCurveHandleTarget(at: point, size: size) {
            hoveredSketchCurveHandle = sketchCurveHandleTarget
            hoveredSketchDimension = nil
            hoveredSketchPointHandle = nil
            hoveredSplineControlPoint = nil
            hoveredSplineControlPointSlideHandle = nil
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSketchCurveHandle = nil
        if let sketchPointHandleTarget = selectedSketchPointHandleTarget(at: point, size: size) {
            hoveredSketchPointHandle = sketchPointHandleTarget
            hoveredSketchDimension = nil
            hoveredSplineControlPoint = nil
            hoveredSplineControlPointSlideHandle = nil
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSketchPointHandle = nil
        if let sketchDimensionTarget = selectedSketchDimensionTarget(at: point, size: size) {
            hoveredSketchDimension = sketchDimensionTarget
            hoveredSplineControlPoint = nil
            hoveredSplineControlPointSlideHandle = nil
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSketchDimension = nil
        if let bridgeCurveEndpointTarget = selectedBridgeCurveEndpointTarget(at: point, size: size) {
            hoveredBridgeCurveEndpointHandle = bridgeCurveEndpointTarget
            hoveredSplineControlPoint = nil
            hoveredSplineControlPointSlideHandle = nil
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredBridgeCurveEndpointHandle = nil
        if let splineControlPointSlideTarget = selectedSplineControlPointSlideAffordanceTarget(at: point, size: size) {
            hoveredSplineControlPointSlideHandle = splineControlPointSlideTarget
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredSplineControlPoint = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSplineControlPointSlideHandle = nil
        if let polySplineSurfaceVertexSlideTarget = selectedPolySplineSurfaceVertexSlideAffordanceTarget(at: point, size: size) {
            hoveredPolySplineSurfaceVertexSlideHandle = polySplineSurfaceVertexSlideTarget
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredSplineControlPoint = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSurfaceControlPoint = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPolySplineSurfaceVertexSlideHandle = nil
        if let surfaceControlPointSlideTarget = selectedSurfaceControlPointSlideAffordanceTarget(at: point, size: size) {
            hoveredSurfaceControlPointSlideHandle = surfaceControlPointSlideTarget
            hoveredSplineControlPoint = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSurfaceControlPoint = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSurfaceControlPointSlideHandle = nil
        if let surfaceFrameTarget = selectedSurfaceFrameAffordanceTarget(at: point, size: size) {
            hoveredSurfaceFrameHandle = surfaceFrameTarget
            hoveredSplineControlPoint = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSurfaceControlPoint = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSurfaceFrameHandle = nil
        if let splineControlPointTarget = selectedSplineControlPointTarget(at: point, size: size) {
            hoveredSplineControlPoint = splineControlPointTarget
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredPolySplineSurfaceVertex = nil
            hoveredSurfaceControlPoint = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSplineControlPoint = nil
        if let polySplineSurfaceVertexTarget = selectedPolySplineSurfaceVertexTarget(at: point, size: size) {
            hoveredPolySplineSurfaceVertex = polySplineSurfaceVertexTarget
            hoveredPolySplineSurfaceVertexSlideHandle = nil
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredEdgeOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPolySplineSurfaceVertex = nil
        if let surfaceControlPointTarget = selectedSurfaceControlPointTarget(at: point, size: size) {
            hoveredSurfaceControlPoint = surfaceControlPointTarget
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredEdgeOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSurfaceControlPoint = nil
        if let surfaceTrimEndpointTarget = selectedSurfaceTrimEndpointTarget(at: point, size: size) {
            hoveredSurfaceTrimEndpoint = surfaceTrimEndpointTarget
            hoveredSurfaceTrimControlPoint = nil
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredEdgeOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSurfaceTrimEndpoint = nil
        if let surfaceTrimControlPointTarget = selectedSurfaceTrimControlPointTarget(at: point, size: size) {
            hoveredSurfaceTrimControlPoint = surfaceTrimControlPointTarget
            hoveredSurfaceControlPointSlideHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredEdgeOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSurfaceTrimControlPoint = nil
        if let edgeOffsetTarget = selectedEdgeOffsetAffordanceTarget(at: point, size: size) {
            hoveredEdgeOffsetHandle = edgeOffsetTarget
            hoveredSlotWidthHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredEdgeOffsetHandle = nil
        if let slotWidthTarget = selectedSlotWidthAffordanceTarget(at: point, size: size) {
            hoveredSlotWidthHandle = slotWidthTarget
            hoveredSketchVertexOffsetHandle = nil
            hoveredPatternArrayLinearAxisHandle = nil
            hoveredIndependentCopyExtrudeDistanceHandle = nil
            hoveredIndependentCopyBodyDimensionHandle = nil
            hoveredPatternArrayRadialAngleHandle = nil
            hoveredPatternArrayCopyCountHandle = nil
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSlotWidthHandle = nil
        if let independentCopyExtrudeDistanceTarget = selectedIndependentCopyExtrudeDistanceAffordanceTarget(at: point, size: size) {
            hoveredIndependentCopyExtrudeDistanceHandle = independentCopyExtrudeDistanceTarget
            hoveredIndependentCopyBodyDimensionHandle = nil
            hoveredPatternArrayLinearAxisHandle = nil
            hoveredPatternArrayRadialAngleHandle = nil
            hoveredPatternArrayCopyCountHandle = nil
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredIndependentCopyExtrudeDistanceHandle = nil
        if let independentCopyBodyDimensionTarget = selectedIndependentCopyBodyDimensionAffordanceTarget(at: point, size: size) {
            hoveredIndependentCopyBodyDimensionHandle = independentCopyBodyDimensionTarget
            hoveredPatternArrayLinearAxisHandle = nil
            hoveredPatternArrayRadialAngleHandle = nil
            hoveredPatternArrayCopyCountHandle = nil
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredIndependentCopyBodyDimensionHandle = nil
        if let patternArrayLinearAxisTarget = selectedPatternArrayLinearAxisAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayLinearAxisHandle = patternArrayLinearAxisTarget
            hoveredIndependentCopyExtrudeDistanceHandle = nil
            hoveredIndependentCopyBodyDimensionHandle = nil
            hoveredPatternArrayRadialAngleHandle = nil
            hoveredPatternArrayCopyCountHandle = nil
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayLinearAxisHandle = nil
        if let patternArrayRadialAngleTarget = selectedPatternArrayRadialAngleAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayRadialAngleHandle = patternArrayRadialAngleTarget
            hoveredPatternArrayCopyCountHandle = nil
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayRadialAngleHandle = nil
        if let patternArrayCopyCountTarget = selectedPatternArrayCopyCountAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayCopyCountHandle = patternArrayCopyCountTarget
            hoveredPatternArrayCurveExtentHandle = nil
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayCopyCountHandle = nil
        if let patternArrayCurveExtentTarget = selectedPatternArrayCurveExtentAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayCurveExtentHandle = patternArrayCurveExtentTarget
            hoveredPatternArrayCurvePathPointHandle = nil
            hoveredPatternArrayOutputModeHandle = nil
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayCurveExtentHandle = nil
        if let patternArrayCurvePathPointTarget = selectedPatternArrayCurvePathPointAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayCurvePathPointHandle = patternArrayCurvePathPointTarget
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayCurvePathPointHandle = nil
        if let patternArrayOutputModeTarget = selectedPatternArrayOutputModeAffordanceTarget(at: point, size: size) {
            hoveredPatternArrayOutputModeHandle = patternArrayOutputModeTarget
            hoveredSketchVertexOffsetHandle = nil
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredPatternArrayOutputModeHandle = nil
        if let sketchVertexOffsetTarget = selectedSketchVertexOffsetAffordanceTarget(at: point, size: size) {
            hoveredSketchVertexOffsetHandle = sketchVertexOffsetTarget
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredSketchVertexOffsetHandle = nil
        if let regionOffsetTarget = selectedRegionOffsetAffordanceTarget(at: point, size: size) {
            hoveredRegionOffsetHandle = regionOffsetTarget
            hoveredAffordance = nil
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        if let edgeFilletTarget = selectedEdgeFilletAffordanceTarget(at: point, size: size) {
            hoveredAffordance = edgeFilletTarget
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        if let edgeTarget = selectedEdgeAffordanceTarget(at: point, size: size) {
            hoveredAffordance = edgeTarget
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        if allowsObjectAffordances,
           let affordanceTarget = affordanceTarget(
               at: point,
               scene: scene,
               layout: mapper.layout
           ) {
            hoveredAffordance = affordanceTarget
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            clearHoverCallbacks()
            return
        }
        hoveredAffordance = nil
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedTargetFeatureIDs()
        )
        let hit = viewportHit(
            point: point,
            in: hitScene,
            layout: mapper.layout
        )
        hoveredCanvasHit = hit
        hoveredModelPoint = mapper.modelPoint(for: point)
        refreshSnapCandidateKind(size: size)
        onHover?(hit)
    }

    private func clearHoverCallbacks() {
        publishSnapCandidateKind(nil)
        onHover?(nil)
    }

    private func clearCanvasHover() {
        hoveredAffordance = nil
        hoveredSketchCurveHandle = nil
        hoveredSketchDimension = nil
        hoveredSketchPointHandle = nil
        hoveredBridgeCurveEndpointHandle = nil
        hoveredSplineControlPoint = nil
        hoveredSplineControlPointSlideHandle = nil
        hoveredPolySplineSurfaceVertexSlideHandle = nil
        hoveredSurfaceControlPointSlideHandle = nil
        hoveredSurfaceFrameHandle = nil
        hoveredPolySplineSurfaceVertex = nil
        hoveredSurfaceControlPoint = nil
        hoveredSurfaceTrimEndpoint = nil
        hoveredSurfaceTrimControlPoint = nil
        hoveredRegionOffsetHandle = nil
        hoveredEdgeOffsetHandle = nil
        hoveredSlotWidthHandle = nil
        hoveredSketchVertexOffsetHandle = nil
        hoveredPatternArrayLinearAxisHandle = nil
        hoveredIndependentCopyExtrudeDistanceHandle = nil
        hoveredIndependentCopyBodyDimensionHandle = nil
        hoveredPatternArrayRadialAngleHandle = nil
        hoveredPatternArrayCopyCountHandle = nil
        hoveredPatternArrayCurveExtentHandle = nil
        hoveredPatternArrayCurvePathPointHandle = nil
        hoveredPatternArrayOutputModeHandle = nil
        hoveredCanvasHit = nil
        hoveredModelPoint = nil
        clearHoverCallbacks()
    }

    private func clearProjectionTransition(_ id: UUID) {
        Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64((Self.projectionAnimationDuration + 0.05) * 1_000_000_000.0)
                )
            } catch {
                return
            }

            if projectionTransition?.id == id {
                projectionTransition = nil
            }
        }
    }

    private func selectProjectionAxis(_ axis: ViewportCoordinateAxis?) {
        transitionProjection(
            to: targetProjectionBasis(for: axis),
            selectedAxis: axis,
            storesOrbitBasis: false
        )
    }

    private func transitionProjection(
        to targetBasis: ViewportProjectionBasis,
        selectedAxis nextSelectedAxis: ViewportCoordinateAxis?,
        storesOrbitBasis: Bool
    ) {
        let now = Date()
        let startBasis = projectionBasis(at: now)
        let transition = ViewportProjectionTransition(
            startBasis: startBasis,
            targetBasis: targetBasis,
            startDate: now,
            duration: Self.projectionAnimationDuration
        )
        selectedAxis = nextSelectedAxis
        orbitBasis = storesOrbitBasis ? targetBasis : nil
        projectionTransition = transition
        activeCanvasDrag = nil
        clearCanvasHover()
        publishProjectionBasis(targetBasis)
        clearProjectionTransition(transition.id)
    }

    private func resetViewportCamera() {
        camera = .identity
        activeCanvasDrag = nil
        clearCanvasHover()
    }

    private func constructionSketchPlane(for hit: ViewportHit?) -> SketchPlane {
        guard showsConstructionPlaneHover else {
            return .xy
        }

        switch hit?.bodyFace {
        case .top, .bottom:
            return .xy
        case .left, .right, .side:
            return .yz
        case .front, .back, .none:
            return .zx
        }
    }

    private func canvasDragSketchPlane(for hit: ViewportHit?) -> SketchPlane {
        canvasDragSketchPlaneOverride ?? constructionSketchPlane(for: hit)
    }

    private func panCanvas(by delta: CGSize) {
        camera = ViewportCamera(
            zoom: camera.zoom,
            pan: CGSize(
                width: camera.pan.width + delta.width,
                height: camera.pan.height + delta.height
            )
        )
    }

    private func orbitViewport(by delta: CGSize) {
        let nextBasis = currentProjectionBasis.orbited(by: delta)
        selectedAxis = nil
        orbitBasis = nextBasis
        projectionTransition = nil
        activeCanvasDrag = nil
        clearCanvasHover()
        publishProjectionBasis(nextBasis)
    }

    private func zoomCanvas(
        by factor: CGFloat,
        anchor: CGPoint,
        size: CGSize
    ) {
        let basis = currentProjectionBasis
        let oldLayout = makeLayout(
            size: size,
            camera: camera,
            basis: basis
        )
        let maximumZoom = oldLayout.maximumZoom
        let anchoredModelPoint = oldLayout.unproject(anchor)
        let newZoom = min(
            max(camera.zoom * factor, ViewportCamera.minimumZoom),
            maximumZoom
        )
        var nextCamera = ViewportCamera(
            zoom: newZoom,
            pan: camera.pan
        )
        let nextLayout = makeLayout(
            size: size,
            camera: nextCamera,
            basis: basis
        )
        let projectedAnchor = nextLayout.project(anchoredModelPoint)
        nextCamera.pan.width += anchor.x - projectedAnchor.x
        nextCamera.pan.height += anchor.y - projectedAnchor.y
        camera = nextCamera.clamped(maximumZoom: maximumZoom)
    }
}
