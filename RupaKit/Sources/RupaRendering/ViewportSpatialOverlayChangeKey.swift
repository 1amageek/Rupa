import RupaCore
import RupaViewportScene

/// Exact, camera-independent values already owned by the viewport.
/// Capturing this key never evaluates geometry or retains callback closures.
struct ViewportSpatialOverlayChangeKey: Equatable {
    struct Creation: Equatable {
        let kind: ViewportCanvasDragPreviewKind
        let drag: ViewportModelDrag?
        let plane: SketchPlane?
    }

    var selection = SelectionModel()
    var selectionPreview: [SelectionTarget] = []
    var meshSelection: ViewportMeshSelectionOverlay?
    var editedBodies: [FeatureID: ViewportObjectEditState] = [:]
    var activeDrags = ViewportActiveInteractionDrags()
    var hoveredHandle: ViewportSpatialHandleIdentity?
    var pendingHandle: ViewportSpatialHandleIdentity?
    var nativeAxisValue: Double?
    var sketchTransformMutation: Transform3D?
    var hoveredHit: ViewportHit?
    var creation: Creation?
    var hasCanvasDrag = false
    var modifierControl = false
    var patternReplacement: ViewportPatternArrayCurvePathReplacementPreviewRequest?
    var surfaceAnalysis: SurfaceAnalysisResult?
    var surfaceAnalysisOptions = ViewportSurfaceAnalysisOptions()
    var surfaceContinuity: SurfaceContinuityResult?
    var sectionAnalysis: SectionAnalysisResult?
    var snap: SnapResolutionResult?
    var snapOptions: SnapResolutionOptions?
    var placement: ViewportPlacementHighlight?
    var measurement = ViewportMeasurementState()
    var measurementToolActive = false
    var showsAutomaticMeasurement = false
    var measurementPlane: SketchPlane?
    var displayUnit: LengthDisplayUnit = .millimeter
    var axisConstraint: SketchAxisConstraint?
    var allowsObjectAffordances = false
    var showsConstructionPlaneHover = false
    var slotWidthMeters: Double = 0
    var sketchVertexOffsetDistanceMeters: Double = 0
    var edgeOffsetDistanceMeters: Double = 0
    // The producer has a fixed set of callback routes; only availability matters.
    var availableRoutes: UInt32 = 0
}
