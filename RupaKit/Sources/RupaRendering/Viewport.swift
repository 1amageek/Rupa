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
    private static let nativeGestureLogger = Logger(
        subsystem: "RupaRendering",
        category: "ViewportNativeGesture"
    )
    private static let selectionRectangleLogger = Logger(
        subsystem: "RupaRendering",
        category: "ViewportSelectionRectangle"
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
    @State private var pendingNativeAffordance: ViewportNativeAffordanceClaim?
    @State private var hoveredNativeHandleIdentity: ViewportSpatialHandleIdentity?
    @State private var nativeInputGesture: NativeInputGesture?

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

    /// One open sketch transform gesture.
    ///
    /// The press owns the prepared baseline for the whole drag, so no later
    /// frame can change what is committed, and `mutation` is the preview the
    /// producer redraws this route's handles at until the release resolves.
    private struct SketchTransformPress {
        let input: ViewportSketchTransformInput
        let identity: ViewportSpatialHandleIdentity
        let source: ViewportSourceIdentity
        let snapshotID: EvaluationSnapshotID?
        let selectedTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let start: CGPoint
        var mutation: Transform3D?
        var finish: (point: CGPoint, revision: UInt64)?
    }

    /// One open pattern affordance gesture.
    ///
    /// The press materializes the prepared record once against the mounted
    /// camera projection and retains that closed value for the whole drag.
    /// Those samples are only meaningful against `revision`, so a camera
    /// revision change ends the gesture rather than continuing against a stale
    /// screen basis.
    private struct NativePatternPress {
        let input: ViewportNativePatternInput
        let source: ViewportSourceIdentity
        let snapshotID: EvaluationSnapshotID?
        let selectedTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let revision: UInt64
        let start: CGPoint
        var value: ViewportNativePatternInput.Value?
    }

    /// One open world-point gesture.
    ///
    /// The press owns the prepared record for the whole drag, and each update
    /// asks the mounted camera for both ends of the gesture against the same
    /// revision, so a camera move cannot mix two projections into one drag.
    /// The release waits for a mounted frame the same way the sketch transform
    /// route does, because the value it commits is read from that frame.
    private struct NativeWorldPointPress {
        let input: ViewportNativeWorldPointInput
        let source: ViewportSourceIdentity
        let snapshotID: EvaluationSnapshotID?
        let selectedTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let start: CGPoint
        var value: ViewportNativeWorldPointInput.Value?
        var finish: (point: CGPoint, revision: UInt64)?
    }

    private enum NativeInputGesture {
        case active(NativeAxisPress)
        case sketchTransform(SketchTransformPress)
        case pattern(NativePatternPress)
        case worldPoint(NativeWorldPointPress)
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
    private let onSketchTransformCommit: ((ViewportSketchTransformDragTarget) -> Void)?
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

    private var activeSplineControlPointSlideDrag: ViewportSplineControlPointSlideDragState? {
        get { activeInteractionDrags.splineControlPointSlide }
        nonmutating set { activeInteractionDrags.splineControlPointSlide = newValue }
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
        onSketchTransformCommit: ((ViewportSketchTransformDragTarget) -> Void)? = nil,
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
        self.onSketchTransformCommit = onSketchTransformCommit
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
        self.selectedPresentationHasExactCADContext = selectedPresentationHasExactCADContext
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
                                    resumeSketchTransformFinish()
                                    resumeNativeWorldPointFinish()
                                } else if presentationSurface.appliedViewportRevision == nil {
                                    cancelNativeInputGesture()
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
                            beginViewportPress(at: point)
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
                            if nativeInputGesture != nil {
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
                    if let finishRevision = openNativeGestureFinishRevision,
                       finishRevision != activeControlSession.revision {
                        cancelNativeInputGesture()
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
                    if case .failed = presentationPlanCache.state { cancelNativeInputGesture() }
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
                cancelNativeInputGesture()
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
                cancelNativeInputGesture()
                resetMeasurement()
            }
            .onChange(of: selection.selectedTargets) { _, _ in
                cancelNativeInputGesture()
            }
            .onChange(of: selection.selectedReferences) { _, _ in
                cancelNativeInputGesture()
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
                cancelNativeInputGesture()
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
        switch nativeInputGesture {
        case .active(let press): key.nativeAxisValue = press.value
        case .sketchTransform(let press): key.sketchTransformMutation = press.mutation
        case .pattern(let press): key.nativePatternValue = press.value
        case .worldPoint(let press): key.nativeWorldPointValue = press.value
        case .cancelled, nil: break
        }
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
        if onSketchTransformCommit != nil { key.availableRoutes |= 1 << 22 }
        if onVertexDrag != nil { key.availableRoutes |= 1 << 23 }
        if onFaceDrag != nil { key.availableRoutes |= 1 << 24 }
        if onEdgeChamferDrag != nil { key.availableRoutes |= 1 << 25 }
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

    /// The occurrences the mounted native frame draws inside `rect`, answered
    /// by the same frame, identity and camera revision as the point path.
    ///
    /// An empty result means the frame drew no occurrence there. A frame that
    /// cannot answer is a typed failure, never an empty rectangle: the caller
    /// publishes nothing rather than a selection the frame never judged.
    ///
    /// With no presentation mounted there is no native frame to ask and the
    /// whole legacy rectangle path runs, so the empty result here is the
    /// absence of a presentation occurrence rather than a refused query.
    private func presentationOccurrenceIDs(
        intersecting rect: CGRect
    ) throws -> [SceneOccurrenceID] {
        guard presentationScene != nil else {
            return []
        }
        return try presentationPlanCache.occurrenceIDs(
            intersecting: rect,
            for: presentationQueryIdentity(),
            revision: activeControlSession.revision
        )
    }

    /// CAD sub-shape scopes and the occurrence resolve through the mounted
    /// native frame. `.object` and `.all` still reach the legacy resolver for
    /// the curve and sketch families, which have no prepared native counterpart
    /// yet.
    private var usesNativeCADSubshapeHits: Bool {
        guard presentationScene != nil else {
            return false
        }
        switch selectionHitPolicy {
        case .all, .object, .face, .edge, .vertex:
            return true
        case .region, .sketchEntity:
            return false
        }
    }

    /// Once the native frame has answered for a topology-backed scene, only the
    /// scopes that still lack a native input path re-ask the legacy identity
    /// resolver. Face, edge and vertex scopes never route a miss into it,
    /// including over an empty pixel, which the native frame answers as a miss.
    /// A scene the native query cannot answer for at all still reaches the
    /// legacy resolver past this property; `NativeCADSubshapeResult.unsupported`
    /// owns that rule and names its condition.
    // FIXME(INCOMPLETE_IMPLEMENTATION): `.all`, `.object`, `.region` and
    // `.sketchEntity` still reach the legacy identity resolver, which projects,
    // occludes and clips with its own GPU rule instead of the mounted native
    // frame, so two selection judgements remain live.
    //
    // Production path: `resolvedViewportHit(_:at:in:layout:presentationOccurrenceID:)`
    // routes a native `.miss` into `legacyViewportHit` for `.all` and
    // `.object`, and `.all` is the default hover scope. `.region` and
    // `.sketchEntity` never run the native query at all, because
    // `usesNativeCADSubshapeHits` excludes them, so they reach the same bridge
    // through `.unsupported`. `.all` and `.object` also reach it after a native
    // occurrence answer, which `legacyOverlayAnswer(_:)` records separately.
    //
    // Do not treat the input cutover as complete while this returns true for
    // any scope: the curve and sketch families need a native path, and the
    // region and sketch-entity scopes need a prepared native identity, before
    // the legacy resolver and this property can be deleted together. Rectangle
    // selection no longer waits on this property; it asks
    // `presentationCADSubshapeRectangleHits(in:in:)` for the CAD sub-shape
    // scopes.
    private var requiresLegacyHitFallback: Bool {
        switch selectionHitPolicy {
        case .face, .edge, .vertex:
            return false
        case .all, .object, .region, .sketchEntity:
            return true
        }
    }

    /// Outcome of the native CAD sub-shape query.
    ///
    /// `unsupported` reports that the native frame cannot answer a CAD
    /// sub-shape query at all — no mounted presentation, or no CAD interaction
    /// node in the scene carries prepared B-Rep topology to resolve an identity
    /// from, and for the `vertex` scope no body carries a surface handle
    /// display either. It is the only outcome that still routes a face, edge or
    /// vertex query to the legacy resolver, so a miss over a scene the native
    /// frame does answer for stays a miss instead of being answered by a
    /// second, differently projected hit rule.
    /// An empty pixel is a `miss`, not `unsupported`: the native frame did
    /// answer, and nothing is drawn there.
    ///
    /// `resolvedOccurrence` is a complete native answer that the interim overlay
    /// residual still has to be ordered against, and it is separated from
    /// `resolved` for that reason alone. A sub-shape answer is final.
    private enum NativeCADSubshapeResult {
        case resolved(ViewportHit)
        case resolvedOccurrence(ViewportHit)
        case miss
        case unsupported
    }

    /// Resolves a CAD face, edge or vertex from prepared B-Rep topology, or the
    /// occurrence the frame draws, using the same native ray and projection that
    /// drew the frame. A sub-shape identity is always the prepared
    /// `SelectionComponentID`, never a render-mesh element.
    ///
    /// Every CAD interaction body with prepared topology is a candidate, not
    /// only the body the pointer draws. A pixel just outside the tessellated
    /// silhouette still has outline edges and silhouette vertices within the
    /// point tolerance, and gating the whole query on a drawn surface would
    /// send those queries — and every hover over empty space — back to the
    /// legacy identity resolver. `visibleSurface` is the native surface hit at
    /// the pointer; its triangle provenance answers the face query for the body
    /// it belongs to and is nil over an empty pixel. Candidates from different
    /// bodies are compared through `ViewportNativeHitCandidate.precedes`, so the
    /// nearest projected sub-shape wins and equal candidates keep stable scene
    /// order.
    ///
    /// The occurrence enters that same comparison at its weakest rank, so a
    /// pointer that named a sub-shape never resolves to the occurrence carrying
    /// it. It is admitted from the drawn triangle alone and is not gated on the
    /// depth that answers the face query: a frame that drew the pointer's pixel
    /// has already answered which occurrence is there.
    private func presentationCADSubshapeHit(
        at point: CGPoint,
        visibleSurface: (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        in scene: ViewportScene
    ) throws -> NativeCADSubshapeResult {
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: presentationPlanCache,
            identity: presentationQueryIdentity(),
            revision: activeControlSession.revision
        )
        // Only a CAD-sourced triangle carries provenance the prepared run list
        // can name. An authored mesh numbers its own faces independently, so
        // its `MeshFaceID` could land inside a CAD run by coincidence and name
        // a face the frame never drew. Withholding the surface from those bodies
        // makes the face query miss instead.
        var visibleSceneNodeID: SceneNodeID?
        var visibleFace: (faceID: MeshFaceID, depth: Double)?
        if let visibleSurface,
           case .cad = visibleSurface.triangle.sourceReference,
           let sceneNodeID = presentationSceneNodeIDByOccurrenceID[
               visibleSurface.triangle.occurrenceID
           ],
           let depth = try probe.projectedPointWithinDepthRange(visibleSurface.point)?.depth {
            visibleSceneNodeID = sceneNodeID
            visibleFace = (faceID: visibleSurface.triangle.faceID, depth: depth)
        }
        var best: (hit: ViewportHit, candidate: ViewportNativeHitCandidate)?
        if let visibleSurface {
            best = ViewportNativeOverlayHitResolver.occurrence(
                drawnBy: visibleSurface.triangle,
                navigation: presentationSceneNodeIDByOccurrenceID,
                items: scene.items,
                selectionHitPolicy: selectionHitPolicy
            )
        }
        var carriesNativeFamily = false
        for item in scene.items {
            guard let sceneNodeID = item.sceneNodeID,
                  case .body(let component) = item.kind else {
                continue
            }
            // The surface handle displays are drawn for every body that carries
            // them, so they are not gated on exact CAD affordance context. Both
            // replaced backends admitted them from the body's own displays, and
            // narrowing them here would make the native path answer less than
            // the path it replaces.
            if selectionHitPolicy.allowsVertexHits,
               ViewportNativeOverlayHitResolver.carriesSurfaceHandleDisplays(component) {
                carriesNativeFamily = true
                if let handle = try ViewportNativeOverlayHitResolver.surfaceHandle(
                    at: point,
                    item: item,
                    component: component,
                    selectionHitPolicy: selectionHitPolicy,
                    tolerance: ViewportNativeCADTopologyResolver.pointTolerance,
                    probe: probe
                ), best.map({ handle.candidate.precedes($0.candidate) }) ?? true {
                    best = handle
                }
            }
            guard presentationCADInteractionSceneNodeIDs.contains(sceneNodeID),
                  let topology = component.topology else {
                continue
            }
            carriesNativeFamily = true
            guard let resolved = try ViewportNativeCADTopologyResolver.resolve(
                at: point,
                topology: topology,
                modelTransform: item.modelTransform,
                selectionHitPolicy: selectionHitPolicy,
                visibleSurface: sceneNodeID == visibleSceneNodeID ? visibleFace : nil,
                probe: probe
            ) else {
                continue
            }
            if let best, resolved.candidate.precedes(best.candidate) == false {
                continue
            }
            best = (
                ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: sceneNodeID,
                    kind: .body,
                    pickingBackend: .native,
                    selectionComponent: resolved.component
                ),
                resolved.candidate
            )
        }
        if let best {
            return best.candidate.rank == .object
                ? .resolvedOccurrence(best.hit)
                : .resolved(best.hit)
        }
        // The occurrence family needs no prepared topology, so a scope that
        // admits it has a supported query on any mounted frame and reports an
        // empty pixel as the miss it is.
        return carriesNativeFamily || selectionHitPolicy.allowsObjectHits ? .miss : .unsupported
    }

    /// Selection scopes whose rectangle the native frame answers from prepared
    /// B-Rep topology.
    ///
    /// `.all` and `.object` are excluded because a rectangle that allows object
    /// hits selects whole occurrences: the legacy filter already drops every
    /// body hit there, and the native occurrence rectangle carries the result.
    /// `.region` and `.sketchEntity` name geometry the prepared topology does
    /// not describe.
    private var usesNativeCADSubshapeRectangle: Bool {
        guard presentationScene != nil else {
            return false
        }
        switch selectionHitPolicy {
        case .face, .edge, .vertex:
            return true
        case .all, .object, .region, .sketchEntity:
            return false
        }
    }

    /// Outcome of the native CAD sub-shape rectangle query.
    ///
    /// `resolved` carries every sub-shape the native frame admitted.
    /// `requiresLegacyResidual` reports whether a CAD interaction body in the
    /// same scene still holds geometry the prepared topology cannot name — a
    /// body without face, edge or vertex targets, whose sub-objects the pick
    /// index projects from a bounding box, and, for the vertex scope, a body
    /// carrying surface knot, span, trim-knot or trim-span handles. Only then
    /// does the legacy resolver run alongside, stripped of everything the
    /// native query owns.
    ///
    /// `unsupported` reports that no CAD interaction body carried prepared
    /// topology at all, so the whole legacy path answers, exactly as the point
    /// query does.
    private enum NativeCADSubshapeRectangleResult {
        case resolved(hits: [ViewportHit], requiresLegacyResidual: Bool)
        case unsupported
    }

    /// Resolves every CAD face, edge and vertex the rectangle admits from
    /// prepared B-Rep topology, using the same native projection, occlusion and
    /// section rule that drew the frame.
    ///
    /// This is a set query with no rank: each admitted sub-shape is reported
    /// once per placement, keyed by the identity `SelectionTarget` defines of a
    /// `SceneNodeID` together with its `SelectionComponent`. A `SubshapeID`
    /// names the feature it belongs to, so scene items that place one shared
    /// feature more than once share its face, edge and vertex identities.
    /// De-duplicating by `SelectionComponentID` alone would drop every
    /// placement after the first.
    ///
    /// Vertices and edges are resolved per body, because each is a candidate the
    /// prepared topology names and the frame is asked about at that candidate's
    /// own pixels. Faces are resolved the other way round, from the triangles
    /// the frame draws inside the rectangle: the region raster reports those for
    /// the whole scene in one pass, and each `.cad` triangle names the body that
    /// emitted it and the emission index its recorded runs resolve. Harvesting
    /// once for the scene is why a face the frame draws in a window narrower
    /// than any candidate test could sample is still selected.
    private func presentationCADSubshapeRectangleHits(
        in rect: CGRect,
        in scene: ViewportScene
    ) throws -> NativeCADSubshapeRectangleResult {
        let identity = try presentationQueryIdentity()
        let revision = activeControlSession.revision
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: presentationPlanCache, identity: identity, revision: revision
        )
        // The interval belongs to the same mounted camera the projections come
        // from, so an edge crossing a clip plane is walked over the part that
        // camera draws instead of being dropped whole. It is read once for the
        // rectangle rather than once per body, which is the same question the
        // frame answered before.
        let depthInterval = try probe.cameraDepthInterval()
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionTarget> = []
        var requiresLegacyResidual = false
        // The bodies the face harvest can name, keyed by the scene node a drawn
        // triangle's occurrence resolves to. A placement absent here drew no
        // prepared topology, so its triangles name no CAD face.
        var bodies: [SceneNodeID: (featureID: FeatureID, topology: ViewportBodyTopology)] = [:]
        for item in scene.items {
            guard let sceneNodeID = item.sceneNodeID,
                  presentationCADInteractionSceneNodeIDs.contains(sceneNodeID),
                  case .body(let component) = item.kind else {
                continue
            }
            guard let topology = component.topology,
                  topology.faces.isEmpty == false
                      || topology.edges.isEmpty == false
                      || topology.vertices.isEmpty == false else {
                // The evaluation gave this body no stable sub-shape identity,
                // so the pick index answers it with sub-objects projected from
                // its bounding box and the native query has no CAD name to
                // report.
                requiresLegacyResidual = true
                continue
            }
            if selectionHitPolicy.allowsVertexHits,
               component.surfaceKnotDisplays.isEmpty == false
                   || component.surfaceSpanDisplays.isEmpty == false
                   || component.surfaceTrimKnotDisplays.isEmpty == false
                   || component.surfaceTrimSpanDisplays.isEmpty == false {
                requiresLegacyResidual = true
            }
            // The scene builder writes the recorded runs and the topology from
            // one body display snapshot or writes neither, so faces without the
            // runs that name them are malformed preparation. Without this the
            // harvest would resolve none of those faces and report the body as
            // holding nothing inside the rectangle.
            guard topology.faces.isEmpty || topology.meshFaceRuns.isEmpty == false else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidSceneItem,
                    message: "A CAD body prepared face topology without the mesh face runs that name it."
                )
            }
            bodies[sceneNodeID] = (featureID: item.featureID, topology: topology)
            let components = try ViewportNativeCADTopologyResolver.resolveRegion(
                in: rect,
                topology: topology,
                modelTransform: item.modelTransform,
                selectionHitPolicy: selectionHitPolicy,
                depthInterval: depthInterval,
                probe: probe
            )
            Self.appendRectangleSubshapeHits(
                components,
                featureID: item.featureID,
                sceneNodeID: sceneNodeID,
                into: &hits,
                admitted: &admitted
            )
        }
        guard bodies.isEmpty == false else {
            return .unsupported
        }
        if selectionHitPolicy.allowsFaceHits {
            // A triangle carries the occurrence that drew it, and mesh face
            // identities are numbered per body, so resolving the occurrence
            // first is what keeps another body's index from naming a run of
            // this one. An authored mesh triangle names no CAD face at all.
            try presentationPlanCache.forEachRegionTriangle(
                intersecting: rect, for: identity, revision: revision
            ) { triangle in
                guard case .cad = triangle.sourceReference else { return }
                guard let sceneNodeID = presentationSceneNodeIDByOccurrenceID[
                          triangle.occurrenceID
                      ],
                      let body = bodies[sceneNodeID] else { return }
                guard let componentID = try ViewportNativeCADTopologyResolver
                    .regionFaceComponentID(
                        forTriangle: triangle, topology: body.topology
                    ) else { return }
                Self.appendRectangleSubshapeHit(
                    .face(componentID),
                    featureID: body.featureID,
                    sceneNodeID: sceneNodeID,
                    into: &hits,
                    admitted: &admitted
                )
            }
        }
        return .resolved(hits: hits, requiresLegacyResidual: requiresLegacyResidual)
    }

    /// Appends the rectangle hits one scene item's admitted sub-shapes
    /// contribute, refusing a sub-shape this rectangle already reported.
    ///
    /// `admitted` spans the whole scene, so the identity it holds has to keep
    /// the placements of one shared feature apart: `ViewportSceneBuilder` gives
    /// every `SceneNodeID` that places a feature its own scene item over the
    /// same prepared topology, and those items therefore carry identical face,
    /// edge and vertex `SelectionComponentID`s. `SelectionTarget` is the
    /// identity the selection already names an editable sub-shape by, so the
    /// rectangle de-duplicates by it and reports each placement once.
    static func appendRectangleSubshapeHits(
        _ components: [SelectionComponent],
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        into hits: inout [ViewportHit],
        admitted: inout Set<SelectionTarget>
    ) {
        for selectionComponent in components {
            appendRectangleSubshapeHit(
                selectionComponent,
                featureID: featureID,
                sceneNodeID: sceneNodeID,
                into: &hits,
                admitted: &admitted
            )
        }
    }

    /// Appends the rectangle hit one admitted sub-shape contributes, refusing a
    /// sub-shape this rectangle already reported.
    ///
    /// The face harvest reports one drawn triangle at a time, and a frame this
    /// plan admits can draw hundreds of thousands of them inside a rectangle, so
    /// the single form is what the harvest calls: gathering each triangle's
    /// component into an array first would allocate once per drawn triangle for
    /// an answer the `admitted` set collapses anyway.
    static func appendRectangleSubshapeHit(
        _ selectionComponent: SelectionComponent,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        into hits: inout [ViewportHit],
        admitted: inout Set<SelectionTarget>
    ) {
        // The resolver reports face, edge and vertex components only; a
        // component naming no generated sub-shape has no rectangle identity
        // to report.
        guard rectangleComponentID(selectionComponent) != nil else { return }
        let target = SelectionTarget(sceneNodeID: sceneNodeID, component: selectionComponent)
        guard admitted.insert(target).inserted else { return }
        hits.append(
            ViewportHit(
                featureID: featureID,
                sceneNodeID: sceneNodeID,
                kind: .body,
                pickingBackend: .native,
                selectionComponent: selectionComponent
            )
        )
    }

    /// Whether the native rectangle query already owns this legacy hit.
    ///
    /// Ownership is decided by what produced the record, not by whether the
    /// native query happened to admit the same sub-shape: a CAD interaction
    /// body's generated face, edge and vertex records are exactly what prepared
    /// topology names, so keeping one would let the identity-buffer rule
    /// re-admit a sub-shape the native frame rejected as occluded, sectioned
    /// away, or outside the rectangle.
    private func nativeRectangleOwnsLegacyHit(_ hit: ViewportHit) -> Bool {
        guard hit.kind == .body,
              let sceneNodeID = hit.sceneNodeID,
              presentationCADInteractionSceneNodeIDs.contains(sceneNodeID),
              let component = hit.selectionComponent,
              let componentID = Self.rectangleComponentID(component) else {
            return false
        }
        return componentID.generatedTopologySubshapeID != nil
    }

    /// The identity a rectangle-admitted `SelectionComponent` is keyed by. The
    /// native rectangle resolver reports only face, edge and vertex components;
    /// the remaining cases name no generated sub-shape.
    private static func rectangleComponentID(
        _ component: SelectionComponent
    ) -> SelectionComponentID? {
        switch component {
        case .face(let componentID), .edge(let componentID), .vertex(let componentID):
            return componentID
        case .object, .sketchEntity, .region, .constructionPlane:
            return nil
        }
    }

    /// Resolves the native outcome into the hit the viewport acts on, asking
    /// the legacy resolver only where the native frame has no input path yet.
    private func resolvedViewportHit(
        _ result: NativeCADSubshapeResult,
        at point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout,
        presentationOccurrenceID: SceneOccurrenceID?
    ) -> ViewportHit? {
        switch result {
        case .resolved(let hit):
            return hit
        case .resolvedOccurrence(let hit):
            guard requiresLegacyHitFallback else {
                return hit
            }
            let legacy = legacyViewportHit(
                at: point,
                in: scene,
                layout: layout,
                presentationOccurrenceID: presentationOccurrenceID
            )
            return legacyOverlayAnswer(legacy) ?? hit
        case .miss where requiresLegacyHitFallback == false:
            return nil
        case .miss, .unsupported:
            return legacyViewportHit(
                at: point,
                in: scene,
                layout: layout,
                presentationOccurrenceID: presentationOccurrenceID
            )
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The native occurrence answer is complete,
    // but the overlay families that outrank it — curve segment, sketch entity,
    // sketch control point and sketch region — are still answered by the
    // pre-RealityKit identity resolver, so a pointer the occurrence wins has to
    // be ordered against a second, differently projected hit rule. That legacy
    // answer is not occlusion-tested against the mounted frame, so a sketch line
    // behind a body can still win the pointer; this preserves the behaviour the
    // replaced rule already had and does not introduce it.
    //
    // Production path: `resolvedViewportHit(_:at:in:layout:presentationOccurrenceID:)`
    // on the `.object` and `.all` scopes, which are the select tool's object
    // scope and the default hover scope.
    //
    // Do not treat the object scope as cut over while this exists. It is deleted
    // when the sketch and curve seams land and those families are produced by
    // `ViewportNativeOverlayHitResolver` as candidates this query orders itself,
    // not when the occurrence alone passes its tests.
    private func legacyOverlayAnswer(_ hit: ViewportHit?) -> ViewportHit? {
        guard let hit else {
            return nil
        }
        // Every legacy body answer is declined. It is the occurrence, which the
        // native frame now owns; a CAD sub-shape of it, which the native CAD
        // resolver already declined at this pointer; or a surface handle
        // display, which the native overlay resolver answers for on this same
        // frame. Re-admitting any of them would let a second, differently
        // projected rule contradict a family this path already owns.
        guard hit.kind != .body else {
            return nil
        }
        return hit
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This is the interim bridge to the
    // pre-RealityKit identity-buffer resolver, kept only for the scopes
    // `requiresLegacyHitFallback` still admits. Its completion condition is
    // recorded there; it is deleted with the resolver, not reimplemented.
    private func legacyViewportHit(
        at point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout,
        presentationOccurrenceID: SceneOccurrenceID?
    ) -> ViewportHit? {
        presentationFilteredLegacyHit(
            viewportHit(
                point: point,
                in: sceneBySuppressingSketches(
                    scene,
                    selectedFeatureIDs: selectedTargetFeatureIDs()
                ),
                layout: layout
            ),
            presentationOccurrenceID: presentationOccurrenceID
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
        // A native update failure is recorded against the mounted frame, which
        // is also the frame a query for this identity resolves against, so an
        // overlay-only rebuild must not hide it.
        guard let renderer = presentationPlanCache.displaySurface(for: identity),
              surfaceFailure?.rendererID == ObjectIdentifier(renderer) else { return nil }
        return surfaceFailure?.error
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
              nativeInputGesture == nil,
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

    private var snapOverlayContext: ViewportSnapOverlayContext {
        ViewportSnapOverlayContext(activeCanvasDrag: activeCanvasDrag)
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
              hoveredCanvasHit?.bodyVertex == nil,
              Self.designatesBodySubshape(hoveredCanvasHit) == false else {
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

    /// Native CAD hits carry their sub-shape in `selectionComponent`; the
    /// legacy body face, edge and vertex fields stay nil for them.
    private static func designatesBodySubshape(_ hit: ViewportHit?) -> Bool {
        switch hit?.selectionComponent {
        case .face, .edge, .vertex:
            return true
        default:
            return false
        }
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


    private func displayedSketchDimensionLine(
        featureID: FeatureID,
        entityID: SketchEntityID,
        start: CGPoint,
        end: CGPoint
    ) -> (start: CGPoint, end: CGPoint) {
        guard let preview = nativeWorldPointPreview,
              case .sketchDimension(let value) = preview.value,
              case .sketchDimension(let handle) = preview.target,
              handle.featureID == featureID,
              handle.entityID == entityID else {
            return (start, end)
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let currentLength = hypot(dx, dy)
        guard currentLength > 1.0e-12 else {
            return (start, end)
        }
        switch handle.kind {
        case .length:
            let length = CGFloat(value)
            return (
                start,
                CGPoint(
                    x: start.x + dx / currentLength * length,
                    y: start.y + dy / currentLength * length
                )
            )
        case .angle:
            let length = CGFloat(currentLength)
            return (
                start,
                CGPoint(
                    x: start.x + cos(CGFloat(value)) * length,
                    y: start.y + sin(CGFloat(value)) * length
                )
            )
        case .radius, .diameter:
            return (start, end)
        }
    }

    private func displayedSketchArcParameters(
        featureID: FeatureID,
        entityID: SketchEntityID,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> (radiusMeters: Double, startAngleRadians: Double, endAngleRadians: Double) {
        guard let preview = nativeWorldPointPreview else {
            return (radiusMeters, startAngleRadians, endAngleRadians)
        }
        switch (preview.target, preview.value) {
        case (
            .sketchCurveHandle(let handle),
            .sketchCurveHandle(let previewRadius, let previewStart, let previewEnd)
        ):
            guard handle.featureID == featureID, handle.entityID == entityID else {
                return (radiusMeters, startAngleRadians, endAngleRadians)
            }
            return (
                previewRadius ?? radiusMeters,
                previewStart ?? startAngleRadians,
                previewEnd ?? endAngleRadians
            )
        case (.sketchDimension(let handle), .sketchDimension(let value)):
            guard handle.featureID == featureID, handle.entityID == entityID else {
                return (radiusMeters, startAngleRadians, endAngleRadians)
            }
            switch handle.kind {
            case .radius:
                return (value, startAngleRadians, endAngleRadians)
            case .angle:
                return (radiusMeters, startAngleRadians, startAngleRadians + value)
            case .length, .diameter:
                return (radiusMeters, startAngleRadians, endAngleRadians)
            }
        default:
            return (radiusMeters, startAngleRadians, endAngleRadians)
        }
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

    private func formattedViewportLength(_ meters: Double) -> String {
        ViewportLengthLabelFormatter.string(
            fromMeters: meters,
            preferredUnit: workspaceRuler.displayUnit
        )
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
        guard let preview = nativeWorldPointPreview,
              case .sketchDisplayDelta(let displayDelta) = preview.value,
              case .sketchPointHandle(let target) = preview.target,
              target.featureID == featureID,
              target.entityID == entityID,
              target.handle == handle else {
            return point
        }
        return CGPoint(
            x: point.x + displayDelta.x,
            y: point.y + displayDelta.y
        )
    }


    private func displayedSplineControlPoints(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPoints: [CGPoint]
    ) -> [CGPoint] {
        if let preview = nativeWorldPointPreview,
           case .sketchDisplayDelta(let displayDelta) = preview.value,
           case .splineControlPoint(let target) = preview.target,
           target.featureID == featureID,
           target.entityID == entityID,
           controlPoints.indices.contains(target.controlPointIndex) {
            var updatedControlPoints = controlPoints
            updatedControlPoints[target.controlPointIndex].x += displayDelta.x
            updatedControlPoints[target.controlPointIndex].y += displayDelta.y
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

    /// A selected CAD face together with the run list that names its triangles.
    private struct SelectedGeneratedTopologyFace {
        var sceneNodeID: SceneNodeID
        var componentID: SelectionComponentID
        var topology: ViewportBodyTopology
    }

    /// The selected CAD face, when one is eligible for an exact surface point.
    ///
    /// Answering costs no frame query. It reports only whether the selection
    /// names a kernel-generated face on a body the native CAD interaction set
    /// covers, and hands back the prepared run list for that body. A caller
    /// uses it to decide whether asking the mounted frame for a surface point
    /// is worth a query at all.
    private func selectedGeneratedTopologyFace(
        in scene: ViewportScene
    ) -> SelectedGeneratedTopologyFace? {
        guard presentationScene != nil,
              let target = selection.primaryTarget,
              case .face(let componentID) = target.component,
              componentID.generatedTopologySubshapeID != nil,
              let item = sceneItem(for: target, in: scene),
              let sceneNodeID = item.sceneNodeID,
              presentationCADInteractionSceneNodeIDs.contains(sceneNodeID),
              case .body(let component) = item.kind,
              let topology = component.topology else {
            return nil
        }
        return SelectedGeneratedTopologyFace(
            sceneNodeID: sceneNodeID,
            componentID: componentID,
            topology: topology
        )
    }

    /// The exact world point of the selected CAD face, taken from the frame.
    ///
    /// The mounted frame already decided which triangle it drew at this pixel
    /// and where the view ray met it, and the prepared run list names the CAD
    /// face that emitted that triangle. So this answers with the frame's own
    /// point when the drawn triangle belongs to the selected face, and with
    /// `nil` when the frame drew something else there: another body, an
    /// authored mesh, another face of the same body, or nothing at all. A face
    /// the frame did not draw is occluded at that pixel, and an occluded face
    /// has no surface point there to offer.
    private func selectedCADFaceSurfaceWorldPoint(
        _ surface: (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        face: SelectedGeneratedTopologyFace
    ) throws -> Point3D? {
        guard let surface,
              case .cad = surface.triangle.sourceReference,
              presentationSceneNodeIDByOccurrenceID[surface.triangle.occurrenceID] == face.sceneNodeID
        else {
            return nil
        }
        // The universal mesh source names a CAD body's triangles by their
        // emission index, so the raw value is that index. A value no `Int` can
        // hold is malformed provenance rather than a miss, and answering `nil`
        // would let the caller intersect the sketch plane instead, as if the
        // frame had drawn nothing here.
        guard let triangleIndex = Int(exactly: surface.triangle.faceID.rawValue) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidSceneItem,
                message: "A drawn CAD triangle reports an unrepresentable mesh face identity."
            )
        }
        guard face.topology.componentID(forTriangle: triangleIndex) == face.componentID else {
            return nil
        }
        return surface.point
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

    /// Edit states for the bodies a native affordance record names.
    ///
    /// The member's own prepared state is the answer: the producer resolved it
    /// from the same `editedBodies` entry this drag would read, and the record
    /// is admitted only from a frame prepared for the current overlay
    /// revision, which `editedBodies` participates in. Reading the live entry
    /// here would give one value two owners without being able to differ.
    ///
    /// A feature selected through several scene nodes contributes one entry, so
    /// the drag applies one transform per feature just as `editedBodies` stores
    /// one state per feature.
    private func bodyEditStates(
        for members: [ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember]
    ) -> [FeatureID: ViewportObjectEditState] {
        Dictionary(
            members.map { member in (member.featureID, member.edit) },
            uniquingKeysWith: { first, _ in first }
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
            if openNativeGestureFinishRevision != nil { return }
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
        if nativeInputGesture != nil {
            switch nativeInputGesture {
            case .sketchTransform: updateSketchTransformGesture(current: current)
            case .pattern: updateNativePatternGesture(current: current)
            case .worldPoint: updateNativeWorldPointGesture(current: current)
            case .active, .cancelled, nil: _ = updateNativeAxisGesture(current: current)
            }
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
        nativeInputGesture = nil
        pendingInteractionTarget = nil
        pendingNativeAffordance = nil
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

    /// The prepared interaction the native frame ranks first at this point.
    ///
    /// The frame owns the priority order, so the pointer routes read only its
    /// leading record and never re-rank the handles the frame drew.
    private func nativeInteractionRecord(at point: CGPoint) throws -> ViewportSpatialInteractionRecord? {
        try presentationPlanCache.interactionRecords(
            at: point, for: presentationQueryIdentity(), revision: activeControlSession.revision
        ).first
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
        case .patternArrayLinearAxis: onPatternArrayLinearAxisDrag != nil
        case .independentCopyExtrudeDistance: onIndependentCopyExtrudeDistanceDrag != nil
        case .independentCopyBodyDimension: onIndependentCopyBodyDimensionDrag != nil
        // Only the axis and local-axis handles of these two routes reduce to
        // one world-axis delta. Their planar handle is the world-point
        // owner's, so the gate mirrors that split rather than enabling the
        // whole case.
        case .polySplineSurfaceVertex(let value):
            value.dragMode != .planar && onPolySplineSurfaceVertexDrag != nil
        case .surfaceControlPoint(let value):
            value.dragMode != .planar && onSurfaceControlPointDrag != nil
        default: false
        }
    }

    private func nativePatternRouteEnabled(_ target: ViewportSpatialPreparedInteractionTarget) -> Bool {
        switch target {
        case .patternArrayRadialAngle: onPatternArrayRadialAngleDrag != nil
        case .patternArrayCopyCount: onPatternArrayCopyCountDrag != nil
        case .patternArrayCurveExtent: onPatternArrayCurveExtentDrag != nil
        case .patternArrayOutputMode: onPatternArrayOutputModeChange != nil
        default: false
        }
    }

    private func nativeWorldPointRouteEnabled(
        _ target: ViewportSpatialPreparedInteractionTarget
    ) -> Bool {
        switch target {
        case .constructionPlane: onConstructionPlaneHandleDrag != nil
        case .patternArrayCurvePathPoint: onPatternArrayCurvePathPointDrag != nil
        case .bridgeCurveEndpoint: onBridgeCurveEndpointDrag != nil
        case .polySplineSurfaceVertex(let value):
            value.dragMode == .planar && onPolySplineSurfaceVertexDrag != nil
        case .surfaceControlPoint(let value):
            value.dragMode == .planar && onSurfaceControlPointDrag != nil
        case .surfaceTrimEndpoint: onSurfaceTrimEndpointDrag != nil
        case .surfaceTrimControlPoint: onSurfaceTrimControlPointDrag != nil
        case .sketchCurveHandle: onSketchCurveHandleDrag != nil
        case .sketchDimension: onSketchDimensionDrag != nil
        case .sketchPointHandle: onSketchPointHandleDrag != nil
        case .splineControlPoint: onSplineControlPointDrag != nil
        default: false
        }
    }

    private var hoveredSpatialHandleIdentity: ViewportSpatialHandleIdentity? {
        get throws { try hoveredNativeHandleIdentity ?? hoveredInteractionTarget?.spatialIdentity }
    }

    private var pendingSpatialHandleIdentity: ViewportSpatialHandleIdentity? {
        get throws {
            switch nativeInputGesture {
            case .active(let press): return press.input.record.identity
            case .sketchTransform(let press): return press.identity
            case .pattern(let press): return press.input.record.identity
            case .worldPoint(let press): return press.input.identity
            case .cancelled, nil: return try pendingInteractionTarget?.spatialIdentity
            }
        }
    }

    /// Reports a refused native gesture.
    ///
    /// The viewport owns no workspace error channel, so a refusal is surfaced
    /// the way the other overlay refusals are rather than being dropped, and it
    /// is never turned into a committed value.
    private func reportNativeGestureFailure(_ error: Error) {
        let description = (error as? MeshSourcePresentationRenderError)?.message
            ?? error.localizedDescription
        Self.nativeGestureLogger.warning(
            "Native viewport gesture refused: \(description, privacy: .public)"
        )
    }

    private func cancelNativeInputGesture() {
        guard nativeInputGesture != nil else { return }
        nativeInputGesture = .cancelled
        hoveredNativeHandleIdentity = nil
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
        if case .active(let press) = nativeInputGesture, !nativeAxisBaselineMatches(press.input) {
            cancelNativeInputGesture()
        }
    }

    private func updateNativeAxisGesture(current: CGPoint) -> Bool {
        guard case .active(var press) = nativeInputGesture else { return false }
        guard press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              press.finish == nil || press.finish?.revision == activeControlSession.revision,
              nativeAxisBaselineMatches(press.input),
              nativeAxisRouteEnabled(press.input.record.target) else {
            cancelNativeInputGesture()
            return false
        }
        do {
            let delta = try presentationPlanCache.worldAxisDelta(
                from: press.start, to: current,
                axisOrigin: press.input.axis.origin, axisDirection: press.input.axis.direction,
                for: presentationQueryIdentity(), revision: activeControlSession.revision
            )
            press.value = try press.input.value(forWorldDelta: delta)
            nativeInputGesture = .active(press)
            return true
        } catch {
            // A self-preview replaces the scene, so no frame is mounted for the
            // new identity until it is drawn. Keep the press baseline; no update
            // or commit is authorized until that frame answers.
            return false
        }
    }

    /// Opens a pattern gesture by materializing the prepared record against the
    /// mounted camera projection exactly once.
    ///
    /// The frame that answered this press with a record is mounted for this
    /// identity and revision, so a projection failure here is a degenerate
    /// handle rather than an unprepared frame: the press is refused and
    /// reported instead of falling through to a legacy selector.
    private func beginNativePatternPress(record: ViewportSpatialInteractionRecord, at point: CGPoint) {
        let revision = activeControlSession.revision
        do {
            let identity = try presentationQueryIdentity()
            guard let input = try ViewportNativePatternInput(record: record, project: {
                try presentationPlanCache.project($0, for: identity, revision: revision)
            }) else {
                nativeInputGesture = .cancelled
                return
            }
            nativeInputGesture = .pattern(.init(
                input: input,
                source: sourceIdentity,
                snapshotID: presentationScene?.snapshotID,
                selectedTargets: selection.selectedTargets,
                selectedReferences: selection.selectedReferences,
                revision: revision,
                start: point
            ))
            activeCanvasDrag = nil
        } catch {
            reportNativeGestureFailure(error)
            nativeInputGesture = .cancelled
        }
    }

    /// Whether the pattern press still describes the frame it was materialized
    /// against.
    ///
    /// The retained projection is a closed sample of one camera revision, so a
    /// revision change ends the gesture instead of reading a stale screen
    /// basis; the axis owner tolerates the same change because it re-queries
    /// the mounted camera on every update.
    private func nativePatternPressMatches(_ press: NativePatternPress) -> Bool {
        press.source == sourceIdentity
            && press.snapshotID == presentationScene?.snapshotID
            && press.selectedTargets == selection.selectedTargets
            && press.selectedReferences == selection.selectedReferences
            && press.revision == activeControlSession.revision
            && nativePatternRouteEnabled(press.input.record.target)
    }

    private func updateNativePatternGesture(current: CGPoint) {
        guard case .pattern(var press) = nativeInputGesture else { return }
        guard nativePatternPressMatches(press) else {
            cancelNativeInputGesture()
            return
        }
        do {
            // A pointer that names no direction leaves the retained value
            // unchanged rather than substituting one.
            if let value = try press.input.value(start: press.start, current: current) {
                press.value = value
                nativeInputGesture = .pattern(press)
            }
        } catch {
            reportNativeGestureFailure(error)
            cancelNativeInputGesture()
        }
    }

    private func finishNativePatternDrag(_ press: NativePatternPress) {
        let commit: ViewportNativePatternInput.Commit?
        if nativePatternPressMatches(press) {
            do {
                commit = try press.input.commit(value: press.value)
            } catch {
                reportNativeGestureFailure(error)
                commit = nil
            }
        } else {
            commit = nil
        }
        applyNativePatternCommit(commit)
    }

    /// Commits the click-only pattern route.
    ///
    /// Output mode owns no drag state, so its press resolves on the release
    /// that stayed on the projected label rather than through the drag path.
    private func finishNativePatternClick(_ press: NativePatternPress, at point: CGPoint) {
        let commit: ViewportNativePatternInput.Commit?
        if nativePatternPressMatches(press) {
            do {
                commit = try press.input.outputModeCommit(releasedAt: point)
            } catch {
                reportNativeGestureFailure(error)
                commit = nil
            }
        } else {
            commit = nil
        }
        applyNativePatternCommit(commit)
    }

    private func applyNativePatternCommit(_ commit: ViewportNativePatternInput.Commit?) {
        // Release input ownership before calling external mutation callbacks.
        clearPendingCanvasInteractionTargets()
        activeCanvasDrag = nil
        guard let commit else { return }
        switch commit {
        case .patternArrayRadialAngle(let target): onPatternArrayRadialAngleDrag?(target)
        case .patternArrayCopyCount(let target): onPatternArrayCopyCountDrag?(target)
        case .patternArrayCurveExtent(let target): onPatternArrayCurveExtentDrag?(target)
        case .patternArrayOutputMode(let target): onPatternArrayOutputModeChange?(target)
        }
    }

    /// The control-session revision a released gesture is still waiting on,
    /// whichever native route owns it. A released gesture holds input ownership
    /// until the frame for that revision answers, so every site that must keep
    /// the press alive across the release reads one value.
    private var openNativeGestureFinishRevision: UInt64? {
        switch nativeInputGesture {
        case .active(let press): press.finish?.revision
        case .sketchTransform(let press): press.finish?.revision
        case .worldPoint(let press): press.finish?.revision
        // The pattern owner reads its retained projection, so its release
        // never waits on a later frame.
        case .pattern, .cancelled, nil: nil
        }
    }

    private func finishNativeInputGesture(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else {
            if nativeInputGesture == nil {
                clearPendingCanvasInteractionTargets()
            } else {
                cancelNativeInputGesture()
            }
            return
        }
        switch nativeInputGesture {
        case .active(var press):
            press.finish = (point, activeControlSession.revision)
            nativeInputGesture = .active(press)
            resumeNativeAxisFinish()
        case .sketchTransform(var press):
            press.finish = (point, activeControlSession.revision)
            nativeInputGesture = .sketchTransform(press)
            resumeSketchTransformFinish()
        case .worldPoint(var press):
            press.finish = (point, activeControlSession.revision)
            nativeInputGesture = .worldPoint(press)
            resumeNativeWorldPointFinish()
        case .pattern:
            // The release point is the last sample of the gesture. The input
            // surface reports no drag preview at it, so a release that left the
            // last reported position is read here and nowhere else. Evaluating
            // it through the update path keeps the drag and the release on one
            // rule: a pointer that names no direction keeps the retained value,
            // and a refused sample ends the gesture instead of committing.
            updateNativePatternGesture(current: point)
            if case .pattern(let press) = nativeInputGesture {
                finishNativePatternDrag(press)
            } else {
                // The update refused the release, which cancelled the gesture
                // without releasing input ownership. Release it here.
                applyNativePatternCommit(nil)
            }
        case .cancelled, nil:
            clearPendingCanvasInteractionTargets()
        }
    }

    private func resumeNativeAxisFinish() {
        guard case .active(let press) = nativeInputGesture, let finish = press.finish else { return }
        guard finish.revision == activeControlSession.revision,
              press.source == sourceIdentity, press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              nativeAxisBaselineMatches(press.input), nativeAxisRouteEnabled(press.input.record.target) else {
            cancelNativeInputGesture()
            return
        }
        let commit: ViewportNativeAxisInput.Commit?
        do {
            let identity = try presentationPreparation.get()
            if let failure = presentationPlanCache.failure(for: identity) { throw failure }
            guard presentationPlanCache.hasReadyCamera(for: identity, revision: finish.revision) else { return }
            let updated = updateNativeAxisGesture(current: finish.point)
            if updated, case .active(let press) = nativeInputGesture, let value = press.value {
                commit = try press.input.commit(value: value)
            } else if case .active = nativeInputGesture {
                // The mounted frame already answered for this revision, so a
                // refusal here belongs to the query rather than to a frame that
                // has not been drawn yet. The pointer is released, so nothing
                // later in this gesture could report it.
                throw RealityViewportSpatialBatch.invalid(
                    "A released native axis gesture read no value from the mounted frame."
                )
            } else {
                // The update refused the gesture on its own state guards and
                // has already cancelled it.
                commit = nil
            }
        } catch {
            // Invalid native values never reach a source mutation callback, and
            // the refusal is reported rather than dropped at mouse-up.
            reportNativeGestureFailure(error)
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
        case .patternArrayLinearAxis(let target): onPatternArrayLinearAxisDrag?(target)
        case .independentCopyExtrudeDistance(let target): onIndependentCopyExtrudeDistanceDrag?(target)
        case .independentCopyBodyDimension(let target): onIndependentCopyBodyDimensionDrag?(target)
        case .polySplineSurfaceVertex(let target): onPolySplineSurfaceVertexDrag?(target)
        case .surfaceControlPoint(let target): onSurfaceControlPointDrag?(target)
        }
    }

    /// Whether the sketch transform route owns production input this frame.
    ///
    /// The route commits a scene-node frame rather than CAD topology, so it is
    /// gated by the bound commit callback alone. The producer registers a
    /// record under the same predicate, and press, update, hover, and release
    /// re-read it, so a route that loses its callback cancels instead of
    /// committing.
    private var sketchTransformRouteEnabled: Bool { onSketchTransformCommit != nil }

    /// Reads the mounted frame once for the single query this role names.
    private func sketchTransformSample(
        for input: ViewportSketchTransformInput,
        from start: CGPoint,
        to current: CGPoint
    ) throws -> ViewportSketchTransformInput.Sample {
        let identity = try presentationQueryIdentity()
        let revision = activeControlSession.revision
        switch try input.query {
        case .worldAxisDelta(let origin, let direction):
            return .worldAxisDelta(
                try presentationPlanCache.worldAxisDelta(
                    from: start,
                    to: current,
                    axisOrigin: origin,
                    axisDirection: direction,
                    for: identity,
                    revision: revision
                )
            )
        case .worldPlanePoint(let origin, let normal):
            // Both ends resolve against the same revision, so a camera move
            // during the drag cannot mix two projections into one turn.
            let from = try presentationPlanCache.worldPlaneIntersection(
                at: start,
                planeOrigin: origin,
                planeNormal: normal,
                for: identity,
                revision: revision
            )
            let to = try presentationPlanCache.worldPlaneIntersection(
                at: current,
                planeOrigin: origin,
                planeNormal: normal,
                for: identity,
                revision: revision
            )
            return .worldPlanePoints(start: from, current: to)
        }
    }

    @discardableResult
    private func updateSketchTransformGesture(current: CGPoint) -> Bool {
        guard case .sketchTransform(var press) = nativeInputGesture else { return false }
        guard press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              press.finish == nil || press.finish?.revision == activeControlSession.revision,
              sketchTransformRouteEnabled else {
            cancelNativeInputGesture()
            return false
        }
        do {
            let sample = try sketchTransformSample(
                for: press.input, from: press.start, to: current
            )
            press.mutation = try press.input.worldMutation(for: sample)
            nativeInputGesture = .sketchTransform(press)
            return true
        } catch {
            // A frame that is not yet mounted for this revision and a role's own
            // refusal raise the same error type, so an open drag cannot tell
            // them apart. It keeps the last preview and authorizes nothing; the
            // release point resolves the gesture and reports its refusal there.
            return false
        }
    }

    private func resumeSketchTransformFinish() {
        guard case .sketchTransform(let press) = nativeInputGesture,
              let finish = press.finish else { return }
        guard finish.revision == activeControlSession.revision,
              press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              sketchTransformRouteEnabled else {
            cancelNativeInputGesture()
            return
        }
        let target: ViewportSketchTransformDragTarget?
        do {
            let identity = try presentationPreparation.get()
            if let failure = presentationPlanCache.failure(for: identity) { throw failure }
            guard presentationPlanCache.hasReadyCamera(for: identity, revision: finish.revision) else { return }
            let sample = try sketchTransformSample(
                for: press.input, from: press.start, to: finish.point
            )
            target = try press.input.commit(
                worldMutation: try press.input.worldMutation(for: sample)
            )
        } catch {
            // The frame answered for this revision, so the refusal belongs to
            // the gesture and never reaches the scene-node mutation callback.
            reportNativeGestureFailure(error)
            target = nil
        }
        // Release input ownership before calling external mutation callbacks.
        clearPendingCanvasInteractionTargets()
        activeCanvasDrag = nil
        guard let target else { return }
        onSketchTransformCommit?(target)
    }

    /// Opens a world-point gesture from the prepared record the mounted frame
    /// answered this press with.
    ///
    /// The record is validated once here, so a degenerate handle is refused at
    /// the press instead of producing a preview that no later update can
    /// resolve.
    private func beginNativeWorldPointPress(
        record: ViewportSpatialInteractionRecord, at point: CGPoint
    ) {
        do {
            guard let input = try ViewportNativeWorldPointInput(record: record) else {
                nativeInputGesture = .cancelled
                return
            }
            nativeInputGesture = .worldPoint(.init(
                input: input,
                source: sourceIdentity,
                snapshotID: presentationScene?.snapshotID,
                selectedTargets: selection.selectedTargets,
                selectedReferences: selection.selectedReferences,
                start: point
            ))
            activeCanvasDrag = nil
        } catch {
            reportNativeGestureFailure(error)
            nativeInputGesture = .cancelled
        }
    }

    /// Reads the mounted frame once for the single plane this role names.
    ///
    /// The plane is named per update from the projection mode in force now,
    /// and both ends of the sample resolve against one revision, so a camera
    /// move during the drag cannot mix two projections into one delta.
    private func nativeWorldPointSample(
        for input: ViewportNativeWorldPointInput,
        from start: CGPoint,
        to current: CGPoint
    ) throws -> ViewportNativeWorldPointInput.Sample {
        let identity = try presentationQueryIdentity()
        let revision = activeControlSession.revision
        switch try input.query(
            displayedCanvas: ViewportCanvasPlane.displayed(for: currentProjectionBasis)
        ) {
        case .worldPlane(let origin, let normal):
            let from = try presentationPlanCache.worldPlaneIntersection(
                at: start,
                planeOrigin: origin,
                planeNormal: normal,
                for: identity,
                revision: revision
            )
            let to = try presentationPlanCache.worldPlaneIntersection(
                at: current,
                planeOrigin: origin,
                planeNormal: normal,
                for: identity,
                revision: revision
            )
            return .init(start: from, current: to)
        case .viewPlane(let anchor):
            // Only the mounted frame knows the direction it is looking along,
            // so the view plane is resolved there rather than reconstructed
            // from a projection basis this view happens to hold.
            let from = try presentationPlanCache.viewPlaneIntersection(
                at: start, through: anchor, for: identity, revision: revision
            )
            let to = try presentationPlanCache.viewPlaneIntersection(
                at: current, through: anchor, for: identity, revision: revision
            )
            return .init(start: from, current: to)
        }
    }

    private func nativeWorldPointValue(
        for input: ViewportNativeWorldPointInput,
        from start: CGPoint,
        to current: CGPoint
    ) throws -> ViewportNativeWorldPointInput.Value {
        try input.value(
            for: try nativeWorldPointSample(for: input, from: start, to: current),
            document: document,
            ruler: workspaceRuler,
            snapOptions: snapResolutionOptions
        )
    }

    @discardableResult
    private func updateNativeWorldPointGesture(current: CGPoint) -> Bool {
        guard case .worldPoint(var press) = nativeInputGesture else { return false }
        guard press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              press.finish == nil || press.finish?.revision == activeControlSession.revision,
              nativeWorldPointRouteEnabled(press.input.record.target) else {
            cancelNativeInputGesture()
            return false
        }
        do {
            press.value = try nativeWorldPointValue(
                for: press.input, from: press.start, to: current
            )
            nativeInputGesture = .worldPoint(press)
            return true
        } catch {
            // A frame that is not yet mounted for this revision and a role's own
            // refusal raise the same error type, so an open drag cannot tell
            // them apart. It keeps the last preview and authorizes nothing; the
            // release point resolves the gesture and reports its refusal there.
            return false
        }
    }

    /// The open world-point gesture's prepared route and resolved preview.
    ///
    /// The record and the value are read as one pair, so a preview can never be
    /// attributed to a handle other than the pressed one.
    private var nativeWorldPointPreview: (
        identity: ViewportSpatialHandleIdentity,
        target: ViewportSpatialPreparedInteractionTarget,
        value: ViewportNativeWorldPointInput.Value
    )? {
        guard case .worldPoint(let press) = nativeInputGesture,
              let value = press.value else { return nil }
        return (press.input.identity, press.input.record.target, value)
    }

    private var nativeConstructionPlanePreview: (
        identity: ViewportSpatialHandleIdentity, origin: Point3D, normal: Vector3D
    )? {
        guard let preview = nativeWorldPointPreview,
              case .constructionPlane(let origin, let normal) = preview.value else { return nil }
        return (preview.identity, origin, normal)
    }

    private var nativeCurvePathPointPreview: ViewportPatternArrayCurvePathPointDragTarget? {
        guard let preview = nativeWorldPointPreview,
              case .patternArrayCurvePathPoint(let source) = preview.target,
              case .patternArrayCurvePathPoint(let point) = preview.value else { return nil }
        return .init(sourceID: source.sourceID, pointIndex: source.pointIndex, point: point)
    }

    private var nativeBridgeCurveEndpointPreview: (
        identity: ViewportSpatialHandleIdentity,
        endpoint: BridgeCurveEndpoint,
        parameter: Double
    )? {
        guard let preview = nativeWorldPointPreview,
              case .bridgeCurveEndpoint(let endpoint, let parameter) = preview.value else {
            return nil
        }
        return (preview.identity, endpoint, parameter)
    }

    /// The open world-point gesture's surface handle displacement, stated in
    /// the record's own model space.
    ///
    /// The prepared case travels with the delta because the four surface
    /// routes differ in whether the overlay draws the original placement for
    /// comparison, and that choice belongs to the route rather than the value.
    private var nativeSurfaceHandlePreview: (
        identity: ViewportSpatialHandleIdentity,
        target: ViewportSpatialPreparedInteractionTarget,
        delta: Vector3D
    )? {
        guard let preview = nativeWorldPointPreview,
              case .surfaceHandleLocalDelta(let delta) = preview.value else { return nil }
        return (preview.identity, preview.target, delta)
    }

    private func resumeNativeWorldPointFinish() {
        guard case .worldPoint(let press) = nativeInputGesture,
              let finish = press.finish else { return }
        guard finish.revision == activeControlSession.revision,
              press.source == sourceIdentity,
              press.snapshotID == presentationScene?.snapshotID,
              press.selectedTargets == selection.selectedTargets,
              press.selectedReferences == selection.selectedReferences,
              nativeWorldPointRouteEnabled(press.input.record.target) else {
            cancelNativeInputGesture()
            return
        }
        let commit: ViewportNativeWorldPointInput.Commit?
        do {
            let identity = try presentationPreparation.get()
            if let failure = presentationPlanCache.failure(for: identity) { throw failure }
            guard presentationPlanCache.hasReadyCamera(for: identity, revision: finish.revision) else { return }
            let value = try nativeWorldPointValue(
                for: press.input, from: press.start, to: finish.point
            )
            commit = try press.input.commit(value: value, document: document)
        } catch {
            // The frame answered for this revision, so the refusal belongs to
            // the gesture and never reaches the document mutation callbacks.
            reportNativeGestureFailure(error)
            commit = nil
        }
        // Release input ownership before calling external mutation callbacks.
        clearPendingCanvasInteractionTargets()
        activeCanvasDrag = nil
        switch commit {
        case .constructionPlane(let target): onConstructionPlaneHandleDrag?(target)
        case .patternArrayCurvePathPoint(let target): onPatternArrayCurvePathPointDrag?(target)
        case .bridgeCurveEndpoint(let target): onBridgeCurveEndpointDrag?(target)
        case .polySplineSurfaceVertex(let target): onPolySplineSurfaceVertexDrag?(target)
        case .surfaceControlPoint(let target): onSurfaceControlPointDrag?(target)
        case .surfaceTrimEndpoint(let target): onSurfaceTrimEndpointDrag?(target)
        case .surfaceTrimControlPoint(let target): onSurfaceTrimControlPointDrag?(target)
        case .sketchCurveHandle(let target): onSketchCurveHandleDrag?(target)
        case .sketchDimension(let target): onSketchDimensionDrag?(target)
        case .sketchPointHandle(let target): onSketchPointHandleDrag?(target)
        case .splineControlPoint(let target): onSplineControlPointDrag?(target)
        case nil: break
        }
    }

    private func beginViewportPress(at point: CGPoint) {
        if measurementToolActive {
            clearPendingCanvasInteractionTargets()
            activeCanvasDrag = nil
            return
        }
        clearPendingCanvasInteractionTargets()
        do {
            if let record = try nativeInteractionRecord(at: point) {
                if let input = try ViewportNativeAxisInput(record: record) {
                    guard nativeAxisRouteEnabled(record.target) else {
                        nativeInputGesture = .cancelled
                        return
                    }
                    nativeInputGesture = .active(.init(
                        input: input, source: sourceIdentity, snapshotID: presentationScene?.snapshotID,
                        selectedTargets: selection.selectedTargets,
                        selectedReferences: selection.selectedReferences, start: point
                    ))
                    activeCanvasDrag = nil
                    return
                }
                if let input = try ViewportSketchTransformInput(record: record) {
                    guard sketchTransformRouteEnabled else {
                        nativeInputGesture = .cancelled
                        return
                    }
                    nativeInputGesture = .sketchTransform(.init(
                        input: input,
                        identity: record.identity,
                        source: sourceIdentity,
                        snapshotID: presentationScene?.snapshotID,
                        selectedTargets: selection.selectedTargets,
                        selectedReferences: selection.selectedReferences,
                        start: point
                    ))
                    activeCanvasDrag = nil
                    return
                }
                if ViewportNativePatternInput.claims(record.target) {
                    guard nativePatternRouteEnabled(record.target) else {
                        nativeInputGesture = .cancelled
                        return
                    }
                    beginNativePatternPress(record: record, at: point)
                    return
                }
                if ViewportNativeWorldPointInput.claims(record.target) {
                    guard nativeWorldPointRouteEnabled(record.target) else {
                        nativeInputGesture = .cancelled
                        return
                    }
                    beginNativeWorldPointPress(record: record, at: point)
                    return
                }
                if case .affordance(let target, let members, let groupEdit) = record.target {
                    setPendingInteractionTarget(.affordance(target))
                    pendingNativeAffordance = ViewportNativeAffordanceClaim(
                        target: target, members: members, groupEdit: groupEdit
                    )
                    activeCanvasDrag = nil
                    return
                }
            }
        } catch {
            nativeInputGesture = .cancelled
            return
        }
    }

    private func setPendingInteractionTarget(_ target: ViewportInteractionTarget) {
        pendingInteractionTarget = target
    }

    private func clearActiveInteractionDrags(except preservedTarget: ViewportInteractionTarget? = nil) {
        activeInteractionDrags.clear(except: preservedTarget)
    }

    private var hasActiveInteractionDrag: Bool {
        if case .active(let press) = nativeInputGesture, press.value != nil { return true }
        if case .sketchTransform(let press) = nativeInputGesture, press.mutation != nil { return true }
        if case .pattern(let press) = nativeInputGesture, press.value != nil { return true }
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
        case .splineControlPointSlide(let target):
            updateSplineControlPointSlideDrag(target: target, start: start, current: current, size: size)
        case .polySplineSurfaceVertexSlide(let target):
            updatePolySplineSurfaceVertexSlideDrag(target: target, start: start, current: current, size: size)
        case .surfaceControlPointSlide(let target):
            updateSurfaceControlPointSlideDrag(target: target, start: start, current: current, size: size)
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
        case .affordance(let target):
            updateAffordanceDrag(target: target, start: start, current: current)
        }
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

    /// The mounted frame every affordance drag measures against.
    ///
    /// The preparation identity and the control revision are read once per
    /// update or commit, so both ends of a two-point sample resolve against one
    /// camera and a camera move cannot mix two projections into one
    /// displacement.
    private func affordanceMeasure() throws -> ViewportNativeAffordanceMeasure {
        ViewportNativeAffordanceMeasure(
            planCache: presentationPlanCache,
            identity: try presentationQueryIdentity(),
            revision: activeControlSession.revision
        )
    }

    /// How a drag update answers a native query it could not resolve.
    ///
    /// A frame that has not judged this identity yet is the transient case the
    /// next pointer move can ask again about, so the last answered ghost edit
    /// stays, nothing is reported, and nothing is authorized. Every other code
    /// is an answer: the pending interaction is cleared, because a drag that
    /// cannot measure must not leave a handle following the pointer against a
    /// baseline nothing answered.
    private func refuseAffordanceDragUpdate(_ error: any Error) {
        guard ViewportNativeQueryFailure.isTransient(error) == false else {
            return
        }
        reportNativeGestureFailure(error)
        clearPendingCanvasInteractionTargets()
    }

    /// How a commit answers a native query it could not resolve.
    ///
    /// A drag that has ended has no later frame to ask, so a frame that never
    /// judged it is an answer too and every failure clears the interaction.
    private func refuseAffordanceDragCommit(_ error: any Error) {
        reportNativeGestureFailure(error)
        clearPendingCanvasInteractionTargets()
    }

    private func updateEdgeTreatmentDragPreview(
        target: ViewportAffordanceTarget,
        dragState: ViewportAffordanceDragState,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> Bool {
        switch target.action {
        case .profileEdgeChamfer(let selectionTarget, let edge):
            guard let baseEdit = dragState.baseEdits[target.featureID],
                  let distance = try baseEdit.profileEdgeChamferDistance(
                      edge,
                      start: dragState.startPoint,
                      current: current,
                      measure: measure
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
                  let radius = try baseEdit.profileEdgeFilletRadius(
                      edge,
                      start: dragState.startPoint,
                      current: current,
                      measure: measure
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
        current: CGPoint
    ) {
        let dragState: ViewportAffordanceDragState
        if let activeAffordanceDrag,
           activeAffordanceDrag.target == target {
            dragState = activeAffordanceDrag
        } else if let claim = pendingNativeAffordance, claim.target == target {
            // The native frame claimed this handle, so the record decides which
            // bodies move, where each one starts, and whether they move as a
            // group. Nothing here is re-derived from the current scene or
            // selection: the drawn handle and the drag share one baseline.
            let baseEdits = bodyEditStates(for: claim.members)
            guard baseEdits.isEmpty == false else { return }
            dragState = ViewportAffordanceDragState(
                target: target,
                startPoint: start,
                baseEdits: baseEdits,
                baseGroupEdit: claim.groupEdit
            )
            activeAffordanceDrag = dragState
        } else {
            // Every affordance handle is a prepared record, so a drag with no
            // claim and no drag in flight has no baseline to measure from.
            // Refusing here keeps the bodies where the last committed edit
            // left them instead of moving them from a guessed start.
            reportNativeGestureFailure(MeshSourcePresentationRenderError(
                code: .failed,
                message: "An affordance drag arrived without a native claim or an active drag."
            ))
            clearPendingCanvasInteractionTargets()
            return
        }

        do {
            let measure = try affordanceMeasure()
            if try updateEdgeTreatmentDragPreview(
                target: target,
                dragState: dragState,
                current: current,
                measure: measure
            ) {
                return
            }

            if let baseGroupEdit = dragState.baseGroupEdit {
                guard let nextGroupEdit = try baseGroupEdit.applying(
                    action: target.action,
                    start: dragState.startPoint,
                    current: current,
                    measure: measure
                ) else { return }
                for (featureID, baseEdit) in dragState.baseEdits {
                    editedBodies[featureID] = baseEdit.transformedFromGroup(
                        baseGroup: baseGroupEdit,
                        targetGroup: nextGroupEdit
                    )
                }
            } else if let baseEdit = dragState.baseEdits[target.featureID] {
                guard let next = try baseEdit.applying(
                    action: target.action,
                    start: dragState.startPoint,
                    current: current,
                    measure: measure
                ) else { return }
                editedBodies[target.featureID] = next
            }
        } catch {
            refuseAffordanceDragUpdate(error)
        }
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

    private func pick(
        at point: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if nativeInputGesture != nil {
            // Output mode owns no drag state, so its release resolves here.
            if case .pattern(let press) = nativeInputGesture {
                finishNativePatternClick(press, at: point)
                return
            }
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
        var presentationSurface: (triangle: MeshSourcePresentationTriangle, point: Point3D)?
        var nativeCADResult = NativeCADSubshapeResult.unsupported
        if let presentationScene {
            do {
                presentationSurface = try presentationSurfaceHit(at: point)
            } catch {
                // An unavailable frame cannot authorize selection or an edit.
                return
            }
            presentationOccurrenceID = presentationSurface?.triangle.occurrenceID
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
            if usesNativeCADSubshapeHits {
                do {
                    nativeCADResult = try presentationCADSubshapeHit(
                        at: point,
                        visibleSurface: presentationSurface,
                        in: sceneContext.scene
                    )
                } catch {
                    // An unavailable frame cannot authorize selection or an edit.
                    return
                }
            }
        }
        guard let onPick else {
            return
        }
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        let hit = resolvedViewportHit(
            nativeCADResult,
            at: point,
            in: scene,
            layout: mapper.layout,
            presentationOccurrenceID: presentationOccurrenceID
        )
        let sketchPlane = constructionSketchPlane(for: hit)
        let exactWorldPoint: Point3D?
        if selectedPresentationHasExactCADContext,
           let selectedFace = selectedGeneratedTopologyFace(in: scene) {
            do {
                exactWorldPoint = try selectedCADFaceSurfaceWorldPoint(
                    presentationSurface,
                    face: selectedFace
                )
            } catch {
                // An unavailable frame cannot authorize selection or an edit.
                return
            }
        } else {
            exactWorldPoint = nil
        }
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
        case .splineControlPointSlide:
            activeSplineControlPointSlideDrag = nil
        case .polySplineSurfaceVertexSlide:
            activePolySplineSurfaceVertexSlideDrag = nil
        case .surfaceControlPointSlide:
            activeSurfaceControlPointSlideDrag = nil
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
        if nativeInputGesture != nil {
            finishNativeInputGesture(at: end)
            return
        }
        if measurementToolActive {
            activeCanvasDrag = nil
            return
        }
        if finishInteractionDragIfNeeded(end: end) {
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
        var startExactWorldPoint: Point3D?
        var endExactWorldPoint: Point3D?
        if let selectedFace = selectedGeneratedTopologyFace(in: scene) {
            do {
                startExactWorldPoint = try selectedCADFaceSurfaceWorldPoint(
                    presentationSurfaceHit(at: start),
                    face: selectedFace
                )
                endExactWorldPoint = try selectedCADFaceSurfaceWorldPoint(
                    presentationSurfaceHit(at: end),
                    face: selectedFace
                )
            } catch {
                // An unavailable frame cannot authorize selection or an edit.
                return
            }
        }
        guard let drag = canvasModelDrag(
            from: start,
            to: end,
            mapper: mapper,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startExactWorldPoint: startExactWorldPoint,
            endExactWorldPoint: endExactWorldPoint
        ) else {
            return
        }
        onCanvasDrag(drag)
    }

    private func finishInteractionDragIfNeeded(end: CGPoint) -> Bool {
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
        case .finish(let finishKind):
            finishInteractionDrag(finishKind, end: end)
            return true
        }
    }

    private func finishInteractionDrag(
        _ finishKind: ViewportActiveInteractionDragKind,
        end: CGPoint
    ) {
        switch finishKind {
        case .splineControlPointSlide:
            finishSplineControlPointSlideDrag()
        case .polySplineSurfaceVertexSlide:
            finishPolySplineSurfaceVertexSlideDrag()
        case .surfaceControlPointSlide:
            finishSurfaceControlPointSlideDrag()
        case .surfaceFrame:
            finishSurfaceFrameDrag()
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
        case .sketchVertexOffset:
            finishSketchVertexOffsetDrag()
        case .regionOffset:
            finishRegionOffsetDrag()
        case .affordance:
            finishAffordanceInteractionDrag(end: end)
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

    private func finishPolySplineSurfaceVertexSlideDrag() {
        let target = committedPolySplineSurfaceVertexSlideDragTarget()
        activePolySplineSurfaceVertexSlideDrag = nil
        activeCanvasDrag = nil
        if let target {
            onPolySplineSurfaceVertexSlideDrag?(target)
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

    private func finishAffordanceInteractionDrag(end: CGPoint) {
        let ghostFeatureIDs = activeAffordanceDrag.map { Array($0.baseEdits.keys) } ?? []
        let bodyMoveDragTarget = committedBodyMoveDragTarget()
        let vertexDragTarget: (featureID: FeatureID, target: ViewportVertexDragTarget)?
        let faceDragTarget: (featureID: FeatureID, target: ViewportFaceDragTarget)?
        let edgeChamferDragTarget: (featureID: FeatureID, target: ViewportEdgeChamferDragTarget)?
        let edgeFilletDragTarget: (featureID: FeatureID, target: ViewportEdgeFilletDragTarget)?
        do {
            // Each route asks the frame only after its own action guard passes,
            // so a translate commit, which measures nothing, never requires one.
            vertexDragTarget = try committedVertexDragTarget(to: end)
            faceDragTarget = try committedFaceDragTarget(to: end)
            edgeChamferDragTarget = try committedEdgeChamferDragTarget(to: end)
            edgeFilletDragTarget = try committedEdgeFilletDragTarget(to: end)
        } catch {
            activeCanvasDrag = nil
            refuseAffordanceDragCommit(error)
            return
        }
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
        to end: CGPoint
    ) throws -> (featureID: FeatureID, target: ViewportVertexDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileCornerMove(let target, let vertex) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let measure = try affordanceMeasure()
        let delta = try baseEdit.profileCornerDragDelta(
            vertex,
            start: activeAffordanceDrag.startPoint,
            current: end,
            measure: measure
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
        to end: CGPoint
    ) throws -> (featureID: FeatureID, target: ViewportFaceDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileFaceMove(let target, let face) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let measure = try affordanceMeasure()
        guard let distance = try baseEdit.profileFaceDragDistance(
            face,
            start: activeAffordanceDrag.startPoint,
            current: end,
            measure: measure
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
        to end: CGPoint
    ) throws -> (featureID: FeatureID, target: ViewportEdgeChamferDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileEdgeChamfer(let target, let edge) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let measure = try affordanceMeasure()
        guard let distance = try baseEdit.profileEdgeChamferDistance(
            edge,
            start: activeAffordanceDrag.startPoint,
            current: end,
            measure: measure
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
        to end: CGPoint
    ) throws -> (featureID: FeatureID, target: ViewportEdgeFilletDragTarget)? {
        guard let activeAffordanceDrag,
              case .profileEdgeFillet(let target, let edge) = activeAffordanceDrag.target.action,
              let baseEdit = activeAffordanceDrag.baseEdits[activeAffordanceDrag.target.featureID] else {
            return nil
        }
        let measure = try affordanceMeasure()
        guard let radius = try baseEdit.profileEdgeFilletRadius(
            edge,
            start: activeAffordanceDrag.startPoint,
            current: end,
            measure: measure
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
        switch ViewportSelectionDragFailurePolicy.outcome(
            for: Result { try selectionDragTarget(from: start, to: end, size: size) }
        ) {
        case .publishes(var target):
            target.selectionIntent = selectionIntent
            onSelectionDrag(target)
        case .retainsPreview:
            // No frame judged this rectangle, so the selection stays as the
            // last answered frame left it. The caller's mouse-up clears the
            // preview either way.
            break
        case let .refuses(error):
            Self.selectionRectangleLogger.error(
                "The rectangle selection was refused: \(ViewportSelectionDragFailurePolicy.refusalDescription(error), privacy: .public)"
            )
        }
    }

    private func publishSelectionDragPreview(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) {
        switch ViewportSelectionDragFailurePolicy.outcome(
            for: Result { try selectionDragTarget(from: start, to: end, size: size) }
        ) {
        case let .publishes(target):
            publishSelectionDragPreview(target: target)
        case .retainsPreview:
            // A pointer move that outran preparation is not an operator error,
            // so the preview the last answered frame produced is kept.
            break
        case let .refuses(error):
            Self.selectionRectangleLogger.error(
                "The rectangle selection preview was refused: \(ViewportSelectionDragFailurePolicy.refusalDescription(error), privacy: .public)"
            )
            publishSelectionDragPreview(hits: [])
        }
    }

    private func publishSelectionDragPreview(target: ViewportSelectionDragTarget) {
        onSelectionDragPreview?(target)
    }

    private func publishSelectionDragPreview(hits: [ViewportHit]) {
        publishSelectionDragPreview(
            target: ViewportSelectionDragTarget(hits: hits)
        )
    }

    /// The rectangle selection the viewport publishes.
    ///
    /// For a CAD sub-shape scope over a mounted presentation the native frame
    /// answers from prepared topology, and the legacy resolver runs only for
    /// the geometry that has no prepared identity — stripped of every hit the
    /// native query owns, so one sub-shape is never judged twice by two
    /// different projections. Every other scope keeps the whole legacy path.
    ///
    /// A native query that cannot be answered is a failure, not an empty
    /// selection: both publishers report nothing rather than replacing the
    /// selection with a rectangle the frame never judged.
    private func selectionDragTarget(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize
    ) throws -> ViewportSelectionDragTarget {
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
        let layout = sceneContext.mapper.layout
        var nativeResult = NativeCADSubshapeRectangleResult.unsupported
        if usesNativeCADSubshapeRectangle {
            nativeResult = try presentationCADSubshapeRectangleHits(in: rect, in: scene)
        }
        let requiresLegacy: Bool
        switch nativeResult {
        case .resolved(_, let requiresLegacyResidual):
            requiresLegacy = requiresLegacyResidual
        case .unsupported:
            requiresLegacy = true
        }
        // The occurrence rectangle is one query over the mounted frame, so both
        // consumers below read the same answer: the legacy filter needs it to
        // know which bodies the presentation still shows, and an object-scope
        // drag reports it as the selection. A rectangle the native query
        // resolves on its own asks the frame nothing.
        let visibleOccurrenceIDs: [SceneOccurrenceID]
        if requiresLegacy || selectionHitPolicy.allowsObjectHits {
            // The answer is the frame's own drawing decision at every device
            // pixel of the rectangle, so an occurrence absent from it is one
            // the frame drew nowhere inside the rectangle. There is no third
            // outcome either consumer has to interpret.
            visibleOccurrenceIDs = try presentationOccurrenceIDs(intersecting: rect)
        } else {
            visibleOccurrenceIDs = []
        }
        let hits: [ViewportHit]
        switch nativeResult {
        case .resolved(let nativeHits, let requiresLegacyResidual):
            if requiresLegacyResidual {
                let residual = legacySelectionRectangleHits(
                    in: rect,
                    scene: scene,
                    layout: layout,
                    visiblePresentationOccurrenceIDs: visibleOccurrenceIDs
                )
                hits = nativeHits + residual.filter { nativeRectangleOwnsLegacyHit($0) == false }
            } else {
                hits = nativeHits
            }
        case .unsupported:
            hits = legacySelectionRectangleHits(
                in: rect,
                scene: scene,
                layout: layout,
                visiblePresentationOccurrenceIDs: visibleOccurrenceIDs
            )
        }
        return ViewportSelectionDragTarget(
            hits: hits,
            presentationOccurrenceIDs: selectionHitPolicy.allowsObjectHits ? visibleOccurrenceIDs : []
        )
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This is the interim bridge to the
    // pre-RealityKit identity-buffer resolver for rectangle selection. It
    // projects, occludes and clips with the GPU identity rule instead of the
    // mounted native frame, so a second selection judgement stays live for the
    // geometry it still answers.
    //
    // Production path: `selectionDragTarget(from:to:size:)` calls this for
    // every scope outside `usesNativeCADSubshapeRectangle`, and for the CAD
    // sub-shape scopes when the scene still holds a body the native query
    // cannot name — one without prepared topology targets, or, for `.vertex`,
    // one carrying surface knot, span or trim handles.
    //
    // Which occurrences the presentation shows inside the rectangle is no
    // longer decided here: the caller answers that from the mounted native
    // frame and passes the result in, so only the hits themselves still come
    // from the legacy projection.
    //
    // Do not treat rectangle selection as migrated while this is reachable:
    // those bodies need a prepared native identity first, after which this
    // method is deleted with the resolver rather than reimplemented.
    private func legacySelectionRectangleHits(
        in rect: CGRect,
        scene: ViewportScene,
        layout: ViewportLayout,
        visiblePresentationOccurrenceIDs: [SceneOccurrenceID]
    ) -> [ViewportHit] {
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedTargetFeatureIDs()
        )
        let rawHits = identityHitResolver.selectionHits(
            in: rect,
            scene: hitScene,
            layout: layout,
            sketchControlPointHitPolicy: sketchControlPointHitPolicy(for: hitScene),
            selectionHitPolicy: selectionHitPolicy
        )
        guard presentationScene != nil else {
            return rawHits
        }
        return MeshSourcePresentationLegacyHitFilter().selectionHits(
            rawHits,
            visiblePresentationOccurrenceIDs: visiblePresentationOccurrenceIDs,
            navigation: presentationSceneNodeIDByOccurrenceID,
            exactCADSceneNodeIDs: presentationCADInteractionSceneNodeIDs,
            selectionHitPolicy: selectionHitPolicy
        )
    }

    private func hover(at point: CGPoint, size: CGSize) {
        if measurementToolActive {
            handleMeasurementHover(at: point)
            return
        }
        do {
            if let record = try nativeInteractionRecord(at: point) {
                if try ViewportNativeAxisInput(record: record) != nil {
                    clearCanvasHover()
                    if nativeAxisRouteEnabled(record.target) {
                        hoveredNativeHandleIdentity = record.identity
                    }
                    return
                }
                if try ViewportSketchTransformInput(record: record) != nil {
                    // `clearCanvasHover` clears the native handle too, so the
                    // claim is written after it rather than before.
                    clearCanvasHover()
                    if sketchTransformRouteEnabled {
                        hoveredNativeHandleIdentity = record.identity
                    }
                    return
                }
                if ViewportNativePatternInput.claims(record.target) {
                    clearCanvasHover()
                    if nativePatternRouteEnabled(record.target) {
                        hoveredNativeHandleIdentity = record.identity
                    }
                    return
                }
                if ViewportNativeWorldPointInput.claims(record.target) {
                    clearCanvasHover()
                    if nativeWorldPointRouteEnabled(record.target) {
                        hoveredNativeHandleIdentity = record.identity
                    }
                    return
                }
                if case .affordance(let target, _, _) = record.target {
                    hoveredNativeHandleIdentity = nil
                    setHoveredInteractionTarget(.affordance(target))
                    hoveredCanvasHit = nil
                    hoveredModelPoint = nil
                    onPresentationOccurrenceHover?(nil)
                    clearHoverCallbacks()
                    return
                }
            }
        } catch {
            clearCanvasHover()
            return
        }
        hoveredNativeHandleIdentity = nil
        let sceneContext = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        )
        let scene = sceneContext.scene
        let mapper = sceneContext.mapper
        clearHoverInteractionTargets()
        let presentationOccurrenceID: SceneOccurrenceID?
        var nativeCADResult = NativeCADSubshapeResult.unsupported
        var exactWorldPoint: Point3D?
        do {
            let presentationSurface = try presentationSurfaceHit(at: point)
            presentationOccurrenceID = presentationSurface?.triangle.occurrenceID
            if usesNativeCADSubshapeHits {
                nativeCADResult = try presentationCADSubshapeHit(
                    at: point,
                    visibleSurface: presentationSurface,
                    in: scene
                )
            }
            if selectedPresentationHasExactCADContext,
               let selectedFace = selectedGeneratedTopologyFace(in: scene) {
                exactWorldPoint = try selectedCADFaceSurfaceWorldPoint(
                    presentationSurface,
                    face: selectedFace
                )
            }
        } catch {
            clearCanvasHover()
            return
        }
        let hit = resolvedViewportHit(
            nativeCADResult,
            at: point,
            in: scene,
            layout: mapper.layout,
            presentationOccurrenceID: presentationOccurrenceID
        )
        hoveredCanvasHit = hit
        let sketchPlane = canvasDragSketchPlane(for: hit)
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
        hoveredNativeHandleIdentity = nil
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

    var hoveredSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget? {
        guard case .splineControlPointSlide(let target) = hoveredInteractionTarget else {
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

    var hoveredSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget? {
        guard case .surfaceControlPointSlide(let target) = hoveredInteractionTarget else {
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

    var pendingSplineControlPointSlideHandle: ViewportSplineControlPointSlideHandleTarget? {
        get {
            guard case .splineControlPointSlide(let target) = pendingInteractionTarget else {
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

    var pendingSurfaceControlPointSlideHandle: ViewportSurfaceControlPointSlideHandleTarget? {
        get {
            guard case .surfaceControlPointSlide(let target) = pendingInteractionTarget else {
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
           nativeInputGesture == nil,
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
        var nativeLinearAxis: ViewportPatternArrayLinearAxisDragTarget?
        var nativeIndependentExtrude: ViewportIndependentCopyExtrudeDistanceDragTarget?
        var nativeIndependentDimension: ViewportIndependentCopyBodyDimensionDragTarget?
        var nativePatternIdentities: [ViewportSpatialHandleIdentity] = []
        if case .active(let press) = nativeInputGesture, let value = press.value {
            switch try press.input.commit(value: value) {
            case .patternArrayLinearAxis(let target): nativeLinearAxis = target
            case .independentCopyExtrudeDistance(let target): nativeIndependentExtrude = target
            case .independentCopyBodyDimension(let target): nativeIndependentDimension = target
            default: break
            }
            if nativeLinearAxis != nil || nativeIndependentExtrude != nil || nativeIndependentDimension != nil {
                nativePatternIdentities.append(press.input.record.identity)
            }
        }
        var nativeRadialAngle: ViewportPatternArrayRadialAngleDragTarget?
        var nativeCopyCount: ViewportPatternArrayCopyCountDragTarget?
        var nativeCurveExtent: ViewportPatternArrayCurveExtentDragTarget?
        if case .pattern(let press) = nativeInputGesture, let value = press.value {
            switch try press.input.commit(value: value) {
            case .patternArrayRadialAngle(let target): nativeRadialAngle = target
            case .patternArrayCopyCount(let target): nativeCopyCount = target
            case .patternArrayCurveExtent(let target): nativeCurveExtent = target
            default: break
            }
            if nativeRadialAngle != nil || nativeCopyCount != nil || nativeCurveExtent != nil {
                nativePatternIdentities.append(press.input.record.identity)
            }
        }
        // Each argument is bound to an explicitly typed local: the single
        // expression exceeded the type checker's budget once the native values
        // joined the remaining legacy drag states.
        let legacyPatternIdentities: [ViewportSpatialHandleIdentity?] = [
            activePatternArrayLinearAxisDrag.map { .patternArrayLinearAxis($0.target.identity) },
            activeIndependentCopyExtrudeDistanceDrag.map { .independentCopyExtrudeDistance($0.target.identity) },
            activeIndependentCopyBodyDimensionDrag.map { .independentCopyBodyDimension($0.target.identity) },
        ]
        let patternHandleIdentities = nativePatternIdentities + legacyPatternIdentities.compactMap { $0 }
        let patternHoveredIdentities: [ViewportSpatialHandleIdentity] =
            try hoveredSpatialHandleIdentity.map { [$0] } ?? []
        let patternPendingIdentities: [ViewportSpatialHandleIdentity] =
            try pendingSpatialHandleIdentity.map { [$0] } ?? []
        let activeLinearAxis: ViewportPatternArrayLinearAxisDragTarget? =
            nativeLinearAxis ?? activePatternArrayLinearAxisDrag.map {
                .init(sourceID: $0.target.sourceID, axisSlot: $0.target.axisSlot, distance: $0.distanceMeters)
            }
        let activeRadialAngle: ViewportPatternArrayRadialAngleDragTarget? = nativeRadialAngle
        let activeCopyCount: ViewportPatternArrayCopyCountDragTarget? = nativeCopyCount
        let activeCurveExtent: ViewportPatternArrayCurveExtentDragTarget? = nativeCurveExtent
        let activeCurvePathPoint: ViewportPatternArrayCurvePathPointDragTarget? =
            nativeCurvePathPointPreview
        let activeIndependentCopyExtrude: ViewportIndependentCopyExtrudeDistanceDragTarget? =
            nativeIndependentExtrude ?? activeIndependentCopyExtrudeDistanceDrag.map {
                .init(sourceID: $0.target.sourceID, outputIndex: $0.target.outputIndex,
                      outputSceneNodeID: $0.target.outputSceneNodeID, featureID: $0.target.featureID,
                      distance: $0.distanceMeters / $0.target.valueScale)
            }
        let activeIndependentCopyDimension: ViewportIndependentCopyBodyDimensionDragTarget? =
            nativeIndependentDimension ?? activeIndependentCopyBodyDimensionDrag.map {
                .init(sourceID: $0.target.sourceID, outputIndex: $0.target.outputIndex,
                      outputSceneNodeID: $0.target.outputSceneNodeID, featureID: $0.target.featureID,
                      kind: $0.target.kind, value: $0.valueMeters / $0.target.valueScale)
            }
        let patternSource: ViewportSpatialOverlaySemanticSnapshot.PatternSource? =
            patternRoute || !document.productMetadata.patternArrays.isEmpty
                ? .init(
                    document: document,
                    scene: scene,
                    selection: selection,
                    ruler: workspaceRuler,
                    hasRoute: patternRoute,
                    replacementRequest: patternArrayCurvePathReplacementPreviewRequest,
                    activeHandleIdentities: patternHandleIdentities,
                    hoveredHandleIdentities: patternHoveredIdentities,
                    pendingHandleIdentities: patternPendingIdentities,
                    activeLinearAxis: activeLinearAxis,
                    activeRadialAngle: activeRadialAngle,
                    activeCopyCount: activeCopyCount,
                    activeCurveExtent: activeCurveExtent,
                    activeCurvePathPoint: activeCurvePathPoint,
                    activeIndependentCopyExtrude: activeIndependentCopyExtrude,
                    activeIndependentCopyDimension: activeIndependentCopyDimension,
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
        if case .active(let press) = nativeInputGesture, let value = press.value {
            switch press.input.record.target {
            case .regionOffset, .edgeOffset, .sketchVertexOffset, .splineControlPointSlide:
                overrides.append(.init(identity: press.input.record.identity, distanceMeters: value))
            case .slotWidth:
                overrides.append(.init(identity: press.input.record.identity, widthMeters: value))
            default: break
            }
        }
        if let preview = nativeWorldPointPreview {
            switch preview.value {
            case .sketchCurveHandle(let radiusMeters, let startAngle, let endAngle):
                overrides.append(.init(identity: preview.identity,
                                       radiusMeters: radiusMeters,
                                       startAngleRadians: startAngle,
                                       endAngleRadians: endAngle))
            case .sketchDimension(let value):
                overrides.append(.init(identity: preview.identity, value: value))
            case .sketchDisplayDelta(let displayDelta):
                overrides.append(.init(identity: preview.identity,
                                       deltaX: displayDelta.x, deltaY: displayDelta.y))
            default:
                break
            }
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
        if let preview = nativeBridgeCurveEndpointPreview {
            overrides.append(.init(identity: preview.identity,
                                   bridgeEndpoint: preview.endpoint,
                                   bridgeParameter: preview.parameter))
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
        if allowsObjectAffordances { interactive.insert(.bodyTransform) }
        // The sketch route commits a scene-node frame and needs no exact CAD
        // topology, so it is gated by its own commit callback rather than by
        // the object-affordance permission, which is resolved from mesh
        // presentations and therefore no sketch selection can meet.
        if onSketchTransformCommit != nil { interactive.insert(.sketchTransform) }
        if onEdgeFilletDrag != nil { interactive.insert(.edgeFillet) }
        if onVertexDrag != nil { interactive.insert(.profileCorner) }
        if onFaceDrag != nil { interactive.insert(.profileFace) }
        if onEdgeChamferDrag != nil { interactive.insert(.profileEdgeChamfer) }
        routes.formUnion(interactive)
        var active: [Active] = []
        let comparison = modifierFlags.containsControl
        if case .active(let press) = nativeInputGesture, let value = press.value {
            switch press.input.record.target {
            case .polySplineSurfaceVertexSlide, .surfaceControlPointSlide, .surfaceFrame:
                active.append(.init(identity: press.input.record.identity, distance: value,
                                    showsOriginalComparison: comparison))
            case .polySplineSurfaceVertex, .surfaceControlPoint:
                // These two draw a moved handle rather than a signed distance,
                // so the axis value is turned back into the model-space
                // displacement the overlay redraws from.
                guard let delta = press.input.localDelta(for: value) else {
                    throw RealityViewportSpatialBatch.invalid(
                        "An axis-mode surface handle has no local drag direction."
                    )
                }
                active.append(.init(identity: press.input.record.identity, delta: delta,
                                    showsOriginalComparison: comparison))
            default: break
            }
        }
        if case .sketchTransform(let press) = nativeInputGesture, let mutation = press.mutation {
            active.append(.init(identity: press.identity, transform: mutation,
                                showsOriginalComparison: comparison))
        }
        if let drag = activeAffordanceDrag {
            active.append(.init(identity: .affordance(drag.target)))
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
        if let preview = nativeSurfaceHandlePreview {
            switch preview.target {
            case .polySplineSurfaceVertex, .surfaceControlPoint:
                active.append(.init(identity: preview.identity, delta: preview.delta,
                                    showsOriginalComparison: comparison))
            default:
                // The two trim routes draw no original-placement comparison,
                // because their handles are redrawn at solved parameters
                // rather than at an offset copy of the original point.
                active.append(.init(identity: preview.identity, delta: preview.delta))
            }
        }
        if let preview = nativeConstructionPlanePreview {
            active.append(.init(identity: preview.identity,
                                origin: preview.origin, normal: preview.normal))
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
