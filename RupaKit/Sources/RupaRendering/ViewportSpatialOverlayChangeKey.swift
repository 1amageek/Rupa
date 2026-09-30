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
    var nativePatternValue: ViewportNativePatternInput.Value?
    var nativeWorldPointValue: ViewportNativeWorldPointInput.Value?
    var bodyTransformMutation: Transform3D?
    var hoveredHit: ViewportHit?
    var edgeTreatmentHoverTarget: SelectionTarget?
    var creation: Creation?
    var hasCanvasDrag = false
    var modifierControl = false
    var patternReplacement: ViewportPatternArrayCurvePathReplacementPreviewRequest?
    var surfaceAnalysis: SurfaceAnalysisResult?
    var surfaceAnalysisOptions = ViewportSurfaceAnalysisOptions()
    var surfaceContinuity: SurfaceContinuityResult?
    var sectionAnalysis: SectionAnalysisResult?
    var sectionAnalysisHandle: ViewportSectionAnalysisDistanceHandle?
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
    var sketchCornerTreatmentHandle: ViewportSketchCornerTreatmentHandle?
    var sketchJoinEndpointFeedback: [SketchCurveJoinEndpointFeedback] = []
    var transformGizmo: ViewportTransformGizmoConfiguration?
    // The producer has a fixed set of callback routes; only availability matters.
    var availableRoutes: UInt32 = 0

    /// This key without what the pointer's hover decides: the hovered target and reference, the
    /// hovered handle and hit, the edge-treatment hover target, snap feedback and the placement
    /// highlight. Two keys whose hover-free keys are equal differ in hover alone.
    var withoutHover: Self {
        var key = self
        key.selection = SelectionModel(
            selectedTargets: selection.selectedTargets,
            selectedReferences: selection.selectedReferences
        )
        key.hoveredHandle = nil
        key.hoveredHit = nil
        key.edgeTreatmentHoverTarget = nil
        key.snap = nil
        key.placement = nil
        return key
    }
}
