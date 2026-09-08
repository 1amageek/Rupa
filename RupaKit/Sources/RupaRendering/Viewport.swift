import Foundation
import OSLog
import RupaCore
import RupaGeometry
import SwiftUI
import RupaViewportScene
import SwiftCAD

/// Lightweight identity for rebuilding the mounted viewport context.
///
/// Camera and revision are deliberately excluded: camera mutations are
/// session state, while this key only tracks inputs that change the geometry
/// context used by fit commands.
private struct ViewportControlContextKey: Equatable, Sendable {
    let viewportID: ViewportInstanceID
    let presentationSnapshotID: EvaluationSnapshotID?
    let documentGeneration: DocumentGeneration?
    let viewportSize: CGSize
    let ruler: RulerConfiguration
    let fittingInsets: ViewportLayout.FittingInsets
    let selectedSceneNodeIDs: [SceneNodeID]
}

@MainActor
public struct Viewport: View {
    private static let projectionAnimationDuration: TimeInterval = 0.34
    private static let snapOverlayLogger = Logger(
        subsystem: "RupaRendering",
        category: "ViewportSnapOverlay"
    )
    private static let placementHighlightLogger = Logger(
        subsystem: "RupaRendering",
        category: "ViewportPlacementHighlight"
    )
    private static let referenceLineAnchorLogger = Logger(
        subsystem: "RupaRendering",
        category: "ViewportReferenceLineAnchor"
    )

    @State private var activeCanvasDrag: ViewportActiveDrag?
    @State private var activeInteractionDrags = ViewportActiveInteractionDrags()
    @State private var localControlSession: ViewportControlSession
    @State private var viewportInstanceID: ViewportInstanceID
    @State private var editedBodies: [FeatureID: ViewportObjectEditState] = [:]
    @State private var dragPreviewDocument: DesignDocument?
    @State private var dragPreviewSceneNodeID: SceneNodeID?
    @State private var dragPreviewRevision: UInt64 = 0
    @State private var surfaceFailure: (rendererID: ObjectIdentifier, error: MeshSourcePresentationRenderError)?
    @State private var hoveredInteractionTarget: ViewportInteractionTarget?
    @State private var pendingInteractionTarget: ViewportInteractionTarget?
    @State private var hoveredNativeAxisIdentity: ViewportSpatialHandleIdentity?
    @State private var nativeAxisGesture: NativeAxisGesture?

    private struct NativeAxisPress {
        let input: ViewportNativeAxisInput
        let source: ViewportSourceIdentity
        let snapshotID: EvaluationSnapshotID?
        let selectedTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let start: CGPoint
        var value: Double?
        var finish: (point: CGPoint, revision: UInt64)?
    }

    private enum NativeAxisGesture {
        case active(NativeAxisPress)
        // Consume the rest of a refused gesture, including its mouse-up.
        case cancelled
    }
    @State private var modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    @State private var snapOverlayResult: SnapResolutionResult?
    @State private var snapOverlayFailureDescription: String?
    @State private var placementHighlightState: ViewportPlacementHighlight?
    @State private var placementHighlightFailureDescription: String?
    @State private var reportedSnapCandidateKind: RupaCore.SnapCandidateKind?
    @State private var hoveredCanvasHit: ViewportHit?
    @State private var hoveredModelPoint: Point2D?
    @State private var measurementSession = ViewportMeasurementSession()
    @State private var automaticMeasurementSummary: String?
    @State private var identityHitResolver = ViewportIdentityHitResolver(
        renderBudget: .deviceCalibrated()
    )
    @State private var previewEvaluationCache = ViewportPreviewEvaluationCache()
    @State private var presentationPlanCache = MeshSourcePresentationPlanCache()
    @State private var overlayRevision = ViewportSpatialOverlayRevision()
    @State private var gridFailure: (rendererID: ObjectIdentifier, error: MeshSourcePresentationRenderError)?
    @State private var nativeGridReadout: (rendererID: ObjectIdentifier, value: ViewportProjectedGrid.ScaleReadout)?
    @State private var presentationSectionGeometryCache = MeshSourcePresentationSectionGeometryCache()
    @State private var baseSceneSnapshotCache = ViewportSceneSnapshotCache()
    @State private var sceneSnapshotCache = ViewportSceneSnapshotCache()

    private let controlSession: ViewportControlSession?
    private let document: DesignDocument
    private let sourceIdentity: ViewportSourceIdentity
    private let presentationScene: UniversalViewportScene?
    private let presentationSceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    private let materialColors: [SceneOccurrenceID: ColorRGBA]
    private let workspaceRenderState: ViewportWorkspaceRenderState
    private let currentEvaluation: DocumentEvaluationContext?
    private let evaluationCache: EvaluatedDocumentCache?
    private let objectRegistry: ObjectTypeRegistry
    private let renderInvalidation: RenderInvalidation
    private let selection: SelectionModel
    private let objectSelectionIndex: ViewportObjectSelectionIndex
    private let selectionDragPreviewTargets: [SelectionTarget]
    private let patternArrayCurvePathReplacementPreviewRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest?
    private let surfaceAnalysis: SurfaceAnalysisResult?
    private let surfaceAnalysisOptions: ViewportSurfaceAnalysisOptions
    private let surfaceContinuity: RupaCore.SurfaceContinuityResult?
    private let sectionAnalysis: SectionAnalysisResult?
    private let sectionClippingPlan: SectionAnalysisClippingPlan?
    private let snapResolutionOptions: SnapResolutionOptions?
    private let canvasDragPreviewKind: ViewportCanvasDragPreviewKind?
    private let canvasPlacementPreviewKind: ViewportCanvasPlacementPreviewKind?
    private let canvasDragAxisConstraint: SketchAxisConstraint?
    private let canvasDragSketchPlaneOverride: SketchPlane?
    private let projectionRequest: ViewportProjectionRequest?
    private let cameraFrameRequest: ViewportCameraFrameRequest?
    private let selectionHitPolicy: ViewportSelectionHitPolicy
    private let bottomChromeReservedHeight: CGFloat
    private let canvasOverlayExclusions: [ViewportCanvasOverlayExclusion]
    private let gridVisualSpacingMode: ViewportProjectedGrid.VisualSpacingMode
    private let workspaceScalePresetTitle: String?
    private let workspaceScalePresetOptions: [WorkspaceScalePresetProfile]
    private let canFitWorkspaceScaleToModel: Bool
    private let canSelectSmallerWorkspaceScale: Bool
    private let canSelectLargerWorkspaceScale: Bool
    private let cameraResetSignal: Int
    private let hoverClearSignal: Int
    private let showsConstructionPlaneHover: Bool
    private let measurementToolActive: Bool
    private let showsAutomaticMeasurement: Bool
    private let measurementConstructionPlane: SketchPlane?
    private let allowsSelectionRectangle: Bool
    private let allowsObjectAffordances: Bool
    private let slotWidthMeters: Double
    private let sketchVertexOffsetDistanceMeters: Double
    private let edgeOffsetDistanceMeters: Double
    private let presentationCADInteractionSceneNodeIDs: Set<SceneNodeID>
    private let onPresentationOccurrencePick: ((SceneOccurrenceID, ViewportSelectionIntent) -> Void)?
    private let meshSelectionDomain: GeometryAttributeDomain
    private let meshSelectionOverlay: ViewportMeshSelectionOverlay?
    private let onMeshElementPick: ((ViewportMeshElementHit?, ViewportSelectionIntent) -> Void)?
    private let onPresentationOccurrenceHover: ((SceneOccurrenceID?) -> Void)?
    private let onPick: ((ViewportCanvasTarget) -> Void)?
    private let onCanvasDrag: ((ViewportModelDrag) -> Void)?
    private let onShiftScroll: ((ViewportScrollDirection) -> Bool)?
    private let onReferenceLineAnchor: ((Point2D) -> Bool)?
    private let onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)?
    private let onSelectionDragPreview: ((ViewportSelectionDragTarget) -> Void)?
    private let onBodyMoveDrag: ((ViewportBodyMoveDragTarget) -> Void)?
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
    private let onConstructionPlaneHandleDrag: ((ViewportConstructionPlaneDragTarget) -> Void)?
    private let onCommandConfirm: (() -> Void)?
    private let onFitWorkspaceScaleToModel: (() -> Void)?
    private let onSelectSmallerWorkspaceScale: (() -> Void)?
    private let onSelectLargerWorkspaceScale: (() -> Void)?
    private let onSelectWorkspaceScalePreset: ((WorkspaceScalePreset) -> Void)?
    private let onHover: ((ViewportHit?) -> Void)?
    private let onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)?
    private let onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)?
    private let onCameraFrameChange: ((ViewportCameraFrame?) -> Void)?
    private let onCameraFrameRequestResult: ((UUID, Result<Void, Error>) -> Void)?
    private let onProjectedGridStepChange: ((Double) -> Void)?
    private let onMeasurementStateChange: ((ViewportMeasurementState) -> Void)?
    private let sceneObjectDefinitions: [ObjectTypeDefinition]
    private let presentationInteractionStateResolver: MeshSourcePresentationInteractionStateResolver
    private let selectedPresentationHasExactCADContext: Bool

    private var workspaceRuler: RulerConfiguration {
        workspaceRenderState.ruler
    }

    private var activeControlSession: ViewportControlSession {
        controlSession ?? localControlSession
    }

    private var camera: ViewportCamera {
        get { activeControlSession.camera }
        nonmutating set { setCamera(newValue) }
    }

    private var orbitBasis: ViewportProjectionBasis? {
        get { activeControlSession.orbitBasis }
        nonmutating set {
            activeControlSession.setProjectionTransition(
                activeControlSession.projectionTransition,
                basis: activeControlSession.basis,
                orbitBasis: newValue,
                selectedAxis: selectedAxis
            )
        }
    }

    private var projectionTransition: ViewportProjectionTransition? {
        get { activeControlSession.projectionTransition }
        nonmutating set {
            activeControlSession.setProjectionTransition(
                newValue,
                basis: activeControlSession.basis,
                orbitBasis: orbitBasis,
                selectedAxis: selectedAxis
            )
        }
    }

    private var selectedAxis: ViewportCoordinateAxis? {
        get { activeControlSession.selectedAxis }
        nonmutating set {
            activeControlSession.setProjectionTransition(
                activeControlSession.projectionTransition,
                basis: activeControlSession.basis,
                orbitBasis: orbitBasis,
                selectedAxis: newValue
            )
        }
    }

    private var displayMode: ViewportDisplayMode {
        activeControlSession.displayMode
    }

    private var shading: ViewportShading {
        activeControlSession.shading
    }

    private var isBackfaceCullingActive: Bool {
        shading.isBackfaceCullingActive(in: displayMode)
    }

    private var viewportBackground: Color {
        switch shading.background {
        case .theme:
            ViewportTheme.background
        case .custom(let color):
            Color(red: color.r, green: color.g, blue: color.b, opacity: color.a)
        }
    }

    private var sceneOverlayState: ViewportSceneOverlayState {
        workspaceRenderState.sceneOverlayState
    }

    private var activeAffordanceDrag: ViewportAffordanceDragState? {
        get { activeInteractionDrags.affordance }
        nonmutating set { activeInteractionDrags.affordance = newValue }
    }

    private var activeSketchCurveHandleDrag: ViewportSketchCurveHandleDragState? {
        get { activeInteractionDrags.sketchCurveHandle }
        nonmutating set { activeInteractionDrags.sketchCurveHandle = newValue }
    }

    private var activeSketchDimensionDrag: ViewportSketchDimensionDragState? {
        get { activeInteractionDrags.sketchDimension }
        nonmutating set { activeInteractionDrags.sketchDimension = newValue }
    }

    private var activeSketchPointHandleDrag: ViewportSketchPointHandleDragState? {
        get { activeInteractionDrags.sketchPointHandle }
        nonmutating set { activeInteractionDrags.sketchPointHandle = newValue }
    }

    private var activeBridgeCurveEndpointDrag: ViewportBridgeCurveEndpointDragState? {
        get { activeInteractionDrags.bridgeCurveEndpoint }
        nonmutating set { activeInteractionDrags.bridgeCurveEndpoint = newValue }
    }

    private var activeSplineControlPointDrag: ViewportSplineControlPointDragState? {
        get { activeInteractionDrags.splineControlPoint }
        nonmutating set { activeInteractionDrags.splineControlPoint = newValue }
    }

    private var activeSplineControlPointSlideDrag: ViewportSplineControlPointSlideDragState? {
        get { activeInteractionDrags.splineControlPointSlide }
        nonmutating set { activeInteractionDrags.splineControlPointSlide = newValue }
    }

    private var activePolySplineSurfaceVertexDrag: ViewportPolySplineSurfaceVertexDragState? {
        get { activeInteractionDrags.polySplineSurfaceVertex }
        nonmutating set { activeInteractionDrags.polySplineSurfaceVertex = newValue }
    }

    private var activeSurfaceControlPointDrag: ViewportSurfaceControlPointDragState? {
        get { activeInteractionDrags.surfaceControlPoint }
        nonmutating set { activeInteractionDrags.surfaceControlPoint = newValue }
    }

    private var activeSurfaceTrimEndpointDrag: ViewportSurfaceTrimEndpointDragState? {
        get { activeInteractionDrags.surfaceTrimEndpoint }
        nonmutating set { activeInteractionDrags.surfaceTrimEndpoint = newValue }
    }

    private var activeSurfaceTrimControlPointDrag: ViewportSurfaceTrimControlPointDragState? {
        get { activeInteractionDrags.surfaceTrimControlPoint }
        nonmutating set { activeInteractionDrags.surfaceTrimControlPoint = newValue }
    }

    private var activePolySplineSurfaceVertexSlideDrag: ViewportPolySplineSurfaceVertexSlideDragState? {
        get { activeInteractionDrags.polySplineSurfaceVertexSlide }
        nonmutating set { activeInteractionDrags.polySplineSurfaceVertexSlide = newValue }
    }

    private var activeSurfaceControlPointSlideDrag: ViewportSurfaceControlPointSlideDragState? {
        get { activeInteractionDrags.surfaceControlPointSlide }
        nonmutating set { activeInteractionDrags.surfaceControlPointSlide = newValue }
    }

    private var activeSurfaceFrameDrag: ViewportSurfaceFrameDragState? {
        get { activeInteractionDrags.surfaceFrame }
        nonmutating set { activeInteractionDrags.surfaceFrame = newValue }
    }

    private var activeRegionOffsetDrag: ViewportRegionOffsetDragState? {
        get { activeInteractionDrags.regionOffset }
        nonmutating set { activeInteractionDrags.regionOffset = newValue }
    }

    private var activeEdgeOffsetDrag: ViewportEdgeOffsetDragState? {
        get { activeInteractionDrags.edgeOffset }
        nonmutating set { activeInteractionDrags.edgeOffset = newValue }
    }

    private var activeSlotWidthDrag: ViewportSlotWidthDragState? {
        get { activeInteractionDrags.slotWidth }
        nonmutating set { activeInteractionDrags.slotWidth = newValue }
    }

    private var activeSketchVertexOffsetDrag: ViewportSketchVertexOffsetDragState? {
        get { activeInteractionDrags.sketchVertexOffset }
        nonmutating set { activeInteractionDrags.sketchVertexOffset = newValue }
    }

    private var activePatternArrayLinearAxisDrag: ViewportPatternArrayLinearAxisDragState? {
        get { activeInteractionDrags.patternArrayLinearAxis }
        nonmutating set { activeInteractionDrags.patternArrayLinearAxis = newValue }
    }

    private var activeIndependentCopyExtrudeDistanceDrag: ViewportIndependentCopyExtrudeDistanceDragState? {
        get { activeInteractionDrags.independentCopyExtrudeDistance }
        nonmutating set { activeInteractionDrags.independentCopyExtrudeDistance = newValue }
    }

    private var activeIndependentCopyBodyDimensionDrag: ViewportIndependentCopyBodyDimensionDragState? {
        get { activeInteractionDrags.independentCopyBodyDimension }
        nonmutating set { activeInteractionDrags.independentCopyBodyDimension = newValue }
    }

    private var activePatternArrayRadialAngleDrag: ViewportPatternArrayRadialAngleDragState? {
        get { activeInteractionDrags.patternArrayRadialAngle }
        nonmutating set { activeInteractionDrags.patternArrayRadialAngle = newValue }
    }

    private var activePatternArrayCopyCountDrag: ViewportPatternArrayCopyCountDragState? {
        get { activeInteractionDrags.patternArrayCopyCount }
        nonmutating set { activeInteractionDrags.patternArrayCopyCount = newValue }
    }

    private var activePatternArrayCurveExtentDrag: ViewportPatternArrayCurveExtentDragState? {
        get { activeInteractionDrags.patternArrayCurveExtent }
        nonmutating set { activeInteractionDrags.patternArrayCurveExtent = newValue }
    }

    private var activePatternArrayCurvePathPointDrag: ViewportPatternArrayCurvePathPointDragState? {
        get { activeInteractionDrags.patternArrayCurvePathPoint }
        nonmutating set { activeInteractionDrags.patternArrayCurvePathPoint = newValue }
    }

    private var activeConstructionPlaneHandleDrag: ViewportConstructionPlaneHandleDragState? {
        get { activeInteractionDrags.constructionPlane }
        nonmutating set { activeInteractionDrags.constructionPlane = newValue }
    }

    public init(
        document: DesignDocument,
        sourceIdentity: ViewportSourceIdentity,
        displayMode: ViewportDisplayMode = .solid,
        shading: ViewportShading = .standard,
        controlSession: ViewportControlSession? = nil,
        presentationScene: UniversalViewportScene? = nil,
        presentationSceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID] = [:],
        workspaceRenderState: ViewportWorkspaceRenderState,
        currentEvaluation: DocumentEvaluationContext? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        selection: SelectionModel = .empty,
        objectSelectionIndex: ViewportObjectSelectionIndex,
        selectionDragPreviewTargets: [SelectionTarget] = [],
        presentationPreviewSceneNodeIDs: Set<SceneNodeID> = [],
        patternArrayCurvePathReplacementPreviewRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest? = nil,
        surfaceAnalysis: SurfaceAnalysisResult? = nil,
        surfaceAnalysisOptions: ViewportSurfaceAnalysisOptions = ViewportSurfaceAnalysisOptions(),
        surfaceContinuity: RupaCore.SurfaceContinuityResult? = nil,
        sectionAnalysis: SectionAnalysisResult? = nil,
        sectionClippingPlan: SectionAnalysisClippingPlan? = nil,
        snapResolutionOptions: SnapResolutionOptions? = nil,
        canvasDragPreviewKind: ViewportCanvasDragPreviewKind? = .rectangle(widthMeters: nil, heightMeters: nil),
        canvasPlacementPreviewKind: ViewportCanvasPlacementPreviewKind? = nil,
        canvasDragAxisConstraint: SketchAxisConstraint? = nil,
        canvasDragSketchPlaneOverride: SketchPlane? = nil,
        projectionRequest: ViewportProjectionRequest? = nil,
        cameraFrameRequest: ViewportCameraFrameRequest? = nil,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all,
        bottomChromeReservedHeight: CGFloat = 0.0,
        canvasOverlayExclusions: [ViewportCanvasOverlayExclusion] = [],
        gridVisualSpacingMode: ViewportProjectedGrid.VisualSpacingMode = .adaptive,
        workspaceScalePresetTitle: String? = nil,
        workspaceScalePresetOptions: [WorkspaceScalePresetProfile] = [],
        canFitWorkspaceScaleToModel: Bool = false,
        canSelectSmallerWorkspaceScale: Bool = false,
        canSelectLargerWorkspaceScale: Bool = false,
        cameraResetSignal: Int = 0,
        hoverClearSignal: Int = 0,
        showsConstructionPlaneHover: Bool = false,
        measurementToolActive: Bool = false,
        showsAutomaticMeasurement: Bool = false,
        measurementConstructionPlane: SketchPlane? = nil,
        allowsSelectionRectangle: Bool = false,
        allowsObjectAffordances: Bool = true,
        meshSelectionDomain: GeometryAttributeDomain = .face,
        onMeshElementPick: ((ViewportMeshElementHit?, ViewportSelectionIntent) -> Void)? = nil,
        meshSelectionOverlay: ViewportMeshSelectionOverlay? = nil,
        slotWidthMeters: Double? = nil,
        sketchVertexOffsetDistanceMeters: Double? = nil,
        edgeOffsetDistanceMeters: Double? = nil,
        presentationCADInteractionSceneNodeIDs: Set<SceneNodeID> = [],
        selectedPresentationHasExactCADContext: Bool,
        onPresentationOccurrencePick: ((SceneOccurrenceID, ViewportSelectionIntent) -> Void)? = nil,
        onPresentationOccurrenceHover: ((SceneOccurrenceID?) -> Void)? = nil,
        onPick: ((ViewportCanvasTarget) -> Void)? = nil,
        onCanvasDrag: ((ViewportModelDrag) -> Void)? = nil,
        onShiftScroll: ((ViewportScrollDirection) -> Bool)? = nil,
        onReferenceLineAnchor: ((Point2D) -> Bool)? = nil,
        onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onSelectionDragPreview: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onBodyMoveDrag: ((ViewportBodyMoveDragTarget) -> Void)? = nil,
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
        onConstructionPlaneHandleDrag: ((ViewportConstructionPlaneDragTarget) -> Void)? = nil,
        onCommandConfirm: (() -> Void)? = nil,
        onFitWorkspaceScaleToModel: (() -> Void)? = nil,
        onSelectSmallerWorkspaceScale: (() -> Void)? = nil,
        onSelectLargerWorkspaceScale: (() -> Void)? = nil,
        onSelectWorkspaceScalePreset: ((WorkspaceScalePreset) -> Void)? = nil,
        onHover: ((ViewportHit?) -> Void)? = nil,
        onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)? = nil,
        onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)? = nil,
        onCameraFrameChange: ((ViewportCameraFrame?) -> Void)? = nil,
        onCameraFrameRequestResult: ((UUID, Result<Void, Error>) -> Void)? = nil,
        onProjectedGridStepChange: ((Double) -> Void)? = nil,
        onMeasurementStateChange: ((ViewportMeasurementState) -> Void)? = nil
        ) {
        self.controlSession = controlSession
        self._localControlSession = State(
            initialValue: ViewportControlSession(
                displayMode: displayMode,
                shading: shading
            )
        )
        self._viewportInstanceID = State(
            initialValue: ViewportInstanceID()
        )
        self.document = document
        self.sourceIdentity = sourceIdentity
        self.presentationScene = presentationScene
        self.presentationSceneNodeIDByOccurrenceID = presentationSceneNodeIDByOccurrenceID
        // Resolve document-owned colors once per supplied View value, not from
        // the camera-driven body or the native scene's update callback.
        var materialColors: [SceneOccurrenceID: ColorRGBA] = [:]
        if let presentationScene {
            let library = document.productMetadata.materialLibrary
            for item in presentationScene.items {
                guard let nodeID = presentationSceneNodeIDByOccurrenceID[item.id],
                      let node = document.productMetadata.sceneNodes[nodeID],
                      let materialID = node.materialID ?? library.defaultMaterialID,
                      let color = library.materials[materialID]?.baseColor else { continue }
                materialColors[item.id] = color
            }
        }
        self.materialColors = materialColors
        self.workspaceRenderState = workspaceRenderState
        self.currentEvaluation = currentEvaluation
        self.evaluationCache = evaluationCache
        self.objectRegistry = objectRegistry
        self.renderInvalidation = renderInvalidation
        self.selection = selection
        self.objectSelectionIndex = objectSelectionIndex
        self.selectionDragPreviewTargets = selectionDragPreviewTargets
        self.patternArrayCurvePathReplacementPreviewRequest = patternArrayCurvePathReplacementPreviewRequest
        self.surfaceAnalysis = surfaceAnalysis
        self.surfaceAnalysisOptions = surfaceAnalysisOptions
        self.surfaceContinuity = surfaceContinuity
        self.sectionAnalysis = sectionAnalysis
        self.sectionClippingPlan = sectionClippingPlan
        self.snapResolutionOptions = snapResolutionOptions
        self.canvasDragPreviewKind = canvasDragPreviewKind
        self.canvasPlacementPreviewKind = canvasPlacementPreviewKind
        self.canvasDragAxisConstraint = canvasDragAxisConstraint
        self.canvasDragSketchPlaneOverride = canvasDragSketchPlaneOverride
        self.projectionRequest = projectionRequest
        self.cameraFrameRequest = cameraFrameRequest
        self.selectionHitPolicy = selectionHitPolicy
        self.bottomChromeReservedHeight = max(0.0, bottomChromeReservedHeight)
        self.canvasOverlayExclusions = canvasOverlayExclusions.filter { exclusion in
            exclusion.hasFiniteRect
                && exclusion.rect.isNull == false
                && exclusion.rect.isEmpty == false
        }
        self.gridVisualSpacingMode = gridVisualSpacingMode
        self.workspaceScalePresetTitle = workspaceScalePresetTitle
        self.workspaceScalePresetOptions = workspaceScalePresetOptions
        self.canFitWorkspaceScaleToModel = canFitWorkspaceScaleToModel
        self.canSelectSmallerWorkspaceScale = canSelectSmallerWorkspaceScale
        self.canSelectLargerWorkspaceScale = canSelectLargerWorkspaceScale
        self.cameraResetSignal = cameraResetSignal
        self.hoverClearSignal = hoverClearSignal
        self.showsConstructionPlaneHover = showsConstructionPlaneHover
        self.measurementToolActive = measurementToolActive
        self.showsAutomaticMeasurement = showsAutomaticMeasurement
        self.measurementConstructionPlane = measurementConstructionPlane
        self.allowsSelectionRectangle = allowsSelectionRectangle
        self.allowsObjectAffordances = allowsObjectAffordances
        self.meshSelectionDomain = meshSelectionDomain
        self.meshSelectionOverlay = meshSelectionOverlay
        self.onMeshElementPick = onMeshElementPick
        let interactionScaleDefaults = WorkspaceInteractionScaleDefaults(ruler: workspaceRenderState.ruler)
        self.slotWidthMeters = slotWidthMeters ?? interactionScaleDefaults.slotWidthMeters
        self.sketchVertexOffsetDistanceMeters = sketchVertexOffsetDistanceMeters
            ?? interactionScaleDefaults.operationStepMeters
        self.edgeOffsetDistanceMeters = edgeOffsetDistanceMeters
            ?? interactionScaleDefaults.operationStepMeters
        self.presentationCADInteractionSceneNodeIDs = presentationCADInteractionSceneNodeIDs
        self.onPresentationOccurrencePick = onPresentationOccurrencePick
        self.onPresentationOccurrenceHover = onPresentationOccurrenceHover
        self.onPick = onPick
        self.onCanvasDrag = onCanvasDrag
        self.onShiftScroll = onShiftScroll
        self.onReferenceLineAnchor = onReferenceLineAnchor
        self.onSelectionDrag = onSelectionDrag
        self.onSelectionDragPreview = onSelectionDragPreview
        self.onBodyMoveDrag = onBodyMoveDrag
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
        self.onConstructionPlaneHandleDrag = onConstructionPlaneHandleDrag
        self.onCommandConfirm = onCommandConfirm
        self.onFitWorkspaceScaleToModel = onFitWorkspaceScaleToModel
        self.onSelectSmallerWorkspaceScale = onSelectSmallerWorkspaceScale
        self.onSelectLargerWorkspaceScale = onSelectLargerWorkspaceScale
        self.onSelectWorkspaceScalePreset = onSelectWorkspaceScalePreset
        self.onHover = onHover
        self.onSnapCandidateKindChange = onSnapCandidateKindChange
        self.onProjectionBasisChange = onProjectionBasisChange
        self.onCameraFrameChange = onCameraFrameChange
        self.onCameraFrameRequestResult = onCameraFrameRequestResult
        self.onProjectedGridStepChange = onProjectedGridStepChange
        self.onMeasurementStateChange = onMeasurementStateChange
        self.sceneObjectDefinitions = objectRegistry.orderedDefinitions
        self.presentationInteractionStateResolver = MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: presentationSceneNodeIDByOccurrenceID,
            selectedSceneNodeIDs: objectSelectionIndex.sceneNodeIDs,
            previewSceneNodeIDs: presentationPreviewSceneNodeIDs,
            hoveredSceneNodeID: selection.hoveredSceneNodeID
        )
        self.selectedPresentationHasExactCADContext = presentationScene == nil
            || selectedPresentationHasExactCADContext
    }

    @ViewBuilder
    public var body: some View {
        if let failure = sourceValidationFailure {
            presentationFailureOverlay(error: failure, previewFailureMessage: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(viewportBackground)
        } else {
        // Read in `body` itself so the transient preview evaluation reaching
        // `ready` invalidates this view even when no other state changes.
        let sceneKey = sceneSnapshotKey(usesDragPreviewDocument: true)
        GeometryReader { proxy in
            let timelinePolicy = ViewportTimelineSchedulePolicy(
                projectionTransition: projectionTransition
            )
            TimelineView(.animation(minimumInterval: nil, paused: timelinePolicy.isPaused)) { timeline in
                let basis = projectionBasis(at: timeline.date)
                let fittingChromeLayout = makeFittingChromeLayout(size: proxy.size)
                let sceneContext = makeSceneContext(
                    size: proxy.size,
                    camera: camera,
                    basis: basis,
                    sceneKey: sceneKey,
                    fittingInsets: fittingChromeLayout.fittingInsets
                )
                let controlContextKey = ViewportControlContextKey(
                    viewportID: viewportInstanceID,
                    presentationSnapshotID: presentationScene?.snapshotID,
                    documentGeneration: sceneDocumentGeneration,
                    viewportSize: proxy.size,
                    ruler: workspaceRuler,
                    fittingInsets: fittingChromeLayout.fittingInsets,
                    selectedSceneNodeIDs: selection.selectedSceneNodeIDs
                )
                let preparation = presentationPreparation
                let preparationIdentity: RealityViewportPreparationRequest.Identity? = if case .success(let identity) = preparation { identity } else { nil }
                let presentationSurface = preparationIdentity.flatMap { presentationPlanCache.displaySurface(for: $0) }
                let gridReadout = presentationSurface.flatMap {
                    nativeGridReadout?.rendererID == ObjectIdentifier($0) ? nativeGridReadout?.value : nil
                }
                let chromeLayout = ViewportCanvasChromeLayout(
                    viewportSize: proxy.size,
                    bottomReservedHeight: bottomChromeReservedHeight,
                    additionalExclusions: canvasOverlayExclusions,
                    viewportBadgeWidth: gridReadout.map { estimatedViewportBadgeWidth(scaleReadout: $0) } ?? 0
                )
                // The body only reads the published state. Preparation is
                // started from the scene-identity task below, because starting
                // it here would mutate observable state during a view update.
                let presentationFailure: MeshSourcePresentationRenderError? = switch preparation {
                case .failure(let error): error
                case .success(let identity):
                    presentationPlanCache.failure(for: identity) ?? presentationFrameFailure(for: identity)
                        ?? presentationSurface.flatMap { gridFailure?.rendererID == ObjectIdentifier($0) ? gridFailure?.error : nil }
                }
                ZStack {
                    if let presentationSurface, let preparationIdentity {
                        RealityViewportView(
                            viewport: presentationSurface,
                            viewportRevision: activeControlSession.revision,
                            displayMode: displayMode,
                            shading: shading,
                            materialColors: materialColors,
                            layout: sceneContext.layout,
                            interaction: presentationInteractionStateResolver,
                            sectionPlane: sectionClippingPlan == nil ? nil : sectionAnalysis?.plane,
                            retainedSide: sectionClippingPlan?.retainedSide ?? .front,
                            sectionTolerance: sectionAnalysis?.toleranceMeters ?? 0,
                            excludedRects: chromeLayout.inputExclusionRects,
                            gridRuler: workspaceRuler,
                            gridSpacing: gridVisualSpacingMode,
                            onGridUpdateResult: { error, readout in
                                guard presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                                gridFailure = error.map { (ObjectIdentifier(presentationSurface), $0) }
                                nativeGridReadout = readout.map { (ObjectIdentifier(presentationSurface), $0) }
                            },
                            onUpdateResult: { error in
                                guard presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                                surfaceFailure = error.map { (ObjectIdentifier(presentationSurface), $0) }
                                if error == nil {
                                    resumeNativeAxisFinish()
                                } else if presentationSurface.appliedViewportRevision == nil {
                                    cancelNativeAxisGesture()
                                }
                            }
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(viewportBackground)
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    if let gridReadout {
                        viewportBadgeOverlay(scaleReadout: gridReadout, chromeLayout: chromeLayout)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    presentationFailureOverlay(
                        error: presentationFailure,
                        previewFailureMessage: previewEvaluationCache.failureMessage(for: dragPreviewRevision)
                    )
                }
                .overlay {
                    canvasDragPlaceholderOverlay
                }
                .overlay {
                    selectionAffordanceAccessibilityMarker
                }
                .overlay {
                    constructionPlaneHandleAccessibilityMarkers(layout: sceneContext.layout)
                }
                .overlay {
                    if let gridReadout { gridAccessibilityMarkers(readout: gridReadout) }
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
                        onPan: { delta, size in
                            panCanvas(by: delta, size: size)
                        },
                        onZoom: { factor, anchor, size in
                            zoomCanvas(by: factor, anchor: anchor, size: size)
                        },
                        onOrbit: { delta, size in
                            orbitViewport(by: delta, size: size)
                        },
                        onModifierFlagsChange: { flags, size in
                            modifierFlags = flags
                            refreshSnapOverlayResolution(size: size)
                            refreshPlacementHighlight(size: size)
                        },
                        onSecondaryClick: { _, _ in
                            onCommandConfirm?()
                        },
                        onShiftScroll: { direction in
                            onShiftScroll?(direction) ?? false
                        },
                        onShiftTap: { point, _ in
                            captureReferenceLineAnchor(at: point)
                        },
                        onCancel: {
                            if nativeAxisGesture != nil {
                                clearPendingCanvasInteractionTargets()
                                activeCanvasDrag = nil
                                return true
                            }
                            guard measurementToolActive else { return false }
                            resetMeasurement()
                            return true
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
                        projection: camera.projection,
                        onResetView: {
                            resetViewportCamera(size: proxy.size, basis: basis)
                        },
                        onSelectAxis: { axis in
                            selectProjectionAxis(axis)
                        },
                        onSelectProjection: { projection in
                            do {
                                try activeControlSession.perform(.setProjection(projection))
                            } catch {
                                Logger(subsystem: "RupaRendering", category: "ViewportControlSession")
                                    .error("Viewport projection failed: \(error.localizedDescription, privacy: .public)")
                            }
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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("CanvasViewport")
                .accessibilityLabel("Canvas viewport")
                .task(id: preparation) {
                    guard !Task.isCancelled else { return }
                    surfaceFailure = nil
                    gridFailure = nil
                    guard case .success(let identity) = preparation else {
                        presentationPlanCache.teardown()
                        return
                    }
                    presentationPlanCache.prepare(
                        identity: identity, scene: presentationScene,
                        fallbackOrigin: sceneContext.layout.renderOrigin
                    ) {
                        try makeSpatialOverlaySemanticBuilder(
                            scene: sceneContext.scene,
                            modelBounds: sceneContext.layout.modelBounds,
                            renderOrigin: sceneContext.layout.renderOrigin,
                            topologyRevision: identity.overlayRevision,
                            drawsLegacyBodies: presentationScene == nil
                        )
                    }
                }
                .onChange(of: gridReadout?.minorStep.meters, initial: true) { _, newValue in
                    // Report the resolved visible grid cell (meters). `.onChange` fires only
                    // on an actual value change and runs after the view update, so this never
                    // mutates SwiftUI state mid-update and cannot form a feedback loop.
                    if let newValue { onProjectedGridStepChange?(newValue) }
                }
                .onChange(of: activeControlSession.revision) { _, _ in
                    if case .active(let press) = nativeAxisGesture, let finish = press.finish,
                       finish.revision != activeControlSession.revision {
                        cancelNativeAxisGesture()
                    }
                    // Agent and UI commands share the session. Reflect their applied
                    // state through the existing snapshot callbacks without waiting
                    // for GPU completion or mutating session state during `body`.
                    publishProjectionBasis(activeControlSession.basis)
                    publishCameraFrame(
                        size: proxy.size,
                        basis: currentProjectionBasis
                    )
                }
                .onChange(of: controlContextKey) { _, _ in
                    let context = makeControlMountContext(
                        viewportID: viewportInstanceID,
                        size: proxy.size,
                        sceneContext: sceneContext,
                        fittingInsets: fittingChromeLayout.fittingInsets
                    )
                    activeControlSession.updateContext(context)
                }
                .onChange(of: presentationFailure) { _, _ in
                    if case .failed = presentationPlanCache.state { cancelNativeAxisGesture() }
                }
                .task(id: viewportInstanceID) {
                    let viewportID = viewportInstanceID
                    let context = makeControlMountContext(
                        viewportID: viewportID,
                        size: proxy.size,
                        sceneContext: sceneContext,
                        fittingInsets: fittingChromeLayout.fittingInsets
                    )
                    let mountToken = activeControlSession.mount(viewportID: viewportID)
                    activeControlSession.updateContext(context)
                    if let projectionRequest {
                        applyProjectionRequest(projectionRequest)
                    } else {
                        publishProjectionBasis(currentProjectionBasis)
                    }
                    publishCameraFrame(size: proxy.size, basis: currentProjectionBasis)

                    defer {
                        activeControlSession.unmount(mountToken)
                    }
                    do {
                        try await Task.sleep(nanoseconds: UInt64.max)
                    } catch {
                        // Cancellation is the lifecycle signal; the defer above
                        // releases only this task's mount token.
                    }
                }
            }
            .onChange(of: snapResolutionOptions) { _, _ in
                refreshSnapOverlayResolution(size: proxy.size)
                refreshPlacementHighlight(size: proxy.size)
            }
            .onChange(of: measurementToolActive) { _, isActive in
                cancelNativeAxisGesture()
                if !isActive {
                    resetMeasurement()
                }
            }
            .onChange(of: automaticMeasurementReadout(size: proxy.size), initial: true) { _, summary in
                automaticMeasurementSummary = summary
                publishMeasurementState()
            }
            .onChange(of: measurementConstructionPlane) { _, _ in
                if measurementToolActive {
                    resetMeasurement()
                }
            }
            .onChange(of: presentationScene?.snapshotID) { _, _ in
                cancelNativeAxisGesture()
                resetMeasurement()
            }
            .onChange(of: selection.selectedTargets) { _, _ in
                cancelNativeAxisGesture()
            }
            .onChange(of: selection.selectedReferences) { _, _ in
                cancelNativeAxisGesture()
            }
            .onChange(of: slotWidthMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: edgeOffsetDistanceMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: sketchVertexOffsetDistanceMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: selection.selectedSceneNodeIDs) { _, _ in
                resetMeasurement()
            }
            .onChange(of: canvasPlacementPreviewKind) { _, _ in
                refreshPlacementHighlight(size: proxy.size)
            }
            .onChange(of: cameraResetSignal) { _, _ in
                resetViewportCamera(size: proxy.size, basis: currentProjectionBasis)
            }
            .onChange(of: hoverClearSignal) { _, _ in
                clearCanvasHover()
            }
            .onChange(of: sourceIdentity) { _, _ in
                cancelNativeAxisGesture()
                clearDragPreviewDocument()
                refreshSnapOverlayResolution(size: proxy.size)
                refreshPlacementHighlight(size: proxy.size)
                resetMeasurement()
            }
            .onDisappear {
                clearPendingCanvasInteractionTargets()
                previewEvaluationCache.clear()
                presentationPlanCache.teardown()
                surfaceFailure = nil
                gridFailure = nil
                nativeGridReadout = nil
                resetMeasurement()
            }
            .onChange(of: projectionRequest) { _, nextRequest in
                if let nextRequest {
                    applyProjectionRequest(nextRequest)
                }
            }
            .onChange(of: cameraFrameRequest) { _, nextRequest in
                if let nextRequest {
                    applyCameraFrameRequest(nextRequest, size: proxy.size)
                }
            }
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
                    pick(at: marker.point, size: size, selectionIntent: .replace)
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
                    pick(at: marker.point, size: size, selectionIntent: .replace)
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

    @ViewBuilder private var canvasDragPlaceholderOverlay: some View {
        if let activeCanvasDrag {
            ZStack {
                if case .selection = activeCanvasDrag.kind {
                    Canvas { context, _ in
                        drawSelectionDragRectangle(activeCanvasDrag, in: &context)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

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

    @ViewBuilder private func constructionPlaneHandleAccessibilityMarkers(
        layout: ViewportLayout
    ) -> some View {
        if onConstructionPlaneHandleDrag != nil {
            let targets = ViewportConstructionPlaneHandleGeometry().targets(
                document: document,
                ruler: workspaceRuler,
                selection: selection,
                layout: layout
            )
            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                let point = constructionPlaneHandleMarkerPoint(target)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 24.0, height: 24.0)
                    .position(point)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(
                        "CanvasConstructionPlaneHandle.\(target.handle.rawValue)"
                    )
                    .accessibilityLabel(constructionPlaneHandleAccessibilityLabel(target))
                    .accessibilityValue(constructionPlaneHandleAccessibilityValue(target))
                    .allowsHitTesting(false)
            }
        }
    }

    private func constructionPlaneHandleMarkerPoint(
        _ target: ViewportConstructionPlaneHandleTarget
    ) -> CGPoint {
        switch target.handle {
        case .origin:
            return target.projectedOrigin
        case .normal:
            return target.projectedNormalEnd
        }
    }

    private func constructionPlaneHandleAccessibilityLabel(
        _ target: ViewportConstructionPlaneHandleTarget
    ) -> String {
        switch target.handle {
        case .origin:
            return "Construction plane origin handle"
        case .normal:
            return "Construction plane normal handle"
        }
    }

    private func constructionPlaneHandleAccessibilityValue(
        _ target: ViewportConstructionPlaneHandleTarget
    ) -> String {
        switch target.handle {
        case .origin:
            return [
                "x \(accessibilityNumber(target.origin.x))",
                "y \(accessibilityNumber(target.origin.y))",
                "z \(accessibilityNumber(target.origin.z))",
            ].joined(separator: ", ")
        case .normal:
            return [
                "x \(accessibilityNumber(target.normal.x))",
                "y \(accessibilityNumber(target.normal.y))",
                "z \(accessibilityNumber(target.normal.z))",
            ].joined(separator: ", ")
        }
    }

    private func accessibilityNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }

    private var hasSelectedAffordance: Bool {
        allowsObjectAffordances && !selectedObjectFeatureIDs().isEmpty
    }

    private func viewportBadge(
        scaleReadout: ViewportProjectedGrid.ScaleReadout
    ) -> some View {
        let menuState = ViewportCanvasScaleMenuState(
            scaleReadout: scaleReadout,
            presetTitle: workspaceScalePresetTitle,
            selectedPreset: WorkspaceScalePreset.matching(
                workspaceRuler
            ),
            presetProfiles: workspaceScalePresetOptions,
            canFitWorkspaceScaleToModel: canFitWorkspaceScaleToModel
                && onFitWorkspaceScaleToModel != nil,
            canSelectSmallerWorkspaceScale: canSelectSmallerWorkspaceScale
                && onSelectSmallerWorkspaceScale != nil,
            canSelectLargerWorkspaceScale: canSelectLargerWorkspaceScale
                && onSelectLargerWorkspaceScale != nil
        )

        return ViewportCanvasScaleHUD(
            scaleReadout: scaleReadout,
            zoomPercentageText: viewportZoomPercentageText,
            menuState: menuState,
            onSelectPreset: onSelectWorkspaceScalePreset,
            onAction: performViewportBadgeAction
        )
    }

    private func viewportBadgeOverlay(
        scaleReadout: ViewportProjectedGrid.ScaleReadout,
        chromeLayout: ViewportCanvasChromeLayout
    ) -> some View {
        let rect = chromeLayout.viewportBadgeRect
        return viewportBadge(scaleReadout: scaleReadout)
            .frame(
                width: rect.width,
                height: rect.height,
                alignment: .leading
            )
            .offset(x: rect.minX, y: rect.minY)
            .zIndex(2.0)
            .onHover { isHovered in
                if isHovered {
                    clearCanvasHover()
                }
            }
    }

    private func estimatedViewportBadgeWidth(
        scaleReadout: ViewportProjectedGrid.ScaleReadout
    ) -> CGFloat {
        ViewportCanvasScaleHUD.estimatedWidth(
            scaleReadout: scaleReadout,
            zoomPercentageText: viewportZoomPercentageText
        )
    }

    private var viewportZoomPercentageText: String {
        "\(Int((camera.zoom * 100.0).rounded()))%"
    }

    private func performViewportBadgeAction(
        _ action: ViewportCanvasScaleMenuState.Action
    ) {
        switch action {
        case .fitToModel:
            onFitWorkspaceScaleToModel?()
        case .smallerPreset:
            onSelectSmallerWorkspaceScale?()
        case .largerPreset:
            onSelectLargerWorkspaceScale?()
        }
    }

    private var currentProjectionBasis: ViewportProjectionBasis {
        projectionBasis(at: Date())
    }

    private func setCamera(
        _ nextCamera: ViewportCamera,
        basis: ViewportProjectionBasis? = nil
    ) {
        do {
            try activeControlSession.applyPresentationState(
                camera: nextCamera,
                basis: basis ?? currentProjectionBasis
            )
        } catch {
            Logger(
                subsystem: "RupaRendering",
                category: "ViewportControlSession"
            ).error("Viewport camera mutation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishProjectionBasis(_ basis: ViewportProjectionBasis) {
        onProjectionBasisChange?(basis)
    }

    private func publishCameraFrame(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) {
        let resolver = ViewportCameraFrameResolver(
            workspaceVisibleSpanMeters: workspaceRuler.visibleSpanMeters
        )
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: basis
        )
        onCameraFrameChange?(resolver.frame(for: camera, in: layout))
    }

    private func projectionBasis(at date: Date) -> ViewportProjectionBasis {
        guard let projectionTransition else {
            if let orbitBasis {
                return orbitBasis
            }
            if selectedAxis == nil {
                return activeControlSession.basis
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

    private func applyCameraFrameRequest(
        _ request: ViewportCameraFrameRequest,
        size: CGSize
    ) {
        let resolver = ViewportCameraFrameResolver(
            workspaceVisibleSpanMeters: workspaceRuler.visibleSpanMeters
        )
        let nextCamera: ViewportCamera
        do {
            nextCamera = try resolver.camera(framing: request) { frameCamera in
                makeLayout(size: size, camera: frameCamera, basis: request.basis)
            }
            try activeControlSession.applyPresentationState(camera: nextCamera, basis: request.basis)
        } catch {
            Logger(subsystem: "RupaRendering", category: "ViewportControlSession")
                .error("Camera framing failed: \(error.localizedDescription, privacy: .public)")
            onCameraFrameRequestResult?(request.id, .failure(error))
            return
        }
        activeCanvasDrag = nil
        clearCanvasHover()
        publishProjectionBasis(request.basis)
        publishCameraFrame(size: size, basis: request.basis)
        onCameraFrameRequestResult?(request.id, .success(()))
    }

    /// A preview document is projected only together with its own evaluation.
    /// While that evaluation is preparing or has failed, the viewport keeps
    /// projecting the published document and its published evaluation.
    private var rendersDragPreviewDocument: Bool {
        dragPreviewDocument != nil
            && sceneDocumentGeneration != nil
            && previewEvaluationCache.isReady(for: dragPreviewRevision)
    }

    private var publishedEvaluatedDocument: EvaluatedDocument? {
        currentEvaluation?.evaluatedDocument ?? evaluationCache?.evaluatedDocument
    }

    private var renderingDocument: DesignDocument {
        rendersDragPreviewDocument ? (dragPreviewDocument ?? document) : document
    }

    private var renderingCurrentEvaluation: DocumentEvaluationContext? {
        rendersDragPreviewDocument ? nil : currentEvaluation
    }

    private var renderingEvaluationCache: EvaluatedDocumentCache? {
        guard rendersDragPreviewDocument else {
            return evaluationCache
        }
        return previewEvaluationCache.readyCache(for: dragPreviewRevision)
    }

    /// Scene construction may evaluate on this thread only for the published
    /// document, which already carries a published evaluation. A projected
    /// preview supplies its own evaluation and never evaluates here.
    private func sceneEvaluationPolicy(
        usesDragPreviewDocument: Bool
    ) -> ViewportSceneEvaluationPolicy {
        presentationScene != nil || (usesDragPreviewDocument && rendersDragPreviewDocument)
            ? .suppliedOnly : .evaluateOnDemand
    }

    private func sceneDocument(usesDragPreviewDocument: Bool) -> DesignDocument {
        usesDragPreviewDocument ? renderingDocument : document
    }

    /// A preview document is derived from the published document and evaluated
    /// under the published generation, so both scenes carry that one generation.
    /// This is what lets a supplied preview evaluation match its document.
    private var sceneDocumentGeneration: DocumentGeneration? {
        switch sourceIdentity {
        case .document(_, let generation):
            generation
        case .presentation:
            nil
        }
    }

    private func sceneCurrentEvaluation(
        usesDragPreviewDocument: Bool
    ) -> DocumentEvaluationContext? {
        usesDragPreviewDocument ? renderingCurrentEvaluation : currentEvaluation
    }

    private func sceneEvaluationCache(
        usesDragPreviewDocument: Bool
    ) -> EvaluatedDocumentCache? {
        usesDragPreviewDocument ? renderingEvaluationCache : evaluationCache
    }

    private func makeScene() -> ViewportScene {
        cachedScene(usesDragPreviewDocument: true)
    }

    private func makeSceneContext(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis,
        usesDragPreviewDocument: Bool = true,
        sceneKey: ViewportSceneSnapshotKey? = nil,
        fittingInsets: ViewportLayout.FittingInsets? = nil
    ) -> ViewportSceneContext {
        let scene = cachedScene(
            usesDragPreviewDocument: usesDragPreviewDocument,
            sceneKey: sceneKey
        )
        let geometryBoundsSource: ViewportGeometryBoundsSource
        if let presentationScene {
            geometryBoundsSource = .geometry(presentationScene.worldBounds)
        } else {
            geometryBoundsSource = .scene
        }
        return ViewportSceneContext(
            ruler: workspaceRuler,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis,
            geometryBoundsSource: geometryBoundsSource,
            fittingInsets: fittingInsets ?? viewportLayoutFittingInsets(size: size)
        )
    }

    private func makeControlMountContext(
        viewportID: ViewportInstanceID,
        size: CGSize,
        sceneContext: ViewportSceneContext,
        fittingInsets: ViewportLayout.FittingInsets
    ) -> ViewportControlMountContext {
        let sceneBounds: GeometryBounds3D?
        let selectedBounds: GeometryBounds3D?
        if let presentationScene {
            sceneBounds = presentationScene.worldBounds
            let selectedSceneNodeIDs = Set(selection.selectedSceneNodeIDs)
            let selectedItems = presentationScene.items.filter { item in
                guard let sceneNodeID = presentationSceneNodeIDByOccurrenceID[item.id] else {
                    return false
                }
                return selectedSceneNodeIDs.contains(sceneNodeID)
            }
            selectedBounds = aggregateControlBounds(selectedItems.map(\.worldBounds))
        } else {
            sceneBounds = controlBounds(for: sceneContext.scene)
            selectedBounds = nil
        }
        let verticalBounds: ClosedRange<Double>?
        if let presentationBounds = presentationScene?.worldBounds {
            verticalBounds = presentationBounds.minimum.y ... presentationBounds.maximum.y
        } else {
            verticalBounds = sceneContext.scene.verticalBounds
        }
        return ViewportControlMountContext(
            viewportID: viewportID,
            viewportSize: size,
            fittingInsets: fittingInsets,
            modelBounds: sceneContext.layout.modelBounds,
            verticalBounds: verticalBounds,
            ruler: workspaceRuler,
            sceneBounds: sceneBounds,
            selectedBounds: selectedBounds
        )
    }

    private func controlBounds(for scene: ViewportScene) -> GeometryBounds3D? {
        guard let modelBounds = scene.modelBounds,
              let verticalBounds = scene.verticalBounds else {
            return nil
        }
        do {
            return try GeometryBounds3D(
                minimum: GeometryPoint3D(
                    x: Double(modelBounds.minX),
                    y: verticalBounds.lowerBound,
                    z: Double(modelBounds.minY)
                ),
                maximum: GeometryPoint3D(
                    x: Double(modelBounds.maxX),
                    y: verticalBounds.upperBound,
                    z: Double(modelBounds.maxY)
                )
            )
        } catch {
            return nil
        }
    }

    private func aggregateControlBounds(
        _ bounds: [GeometryBounds3D]
    ) -> GeometryBounds3D? {
        guard let first = bounds.first else {
            return nil
        }
        var minimum = first.minimum
        var maximum = first.maximum
        for bound in bounds.dropFirst() {
            minimum.x = min(minimum.x, bound.minimum.x)
            minimum.y = min(minimum.y, bound.minimum.y)
            minimum.z = min(minimum.z, bound.minimum.z)
            maximum.x = max(maximum.x, bound.maximum.x)
            maximum.y = max(maximum.y, bound.maximum.y)
            maximum.z = max(maximum.z, bound.maximum.z)
        }
        do {
            return try GeometryBounds3D(minimum: minimum, maximum: maximum)
        } catch {
            return nil
        }
    }

    private func cachedScene(
        usesDragPreviewDocument: Bool,
        sceneKey: ViewportSceneSnapshotKey? = nil
    ) -> ViewportScene {
        sceneSnapshotCache.scene(
            for: sceneKey ?? sceneSnapshotKey(
                usesDragPreviewDocument: usesDragPreviewDocument
            )
        ) {
            buildScene(usesDragPreviewDocument: usesDragPreviewDocument)
        }
    }

    private func buildScene(usesDragPreviewDocument: Bool) -> ViewportScene {
        sceneApplyingSectionClipping(
            cachedBaseScene(usesDragPreviewDocument: usesDragPreviewDocument)
        )
    }

    private func cachedBaseScene(usesDragPreviewDocument: Bool) -> ViewportScene {
        baseSceneSnapshotCache.scene(
            for: sceneSnapshotKey(usesDragPreviewDocument: usesDragPreviewDocument)
        ) {
            ViewportSceneBuilder(objectRegistry: objectRegistry).build(
                document: sceneDocument(usesDragPreviewDocument: usesDragPreviewDocument),
                ruler: workspaceRuler,
                overlayState: sceneOverlayState,
                currentEvaluation: sceneCurrentEvaluation(usesDragPreviewDocument: usesDragPreviewDocument),
                documentGeneration: sceneDocumentGeneration,
                evaluationCache: sceneEvaluationCache(usesDragPreviewDocument: usesDragPreviewDocument),
                evaluationPolicy: sceneEvaluationPolicy(usesDragPreviewDocument: usesDragPreviewDocument)
            )
        }
    }

    private func sceneSnapshotKey(
        usesDragPreviewDocument: Bool
    ) -> ViewportSceneSnapshotKey {
        let source: ViewportSceneSnapshotKey.Source
        if usesDragPreviewDocument,
           rendersDragPreviewDocument {
            source = .dragPreview(
                documentID: sceneDocument(usesDragPreviewDocument: true).id,
                revision: dragPreviewRevision
            )
        } else {
            switch sourceIdentity {
            case .document(let id, let generation):
                source = .document(id: id, generation: generation)
            case .presentation(let snapshotID):
                source = .presentation(snapshotID)
            }
        }

        return ViewportSceneSnapshotKey(
            source: source,
            currentEvaluationGeneration: sceneCurrentEvaluation(
                usesDragPreviewDocument: usesDragPreviewDocument
            )?.generation,
            evaluationCacheGeneration: sceneEvaluationCache(
                usesDragPreviewDocument: usesDragPreviewDocument
            )?.generation,
            workspaceRenderState: workspaceRenderState,
            renderInvalidation: renderInvalidation,
            sectionClippingPlan: sectionClippingPlan,
            objectDefinitions: sceneObjectDefinitions
        )
    }

    func makeSpatialOverlayChangeKey() throws -> ViewportSpatialOverlayChangeKey {
        var key = ViewportSpatialOverlayChangeKey()
        key.selection = selection
        key.selectionPreview = selectionDragPreviewTargets
        key.meshSelection = meshSelectionOverlay
        key.editedBodies = editedBodies
        key.activeDrags = activeInteractionDrags
        key.hoveredHandle = try hoveredSpatialHandleIdentity
        key.pendingHandle = try pendingSpatialHandleIdentity
        if case .active(let press) = nativeAxisGesture { key.nativeAxisValue = press.value }
        key.hoveredHit = showsConstructionHighlight ? hoveredCanvasHit : nil
        if let drag = activeCanvasDrag, case .creation(let kind) = drag.kind {
            key.creation = .init(kind: kind, drag: drag.modelDrag, plane: drag.sketchPlane)
        }
        key.hasCanvasDrag = activeCanvasDrag != nil
        key.modifierControl = modifierFlags.containsControl
        key.patternReplacement = patternArrayCurvePathReplacementPreviewRequest
        key.surfaceAnalysis = surfaceAnalysis
        key.surfaceAnalysisOptions = surfaceAnalysisOptions
        key.surfaceContinuity = surfaceContinuity
        key.sectionAnalysis = sectionAnalysis
        key.snap = snapOverlayResult
        key.snapOptions = snapResolutionOptions
        key.placement = placementHighlightState
        key.measurement = measurementSession.state
        key.measurementToolActive = measurementToolActive
        key.showsAutomaticMeasurement = showsAutomaticMeasurement
        key.measurementPlane = measurementConstructionPlane
        key.displayUnit = workspaceRuler.displayUnit
        key.axisConstraint = canvasDragAxisConstraint
        key.allowsObjectAffordances = allowsObjectAffordances
        key.showsConstructionPlaneHover = showsConstructionPlaneHover
        key.slotWidthMeters = slotWidthMeters
        key.sketchVertexOffsetDistanceMeters = sketchVertexOffsetDistanceMeters
        key.edgeOffsetDistanceMeters = edgeOffsetDistanceMeters
        // Fixed route bits avoid an array allocation on every camera frame.
        if onRegionOffsetDrag != nil { key.availableRoutes |= 1 << 0 }
        if onEdgeOffsetDrag != nil { key.availableRoutes |= 1 << 1 }
        if onSlotWidthDrag != nil { key.availableRoutes |= 1 << 2 }
        if onSketchVertexOffsetDrag != nil { key.availableRoutes |= 1 << 3 }
        if onSplineControlPointSlideDrag != nil { key.availableRoutes |= 1 << 4 }
        if onPolySplineSurfaceVertexDrag != nil { key.availableRoutes |= 1 << 5 }
        if onSurfaceControlPointDrag != nil { key.availableRoutes |= 1 << 6 }
        if onSurfaceTrimEndpointDrag != nil { key.availableRoutes |= 1 << 7 }
        if onSurfaceTrimControlPointDrag != nil { key.availableRoutes |= 1 << 8 }
        if onPolySplineSurfaceVertexSlideDrag != nil { key.availableRoutes |= 1 << 9 }
        if onSurfaceControlPointSlideDrag != nil { key.availableRoutes |= 1 << 10 }
        if onSurfaceFrameDrag != nil { key.availableRoutes |= 1 << 11 }
        if onConstructionPlaneHandleDrag != nil { key.availableRoutes |= 1 << 12 }
        if onEdgeFilletDrag != nil { key.availableRoutes |= 1 << 13 }
        if onPatternArrayLinearAxisDrag != nil { key.availableRoutes |= 1 << 14 }
        if onIndependentCopyExtrudeDistanceDrag != nil { key.availableRoutes |= 1 << 15 }
        if onIndependentCopyBodyDimensionDrag != nil { key.availableRoutes |= 1 << 16 }
        if onPatternArrayRadialAngleDrag != nil { key.availableRoutes |= 1 << 17 }
        if onPatternArrayCopyCountDrag != nil { key.availableRoutes |= 1 << 18 }
        if onPatternArrayCurveExtentDrag != nil { key.availableRoutes |= 1 << 19 }
        if onPatternArrayCurvePathPointDrag != nil { key.availableRoutes |= 1 << 20 }
        if onPatternArrayOutputModeChange != nil { key.availableRoutes |= 1 << 21 }
        return key
    }

    var sourceValidationFailure: MeshSourcePresentationRenderError? {
        do {
            try sourceIdentity.validate(document: document, presentationScene: presentationScene)
            return nil
        } catch {
            return (error as? MeshSourcePresentationRenderError)
                ?? .init(code: .failed, message: error.localizedDescription)
        }
    }

    private var presentationPreparation: Result<RealityViewportPreparationRequest.Identity, MeshSourcePresentationRenderError> {
        do {
            try sourceIdentity.validate(document: document, presentationScene: presentationScene)
            let revision = try overlayRevision.revision(for: makeSpatialOverlayChangeKey())
            return .success(.init(
                scene: sceneSnapshotKey(usesDragPreviewDocument: true),
                snapshotID: presentationScene?.snapshotID,
                overlayRevision: revision
            ))
        } catch {
            return .failure((error as? MeshSourcePresentationRenderError)
                ?? .init(code: .failed, message: error.localizedDescription))
        }
    }

    private func sceneApplyingSectionClipping(_ scene: ViewportScene) -> ViewportScene {
        guard let sectionClippingPlan else {
            return scene
        }
        return ViewportSectionClippingPlan(
            sectionPlan: sectionClippingPlan,
            scene: scene
        )
        .renderedScene(from: scene)
    }

    private func makeCoordinateMapper(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis,
        usesDragPreviewDocument: Bool = true,
        fittingInsets: ViewportLayout.FittingInsets? = nil
    ) -> ViewportModelCoordinateMapper {
        makeSceneContext(
            size: size,
            camera: camera,
            basis: basis,
            usesDragPreviewDocument: usesDragPreviewDocument,
            fittingInsets: fittingInsets ?? viewportLayoutFittingInsets(size: size)
        ).mapper
    }

    private func makeLayout(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis,
        usesDragPreviewDocument: Bool = true,
        fittingInsets: ViewportLayout.FittingInsets? = nil
    ) -> ViewportLayout {
        makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: basis,
            usesDragPreviewDocument: usesDragPreviewDocument,
            fittingInsets: fittingInsets
        ).layout
    }

    private func viewportLayoutFittingInsets(size: CGSize) -> ViewportLayout.FittingInsets {
        makeFittingChromeLayout(size: size).fittingInsets
    }

    private func makeFittingChromeLayout(size: CGSize) -> ViewportCanvasChromeLayout {
        ViewportCanvasChromeLayout(
            viewportSize: size,
            bottomReservedHeight: bottomChromeReservedHeight,
            additionalExclusions: canvasOverlayExclusions,
            viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
        )
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
        guard layout.scale.isFinite, layout.scale > 0 else { return }
        let extent = Double(hypot(size.width, size.height) * 1.1 / layout.scale)
            + max(abs(layout.renderOrigin.x), abs(layout.renderOrigin.z))
        for axis in [ViewportCoordinateAxis.x, .z] {
            let start = axis == .x ? Point3D(x: -extent, y: 0, z: 0) : Point3D(x: 0, y: 0, z: -extent)
            let end = axis == .x ? Point3D(x: extent, y: 0, z: 0) : Point3D(x: 0, y: 0, z: extent)
            context.stroke(projectedPath([start, end], layout: layout), with: .color(axis.color.opacity(0.46)), lineWidth: 1.5)
            if let labelPoint = layout.projectedPoint(end)?.point {
                drawAxisLabel(axis.label, at: CGPoint(x: labelPoint.x + 12, y: labelPoint.y - 8), color: axis.color, in: &context)
            }
        }
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


    private func presentationSectionGeometryResolver(
        sceneKey: ViewportSceneSnapshotKey? = nil
    ) -> MeshSourcePresentationSectionGeometryResolver? {
        guard let presentationScene,
              let sectionClippingPlan else {
            presentationSectionGeometryCache.invalidate()
            return nil
        }
        let sceneKey = sceneKey ?? sceneSnapshotKey(usesDragPreviewDocument: true)
        let cacheKey = MeshSourcePresentationSectionGeometryCache.Key(
            presentationSnapshotID: presentationScene.snapshotID,
            sceneSnapshotKey: sceneKey,
            plane: sectionAnalysis?.plane,
            toleranceMeters: sectionAnalysis?.toleranceMeters
        )
        return presentationSectionGeometryCache.resolver(for: cacheKey) {
            MeshSourcePresentationSectionGeometryResolver(
                sectionPlan: sectionClippingPlan,
                plane: sectionAnalysis?.plane,
                toleranceMeters: sectionAnalysis?.toleranceMeters
            )
        }
    }

    private func presentationSurfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        try presentationPlanCache.surfaceHit(
            at: point,
            for: presentationQueryIdentity(),
            revision: activeControlSession.revision
        )
    }

    private func presentationQueryIdentity() throws -> RealityViewportPreparationRequest.Identity {
        let identity = try presentationPreparation.get()
        guard identity.snapshotID == presentationScene?.snapshotID else {
            throw MeshSourcePresentationRenderError(code: .failed, message: "The surface query belongs to a different presentation snapshot.")
        }
        if let failure = presentationFrameFailure(for: identity) { throw failure }
        return identity
    }

    private func presentationOccurrenceIDs(
        intersecting rect: CGRect,
        layout: ViewportLayout
    ) -> [SceneOccurrenceID] {
        guard let presentationScene else {
            return []
        }
        guard let plan = currentPresentationPlan(for: presentationScene) else {
            return []
        }
        return MeshSourcePresentationScreenHitTester().occurrenceIDs(
            intersecting: rect,
            in: plan,
            layout: layout,
            sectionGeometryResolver: presentationSectionGeometryResolver(),
            cullBackFaces: isBackfaceCullingActive
        )
    }

    private func presentationFilteredLegacyHit(
        _ hit: ViewportHit?,
        presentationOccurrenceID: SceneOccurrenceID?
    ) -> ViewportHit? {
        guard presentationScene != nil else {
            return hit
        }
        return MeshSourcePresentationLegacyHitFilter().hit(
            hit,
            presentationOccurrenceID: presentationOccurrenceID,
            navigation: presentationSceneNodeIDByOccurrenceID,
            exactCADSceneNodeIDs: presentationCADInteractionSceneNodeIDs
        )
    }

    private func presentationFrameFailure(
        for identity: RealityViewportPreparationRequest.Identity
    ) -> MeshSourcePresentationRenderError? {
        guard let renderer = presentationPlanCache.surface(for: identity),
              surfaceFailure?.rendererID == ObjectIdentifier(renderer) else { return nil }
        return surfaceFailure?.error
    }

    private func currentPresentationPlan(for scene: UniversalViewportScene) -> MeshSourcePresentationRenderPlan? {
        guard case .success(let identity) = presentationPreparation,
              scene.snapshotID == identity.snapshotID,
              presentationPlanCache.surface(for: identity) != nil,
              presentationFrameFailure(for: identity) == nil else { return nil }
        return presentationPlanCache.plan(for: scene)
    }

    private var activeMeasurementPlane: SketchPlane? {
        measurementConstructionPlane ?? snapResolutionOptions?.constructionPlane
    }

    private func resetMeasurement() {
        guard measurementSession.state != ViewportMeasurementState() else {
            return
        }
        measurementSession.reset()
        publishMeasurementState()
    }

    private func publishMeasurementState() {
        var state = measurementSession.state
        state.boundsSummary = automaticMeasurementSummary
        onMeasurementStateChange?(state)
    }

    private func measurementEndpoint(
        at point: CGPoint
    ) -> ViewportMeasurementResolution {
        do {
            let identity = try presentationQueryIdentity()
            let revision = activeControlSession.revision
            let presentationHit = try presentationPlanCache.surfaceHit(
                at: point, for: identity, revision: revision
            ).map {
                ViewportMeasurementPresentationHit(point: $0.point, occurrenceID: $0.triangle.occurrenceID)
            }
            let effectivePlane = activeMeasurementPlane
            // Snap and plane fallback consume the same native intersection.
            // A plane failure does not invalidate a valid surface hit.
            let planeInput: Result<(world: Point3D, local: Point2D), Error>? = effectivePlane.map { plane in
                Result {
                    let coordinates = try SketchPlaneCoordinateSystem(plane: plane)
                    let world = try presentationPlanCache.worldPlaneIntersection(
                        at: point, planeOrigin: coordinates.origin, planeNormal: coordinates.normal,
                        for: identity, revision: revision
                    )
                    _ = try presentationPlanCache.projectWithinDepthRange(
                        world, for: identity, revision: revision
                    )
                    return (world, coordinates.project(world).point)
                }
            }
            let snapQuery: ViewportSnapQuery?
            if case .success(let input)? = planeInput {
                snapQuery = ViewportSnapQuery(point: input.local)
            } else {
                snapQuery = nil
            }
            let snap = ViewportSnapResolutionService().resolution(
                for: snapQuery, document: document, ruler: workspaceRuler,
                options: snapResolutionOptions, modifierFlags: modifierFlags
            )
            return ViewportMeasurementResolver().resolve(
                effectivePlane: effectivePlane, snap: snap, presentationHit: presentationHit,
                planeIntersection: { _ in
                    guard let planeInput else {
                        throw ViewportMeasurementResolutionFailure.noConstructionPlane
                    }
                    return try planeInput.get().world
                },
                validateWorldPoint: { world in
                    _ = try presentationPlanCache.projectWithinDepthRange(
                        world, for: identity, revision: revision
                    )
                }
            )
        } catch {
            return ViewportMeasurementResolution(
                endpoint: nil, failure: .presentationUnavailable(error.localizedDescription)
            )
        }
    }

    private func handleMeasurementClick(
        at point: CGPoint
    ) {
        let resolution = measurementEndpoint(at: point)
        if let endpoint = resolution.endpoint {
            measurementSession.click(endpoint)
        } else {
            measurementSession.refuse(
                resolution.failure ?? .viewRayUnavailable
            )
        }
        measurementSession.warn(resolution.warning)
        publishMeasurementState()
    }

    private func handleMeasurementHover(
        at point: CGPoint
    ) {
        guard measurementSession.state.phase == .anchored else {
            return
        }
        let resolution = measurementEndpoint(at: point)
        measurementSession.hover(resolution.endpoint)
        if resolution.endpoint == nil {
            measurementSession.refuse(
                resolution.failure ?? .viewRayUnavailable
            )
        }
        measurementSession.warn(resolution.warning)
        publishMeasurementState()
    }

    private func automaticMeasurementReadout(size: CGSize) -> String? {
        guard showsAutomaticMeasurement, activeCanvasDrag == nil, pendingInteractionTarget == nil,
              nativeAxisGesture == nil,
              let occurrence = selectedMeasurementOccurrence() else { return nil }
        let layout = makeSceneContext(size: size, camera: camera, basis: currentProjectionBasis).layout
        let chrome = ViewportCanvasChromeLayout(
            viewportSize: size, bottomReservedHeight: bottomChromeReservedHeight,
            additionalExclusions: canvasOverlayExclusions,
            viewportBadgeWidth: nativeGridReadout.map { estimatedViewportBadgeWidth(scaleReadout: $0.value) } ?? 0
        )
        let rulers = ViewportMeasurementBoundsRulerLayout().rulers(
            for: occurrence.worldBounds, layout: layout, displayUnit: workspaceRuler.displayUnit,
            safeRect: layout.fittingInsets.fittingRect(in: size), excludedRects: chrome.inputExclusionRects
        )
        let bounds = occurrence.worldBounds
        let values: [(ViewportMeasurementRulerAxis, Double)] = [
            (.x, bounds.maximum.x - bounds.minimum.x),
            (.y, bounds.maximum.y - bounds.minimum.y),
            (.z, bounds.maximum.z - bounds.minimum.z)
        ]
        return "World bounds: " + values.map { axis, value in
            let omitted = value > 0 && !rulers.contains(where: { $0.axis == axis })
            return "\(axis.title) \(formattedViewportLength(value))\(omitted ? " (ruler hidden)" : "")"
        }.joined(separator: " · ")
    }

    @ViewBuilder
    private func presentationFailureOverlay(
        error: MeshSourcePresentationRenderError?,
        previewFailureMessage: String?
    ) -> some View {
        if let message = error?.localizedDescription ?? previewFailureMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.red)
                .padding(8.0)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8.0))
                .padding(12.0)
                .accessibilityIdentifier(error == nil ? "CanvasPreviewFailure" : "CanvasPresentationFailure")
                .accessibilityLabel(error == nil ? "Preview geometry unavailable" : "Presentation geometry unavailable")
                .accessibilityValue(message)
                .allowsHitTesting(false)
        }
    }

    private func point3D(_ point: GeometryPoint3D) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func drawModel(
        in context: inout GraphicsContext,
        sceneContext: ViewportSceneContext,
        chromeLayout: ViewportCanvasChromeLayout,
        placementCellSideMeters: Double,
        drawsLegacyBodies: Bool
    ) {
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
        let selectedBodyItems = selectedBodyItems(in: scene)
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
        let constructionHit = showsConstructionHighlight ? hoveredCanvasHit : nil
        let sectionDisplayPlan = sectionClippingPlan.map {
            ViewportSectionClippingPlan(
                sectionPlan: $0,
                scene: scene
            )
        }

        if constructionHit?.bodyFace == nil,
           constructionHit?.bodyEdge == nil,
           constructionHit?.bodyVertex == nil,
           canvasPlacementPreviewKind != nil,
           let placementHighlight = placementHighlightState {
            drawPlacementHighlight(
                placementHighlight,
                visibleCellMeters: placementCellSideMeters,
                in: &context,
                layout: layout
            )
        }

        if drawsLegacyBodies || rendersDragPreviewDocument || editedBodies.isEmpty == false {
            for item in scene.items {
                if case .body = item.kind,
                   drawsLegacyBodies || Self.drawsTransientBody(
                    sceneNodeID: item.sceneNodeID,
                    previewSceneNodeID: rendersDragPreviewDocument ? dragPreviewSceneNodeID : nil,
                    isEdited: editedBodies[item.featureID] != nil
                   ) {
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
                            || item.sceneNodeID.map(previewObjectSceneNodeIDs.contains) == true,
                        sectionAction: sectionDisplayPlan?.action(forSceneItemID: item.id)
                    )
                }
            }
        }

        for item in scene.items {
            if case .curve = item.kind {
                drawCurve(
                    item,
                    in: &context,
                    layout: layout,
                    isSelected: isObjectItem(
                        item,
                        selectedByFeatureIDs: selectedObjectFeatureIDs,
                        selectedBySceneNodeIDs: selectedObjectSceneNodeIDs
                    ),
                    isHovered: hoveredFeatureIDs.contains(item.featureID)
                        || item.sceneNodeID.map(hoveredSceneNodeIDs.contains) == true
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

        if let overlay = meshSelectionOverlay, overlay.snapshotID == presentationScene?.snapshotID {
            var outline = Path()
            for segment in overlay.boundarySegments {
                outline.addPath(projectedPath([
                    Point3D(x: segment.start.x, y: segment.start.y, z: segment.start.z),
                    Point3D(x: segment.end.x, y: segment.end.y, z: segment.end.z),
                ], layout: layout))
            }
            context.stroke(outline, with: .color(.orange), lineWidth: 2)
            var vertices = Path()
            for point in overlay.points {
                guard let location = layout.projectedPoint(Point3D(
                    x: point.position.x, y: point.position.y, z: point.position.z
                ))?.point else { continue }
                vertices.addEllipse(in: CGRect(x: location.x - 4, y: location.y - 4, width: 8, height: 8))
            }
            context.fill(vertices, with: .color(.orange))
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
        drawSurfaceKnotDisplays(
            scene: scene,
            layout: layout,
            in: &context
        )
        drawSurfaceSpanDisplays(
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

        drawSectionAnalysisOverlay(
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
            layout: layout,
            chromeLayout: chromeLayout
        )

        drawConstructionPlaneHandleAffordances(
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
                layout: layout
            )
        }

        drawMeasurementOverlays(
            in: &context,
            layout: layout,
            chromeLayout: chromeLayout
        )
    }

    private func drawMeasurementOverlays(
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        chromeLayout: ViewportCanvasChromeLayout
    ) {
        if measurementToolActive {
            guard let start = measurementSession.state.start,
                  let startProjection = layout.projectedPoint(start.point)?.point else {
                return
            }
            context.fill(
                Path(ellipseIn: CGRect(
                    x: startProjection.x - 4.0,
                    y: startProjection.y - 4.0,
                    width: 8.0,
                    height: 8.0
                )),
                with: .color(.cyan)
            )
            guard let end = measurementSession.state.visibleEnd,
                  let endProjection = layout.projectedPoint(end.point)?.point else { return }
            var path = Path()
            path.move(to: startProjection)
            path.addLine(to: endProjection)
            context.stroke(
                path,
                with: .color(.cyan.opacity(0.92)),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: endProjection.x - 4.0,
                    y: endProjection.y - 4.0,
                    width: 8.0,
                    height: 8.0
                )),
                with: .color(.cyan)
            )
            if let distanceMeters = measurementDistanceMeters(start: start.point, end: end.point) {
                let midpoint = CGPoint(
                    x: (startProjection.x + endProjection.x) * 0.5,
                    y: (startProjection.y + endProjection.y) * 0.5
                )
                let length = hypot(
                    endProjection.x - startProjection.x,
                    endProjection.y - startProjection.y
                )
                let normal = length > 1.0e-6
                    ? CGPoint(
                        x: -(endProjection.y - startProjection.y) / length,
                        y: (endProjection.x - startProjection.x) / length
                    )
                    : CGPoint(x: 0.0, y: -1.0)
                drawMeasurementLabel(
                    formattedViewportLength(distanceMeters),
                    at: CGPoint(
                        x: midpoint.x + normal.x * 14.0,
                        y: midpoint.y + normal.y * 14.0
                    ),
                    in: &context
                )
            }
            return
        }

        guard showsAutomaticMeasurement,
              activeCanvasDrag == nil,
              pendingInteractionTarget == nil,
              nativeAxisGesture == nil,
              let occurrence = selectedMeasurementOccurrence() else {
            return
        }
        let safeRect = layout.fittingInsets.fittingRect(in: layout.viewportSize)
        let rulers = ViewportMeasurementBoundsRulerLayout().rulers(
            for: occurrence.worldBounds,
            layout: layout,
            displayUnit: workspaceRuler.displayUnit,
            safeRect: safeRect,
            excludedRects: chromeLayout.inputExclusionRects
        )
        for ruler in rulers {
            var path = Path()
            path.move(to: ruler.extensionStart)
            path.addLine(to: ruler.dimensionStart)
            path.move(to: ruler.extensionEnd)
            path.addLine(to: ruler.dimensionEnd)
            path.move(to: ruler.dimensionStart)
            path.addLine(to: ruler.dimensionEnd)
            context.stroke(
                path,
                with: .color(.orange.opacity(0.88)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
            )
            drawMeasurementLabel(
                ruler.label,
                at: CGPoint(x: ruler.labelRect.midX, y: ruler.labelRect.midY),
                in: &context
            )
        }
    }

    private func drawMeasurementLabel(
        _ label: String,
        at point: CGPoint,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: point.x - max(26.0, CGFloat(label.count) * 3.2 + 7.0),
            y: point.y - 10.0,
            width: max(52.0, CGFloat(label.count) * 6.4 + 14.0),
            height: 20.0
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: 5.0),
            with: .color(Color.black.opacity(0.70))
        )
        context.draw(
            Text(label)
                .font(.system(size: 10.0, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.96)),
            at: point
        )
    }

    private func measurementDistanceMeters(
        start: Point3D,
        end: Point3D
    ) -> Double? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dz = end.z - start.z
        let distance = sqrt(dx * dx + dy * dy + dz * dz)
        return distance.isFinite ? distance : nil
    }

    private func selectedMeasurementOccurrence() -> UniversalViewportSceneItem? {
        guard let presentationScene else { return nil }
        guard selection.selectedSceneNodeIDs.count == 1,
              let selectedID = selection.selectedSceneNodeIDs.first else { return nil }
        var match: UniversalViewportSceneItem?
        for item in presentationScene.items
        where presentationSceneNodeIDByOccurrenceID[item.occurrenceID] == selectedID {
            guard match == nil else { return nil }
            match = item
        }
        return match
    }

    private func drawSectionAnalysisOverlay(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let overlay = ViewportSectionAnalysisOverlay.build(
            result: sectionAnalysis,
            ruler: workspaceRuler
        )
        guard overlay.plane != nil || overlay.segments.isEmpty == false else {
            return
        }
        if let plane = overlay.plane {
            drawSectionAnalysisPlaneItem(
                plane,
                in: &context,
                layout: layout
            )
        }
        drawSectionAnalysisContourItems(
            overlay.contours,
            in: &context,
            layout: layout
        )
        drawSectionAnalysisHatchItems(
            overlay.hatches,
            in: &context,
            layout: layout
        )
        guard overlay.segments.isEmpty == false else {
            return
        }
        var intersectionPath = Path()
        for segment in overlay.segments {
            intersectionPath.addPath(projectedPath([segment.start, segment.end], layout: layout))
        }
        context.stroke(
            intersectionPath,
            with: .color(Color.black.opacity(0.58)),
            style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            intersectionPath,
            with: .color(ViewportTheme.sectionAnalysisIntersection.opacity(0.95)),
            style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSectionAnalysisContourItems(
        _ items: [ViewportSectionAnalysisOverlay.ContourItem],
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        for item in items where item.isClosed && item.points.count >= 3 {
            let path = projectedPath(item.points, layout: layout, closed: true)
            context.fill(
                path,
                with: .color(ViewportTheme.sectionAnalysisIntersection.opacity(0.10))
            )
            context.stroke(
                path,
                with: .color(ViewportTheme.sectionAnalysisIntersection.opacity(0.36)),
                style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)
            )
        }
    }

    private func drawSectionAnalysisHatchItems(
        _ items: [ViewportSectionAnalysisOverlay.HatchItem],
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard items.isEmpty == false else {
            return
        }
        var hatchPath = Path()
        for item in items {
            hatchPath.addPath(projectedPath([item.start, item.end], layout: layout))
        }
        context.stroke(
            hatchPath,
            with: .color(ViewportTheme.sectionAnalysisIntersection.opacity(0.34)),
            style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
        )
    }

    private func drawSectionAnalysisPlaneItem(
        _ item: ViewportSectionAnalysisOverlay.PlaneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let planePath = projectedPath(item.corners, layout: layout, closed: true)
        context.fill(
            planePath,
            with: .color(ViewportTheme.sectionAnalysisPlane.opacity(0.055))
        )
        context.stroke(
            planePath,
            with: .color(ViewportTheme.sectionAnalysisPlane.opacity(0.48)),
            style: StrokeStyle(lineWidth: 1.0, lineJoin: .round, dash: [8.0, 5.0])
        )

        let normalPath = projectedPath([item.origin, item.normalEnd], layout: layout)
        context.stroke(
            normalPath,
            with: .color(ViewportTheme.sectionAnalysisNormal.opacity(0.62)),
            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [5.0, 4.0])
        )
    }

    private func drawConstructionPlaneHandleAffordances(
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard onConstructionPlaneHandleDrag != nil else {
            return
        }
        let geometry = ViewportConstructionPlaneHandleGeometry()
        let targets = geometry.targets(
            document: document,
            ruler: workspaceRuler,
            selection: selection,
            layout: layout
        )
        guard targets.isEmpty == false else {
            return
        }

        var drawnPlaneIDs: Set<ConstructionPlaneSourceID> = []
        for target in targets {
            guard let displayTarget = displayedConstructionPlaneHandleTarget(target, layout: layout) else { continue }
            guard drawnPlaneIDs.insert(displayTarget.constructionPlaneID).inserted else {
                continue
            }
            drawConstructionPlaneFrame(
                displayTarget,
                in: &context,
                layout: layout
            )
            drawConstructionPlaneNormalGuide(
                displayTarget,
                in: &context
            )
        }

        for target in targets {
            guard let displayTarget = displayedConstructionPlaneHandleTarget(target, layout: layout) else { continue }
            drawConstructionPlaneHandle(
                displayTarget,
                isHighlighted: isConstructionPlaneHandleHighlighted(target),
                in: &context
            )
        }
    }

    private func displayedConstructionPlaneHandleTarget(
        _ target: ViewportConstructionPlaneHandleTarget,
        layout: ViewportLayout
    ) -> ViewportConstructionPlaneHandleTarget? {
        guard let activeConstructionPlaneHandleDrag,
              activeConstructionPlaneHandleDrag.target.constructionPlaneID == target.constructionPlaneID,
              let basis = constructionPlaneBasis(
                  origin: activeConstructionPlaneHandleDrag.origin,
                  normal: activeConstructionPlaneHandleDrag.normal
              ) else {
            return target
        }

        let guideLength = max(pointDistance(target.normalEnd, target.origin), 1.0e-9)
        let halfExtent = max(guideLength * 1.7, 1.0e-9)
        let origin = basis.origin
        let normalEnd = pointOffsetBy(origin, scale(basis.normal, by: guideLength))
        let negativeU = scale(basis.u, by: -halfExtent)
        let positiveU = scale(basis.u, by: halfExtent)
        let negativeV = scale(basis.v, by: -halfExtent)
        let positiveV = scale(basis.v, by: halfExtent)
        let corners = [
            pointOffsetBy(pointOffsetBy(origin, negativeU), negativeV),
            pointOffsetBy(pointOffsetBy(origin, positiveU), negativeV),
            pointOffsetBy(pointOffsetBy(origin, positiveU), positiveV),
            pointOffsetBy(pointOffsetBy(origin, negativeU), positiveV),
        ]
        guard let projectedOrigin = layout.projectedPoint(origin)?.point,
              let projectedNormalEnd = layout.projectedPoint(normalEnd)?.point else { return nil }
        return ViewportConstructionPlaneHandleTarget(
            constructionPlaneID: target.constructionPlaneID,
            sceneNodeID: target.sceneNodeID,
            handle: target.handle,
            origin: origin,
            normal: basis.normal,
            normalEnd: normalEnd,
            corners: corners,
            projectedOrigin: projectedOrigin,
            projectedNormalEnd: projectedNormalEnd
        )
    }

    private func constructionPlaneBasis(
        origin: Point3D,
        normal: Vector3D
    ) -> (origin: Point3D, normal: Vector3D, u: Vector3D, v: Vector3D)? {
        do {
            let unitNormal = try normal.normalized(tolerance: 1.0e-12)
            let helper = abs(unitNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(unitNormal).normalized(tolerance: 1.0e-12)
            let v = unitNormal.cross(u)
            return (origin, unitNormal, u, v)
        } catch {
            return nil
        }
    }

    private func drawConstructionPlaneFrame(
        _ target: ViewportConstructionPlaneHandleTarget,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let path = projectedPath(target.corners, layout: layout, closed: true)
        context.fill(
            path,
            with: .color(ViewportTheme.sectionAnalysisPlane.opacity(0.045))
        )
        context.stroke(
            path,
            with: .color(ViewportTheme.sectionAnalysisPlane.opacity(0.40)),
            style: StrokeStyle(lineWidth: 0.9, lineJoin: .round, dash: [7.0, 5.0])
        )
    }

    private func drawConstructionPlaneNormalGuide(
        _ target: ViewportConstructionPlaneHandleTarget,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: target.projectedOrigin)
        path.addLine(to: target.projectedNormalEnd)
        context.stroke(
            path,
            with: .color(ViewportTheme.sectionAnalysisNormal.opacity(0.76)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5.0, 4.0])
        )
    }

    private func drawConstructionPlaneHandle(
        _ target: ViewportConstructionPlaneHandleTarget,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        switch target.handle {
        case .origin:
            drawTransformHandle(
                at: target.projectedOrigin,
                style: .faceCenter,
                isHighlighted: isHighlighted,
                in: &context
            )
        case .normal:
            drawTransformHandle(
                at: target.projectedNormalEnd,
                style: .vertex,
                isHighlighted: isHighlighted,
                in: &context
            )
        }
    }

    private func isConstructionPlaneHandleHighlighted(
        _ target: ViewportConstructionPlaneHandleTarget
    ) -> Bool {
        hoveredConstructionPlaneHandle?.identity == target.identity
            || pendingConstructionPlaneHandle?.identity == target.identity
            || activeConstructionPlaneHandleDrag?.target.identity == target.identity
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
        layout: ViewportLayout,
        chromeLayout: ViewportCanvasChromeLayout
    ) {
        guard let snapOverlayResult else {
            return
        }
        ViewportSnapOverlayRenderer.draw(
            result: snapOverlayResult,
            layout: layout,
            chromeLayout: chromeLayout,
            context: snapOverlayContext,
            in: &context
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
            guidePath.addPath(projectedPath([
                Point3D(x: Double(minX), y: 0, z: anchor.point.y),
                Point3D(x: Double(maxX), y: 0, z: anchor.point.y),
            ], layout: layout))
            guidePath.addPath(projectedPath([
                Point3D(x: anchor.point.x, y: 0, z: Double(minY)),
                Point3D(x: anchor.point.x, y: 0, z: Double(maxY)),
            ], layout: layout))
            context.stroke(guidePath, with: .color(lineColor), style: style)

            guard let projectedAnchor = layout.projectedPoint(
                CGPoint(x: CGFloat(anchor.point.x), y: CGFloat(anchor.point.y))
            )?.point else { continue }
            let anchorRect = CGRect(
                x: projectedAnchor.x - 3.0,
                y: projectedAnchor.y - 3.0,
                width: 6.0,
                height: 6.0
            )
            context.fill(Path(ellipseIn: anchorRect), with: .color(anchorColor))
        }
    }

    private func snapOverlayQuery() -> ViewportSnapQuery? {
        if let activeCanvasDrag {
            guard case .creation = activeCanvasDrag.kind else {
                return nil
            }
            let sketchPlane = activeCanvasDrag.sketchPlane ?? canvasDragSketchPlane(for: hoveredCanvasHit)
            guard let startInput = canvasInput(
                for: activeCanvasDrag.startLocation,
                exactWorldPoint: nil,
                sketchPlane: sketchPlane
            ),
            let currentInput = canvasInput(
                for: activeCanvasDrag.currentLocation,
                exactWorldPoint: nil,
                sketchPlane: sketchPlane
            ) else {
                return nil
            }
            let constrainedPoint = canvasDragAxisConstraint?.constrainedCanvasPoint(
                currentInput.point,
                from: startInput.point,
                on: sketchPlane
            ) ?? currentInput.point
            return ViewportSnapQuery(
                point: constrainedPoint,
                referencePoint: startInput.point
            )
        }
        guard let hoveredModelPoint else {
            return nil
        }
        return ViewportSnapQuery(point: hoveredModelPoint, referencePoint: nil)
    }

    private func canvasInput(
        for viewportPoint: CGPoint,
        exactWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> WorkspaceCanvasPlaneInputMapper.Result? {
        do {
            let identity = try presentationQueryIdentity()
            let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
            let worldPoint: Point3D
            // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy CAD face callers still
            // supply CPU-resolved surface points. RK-4.2.3 must replace those
            // callers with native provenance before claiming full input cutover.
            if let exactWorldPoint {
                _ = try presentationPlanCache.project(
                    exactWorldPoint, for: identity, revision: activeControlSession.revision
                )
                worldPoint = exactWorldPoint
            } else {
                worldPoint = try presentationPlanCache.worldPlaneIntersection(
                    at: viewportPoint,
                    planeOrigin: coordinateSystem.origin,
                    planeNormal: coordinateSystem.normal,
                    for: identity,
                    revision: activeControlSession.revision
                )
            }
            return .init(
                point: SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
                    .canvasPoint(fromLocal: coordinateSystem.project(worldPoint).point),
                worldPoint: worldPoint
            )
        } catch {
            return nil
        }
    }

    private func canvasModelDrag(
        from start: CGPoint,
        to end: CGPoint,
        mapper: ViewportModelCoordinateMapper,
        sketchPlane: SketchPlane,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags(),
        startExactWorldPoint: Point3D? = nil,
        endExactWorldPoint: Point3D? = nil
    ) -> ViewportModelDrag? {
        guard let startInput = canvasInput(
            for: start,
            exactWorldPoint: startExactWorldPoint,
            sketchPlane: sketchPlane
        ),
        let endInput = canvasInput(
            for: end,
            exactWorldPoint: endExactWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return nil
        }
        return ViewportModelDrag(
            start: startInput.point,
            end: endInput.point,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startExactWorldPoint,
            endWorldPoint: endExactWorldPoint,
            startViewRayAnchorWorldPoint: mapper.displayedCanvasWorldPoint(for: start),
            endViewRayAnchorWorldPoint: mapper.displayedCanvasWorldPoint(for: end)
        )
    }

    private func publishSnapCandidateKind(_ kind: RupaCore.SnapCandidateKind?) {
        guard reportedSnapCandidateKind != kind else {
            return
        }
        reportedSnapCandidateKind = kind
        onSnapCandidateKindChange?(kind)
    }

    private func refreshSnapOverlayResolution(size: CGSize) {
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        refreshSnapOverlayResolution(layout: mapper.layout)
    }

    private func refreshSnapOverlayResolution(layout: ViewportLayout) {
        applySnapOverlayResolution(
            ViewportSnapResolutionService().resolution(
                for: snapOverlayQuery(),
                document: document,
                ruler: workspaceRuler,
                options: snapResolutionOptions,
                modifierFlags: modifierFlags
            )
        )
    }

    private func applySnapOverlayResolution(_ resolution: ViewportSnapResolution) {
        if snapOverlayResult != resolution.result {
            snapOverlayResult = resolution.result
        }
        if snapOverlayFailureDescription != resolution.failureDescription {
            if let failureDescription = resolution.failureDescription {
                Self.snapOverlayLogger.warning(
                    "Snap overlay resolution failed: \(failureDescription, privacy: .public)"
                )
            }
            snapOverlayFailureDescription = resolution.failureDescription
        }
        publishSnapCandidateKind(resolution.publishedKind(context: snapOverlayContext))
    }

    private func refreshPlacementHighlight(size: CGSize) {
        let mapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        refreshPlacementHighlight(layout: mapper.layout)
    }

    private func refreshPlacementHighlight(layout: ViewportLayout) {
        guard let previewKind = canvasPlacementPreviewKind,
              let hoveredModelPoint,
              hoveredCanvasHit?.bodyFace == nil,
              hoveredCanvasHit?.bodyEdge == nil,
              hoveredCanvasHit?.bodyVertex == nil else {
            clearPlacementHighlight()
            return
        }

        let resolution = ViewportSnapResolutionService().resolution(
            for: ViewportSnapQuery(point: hoveredModelPoint, referencePoint: nil),
            document: document,
            ruler: workspaceRuler,
            options: snapResolutionOptions,
            modifierFlags: modifierFlags
        )
        let sketchPlane = canvasDragSketchPlane(for: hoveredCanvasHit)
        applyPlacementHighlight(
            ViewportPlacementHighlight(
                point: resolution.result?.resolvedPoint ?? hoveredModelPoint,
                sketchPlane: sketchPlane,
                previewKind: previewKind
            ),
            failureDescription: resolution.failureDescription
        )
    }

    private func applyPlacementHighlight(
        _ placementHighlight: ViewportPlacementHighlight,
        failureDescription: String?
    ) {
        if placementHighlightState != placementHighlight {
            placementHighlightState = placementHighlight
        }
        if placementHighlightFailureDescription != failureDescription {
            if let failureDescription {
                Self.placementHighlightLogger.warning(
                    "Placement highlight snap resolution failed: \(failureDescription, privacy: .public)"
                )
            }
            placementHighlightFailureDescription = failureDescription
        }
    }

    private func clearPlacementHighlight() {
        if placementHighlightState != nil {
            placementHighlightState = nil
        }
        if placementHighlightFailureDescription != nil {
            placementHighlightFailureDescription = nil
        }
    }

    private func clearSnapOverlayResolution() {
        if snapOverlayResult != nil {
            snapOverlayResult = nil
        }
        if snapOverlayFailureDescription != nil {
            snapOverlayFailureDescription = nil
        }
        publishSnapCandidateKind(nil)
    }

    private func captureReferenceLineAnchor(at point: CGPoint) -> Bool {
        guard let onReferenceLineAnchor else {
            return false
        }
        let sketchPlane = canvasDragSketchPlane(for: hoveredCanvasHit)
        guard let modelPoint = canvasInput(
            for: point,
            exactWorldPoint: nil,
            sketchPlane: sketchPlane
        )?.point else {
            return false
        }
        let resolution = ViewportSnapResolutionService().resolution(
            for: ViewportSnapQuery(point: modelPoint, referencePoint: nil),
            document: document,
            ruler: workspaceRuler,
            options: snapResolutionOptions,
            modifierFlags: modifierFlags
        )
        if let failureDescription = resolution.failureDescription {
            Self.referenceLineAnchorLogger.warning(
                "Reference line anchor snap resolution failed: \(failureDescription, privacy: .public)"
            )
        }
        guard let result = resolution.result,
              let selectedCandidate = result.selectedCandidate,
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
        let path = projectedPath(item.points, layout: layout, closed: item.isClosed)
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
        let endPoint = Point3D(
            x: item.position.x + item.normal.x * item.normalCurvature * scale,
            y: item.position.y + item.normal.y * item.normalCurvature * scale,
            z: item.position.z + item.normal.z * item.normalCurvature * scale
        )
        let path = projectedPath([item.position, endPoint], layout: layout)
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
        let start = Point3D(
            x: position.x - offset.x,
            y: position.y - offset.y,
            z: position.z - offset.z
        )
        let end = Point3D(
            x: position.x + offset.x,
            y: position.y + offset.y,
            z: position.z + offset.z
        )
        let path = projectedPath([start, end], layout: layout)
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
        let color = surfaceContinuityColor(for: item)
        let path = projectedPath([item.start, item.end], layout: layout)
        context.stroke(
            path,
            with: .color(color.opacity(0.94)),
            style: StrokeStyle(
                lineWidth: item.requiresCurvatureContinuitySolve ? 4.0 : 3.2,
                lineCap: .round,
                dash: item.requiresCurvatureContinuitySolve ? [6.0, 4.0] : []
            )
        )
        for endpoint in [item.start, item.end] {
            if let point = layout.projectedPoint(endpoint)?.point {
                drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
            }
        }
        guard let midpoint = layout.projectedPoint(item.midpoint)?.point else { return }
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
            let projectedPoints = layout.projectedPolygon(region.points.map {
                Point3D(x: Double($0.x), y: 0, z: Double($0.y))
            }).map(\.point)
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters ?? 0.0
        ) else { return }
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            widthMeters: widthMeters
        ) else { return }
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        ) else { return }
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        ) else { return }
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        ) else { return }
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
        guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return }
        guard let end = candidate.geometry.projectedTip(
            layout: layout,
            distanceMeters: distanceMeters
        ) else { return }
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
        let patchDescriptors = polySplinePatchDescriptorsByFeatureID()
        guard let previewVertices = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewVertices(
            selectedVertices: selectedInputs,
            topologyVertices: polySplineSurfaceTopologyVertices(in: scene),
            patches: patchDescriptors,
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
            patches: patchDescriptors,
            direction: activePolySplineSurfaceVertexSlideDrag.target.direction,
            distanceMeters: activePolySplineSurfaceVertexSlideDrag.distanceMeters,
            tolerance: document.modelingSettings.tolerance
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
            let displayedPoint = showsOriginalComparison ? vertex.originalPoint : vertex.movedPoint
            if !showsOriginalComparison {
                let path = projectedPath([vertex.originalPoint, displayedPoint], layout: layout)
                context.stroke(
                    path,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5.0, 4.0])
                )
            }
            guard let displayed = layout.projectedPoint(displayedPoint)?.point else { continue }
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
            patches: polySplinePatchDescriptorsByFeatureID(),
            direction: activeSurfaceControlPointSlideDrag.target.direction,
            distanceMeters: activeSurfaceControlPointSlideDrag.distanceMeters
        ) else {
            return
        }
        let showsOriginalComparison = modifierFlags.containsControl
        let color = ViewportTheme.surfaceEdit
        for vertex in previewVertices {
            let displayedPoint = showsOriginalComparison ? vertex.originalPoint : vertex.movedPoint
            if !showsOriginalComparison {
                let path = projectedPath([vertex.originalPoint, displayedPoint], layout: layout)
                context.stroke(
                    path,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5.0, 4.0])
                )
            }
            guard let displayed = layout.projectedPoint(displayedPoint)?.point else { continue }
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

            let path = projectedPath([
                mesh.positions[firstIndex], mesh.positions[secondIndex], mesh.positions[thirdIndex],
            ], layout: layout, closed: true)
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
                guard let projected = layout.projectedPoint(displayedPoint)?.point else { continue }
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
                let path = projectedPath([displayedLine.start, displayedLine.end], layout: layout)
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
                let path = projectedPath(displayedPoints, layout: layout)
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
        guard let projected = layout.projectedPoint(point)?.point else { return }
        drawTransformHandle(
            at: projected,
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
        guard let projectedStart = layout.projectedPoint(start)?.point,
              let projectedEnd = layout.projectedPoint(end)?.point else { return }
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
        guard let projectedCenter = layout.projectedPoint(center)?.point,
              let projectedRadius = layout.projectedPoint(radiusPoint)?.point else { return }
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
        guard let projectedCenter = layout.projectedPoint(center)?.point,
              let projectedRadius = layout.projectedPoint(radiusPoint)?.point else { return }
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
            preferredUnit: workspaceRuler.displayUnit
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
        guard let projected = layout.projectedPoint(point)?.point else { return }
        drawTransformHandle(
            at: projected,
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
        let controlPath = projectedPath(controlPoints, layout: layout)
        context.stroke(
            controlPath,
            with: .color(color.opacity(0.38)),
            style: StrokeStyle(lineWidth: 1.1, dash: [4.0, 3.0])
        )
        for (index, point) in controlPoints.enumerated() {
            guard let projected = layout.projectedPoint(point)?.point else { continue }
            drawTransformHandle(
                at: projected,
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

        var spinePoints: [CGPoint] = []
        spinePoints.reserveCapacity(comb.samples.count)
        for sample in comb.samples {
            let samplePoint = CGPoint(
                x: CGFloat(sample.point.x),
                y: CGFloat(sample.point.y)
            )
            let end = CGPoint(
                x: CGFloat(sample.point.x + sample.normal.x * sample.curvature * scale),
                y: CGFloat(sample.point.y + sample.normal.y * sample.curvature * scale)
            )
            let combLine = projectedPath([samplePoint, end], layout: layout)
            context.stroke(
                combLine,
                with: .color(.white.opacity(0.58)),
                lineWidth: 0.8
            )

            spinePoints.append(end)
        }
        let spinePath = projectedPath(spinePoints, layout: layout)
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
        sceneOverlayState.curveCurvatureDisplays[
            .sketchEntity(featureID: featureID, entityID: entityID)
        ]
    }

    private func pointDisplay(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) -> PointDisplay? {
        sceneOverlayState.pointDisplays[
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
        let points = (0 ... 96).map { index in
            let angle = CGFloat(index) / 96.0 * CGFloat.pi * 2.0
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        return projectedPath(points, layout: layout)
    }

    private func projectedArcPath(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        layout: ViewportLayout
    ) -> Path {
        let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
        let points = (0 ... 96).map { index in
            pointOnSketchCircle(
                center: center, radiusMeters: radiusMeters,
                angleRadians: startAngleRadians + span * Double(index) / 96
            )
        }
        return projectedPath(points, layout: layout)
    }

    /// Published surfaces belong exclusively to Metal. Only explicit edited
    /// bodies and the requested preview target may add a transient Canvas ghost.
    static func drawsTransientBody(
        sceneNodeID: SceneNodeID?, previewSceneNodeID: SceneNodeID?, isEdited: Bool
    ) -> Bool {
        isEdited || (previewSceneNodeID != nil && sceneNodeID == previewSceneNodeID)
    }

    private func drawBody(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        sectionAction: SectionAnalysisClippingPlan.BodyAction?
    ) {
        guard case .body(let component) = item.kind else {
            return
        }
        guard sectionAction != .hidden else {
            return
        }
        if let mesh = component.mesh {
            drawBodyMesh(
                mesh,
                item: item,
                in: &context,
                layout: layout,
                isSelected: isSelected,
                isHovered: isHovered,
                sectionAction: sectionAction
            )
            return
        }
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        let isSectionClipped = sectionAction == .clipped
        let fillColor = isSelected
            ? ViewportTheme.selection
            : (isSectionClipped ? ViewportTheme.sectionAnalysisPlane : ViewportTheme.bodySurface)
        let corners = edit.worldBoxCorners
        let faces = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4],
                     [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
        let fillOpacity = isSelected ? 0.44 : (isSectionClipped ? 0.24 : 0.52)
        for (index, face) in faces.enumerated() {
            context.fill(
                projectedPath(face.map { corners[$0] }, layout: layout, closed: true),
                with: .color(fillColor.opacity(fillOpacity * (0.72 + Double(index % 3) * 0.11)))
            )
        }
        let highlighted = isSelected || isHovered || isSectionClipped
        context.stroke(
            projectedBoxEdges(corners, layout: layout),
            with: .color((highlighted ? Color.white : Color.black).opacity(highlighted ? 0.58 : 0.42)),
            lineWidth: highlighted ? 1.35 : 0.85
        )
    }

    private func drawCurve(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool
    ) {
        guard case .curve(let component) = item.kind else {
            return
        }
        let color = isSelected
            ? ViewportTheme.selection
            : (isHovered ? ViewportTheme.hover : ViewportTheme.curve)
        let lineWidth: CGFloat = isSelected ? 3.0 : (isHovered ? 2.6 : 1.8)
        for segment in component.segments where segment.points.count >= 2 {
            let path = projectedPath(segment.points.map { layout.transformedPoint($0, in: item) }, layout: layout)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func drawBodyMesh(
        _ mesh: ViewportBodyMesh,
        item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        sectionAction: SectionAnalysisClippingPlan.BodyAction?
    ) {
        let isSectionClipped = sectionAction == .clipped
        let baseColor = isSelected
            ? ViewportTheme.selection
            : (isSectionClipped ? ViewportTheme.sectionAnalysisPlane : ViewportTheme.bodySurface)
        let fillOpacity = isSelected ? 0.28 : (isSectionClipped ? 0.16 : 0.22)
        let strokeOpacity = isSelected || isHovered || isSectionClipped ? 0.62 : 0.26
        let meshClipper = ViewportSectionMeshClipper()
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
            let polygon: [Point3D]
            if isSectionClipped,
               let sectionAnalysis,
               let retainedSide = sectionClippingPlan?.retainedSide {
                polygon = meshClipper.clippedTriangle(
                    first: mesh.positions[firstIndex],
                    second: mesh.positions[secondIndex],
                    third: mesh.positions[thirdIndex],
                    item: item,
                    plane: sectionAnalysis.plane,
                    retaining: retainedSide,
                    toleranceMeters: sectionAnalysis.toleranceMeters
                )
                guard polygon.count >= 3 else {
                    index += 3
                    continue
                }
            } else {
                polygon = [
                    ViewportLayout.transformedPoint(mesh.positions[firstIndex], by: item.modelTransform),
                    ViewportLayout.transformedPoint(mesh.positions[secondIndex], by: item.modelTransform),
                    ViewportLayout.transformedPoint(mesh.positions[thirdIndex], by: item.modelTransform),
                ]
            }

            let path = projectedPath(polygon, layout: layout, closed: true)
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

    private func drawPlacementHighlight(
        _ placement: ViewportPlacementHighlight,
        visibleCellMeters: Double,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let geometry = ViewportPlacementPreviewGeometry(
            placement: placement,
            layout: layout,
            defaults: WorkspaceScaleDefaults(ruler: workspaceRuler),
            visibleCellMeters: visibleCellMeters
        ) else {
            return
        }

        switch geometry.shape {
        case .rectangle(let footprint):
            let highlightPath = path(for: footprint)
            context.fill(highlightPath, with: .color(Color.cyan.opacity(0.12)))
            context.stroke(highlightPath, with: .color(Color.cyan.opacity(0.62)), lineWidth: 1.6)
        case .polygon(let center, let vertices, let radiusEnd):
            let polygonPath = polylinePath(for: vertices + vertices.prefix(1))
            let radiusPath = polylinePath(for: [center, radiusEnd])
            context.stroke(
                radiusPath,
                with: .color(Color.white.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
            )
            context.fill(polygonPath, with: .color(Color.cyan.opacity(0.10)))
            context.stroke(
                polygonPath,
                with: .color(Color.cyan.opacity(0.68)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        case .arc(let center, let points, let radiusEnd):
            let arcPath = polylinePath(for: points)
            let radiusPath = polylinePath(for: [center, radiusEnd])
            context.stroke(
                radiusPath,
                with: .color(Color.white.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
            )
            context.stroke(
                arcPath,
                with: .color(Color.cyan.opacity(0.76)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
        case .spline(let controlPoints, let curvePoints):
            let controlPath = polylinePath(for: controlPoints)
            let curvePath = polylinePath(for: curvePoints)
            context.stroke(
                controlPath,
                with: .color(Color.white.opacity(0.20)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round, dash: [4.0, 4.0])
            )
            context.stroke(
                curvePath,
                with: .color(Color.cyan.opacity(0.76)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
        case .circle(let center, let points, let radiusEnd):
            let circlePath = polylinePath(for: points)
            let radiusPath = polylinePath(for: [center, radiusEnd])
            context.stroke(
                radiusPath,
                with: .color(Color.white.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
            )
            context.fill(circlePath, with: .color(Color.cyan.opacity(0.08)))
            context.stroke(
                circlePath,
                with: .color(Color.cyan.opacity(0.72)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
        }
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
                guard componentID.generatedTopologySubshapeID != nil,
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
                guard componentID.generatedTopologySubshapeID != nil,
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
                guard componentID.generatedTopologySubshapeID != nil,
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
        let highlightPath = projectedPath(
            face.points.map { layout.transformedPoint($0, in: item) }, layout: layout, closed: true
        )
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
        let path = projectedPath(
            [edge.start, edge.end].map { layout.transformedPoint($0, in: item) }, layout: layout
        )
        context.stroke(
            path,
            with: .color(style.color.opacity(style.strokeOpacity)),
            lineWidth: style.lineWidth + 1.8
        )
        for endpoint in [edge.start, edge.end] {
            if let point = layout.projectedPoint(endpoint, in: item)?.point {
                drawTransformHandle(at: point, style: .vertex, isHighlighted: true, in: &context)
            }
        }
    }

    private func drawGeneratedVertexHighlight(
        _ vertex: ViewportBodyTopology.Vertex,
        item: ViewportSceneItem,
        style: ViewportFaceHighlightStyle,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let point = layout.projectedPoint(vertex.point, in: item)?.point else { return }
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
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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

    private func drawSurfaceKnotDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceKnotDisplays {
                drawSurfaceKnotDisplay(
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

    private func drawSurfaceKnotDisplay(
        _ display: ViewportSurfaceKnotDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
            with: .color(color.opacity(isSelected || isHovered ? 0.78 : 0.42))
        )
        context.stroke(
            Path(rect),
            with: .color(color.opacity(isSelected || isHovered ? 0.94 : 0.62)),
            lineWidth: isSelected ? 1.25 : 0.85
        )
    }

    private func drawSurfaceSpanDisplays(
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            for display in component.surfaceSpanDisplays {
                drawSurfaceSpanDisplay(
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

    private func drawSurfaceSpanDisplay(
        _ display: ViewportSurfaceSpanDisplay,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool,
        in context: inout GraphicsContext
    ) {
        guard let point = layout.projectedPoint(display.point, in: item)?.point else { return }
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
        guard let origin = layout.projectedPoint(display.position, in: item)?.point else { return }
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
            let projected = layout.projectedPoint(Point3D(
                x: basePoint.x + modelDirection.x * distanceMeters,
                y: basePoint.y + modelDirection.y * distanceMeters,
                z: basePoint.z + modelDirection.z * distanceMeters
            ))?.point
            return projected
        }
        let modelScale = Double(max(max(item.modelBounds.width, item.modelBounds.height), 1.0e-6)) * 0.08
        let axisPoint = Point3D(
            x: display.position.x + direction.x * modelScale,
            y: display.position.y + direction.y * modelScale,
            z: display.position.z + direction.z * modelScale
        )
        guard let projected = layout.projectedPoint(axisPoint, in: item)?.point else { return nil }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceControlPointDrag.delta)
        guard let end = layout.projectedPoint(movedPoint)?.point else { return }
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
        guard let point = target.geometry.projectedPoint(layout: layout) else { return }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceTrimEndpointDrag.delta)
        guard let end = layout.projectedPoint(movedPoint)?.point else { return }
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
        guard let point = target.geometry.projectedPoint(layout: layout) else { return }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activeSurfaceTrimControlPointDrag.delta)
        guard let end = layout.projectedPoint(movedPoint)?.point else { return }
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
        guard let point = target.geometry.projectedPoint(layout: layout) else { return }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
        let movedPoint = geometry.displayPoint(offsetByLocalDelta: activePolySplineSurfaceVertexDrag.delta)
        guard let end = layout.projectedPoint(movedPoint)?.point else { return }
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
        guard let point = geometry.projectedPoint(layout: layout) else { return }
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
        guard let start = geometry.projectedPoint(layout: layout) else { return }
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
            topologyVertices: topologyVertices,
            patches: polySplinePatchDescriptorsByFeatureID()
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
                || componentID.generatedTopologySubshapeID == nil
        case .edge(let componentID):
            guard case .body(let bodyComponent) = item.kind else {
                return false
            }
            return bodyComponent.topology?.edges.contains { $0.componentID == componentID } == true
                || componentID.generatedTopologySubshapeID == nil
        case .vertex(let componentID):
            guard case .body(let bodyComponent) = item.kind else {
                return false
            }
            return bodyComponent.topology?.vertices.contains { $0.componentID == componentID } == true
                || componentID.generatedTopologySubshapeID == nil
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
              componentID.generatedTopologySubshapeID != nil,
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
            return ViewportBodyFace.editableCases.compactMap { face in
                let footprint = projection.footprint(for: face)
                let center = footprint.center
                guard let modelPoint = layout.canvasCoordinates(for: center) else { return nil }
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
            return ViewportBodyEdge.verticalCases.compactMap { edge in
                let segment = projection.segment(for: edge)
                let center = CGPoint(
                    x: (segment.start.x + segment.end.x) / 2.0,
                    y: (segment.start.y + segment.end.y) / 2.0
                )
                guard let modelPoint = layout.canvasCoordinates(for: center) else { return nil }
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
        layout: ViewportLayout
    ) {
        let selectedTargets = objectSelectionTargets()
        let selectedFeatureIDs = featureIDs(for: selectedTargets)
        let selectedSceneNodeIDs = sceneNodeIDs(for: selectedTargets)
        let suppressedFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        let selectedBodyItems = selectedBodyItems(in: scene)
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
        for item in scene.items where isObjectItem(
            item,
            selectedByFeatureIDs: selectedFeatureIDs,
            selectedBySceneNodeIDs: selectedSceneNodeIDs
        ) {
            if case .sketch = item.kind,
               suppressedFeatureIDs.contains(item.featureID) {
                continue
            }
            switch item.kind {
            case .curve:
                continue
            case .body:
                guard selectedBodyItems.count <= 1,
                      selectedBodyItems.first?.id == item.id else {
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
        guard let center = candidate.geometry.centerProjectedPoint,
              let start = candidate.geometry.startProjectedPoint else { return }
        guard let end = candidate.geometry.projectedTip(angleRadians: angleRadians) else { return }
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
        guard let handlePoint = candidate.geometry.handlePoint(copyCount: copyCount) else { return }
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
                let path = patternArrayCurvePathPointProjectedPath(
                    target: candidate.target,
                    layout: layout
                )
                if !path.isEmpty {
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.4)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [5.0, 4.0])
                    )
                }
            }
            let identity = candidate.target.identity
            let dragPoint = activePatternArrayCurvePathPointDrag?.target.identity == identity
                ? activePatternArrayCurvePathPointDrag?.point
                : nil
            let projectedPoint: CGPoint
            if let dragPoint {
                guard let visible = layout.projectedPoint(dragPoint)?.point else { continue }
                projectedPoint = visible
            } else {
                projectedPoint = candidate.projectedPoint
            }
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
    ) -> Path {
        let points = target.pathPoints.enumerated().map { index, point in
            if activePatternArrayCurvePathPointDrag?.target.sourceID == target.sourceID,
               activePatternArrayCurvePathPointDrag?.target.pointIndex == index,
               let activePoint = activePatternArrayCurvePathPointDrag?.point {
                return activePoint
            }
            return point
        }
        return projectedPath(points, layout: layout)
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
        let bounds = item.modelBounds
        return projectedPath([
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
        ], layout: layout, closed: true)
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
            return layout.projectedFootprintIfVisible(item.modelBounds)?.center
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
        guard let projection = edit.projectedBodyProjection(layout: layout) else { return }
        let bodyBounds = projection.hitBounds
        let modelCenter = edit.centerPoint
        guard let center = edit.projectedPoint(modelCenter, layout: layout),
              let affordanceBasis = edit.projectedAxisBasis(layout: layout) else { return }
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
            guard let endLength = edit.modelLength(forViewportLength: endScaleLength, axis: axis, layout: layout),
                  let centerLength = edit.modelLength(forViewportLength: radius, axis: axis, layout: layout) else { continue }
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
                    amount: endLength
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
                    amount: centerLength
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
        let path = projectedBoxEdges(edit.worldBoxCorners, layout: layout)
        context.stroke(path, with: .color(Color.white.opacity(0.70)), lineWidth: 1.3)
        context.stroke(path, with: .color(Color.black.opacity(0.36)), lineWidth: 0.55)
    }

    private func projectedBoxEdges(_ corners: [Point3D], layout: ViewportLayout) -> Path {
        var result = Path()
        for index in 0..<8 {
            for bit in [1, 2, 4] where index & bit == 0 {
                result.addPath(projectedPath([corners[index], corners[index | bit]], layout: layout))
            }
        }
        return result
    }

    private func drawSketchSelectionAffordance(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard let footprint = layout.projectedFootprintIfVisible(item.modelBounds) else { return }
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
        ViewportBodyVertex.allCases.compactMap { vertex in
            let position = edit.position(for: vertex)
            guard let point = edit.projectedPoint(position, layout: layout) else { return nil }
            return ViewportVertexHandle(
                vertex: vertex,
                position: position,
                point: point
            )
        }
    }

    private func bodyFaceCenterHandles(
        _ edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> [ViewportFaceHandle] {
        ViewportBodyFace.editableCases.compactMap { face in
            let position = edit.position(for: face)
            guard let point = edit.projectedPoint(position, layout: layout) else { return nil }
            return ViewportFaceHandle(
                face: face,
                position: position,
                point: point
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
        guard let drag = canvasModelDrag(
            from: activeDrag.startLocation,
            to: activeDrag.currentLocation,
            mapper: mapper,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        let previewDrag = ViewportCanvasDragSnapResolver().resolvedDrag(
            drag,
            document: document,
            ruler: workspaceRuler,
            snapOptions: snapResolutionOptions,
            axisConstraint: canvasDragAxisConstraint
        )
        guard let preview = ViewportCanvasDragPreview(
            kind: previewKind,
            drag: previewDrag,
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
        case .circle(let preview):
            drawCircleDragPreview(preview, in: &context)
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

    private func drawCircleDragPreview(
        _ preview: ViewportCanvasCircleDragPreview,
        in context: inout GraphicsContext
    ) {
        let circlePath = polylinePath(for: preview.projectedPoints)
        let radiusPath = polylinePath(for: [
            preview.projectedCenter,
            preview.projectedRadiusEnd,
        ])
        context.stroke(
            radiusPath,
            with: .color(Color.white.opacity(0.28)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4.0, 4.0])
        )
        context.fill(circlePath, with: .color(Color.accentColor.opacity(0.10)))
        context.stroke(
            circlePath,
            with: .color(Color.black.opacity(0.56)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            circlePath,
            with: .color(Color.accentColor.opacity(0.92)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
        drawPreviewHandle(at: preview.projectedCenter, radius: 4.6, in: &context)
        drawPreviewHandle(at: preview.projectedRadiusEnd, radius: 4.2, in: &context)
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

    private func projectedPath(
        _ points: [CGPoint], layout: ViewportLayout, closed: Bool = false
    ) -> Path {
        projectedPath(points.map { Point3D(x: Double($0.x), y: 0, z: Double($0.y)) }, layout: layout, closed: closed)
    }

    private func projectedPath(
        _ points: [Point3D], layout: ViewportLayout, closed: Bool = false
    ) -> Path {
        if closed {
            return path(for: layout.projectedPolygon(points).map(\.point))
        }
        var result = Path()
        for (start, end) in zip(points, points.dropFirst()) {
            let segment = layout.projectedPolygon([start, end])
            guard let first = segment.first,
                  let last = segment.last(where: { $0.point != first.point }) else { continue }
            result.move(to: first.point)
            result.addLine(to: last.point)
        }
        return result
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
        guard let fullLength = edit.modelLength(forViewportLength: viewportLength, axis: axis, layout: layout),
              let headLength = edit.modelLength(
            forViewportLength: isHighlighted ? 18.0 : 15.0,
            axis: axis,
            layout: layout
        ) else { return }
        let shaftLength = max(fullLength - headLength * 0.7, 0.0)
        let shaftEnd = start.offset(axis: axis, amount: shaftLength)
        let end = start.offset(
            axis: axis,
            amount: fullLength
        )

        let shaft = projectedPath([edit.worldPoint(start), edit.worldPoint(shaftEnd)], layout: layout)
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
        let worldTip = edit.worldPoint(tip)
        let worldBase = baseVertices.map(edit.worldPoint)
        let sideOpacity = isHighlighted ? 0.88 : 0.76
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            context.fill(
                projectedPath([worldTip, worldBase[index], worldBase[nextIndex]], layout: layout, closed: true),
                with: .color(color.opacity(sideOpacity - Double(index % 3) * 0.05))
            )
        }
        context.fill(
            projectedPath(Array(worldBase.reversed()), layout: layout, closed: true),
            with: .color(color.opacity(isHighlighted ? 0.62 : 0.48))
        )
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            let path = projectedPath([worldBase[index], worldBase[nextIndex]], layout: layout)
            context.stroke(
                path,
                with: .color(Color.black.opacity(isHighlighted ? 0.48 : 0.34)),
                lineWidth: isHighlighted ? 1.2 : 0.8
            )
        }
        for index in stride(from: 0, to: segmentCount, by: 6) {
            let path = projectedPath([worldTip, worldBase[index]], layout: layout)
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
        guard let point = edit.projectedPoint(center, layout: layout) else { return }
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
        let points = (0 ..< segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * 2.0 * CGFloat.pi
            let point = center
                .offset(axis: firstAxis, amount: cos(angle) * radius)
                .offset(axis: secondAxis, amount: sin(angle) * radius)
            return edit.worldPoint(point)
        }
        return layout.projectedPolygon(points).map(\.point)
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
        _ cube: ViewportProjectedBox?,
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
        _ box: ViewportProjectedBox?,
        color: Color,
        isHighlighted: Bool,
        fillOpacity: Double,
        in context: inout GraphicsContext
    ) {
        guard let box else { return }
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
        objectSelectionIndex.featureIDs
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
        if let sceneNodeID = item.sceneNodeID {
            return sceneNodeIDs.contains(sceneNodeID)
        }
        return featureIDs.contains(item.featureID)
    }

    private func objectSelectionTargets() -> [SelectionTarget] {
        objectSelectionIndex.objectTargets
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
        let patchDescriptors = polySplinePatchDescriptorsByFeatureID()
        return PolySplineSurfaceVertexSlideDirection.allCases.compactMap { direction in
            guard let geometry = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
                selectedVertices: inputs,
                topologyVertices: topologyVertices,
                patches: patchDescriptors,
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
        let patchDescriptors = polySplinePatchDescriptorsByFeatureID()
        return PolySplineSurfaceVertexSlideDirection.allCases.compactMap { direction in
            guard let geometry = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
                selectedControlPoints: inputs,
                topologyVertices: topologyVertices,
                patches: patchDescriptors,
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

    /// Patch corner tables derived from the current PolySpline source meshes.
    /// Display affordances resolve patch context through this table because
    /// vertex identities only carry the owning feature and source index.
    private func polySplinePatchDescriptorsByFeatureID() -> [FeatureID: [ViewportPolySplinePatchDescriptor]] {
        let tolerance = document.modelingSettings.tolerance
        var descriptorsByFeatureID: [FeatureID: [ViewportPolySplinePatchDescriptor]] = [:]
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case let .polySpline(polySpline) = feature.operation else {
                continue
            }
            let analysis = PolySplineMeshAnalyzer().analyze(
                mesh: polySpline.sourceMesh,
                options: polySpline.options,
                tolerance: tolerance
            )
            guard analysis.result.isSupported else {
                continue
            }
            descriptorsByFeatureID[featureID] = analysis.supportedPatches.map { patch in
                ViewportPolySplinePatchDescriptor(
                    candidateID: patch.candidateID,
                    cornerSourceVertexIndices: patch.boundaryVertexIndices
                )
            }
        }
        return descriptorsByFeatureID
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
        let subshapeID = controlPoint.surface.subshape.subshapeID
        let roleParts = subshapeID.role.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard roleParts.count == 2,
              roleParts[0] == "polySpline" else {
            return nil
        }
        let parts = roleParts[1].split(
            separator: ":",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 3,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "face" else {
            return nil
        }
        return (subshapeID.featureID, patchID)
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
            guard componentID.generatedTopologySubshapeID != nil else {
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
            guard componentID.generatedTopologySubshapeID != nil else {
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
        guard componentID.generatedTopologySubshapeID != nil else {
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

    private func selectedBodyItems(in scene: ViewportScene) -> [ViewportSceneItem] {
        objectSelectionIndex.selectedBodySourceItems(in: scene)
    }

    private func selectedBodyItem(
        for affordanceTarget: ViewportAffordanceTarget,
        in scene: ViewportScene
    ) -> ViewportSceneItem? {
        if let sceneNodeID = affordanceTarget.selectionTarget?.sceneNodeID {
            return scene.items.first { item in
                item.sceneNodeID == sceneNodeID && item.featureID == affordanceTarget.featureID
            }
        }
        return scene.items.first { item in
            item.sceneNodeID == nil && item.featureID == affordanceTarget.featureID
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
        hoveredAffordance?.featureID == featureID && hoveredAffordance?.action == action
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
            refreshSnapOverlayResolution(size: size)
        }
        if start == nil || current == nil {
            // Mouse-up clears the adapter preview before a replacement frame
            // may become ready. The input owner still owns that release.
            if case .active(let press) = nativeAxisGesture, press.finish != nil { return }
            clearPendingCanvasInteractionTargets()
            clearDragPreviewDocument()
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }
        guard let start, let current else {
            activeCanvasDrag = nil
            publishSelectionDragPreview(hits: [])
            return
        }
        if nativeAxisGesture != nil {
            _ = updateNativeAxisGesture(current: current)
            return
        }
        if let pendingInteractionTarget {
            updatePendingInteractionDrag(
                pendingInteractionTarget,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if hasActiveInteractionDrag {
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
        let sketchPlane = canvasDragSketchPlane(for: hoveredCanvasHit)
        let inputMapper = makeCoordinateMapper(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        activeCanvasDrag = ViewportActiveDrag(
            startLocation: start,
            currentLocation: current,
            kind: .creation(canvasDragPreviewKind),
            sketchPlane: sketchPlane,
            modelDrag: semanticCanvasModelDrag(
                from: start,
                to: current,
                mapper: inputMapper,
                sketchPlane: sketchPlane
            )
        )
    }

    /// Resolves the creation gesture at the input boundary.  The resulting
    /// world points and view-ray anchors remain stable when the camera changes
    /// before the RealityKit preparation worker consumes the snapshot.
    private func semanticCanvasModelDrag(
        from start: CGPoint,
        to end: CGPoint,
        mapper: ViewportModelCoordinateMapper,
        sketchPlane: SketchPlane
    ) -> ViewportModelDrag? {
        guard let startInput = canvasInput(
            for: start,
            exactWorldPoint: nil,
            sketchPlane: sketchPlane
        ), let endInput = canvasInput(
            for: end,
            exactWorldPoint: nil,
            sketchPlane: sketchPlane
        ) else {
            return nil
        }
        return ViewportModelDrag(
            start: startInput.point,
            end: endInput.point,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startInput.worldPoint,
            endWorldPoint: endInput.worldPoint,
            startViewRayAnchorWorldPoint: mapper.displayedCanvasWorldPoint(for: start),
            endViewRayAnchorWorldPoint: mapper.displayedCanvasWorldPoint(for: end)
        )
    }

    private func clearPendingCanvasInteractionTargets() {
        nativeAxisGesture = nil
        pendingInteractionTarget = nil
        clearDragPreviewDocument()
        clearAffordanceGhostEdits()
        clearActiveInteractionDrags()
    }

    private func clearDragPreviewDocument() {
        dragPreviewSceneNodeID = nil
        if dragPreviewDocument != nil {
            dragPreviewDocument = nil
            advanceDragPreviewRevision()
        }
        previewEvaluationCache.clear()
    }

    private func setDragPreviewDocument(_ previewDocument: DesignDocument, target: SelectionTarget) {
        dragPreviewDocument = previewDocument
        dragPreviewSceneNodeID = target.sceneNodeID
        advanceDragPreviewRevision()
        guard let documentGeneration = sceneDocumentGeneration else {
            previewEvaluationCache.clear()
            return
        }
        previewEvaluationCache.prepare(
            document: previewDocument,
            generation: documentGeneration,
            revision: dragPreviewRevision,
            reusing: publishedEvaluatedDocument,
            objectRegistry: objectRegistry
        )
    }

    private func advanceDragPreviewRevision() {
        if dragPreviewRevision == UInt64.max {
            dragPreviewRevision = 1
        } else {
            dragPreviewRevision += 1
        }
    }

    private func nativeAxisInput(at point: CGPoint) throws -> ViewportNativeAxisInput? {
        let records = try presentationPlanCache.interactionRecords(
            at: point, for: presentationQueryIdentity(), revision: activeControlSession.revision
        )
        guard let record = records.first else { return nil }
        return try ViewportNativeAxisInput(record: record)
    }

    private func nativeAxisRouteEnabled(_ target: ViewportSpatialPreparedInteractionTarget) -> Bool {
        switch target {
        case .splineControlPointSlide: onSplineControlPointSlideDrag != nil
        case .polySplineSurfaceVertexSlide: onPolySplineSurfaceVertexSlideDrag != nil
        case .surfaceControlPointSlide: onSurfaceControlPointSlideDrag != nil
        case .surfaceFrame: onSurfaceFrameDrag != nil
        case .regionOffset: onRegionOffsetDrag != nil
        case .edgeOffset: onEdgeOffsetDrag != nil
        case .slotWidth: onSlotWidthDrag != nil
        case .sketchVertexOffset: onSketchVertexOffsetDrag != nil
        default: false
        }
    }

    private var hoveredSpatialHandleIdentity: ViewportSpatialHandleIdentity? {
        get throws { try hoveredNativeAxisIdentity ?? hoveredInteractionTarget?.spatialIdentity }
    }

    private var pendingSpatialHandleIdentity: ViewportSpatialHandleIdentity? {
        get throws {
            if case .active(let press) = nativeAxisGesture { return press.input.record.identity }
            return try pendingInteractionTarget?.spatialIdentity
        }
    }

    private func cancelNativeAxisGesture() {
        guard nativeAxisGesture != nil else { return }
        nativeAxisGesture = .cancelled
        hoveredNativeAxisIdentity = nil
        activeCanvasDrag = nil
        clearActiveInteractionDrags()
        clearDragPreviewDocument()
        clearAffordanceGhostEdits()
    }

    private func nativeAxisBaselineMatches(_ input: ViewportNativeAxisInput) -> Bool {
        switch input.record.target {
        case .slotWidth: input.axis.baseValue == slotWidthMeters
        case .edgeOffset: input.axis.baseValue == edgeOffsetDistanceMeters
        case .sketchVertexOffset: input.axis.baseValue == sketchVertexOffsetDistanceMeters
        default: true
        }
    }

    private func cancelChangedNativeAxisBaseline() {
        if case .active(let press) = nativeAxisGesture, !nativeAxisBaselineMatches(press.input) {
            cancelNativeAxisGesture()
        }
    }

    private func updateNativeAxisGesture(current: CGPoint) -> Bool {
        guard case .active(var press) = nativeAxisGesture else { return false }
        guard press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              press.finish == nil || press.finish?.revision == activeControlSession.revision,
              nativeAxisBaselineMatches(press.input),
              nativeAxisRouteEnabled(press.input.record.target) else {
            cancelNativeAxisGesture()
            return false
        }
        do {
            let delta = try presentationPlanCache.worldAxisDelta(
                from: press.start, to: current,
                axisOrigin: press.input.axis.origin, axisDirection: press.input.axis.direction,
                for: presentationQueryIdentity(), revision: activeControlSession.revision
            )
            press.value = try press.input.value(forWorldDelta: delta)
            nativeAxisGesture = .active(press)
            return true
        } catch {
            // A self-preview may temporarily replace the native frame. Keep
            // the press baseline; no update or commit is authorized until ready.
            return false
        }
    }

    private func finishNativeAxisGesture(at point: CGPoint) {
        guard case .active(var press) = nativeAxisGesture else {
            clearPendingCanvasInteractionTargets()
            return
        }
        guard point.x.isFinite, point.y.isFinite else {
            cancelNativeAxisGesture()
            return
        }
        press.finish = (point, activeControlSession.revision)
        nativeAxisGesture = .active(press)
        resumeNativeAxisFinish()
    }

    private func resumeNativeAxisFinish() {
        guard case .active(let press) = nativeAxisGesture, let finish = press.finish else { return }
        guard finish.revision == activeControlSession.revision,
              press.source == sourceIdentity, press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              nativeAxisBaselineMatches(press.input), nativeAxisRouteEnabled(press.input.record.target) else {
            cancelNativeAxisGesture()
            return
        }
        let commit: ViewportNativeAxisInput.Commit?
        do {
            let identity = try presentationPreparation.get()
            if let failure = presentationPlanCache.failure(for: identity) { throw failure }
            guard presentationPlanCache.hasReadyCamera(for: identity, revision: finish.revision) else { return }
            if updateNativeAxisGesture(current: finish.point),
               case .active(let press) = nativeAxisGesture, let value = press.value {
                commit = try press.input.commit(value: value)
            } else { commit = nil }
        } catch {
            // Invalid native values never reach a source mutation callback.
            commit = nil
        }
        // Release input ownership before calling external mutation callbacks.
        clearPendingCanvasInteractionTargets()
        activeCanvasDrag = nil
        guard let commit else { return }
        switch commit {
        case .splineControlPointSlide(let target): onSplineControlPointSlideDrag?(target)
        case .polySplineSurfaceVertexSlide(let target): onPolySplineSurfaceVertexSlideDrag?(target)
        case .surfaceControlPointSlide(let target): onSurfaceControlPointSlideDrag?(target)
        case .surfaceFrame(let target): onSurfaceFrameDrag?(target)
        case .regionOffset(let target): onRegionOffsetDrag?(target)
        case .edgeOffset(let target): onEdgeOffsetDrag?(target)
        case .slotWidth(let target): onSlotWidthDrag?(target)
        case .sketchVertexOffset(let target): onSketchVertexOffsetDrag?(target)
        }
    }

    private func beginViewportPress(at point: CGPoint, size: CGSize) {
        if measurementToolActive {
            clearPendingCanvasInteractionTargets()
            activeCanvasDrag = nil
            return
        }
        clearPendingCanvasInteractionTargets()
        do {
            if let input = try nativeAxisInput(at: point) {
                guard nativeAxisRouteEnabled(input.record.target) else {
                    nativeAxisGesture = .cancelled
                    return
                }
                nativeAxisGesture = .active(.init(
                    input: input, source: sourceIdentity, snapshotID: presentationScene?.snapshotID,
                    selectedTargets: selection.selectedTargets,
                    selectedReferences: selection.selectedReferences, start: point
                ))
                activeCanvasDrag = nil
                return
            }
        } catch {
            nativeAxisGesture = .cancelled
            return
        }
        guard let target = resolvedInteractionTarget(at: point, size: size) else {
            clearPendingCanvasInteractionTargets()
            return
        }
        clearPendingCanvasInteractionTargets()
        setPendingInteractionTarget(target)
        activeCanvasDrag = nil
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Non-axis CAD routes still use legacy
    // selectors from press/hover. Full RK-4 input cutover requires replacing
    // those routes; migrated native axis routes are never resolved here.
    private func resolvedInteractionTarget(
        at point: CGPoint,
        size: CGSize,
        sceneContext: ViewportSceneContext? = nil
    ) -> ViewportInteractionTarget? {
        let sceneContext = sceneContext ?? makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        if let target = selectedSketchCurveHandleTarget(at: point, sceneContext: sceneContext) {
            return .sketchCurveHandle(target)
        }
        if let target = selectedSketchPointHandleTarget(at: point, sceneContext: sceneContext) {
            return .sketchPointHandle(target)
        }
        if let target = selectedSketchDimensionTarget(at: point, sceneContext: sceneContext) {
            return .sketchDimension(target)
        }
        if onBridgeCurveEndpointDrag != nil,
           let target = selectedBridgeCurveEndpointTarget(at: point, sceneContext: sceneContext) {
            return .bridgeCurveEndpoint(target)
        }
        if let target = selectedSplineControlPointTarget(at: point, sceneContext: sceneContext) {
            return .splineControlPoint(target)
        }
        if let target = selectedPolySplineSurfaceVertexTarget(at: point, sceneContext: sceneContext) {
            return .polySplineSurfaceVertex(target)
        }
        if let target = selectedSurfaceControlPointTarget(at: point, sceneContext: sceneContext) {
            return .surfaceControlPoint(target)
        }
        if let target = selectedSurfaceTrimEndpointTarget(at: point, sceneContext: sceneContext) {
            return .surfaceTrimEndpoint(target)
        }
        if let target = selectedSurfaceTrimControlPointTarget(at: point, sceneContext: sceneContext) {
            return .surfaceTrimControlPoint(target)
        }
        if let target = selectedIndependentCopyExtrudeDistanceAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .independentCopyExtrudeDistance(target)
        }
        if let target = selectedIndependentCopyBodyDimensionAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .independentCopyBodyDimension(target)
        }
        if let target = selectedPatternArrayLinearAxisAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayLinearAxis(target)
        }
        if let target = selectedPatternArrayRadialAngleAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayRadialAngle(target)
        }
        if let target = selectedPatternArrayCopyCountAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayCopyCount(target)
        }
        if let target = selectedPatternArrayCurveExtentAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayCurveExtent(target)
        }
        if let target = selectedPatternArrayCurvePathPointAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayCurvePathPoint(target)
        }
        if let target = selectedPatternArrayOutputModeAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .patternArrayOutputMode(target)
        }
        if let target = selectedConstructionPlaneHandleTarget(at: point, sceneContext: sceneContext) {
            return .constructionPlane(target)
        }
        if let target = selectedVertexAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .affordance(target)
        }
        if let target = selectedFaceAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .affordance(target)
        }
        if let target = selectedEdgeFilletAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .affordance(target)
        }
        if let target = selectedEdgeAffordanceTarget(at: point, sceneContext: sceneContext) {
            return .affordance(target)
        }
        guard allowsObjectAffordances else {
            return nil
        }
        return affordanceTarget(
            at: point,
            scene: sceneContext.scene,
            layout: sceneContext.layout
        ).map(ViewportInteractionTarget.affordance)
    }

    private func setPendingInteractionTarget(_ target: ViewportInteractionTarget) {
        pendingInteractionTarget = target
    }

    private func clearActiveInteractionDrags(except preservedTarget: ViewportInteractionTarget? = nil) {
        activeInteractionDrags.clear(except: preservedTarget)
    }

    private var hasActiveInteractionDrag: Bool {
        if case .active(let press) = nativeAxisGesture, press.value != nil { return true }
        return activeInteractionDrags.hasActiveDrag
    }

    private func updatePendingInteractionDrag(
        _ target: ViewportInteractionTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        clearActiveInteractionDrags(except: target)
        switch target {
        case .sketchCurveHandle(let target):
            updateSketchCurveHandleDrag(target: target, start: start, current: current, size: size)
        case .sketchDimension(let target):
            updateSketchDimensionDrag(target: target, start: start, current: current, size: size)
        case .sketchPointHandle(let target):
            updateSketchPointHandleDrag(target: target, start: start, current: current, size: size)
        case .bridgeCurveEndpoint(let target):
            updateBridgeCurveEndpointDrag(target: target, start: start, current: current, size: size)
        case .splineControlPoint(let target):
            updateSplineControlPointDrag(target: target, start: start, current: current, size: size)
        case .splineControlPointSlide(let target):
            updateSplineControlPointSlideDrag(target: target, start: start, current: current, size: size)
        case .polySplineSurfaceVertex(let target):
            updatePolySplineSurfaceVertexDrag(target: target, start: start, current: current, size: size)
        case .polySplineSurfaceVertexSlide(let target):
            updatePolySplineSurfaceVertexSlideDrag(target: target, start: start, current: current, size: size)
        case .surfaceControlPoint(let target):
            updateSurfaceControlPointDrag(target: target, start: start, current: current, size: size)
        case .surfaceControlPointSlide(let target):
            updateSurfaceControlPointSlideDrag(target: target, start: start, current: current, size: size)
        case .surfaceTrimEndpoint(let target):
            updateSurfaceTrimEndpointDrag(target: target, start: start, current: current, size: size)
        case .surfaceTrimControlPoint(let target):
            updateSurfaceTrimControlPointDrag(target: target, start: start, current: current, size: size)
        case .surfaceFrame(let target):
            updateSurfaceFrameDrag(target: target, start: start, current: current, size: size)
        case .regionOffset(let target):
            updateRegionOffsetDrag(target: target, start: start, current: current, size: size)
        case .edgeOffset(let target):
            updateEdgeOffsetDrag(target: target, start: start, current: current, size: size)
        case .slotWidth(let target):
            updateSlotWidthDrag(target: target, start: start, current: current, size: size)
        case .sketchVertexOffset(let target):
            updateSketchVertexOffsetDrag(target: target, start: start, current: current, size: size)
        case .patternArrayLinearAxis(let target):
            updatePatternArrayLinearAxisDrag(target: target, start: start, current: current)
        case .independentCopyExtrudeDistance(let target):
            updateIndependentCopyExtrudeDistanceDrag(target: target, start: start, current: current)
        case .independentCopyBodyDimension(let target):
            updateIndependentCopyBodyDimensionDrag(target: target, start: start, current: current)
        case .patternArrayRadialAngle(let target):
            updatePatternArrayRadialAngleDrag(target: target, start: start, current: current)
        case .patternArrayCopyCount(let target):
            updatePatternArrayCopyCountDrag(target: target, start: start, current: current)
        case .patternArrayCurveExtent(let target):
            updatePatternArrayCurveExtentDrag(target: target, start: start, current: current)
        case .patternArrayCurvePathPoint(let target):
            updatePatternArrayCurvePathPointDrag(target: target, start: start, current: current, size: size)
        case .patternArrayOutputMode:
            break
        case .constructionPlane(let target):
            updateConstructionPlaneHandleDrag(target: target, start: start, current: current, size: size)
        case .affordance(let target):
            updateAffordanceDrag(target: target, start: start, current: current, size: size)
        }
    }

    private func selectedSketchCurveHandleTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSketchCurveHandleTarget? {
        guard onSketchCurveHandleDrag != nil else {
            return nil
        }
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
                    guard let projected = layout.projectedPoint(handle.point)?.point else { continue }
                    let distance = point.distance(to: projected)
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSketchDimensionTarget? {
        guard onSketchDimensionDrag != nil else {
            return nil
        }
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
            guard let projectedStart = layout.projectedPoint(start)?.point,
                  let projectedEnd = layout.projectedPoint(end)?.point else { return [] }
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
            guard let radiusPoint = layout.projectedPoint(
                circleRadiusHandlePoint(center: center, radiusMeters: radiusMeters)
            )?.point else { return [] }
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
            guard let projectedCenter = layout.projectedPoint(center)?.point,
                  let projectedRadius = layout.projectedPoint(radiusPoint)?.point else { return [] }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSketchPointHandleTarget? {
        guard onSketchPointHandleDrag != nil else {
            return nil
        }
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
                    guard let projectedPoint = layout.projectedPoint(handle.point)?.point else { continue }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSplineControlPointHandleTarget? {
        guard onSplineControlPointDrag != nil else {
            return nil
        }
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
                    guard let projectedPoint = layout.projectedPoint(controlPoints[index])?.point else { continue }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPolySplineSurfaceVertexHandleTarget? {
        guard onPolySplineSurfaceVertexDrag != nil else {
            return nil
        }
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
            guard let projectedPoint = target.geometry.projectedPoint(layout: layout) else {
                continue
            }
            guard point.distance(to: projectedPoint) <= handleTolerance else {
                continue
            }
            return target
        }
        return nil
    }

    private func selectedSurfaceControlPointTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSurfaceControlPointHandleTarget? {
        guard onSurfaceControlPointDrag != nil else {
            return nil
        }
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
            guard let projectedPoint = target.geometry.projectedPoint(layout: layout) else {
                continue
            }
            guard point.distance(to: projectedPoint) <= handleTolerance else {
                continue
            }
            return target
        }
        return nil
    }

    private func selectedSurfaceTrimEndpointTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSurfaceTrimEndpointHandleTarget? {
        guard onSurfaceTrimEndpointDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        var nearest: (target: ViewportSurfaceTrimEndpointHandleTarget, distance: CGFloat)?
        for target in surfaceTrimEndpointHandleTargets(in: scene) {
            guard let projectedPoint = target.geometry.projectedPoint(layout: layout) else {
                continue
            }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportBridgeCurveEndpointHandleTarget? {
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSurfaceTrimControlPointHandleTarget? {
        guard onSurfaceTrimControlPointDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let handleTolerance: CGFloat = 12.0
        var nearest: (target: ViewportSurfaceTrimControlPointHandleTarget, distance: CGFloat)?
        for target in surfaceTrimControlPointHandleTargets(in: scene) {
            guard let projectedPoint = target.geometry.projectedPoint(layout: layout) else {
                continue
            }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPolySplineSurfaceVertexSlideHandleTarget? {
        guard onPolySplineSurfaceVertexSlideDrag != nil else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedSurfaceControlPointSlideAffordanceTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSurfaceControlPointSlideHandleTarget? {
        guard onSurfaceControlPointSlideDrag != nil else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func selectedSurfaceFrameAffordanceTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSurfaceFrameHandleTarget? {
        guard onSurfaceFrameDrag != nil else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
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
        guard let center = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return nil }
        guard let endpoint = candidate.geometry.projectedTip(layout: layout) else { return nil }
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
        guard let center = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return nil }
        guard let endpoint = candidate.geometry.projectedTip(layout: layout) else { return nil }
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
        guard let center = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { return nil }
        guard let endpoint = candidate.geometry.projectedTip(layout: layout) else { return nil }
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
        guard let center = target.geometry.projectedPoint(layout: layout) else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
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
        guard let center = target.geometry.projectedPoint(layout: layout) else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
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
        guard let center = target.geometry.projectedPoint(layout: layout) else {
            return nil
        }
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
            if nearest.map({ distance < $0.distance }) ?? true {
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
        sceneContext: ViewportSceneContext
    ) -> ViewportAffordanceTarget? {
        guard onVertexDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportAffordanceTarget? {
        guard onFaceDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportAffordanceTarget? {
        guard onEdgeChamferDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportAffordanceTarget? {
        guard onEdgeFilletDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportRegionOffsetHandleTarget? {
        guard onRegionOffsetDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = regionOffsetAffordanceCandidates(
            targets: selectedSketchRegionTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { continue }
            guard let end = candidate.geometry.projectedTip(layout: layout) else { continue }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportEdgeOffsetHandleTarget? {
        guard onEdgeOffsetDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSlotWidthHandleTarget? {
        guard onSlotWidthDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = slotWidthAffordanceCandidates(
            targets: selectedSlotWidthSourceTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { continue }
            guard let end = candidate.geometry.projectedTip(layout: layout) else { continue }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayLinearAxisHandleTarget? {
        guard onPatternArrayLinearAxisDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportIndependentCopyExtrudeDistanceHandleTarget? {
        guard onIndependentCopyExtrudeDistanceDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportIndependentCopyBodyDimensionHandleTarget? {
        guard onIndependentCopyBodyDimensionDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayRadialAngleHandleTarget? {
        guard onPatternArrayRadialAngleDrag != nil else {
            return nil
        }
        let candidates = patternArrayRadialAngleAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            let arcPoints = candidate.geometry.projectedArcPoints()
            guard let tip = candidate.geometry.projectedTip() else { continue }
            let arcHit = point.distanceToPolyline(arcPoints) <= 10.0
            let tipHit = point.distance(to: tip) <= 14.0
            if arcHit || tipHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayCopyCountAffordanceTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayCopyCountHandleTarget? {
        guard onPatternArrayCopyCountDrag != nil else {
            return nil
        }
        let candidates = patternArrayCopyCountAffordanceCandidates(
            scene: sceneContext.scene,
            layout: sceneContext.layout
        )
        for candidate in candidates.reversed() {
            guard let handlePoint = candidate.geometry.handlePoint else { continue }
            let handleHit = point.distance(to: handlePoint) <= 14.0
            let guideHit = point.distanceToPolyline(candidate.geometry.guidePoints()) <= 10.0
            if handleHit || guideHit {
                return candidate.target
            }
        }
        return nil
    }

    private func selectedPatternArrayCurveExtentAffordanceTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayCurveExtentHandleTarget? {
        guard onPatternArrayCurveExtentDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayCurvePathPointHandleTarget? {
        guard onPatternArrayCurvePathPointDrag != nil else {
            return nil
        }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportPatternArrayOutputModeHandleTarget? {
        guard onPatternArrayOutputModeChange != nil else {
            return nil
        }
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

    private func selectedConstructionPlaneHandleTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportConstructionPlaneHandleTarget? {
        guard onConstructionPlaneHandleDrag != nil else {
            return nil
        }
        return ViewportConstructionPlaneHandleGeometry().target(
            at: point,
            document: document,
            ruler: workspaceRuler,
            selection: selection,
            layout: sceneContext.layout
        )
    }

    private func selectedSketchVertexOffsetAffordanceTarget(
        at point: CGPoint,
        sceneContext: ViewportSceneContext
    ) -> ViewportSketchVertexOffsetHandleTarget? {
        guard onSketchVertexOffsetDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = sketchVertexOffsetAffordanceCandidates(
            targets: selectedSketchVertexOffsetSourceTargets(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { continue }
            guard let end = candidate.geometry.projectedTip(layout: layout) else { continue }
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
        sceneContext: ViewportSceneContext
    ) -> ViewportSplineControlPointSlideHandleTarget? {
        guard onSplineControlPointSlideDrag != nil else {
            return nil
        }
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let candidates = splineControlPointSlideAffordanceCandidates(
            groups: selectedSplineControlPointGroups(),
            scene: scene,
            layout: layout
        )
        for candidate in candidates.reversed() {
            guard let start = layout.projectedPoint(candidate.geometry.baseModelPoint)?.point else { continue }
            guard let end = candidate.geometry.projectedTip(layout: layout) else { continue }
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
        let selectedBodyItems = selectedBodyItems(in: scene)
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

        for item in selectedBodyItems.reversed() {
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
            selectionTarget: objectSelectionIndex.exactTarget(for: item),
            edit: edit,
            layout: layout
        )
    }

    private func bodyAffordanceTarget(
        point: CGPoint,
        featureID: FeatureID,
        selectionTarget: SelectionTarget? = nil,
        edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        guard let bodyBounds = edit.projectedBodyProjection(layout: layout)?.hitBounds else { return nil }
        let modelCenter = edit.centerPoint
        guard let center = edit.projectedPoint(modelCenter, layout: layout),
              let affordanceBasis = edit.projectedAxisBasis(layout: layout) else { return nil }
        let radius = max(28.0, min(72.0, min(bodyBounds.width, bodyBounds.height) * 0.38))
        let axisLength = bodyAffordanceAxisLength(for: radius)
        let endScaleLength = bodyAffordanceEndScaleLength(
            axisLength: axisLength,
            rotationRadius: radius
        )
        let handleTolerance: CGFloat = 10.0

        for axis in ViewportCoordinateAxis.allCases {
            guard let endLength = edit.modelLength(forViewportLength: endScaleLength, axis: axis, layout: layout),
                  let centerLength = edit.modelLength(forViewportLength: radius, axis: axis, layout: layout) else { continue }
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: endLength
                ),
                layout: layout
            )
            if let endpoint, point.distance(to: endpoint) <= handleTolerance {
                return ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: selectionTarget,
                    action: .oneSidedScale(axis)
                )
            }

            let centerScalePoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: centerLength
                ),
                layout: layout
            )
            if let centerScalePoint, point.distance(to: centerScalePoint) <= handleTolerance {
                return ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: selectionTarget,
                    action: .centerScale(axis)
                )
            }
        }

        for handle in bodyVertexHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: selectionTarget,
                    action: .vertexMove(handle.vertex)
                )
            }
        }

        for handle in bodyFaceCenterHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: selectionTarget,
                    action: .faceMove(handle.face)
                )
            }
        }

        if let axis = rotationAffordanceAxis(
            point: point,
            center: center,
            radius: radius,
            basis: affordanceBasis
        ) {
            return ViewportAffordanceTarget(
                featureID: featureID,
                selectionTarget: selectionTarget,
                action: .rotate(axis)
            )
        }

        for axis in ViewportCoordinateAxis.allCases {
            guard let axisModelLength = edit.modelLength(forViewportLength: axisLength, axis: axis, layout: layout) else { continue }
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: axisModelLength
                ),
                layout: layout
            )
            if let endpoint, point.distanceToSegment(start: center, end: endpoint) <= 7.0 {
                return ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: selectionTarget,
                    action: .translate(axis)
                )
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


    /// Gizmo actions without a commit path (translate, rotate, scale) must not
    /// leave their drag preview behind: a stale editedBodies entry permanently
    /// displaces the gizmo, the face and edge highlights, and the affordance
    /// hit areas for the body, making it look unselectable.
    private func clearAffordanceGhostEdits() {
        guard let activeAffordanceDrag else {
            return
        }
        for featureID in activeAffordanceDrag.baseEdits.keys {
            editedBodies.removeValue(forKey: featureID)
        }
    }

    private func updateEdgeTreatmentDragPreview(
        target: ViewportAffordanceTarget,
        dragState: ViewportAffordanceDragState,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Bool {
        switch target.action {
        case .profileEdgeChamfer(let selectionTarget, let edge):
            guard let baseEdit = dragState.baseEdits[target.featureID],
                  let distance = baseEdit.profileEdgeChamferDistance(
                      edge,
                      start: dragState.startPoint,
                      current: current,
                      layout: layout
                  ),
                  distance > 1.0e-12 else {
                clearDragPreviewDocument()
                return true
            }
            updateEdgeTreatmentPreviewDocument(
                request: .chamfer(
                    target: selectionTarget,
                    distance: Double(distance)
                )
            )
            return true
        case .profileEdgeFillet(let selectionTarget, let edge):
            guard let baseEdit = dragState.baseEdits[target.featureID],
                  let radius = baseEdit.profileEdgeFilletRadius(
                      edge,
                      start: dragState.startPoint,
                      current: current,
                      layout: layout
                  ),
                  radius > 1.0e-12 else {
                clearDragPreviewDocument()
                return true
            }
            updateEdgeTreatmentPreviewDocument(
                request: .fillet(
                    target: selectionTarget,
                    radius: Double(radius),
                    segmentCount: 8
                )
            )
            return true
        default:
            clearDragPreviewDocument()
            return false
        }
    }

    private func updateEdgeTreatmentPreviewDocument(
        request: ViewportEdgeTreatmentPreviewRequest
    ) {
        do {
            setDragPreviewDocument(
                try ViewportEdgeTreatmentPreviewDocumentBuilder(
                    objectRegistry: objectRegistry
                ).previewDocument(
                    for: request,
                    in: document
                ),
                target: request.target
            )
        } catch {
            clearDragPreviewDocument()
            previewEvaluationCache.fail(revision: dragPreviewRevision, message: error.localizedDescription)
        }
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
            basis: currentProjectionBasis,
            usesDragPreviewDocument: false
        )
        let scene = sceneContext.scene
        let layout = sceneContext.layout
        let selectedFeatureIDs = selectedObjectFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene)
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
                guard let item = selectedBodyItem(for: target, in: scene),
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

        if updateEdgeTreatmentDragPreview(
            target: target,
            dragState: dragState,
            current: current,
            layout: layout
        ) {
            return
        }

        if let baseGroupEdit = dragState.baseGroupEdit {
            guard let nextGroupEdit = baseGroupEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            ) else { return }
            for (featureID, baseEdit) in dragState.baseEdits {
                editedBodies[featureID] = baseEdit.transformedFromGroup(
                    baseGroup: baseGroupEdit,
                    targetGroup: nextGroupEdit
                )
            }
        } else if let baseEdit = dragState.baseEdits[target.featureID] {
            guard let next = baseEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            ) else { return }
            editedBodies[target.featureID] = next
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
        guard let startPoint = layout.canvasCoordinates(for: start),
              let currentPoint = layout.canvasCoordinates(for: current) else { return }
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
        guard let delta = target.geometry.localPlanarDelta(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
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
        guard let projectedPoint = projectedBridgeCurveEndpointPoint(
            projection.point,
            modelTransform: target.modelTransform,
            layout: layout
        ) else {
            return
        }
        guard let projectedTangentTip = ViewportBridgeCurveEndpointAffordanceService.projectedTangentTip(
            point: projection.point,
            outgoingTangent: projection.outgoingTangent,
            modelTransform: target.modelTransform,
            layout: layout
        ) else {
            return
        }
        activeBridgeCurveEndpointDrag = ViewportBridgeCurveEndpointDragState(
            target: target,
            startPoint: start,
            endpoint: projection.endpoint,
            parameter: projection.parameter,
            projectedPoint: projectedPoint,
            projectedTangentTip: projectedTangentTip
        )
    }

    private func projectedBridgeCurveEndpointPoint(
        _ point: Point2D,
        modelTransform: Transform3D,
        layout: ViewportLayout
    ) -> CGPoint? {
        layout.projectedPoint(modelTransform.viewportTransformedPoint(Point3D(
            x: point.x,
            y: 0.0,
            z: point.y
        )))?.point
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
        guard let distanceMeters = target.geometry.slideDistance(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeSplineControlPointSlideDrag = ViewportSplineControlPointSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
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
        guard let distanceMeters = target.geometry.slideDistance(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activePolySplineSurfaceVertexSlideDrag = ViewportPolySplineSurfaceVertexSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
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
        guard let distanceMeters = target.geometry.slideDistance(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeSurfaceControlPointSlideDrag = ViewportSurfaceControlPointSlideDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
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
        guard let distanceMeters = target.geometry.dragDistance(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeSurfaceFrameDrag = ViewportSurfaceFrameDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
        )
    }

    private func updateConstructionPlaneHandleDrag(
        target: ViewportConstructionPlaneHandleTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let layout = makeLayout(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        guard let dragTarget = ViewportConstructionPlaneHandleGeometry().draggedTarget(
            target: target,
            start: start,
            current: current,
            layout: layout
        ) else {
            activeConstructionPlaneHandleDrag = nil
            return
        }
        let snappedTarget = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
            dragTarget,
            sourceTarget: target,
            screenPoint: current,
            document: document,
            ruler: workspaceRuler,
            options: snapResolutionOptions,
            layout: layout
        )
        activeConstructionPlaneHandleDrag = ViewportConstructionPlaneHandleDragState(
            target: target,
            startPoint: start,
            origin: snappedTarget.origin,
            normal: snappedTarget.normal
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
            guard let value = target.geometry.localPlanarDelta(
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
        case .axis(let axis):
            guard let value = target.geometry.localDelta(
                axis: axis,
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
        case .localAxis(_, let direction):
            guard let value = target.geometry.localDelta(
                direction: direction,
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
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
            guard let value = target.geometry.localPlanarDelta(
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
        case .axis(let axis):
            guard let value = target.geometry.localDelta(
                axis: axis,
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
        case .localAxis(_, let direction):
            guard let value = target.geometry.localDelta(
                direction: direction,
                start: start,
                current: current,
                layout: layout
            ) else {
                return
            }
            delta = value
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
        guard let delta = target.geometry.localPlanarDelta(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
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
        guard let delta = target.geometry.localPlanarDelta(
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
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
        guard let distanceMeters = regionOffsetDistance(
            target: target,
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeRegionOffsetDrag = ViewportRegionOffsetDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
        )
    }

    private func regionOffsetDistance(
        target: ViewportRegionOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
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
        guard let widthMeters = slotWidth(
            target: target,
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeSlotWidthDrag = ViewportSlotWidthDragState(
            target: target,
            startPoint: start,
            widthMeters: widthMeters
        )
    }

    private func slotWidth(
        target: ViewportSlotWidthHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
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
        guard let angleRadians = target.geometry.angleRadians(
            start: start,
            current: current
        ) else {
            return
        }
        activePatternArrayRadialAngleDrag = ViewportPatternArrayRadialAngleDragState(
            target: target,
            startPoint: start,
            angleRadians: angleRadians
        )
    }

    private func updatePatternArrayCopyCountDrag(
        target: ViewportPatternArrayCopyCountHandleTarget,
        start: CGPoint,
        current: CGPoint
    ) {
        guard let copyCount = target.geometry.copyCount(
            start: start,
            current: current
        ) else {
            return
        }
        activePatternArrayCopyCountDrag = ViewportPatternArrayCopyCountDragState(
            target: target,
            startPoint: start,
            copyCount: copyCount
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
        guard let startPoint = layout.canvasCoordinates(for: start),
              let currentPoint = layout.canvasCoordinates(for: current) else { return }
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
        guard let distanceMeters = sketchVertexOffsetDistance(
            target: target,
            start: start,
            current: current,
            layout: layout
        ) else {
            return
        }
        activeSketchVertexOffsetDrag = ViewportSketchVertexOffsetDragState(
            target: target,
            startPoint: start,
            distanceMeters: distanceMeters
        )
    }

    private func sketchVertexOffsetDistance(
        target: ViewportSketchVertexOffsetHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
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
        guard let startPoint = layout.canvasCoordinates(for: start),
              let currentPoint = layout.canvasCoordinates(for: current) else { return }
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
        guard let currentPoint = layout.canvasCoordinates(for: current) else { return }
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
        guard let startPoint = layout.canvasCoordinates(for: start),
              let currentPoint = layout.canvasCoordinates(for: current) else { return }
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
        if nativeAxisGesture != nil {
            clearPendingCanvasInteractionTargets()
            return
        }
        if measurementToolActive {
            handleMeasurementClick(at: point)
            return
        }
        if let pendingInteractionTarget {
            finishPendingInteractionClick(pendingInteractionTarget)
            return
        }
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        var presentationOccurrenceID: SceneOccurrenceID?
        if let presentationScene {
            do {
                presentationOccurrenceID = try presentationSurfaceHit(at: point)?.triangle.occurrenceID
            } catch {
                // An unavailable frame cannot authorize selection or an edit.
                return
            }
            if let onMeshElementPick {
                let hit: ViewportMeshElementHit?
                do {
                    hit = try presentationPlanCache.meshElement(
                        at: point, domain: meshSelectionDomain,
                        for: presentationQueryIdentity(), revision: activeControlSession.revision
                    )
                } catch {
                    // An unavailable frame cannot authorize selection or an edit.
                    return
                }
                onMeshElementPick(hit, selectionIntent)
                if hit != nil { return }
            }
            if onMeshElementPick != nil,
               let occurrenceID = presentationOccurrenceID,
               let item = presentationScene.items.first(where: { $0.occurrenceID == occurrenceID }),
               case .authoredMesh = item.sourceReference {
                // Missing an element in this domain is not a CAD-object selection.
                return
            }
            if let occurrenceID = presentationOccurrenceID,
               let onPresentationOccurrencePick {
                onPresentationOccurrencePick(occurrenceID, selectionIntent)
                return
            }
        }
        guard let onPick else {
            return
        }
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        let hit = presentationFilteredLegacyHit(
            viewportHit(
                point: point,
                in: sceneBySuppressingSketches(
                    scene,
                    selectedFeatureIDs: selectedTargetFeatureIDs()
                ),
                layout: mapper.layout
            ),
            presentationOccurrenceID: presentationOccurrenceID
        )
        let sketchPlane = constructionSketchPlane(for: hit)
        let exactWorldPoint = selectedPresentationHasExactCADContext
            ? selectedGeneratedFaceSurfaceWorldPoint(
                at: point,
                in: scene,
                layout: mapper.layout
            )
            : nil
        let input = canvasInput(
            for: point,
            exactWorldPoint: exactWorldPoint,
            sketchPlane: sketchPlane
        )
        guard let input else {
            return
        }
        onPick(
            ViewportCanvasTarget(
                hit: hit,
                modelPoint: input.point,
                modelWorldPoint: exactWorldPoint,
                viewRayAnchorWorldPoint: mapper.displayedCanvasWorldPoint(for: point),
                sketchPlane: sketchPlane,
                selectionIntent: selectionIntent,
                modifierFlags: modifierFlags
            )
        )
    }

    private func finishPendingInteractionClick(_ target: ViewportInteractionTarget) {
        pendingInteractionTarget = nil
        switch target {
        case .sketchCurveHandle:
            activeSketchCurveHandleDrag = nil
        case .sketchDimension:
            activeSketchDimensionDrag = nil
        case .sketchPointHandle:
            activeSketchPointHandleDrag = nil
        case .bridgeCurveEndpoint:
            activeBridgeCurveEndpointDrag = nil
            activeCanvasDrag = nil
        case .splineControlPoint:
            activeSplineControlPointDrag = nil
        case .splineControlPointSlide:
            activeSplineControlPointSlideDrag = nil
        case .polySplineSurfaceVertex:
            activePolySplineSurfaceVertexDrag = nil
        case .polySplineSurfaceVertexSlide:
            activePolySplineSurfaceVertexSlideDrag = nil
        case .surfaceControlPoint:
            activeSurfaceControlPointDrag = nil
        case .surfaceControlPointSlide:
            activeSurfaceControlPointSlideDrag = nil
        case .surfaceTrimEndpoint:
            activeSurfaceTrimEndpointDrag = nil
        case .surfaceTrimControlPoint:
            activeSurfaceTrimControlPointDrag = nil
        case .surfaceFrame:
            activeSurfaceFrameDrag = nil
        case .regionOffset:
            activeRegionOffsetDrag = nil
        case .edgeOffset:
            activeEdgeOffsetDrag = nil
        case .slotWidth:
            activeSlotWidthDrag = nil
        case .sketchVertexOffset:
            activeSketchVertexOffsetDrag = nil
        case .patternArrayLinearAxis:
            activePatternArrayLinearAxisDrag = nil
        case .independentCopyExtrudeDistance:
            activeIndependentCopyExtrudeDistanceDrag = nil
        case .independentCopyBodyDimension:
            activeIndependentCopyBodyDimensionDrag = nil
        case .patternArrayRadialAngle:
            activePatternArrayRadialAngleDrag = nil
        case .patternArrayCopyCount:
            activePatternArrayCopyCountDrag = nil
        case .patternArrayCurveExtent:
            activePatternArrayCurveExtentDrag = nil
        case .patternArrayCurvePathPoint:
            activePatternArrayCurvePathPointDrag = nil
        case .patternArrayOutputMode(let target):
            activeCanvasDrag = nil
            onPatternArrayOutputModeChange?(target.commitTarget)
        case .constructionPlane:
            activeConstructionPlaneHandleDrag = nil
            activeCanvasDrag = nil
        case .affordance:
            clearAffordanceGhostEdits()
            activeAffordanceDrag = nil
        }
    }

    private func handleCanvasDrag(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if nativeAxisGesture != nil {
            finishNativeAxisGesture(at: end)
            return
        }
        if measurementToolActive {
            activeCanvasDrag = nil
            return
        }
        if finishInteractionDragIfNeeded(end: end, size: size) {
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
        guard let drag = canvasModelDrag(
            from: start,
            to: end,
            mapper: mapper,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startExactWorldPoint: selectedGeneratedFaceSurfaceWorldPoint(
                at: start,
                in: scene,
                layout: mapper.layout
            ),
            endExactWorldPoint: selectedGeneratedFaceSurfaceWorldPoint(
                at: end,
                in: scene,
                layout: mapper.layout
            )
        ) else {
            return
        }
        onCanvasDrag(drag)
    }

    private func finishInteractionDragIfNeeded(end: CGPoint, size: CGSize) -> Bool {
        let hasPendingTarget = pendingInteractionTarget != nil
        let request = ViewportInteractionDragFinishResolver.request(
            pendingTarget: pendingInteractionTarget,
            activeInteractionDrags: activeInteractionDrags
        )
        if hasPendingTarget {
            pendingInteractionTarget = nil
        }

        switch request {
        case .none:
            return false
        case .clearCanvasDrag:
            activeCanvasDrag = nil
            return true
        case .finish(let finishKind):
            finishInteractionDrag(finishKind, end: end, size: size)
            return true
        }
    }

    private func finishInteractionDrag(
        _ finishKind: ViewportActiveInteractionDragKind,
        end: CGPoint,
        size: CGSize
    ) {
        switch finishKind {
        case .sketchCurveHandle:
            finishSketchCurveHandleDrag()
        case .sketchDimension:
            finishSketchDimensionDrag()
        case .sketchPointHandle:
            finishSketchPointHandleDrag()
        case .bridgeCurveEndpoint:
            finishBridgeCurveEndpointDrag()
        case .splineControlPointSlide:
            finishSplineControlPointSlideDrag()
        case .polySplineSurfaceVertexSlide:
            finishPolySplineSurfaceVertexSlideDrag()
        case .surfaceControlPointSlide:
            finishSurfaceControlPointSlideDrag()
        case .surfaceFrame:
            finishSurfaceFrameDrag()
        case .splineControlPoint:
            finishSplineControlPointDrag()
        case .polySplineSurfaceVertex:
            finishPolySplineSurfaceVertexDrag()
        case .surfaceControlPoint:
            finishSurfaceControlPointDrag()
        case .surfaceTrimEndpoint:
            finishSurfaceTrimEndpointDrag()
        case .surfaceTrimControlPoint:
            finishSurfaceTrimControlPointDrag()
        case .edgeOffset:
            finishEdgeOffsetDrag()
        case .slotWidth:
            finishSlotWidthDrag()
        case .independentCopyExtrudeDistance:
            finishIndependentCopyExtrudeDistanceDrag()
        case .independentCopyBodyDimension:
            finishIndependentCopyBodyDimensionDrag()
        case .patternArrayLinearAxis:
            finishPatternArrayLinearAxisDrag()
        case .patternArrayRadialAngle:
            finishPatternArrayRadialAngleDrag()
        case .patternArrayCopyCount:
            finishPatternArrayCopyCountDrag()
        case .patternArrayCurveExtent:
            finishPatternArrayCurveExtentDrag()
        case .patternArrayCurvePathPoint:
            finishPatternArrayCurvePathPointDrag()
        case .constructionPlane:
            finishConstructionPlaneHandleDrag()
        case .sketchVertexOffset:
            finishSketchVertexOffsetDrag()
        case .regionOffset:
            finishRegionOffsetDrag()
        case .affordance:
            finishAffordanceInteractionDrag(end: end, size: size)
        }
    }

    private func finishSketchCurveHandleDrag() {
        let target = committedSketchCurveHandleDragTarget()
        activeSketchCurveHandleDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSketchCurveHandleDrag?(target)
        }
    }

    private func finishSketchDimensionDrag() {
        let target = committedSketchDimensionDragTarget()
        activeSketchDimensionDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSketchDimensionDrag?(target)
        }
    }

    private func finishSketchPointHandleDrag() {
        let target = committedSketchPointHandleDragTarget()
        activeSketchPointHandleDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSketchPointHandleDrag?(target)
        }
    }

    private func finishBridgeCurveEndpointDrag() {
        let target = committedBridgeCurveEndpointDragTarget()
        activeBridgeCurveEndpointDrag = nil
        activeCanvasDrag = nil
        publishSelectionDragPreview(hits: [])
        if let target {
            onBridgeCurveEndpointDrag?(target)
        }
    }

    private func finishSplineControlPointDrag() {
        let target = committedSplineControlPointDragTarget()
        activeSplineControlPointDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSplineControlPointDrag?(target)
        }
    }

    private func finishSplineControlPointSlideDrag() {
        let target = committedSplineControlPointSlideDragTarget()
        activeSplineControlPointSlideDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSplineControlPointSlideDrag?(target)
        }
    }

    private func finishPolySplineSurfaceVertexDrag() {
        let target = committedPolySplineSurfaceVertexDragTarget()
        activePolySplineSurfaceVertexDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPolySplineSurfaceVertexDrag?(target)
        }
    }

    private func finishPolySplineSurfaceVertexSlideDrag() {
        let target = committedPolySplineSurfaceVertexSlideDragTarget()
        activePolySplineSurfaceVertexSlideDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPolySplineSurfaceVertexSlideDrag?(target)
        }
    }

    private func finishSurfaceControlPointDrag() {
        let target = committedSurfaceControlPointDragTarget()
        activeSurfaceControlPointDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSurfaceControlPointDrag?(target)
        }
    }

    private func finishSurfaceControlPointSlideDrag() {
        let target = committedSurfaceControlPointSlideDragTarget()
        activeSurfaceControlPointSlideDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSurfaceControlPointSlideDrag?(target)
        }
    }

    private func finishSurfaceTrimEndpointDrag() {
        let target = committedSurfaceTrimEndpointDragTarget()
        activeSurfaceTrimEndpointDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSurfaceTrimEndpointDrag?(target)
        }
    }

    private func finishSurfaceTrimControlPointDrag() {
        let target = committedSurfaceTrimControlPointDragTarget()
        activeSurfaceTrimControlPointDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSurfaceTrimControlPointDrag?(target)
        }
    }

    private func finishSurfaceFrameDrag() {
        let target = committedSurfaceFrameDragTarget()
        activeSurfaceFrameDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSurfaceFrameDrag?(target)
        }
    }

    private func finishRegionOffsetDrag() {
        let target = committedRegionOffsetDragTarget()
        activeRegionOffsetDrag = nil
        activeCanvasDrag = nil
        if let target {
            onRegionOffsetDrag?(target)
        }
    }

    private func finishEdgeOffsetDrag() {
        let target = committedEdgeOffsetDragTarget()
        activeEdgeOffsetDrag = nil
        activeCanvasDrag = nil
        if let target {
            onEdgeOffsetDrag?(target)
        }
    }

    private func finishSlotWidthDrag() {
        let target = committedSlotWidthDragTarget()
        activeSlotWidthDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSlotWidthDrag?(target)
        }
    }

    private func finishSketchVertexOffsetDrag() {
        let target = committedSketchVertexOffsetDragTarget()
        activeSketchVertexOffsetDrag = nil
        activeCanvasDrag = nil
        if let target {
            onSketchVertexOffsetDrag?(target)
        }
    }

    private func finishPatternArrayLinearAxisDrag() {
        let target = committedPatternArrayLinearAxisDragTarget()
        activePatternArrayLinearAxisDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPatternArrayLinearAxisDrag?(target)
        }
    }

    private func finishIndependentCopyExtrudeDistanceDrag() {
        let target = committedIndependentCopyExtrudeDistanceDragTarget()
        activeIndependentCopyExtrudeDistanceDrag = nil
        activeCanvasDrag = nil
        if let target {
            onIndependentCopyExtrudeDistanceDrag?(target)
        }
    }

    private func finishIndependentCopyBodyDimensionDrag() {
        let target = committedIndependentCopyBodyDimensionDragTarget()
        activeIndependentCopyBodyDimensionDrag = nil
        activeCanvasDrag = nil
        if let target {
            onIndependentCopyBodyDimensionDrag?(target)
        }
    }

    private func finishPatternArrayRadialAngleDrag() {
        let target = committedPatternArrayRadialAngleDragTarget()
        activePatternArrayRadialAngleDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPatternArrayRadialAngleDrag?(target)
        }
    }

    private func finishPatternArrayCopyCountDrag() {
        let target = committedPatternArrayCopyCountDragTarget()
        activePatternArrayCopyCountDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPatternArrayCopyCountDrag?(target)
        }
    }

    private func finishPatternArrayCurveExtentDrag() {
        let target = committedPatternArrayCurveExtentDragTarget()
        activePatternArrayCurveExtentDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPatternArrayCurveExtentDrag?(target)
        }
    }

    private func finishPatternArrayCurvePathPointDrag() {
        let target = committedPatternArrayCurvePathPointDragTarget()
        activePatternArrayCurvePathPointDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPatternArrayCurvePathPointDrag?(target)
        }
    }

    private func finishConstructionPlaneHandleDrag() {
        let target = committedConstructionPlaneHandleDragTarget()
        activeConstructionPlaneHandleDrag = nil
        activeCanvasDrag = nil
        if let target {
            onConstructionPlaneHandleDrag?(target)
        }
    }

    private func finishAffordanceInteractionDrag(end: CGPoint, size: CGSize) {
        let ghostFeatureIDs = activeAffordanceDrag.map { Array($0.baseEdits.keys) } ?? []
        let bodyMoveDragTarget = committedBodyMoveDragTarget()
        let vertexDragTarget = committedVertexDragTarget(to: end, size: size)
        let faceDragTarget = committedFaceDragTarget(to: end, size: size)
        let edgeChamferDragTarget = committedEdgeChamferDragTarget(to: end, size: size)
        let edgeFilletDragTarget = committedEdgeFilletDragTarget(to: end, size: size)
        activeAffordanceDrag = nil
        activeCanvasDrag = nil
        clearDragPreviewDocument()
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
        if let bodyMoveDragTarget {
            editedBodies.removeValue(forKey: bodyMoveDragTarget.featureID)
            onBodyMoveDrag?(bodyMoveDragTarget.target)
        }
        for featureID in ghostFeatureIDs {
            editedBodies.removeValue(forKey: featureID)
        }
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

    private func committedConstructionPlaneHandleDragTarget() -> ViewportConstructionPlaneDragTarget? {
        guard let activeConstructionPlaneHandleDrag else {
            return nil
        }
        switch activeConstructionPlaneHandleDrag.target.handle {
        case .origin:
            guard pointDistance(
                activeConstructionPlaneHandleDrag.origin,
                activeConstructionPlaneHandleDrag.target.origin
            ) > 1.0e-12 else {
                return nil
            }
        case .normal:
            guard vectorDistance(
                activeConstructionPlaneHandleDrag.normal,
                activeConstructionPlaneHandleDrag.target.normal
            ) > 1.0e-12 else {
                return nil
            }
        }
        return ViewportConstructionPlaneDragTarget(
            constructionPlaneID: activeConstructionPlaneHandleDrag.target.constructionPlaneID,
            sceneNodeID: activeConstructionPlaneHandleDrag.target.sceneNodeID,
            handle: activeConstructionPlaneHandleDrag.target.handle,
            origin: activeConstructionPlaneHandleDrag.origin,
            normal: activeConstructionPlaneHandleDrag.normal
        )
    }

    private func pointDistance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        vectorDistance(vector(from: rhs, to: lhs), Vector3D(x: 0.0, y: 0.0, z: 0.0))
    }

    private func vectorDistance(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        let dz = lhs.z - rhs.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    private func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }

    private func pointOffsetBy(_ point: Point3D, _ vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private func scale(_ vector: Vector3D, by scalar: Double) -> Vector3D {
        Vector3D(
            x: vector.x * scalar,
            y: vector.y * scalar,
            z: vector.z * scalar
        )
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

    /// Commits the transform gizmo's in-plane translate actions: the ghost
    /// edit's center offset from its base is the profile-sketch translation
    /// (edit-state x maps to sketch x, edit-state z to sketch y). Height
    /// translation cannot be expressed as a profile edit and stays a
    /// non-committing preview.
    private func committedBodyMoveDragTarget() -> (featureID: FeatureID, target: ViewportBodyMoveDragTarget)? {
        guard let activeAffordanceDrag,
              case .translate = activeAffordanceDrag.target.action,
              activeAffordanceDrag.baseGroupEdit == nil,
              let selectionTarget = activeAffordanceDrag.target.selectionTarget,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID],
              let currentEdit = editedBodies[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let deltaX = Double(currentEdit.centerPoint.x - baseEdit.centerPoint.x)
        let deltaY = Double(currentEdit.centerPoint.z - baseEdit.centerPoint.z)
        guard abs(deltaX) > 1.0e-12 || abs(deltaY) > 1.0e-12 else {
            return nil
        }
        return (
            activeAffordanceDrag.target.featureID,
            ViewportBodyMoveDragTarget(
                target: selectionTarget,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
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
        guard let delta = baseEdit.profileCornerDragDelta(
            start: activeAffordanceDrag.startPoint,
            current: end,
            layout: layout
        ) else { return nil }
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
            basis: currentProjectionBasis,
            usesDragPreviewDocument: false
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
            basis: currentProjectionBasis,
            usesDragPreviewDocument: false
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
        var target = selectionDragTarget(from: start, to: end, size: size)
        target.selectionIntent = selectionIntent
        onSelectionDrag(target)
    }

    private func publishSelectionDragPreview(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) {
        publishSelectionDragPreview(
            target: selectionDragTarget(from: start, to: end, size: size)
        )
    }

    private func publishSelectionDragPreview(target: ViewportSelectionDragTarget) {
        onSelectionDragPreview?(target)
    }

    private func publishSelectionDragPreview(hits: [ViewportHit]) {
        publishSelectionDragPreview(
            target: ViewportSelectionDragTarget(hits: hits)
        )
    }

    private func selectionDragTarget(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) -> ViewportSelectionDragTarget {
        let rect = dragRect(from: start, to: end)
        guard rect.width > 0.0, rect.height > 0.0 else {
            return ViewportSelectionDragTarget(hits: [])
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
        let presentationOccurrenceIDs = presentationOccurrenceIDs(
            intersecting: rect,
            layout: mapper.layout
        )
        let rawHits = identityHitResolver.selectionHits(
            in: rect,
            scene: hitScene,
            layout: mapper.layout,
            sketchControlPointHitPolicy: sketchControlPointHitPolicy(for: hitScene),
            selectionHitPolicy: selectionHitPolicy
        )
        let hits = if presentationScene == nil {
            rawHits
        } else {
            MeshSourcePresentationLegacyHitFilter().selectionHits(
                rawHits,
                visiblePresentationOccurrenceIDs: presentationOccurrenceIDs,
                navigation: presentationSceneNodeIDByOccurrenceID,
                exactCADSceneNodeIDs: presentationCADInteractionSceneNodeIDs,
                selectionHitPolicy: selectionHitPolicy
            )
        }
        return ViewportSelectionDragTarget(
            hits: hits,
            presentationOccurrenceIDs: selectionHitPolicy.allowsObjectHits
                ? presentationOccurrenceIDs
                : []
        )
    }

    private func hover(at point: CGPoint, size: CGSize) {
        if measurementToolActive {
            handleMeasurementHover(at: point)
            return
        }
        do {
            if let input = try nativeAxisInput(at: point) {
                clearCanvasHover()
                if nativeAxisRouteEnabled(input.record.target) {
                    hoveredNativeAxisIdentity = input.record.identity
                }
                return
            }
        } catch {
            clearCanvasHover()
            return
        }
        hoveredNativeAxisIdentity = nil
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        if let target = resolvedInteractionTarget(at: point, size: size, sceneContext: sceneContext) {
            setHoveredInteractionTarget(target)
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            onPresentationOccurrenceHover?(nil)
            clearHoverCallbacks()
            return
        }
        clearHoverInteractionTargets()
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedTargetFeatureIDs()
        )
        let presentationOccurrenceID: SceneOccurrenceID?
        do {
            presentationOccurrenceID = try presentationSurfaceHit(at: point)?.triangle.occurrenceID
        } catch {
            clearCanvasHover()
            return
        }
        let hit = presentationFilteredLegacyHit(
            viewportHit(
                point: point,
                in: hitScene,
                layout: mapper.layout
            ),
            presentationOccurrenceID: presentationOccurrenceID
        )
        hoveredCanvasHit = hit
        let sketchPlane = canvasDragSketchPlane(for: hit)
        let exactWorldPoint = selectedPresentationHasExactCADContext
            ? selectedGeneratedFaceSurfaceWorldPoint(
                at: point,
                in: scene,
                layout: mapper.layout
            )
            : nil
        hoveredModelPoint = canvasInput(
            for: point,
            exactWorldPoint: exactWorldPoint,
            sketchPlane: sketchPlane
        )?.point
        refreshSnapOverlayResolution(layout: mapper.layout)
        refreshPlacementHighlight(layout: mapper.layout)
        if hit == nil, let presentationOccurrenceID {
            onHover?(nil)
            onPresentationOccurrenceHover?(presentationOccurrenceID)
        } else {
            onPresentationOccurrenceHover?(nil)
            onHover?(hit)
        }
    }

    private func clearHoverInteractionTargets() {
        hoveredNativeAxisIdentity = nil
        hoveredInteractionTarget = nil
    }

    private func setHoveredInteractionTarget(_ target: ViewportInteractionTarget) {
        hoveredInteractionTarget = target
    }

    private func clearHoverCallbacks() {
        clearSnapOverlayResolution()
        clearPlacementHighlight()
        onPresentationOccurrenceHover?(nil)
        onHover?(nil)
    }

    private func clearCanvasHover() {
        clearHoverInteractionTargets()
        hoveredCanvasHit = nil
        hoveredModelPoint = nil
        if measurementToolActive {
            measurementSession.hover(nil)
            publishMeasurementState()
        }
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
        activeControlSession.setProjectionTransition(
            transition,
            basis: targetBasis,
            orbitBasis: storesOrbitBasis ? targetBasis : nil,
            selectedAxis: nextSelectedAxis
        )
        activeCanvasDrag = nil
        clearCanvasHover()
        publishProjectionBasis(targetBasis)
        clearProjectionTransition(transition.id)
    }

    private func resetViewportCamera(
        size: CGSize,
        basis: ViewportProjectionBasis
    ) {
        do {
            try activeControlSession.perform(.resetCamera)
        } catch {
            Logger(
                subsystem: "RupaRendering",
                category: "ViewportControlSession"
            ).error("Viewport reset failed: \(error.localizedDescription, privacy: .public)")
        }
        activeCanvasDrag = nil
        clearCanvasHover()
        publishCameraFrame(size: size, basis: basis)
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

    private func panCanvas(
        by delta: CGSize,
        size: CGSize
    ) {
        do {
            try activeControlSession.perform(
                .pan(
                    deltaXPoints: Double(delta.width),
                    deltaYPoints: Double(delta.height)
                )
            )
        } catch {
            Logger(
                subsystem: "RupaRendering",
                category: "ViewportControlSession"
            ).error("Viewport pan failed: \(error.localizedDescription, privacy: .public)")
        }
        publishCameraFrame(size: size, basis: currentProjectionBasis)
    }

    private func orbitViewport(
        by delta: CGSize,
        size: CGSize
    ) {
        let nextBasis: ViewportProjectionBasis
        do {
            let yawDeltaDegrees = -Double(delta.width) * 0.008 * 180.0 / .pi
            let elevationDeltaDegrees = Double(delta.height) * 0.006 * 180.0 / .pi
            try activeControlSession.perform(
                .orbit(
                    yawDeltaDegrees: yawDeltaDegrees,
                    elevationDeltaDegrees: elevationDeltaDegrees
                )
            )
            nextBasis = activeControlSession.basis
        } catch {
            Logger(
                subsystem: "RupaRendering",
                category: "ViewportControlSession"
            ).error("Viewport orbit failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        activeCanvasDrag = nil
        clearCanvasHover()
        publishProjectionBasis(nextBasis)
        publishCameraFrame(size: size, basis: nextBasis)
    }

    private func zoomCanvas(
        by factor: CGFloat,
        anchor: CGPoint,
        size: CGSize
    ) {
        let basis = currentProjectionBasis
        do {
            try activeControlSession.perform(.zoom(factor: Double(factor), anchor: anchor))
        } catch {
            Logger(subsystem: "RupaRendering", category: "ViewportControlSession")
                .error("Viewport zoom failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        publishCameraFrame(size: size, basis: basis)
    }
}

private extension Viewport {
    var hoveredAffordance: ViewportAffordanceTarget? {
        guard case .affordance(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSketchCurveHandle: ViewportSketchCurveHandleTarget? {
        guard case .sketchCurveHandle(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSketchDimension: ViewportSketchDimensionTarget? {
        guard case .sketchDimension(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSketchPointHandle: ViewportSketchPointHandleTarget? {
        guard case .sketchPointHandle(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredBridgeCurveEndpointHandle: ViewportBridgeCurveEndpointHandleTarget? {
        guard case .bridgeCurveEndpoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSplineControlPoint: ViewportSplineControlPointHandleTarget? {
        guard case .splineControlPoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget? {
        guard case .splineControlPointSlide(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPolySplineSurfaceVertex: ViewportPolySplineSurfaceVertexHandleTarget? {
        guard case .polySplineSurfaceVertex(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPolySplineSurfaceVertexSlideHandle: ViewportPolySplineSurfaceVertexSlideHandleTarget? {
        guard case .polySplineSurfaceVertexSlide(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSurfaceControlPoint: ViewportSurfaceControlPointHandleTarget? {
        guard case .surfaceControlPoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget? {
        guard case .surfaceControlPointSlide(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSurfaceTrimEndpoint: ViewportSurfaceTrimEndpointHandleTarget? {
        guard case .surfaceTrimEndpoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSurfaceTrimControlPoint: ViewportSurfaceTrimControlPointHandleTarget? {
        guard case .surfaceTrimControlPoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSurfaceFrameHandle: ViewportSurfaceFrameHandleTarget? {
        guard case .surfaceFrame(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredRegionOffsetHandle: ViewportRegionOffsetHandleTarget? {
        guard case .regionOffset(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredEdgeOffsetHandle: ViewportEdgeOffsetHandleTarget? {
        guard case .edgeOffset(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSlotWidthHandle: ViewportSlotWidthHandleTarget? {
        guard case .slotWidth(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredSketchVertexOffsetHandle: ViewportSketchVertexOffsetHandleTarget? {
        guard case .sketchVertexOffset(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayLinearAxisHandle: ViewportPatternArrayLinearAxisHandleTarget? {
        guard case .patternArrayLinearAxis(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredIndependentCopyExtrudeDistanceHandle: ViewportIndependentCopyExtrudeDistanceHandleTarget? {
        guard case .independentCopyExtrudeDistance(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredIndependentCopyBodyDimensionHandle: ViewportIndependentCopyBodyDimensionHandleTarget? {
        guard case .independentCopyBodyDimension(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayRadialAngleHandle: ViewportPatternArrayRadialAngleHandleTarget? {
        guard case .patternArrayRadialAngle(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayCopyCountHandle: ViewportPatternArrayCopyCountHandleTarget? {
        guard case .patternArrayCopyCount(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayCurveExtentHandle: ViewportPatternArrayCurveExtentHandleTarget? {
        guard case .patternArrayCurveExtent(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayCurvePathPointHandle: ViewportPatternArrayCurvePathPointHandleTarget? {
        guard case .patternArrayCurvePathPoint(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredPatternArrayOutputModeHandle: ViewportPatternArrayOutputModeHandleTarget? {
        guard case .patternArrayOutputMode(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }

    var hoveredConstructionPlaneHandle: ViewportConstructionPlaneHandleTarget? {
        guard case .constructionPlane(let target) = hoveredInteractionTarget else {
            return nil
        }
        return target
    }
}

private extension Viewport {
    var pendingAffordance: ViewportAffordanceTarget? {
        get {
            guard case .affordance(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSketchCurveHandle: ViewportSketchCurveHandleTarget? {
        get {
            guard case .sketchCurveHandle(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSketchDimension: ViewportSketchDimensionTarget? {
        get {
            guard case .sketchDimension(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSketchPointHandle: ViewportSketchPointHandleTarget? {
        get {
            guard case .sketchPointHandle(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingBridgeCurveEndpointHandle: ViewportBridgeCurveEndpointHandleTarget? {
        get {
            guard case .bridgeCurveEndpoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSplineControlPoint: ViewportSplineControlPointHandleTarget? {
        get {
            guard case .splineControlPoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget? {
        get {
            guard case .splineControlPointSlide(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPolySplineSurfaceVertex: ViewportPolySplineSurfaceVertexHandleTarget? {
        get {
            guard case .polySplineSurfaceVertex(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPolySplineSurfaceVertexSlideHandle: ViewportPolySplineSurfaceVertexSlideHandleTarget? {
        get {
            guard case .polySplineSurfaceVertexSlide(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSurfaceControlPoint: ViewportSurfaceControlPointHandleTarget? {
        get {
            guard case .surfaceControlPoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget? {
        get {
            guard case .surfaceControlPointSlide(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSurfaceTrimEndpoint: ViewportSurfaceTrimEndpointHandleTarget? {
        get {
            guard case .surfaceTrimEndpoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSurfaceTrimControlPoint: ViewportSurfaceTrimControlPointHandleTarget? {
        get {
            guard case .surfaceTrimControlPoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSurfaceFrameHandle: ViewportSurfaceFrameHandleTarget? {
        get {
            guard case .surfaceFrame(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingRegionOffsetHandle: ViewportRegionOffsetHandleTarget? {
        get {
            guard case .regionOffset(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingEdgeOffsetHandle: ViewportEdgeOffsetHandleTarget? {
        get {
            guard case .edgeOffset(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSlotWidthHandle: ViewportSlotWidthHandleTarget? {
        get {
            guard case .slotWidth(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingSketchVertexOffsetHandle: ViewportSketchVertexOffsetHandleTarget? {
        get {
            guard case .sketchVertexOffset(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayLinearAxisHandle: ViewportPatternArrayLinearAxisHandleTarget? {
        get {
            guard case .patternArrayLinearAxis(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingIndependentCopyExtrudeDistanceHandle: ViewportIndependentCopyExtrudeDistanceHandleTarget? {
        get {
            guard case .independentCopyExtrudeDistance(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingIndependentCopyBodyDimensionHandle: ViewportIndependentCopyBodyDimensionHandleTarget? {
        get {
            guard case .independentCopyBodyDimension(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayRadialAngleHandle: ViewportPatternArrayRadialAngleHandleTarget? {
        get {
            guard case .patternArrayRadialAngle(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayCopyCountHandle: ViewportPatternArrayCopyCountHandleTarget? {
        get {
            guard case .patternArrayCopyCount(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayCurveExtentHandle: ViewportPatternArrayCurveExtentHandleTarget? {
        get {
            guard case .patternArrayCurveExtent(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayCurvePathPointHandle: ViewportPatternArrayCurvePathPointHandleTarget? {
        get {
            guard case .patternArrayCurvePathPoint(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingPatternArrayOutputModeHandle: ViewportPatternArrayOutputModeHandleTarget? {
        get {
            guard case .patternArrayOutputMode(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }

    var pendingConstructionPlaneHandle: ViewportConstructionPlaneHandleTarget? {
        get {
            guard case .constructionPlane(let target) = pendingInteractionTarget else {
                return nil
            }
            return target
        }
    }
}

extension Viewport {
    // FIXME(INCOMPLETE_IMPLEMENTATION): The production mount now consumes this
    // complete producer, but mounted App parity and native pointer routing are
    // not yet verified. Do not report the RealityKit migration complete before
    // RK-3.2 mount tests, RK-4 input cutover, and RK-IV App verification pass.
    /// Captures the source and interaction values required by native spatial
    /// overlays while this viewport is isolated to the main actor.  The
    /// returned builder owns only checked-Sendable values and may be retained
    /// by the RealityKit preparation worker; camera-only updates must not call
    /// this method again.
    func makeSpatialOverlaySemanticBuilder(
        scene: ViewportScene,
        modelBounds: CGRect,
        renderOrigin: Point3D,
        topologyRevision: UInt64,
        drawsLegacyBodies: Bool
    ) throws -> @Sendable (Point3D, Int) throws -> ViewportSpatialOverlayProducer.Output {
        let snapshot = try makeSpatialOverlaySemanticSnapshot(
            scene: scene,
            modelBounds: modelBounds,
            renderOrigin: renderOrigin,
            drawsLegacyBodies: drawsLegacyBodies
        )
        return ViewportSpatialOverlayProducer.makeBuilder(
            from: snapshot,
            topologyRevision: topologyRevision
        )
    }

    /// Materializes the immutable producer input from world-owned values.
    /// Camera size, projection basis and grid spacing are deliberately absent:
    /// no camera-only update may recapture this source snapshot.
    func makeSpatialOverlaySemanticSnapshot(
        scene: ViewportScene,
        modelBounds: CGRect,
        renderOrigin: Point3D,
        drawsLegacyBodies: Bool
    ) throws -> ViewportSpatialOverlaySemanticSnapshot {
        guard renderOrigin.isFinite,
              modelBounds.origin.x.isFinite,
              modelBounds.origin.y.isFinite,
              modelBounds.width.isFinite,
              modelBounds.height.isFinite,
              modelBounds.width >= 0,
              modelBounds.height >= 0 else {
            throw RealityViewportSpatialBatch.invalid("Spatial overlay world bounds are invalid.")
        }

        var measurement: ViewportSpatialOverlaySemanticSnapshot.Measurement?
        if measurementToolActive,
           let start = measurementSession.state.start,
           let end = measurementSession.state.visibleEnd {
            guard start.point.isFinite, end.point.isFinite,
                  let distance = measurementDistanceMeters(start: start.point, end: end.point),
                  distance > 1.0e-12 else {
                throw RealityViewportSpatialBatch.invalid("Measurement endpoints are invalid.")
            }
            measurement = .init(
                start: start.point,
                end: end.point,
                label: formattedViewportLength(distance),
                boundsRuler: nil
            )
        }

        if showsAutomaticMeasurement,
           activeCanvasDrag == nil,
           pendingInteractionTarget == nil,
           nativeAxisGesture == nil,
           let occurrence = selectedMeasurementOccurrence() {
            let input = ViewportMeasurementBoundsRulerInput(
                bounds: occurrence.worldBounds,
                labels: ViewportMeasurementBoundsRulerLayout().preformattedLabels(
                    for: occurrence.worldBounds,
                    displayUnit: workspaceRuler.displayUnit
                )
            )
            if let current = measurement {
                measurement = .init(
                    start: current.start,
                    end: current.end,
                    label: current.label,
                    boundsRuler: input
                )
            } else {
                // The ruler is a native resource group even when no two-point
                // measurement is active, so retain it in the same snapshot.
                measurement = .init(
                    start: nil,
                    end: nil,
                    label: nil,
                    boundsRuler: input
                )
            }
        }

        let selectedSketchRegions = selectedSketchRegionTargets().map {
            ViewportSpatialOverlaySemanticSnapshot.Interaction.SketchRegion(
                featureID: $0.featureID,
                componentID: $0.componentID
            )
        }
        let previewSketchRegions = sketchRegionSelectionTargets(in: selectionDragPreviewTargets).map {
            ViewportSpatialOverlaySemanticSnapshot.Interaction.SketchRegion(
                featureID: $0.featureID,
                componentID: $0.componentID
            )
        }
        let hoveredSketchRegion = hoveredSketchRegionTarget().map {
            ViewportSpatialOverlaySemanticSnapshot.Interaction.SketchRegion(
                featureID: $0.featureID,
                componentID: $0.componentID
            )
        }
        let interaction = ViewportSpatialOverlaySemanticSnapshot.Interaction(
            selectedFeatureIDs: selectedTargetFeatureIDs(),
            selectedSceneNodeIDs: Set(selection.selectedSceneNodeIDs),
            hoveredFeatureIDs: hoveredFeatureIDs(),
            hoveredSceneNodeIDs: hoveredSceneNodeIDs(),
            selectedTargets: selection.selectedTargets,
            previewTargets: selectionDragPreviewTargets,
            objectSelectionTargets: objectSelectionTargets(),
            previewObjectSelectionTargets: objectSelectionTargets(in: selectionDragPreviewTargets),
            selectedReferences: selection.selectedReferences,
            hoveredReference: selection.hoveredReference,
            hoveredTarget: selection.hoveredTarget,
            selectedSketchEntities: selectedSketchEntityTargets(),
            previewSketchEntities: sketchEntitySelectionTargets(in: selectionDragPreviewTargets),
            hoveredSketchEntity: hoveredSketchEntityTarget(),
            selectedSketchRegions: selectedSketchRegions,
            previewSketchRegions: previewSketchRegions,
            hoveredSketchRegion: hoveredSketchRegion
        )

        let meshSelection = try semanticMeshSelectionSnapshot()
        let patternRoute = onPatternArrayLinearAxisDrag != nil
            || onIndependentCopyExtrudeDistanceDrag != nil
            || onIndependentCopyBodyDimensionDrag != nil
            || onPatternArrayRadialAngleDrag != nil
            || onPatternArrayCopyCountDrag != nil
            || onPatternArrayCurveExtentDrag != nil
            || onPatternArrayCurvePathPointDrag != nil
            || onPatternArrayOutputModeChange != nil
            || patternArrayCurvePathReplacementPreviewRequest != nil
        let patternSource: ViewportSpatialOverlaySemanticSnapshot.PatternSource? =
            patternRoute || !document.productMetadata.patternArrays.isEmpty
                ? .init(
                    document: document,
                    scene: scene,
                    selection: selection,
                    ruler: workspaceRuler,
                    hasRoute: patternRoute,
                    replacementRequest: patternArrayCurvePathReplacementPreviewRequest,
                    activeHandleIdentities: [
                        activePatternArrayLinearAxisDrag.map { .patternArrayLinearAxis($0.target.identity) },
                        activePatternArrayRadialAngleDrag.map { .patternArrayRadialAngle($0.target.identity) },
                        activePatternArrayCopyCountDrag.map { .patternArrayCopyCount($0.target.identity) },
                        activePatternArrayCurveExtentDrag.map { .patternArrayCurveExtent($0.target.identity) },
                        activePatternArrayCurvePathPointDrag.map { .patternArrayCurvePathPoint($0.target.identity) },
                        activeIndependentCopyExtrudeDistanceDrag.map { .independentCopyExtrudeDistance($0.target.identity) },
                        activeIndependentCopyBodyDimensionDrag.map { .independentCopyBodyDimension($0.target.identity) },
                    ].compactMap { $0 },
                    hoveredHandleIdentities: try hoveredSpatialHandleIdentity.map { [$0] } ?? [],
                    pendingHandleIdentities: try pendingSpatialHandleIdentity.map { [$0] } ?? [],
                    activeLinearAxis: activePatternArrayLinearAxisDrag.map {
                        .init(sourceID: $0.target.sourceID, axisSlot: $0.target.axisSlot, distance: $0.distanceMeters)
                    },
                    activeRadialAngle: activePatternArrayRadialAngleDrag.map {
                        .init(sourceID: $0.target.sourceID, angleRadians: $0.angleRadians)
                    },
                    activeCopyCount: activePatternArrayCopyCountDrag.map {
                        .init(sourceID: $0.target.sourceID, slot: $0.target.slot, copyCount: $0.copyCount)
                    },
                    activeCurveExtent: activePatternArrayCurveExtentDrag.map {
                        .init(sourceID: $0.target.sourceID, extent: .distance($0.distanceMeters))
                    },
                    activeCurvePathPoint: activePatternArrayCurvePathPointDrag.map {
                        .init(sourceID: $0.target.sourceID, pointIndex: $0.target.pointIndex, point: $0.point)
                    },
                    activeIndependentCopyExtrude: activeIndependentCopyExtrudeDistanceDrag.map {
                        .init(sourceID: $0.target.sourceID, outputIndex: $0.target.outputIndex,
                              outputSceneNodeID: $0.target.outputSceneNodeID, featureID: $0.target.featureID,
                              distance: $0.distanceMeters / $0.target.valueScale)
                    },
                    activeIndependentCopyDimension: activeIndependentCopyBodyDimensionDrag.map {
                        .init(sourceID: $0.target.sourceID, outputIndex: $0.target.outputIndex,
                              outputSceneNodeID: $0.target.outputSceneNodeID, featureID: $0.target.featureID,
                              kind: $0.target.kind, value: $0.valueMeters / $0.target.valueScale)
                    },
                    linearAxisRouteEnabled: onPatternArrayLinearAxisDrag != nil,
                    radialAngleRouteEnabled: onPatternArrayRadialAngleDrag != nil,
                    copyCountRouteEnabled: onPatternArrayCopyCountDrag != nil,
                    curveExtentRouteEnabled: onPatternArrayCurveExtentDrag != nil,
                    curvePathPointRouteEnabled: onPatternArrayCurvePathPointDrag != nil,
                    outputModeRouteEnabled: onPatternArrayOutputModeChange != nil,
                    independentCopyExtrudeRouteEnabled: onIndependentCopyExtrudeDistanceDrag != nil,
                    independentCopyDimensionRouteEnabled: onIndependentCopyBodyDimensionDrag != nil
                )
                : nil
        let analysisSource: ViewportSpatialOverlaySemanticSnapshot.AnalysisSource? =
            surfaceAnalysis != nil || surfaceContinuity != nil
                ? .init(
                    result: surfaceAnalysis,
                    continuity: surfaceContinuity,
                    scene: scene,
                    selection: selection,
                    document: document,
                    options: surfaceAnalysisOptions
                )
                : nil
        let sectionSource: ViewportSpatialOverlaySemanticSnapshot.SectionSource? =
            sectionAnalysis.map {
                .init(result: $0, ruler: workspaceRuler)
            }
        let world = ViewportSpatialOverlaySemanticSnapshot.WorldContext(
            modelBounds: modelBounds
        )
        let snapReference: ViewportSpatialOverlaySemanticSnapshot.SnapReference? = {
            let anchors = snapResolutionOptions?.referenceLineAnchors ?? []
            guard snapOverlayResult != nil || !anchors.isEmpty else { return nil }
            return .init(
                result: snapOverlayResult,
                referenceLineAnchors: anchors,
                modelBounds: modelBounds,
                context: activeCanvasDrag.map {
                    if case .creation = $0.kind { return .creationDrag }
                    return .passiveHover
                } ?? .passiveHover
            )
        }()
        let placement = placementHighlightState.map {
            ViewportSpatialOverlaySemanticSnapshot.Placement(
                highlight: $0,
                defaults: WorkspaceScaleDefaults(ruler: workspaceRuler)
            )
        }
        let dragPreview = try makeSemanticDragPreview()
        return ViewportSpatialOverlaySemanticSnapshot(
            scene: scene,
            interaction: interaction,
            meshSelection: meshSelection,
            sketchCurveSource: try makeSemanticSketchCurveSource(scene: scene),
            surfaceTransformSource: try makeSemanticSurfaceTransformSource(scene: scene),
            patternSource: patternSource,
            analysisSource: analysisSource,
            sectionSource: sectionSource,
            editedBodies: editedBodies,
            world: world,
            snapReference: snapReference,
            placement: placement,
            dragPreview: dragPreview,
            includesGrid: true,
            measurement: measurement,
            drawsLegacyBodies: drawsLegacyBodies,
            drawsDragPreviewBodies: rendersDragPreviewDocument
        )
    }

    private func makeSemanticSketchCurveSource(
        scene: ViewportScene
    ) throws -> ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput {
        typealias Route = ViewportSpatialOverlayProducer.SketchCurveAffordanceRoute
        typealias Override = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.ActiveOverride
        var routes: Set<Route> = [
            .lineDimension, .circleDimension, .arcDimension, .curvePointControl,
            .splineControl, .curvatureComb, .bridgeCurveEndpoint,
        ]
        if onRegionOffsetDrag != nil { routes.insert(.regionOffset) }
        if onEdgeOffsetDrag != nil { routes.insert(.edgeOffset) }
        if onSlotWidthDrag != nil { routes.insert(.slotWidth) }
        if onSketchVertexOffsetDrag != nil { routes.insert(.sketchVertexOffset) }
        if onSplineControlPointSlideDrag != nil { routes.insert(.splineSlide) }
        var overrides: [Override] = []
        if case .active(let press) = nativeAxisGesture, let value = press.value {
            switch press.input.record.target {
            case .regionOffset, .edgeOffset, .sketchVertexOffset, .splineControlPointSlide:
                overrides.append(.init(identity: press.input.record.identity, distanceMeters: value))
            case .slotWidth:
                overrides.append(.init(identity: press.input.record.identity, widthMeters: value))
            default: break
            }
        }
        if let drag = activeSketchCurveHandleDrag {
            overrides.append(.init(identity: .sketchCurveHandle(drag.target.identity),
                                   radiusMeters: drag.radiusMeters,
                                   startAngleRadians: drag.startAngleRadians,
                                   endAngleRadians: drag.endAngleRadians))
        }
        if let drag = activeSketchDimensionDrag {
            overrides.append(.init(identity: .sketchDimension(drag.target.identity), value: drag.value))
        }
        if let drag = activeSketchPointHandleDrag {
            overrides.append(.init(identity: .sketchPointHandle(drag.target.identity),
                                   deltaX: drag.viewportDelta.x, deltaY: drag.viewportDelta.y))
        }
        if let drag = activeSplineControlPointDrag {
            overrides.append(.init(identity: .splineControlPoint(drag.target.identity),
                                   deltaX: drag.viewportDelta.x, deltaY: drag.viewportDelta.y))
        }
        if let drag = activeRegionOffsetDrag {
            overrides.append(.init(identity: .regionOffset(drag.target.identity), distanceMeters: drag.distanceMeters))
        }
        if let drag = activeEdgeOffsetDrag {
            overrides.append(.init(identity: .edgeOffset(drag.target.identity), distanceMeters: drag.distanceMeters))
        }
        if let drag = activeSlotWidthDrag {
            overrides.append(.init(identity: .slotWidth(drag.target.identity), widthMeters: drag.widthMeters))
        }
        if let drag = activeSketchVertexOffsetDrag {
            overrides.append(.init(identity: .sketchVertexOffset(drag.target.identity), distanceMeters: drag.distanceMeters))
        }
        if let drag = activeSplineControlPointSlideDrag {
            overrides.append(.init(identity: .splineControlPointSlide(drag.target.identity),
                                   distanceMeters: drag.distanceMeters))
        }
        if let drag = activeBridgeCurveEndpointDrag {
            overrides.append(.init(identity: .bridgeCurveEndpoint(drag.target.identity),
                                   bridgeEndpoint: drag.endpoint, bridgeParameter: drag.parameter))
        }
        return .init(
            document: document, scene: scene, selection: selection,
            interaction: .init(
                active: overrides.map { .init(identity: $0.identity, state: $0.state) },
                hovered: try hoveredSpatialHandleIdentity,
                pending: try pendingSpatialHandleIdentity
            ),
            overlayState: sceneOverlayState,
            ruler: workspaceRuler, enabledRoutes: routes, activeOverrides: overrides,
            includeSelectedBridgeEndpoints: true,
            slotWidthMeters: slotWidthMeters,
            sketchVertexOffsetDistanceMeters: sketchVertexOffsetDistanceMeters,
            edgeOffsetDistanceMeters: edgeOffsetDistanceMeters
        )
    }

    private var showsConstructionHighlight: Bool {
        showsConstructionPlaneHover && hoveredAffordance == nil
            && pendingAffordance == nil && activeAffordanceDrag == nil
    }

    private func makeSemanticSurfaceTransformSource(
        scene: ViewportScene
    ) throws -> ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput {
        typealias Route = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceRoute
        typealias Active = ViewportSpatialOverlayProducer.SurfaceTransformActiveValue
        var routes: Set<Route> = [
            .surfaceControlPoint, .surfaceTrimEndpoint, .surfaceTrimControlPoint,
            .surfaceKnot, .surfaceSpan, .surfaceTrimKnot, .surfaceTrimSpan, .surfaceFrame,
            .constructionFace,
        ]
        var interactive: Set<Route> = []
        if onPolySplineSurfaceVertexDrag != nil {
            interactive.insert(.polySplineSurfaceVertex)
            routes.insert(.activePolySplineSurfaceVertexPreview)
        }
        if onSurfaceControlPointDrag != nil {
            interactive.insert(.surfaceControlPoint)
            routes.insert(.activeSurfaceControlPointPreview)
        }
        if onSurfaceTrimEndpointDrag != nil { interactive.insert(.surfaceTrimEndpoint) }
        if onSurfaceTrimControlPointDrag != nil { interactive.insert(.surfaceTrimControlPoint) }
        if onPolySplineSurfaceVertexSlideDrag != nil { interactive.insert(.polySplineSurfaceVertexSlide) }
        if onSurfaceControlPointSlideDrag != nil { interactive.insert(.surfaceControlPointSlide) }
        if onSurfaceFrameDrag != nil { interactive.insert(.surfaceFrame) }
        if onConstructionPlaneHandleDrag != nil { interactive.insert(.constructionPlane) }
        if allowsObjectAffordances {
            interactive.formUnion([.bodyTransform, .sketchTransform])
        }
        if onEdgeFilletDrag != nil { interactive.insert(.edgeFillet) }
        routes.formUnion(interactive)
        var active: [Active] = []
        let comparison = modifierFlags.containsControl
        if case .active(let press) = nativeAxisGesture, let value = press.value {
            switch press.input.record.target {
            case .polySplineSurfaceVertexSlide, .surfaceControlPointSlide, .surfaceFrame:
                active.append(.init(identity: press.input.record.identity, distance: value,
                                    showsOriginalComparison: comparison))
            default: break
            }
        }
        if let drag = activeAffordanceDrag {
            active.append(.init(identity: .affordance(drag.target)))
        }
        if let drag = activePolySplineSurfaceVertexDrag {
            active.append(.init(identity: try ViewportInteractionTarget.polySplineSurfaceVertex(drag.target).spatialIdentity,
                                delta: Vector3D(x: drag.delta.x, y: drag.delta.y, z: drag.delta.z),
                                showsOriginalComparison: comparison))
        }
        if let drag = activeSurfaceControlPointDrag {
            active.append(.init(identity: try ViewportInteractionTarget.surfaceControlPoint(drag.target).spatialIdentity,
                                delta: Vector3D(x: drag.delta.x, y: drag.delta.y, z: drag.delta.z),
                                showsOriginalComparison: comparison))
        }
        if let drag = activeSurfaceTrimEndpointDrag {
            active.append(.init(identity: try ViewportInteractionTarget.surfaceTrimEndpoint(drag.target).spatialIdentity,
                                delta: Vector3D(x: drag.delta.x, y: drag.delta.y, z: drag.delta.z)))
        }
        if let drag = activeSurfaceTrimControlPointDrag {
            active.append(.init(identity: try ViewportInteractionTarget.surfaceTrimControlPoint(drag.target).spatialIdentity,
                                delta: Vector3D(x: drag.delta.x, y: drag.delta.y, z: drag.delta.z)))
        }
        if let drag = activePolySplineSurfaceVertexSlideDrag {
            active.append(.init(identity: .polySplineSurfaceVertexSlide(drag.target.identity),
                                distance: drag.distanceMeters, showsOriginalComparison: comparison))
        }
        if let drag = activeSurfaceControlPointSlideDrag {
            active.append(.init(identity: try ViewportInteractionTarget.surfaceControlPointSlide(drag.target).spatialIdentity,
                                distance: drag.distanceMeters, showsOriginalComparison: comparison))
        }
        if let drag = activeSurfaceFrameDrag {
            active.append(.init(identity: try ViewportInteractionTarget.surfaceFrame(drag.target).spatialIdentity,
                                distance: drag.distanceMeters))
        }
        if let drag = activeConstructionPlaneHandleDrag {
            active.append(.init(identity: .constructionPlane(drag.target.identity),
                                origin: drag.origin, normal: drag.normal))
        }
        let constructionFace: SelectionTarget?
        if showsConstructionHighlight, let hit = hoveredCanvasHit,
           let nodeID = hit.sceneNodeID, let face = hit.bodyFace {
            let component: SelectionComponentID = switch face {
            case .front: .bodyFaceFront
            case .back: .bodyFaceBack
            case .top: .bodyFaceTop
            case .bottom: .bodyFaceBottom
            case .left: .bodyFaceLeft
            case .right: .bodyFaceRight
            case .side: .bodyFaceSide
            }
            constructionFace = .init(sceneNodeID: nodeID, component: hit.selectionComponent ?? .face(component))
        } else {
            constructionFace = nil
        }
        return .init(
            document: document, scene: scene, selection: selection, editedBodies: editedBodies,
            ruler: workspaceRuler, enabledRoutes: routes, interactiveRoutes: interactive,
            activeValues: active,
            hoveredHandleIdentities: try hoveredSpatialHandleIdentity.map { [$0] } ?? [],
            pendingHandleIdentities: try pendingSpatialHandleIdentity.map { [$0] } ?? [],
            modifierControl: comparison, objectRegistry: objectRegistry, constructionFaceTarget: constructionFace
        )
    }

    private func makeSemanticDragPreview() throws -> ViewportSpatialOverlaySemanticSnapshot.DragPreview? {
        guard let activeCanvasDrag,
              case .creation(let kind) = activeCanvasDrag.kind,
              let drag = activeCanvasDrag.modelDrag else {
            return nil
        }
        return .init(
            kind: kind,
            drag: drag,
            document: document,
            ruler: workspaceRuler,
            snapOptions: snapResolutionOptions,
            axisConstraint: canvasDragAxisConstraint
        )
    }

    private func semanticMeshSelectionSnapshot() throws -> ViewportMeshSelectionOverlay? {
        guard let overlay = meshSelectionOverlay else {
            return nil
        }
        guard overlay.snapshotID == presentationScene?.snapshotID else {
            throw RealityViewportSpatialBatch.invalid(
                "Mesh selection overlay belongs to a stale presentation snapshot."
            )
        }
        return overlay
    }

}
