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
    @State private var constructionPlaneHandleMarkers: [ViewportConstructionPlaneHandleMarker] = []
    @State private var nativeInputGesture: NativeInputGesture?
    @State private var bodyCommitHandoff = ViewportBodyCommitHandoff()

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
    /// The release waits for a mounted frame the same way the body transform
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
        case bodyTransform(BodyTransformPress)
        case active(NativeAxisPress)
        case pattern(NativePatternPress)
        case worldPoint(NativeWorldPointPress)
        // Consume the rest of a refused gesture, including its mouse-up.
        case cancelled
    }

    private struct BodyTransformPress {
        let input: ViewportBodyTransformInput
        let source: ViewportSourceIdentity
        let snapshotID: EvaluationSnapshotID?
        let selectedTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let start: CGPoint
        var mutation: Transform3D?
        var finish: (point: CGPoint, revision: UInt64)?
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
    @State private var previewEvaluationCache = ViewportPreviewEvaluationCache()
    @State private var presentationPlanCache = MeshSourcePresentationPlanCache()
    @State private var overlayRevision = ViewportSpatialOverlayRevision()
    @State private var gridFailure: (rendererID: ObjectIdentifier, error: MeshSourcePresentationRenderError)?
    @State private var nativeGridReadout: (rendererID: ObjectIdentifier, value: ViewportProjectedGrid.ScaleReadout)?
    @State private var nativeBoundsRulerAxes: (rendererID: ObjectIdentifier, disabled: Set<ViewportMeasurementRulerAxis>)?
    @State private var baseSceneSnapshotCache = ViewportSceneSnapshotCache()
    @State private var sceneSnapshotCache = ViewportSceneSnapshotCache()

    private let controlSession: ViewportControlSession?
    private let document: DesignDocument
    private let sourceIdentity: ViewportSourceIdentity
    private let presentationScene: UniversalViewportScene?
    private let presentationSceneNodeIDByOccurrenceID: [SceneOccurrenceID: SceneNodeID]
    private let occurrenceMaterials: [SceneOccurrenceID: SwiftCAD.Material]
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
    private let cameraResetSignal: Int
    private let hoverClearSignal: Int
    private let showsConstructionPlaneHover: Bool
    private let measurementToolActive: Bool
    private let showsAutomaticMeasurement: Bool
    private let showsBoundsReadout: Bool
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
    private let onBodyPlacementCommit: (([ViewportBodyPlacementDragTarget]) async throws -> ViewportSourceIdentity)?
    private let onBodyResizeCommit: ((ViewportBodyResizeDragTarget) async throws -> ViewportSourceIdentity)?
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
    private let onHover: ((ViewportHit?) -> Void)?
    private let onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)?
    private let onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)?
    private let onCameraFrameChange: ((ViewportCameraFrame?) -> Void)?
    private let onCameraFrameRequestResult: ((UUID, Result<Void, Error>) -> Void)?
    private let onProjectedGridStepChange: ((ViewportProjectedGrid.ScaleReadout.Length) -> Void)?
    private let onMeasurementStateChange: ((ViewportMeasurementState) -> Void)?
    private let onNativeGestureRefusal: ((any Error) -> Void)?
    private let onPresentationFailure: ((any Error) -> Void)?
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

    /// Supplies the frame owner at composition time; the mounted view retains
    /// its normal State lifetime and teardown contract.
    init(_ viewport: Self, presentationPlanCache: MeshSourcePresentationPlanCache) {
        self = viewport
        _presentationPlanCache = State(initialValue: presentationPlanCache)
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
        cameraResetSignal: Int = 0,
        hoverClearSignal: Int = 0,
        showsConstructionPlaneHover: Bool = false,
        measurementToolActive: Bool = false,
        showsAutomaticMeasurement: Bool = false,
        showsBoundsReadout: Bool = false,
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
        onBodyPlacementCommit: (([ViewportBodyPlacementDragTarget]) async throws -> ViewportSourceIdentity)? = nil,
        onBodyResizeCommit: ((ViewportBodyResizeDragTarget) async throws -> ViewportSourceIdentity)? = nil,
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
        onHover: ((ViewportHit?) -> Void)? = nil,
        onSnapCandidateKindChange: ((RupaCore.SnapCandidateKind?) -> Void)? = nil,
        onProjectionBasisChange: ((ViewportProjectionBasis) -> Void)? = nil,
        onCameraFrameChange: ((ViewportCameraFrame?) -> Void)? = nil,
        onCameraFrameRequestResult: ((UUID, Result<Void, Error>) -> Void)? = nil,
        onProjectedGridStepChange: ((ViewportProjectedGrid.ScaleReadout.Length) -> Void)? = nil,
        onMeasurementStateChange: ((ViewportMeasurementState) -> Void)? = nil,
        onNativeGestureRefusal: ((any Error) -> Void)? = nil,
        onPresentationFailure: ((any Error) -> Void)? = nil
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
        // Resolve the document-owned appearance once per supplied View value,
        // not from the camera-driven body or the native scene's update callback.
        var occurrenceMaterials: [SceneOccurrenceID: SwiftCAD.Material] = [:]
        if let presentationScene {
            for item in presentationScene.items {
                guard let nodeID = presentationSceneNodeIDByOccurrenceID[item.id],
                      let material = document.sceneNodeAppearance(id: nodeID) else { continue }
                occurrenceMaterials[item.id] = material
            }
        }
        self.occurrenceMaterials = occurrenceMaterials
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
        self.cameraResetSignal = cameraResetSignal
        self.hoverClearSignal = hoverClearSignal
        self.showsConstructionPlaneHover = showsConstructionPlaneHover
        self.measurementToolActive = measurementToolActive
        self.showsAutomaticMeasurement = showsAutomaticMeasurement
        self.showsBoundsReadout = showsBoundsReadout
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
        self.onBodyPlacementCommit = onBodyPlacementCommit
        self.onBodyResizeCommit = onBodyResizeCommit
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
        self.onHover = onHover
        self.onSnapCandidateKindChange = onSnapCandidateKindChange
        self.onProjectionBasisChange = onProjectionBasisChange
        self.onCameraFrameChange = onCameraFrameChange
        self.onCameraFrameRequestResult = onCameraFrameRequestResult
        self.onProjectedGridStepChange = onProjectedGridStepChange
        self.onMeasurementStateChange = onMeasurementStateChange
        self.onNativeGestureRefusal = onNativeGestureRefusal
        self.onPresentationFailure = onPresentationFailure
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
            presentationFailureReporter(error: failure, previewFailureMessage: nil)
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
                    additionalExclusions: canvasOverlayExclusions
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
                    // The host stays mounted while no frame is current, so one
                    // canvas keeps one native scene across every rebuild.
                    RealityViewportView(
                        viewport: presentationSurface ?? preparationIdentity.flatMap {
                            presentationPlanCache.displayCandidate(for: $0)
                        },
                        viewportRevision: activeControlSession.revision,
                        displayMode: displayMode,
                        shading: shading,
                        occurrenceMaterials: occurrenceMaterials,
                        layout: sceneContext.layout,
                        interaction: presentationInteractionStateResolver,
                        sectionPlane: sectionClippingPlan == nil ? nil : sectionAnalysis?.plane,
                        retainedSide: sectionClippingPlan?.retainedSide ?? .front,
                        sectionTolerance: sectionAnalysis?.toleranceMeters ?? 0,
                        excludedRects: chromeLayout.inputExclusionRects,
                        objectPreviewTransforms: bodyPreviewTransforms,
                        objectPreviewSnapshotID: presentationScene?.snapshotID,
                        gridRuler: workspaceRuler,
                        gridSpacing: gridVisualSpacingMode,
                        onGridUpdateResult: { error, readout in
                            guard let preparationIdentity, let presentationSurface,
                                  presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                            gridFailure = error.map { (ObjectIdentifier(presentationSurface), $0) }
                            nativeGridReadout = readout.map { (ObjectIdentifier(presentationSurface), $0) }
                        },
                        onBoundsRulerUpdateResult: { axes in
                            guard let preparationIdentity, let presentationSurface,
                                  presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                            nativeBoundsRulerAxes = axes.map { (ObjectIdentifier(presentationSurface), $0) }
                        },
                        onAppliedFrameRevision: { revision in
                            guard let preparationIdentity, let presentationSurface,
                                  presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                            guard let revision else {
                                constructionPlaneHandleMarkers = []
                                return
                            }
                            do {
                                let markers = try ViewportConstructionPlaneHandleMarkerResolver.resolve(
                                    planCache: presentationPlanCache,
                                    identity: preparationIdentity,
                                    revision: revision
                                )
                                if constructionPlaneHandleMarkers != markers {
                                    constructionPlaneHandleMarkers = markers
                                }
                            } catch {
                                constructionPlaneHandleMarkers = []
                                let failure = (error as? MeshSourcePresentationRenderError)
                                    ?? MeshSourcePresentationRenderError(
                                        code: .failed, message: error.localizedDescription
                                    )
                                surfaceFailure = (ObjectIdentifier(presentationSurface), failure)
                            }
                        },
                        onUpdateResult: { error in
                            guard let preparationIdentity, let presentationSurface,
                                  presentationPlanCache.displaySurface(for: preparationIdentity) === presentationSurface else { return }
                            surfaceFailure = error.map { (ObjectIdentifier(presentationSurface), $0) }
                            if error == nil {
                                resumeNativeAxisFinish()
                                resumeBodyTransformFinish()
                                resumeNativeWorldPointFinish()
                            } else if presentationSurface.appliedViewportRevision == nil {
                                cancelNativeInputGesture()
                            }
                        }
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(viewportBackground)
                .contentShape(Rectangle())
                .background {
                    presentationFailureReporter(
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
                    constructionPlaneHandleAccessibilityMarkers
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
                        onModifierFlagsChange: { flags, _ in
                            modifierFlags = flags
                            refreshSnapOverlayResolution()
                            refreshPlacementHighlight()
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
                            if nativeInputGesture != nil || pendingInteractionTarget != nil
                                || activeInteractionDrags.hasActiveDrag || activeCanvasDrag != nil {
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
                .onChange(of: gridReadout?.minorStep, initial: true) { _, newValue in
                    // Report the resolved visible grid cell: its metres for placement and
                    // its resolved text and unit for the header. `.onChange` fires only on
                    // an actual value change and runs after the view update, so this never
                    // mutates SwiftUI state mid-update and cannot form a feedback loop.
                    // A surface that publishes no readout while it remounts leaves the last
                    // step standing rather than withdrawing it.
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
                refreshSnapOverlayResolution()
                refreshPlacementHighlight()
            }
            .onChange(of: measurementToolActive) { _, isActive in
                cancelNativeInputGesture()
                if !isActive {
                    resetMeasurement()
                }
            }
            .onChange(of: automaticMeasurementReadout(), initial: true) { _, summary in
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
            .onChange(of: bodyTransformRouteEnabled) { _, enabled in
                if !enabled, case .bodyTransform = nativeInputGesture { cancelNativeInputGesture() }
            }
            .onChange(of: slotWidthMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: edgeOffsetDistanceMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: sketchVertexOffsetDistanceMeters) { _, _ in cancelChangedNativeAxisBaseline() }
            .onChange(of: selection.selectedSceneNodeIDs) { _, _ in
                resetMeasurement()
            }
            .onChange(of: canvasPlacementPreviewKind) { _, _ in
                refreshPlacementHighlight()
            }
            .onChange(of: cameraResetSignal) { _, _ in
                resetViewportCamera(size: proxy.size, basis: currentProjectionBasis)
            }
            .onChange(of: hoverClearSignal) { _, _ in
                clearCanvasHover()
            }
            .onChange(of: sourceIdentity) { _, _ in
                bodyCommitHandoff.observe(sourceIdentity)
                cancelNativeInputGesture()
                clearDragPreviewDocument()
                refreshSnapOverlayResolution()
                refreshPlacementHighlight()
                resetMeasurement()
            }
            .onDisappear {
                bodyCommitHandoff.reset()
                clearPendingCanvasInteractionTargets()
                previewEvaluationCache.clear()
                presentationPlanCache.teardown()
                surfaceFailure = nil
                gridFailure = nil
                nativeGridReadout = nil
                nativeBoundsRulerAxes = nil
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

    /// Marks where each editable body face projects.
    ///
    /// The markers report and do not intercept. `ViewportInputSurface` owns
    /// every press, click and drag the canvas receives, so the layer stays out
    /// of the pointer's way and a modifier-held click or a drag that starts
    /// over a face reaches the route it reaches anywhere else on the body. The
    /// button action remains the assistive-technology activation route.
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
        .allowsHitTesting(false)
    }

    /// Marks where each vertical body edge projects.
    ///
    /// The markers report and do not intercept, for the reason
    /// `faceAccessibilityMarkers` records.
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
        .allowsHitTesting(false)
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

    /// Marks the construction-plane handles the mounted frame drew.
    ///
    /// The screen points come from `constructionPlaneHandleMarkers`, which the
    /// applied-frame receiver resolves against the frame that drew the
    /// handles. The gate matches the one that registers the prepared records,
    /// so an uninteractive plane publishes neither a handle nor a marker.
    @ViewBuilder private var constructionPlaneHandleAccessibilityMarkers: some View {
        if onConstructionPlaneHandleDrag != nil {
            ForEach(constructionPlaneHandleMarkers, id: \.identity) { marker in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 24.0, height: 24.0)
                    .position(marker.point)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(
                        "CanvasConstructionPlaneHandle.\(marker.identity.handle.rawValue)"
                    )
                    .accessibilityLabel(constructionPlaneHandleAccessibilityLabel(marker))
                    .accessibilityValue(constructionPlaneHandleAccessibilityValue(marker))
                    .allowsHitTesting(false)
            }
        }
    }

    private func constructionPlaneHandleAccessibilityLabel(
        _ marker: ViewportConstructionPlaneHandleMarker
    ) -> String {
        switch marker.identity.handle {
        case .origin:
            return "Construction plane origin handle"
        case .normal:
            return "Construction plane normal handle"
        }
    }

    private func constructionPlaneHandleAccessibilityValue(
        _ marker: ViewportConstructionPlaneHandleMarker
    ) -> String {
        switch marker.identity.handle {
        case .origin:
            return [
                "x \(accessibilityNumber(marker.origin.x))",
                "y \(accessibilityNumber(marker.origin.y))",
                "z \(accessibilityNumber(marker.origin.z))",
            ].joined(separator: ", ")
        case .normal:
            return [
                "x \(accessibilityNumber(marker.normal.x))",
                "y \(accessibilityNumber(marker.normal.y))",
                "z \(accessibilityNumber(marker.normal.z))",
            ].joined(separator: ", ")
        }
    }

    private func accessibilityNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }

    private var hasSelectedAffordance: Bool {
        allowsObjectAffordances && !selectedObjectFeatureIDs().isEmpty
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
        case .bodyTransform(let press):
            if presentationScene == nil { key.bodyTransformMutation = press.mutation }
        case .active(let press): key.nativeAxisValue = press.value
        case .pattern(let press): key.nativePatternValue = press.value
        case .worldPoint(let press): key.nativeWorldPointValue = press.value
        case .cancelled, nil: break
        }
        if presentationScene == nil, bodyCommitHandoff.source == sourceIdentity {
            key.bodyTransformMutation = bodyCommitHandoff.mutation
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
        if onVertexDrag != nil { key.availableRoutes |= 1 << 23 }
        if onFaceDrag != nil { key.availableRoutes |= 1 << 24 }
        if onEdgeChamferDrag != nil { key.availableRoutes |= 1 << 25 }
        if onBodyPlacementCommit != nil { key.availableRoutes |= 1 << 26 }
        if onBodyResizeCommit != nil { key.availableRoutes |= 1 << 27 }
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

    private func makeLayout(
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis,
        usesDragPreviewDocument: Bool = true,
        fittingInsets: ViewportLayout.FittingInsets? = nil
    ) -> ViewportLayout {
        makeSceneContext(
            size: size,
            camera: camera,
            basis: basis,
            usesDragPreviewDocument: usesDragPreviewDocument,
            fittingInsets: fittingInsets ?? viewportLayoutFittingInsets(size: size)
        ).layout
    }

    private func viewportLayoutFittingInsets(size: CGSize) -> ViewportLayout.FittingInsets {
        makeFittingChromeLayout(size: size).fittingInsets
    }

    private func makeFittingChromeLayout(size: CGSize) -> ViewportCanvasChromeLayout {
        ViewportCanvasChromeLayout(
            viewportSize: size,
            bottomReservedHeight: bottomChromeReservedHeight,
            additionalExclusions: canvasOverlayExclusions
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
    /// With no presentation mounted there is no native frame to ask, and the
    /// caller has already answered the whole rectangle as empty, so the empty
    /// result here is the absence of a presentation rather than a refused
    /// query.
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

    /// Resolves a CAD face, edge or vertex from prepared B-Rep topology, or the
    /// occurrence the frame draws, using the same native ray and projection that
    /// drew the frame. A sub-shape identity is always the prepared
    /// `SelectionComponentID`, never a render-mesh element.
    ///
    /// Every CAD interaction body with prepared topology is a candidate, not
    /// only the body the pointer draws. A pixel just outside the tessellated
    /// silhouette still has outline edges and silhouette vertices within the
    /// point tolerance, so gating the whole query on a drawn surface would
    /// answer nothing for a pointer the frame drew an edge under.
    /// `visibleSurface` is the native surface hit at the pointer; its triangle
    /// provenance answers the face query for the body it belongs to and is nil
    /// over an empty pixel. Candidates from different
    /// bodies are compared through `ViewportNativeHitCandidate.precedes`, so the
    /// nearest projected sub-shape wins and equal candidates keep stable scene
    /// order.
    ///
    /// The occurrence enters that same comparison at its weakest rank, so a
    /// pointer that named a sub-shape never resolves to the occurrence carrying
    /// it. It is admitted from the drawn triangle alone and is not gated on the
    /// depth that answers the face query: a frame that drew the pointer's pixel
    /// has already answered which occurrence is there.
    ///
    /// The answer is one optional hit. Every family a scope admits is generated
    /// and ordered here, so `nil` is the mounted frame's own answer that
    /// nothing this scope admits is drawn at the pointer, and there is no
    /// second hit rule for it to mean anything else. A sketch the frame
    /// suppressed is part of that answer rather than an unclaimed family: the
    /// frame stopped drawing it, so the pointer misses it.
    private func presentationCADSubshapeHit(
        at point: CGPoint,
        visibleSurface: (triangle: MeshSourcePresentationTriangle, point: Point3D)?,
        in scene: ViewportScene
    ) throws -> ViewportHit? {
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
        // Either gate the sketch entity families use: `object` or
        // `sketchEntity` reaches an entity and `sketchEntity` alone reaches a
        // control point, so their union is the wider of the two.
        let admitsSketchFamilies = selectionHitPolicy.allowsObjectHits
            || selectionHitPolicy.allowsSketchEntityHits
        let admitsSketchRegions = selectionHitPolicy.allowsRegionHits
        let suppressedSketchFeatureIDs = admitsSketchFamilies || admitsSketchRegions
            ? frameSuppressedSketchFeatureIDs(in: scene)
            : []
        let sketchControlPoints: ViewportSketchControlPointHitPolicy = admitsSketchFamilies
            ? sketchControlPointHitPolicy(for: scene)
            : .none
        for item in scene.items {
            // A sketch item carries no scene node and no body component, so it
            // is answered before the body families rather than through them.
            if case .sketch(let primitives) = item.kind {
                let queriesEntities = admitsSketchFamilies && !primitives.isEmpty
                let queriesRegions = admitsSketchRegions
                    && !item.sketchRegions.isEmpty
                guard queriesEntities || queriesRegions else { continue }
                // A sketch the frame suppressed — because the body it feeds is
                // selected or being edited — is not drawn and is not asked
                // about, which is the producer's rule read from the same
                // selection. The frame drew nothing there, so skipping the
                // item is the answer and not a family left unclaimed for
                // something else to speak for. The resolver this replaced
                // suppressed by feature alone and answered the sketch the
                // frame had stopped drawing.
                guard !suppressedSketchFeatureIDs.contains(item.featureID) else {
                    continue
                }
                if queriesEntities,
                   let sketch = try ViewportNativeOverlayHitResolver.sketchEntity(
                       at: point,
                       item: item,
                       primitives: primitives,
                       selectionHitPolicy: selectionHitPolicy,
                       sketchControlPointHitPolicy: sketchControlPoints,
                       tolerance: ViewportNativeCADTopologyResolver.pointTolerance,
                       probe: probe
                   ), best.map({ sketch.candidate.precedes($0.candidate) }) ?? true {
                    best = sketch
                }
                // A region is the only family the frame draws for a sketch
                // that carries no primitive of its own, so it is asked
                // independently of the entity query above rather than after it.
                if queriesRegions,
                   let region = try ViewportNativeOverlayHitResolver.sketchRegion(
                       at: point,
                       item: item,
                       selectionHitPolicy: selectionHitPolicy,
                       probe: probe
                   ), best.map({ region.candidate.precedes($0.candidate) }) ?? true {
                    best = region
                }
                continue
            }
            // A curve item carries no body component either, and its polylines
            // are the only family it draws.
            if case .curve(let component) = item.kind {
                if let curve = try ViewportNativeOverlayHitResolver.curveSegment(
                    at: point,
                    item: item,
                    component: component,
                    selectionHitPolicy: selectionHitPolicy,
                    tolerance: ViewportNativeCADTopologyResolver.pointTolerance,
                    probe: probe
                ), best.map({ curve.candidate.precedes($0.candidate) }) ?? true {
                    best = curve
                }
                continue
            }
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
                    selectionComponent: resolved.component
                ),
                resolved.candidate
            )
        }
        return best?.hit
    }

    /// Every family the rectangle admits, answered by the mounted native frame
    /// this viewport draws, through the same identity, camera revision and
    /// projection the point path reads.
    ///
    /// This is a set query with no rank: a rectangle asks which drawn things
    /// the operator enclosed, so each admitted identity is reported once and
    /// nothing here compares two of them. The families, their inputs, their
    /// scope gates and the order the scene is walked in are the point path's,
    /// so the two gestures cannot name different families for one item. Only
    /// the admission rule differs: a rectangle asks whether the frame draws a
    /// candidate inside it, where a pointer asks how near the frame draws it.
    ///
    /// A CAD sub-shape is keyed by `SelectionTarget`, the identity a selection
    /// already names an editable sub-shape by, so one shared feature placed by
    /// several scene nodes reports each placement once. A `SubshapeID` names
    /// the feature it belongs to, so de-duplicating by `SelectionComponentID`
    /// alone would drop every placement after the first. The overlay families
    /// carry no such sharing and each reports one hit per identity per item.
    ///
    /// Vertices and edges are resolved per body, because each is a candidate
    /// the prepared topology names and the frame is asked about at that
    /// candidate's own pixels. Faces are resolved the other way round, from the
    /// triangles the frame draws inside the rectangle: the region raster
    /// reports those for the whole scene in one pass, and each `.cad` triangle
    /// names the body that emitted it and the emission index its recorded runs
    /// resolve. Harvesting once for the scene is why a face the frame draws in
    /// a window narrower than any candidate test could sample is still
    /// selected.
    ///
    /// A scope that admits object hits reports no body-derived family at all.
    /// Such a rectangle selects whole occurrences, which the occurrence query
    /// answers and the consumer keys by scene node alone, so a body's faces,
    /// edges, vertices and surface handles would name sub-shapes that scope
    /// cannot select. The rule is stated once here instead of being repeated
    /// in each family's own entry point.
    ///
    /// A CAD interaction body without prepared topology contributes nothing.
    /// Its sub-objects carry no stable CAD identity, and projecting a bounding
    /// box to invent one would put a render-derived name where a prepared one
    /// belongs.
    private func presentationRectangleHits(
        in rect: CGRect,
        in scene: ViewportScene
    ) throws -> [ViewportHit] {
        let identity = try presentationQueryIdentity()
        let revision = activeControlSession.revision
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: presentationPlanCache, identity: identity, revision: revision
        )
        // The interval belongs to the same mounted camera the projections come
        // from, so an edge crossing a clip plane is walked over the part that
        // camera draws instead of being dropped whole. It is read once for the
        // rectangle rather than once per family, which is the same question the
        // frame answered before.
        let depthInterval = try probe.cameraDepthInterval()
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionTarget> = []
        let admitsBodyFamilies = selectionHitPolicy.allowsObjectHits == false
        // Either gate the sketch entity families use: `object` or
        // `sketchEntity` reaches an entity and `sketchEntity` alone reaches a
        // control point, so their union is the wider of the two.
        let admitsSketchFamilies = selectionHitPolicy.allowsObjectHits
            || selectionHitPolicy.allowsSketchEntityHits
        let admitsSketchRegions = selectionHitPolicy.allowsRegionHits
        let suppressedSketchFeatureIDs = admitsSketchFamilies || admitsSketchRegions
            ? frameSuppressedSketchFeatureIDs(in: scene)
            : []
        let sketchControlPoints: ViewportSketchControlPointHitPolicy = admitsSketchFamilies
            ? sketchControlPointHitPolicy(for: scene)
            : .none
        // The bodies the face harvest can name, keyed by the scene node a drawn
        // triangle's occurrence resolves to. A placement absent here drew no
        // prepared topology, so its triangles name no CAD face.
        var bodies: [SceneNodeID: (featureID: FeatureID, topology: ViewportBodyTopology)] = [:]
        for item in scene.items {
            // A sketch item carries no scene node and no body component, so it
            // is answered before the body families rather than through them.
            if case .sketch(let primitives) = item.kind {
                let queriesEntities = admitsSketchFamilies && !primitives.isEmpty
                let queriesRegions = admitsSketchRegions && !item.sketchRegions.isEmpty
                guard queriesEntities || queriesRegions else { continue }
                // A sketch the frame suppressed — because the body it feeds is
                // selected or being edited — is not drawn and is not asked
                // about, which is the producer's rule read from the same
                // selection. The frame drew nothing there, so skipping the item
                // is the answer and not a family left unclaimed.
                guard !suppressedSketchFeatureIDs.contains(item.featureID) else {
                    continue
                }
                if queriesEntities {
                    hits += try ViewportNativeOverlayHitResolver.sketchEntities(
                        in: rect,
                        item: item,
                        primitives: primitives,
                        selectionHitPolicy: selectionHitPolicy,
                        sketchControlPointHitPolicy: sketchControlPoints,
                        depthInterval: depthInterval,
                        probe: probe
                    )
                }
                // A region is the only family the frame draws for a sketch that
                // carries no primitive of its own, so it is asked independently
                // of the entity query above rather than after it.
                if queriesRegions {
                    hits += try ViewportNativeOverlayHitResolver.sketchRegions(
                        in: rect,
                        item: item,
                        selectionHitPolicy: selectionHitPolicy,
                        depthInterval: depthInterval,
                        probe: probe
                    )
                }
                continue
            }
            // A curve item carries no body component either, and its polylines
            // are the only family it draws.
            if case .curve(let component) = item.kind {
                hits += try ViewportNativeOverlayHitResolver.curveSegments(
                    in: rect,
                    item: item,
                    component: component,
                    selectionHitPolicy: selectionHitPolicy,
                    depthInterval: depthInterval,
                    probe: probe
                )
                continue
            }
            guard admitsBodyFamilies,
                  let sceneNodeID = item.sceneNodeID,
                  case .body(let component) = item.kind else {
                continue
            }
            // The surface handle displays are drawn for every body that carries
            // them, so they are not gated on exact CAD affordance context, which
            // is the gate the point path states for this family.
            if ViewportNativeOverlayHitResolver.carriesSurfaceHandleDisplays(component) {
                hits += try ViewportNativeOverlayHitResolver.surfaceHandles(
                    in: rect,
                    item: item,
                    component: component,
                    selectionHitPolicy: selectionHitPolicy,
                    depthInterval: depthInterval,
                    probe: probe
                )
            }
            guard presentationCADInteractionSceneNodeIDs.contains(sceneNodeID),
                  let topology = component.topology else {
                continue
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
        guard selectionHitPolicy.allowsFaceHits, bodies.isEmpty == false else {
            return hits
        }
        // A triangle carries the occurrence that drew it, and mesh face
        // identities are numbered per body, so resolving the occurrence first is
        // what keeps another body's index from naming a run of this one. An
        // authored mesh triangle names no CAD face at all.
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
        return hits
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
                selectionComponent: selectionComponent
            )
        )
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
                options: snapResolutionOptions, modifierFlags: modifierFlags,
                currentEvaluation: currentEvaluation,
                currentGeneration: sceneDocumentGeneration
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

    /// The world-bounds text the transient status carries. Its gate is a
    /// superset of the spatial ruler gate, so an axis the frame refuses to
    /// place still reports its value wherever the rulers can be drawn.
    private func automaticMeasurementReadout() -> String? {
        guard showsBoundsReadout, activeCanvasDrag == nil, pendingInteractionTarget == nil,
              nativeInputGesture == nil,
              let occurrence = selectedMeasurementOccurrence() else { return nil }
        let disabledAxes = mountedBoundsRulerDisabledAxes
        let bounds = occurrence.worldBounds
        let values: [(ViewportMeasurementRulerAxis, Double)] = [
            (.x, bounds.maximum.x - bounds.minimum.x),
            (.y, bounds.maximum.y - bounds.minimum.y),
            (.z, bounds.maximum.z - bounds.minimum.z)
        ]
        return "World bounds: " + values.map { axis, value in
            // The frame that draws the annotation decides whether an axis is
            // drawn. Before it answers, the readout states the measurement
            // without claiming anything about the annotation.
            let omitted = value > 0 && disabledAxes?.contains(axis) == true
            return "\(axis.title) \(formattedViewportLength(value))\(omitted ? " (ruler hidden)" : "")"
        }.joined(separator: " · ")
    }

    /// The bounds ruler axes refused by the frame the viewport displays now.
    /// An answer published by an earlier surface describes a frame that is no
    /// longer on screen, so it is withdrawn instead of reused.
    private var mountedBoundsRulerDisabledAxes: Set<ViewportMeasurementRulerAxis>? {
        guard case .success(let identity) = presentationPreparation,
              let surface = presentationPlanCache.displaySurface(for: identity),
              let published = nativeBoundsRulerAxes,
              published.rendererID == ObjectIdentifier(surface) else { return nil }
        return published.disabled
    }

    func presentationFailureReporter(
        error: MeshSourcePresentationRenderError?,
        previewFailureMessage: String?
    ) -> some View {
        let failure = error ?? previewFailureMessage.map {
            MeshSourcePresentationRenderError(code: .failed, message: $0)
        }
        return Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: failure, initial: true) { _, _ in
                guard let failure else { return }
                Self.nativeGestureLogger.error("Viewport presentation failed: \(failure.localizedDescription, privacy: .public)")
                onPresentationFailure?(failure)
            }
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

    /// The point the mounted frame draws at `viewportPoint` on the displayed
    /// canvas plane, which is the ray origin a canvas gesture carries when it
    /// names no exact world point.
    private func canvasViewRayAnchor(at viewportPoint: CGPoint) throws -> Point3D {
        let identity = try presentationQueryIdentity()
        return try ViewportCanvasViewRayAnchorResolver.resolve(
            at: viewportPoint,
            canvasPlane: .displayed(for: currentProjectionBasis),
            planCache: presentationPlanCache,
            identity: identity,
            revision: activeControlSession.revision
        )
    }

    private func canvasModelDrag(
        from start: CGPoint,
        to end: CGPoint,
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
        let startAnchor: Point3D
        let endAnchor: Point3D
        do {
            startAnchor = try canvasViewRayAnchor(at: start)
            endAnchor = try canvasViewRayAnchor(at: end)
        } catch {
            // A frame that cannot place the view-ray anchor cannot authorize
            // the drag: the consumer would substitute a different ray origin
            // and move the created geometry.
            return nil
        }
        return ViewportModelDrag(
            start: startInput.point,
            end: endInput.point,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startExactWorldPoint,
            endWorldPoint: endExactWorldPoint,
            startViewRayAnchorWorldPoint: startAnchor,
            endViewRayAnchorWorldPoint: endAnchor
        )
    }

    private func publishSnapCandidateKind(_ kind: RupaCore.SnapCandidateKind?) {
        guard reportedSnapCandidateKind != kind else {
            return
        }
        reportedSnapCandidateKind = kind
        onSnapCandidateKindChange?(kind)
    }

    private func refreshSnapOverlayResolution() {
        applySnapOverlayResolution(
            ViewportSnapResolutionService().resolution(
                for: snapOverlayQuery(),
                document: document,
                ruler: workspaceRuler,
                options: snapResolutionOptions,
                modifierFlags: modifierFlags,
                currentEvaluation: currentEvaluation,
                currentGeneration: sceneDocumentGeneration
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

    private func refreshPlacementHighlight() {
        guard let previewKind = canvasPlacementPreviewKind,
              let hoveredModelPoint,
              hoveredCanvasHit?.bodyFace == nil,
              hoveredCanvasHit?.bodyEdge == nil,
              Self.designatesBodySubshape(hoveredCanvasHit) == false else {
            clearPlacementHighlight()
            return
        }

        let resolution = ViewportSnapResolutionService().resolution(
            for: ViewportSnapQuery(point: hoveredModelPoint, referencePoint: nil),
            document: document,
            ruler: workspaceRuler,
            options: snapResolutionOptions,
            modifierFlags: modifierFlags,
            currentEvaluation: currentEvaluation,
            currentGeneration: sceneDocumentGeneration
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
            modifierFlags: modifierFlags,
            currentEvaluation: currentEvaluation,
            currentGeneration: sceneDocumentGeneration
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

    /// The sketch features the mounted frame stops drawing, which are exactly
    /// the ones the native query stops asking about.
    ///
    /// `ViewportSpatialOverlayProducer` suppresses a sketch once the body it
    /// feeds is selected or is being edited, because the body replaced it on
    /// screen. That rule reads the selection by scene node where an item has
    /// one and by feature otherwise, which is what `isObjectItem` states, so
    /// this reads the producer's own rule and states the suppression once for
    /// both gestures that ask about a sketch.
    private func frameSuppressedSketchFeatureIDs(in scene: ViewportScene) -> Set<FeatureID> {
        let selectedFeatureIDs = selectedTargetFeatureIDs()
        let selectedSceneNodeIDs = Set(selection.selectedSceneNodeIDs)
        return Set(
            scene.items.compactMap { item -> FeatureID? in
                guard case .body = item.kind,
                      isObjectItem(
                          item,
                          selectedByFeatureIDs: selectedFeatureIDs,
                          selectedBySceneNodeIDs: selectedSceneNodeIDs
                      ) || editedBodies[item.featureID] != nil else {
                    return nil
                }
                return item.sourceFeatureID
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

    private func formattedViewportLength(_ meters: Double) -> String {
        ViewportLengthLabelFormatter.string(
            fromMeters: meters,
            preferredUnit: workspaceRuler.displayUnit
        )
    }

    private func pointDisplay(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) -> PointDisplay? {
        sceneOverlayState.pointDisplays[
            .sketchEntity(featureID: featureID, entityID: entityID)
        ]
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

    private func selectedSketchEntityTargets() -> [ViewportSketchEntitySelectionTarget] {
        sketchEntitySelectionTargets(in: selection.selectedTargets)
    }

    private func sketchEntitySelectionTargets(in targets: [SelectionTarget]) -> [ViewportSketchEntitySelectionTarget] {
        targets.compactMap { target in
            sketchEntitySelectionTarget(for: target)
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

    private func updateCanvasDragPlaceholder(
        from start: CGPoint?,
        to current: CGPoint?,
        size: CGSize
    ) {
        defer {
            refreshSnapOverlayResolution()
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
            case .bodyTransform: updateBodyTransformGesture(current: current)
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
        activeCanvasDrag = ViewportActiveDrag(
            startLocation: start,
            currentLocation: current,
            kind: .creation(canvasDragPreviewKind),
            sketchPlane: sketchPlane,
            modelDrag: semanticCanvasModelDrag(
                from: start,
                to: current,
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
        let startAnchor: Point3D
        let endAnchor: Point3D
        do {
            startAnchor = try canvasViewRayAnchor(at: start)
            endAnchor = try canvasViewRayAnchor(at: end)
        } catch {
            // A frame that cannot place the view-ray anchor cannot authorize
            // the creation gesture.
            return nil
        }
        return ViewportModelDrag(
            start: startInput.point,
            end: endInput.point,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startInput.worldPoint,
            endWorldPoint: endInput.worldPoint,
            startViewRayAnchorWorldPoint: startAnchor,
            endViewRayAnchorWorldPoint: endAnchor
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
            case .bodyTransform(let press): return press.input.identity
            case .active(let press): return press.input.record.identity
            case .pattern(let press): return press.input.record.identity
            case .worldPoint(let press): return press.input.identity
            case .cancelled, nil: return try pendingInteractionTarget?.spatialIdentity
            }
        }
    }

    /// Reports a refused native gesture.
    ///
    /// This is the one funnel every refusal this view judges reportable leaves
    /// through, so a transient `frameNotReady` is filtered by the caller rather
    /// than here. The refusal reaches this module's log and, when the owner
    /// bound one, the owner's channel; it is never turned into a committed
    /// value. The owner receives the `Error` itself, because a rendered string
    /// drops the typed code and the concrete type a failure record keeps.
    private func reportNativeGestureFailure(_ error: Error) {
        let description = (error as? MeshSourcePresentationRenderError)?.message
            ?? error.localizedDescription
        Self.nativeGestureLogger.warning(
            "Native viewport gesture refused: \(description, privacy: .public)"
        )
        onNativeGestureRefusal?(error)
    }

    private func cancelNativeInputGesture() {
        guard nativeInputGesture != nil || pendingInteractionTarget != nil || activeInteractionDrags.hasActiveDrag else { return }
        clearAffordanceGhostEdits()
        pendingInteractionTarget = nil
        pendingNativeAffordance = nil
        nativeInputGesture = .cancelled
        hoveredNativeHandleIdentity = nil
        activeCanvasDrag = nil
        clearActiveInteractionDrags()
        clearDragPreviewDocument()
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
        case .bodyTransform(let press): press.finish?.revision
        case .active(let press): press.finish?.revision
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
        case .bodyTransform(var press):
            press.finish = (point, activeControlSession.revision)
            nativeInputGesture = .bodyTransform(press)
            resumeBodyTransformFinish()
        case .active(var press):
            press.finish = (point, activeControlSession.revision)
            nativeInputGesture = .active(press)
            resumeNativeAxisFinish()
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
            // the refusal leaves through the reporting funnel rather than being
            // dropped at mouse-up.
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

    private var bodyPreviewTransforms: [String: Transform3D] {
        guard case .bodyTransform(let press) = nativeInputGesture,
              let mutation = press.mutation else { return bodyCommitHandoff.transforms(for: sourceIdentity) }
        return Dictionary(uniqueKeysWithValues: press.input.members.map { ($0.occurrenceID, mutation) })
    }

    private var bodyTransformRouteEnabled: Bool {
        onBodyPlacementCommit != nil && (presentationScene != nil || allowsObjectAffordances
            || (!selection.selectedTargets.isEmpty && selection.selectedTargets.allSatisfy {
                $0.component == .object
                    && document.productMetadata.sceneNodes[$0.sceneNodeID]?.reference?.kind == .sketch
            }))
    }

    private func bodyTransformBaselineMatches(_ press: BodyTransformPress) -> Bool {
        press.source == sourceIdentity && press.snapshotID == presentationScene?.snapshotID
            && press.selectedTargets == selection.selectedTargets
            && press.selectedReferences == selection.selectedReferences
            && bodyTransformRouteEnabled
            && (!press.input.isResize || onBodyResizeCommit != nil)
            && (press.finish == nil || press.finish?.revision == activeControlSession.revision)
    }

    private func updateBodyTransformGesture(current: CGPoint) {
        guard case .bodyTransform(var press) = nativeInputGesture else { return }
        guard bodyTransformBaselineMatches(press) else { cancelNativeInputGesture(); return }
        do {
            press.mutation = try press.input.mutation(from: press.start, to: current, measure: affordanceMeasure())
            nativeInputGesture = .bodyTransform(press)
        } catch {
            if !ViewportNativeQueryFailure.isTransient(error) {
                reportNativeGestureFailure(error)
                cancelNativeInputGesture()
            }
        }
    }

    private func resumeBodyTransformFinish() {
        guard case .bodyTransform(let press) = nativeInputGesture, let finish = press.finish else { return }
        guard bodyTransformBaselineMatches(press) else { cancelNativeInputGesture(); return }
        let targets: [ViewportBodyPlacementDragTarget]
        let resizeTarget: ViewportBodyResizeDragTarget?
        let mutation: Transform3D
        do {
            let identity = try presentationPreparation.get()
            if let failure = presentationPlanCache.failure(for: identity) { throw failure }
            guard presentationPlanCache.hasReadyCamera(for: identity, revision: finish.revision) else { return }
            mutation = try press.input.mutation(from: press.start, to: finish.point, measure: affordanceMeasure())
            targets = try press.input.commits(mutation: mutation)
            resizeTarget = try press.input.resizeCommit(mutation: mutation)
            if let resizeTarget { try resizeTarget.validate(in: document) }
            for target in targets { try target.validate(in: document) }
        } catch {
            reportNativeGestureFailure(error)
            clearPendingCanvasInteractionTargets()
            activeCanvasDrag = nil
            return
        }
        if let resizeTarget, let onBodyResizeCommit {
            bodyCommitHandoff.begin(
                source: sourceIdentity, mutation: mutation,
                occurrenceIDs: press.input.members.map(\.occurrenceID),
                commit: { try await onBodyResizeCommit(resizeTarget) },
                onFailure: reportNativeGestureFailure
            )
        } else if !targets.isEmpty, let onBodyPlacementCommit {
            bodyCommitHandoff.begin(
                source: sourceIdentity, mutation: mutation,
                occurrenceIDs: press.input.members.map(\.occurrenceID),
                commit: { try await onBodyPlacementCommit(targets) },
                onFailure: reportNativeGestureFailure
            )
        }
        clearPendingCanvasInteractionTargets()
        activeCanvasDrag = nil
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
            snapOptions: snapResolutionOptions,
            currentEvaluation: currentEvaluation,
            currentGeneration: sceneDocumentGeneration
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
        guard !bodyCommitHandoff.isPending else {
            nativeInputGesture = .cancelled
            return
        }
        if measurementToolActive {
            clearPendingCanvasInteractionTargets()
            activeCanvasDrag = nil
            return
        }
        clearPendingCanvasInteractionTargets()
        do {
            if let record = try nativeInteractionRecord(at: point) {
                if let input = try ViewportBodyTransformInput(record: record) {
                    guard !input.isResize || onBodyResizeCommit != nil else {
                        throw RealityViewportSpatialBatch.invalid("Box resize is unavailable in this viewport.")
                    }
                    guard bodyTransformRouteEnabled else {
                        nativeInputGesture = .cancelled
                        return
                    }
                    nativeInputGesture = .bodyTransform(.init(input: input, source: sourceIdentity,
                        snapshotID: presentationScene?.snapshotID, selectedTargets: selection.selectedTargets,
                        selectedReferences: selection.selectedReferences, start: point))
                    activeCanvasDrag = nil
                    return
                }
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
                if case .affordance(let target, let members, let groupEdit, let placement) = record.target {
                    setPendingInteractionTarget(.affordance(target))
                    pendingNativeAffordance = ViewportNativeAffordanceClaim(
                        target: target, members: members, groupEdit: groupEdit, placement: placement
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
        if case .bodyTransform(let press) = nativeInputGesture, press.mutation != nil { return true }
        if case .active(let press) = nativeInputGesture, press.value != nil { return true }
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
        case .affordance(let target):
            updateAffordanceDrag(target: target, start: start, current: current)
        }
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
                baseGroupEdit: claim.groupEdit,
                placement: claim.placement
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
        var nativeCADHit: ViewportHit?
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
            do {
                nativeCADHit = try presentationCADSubshapeHit(
                    at: point,
                    visibleSurface: presentationSurface,
                    in: sceneContext.scene
                )
            } catch {
                // An unavailable frame cannot authorize selection or an edit.
                return
            }
        }
        guard let onPick else {
            return
        }
        let scene = sceneContext.scene
        let hit = nativeCADHit
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
        let viewRayAnchorWorldPoint: Point3D
        do {
            viewRayAnchorWorldPoint = try canvasViewRayAnchor(at: point)
        } catch {
            // An unavailable frame cannot authorize selection or an edit.
            return
        }
        onPick(
            ViewportCanvasTarget(
                hit: hit,
                modelPoint: input.point,
                modelWorldPoint: exactWorldPoint,
                viewRayAnchorWorldPoint: viewRayAnchorWorldPoint,
                sketchPlane: sketchPlane,
                selectionIntent: selectionIntent,
                modifierFlags: modifierFlags
            )
        )
    }

    private func finishPendingInteractionClick(_ target: ViewportInteractionTarget) {
        pendingInteractionTarget = nil
        switch target {
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
        case .affordance:
            finishAffordanceInteractionDrag(end: end)
        }
    }

    private func finishAffordanceInteractionDrag(end: CGPoint) {
        let ghostFeatureIDs = activeAffordanceDrag.map { Array($0.baseEdits.keys) } ?? []
        let vertexDragTarget: (featureID: FeatureID, target: ViewportVertexDragTarget)?
        let faceDragTarget: (featureID: FeatureID, target: ViewportFaceDragTarget)?
        let edgeChamferDragTarget: (featureID: FeatureID, target: ViewportEdgeChamferDragTarget)?
        let edgeFilletDragTarget: (featureID: FeatureID, target: ViewportEdgeFilletDragTarget)?
        do {
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
        for featureID in ghostFeatureIDs {
            editedBodies.removeValue(forKey: featureID)
        }
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
    /// The mounted frame is the query authority, so one query over it answers
    /// every family the scope admits and there is no second projection to
    /// reconcile. A viewport that mounted no presentation draws nothing and
    /// has nothing to ask, and the empty selection is that complete answer
    /// rather than a route to another rule.
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
        guard presentationScene != nil else {
            return ViewportSelectionDragTarget(hits: [])
        }
        let scene = makeSceneContext(
            size: size,
            camera: camera,
            basis: currentProjectionBasis
        ).scene
        let hits = try presentationRectangleHits(in: rect, in: scene)
        // An object scope reports whole occurrences, which the frame's own
        // drawing decision at every device pixel of the rectangle answers. An
        // occurrence absent from it is one the frame drew nowhere inside the
        // rectangle, and no other scope has a consumer for the answer.
        let occurrenceIDs: [SceneOccurrenceID]
        if selectionHitPolicy.allowsObjectHits {
            occurrenceIDs = try presentationOccurrenceIDs(intersecting: rect)
        } else {
            occurrenceIDs = []
        }
        return ViewportSelectionDragTarget(
            hits: hits,
            presentationOccurrenceIDs: occurrenceIDs
        )
    }

    private func hover(at point: CGPoint, size: CGSize) {
        if measurementToolActive {
            handleMeasurementHover(at: point)
            return
        }
        do {
            if let record = try nativeInteractionRecord(at: point) {
                if try ViewportBodyTransformInput(record: record) != nil {
                    // `clearCanvasHover` clears the native handle too, so the
                    // claim is written after it rather than before.
                    clearCanvasHover()
                    if bodyTransformRouteEnabled { hoveredNativeHandleIdentity = record.identity }
                    return
                }
                if try ViewportNativeAxisInput(record: record) != nil {
                    clearCanvasHover()
                    if nativeAxisRouteEnabled(record.target) {
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
                if case .affordance(let target, _, _, _) = record.target {
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
        clearHoverInteractionTargets()
        let presentationOccurrenceID: SceneOccurrenceID?
        var nativeCADHit: ViewportHit?
        var exactWorldPoint: Point3D?
        do {
            let presentationSurface = try presentationSurfaceHit(at: point)
            presentationOccurrenceID = presentationSurface?.triangle.occurrenceID
            // The mounted frame is the query authority. A viewport that
            // mounted none has nothing to ask, and no hit is its complete
            // answer rather than a route to a second rule.
            if presentationScene != nil {
                nativeCADHit = try presentationCADSubshapeHit(
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
        let hit = nativeCADHit
        hoveredCanvasHit = hit
        let sketchPlane = canvasDragSketchPlane(for: hit)
        hoveredModelPoint = canvasInput(
            for: point,
            exactWorldPoint: exactWorldPoint,
            sketchPlane: sketchPlane
        )?.point
        refreshSnapOverlayResolution()
        refreshPlacementHighlight()
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
        // expression exceeded the type checker's budget.
        let patternHandleIdentities = nativePatternIdentities
        let patternHoveredIdentities: [ViewportSpatialHandleIdentity] =
            try hoveredSpatialHandleIdentity.map { [$0] } ?? []
        let patternPendingIdentities: [ViewportSpatialHandleIdentity] =
            try pendingSpatialHandleIdentity.map { [$0] } ?? []
        let activeLinearAxis: ViewportPatternArrayLinearAxisDragTarget? = nativeLinearAxis
        let activeRadialAngle: ViewportPatternArrayRadialAngleDragTarget? = nativeRadialAngle
        let activeCopyCount: ViewportPatternArrayCopyCountDragTarget? = nativeCopyCount
        let activeCurveExtent: ViewportPatternArrayCurveExtentDragTarget? = nativeCurveExtent
        let activeCurvePathPoint: ViewportPatternArrayCurvePathPointDragTarget? =
            nativeCurvePathPointPreview
        let activeIndependentCopyExtrude: ViewportIndependentCopyExtrudeDistanceDragTarget? =
            nativeIndependentExtrude
        let activeIndependentCopyDimension: ViewportIndependentCopyBodyDimensionDragTarget? =
            nativeIndependentDimension
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
            bodyPreviewTransforms: presentationScene == nil ? bodyPreviewTransforms : [:],
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
        var routes: Set<Route> = [.curvatureComb]
        if onSketchDimensionDrag != nil {
            routes.formUnion([.lineDimension, .circleDimension, .arcDimension])
        }
        if onSketchPointHandleDrag != nil && onSketchCurveHandleDrag != nil {
            routes.insert(.curvePointControl)
        }
        if onSplineControlPointDrag != nil { routes.insert(.splineControl) }
        if onBridgeCurveEndpointDrag != nil { routes.insert(.bridgeCurveEndpoint) }
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
        if bodyTransformRouteEnabled { interactive.insert(.bodyTransform) }
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
        if let drag = activeAffordanceDrag {
            active.append(.init(identity: .affordance(drag.target)))
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
        var result = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
            document: document, scene: scene, selection: selection, editedBodies: editedBodies,
            ruler: workspaceRuler, enabledRoutes: routes, interactiveRoutes: interactive,
            activeValues: active,
            hoveredHandleIdentities: try hoveredSpatialHandleIdentity.map { [$0] } ?? [],
            pendingHandleIdentities: try pendingSpatialHandleIdentity.map { [$0] } ?? [],
            modifierControl: comparison, objectRegistry: objectRegistry, constructionFaceTarget: constructionFace
        )
        result.bodyPreviewTransforms = presentationScene == nil ? bodyPreviewTransforms : [:]
        result.allowsBodyResize = onBodyResizeCommit != nil
        result.presentationScene = presentationScene
        result.presentationNodeIDs = presentationSceneNodeIDByOccurrenceID
        return result
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
            axisConstraint: canvasDragAxisConstraint,
            currentEvaluation: currentEvaluation,
            currentGeneration: sceneDocumentGeneration
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
