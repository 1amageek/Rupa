import Foundation
import MacComponent
import RupaCore
import RupaDomainFoundation
import RupaKit
import RupaGeometry
import RupaProject
import RupaRendering
import SwiftUI

func viewportDisplayModeTitle(_ mode: ViewportDisplayMode) -> String {
    switch mode {
    case .solid: "Solid"
    case .solidWithEdges: "Solid + Mesh Edges"
    case .wireframe: "Wireframe"
    case .normals: "Normals"
    }
}

enum WorkspaceSidebarSection: String, CaseIterable, Identifiable, Sendable {
    case scene
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .scene:
            "Scene"
        case .history:
            "History"
        }
    }
}

enum WorkspaceInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case properties
    case definitions

    var id: Self { self }

    var title: String {
        switch self {
        case .properties:
            "Properties"
        case .definitions:
            "Definitions"
        }
    }
}

@MainActor
public struct MainView: View {
    private let workspace: ProjectWorkspace
    private let domainRegistry: DomainRegistry
    private let operationSequencer: ProjectWorkspaceOperationSequencer
    private let newProject: @MainActor () -> Void
    private let onViewportMount: @MainActor (ProjectDocumentLifetimeID, ViewportControlSession) -> Void
    private let onViewportUnmount: @MainActor (ViewportInstanceID) -> Void

    public init(
        workspace: ProjectWorkspace,
        domainRegistry: DomainRegistry = DomainRegistry(),
        operationSequencer: ProjectWorkspaceOperationSequencer,
        newProject: @escaping @MainActor () -> Void = {},
        onViewportMount: @escaping @MainActor (ProjectDocumentLifetimeID, ViewportControlSession) -> Void = { _, _ in },
        onViewportUnmount: @escaping @MainActor (ViewportInstanceID) -> Void = { _ in }
    ) {
        self.workspace = workspace
        self.domainRegistry = domainRegistry
        self.operationSequencer = operationSequencer
        self.newProject = newProject
        self.onViewportMount = onViewportMount
        self.onViewportUnmount = onViewportUnmount
    }

    public var body: some View {
        Group {
            if let snapshot = workspace.view {
                ProjectMainViewContent(
                    workspace: workspace,
                    snapshot: snapshot,
                    domainRegistry: domainRegistry,
                    operationSequencer: operationSequencer,
                    newProject: newProject,
                    onViewportMount: onViewportMount,
                    onViewportUnmount: onViewportUnmount
                )
                .id(snapshot.documentLifetimeID)
            } else {
                ProgressView("Loading Project")
                    .frame(minWidth: WorkspaceEditorSplitLayout.minimumWindowWidth, minHeight: 720)
            }
        }
    }
}

@MainActor
private struct ProjectMainViewContent: View {
    private let workspace: ProjectWorkspace
    private let snapshot: ProjectViewSnapshot
    private var viewportInstanceID: ViewportInstanceID { viewportControlSession.id }
    private let onViewportMount: @MainActor (ProjectDocumentLifetimeID, ViewportControlSession) -> Void
    private let onViewportUnmount: @MainActor (ViewportInstanceID) -> Void
    @State private var viewportControlSession: ViewportControlSession
    @State private var isViewportShadingPresented = false
    @State private var selectedSharedDefinitionID: ComponentDefinitionID?
    @State private var modelingDraft: ModelingOperationDraft?
    @State private var gearDraft: InvoluteGearDraft?
    @State private var solidShape: WorkspaceSolidShape = .box
    @State private var modelingPreview = ModelingPreviewState()
    @State private var modelingTask: Task<Void, Never>?
    @State private var meshDraft: MeshOperationDraft?
    @State private var viewportMeasurementState = ViewportMeasurementState()
    @State private var pendingOutlinerStateIDs: Set<SceneNodeID> = []
    @State private var meshSelectionDomain = GeometryAttributeDomain.face
    @State private var meshSelectionOverlay: ViewportMeshSelectionOverlay?
    @State private var meshOverlayError: String?
    @State private var showsMakeEditableConfirmation = false
    @State private var historyPreviewTitle: String?
    @State private var selectedTool: ModelingTool
    @State private var polygonToolState: PolygonToolState
    @State private var sketchInputState: SketchInputState
    /// How many of the workspace's own sentences the transcript keeps. The newest is what the
    /// status item shows; the rest are the recent history the Logs pane lists.
    private static let transientDiagnosticLimit = 200
    /// How many retired object property values the migration report names before it
    /// counts the rest. A status line is one sentence, and the failure log keeps the
    /// record.
    private static let namedRetiredObjectPropertyLimit = 3
    @State private var transientDiagnostics: [EditorDiagnostic]
    /// The document whose retired object property values have already been reported.
    ///
    /// See `RupaUI/DESIGN.md`, "Failure surfacing": the report is once per open, so a
    /// reappearance within the same open must not repeat it.
    @State private var reportedRetiredObjectPropertiesOf: ProjectDocumentLifetimeID?
    @State private var hoveredTarget: SelectionTarget?
    @State private var hoveredReference: SelectionReference?
    @State private var isPreviewExpanded: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var isInspectorPresented: Bool
    @State private var sidebarSection: WorkspaceSidebarSection
    @State private var inspectorTab: WorkspaceInspectorTab
    @State private var sidebarSearchText: String
    @State private var workspacePlaneMode: WorkspacePlaneMode
    @State private var selectionScope: WorkspaceSelectionScope
    @State private var selectionDragPreviewTargets: [SelectionTarget]
    @State private var selectionDragPreviewSceneNodeIDs: Set<SceneNodeID>
    @State private var patternArrayCurvePathPickState: PatternArrayCurvePathPickState
    @State private var patternArrayCurvePathPreviewCandidate: PatternArrayCurvePathCandidate?
    @State private var pointPickRequest: WorkspacePointPickRequest?
    @State private var placeSession: WorkspacePlaceSession?
    @State private var transformSession: WorkspaceTransformSession?
    @State private var mirrorSession: WorkspaceMirrorSession?
    /// Section Analysis while its dialog is up.
    @State private var sectionAnalysisSession: WorkspaceSectionAnalysisSession?
    /// The slice Section Analysis placed, shown until the command is run again.
    @State private var placedSectionQuery: SectionAnalysisQuery?
    @State private var arraySession: WorkspaceArrayCreationSession?
    @State private var selectionMass: SceneMass?
    @State private var selectionMassMeasurement = SelectionMassMeasurement()
    /// Rebuilds the view after an edit that committed but whose view failed, or stops editing.
    @State private var committedOperationRecovery: WorkspaceCommittedOperationRecovery
    /// Which dialog commands are submitting, so one OK makes one edit and a completion ends only
    /// the dialog that submitted it.
    @State private var dialogSubmissions = WorkspaceDialogSubmissions()
    @State private var measurementSeed: ViewportMeasurementSeed?
    @State private var surfaceControlPointMoveOptions = SurfaceControlPointMoveOptions()
    @State private var patternArraySummaryCache: PatternArraySummaryCache
    /// Whole-document analyses the view reads several times per render, made once per input.
    @State private var documentAnalysisCache = WorkspaceDocumentAnalysisCache()
    @State private var isGridSnapEnabled: Bool
    @State private var isObjectTargetingEnabled: Bool
    @State private var isConstructionPlaneSnapEnabled: Bool
    @State private var snapOverrideState: WorkspaceSnapOverrideState
    @State private var surfaceAnalysisOptions: ViewportSurfaceAnalysisOptions
    @State private var sectionClippingMode: WorkspaceSectionClippingMode
    @State private var selectedSplineControlPointIndex: Int
    @State private var sketchSplineControlPointSlideDistanceMeters: Double
    @State private var polySplineSurfaceVertexSlideDistanceMeters: Double
    @State private var surfaceControlPointFrameUMoveMeters: Double
    @State private var surfaceControlPointFrameVMoveMeters: Double
    @State private var surfaceControlPointFrameNormalMoveMeters: Double
    @State private var surfaceKnotInsertionValue: Double
    @State private var surfaceSpanSplitFraction: Double
    @State private var surfaceKnotMultiplicityValue: Int
    @State private var surfaceBoundaryContinuityLevel: SurfaceBoundaryContinuityLevel
    @State private var surfaceBoundaryMatchSide: SurfaceBoundaryMatchSide
    @State private var surfaceBoundaryReferenceDirection: SurfaceBoundaryReferenceDirection
    @State private var surfaceTrimDomainULowerBound: Double
    @State private var surfaceTrimDomainUUpperBound: Double
    @State private var surfaceTrimDomainVLowerBound: Double
    @State private var surfaceTrimDomainVUpperBound: Double
    @State private var sketchSplineControlPointSlideCount: Int
    @State private var slideCommandState: SlideCommandState
    @State private var slideComparison = WorkspaceSlideComparison()
    /// Trim (T) or Split Segment is running: each click on a sketch curve removes the segment under
    /// it, or splits the curve there.
    @State private var curvePickCommand: WorkspaceCurvePickCommand?
    @State private var cutCurveSession: WorkspaceCutCurveSession?
    /// Boolean's and Cut's dialogs on bodies (Q and C).
    @State private var booleanSession: WorkspaceBooleanSession?
    @State private var bodyCutSession: WorkspaceBodyCutSession?
    @State private var rebuildSession: WorkspaceRebuildSession?
    @State private var deformSession: WorkspaceDeformSession?
    @State private var projectSession: WorkspaceProjectSession?
    @State private var bridgeEdgeSession: WorkspaceBridgeEdgeSession?
    @State private var filletSession: WorkspaceFilletSession?
    /// The G1 tension typed for a Bridge Curve (D), until Return applies it or Escape drops it.
    @State private var bridgeTensionInput: (sourceID: BridgeCurveSourceID, value: Double)?
    @State private var isCommandPaletteOpen = false
    @State private var isTextDialogPresented = false
    @State private var textDialogText = ""
    @State private var textDialogFontFamily = "Helvetica"
    /// Text's size; the official default is 1 cm.
    @State private var textDialogSizeMeters = 0.01
    /// Cut Curve's Extend option: the cutter reaches the target along its line or circle.
    @State private var cutCurveExtendsCutter = false
    @State private var sketchSplitFraction: Double
    @State private var sketchRebuildControlPointCount: Int
    @State private var sketchRebuildToleranceMeters: Double
    @State private var sketchRebuildKeepsCorners: Bool
    @State private var sketchRebuildExplicitDegree: Int
    @State private var sketchRebuildExplicitSpanCount: Int
    @State private var sketchRebuildExplicitWeight: Double
    @State private var sketchExtendDistanceMeters: Double
    @State private var sketchExtendShape: ExtendCurveShape
    @State private var sketchVertexOffsetDistanceMeters: Double
    @State private var sketchCornerTreatmentDistanceMeters: Double
    @State private var sketchCornerTreatment: SketchCornerTreatment
    @State private var sketchCurveJoinContinuity: SketchCurveJoinContinuity
    @State private var sketchVertexAlignmentContinuity: SketchVertexAlignmentContinuity
    @State private var sketchVertexAlignmentDistanceMeters: Double?
    @State private var sketchVertexAlignmentParameter: Double = 0.5
    @State private var regionOffsetDistanceMeters: Double
    @State private var regionOffsetGapFill: OffsetCurveGapFill
    @State private var regionOffsetCommandState: RegionOffsetCommandState
    @State private var faceDraftAngleDegrees: Double
    @State private var edgeOffsetDistanceMeters: Double
    @State private var edgeOffsetGapFill: OffsetCurveGapFill
    /// Offset Planar Curve's gap fill at a curve's corners, which V steps.
    @State private var curveOffsetGapFill: OffsetCurveGapFill = .round
    @State private var edgeOffsetCommandState: EdgeOffsetCommandState
    @State private var dimensionCommandState: DimensionCommandState
    @State private var slotProfileWidthMeters: Double
    @State private var slotProfileCommandState: SlotProfileCommandState
    @State private var viewportProjectionBasis: ViewportProjectionBasis
    @State private var viewportChromeGeometry: WorkspaceCanvasChromeGeometry
    @State private var viewportCameraResetSignal: Int
    @State private var presentedHeaderPanel: WorkspaceCanvasHeaderPanel?
    @State private var headerHoverHint = WorkspaceHoverHint()
    @State private var viewAlignedConstructionPlaneRequest: ViewAlignedConstructionPlaneRequest?
    @State private var viewportProjectionRequest: ViewportProjectionRequest?
    @State private var viewportCameraState = WorkspaceViewportCameraState()
    @State private var viewportCameraFrameRequest: ViewportCameraFrameRequest?
    @State private var viewportProjectedGridMinorStep: ViewportProjectedGrid.ScaleReadout.Length?
    @State private var constructionPlaneRenameTargetID: ConstructionPlaneSourceID?
    @State private var constructionPlaneRenameText: String
    @State private var viewportHoverClearSignal: Int
    private let operationSequencer: ProjectWorkspaceOperationSequencer
    @FocusState private var isWorkspaceFocused: Bool
    @FocusState private var focusedPlaceOption: WorkspacePlaceOptionField?
    @FocusState private var isSectionDistanceFocused: Bool
    /// The O commands' typed distance D focuses.
    @FocusState private var focusedCommandDistance: WorkspaceCommandDistanceField?
    /// What is typed into the transform dialog's fields, applied only on Return.
    @State private var transformFieldTexts: [WorkspaceTransformTypedField: String] = [:]

    private let objectRegistry: ObjectTypeRegistry
    private let viewportObjectSelectionIndex: ViewportObjectSelectionIndex
    private let commandCatalog: WorkspaceCommandCatalog
    private let domainCommandDispatcher: ProjectDomainCommandDispatcher
    private let exactPresentationCADSceneNodeIDs: Set<SceneNodeID>
    private let selectedPresentationHasExactCADAffordanceContext: Bool
    private let newProject: @MainActor () -> Void

    init(
        workspace: ProjectWorkspace,
        snapshot: ProjectViewSnapshot,
        isPreviewExpanded: Bool = false,
        columnVisibility: NavigationSplitViewVisibility = .all,
        isInspectorPresented: Bool = true,
        domainRegistry: DomainRegistry = DomainRegistry(),
        operationSequencer: ProjectWorkspaceOperationSequencer,
        newProject: @escaping @MainActor () -> Void = {},
        onViewportMount: @escaping @MainActor (ProjectDocumentLifetimeID, ViewportControlSession) -> Void = { _, _ in },
        onViewportUnmount: @escaping @MainActor (ViewportInstanceID) -> Void = { _ in }
    ) {
        let editingDefaults = WorkspaceInteractionScaleDefaults(ruler: snapshot.workspaceState.ruler)
        let viewportControlSession = ViewportControlSession()
        self.workspace = workspace
        self.snapshot = snapshot
        self.onViewportMount = onViewportMount
        self.onViewportUnmount = onViewportUnmount
        self._viewportControlSession = State(initialValue: viewportControlSession)
        self._committedOperationRecovery = State(initialValue: WorkspaceCommittedOperationRecovery(workspace: workspace))
        self.operationSequencer = operationSequencer
        self.newProject = newProject
        self._selectedTool = State(initialValue: .select)
        self._polygonToolState = State(initialValue: .standard)
        self._sketchInputState = State(initialValue: .standard)
        self._transientDiagnostics = State(initialValue: [])
        self._hoveredTarget = State(initialValue: nil)
        self._hoveredReference = State(initialValue: nil)
        self._isPreviewExpanded = State(initialValue: isPreviewExpanded)
        self._columnVisibility = State(initialValue: columnVisibility)
        self._isInspectorPresented = State(initialValue: isInspectorPresented)
        self._sidebarSection = State(initialValue: .scene)
        self._inspectorTab = State(initialValue: .properties)
        self._sidebarSearchText = State(initialValue: "")
        self._workspacePlaneMode = State(initialValue: .adaptive)
        self._selectionScope = State(initialValue: .object)
        self._selectionDragPreviewTargets = State(initialValue: [])
        self._selectionDragPreviewSceneNodeIDs = State(initialValue: [])
        self._patternArrayCurvePathPickState = State(initialValue: .inactive)
        self._patternArrayCurvePathPreviewCandidate = State(initialValue: nil)
        self._patternArraySummaryCache = State(initialValue: PatternArraySummaryCache())
        self._isGridSnapEnabled = State(initialValue: true)
        self._isObjectTargetingEnabled = State(initialValue: true)
        self._isConstructionPlaneSnapEnabled = State(initialValue: true)
        self._snapOverrideState = State(initialValue: WorkspaceSnapOverrideState())
        self._surfaceAnalysisOptions = State(initialValue: ViewportSurfaceAnalysisOptions())
        self._sectionClippingMode = State(initialValue: .front)
        self._selectedSplineControlPointIndex = State(initialValue: 0)
        self._sketchSplineControlPointSlideDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._polySplineSurfaceVertexSlideDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._surfaceControlPointFrameUMoveMeters = State(initialValue: editingDefaults.surfaceFrameTangentialMoveMeters)
        self._surfaceControlPointFrameVMoveMeters = State(initialValue: editingDefaults.surfaceFrameTangentialMoveMeters)
        self._surfaceControlPointFrameNormalMoveMeters = State(initialValue: editingDefaults.surfaceFrameNormalMoveMeters)
        self._surfaceKnotInsertionValue = State(initialValue: 0.5)
        self._surfaceSpanSplitFraction = State(initialValue: 0.5)
        self._surfaceKnotMultiplicityValue = State(initialValue: 2)
        self._surfaceBoundaryContinuityLevel = State(initialValue: .g1)
        self._surfaceBoundaryMatchSide = State(initialValue: .automatic)
        self._surfaceBoundaryReferenceDirection = State(initialValue: .automatic)
        self._surfaceTrimDomainULowerBound = State(initialValue: 0.0)
        self._surfaceTrimDomainUUpperBound = State(initialValue: 1.0)
        self._surfaceTrimDomainVLowerBound = State(initialValue: 0.0)
        self._surfaceTrimDomainVUpperBound = State(initialValue: 1.0)
        self._sketchSplineControlPointSlideCount = State(initialValue: 1)
        self._slideCommandState = State(initialValue: .inactive)
        self._sketchSplitFraction = State(initialValue: 0.5)
        self._sketchRebuildControlPointCount = State(initialValue: 7)
        self._sketchRebuildToleranceMeters = State(initialValue: editingDefaults.sketchRebuildToleranceMeters)
        self._sketchRebuildKeepsCorners = State(initialValue: true)
        self._sketchRebuildExplicitDegree = State(initialValue: 3)
        self._sketchRebuildExplicitSpanCount = State(initialValue: 2)
        self._sketchRebuildExplicitWeight = State(initialValue: 0.5)
        self._sketchExtendDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._sketchExtendShape = State(initialValue: .natural)
        self._sketchVertexOffsetDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._sketchCornerTreatmentDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._sketchCornerTreatment = State(initialValue: .fillet)
        self._sketchCurveJoinContinuity = State(initialValue: .g0)
        self._sketchVertexAlignmentContinuity = State(initialValue: .g0)
        self._regionOffsetDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._regionOffsetGapFill = State(initialValue: .round)
        self._regionOffsetCommandState = State(initialValue: .inactive)
        self._faceDraftAngleDegrees = State(initialValue: 5.0)
        self._edgeOffsetDistanceMeters = State(initialValue: editingDefaults.operationStepMeters)
        self._edgeOffsetGapFill = State(initialValue: .round)
        self._edgeOffsetCommandState = State(initialValue: .inactive)
        self._dimensionCommandState = State(initialValue: .inactive)
        self._slotProfileWidthMeters = State(initialValue: editingDefaults.slotWidthMeters)
        self._slotProfileCommandState = State(initialValue: .inactive)
        self._viewportProjectionBasis = State(initialValue: .isometric)
        self._viewportChromeGeometry = State(initialValue: .empty)
        self._viewportCameraResetSignal = State(initialValue: 0)
        self._presentedHeaderPanel = State(initialValue: nil)
        self._viewAlignedConstructionPlaneRequest = State(initialValue: nil)
        self._viewportProjectionRequest = State(initialValue: nil)
        self._viewportCameraFrameRequest = State(initialValue: nil)
        self._viewportProjectedGridMinorStep = State(initialValue: nil)
        self._constructionPlaneRenameTargetID = State(initialValue: nil)
        self._constructionPlaneRenameText = State(initialValue: "")
        self._viewportHoverClearSignal = State(initialValue: 0)
        self.objectRegistry = snapshot.objectRegistry
        self.viewportObjectSelectionIndex = ViewportObjectSelectionIndex(
            document: snapshot.document.document,
            selection: snapshot.selection
        )
        self.commandCatalog = WorkspaceCommandCatalog(domainRegistry: domainRegistry)
        self.domainCommandDispatcher = ProjectDomainCommandDispatcher(registry: domainRegistry)
        let exactPresentationCADSceneNodeIDs = Self.makeExactPresentationCADSceneNodeIDs(
            snapshot: snapshot
        )
        self.exactPresentationCADSceneNodeIDs = exactPresentationCADSceneNodeIDs
        self.selectedPresentationHasExactCADAffordanceContext =
            MeshSourcePresentationExactCADSelectionResolver(
                availableSceneNodeIDs: exactPresentationCADSceneNodeIDs
            )
            .hasExactContext(for: snapshot.selection)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: WorkspaceEditorSplitLayout.sidebarMinimumWidth,
                    ideal: 248,
                    max: 320
                )
        } detail: {
            editorDetailPane
                .navigationTitle(documentTitle)
                .toolbar {
                    editorToolbar
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onDeleteCommand {
            _ = handleDeleteSelection()
        }
        .frame(minWidth: WorkspaceEditorSplitLayout.minimumWindowWidth, minHeight: 720)
        .onChange(of: modelingDraft) { _, _ in invalidateModelingPreview() }
        .onChange(of: meshDraft) { _, _ in invalidateModelingPreview() }
        .task(id: meshOverlayRequest) { await updateMeshSelectionOverlay() }
        .onChange(of: snapshot.authorityCoordinate) { _, _ in
            gearDraft = nil
            if modelingPreview.phase != .applying { invalidateModelingPreview() }
            if let draft = meshDraft,
               snapshot.document.document.authoredMeshAssets[draft.sourceID]?.contentIdentity != draft.contentIdentity {
                meshDraft = nil
            }
        }
        .onAppear {
            onViewportMount(snapshot.documentLifetimeID, viewportControlSession)
            reportRetiredObjectProperties()
        }
        .overlay {
            if let reason = committedOperationRecovery.unavailableReason {
                ContentUnavailableView(
                    "Editing Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("An edit was applied, but the project view could not be rebuilt. "
                        + "Reopen the project to continue. \(reason)")
                )
                .background(.background)
                .accessibilityIdentifier("Workspace.editingUnavailable")
            }
        }
        .onDisappear {
            modelingTask?.cancel()
            selectionMassMeasurement.cancel()
            onViewportUnmount(viewportInstanceID)
        }
        .confirmationDialog("Make CAD Editable as Mesh?", isPresented: $showsMakeEditableConfirmation) {
            Button("Make Editable", action: makeSelectedCADEditable)
                .contentShape(Rectangle())
            Button("Cancel", role: .cancel) {}
                .contentShape(Rectangle())
        } message: {
            Text("Create an independent Mesh from modeling-quality CAD geometry and switch its presentation. The CAD source is retained. This operation is undoable.")
        }
    }

    /// Tells the person who opened this document which stored values its object types
    /// no longer declare, once per open.
    ///
    /// The values are already gone from the open document and the next save writes it
    /// without them, so this is the only point at which the loss is visible.
    /// See `RupaUI/DESIGN.md`, "Failure surfacing".
    private func reportRetiredObjectProperties() {
        guard reportedRetiredObjectPropertiesOf != snapshot.documentLifetimeID else { return }
        reportedRetiredObjectPropertiesOf = snapshot.documentLifetimeID
        let retired = snapshot.retiredObjectProperties
        guard !retired.isEmpty else { return }
        let named = retired.prefix(Self.namedRetiredObjectPropertyLimit)
            .map { "\($0.sceneNodeName) · \($0.propertyID.rawValue)" }
            .joined(separator: ", ")
        let suffix = retired.count > Self.namedRetiredObjectPropertyLimit
            ? ", and \(retired.count - Self.namedRetiredObjectPropertyLimit) more"
            : ""
        reportToolStatus(
            "Opened without \(retired.count) stored value(s) these object types no longer declare: \(named)\(suffix). Saving this document discards them.",
            severity: .warning,
            operation: "Document.objectSchemaMigration"
        )
    }

    private func invalidateModelingPreview() {
        modelingTask?.cancel()
        modelingTask = nil
        modelingPreview.invalidate()
    }

    private func cancelModelingOperation() {
        invalidateModelingPreview()
        modelingDraft = nil
        meshDraft = nil
        gearDraft = nil
        historyPreviewTitle = nil
        if selectedTool == .mesh { selectedTool = .select }
    }

    private func beginModelingOperation(_ kind: ModelingOperationDraft.Kind) {
        switch kind {
        case .box: activateSolidShape(.box); return
        case .sphere: activateSolidShape(.sphere); return
        case .cylinder: activateSolidShape(.cylinder); return
        default: break
        }
        cancelModelingOperation()
        selectedTool = .select
        curvePickCommand = nil
        cutCurveSession = nil
        filletSession = nil
        endBodyOperationDialogs()
        modelingDraft = ModelingOperationDraft(
            kind: kind,
            selection: snapshot.selection,
            ruler: snapshot.workspaceState.ruler
        )
    }

    private func beginConstrainedSurfaceEditing(_ feature: FeatureNode) {
        guard case .constrainedSurface(let source) = feature.operation else { return }
        beginModelingOperation(.constrainedSurface)
        modelingDraft?.name = feature.name ?? "Constrained Surface"
        modelingDraft?.constrainedFeatureID = feature.id
        modelingDraft?.constrainedPoints = source.points
        modelingDraft?.pointTolerance = "\(source.positionTolerance) m"
        modelingDraft?.angularTolerance = "\(source.angularTolerance * 180 / .pi)"
        modelingDraft?.pointOptimization = source.optimization
        let occurrences = snapshot.document.document.productMetadata.sceneNodes.values
            .filter { $0.reference == .body(feature.id) }
        let selected = occurrences.first { snapshot.selection.wholeSceneNodeIDs.contains($0.id) }
        modelingDraft?.constrainedSceneNodeID = selected?.id ?? (occurrences.count == 1 ? occurrences.first?.id : nil)
    }

    private func beginGearEditing(_ feature: FeatureNode? = nil) {
        cancelModelingOperation()
        selectedTool = .select
        gearDraft = InvoluteGearDraft(feature: feature,
            parameters: snapshot.document.document.cadDocument.parameters,
            unit: snapshot.workspaceState.ruler.displayUnit)
    }

    private func previewModelingOperation() {
        guard let draft = modelingDraft else { return }
        let command: EditorCommand
        do {
            command = try draft.command(in: snapshot.document.document)
        } catch {
            // The panel disables Preview while the draft names no command, so
            // this is the document moving between the press and this call: a
            // refused precondition rather than a run that failed. It goes to
            // the refusal channel, and the panel shows the same reason itself.
            invalidateModelingPreview()
            reportToolStatus(error.localizedDescription, severity: .warning)
            return
        }
        do {
            let action = try DefaultProjectWorkspaceActionPlanner().source(
                name: draft.name, commands: [command], from: snapshot
            )
            startModelingPreview(.source(action))
        } catch {
            invalidateModelingPreview()
            modelingPreview.errorMessage = recordFailure(error)
        }
    }

    private func previewHistoryOperation(_ command: EditorCommand, title: String) {
        cancelModelingOperation()
        historyPreviewTitle = title
        do {
            let action = try DefaultProjectWorkspaceActionPlanner().source(name: title, commands: [command], from: snapshot)
            startModelingPreview(.source(action))
        } catch { modelingPreview.errorMessage = recordFailure(error) }
    }

    private func handleMeshElementPick(_ hit: ViewportMeshElementHit?, intent: ViewportSelectionIntent) {
        guard !modelingPreview.isBusy else { return }
        guard let hit else {
            if intent == .replace { meshDraft?.elements.removeAll() }
            return
        }
        // A pick naming a frame the workspace has already replaced is a
        // transient miss, not a refusal: the successor frame carries the hit.
        guard hit.snapshotID == snapshot.viewport.snapshotID else { return }
        guard let asset = snapshot.document.document.authoredMeshAssets[hit.sourceID] else {
            reportToolStatus(
                "The picked Mesh source is no longer part of this document.",
                severity: .warning
            )
            return
        }
        guard let nodeID = snapshot.sceneNodeIDByOccurrenceID[hit.occurrenceID] else {
            reportToolStatus(
                "The picked Mesh occurrence has no scene node to edit.",
                severity: .warning
            )
            return
        }
        guard snapshot.document.document.productMetadata.sceneNodes[nodeID]?.isLocked == false else {
            reportToolStatus(
                "Unlock this scene node before selecting Mesh elements on it.",
                severity: .warning
            )
            return
        }
        do {
            var draft = meshDraft ?? MeshOperationDraft(sourceID: hit.sourceID, contentIdentity: asset.contentIdentity, occurrenceID: hit.occurrenceID, unit: snapshot.workspaceState.ruler.displayUnit)
            if draft.sourceID != hit.sourceID || draft.contentIdentity != asset.contentIdentity || draft.occurrenceID != hit.occurrenceID {
                draft = MeshOperationDraft(sourceID: hit.sourceID, contentIdentity: asset.contentIdentity, occurrenceID: hit.occurrenceID, unit: snapshot.workspaceState.ruler.displayUnit)
            }
            try draft.select(hit.element, toggle: intent == .toggle)
            updateMeshDraft(draft)
        } catch {
            modelingPreview.errorMessage = recordFailure(error)
        }
    }

    private var meshElementPickHandler: ((ViewportMeshElementHit?, ViewportSelectionIntent) -> Void)? {
        guard selectedTool == .mesh else { return nil }
        return { hit, intent in handleMeshElementPick(hit, intent: intent) }
    }

    private struct MeshOverlayRequest: Equatable {
        let snapshotID: EvaluationSnapshotID
        let occurrenceID: SceneOccurrenceID
        let elements: [MeshSelectionElement]
    }

    private var meshOverlayRequest: MeshOverlayRequest? {
        guard selectedTool == .mesh, let draft = meshDraft else { return nil }
        return MeshOverlayRequest(snapshotID: snapshot.viewport.snapshotID, occurrenceID: draft.occurrenceID, elements: draft.elements)
    }

    private func updateMeshSelectionOverlay() async {
        meshSelectionOverlay = nil
        meshOverlayError = nil
        guard let request = meshOverlayRequest,
              let item = snapshot.viewport.items.first(where: { $0.occurrenceID == request.occurrenceID }) else { return }
        let worker = Task.detached(priority: .userInitiated) {
            try ViewportMeshSelectionOverlay.build(snapshotID: request.snapshotID, item: item, selectedElements: request.elements)
        }
        do {
            let overlay = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard meshOverlayRequest == request else { return }
            meshSelectionOverlay = overlay
            if var draft = meshDraft, !modelingPreview.isBusy, draft.coordinates.allSatisfy(\.isEmpty) {
                prefillMeshPosition(&draft, from: overlay)
                meshDraft = draft
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, meshOverlayRequest == request else { return }
            meshOverlayError = recordFailure(error)
        }
    }

    private func updateMeshDraft(_ draft: MeshOperationDraft) {
        var updated = draft
        if updated.kind == .position,
           (meshDraft?.kind != .position || meshDraft?.elements != updated.elements) {
            updated.coordinates = ["", "", ""]
            prefillMeshPosition(&updated, from: meshSelectionOverlay)
        }
        meshDraft = updated
    }

    private func prefillMeshPosition(_ draft: inout MeshOperationDraft, from overlay: ViewportMeshSelectionOverlay?) {
        guard draft.kind == .position, draft.elements.count == 1,
              case .vertex = draft.elements[0], let overlay,
              overlay.snapshotID == snapshot.viewport.snapshotID,
              overlay.occurrenceID == draft.occurrenceID,
              overlay.selectedElements == draft.elements,
              let point = overlay.points.first?.sourcePosition else { return }
        draft.coordinates = [point.x, point.y, point.z].map {
            let field = workspaceLengthFieldPresentation(fromMeters: $0, preferredUnit: draft.unit)
            return field.text + " " + field.unit.symbol
        }
    }

    private func previewMeshOperation() {
        guard let draft = meshDraft else { return }
        do { startModelingPreview(.mesh(try draft.request(from: snapshot))) }
        catch {
            invalidateModelingPreview()
            modelingPreview.errorMessage = recordFailure(error)
        }
    }

    private func makeSelectedCADEditable() {
        guard !modelingPreview.isBusy, snapshot.selection.selectedTargets.count == 1,
              let nodeID = snapshot.selection.selectedTargets.first?.sceneNodeID else { return }
        let request = ProjectMakeEditableRequest(snapshot: snapshot, sceneNodeID: nodeID, authoredMeshSourceID: GeometrySourceID(), authoredMeshRepresentationID: GeometryRepresentationID())
        cancelModelingOperation()
        selectedTool = .mesh
        let token = modelingPreview.beginConfirmedApply()
        modelingTask = Task { @MainActor in
            do {
                _ = try await runWorkspaceOperation { try await workspace.makeEditable(request) }
                guard modelingPreview.token == token else { return }
                modelingPreview.invalidate()
                selectedTool = .mesh
            } catch is CancellationError {
                // A run cancelled by its own successor, or by teardown, is
                // superseded rather than refused, so it names no failure.
                return
            } catch {
                modelingPreview.fail(error, token: token)
                reportToolStatus(
                    recordFailure(error),
                    severity: .warning,
                    recordsFailure: false
                )
            }
        }
    }

    private func startModelingPreview(_ request: ModelingPreviewState.Request) {
        modelingTask?.cancel()
        let token = modelingPreview.begin(request)
        modelingTask = Task { @MainActor in
            do {
                let payload = try await runWorkspaceOperation {
                    switch request {
                    case .source(let action): try await workspace.previewRenderPayload(action)
                    case .mesh(let request): try await workspace.previewRenderPayload(request)
                    }
                }
                try Task.checkCancellation()
                modelingPreview.complete(payload, token: token)
            } catch is CancellationError {
                // A run cancelled by its own successor, or by teardown, is
                // superseded rather than refused, so it names no failure.
                return
            } catch {
                modelingPreview.fail(error, token: token)
                recordFailure(error)
            }
        }
    }

    private func applyModelingOperation() {
        guard let request = modelingPreview.takeForApply() else { return }
        let token = modelingPreview.token
        modelingTask = Task { @MainActor in
            do {
                _ = try await runWorkspaceOperation {
                    switch request {
                    case .source(let action): _ = try await workspace.perform(action)
                    case .mesh(let request): _ = try await workspace.commit(request)
                    }
                    return true
                }
                guard modelingPreview.token == token else { return }
                cancelModelingOperation()
            } catch is CancellationError {
                // A run cancelled by its own successor, or by teardown, is
                // superseded rather than refused, so it names no failure.
                return
            } catch {
                // A post-commit failure consumes the request too; never replay it.
                modelingPreview.fail(error, token: token)
                recordFailure(error)
            }
        }
    }

    private var diagnostics: [EditorDiagnostic] {
        EditorDiagnostic.stableMerged([
            snapshot.evaluationSnapshot.diagnostics,
            transientDiagnostics,
        ])
    }

    private var activeConstructionPlane: ConstructionPlaneSource? {
        guard let id = snapshot.workspaceState.activeConstructionPlaneID else {
            return nil
        }
        return snapshot.document.document.productMetadata.constructionPlanes[id]
    }

    private func activeSketchPlane(fallback: SketchPlane = .xy) -> SketchPlane {
        activeConstructionPlane?.plane ?? fallback
    }

    private var displaySelection: SelectionModel {
        let hover: SelectionModel.Hover
        if let hoveredTarget {
            hover = .target(hoveredTarget)
        } else if let hoveredReference {
            hover = .reference(hoveredReference)
        } else {
            hover = .none
        }
        return snapshot.selection.replacingHover(with: hover)
    }

    private var viewportDisplayMode: ViewportDisplayMode {
        viewportControlSession.displayMode
    }

    /// The log the workspace chrome records refused operations in.
    /// See `RupaUI/DESIGN.md`, "Failure surfacing".
    private var failureLog: WorkspaceFailureLog { .shared }

    /// Records `error` and returns the message to display, so a catch keeps the
    /// text it already showed while the event survives the next interaction.
    @discardableResult
    private func recordFailure(
        _ error: any Error,
        operation: String = #function
    ) -> String {
        failureLog.record(error, operation: operation)
    }

    private func reportViewportPresentationFailure(_ error: any Error) {
        reportToolStatus(
            recordFailure(error, operation: "Viewport.presentation"),
            severity: .error,
            recordsFailure: false
        )
    }

    /// Publishes a tool status line. `.info` is progress; anything else is a
    /// refused operation and is recorded unless the caller already recorded it
    /// with the originating error.
    private func reportToolStatus(
        _ message: String,
        severity: EditorDiagnostic.Severity = .info,
        recordsFailure: Bool = true,
        operation: String = #function
    ) {
        if recordsFailure, severity != .info {
            failureLog.record(refusal: message, operation: operation)
        }
        transientDiagnostics.append(
            EditorDiagnostic(severity: severity, message: message)
        )
        // The status item reads this array on every layout pass and a tool activation appends to
        // it, so its length is a contract rather than an accident. `failureLog` is the authority
        // for what failed; dropping the oldest sentence loses a view, never a record.
        if transientDiagnostics.count > Self.transientDiagnosticLimit {
            transientDiagnostics.removeFirst(
                transientDiagnostics.count - Self.transientDiagnosticLimit
            )
        }
    }

    private func enqueueWorkspaceOperation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
        let expectedDocumentLifetimeID = snapshot.documentLifetimeID
        let recovery = committedOperationRecovery
        return operationSequencer.enqueue(
            operationGuard: {
                guard workspace.view?.documentLifetimeID == expectedDocumentLifetimeID else {
                    throw ProjectWorkspaceActionError(
                        code: .documentLifetimeMismatch,
                        message: "The queued UI operation belongs to a replaced project document."
                    )
                }
                try recovery.checkAvailable()
            },
            {
                // A committed edit whose view failed is recovered in this slot, before the next
                // queued operation plans against the view.
                try await recovery.run(operation)
            }
        )
    }

    private func runWorkspaceOperation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        let task = enqueueWorkspaceOperation(operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func clearSelection(
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        selectedSharedDefinitionID = nil
        let task = enqueueWorkspaceOperation {
            let published = try await workspace.applySelection(.clear)
            completion(published)
            return published
        }
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func submitSelectionMutation(
        _ mutation: @escaping @MainActor @Sendable (
            inout SelectionModel,
            DesignDocument
        ) throws -> Void,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        selectedSharedDefinitionID = nil
        isWorkspaceFocused = true
        reportFailure(of: selectionSubmitter.queue(mutation, completion: completion))
    }

    /// Selection changes check against the workspace's latest published view: a completion runs
    /// after its command published, when `snapshot` still holds the view before it.
    private var selectionSubmitter: WorkspaceSelectionSubmitter {
        WorkspaceSelectionSubmitter(workspace: workspace) { operation in
            enqueueWorkspaceOperation(operation)
        }
    }

    private func reportFailure(of task: Task<ProjectViewSnapshot, Error>) {
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    @discardableResult
    private func selectSceneNodes(_ ids: [SceneNodeID]) -> Bool {
        updateSelection { selection, document in
            try selection.selectSceneNodes(ids, in: document)
        }
    }

    @discardableResult
    private func selectTarget(_ target: SelectionTarget?) -> Bool {
        updateSelection { selection, document in
            try selection.selectTarget(target, in: document)
        }
    }

    @discardableResult
    private func selectTargets(_ targets: [SelectionTarget]) -> Bool {
        updateSelection { selection, document in
            try selection.selectTargets(targets, in: document)
        }
    }

    @discardableResult
    private func selectReference(_ reference: SelectionReference?) -> Bool {
        updateSelection { selection, document in
            try selection.selectReference(reference, in: document)
        }
    }

    @discardableResult
    private func selectReferences(_ references: [SelectionReference]) -> Bool {
        updateSelection { selection, document in
            try selection.selectReferences(references, in: document)
        }
    }

    @discardableResult
    private func updateSelection(
        _ update: @escaping @MainActor @Sendable (
            inout SelectionModel,
            DesignDocument
        ) throws -> Void
    ) -> Bool {
        selectedSharedDefinitionID = nil
        do {
            reportFailure(of: try selectionSubmitter.submit(update))
            isWorkspaceFocused = true
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    private func hoverSceneNode(_ id: SceneNodeID?) -> Bool {
        do {
            var selection = displaySelection
            try selection.hoverSceneNode(id, in: snapshot.document.document)
            hoveredTarget = selection.hoveredTarget
            hoveredReference = selection.hoveredReference
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    private func hoverTarget(_ target: SelectionTarget?) -> Bool {
        do {
            var selection = displaySelection
            try selection.hoverTarget(target, in: snapshot.document.document)
            hoveredTarget = selection.hoveredTarget
            hoveredReference = selection.hoveredReference
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    private func hoverReference(_ reference: SelectionReference?) -> Bool {
        do {
            var selection = displaySelection
            try selection.hoverReference(reference, in: snapshot.document.document)
            hoveredTarget = selection.hoveredTarget
            hoveredReference = selection.hoveredReference
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    private func applyWorkspace(
        _ command: WorkspaceCommand,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        applyWorkspace([command], completion: completion)
    }

    private func applyWorkspace(
        _ commands: [WorkspaceCommand],
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        applyWorkspace(commands: { _ in commands }, completion: completion)
    }

    private func applyWorkspace(
        commands: @escaping @MainActor @Sendable (ProjectViewSnapshot) throws -> [WorkspaceCommand],
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        let operation: @MainActor @Sendable () async throws -> ProjectViewSnapshot = {
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            let currentCommands = try commands(current)
            let published = if currentCommands.isEmpty {
                current
            } else {
                try await workspace.applyWorkspace(currentCommands)
            }
            completion(published)
            return published
        }
        if submitNumericInput({ _ = try await operation() }) { return }
        let task = enqueueWorkspaceOperation(operation)
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func submitSource(
        _ command: EditorCommand,
        completion: @escaping @MainActor (CommandExecutionResult?) async throws -> Void = { _ in }
    ) {
        submitSource([command], name: command.name) { results in
            try await completion(results.last)
        }
    }

    private func submitSource(
        _ commands: [EditorCommand],
        name: String,
        completion: @escaping @MainActor ([CommandExecutionResult]) async throws -> Void = { _ in }
    ) {
        submitSource(name: name, commands: { _ in commands }, completion: completion)
    }

    private func submitSource(
        name: String,
        commands: @escaping @MainActor @Sendable (ProjectViewSnapshot) throws -> [EditorCommand],
        completion: @escaping @MainActor ([CommandExecutionResult]) async throws -> Void = { _ in }
    ) {
        if submitNumericInput({
            let results = try await executeSource(name: name, commands: commands)
            try await completion(results)
        }) { return }
        let task = enqueueWorkspaceOperation {
            let results = try await executeSource(name: name, commands: commands)
            try await completion(results)
            return results
        }
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    /// Submits a dialog command's edit (`WorkspaceDialogSubmissions`): refused while the same
    /// dialog's earlier edit is still applying; the dialog ends (`end`) only when the edit exists
    /// and the dialog that submitted it (`instance`) is still the running one; a refused edit
    /// leaves the dialog for another try.
    private func submitDialogCommand(
        _ commands: [EditorCommand],
        name: String,
        instance: WorkspaceDialogInstance,
        running: @escaping @MainActor () -> WorkspaceDialogInstance?,
        end: @escaping @MainActor () -> Void,
        done: @escaping @MainActor () -> Void
    ) {
        guard dialogSubmissions.begin(instance) else {
            reportToolStatus("\(name) is still applying the previous OK.", severity: .warning)
            return
        }
        let submissions = dialogSubmissions
        let task = enqueueWorkspaceOperation {
            try await executeSource(name: name, commands: { _ in commands })
        }
        Task { @MainActor in
            let outcome: WorkspaceDialogSubmissions.Outcome
            do {
                let results = try await task.value
                outcome = results.last?.didMutate == true ? .applied : .refused
            } catch let error as WorkspaceCommittedOperationError {
                reportToolStatus(error.localizedDescription, severity: .warning)
                if case .workspaceUnavailable = error {
                    outcome = .refused
                } else {
                    outcome = .appliedWithViewFailure
                }
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
                outcome = .refused
            }
            guard submissions.finish(instance, outcome: outcome, running: running()) else { return }
            end()
            if outcome == .applied { done() }
        }
    }

    /// The control context is synchronous; queued work never inherits it.
    private func submitNumericInput(
        _ operation: @escaping @MainActor @Sendable () async throws -> Void
    ) -> Bool {
        guard let controlID = InspectorInputSubmission.controlID else { return false }
        let lifetime = snapshot.documentLifetimeID
        InspectorInputSubmission.$controlID.withValue(nil) {
            operationSequencer.enqueueReplacingPending(key: controlID) {
                do {
                    guard workspace.view?.documentLifetimeID == lifetime else {
                        throw ProjectWorkspaceActionError(
                            code: .documentLifetimeMismatch,
                            message: "The edited document is no longer active.")
                    }
                    try await committedOperationRecovery.run(operation)
                } catch {
                    reportToolStatus(error.localizedDescription, severity: .warning)
                }
            }
        }
        return true
    }

    private func performSource(
        _ command: EditorCommand
    ) async -> CommandExecutionResult? {
        await performSource([command], name: command.name).last
    }

    private func performSource(
        _ commands: [EditorCommand],
        name: String
    ) async -> [CommandExecutionResult] {
        await performSource(name: name, commands: { _ in commands })
    }

    private func performSource(
        name: String,
        commands: @escaping @MainActor @Sendable (ProjectViewSnapshot) throws -> [EditorCommand]
    ) async -> [CommandExecutionResult] {
        let task = enqueueWorkspaceOperation {
            try await executeSource(name: name, commands: commands)
        }
        do {
            return try await task.value
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return []
        }
    }

    private func executeSource(
        name: String,
        commands: @escaping @MainActor @Sendable (ProjectViewSnapshot) throws -> [EditorCommand]
    ) async throws -> [CommandExecutionResult] {
        guard let current = workspace.view else {
            throw ProjectWorkspaceActionError(
                code: .snapshotUnavailable,
                message: "The project workspace has no published view snapshot."
            )
        }
        let currentCommands = try commands(current)
        guard currentCommands.isEmpty == false else {
            return []
        }
        let action = try DefaultProjectWorkspaceActionPlanner().source(
            name: name,
            commands: currentCommands,
            from: current
        )
        let result = try await workspace.perform(action)
        guard case .source(let commit, _) = result else {
            throw ProjectWorkspaceActionError(
                code: .actionResultMismatch,
                message: "The project returned an interaction result for a source command."
            )
        }
        return commit.commandResults
    }

    /// Re-evaluates the published document and reports what the evaluation
    /// found.
    ///
    /// Validation is a read. `EditorCommand.validateDocument` is the one Core
    /// command that mutates no source, and a project source transaction carries
    /// only source-mutating commands, so submitting it through `submitSource`
    /// refuses every press instead of validating anything. The workspace
    /// already owns the published evaluation this view reads, so the button
    /// asks it to evaluate that publication again and reports the counts the
    /// new publication carries. See `RupaUI/DESIGN.md`, "Contracts and Invariants".
    ///
    /// The operation succeeded even when the document it evaluated has errors,
    /// so the line it publishes is progress, not a refusal. The document's own
    /// diagnostics reach the Issues readout through the republished snapshot.
    private func validateDocument() {
        let task = enqueueWorkspaceOperation { () -> ProjectViewSnapshot in
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            return try await workspace.evaluate(from: current)
        }
        Task { @MainActor in
            do {
                let published = try await task.value
                reportToolStatus(validationSummary(of: published), severity: .info)
            } catch {
                reportToolStatus(
                    recordFailure(error),
                    severity: .error,
                    recordsFailure: false
                )
            }
        }
    }

    private func validationSummary(of published: ProjectViewSnapshot) -> String {
        let diagnostics = published.evaluationSnapshot.diagnostics
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        return "Validation finished: \(errors) errors, \(warnings) warnings."
    }

    private func setRulerConfiguration(
        _ ruler: RulerConfiguration,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        applyWorkspace(.setRulerConfiguration(ruler)) { published in
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
            completion(published)
        }
    }

    private func setDisplayUnit(
        _ unit: LengthDisplayUnit,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        applyWorkspace(.setDisplayUnit(unit), completion: completion)
    }

    private func setViewportGridSettings(_ settings: ViewportGridSettings) {
        applyWorkspace(.setViewportGridSettings(settings))
    }

    private func setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool?,
        combScale: Double?
    ) {
        applyWorkspace(
            .setCurveCurvatureDisplay(
                target: target,
                isVisible: isVisible,
                combScale: combScale
            )
        )
    }

    private func setPointDisplay(
        target: SelectionTarget,
        isVisible: Bool?
    ) {
        applyWorkspace(.setPointDisplay(target: target, isVisible: isVisible))
    }

    private func setSurfaceControlPointDisplay(
        target: SelectionReference,
        isVisible: Bool?
    ) {
        applyWorkspace(
            .setSurfaceControlPointDisplay(target: target, isVisible: isVisible)
        )
    }

    private func setSurfaceFrameDisplay(
        query: SurfaceFrameQuery,
        isVisible: Bool?
    ) {
        applyWorkspace(.setSurfaceFrameDisplay(query: query, isVisible: isVisible))
    }

    @discardableResult
    private func setActiveTool(_ tool: ModelingTool) -> ModelingToolActivationResult {
        selectedTool = tool
        // Trim, Split Segment and Insert Knot take the select tool's clicks; another tool ends them.
        if tool != .select {
            curvePickCommand = nil
            cutCurveSession = nil
            filletSession = nil
            endBodyOperationDialogs()
        }
        if !keepsSketchInputState(for: tool) {
            sketchInputState.clearTransientInput()
        }
        return ModelingToolActivationResult(
            tool: tool,
            selectedSceneNodeID: snapshot.selection.primarySceneNodeID
        )
    }

    private func keepsSketchInputState(for tool: ModelingTool) -> Bool {
        switch tool {
        case .sketch, .polygon, .circle, .arc, .spline, .solid:
            return true
        case .select, .sweep, .mesh, .measure, .section, .surface:
            return false
        }
    }

    @discardableResult
    private func adjustPolygonSideCount(by delta: Int) -> Bool {
        do {
            try polygonToolState.adjustSideCount(by: delta)
            return true
        } catch let failure as PolygonToolState.Failure {
            reportToolStatus(failure.message, severity: .warning)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
        return false
    }

    @discardableResult
    private func togglePolygonSizingMode() -> PolygonSizingMode {
        polygonToolState.toggleSizingMode()
        return polygonToolState.sizingMode
    }

    @discardableResult
    private func togglePolygonInclinationMode() -> PolygonInclinationMode {
        polygonToolState.toggleInclinationMode()
        return polygonToolState.inclinationMode
    }

    @discardableResult
    private func togglePolygonCutsFaces() -> Bool {
        polygonToolState.toggleCutsFaces()
        return polygonToolState.cutsFaces
    }

    @discardableResult
    private func toggleSketchAxisConstraint(
        _ axisConstraint: SketchAxisConstraint
    ) -> SketchAxisConstraint? {
        sketchInputState.toggleAxisConstraint(axisConstraint)
        return sketchInputState.axisConstraint
    }

    @discardableResult
    private func focusNextSketchDimensionInput(
        availableFocuses: [SketchDimensionInputFocus] = SketchDimensionInputFocus.allCases
    ) -> SketchDimensionInputFocus? {
        sketchInputState.focusNextDimensionInput(availableFocuses: availableFocuses)
    }

    @discardableResult
    private func setSketchDimensionInputLength(_ lengthMeters: Double?) -> Bool {
        updateSketchInput {
            try $0.setDimensionInputLengthMeters(lengthMeters)
        }
    }

    @discardableResult
    private func setSketchDimensionInputAngle(_ angleRadians: Double?) -> Bool {
        updateSketchInput {
            try $0.setDimensionInputAngleRadians(angleRadians)
        }
    }

    @discardableResult
    private func setSketchDimensionInputWidth(_ widthMeters: Double?) -> Bool {
        updateSketchInput {
            try $0.setDimensionInputWidthMeters(widthMeters)
        }
    }

    @discardableResult
    private func setSketchDimensionInputHeight(_ heightMeters: Double?) -> Bool {
        updateSketchInput {
            try $0.setDimensionInputHeightMeters(heightMeters)
        }
    }

    @discardableResult
    private func updateSketchInput(
        _ update: (inout SketchInputState) throws -> Void
    ) -> Bool {
        do {
            try update(&sketchInputState)
            return true
        } catch let error as SketchDimensionInputValueError {
            reportToolStatus(error.message, severity: .warning)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
        return false
    }

    @discardableResult
    private func addSketchReferenceLineAnchor(at point: Point2D) -> Bool {
        guard point.x.isFinite, point.y.isFinite else {
            reportToolStatus(
                "Sketch reference line requires a finite model coordinate.",
                severity: .warning
            )
            return false
        }
        sketchInputState.addReferenceLineAnchor(
            SketchReferenceLineAnchor(point: point)
        )
        return true
    }

    private func nextSceneNodeName(
        prefix: String,
        in document: DesignDocument
    ) -> String {
        nextUniqueName(
            prefix: prefix,
            existing: Set(
                document.productMetadata.sceneNodes.values.map(\.name)
            )
        )
    }

    private func nextUniqueName(prefix: String, existing: Set<String>) -> String {
        guard existing.contains(prefix) else {
            return prefix
        }
        var suffix = 2
        while existing.contains("\(prefix) \(suffix)") {
            suffix += 1
        }
        return "\(prefix) \(suffix)"
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Browser", selection: $sidebarSection) {
                ForEach(WorkspaceSidebarSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .accessibilityIdentifier("WorkspaceSidebar.segmentedControl")

            if sidebarSection == .scene {
                sceneSidebarList
            } else {
                historySidebarList
            }
        }
        .navigationTitle("Browser")
    }

    private var sceneSidebarList: some View {
        VStack(spacing: 0) {
            Outliner(
                metadata: snapshot.document.document.productMetadata,
                selectedIDs: Set(snapshot.selection.selectedSceneNodeIDs),
                generation: snapshot.documentGeneration,
                canFrameSelection: viewportControlSession.canFitSelected,
                pendingStateIDs: pendingOutlinerStateIDs,
                searchText: $sidebarSearchText,
                onIntent: handleOutlinerIntent
            )
            .frame(maxHeight: .infinity)

            if !filteredComponentDefinitionIDs.isEmpty || hasVisibleAssetRows {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !filteredComponentDefinitionIDs.isEmpty {
                            Text("Shared Definitions")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(filteredComponentDefinitionIDs, id: \.self) { id in
                                componentDefinitionRow(id)
                            }
                        }
                        if hasVisibleAssetRows {
                            DisclosureGroup("Assets") {
                                ForEach(materialAssetRows) { row in
                                    browserAssetRow(row)
                                        .padding(.leading, 8)
                                }
                                ForEach(validationRuleAssetRows) { row in
                                    browserAssetRow(row)
                                        .padding(.leading, 8)
                                }
                                ForEach(exportPresetAssetRows) { row in
                                    browserAssetRow(row)
                                        .padding(.leading, 8)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 180)
            }
        }
        .accessibilityIdentifier("WorkspaceSidebar.sceneList")
    }

    private var historySidebarList: some View {
        List {
            if filteredFeatureHistory.isEmpty {
                Text("No feature history")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("WorkspaceSidebar.historyEmpty")
            } else {
                FeatureHistoryView(
                    orderedFeatures: featureHistoryFeatures,
                    parameters: snapshot.document.document.cadDocument.parameters,
                    displayUnit: snapshot.workspaceState.ruler.displayUnit,
                    visibleFeatureIDs: featureHistoryVisibleIDs,
                    namesByID: featureHistoryNamesByID,
                    isBusy: modelingPreview.isBusy,
                    onSelect: { featureID in
                        if let node = snapshot.document.document.productMetadata.sceneNodes.values.first(where: { $0.reference?.featureID == featureID }) {
                            _ = selectSceneNodes([node.id])
                        }
                    },
                    onEditConstrainedSurface: { beginConstrainedSurfaceEditing($0) },
                    onEditGear: { beginGearEditing($0) },
                    onPreview: { command, title in previewHistoryOperation(command, title: title) }
                )
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $sidebarSearchText, prompt: "Search History")
        .accessibilityIdentifier("WorkspaceSidebar.historyList")
    }

    private var filteredFeatureHistory: [FeatureNode] {
        let graph = snapshot.document.document.cadDocument.designGraph
        let features = featureHistoryFeatures
        guard !normalizedSidebarSearchText.isEmpty else {
            return features
        }
        return features.filter { feature in
            let inputNames = feature.inputs.map { input in
                graph.nodes[input.featureID]?.name ?? input.featureID.description
            }
            return matchesSidebarSearch(
                feature.name ?? "Feature",
                feature.isSuppressed ? "Suppressed" : "Active",
                inputNames.joined(separator: " ")
            )
        }
    }

    private var featureHistoryFeatures: [FeatureNode] {
        let graph = snapshot.document.document.cadDocument.designGraph
        return graph.order.compactMap { graph.nodes[$0] }
    }

    private var featureHistoryVisibleIDs: Set<FeatureID> {
        Set(filteredFeatureHistory.map(\.id))
    }

    private var featureHistoryNamesByID: [FeatureID: String] {
        let graph = snapshot.document.document.cadDocument.designGraph
        return Dictionary(
            uniqueKeysWithValues: graph.order.enumerated().compactMap { index, featureID in
                guard let feature = graph.nodes[featureID] else {
                    return nil
                }
                return (featureID, feature.name ?? "Feature \(index + 1)")
            }
        )
    }

    private var selectedSceneNodeIDsBinding: Binding<Set<SceneNodeID>> {
        Binding(
            get: {
                Set(snapshot.selection.selectedSceneNodeIDs)
            },
            set: { ids in
                let orderedIDs = sceneBrowserRows.map(\.id).filter { ids.contains($0) }
                patternArrayCurvePathPickState.cancel()
                _ = selectSceneNodes(orderedIDs)
                dimensionCommandState.deactivate()
            }
        )
    }

    private var documentTitle: String {
        ProjectTitlePresentation.title(projectName: snapshot.projectName)
    }

    private var surfaceAnalysisOverlaySummary: String {
        var enabled: [String] = []
        if surfaceAnalysisOptions.showsCurvatureCombs {
            enabled.append("Comb")
        }
        if surfaceAnalysisOptions.showsPrincipalDirections {
            enabled.append("Dir")
        }
        if surfaceAnalysisOptions.showsTrimBoundaries {
            enabled.append("Trim")
        }
        if enabled.isEmpty {
            return "Off"
        }
        return enabled.joined(separator: " + ")
    }

    private var constructionPlaneSnapPlane: SketchPlane? {
        guard isConstructionPlaneSnapEnabled else {
            return nil
        }
        if let explicitPlane = workspacePlaneMode.sketchPlane {
            return explicitPlane
        }
        return activeConstructionPlane?.plane
    }

    private var constructionPlaneSnapSummary: String {
        guard isConstructionPlaneSnapEnabled else {
            return "Off"
        }
        if workspacePlaneMode.sketchPlane != nil {
            return workspacePlaneMode.title
        }
        if let activeConstructionPlane = activeConstructionPlane {
            return activeConstructionPlane.name
        }
        return "No Plane"
    }

    private var savedConstructionPlaneSummary: ConstructionPlaneSummaryResult {
        ConstructionPlaneSummaryService().summarize(
            document: snapshot.document.document,
            activePlaneID: snapshot.workspaceState.activeConstructionPlaneID
        )
    }

    private var savedViewBuilder: WorkspaceSavedViewBuilder {
        WorkspaceSavedViewBuilder()
    }

    private var savedViews: [SavedView] {
        savedViewBuilder.sortedSavedViews(in: snapshot.document.document)
    }

    private var selectedConstructionPlaneEntry: ConstructionPlaneSummaryResult.Entry? {
        let selectedPlaneIDs = snapshot.selection.selectedTargets.compactMap { target in
            if case .constructionPlane(let id) = target.component {
                return id
            }
            return nil
        }
        guard selectedPlaneIDs.count == 1,
              let selectedPlaneID = selectedPlaneIDs.first else {
            return nil
        }
        return savedConstructionPlaneSummary.planes.first { $0.id == selectedPlaneID }
    }

    private var selectedConstructionPlaneInspectorState: WorkspaceConstructionPlaneInspectorState? {
        selectedConstructionPlaneEntry.map { entry in
            WorkspaceConstructionPlaneInspectorState(entry: entry)
        }
    }

    private var sceneBrowserRows: [SceneBrowserRow] {
        var rows: [SceneBrowserRow] = []
        let metadata = snapshot.document.document.productMetadata

        func append(_ id: SceneNodeID, depth: Int, parent: SceneNode? = nil) {
            guard let node = metadata.sceneNodes[id] else {
                return
            }
            // A hidden profile sketch nested under its body is the consumed
            // source of a combined primitive (box, cylinder). It stays
            // selectable through the body workflows, so the browser lists the
            // primitive as one object instead of body-plus-sketch clutter.
            let isConsumedProfileSketch = node.reference?.kind == .sketch
                && node.isVisible == false
                && parent?.reference?.kind == .body
            if isConsumedProfileSketch {
                return
            }
            rows.append(SceneBrowserRow(id: id, depth: depth))
            for childID in node.childIDs {
                append(childID, depth: depth + 1, parent: node)
            }
        }

        for rootSceneNodeID in metadata.rootSceneNodeIDs {
            append(rootSceneNodeID, depth: 0)
        }
        return rows
    }

    private var filteredSceneBrowserRows: [SceneBrowserRow] {
        guard !normalizedSidebarSearchText.isEmpty else {
            return sceneBrowserRows
        }

        return sceneBrowserRows.filter { row in
            guard let node = snapshot.document.document.productMetadata.sceneNodes[row.id] else {
                return false
            }
            return matchesSidebarSearch(node.name, sceneNodeKindTitle(for: node.reference))
        }
    }

    private var componentDefinitionIDs: [ComponentDefinitionID] {
        snapshot.document.document.productMetadata.componentDefinitions.values
            .sorted { $0.name < $1.name }
            .map(\.id)
    }

    private var filteredComponentDefinitionIDs: [ComponentDefinitionID] {
        guard !normalizedSidebarSearchText.isEmpty else {
            return componentDefinitionIDs
        }

        return componentDefinitionIDs.filter { id in
            guard let definition = snapshot.document.document.productMetadata.componentDefinitions[id] else {
                return false
            }
            return matchesSidebarSearch(definition.name, "Component Definition")
        }
    }

    private var componentInstanceIDs: [ComponentInstanceID] {
        snapshot.document.document.productMetadata.componentInstances.values
            .sorted { $0.name < $1.name }
            .map(\.id)
    }

    private var filteredComponentInstanceIDs: [ComponentInstanceID] {
        guard !normalizedSidebarSearchText.isEmpty else {
            return componentInstanceIDs
        }

        return componentInstanceIDs.filter { id in
            guard let instance = snapshot.document.document.productMetadata.componentInstances[id] else {
                return false
            }
            return matchesSidebarSearch(instance.name, "Component Instance")
        }
    }

    private var materialAssetRows: [SidebarAssetRow] {
        snapshot.document.document.productMetadata.materialLibrary.materials.values
            .sorted { $0.name < $1.name }
            .filter { matchesSidebarSearch($0.name, "Material") }
            .map {
                SidebarAssetRow(
                    id: $0.id.description,
                    title: $0.name,
                    subtitle: "Material",
                    systemImage: "paintpalette"
                )
            }
    }

    private var validationRuleAssetRows: [SidebarAssetRow] {
        snapshot.document.document.productMetadata.validationRules.values
            .sorted { $0.name < $1.name }
            .filter { matchesSidebarSearch($0.name, $0.category.rawValue, "Validation Rule") }
            .map {
                SidebarAssetRow(
                    id: $0.id.description,
                    title: $0.name,
                    subtitle: "\($0.category.rawValue.capitalized) / \($0.severity.rawValue.capitalized)",
                    systemImage: $0.isEnabled ? "checkmark.seal" : "checkmark.seal.fill"
                )
            }
    }

    private var exportPresetAssetRows: [SidebarAssetRow] {
        snapshot.document.document.productMetadata.exportPresets.values
            .sorted { $0.name < $1.name }
            .filter { matchesSidebarSearch($0.name, $0.format.rawValue, "Export Preset") }
            .map {
                SidebarAssetRow(
                    id: $0.id.description,
                    title: $0.name,
                    subtitle: "\($0.format.rawValue.uppercased()) / \($0.outputUnit.symbol)",
                    systemImage: "square.and.arrow.up"
                )
            }
    }

    private var hasVisibleAssetRows: Bool {
        !materialAssetRows.isEmpty
            || !validationRuleAssetRows.isEmpty
            || !exportPresetAssetRows.isEmpty
    }

    private func handleOutlinerIntent(_ intent: OutlinerIntent) {
        switch intent {
        case .select(let ids):
            patternArrayCurvePathPickState.cancel()
            _ = selectSceneNodes(ids)
            dimensionCommandState.deactivate()

        case .hover(let id, let isHovered):
            if let id {
                setHoveredSceneNode(id, isHovered: isHovered)
            } else {
                setHoveredSceneNode(nil)
            }

        case .rename(let id, let name):
            submitSource(name: "renameOutlinerNode") { current in
                try OutlinerSourceCommandPlanner.rename(
                    id: id,
                    name: name,
                    in: current.document.document.productMetadata
                )
            }

        case .move(let ids, let parentID, let beforeSiblingID, let expectedGeneration):
            submitSource(name: "moveOutlinerNodes") { current in
                guard current.documentGeneration == expectedGeneration else {
                    throw EditorError(
                        code: .documentGenerationMismatch,
                        message: "The scene changed during the drag. Start the move again."
                    )
                }
                return [.moveSceneNodes(ids: ids, parentID: parentID, beforeSiblingID: beforeSiblingID)]
            }

        case .setVisibility(let ids, let isVisible):
            submitOutlinerStateCommands(ids: ids, isVisible: isVisible)

        case .setLock(let ids, let isLocked):
            submitOutlinerStateCommands(ids: ids, isLocked: isLocked)

        case .isolate(let ids):
            submitOutlinerIsolation(ids: ids)

        case .showAll:
            submitOutlinerShowAll()

        case .group(let ids):
            groupSceneNodes(ids)

        case .ungroup(let ids):
            ungroupSceneNodes(ids)

        case .delete(let ids):
            deleteSceneNodes(ids)

        case .duplicate(let ids):
            duplicateSceneNodes(ids)

        case .frameCurrentSelection:
            guard viewportControlSession.canFitSelected else {
                reportToolStatus(
                    "Frame requires visible selected geometry in the mounted viewport.",
                    severity: .warning
                )
                return
            }
            performViewportControl(.fitSelected)
        }
    }

    private func submitOutlinerStateCommands(
        ids: [SceneNodeID],
        isVisible: Bool? = nil,
        isLocked: Bool? = nil
    ) {
        let targets = Set(ids)
        guard pendingOutlinerStateIDs.isDisjoint(with: targets) else { return }
        pendingOutlinerStateIDs.formUnion(targets)
        let task = enqueueWorkspaceOperation {
            try await executeSource(name: "outlinerStateChange") { current in
                try OutlinerSourceCommandPlanner.stateChange(
                    ids: ids,
                    isVisible: isVisible,
                    isLocked: isLocked,
                    in: current.document.document.productMetadata
                )
            }
        }
        Task { @MainActor in
            defer { pendingOutlinerStateIDs.subtract(targets) }
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func submitOutlinerIsolation(ids: [SceneNodeID]) {
        submitSource(name: "isolateOutlinerSelection") { current in
            try OutlinerSourceCommandPlanner.isolate(
                ids: ids,
                in: current.document.document.productMetadata
            )
        }
    }

    private func submitOutlinerShowAll() {
        submitSource(name: "showAllOutlinerNodes") { current in
            try OutlinerSourceCommandPlanner.showAll(in: current.document.document.productMetadata)
        }
    }

    private var normalizedSidebarSearchText: String {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSidebarSearch(_ values: String...) -> Bool {
        let query = normalizedSidebarSearchText
        guard !query.isEmpty else {
            return true
        }
        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The detail column's split. The size it lays out at is the proposal
    /// NavigationSplitView hands down; nothing here measures that size and
    /// hands it back to this subtree as a frame. This is the one place the
    /// inspector column's width is declared, and it declares one width rather
    /// than a range: a range is a drift allowance, because the split applies
    /// the opening width once and afterwards only clamps the division it
    /// redistributes as the window resizes. See `RupaUI/DESIGN.md`.
    private var editorDetailPane: some View {
        HSplitPane {
            canvasColumn
            if isInspectorPresented || modelingDraft != nil
                || historyPreviewTitle != nil || selectedTool == .mesh {
                inspectorDetailPane
            }
        }
        .leadingPaneWidth(minimum: WorkspaceEditorSplitLayout.minimumCanvasWidth)
        .trailingPaneWidth(
            WorkspaceEditorSplitLayout.inspectorWidth,
            minimum: WorkspaceEditorSplitLayout.inspectorWidth,
            maximum: WorkspaceEditorSplitLayout.inspectorWidth
        )
        .dividerDragStrip(width: WorkspaceEditorSplitLayout.dividerDragStripWidth)
    }

    @ViewBuilder
    private var inspectorDetailPane: some View {
        Group {
            if let draft = modelingDraft {
                ModelingOperationView(
                    draft: Binding(get: { modelingDraft ?? draft }, set: { modelingDraft = $0 }),
                    document: snapshot.document.document,
                    isBusy: modelingPreview.isBusy,
                    hasMatchingPreview: modelingPreview.phase == .ready,
                    errorMessage: modelingPreview.errorMessage,
                    onUseSelection: { modelingDraft?.targets = snapshot.selection.selectedTargets },
                    onPreview: previewModelingOperation,
                    onApply: applyModelingOperation,
                    onCancel: cancelModelingOperation
                )
            } else if let title = historyPreviewTitle {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.headline)
                    Text("Review the evaluated result before applying. Dependency-invalid changes leave the document unchanged.")
                    if modelingPreview.isBusy { ProgressView("Evaluating…") }
                    if let message = modelingPreview.errorMessage {
                        Text(message).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("Modeling.historyPreview.error")
                    }
                    HStack {
                        Button("Cancel", action: cancelModelingOperation).keyboardShortcut(.cancelAction)
                            .contentShape(Rectangle())
                        Button("Apply", action: applyModelingOperation)
                            .contentShape(Rectangle())
                            .disabled(modelingPreview.phase != .ready)
                            .keyboardShortcut(.defaultAction)
                    }
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else if selectedTool == .mesh {
                if let draft = meshDraft {
                    VStack(alignment: .leading, spacing: 0) {
                        MeshOperationView(
                            draft: Binding(get: { meshDraft ?? draft }, set: updateMeshDraft),
                            domain: $meshSelectionDomain,
                            isBusy: modelingPreview.isBusy,
                            hasMatchingPreview: modelingPreview.phase == .ready,
                            errorMessage: modelingPreview.errorMessage,
                            onPreview: previewMeshOperation, onApply: applyModelingOperation, onCancel: cancelModelingOperation
                        )
                        if let meshOverlayError {
                            Text(meshOverlayError).foregroundStyle(.red).padding(.horizontal, 16)
                                .accessibilityIdentifier("Modeling.meshOverlay.error")
                        } else if let overlay = meshSelectionOverlay, overlay.isTruncated {
                            Text("Selection outline: \(overlay.visibleBoundarySegmentCount) of \(overlay.sourceBoundarySegmentCount) edges shown. All selected IDs remain active.")
                                .font(.caption).padding(.horizontal, 16)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Mesh Editing").font(.headline)
                        Picker("Select", selection: $meshSelectionDomain) {
                            Text("Vertex").tag(GeometryAttributeDomain.vertex)
                            Text("Edge").tag(GeometryAttributeDomain.edge)
                            Text("Face").tag(GeometryAttributeDomain.face)
                        }.pickerStyle(.segmented)
                        Text("Click an Authored Mesh in the canvas. CAD bodies must first be made editable as Mesh.")
                        Button("Make Selected CAD Editable…") { showsMakeEditableConfirmation = true }
                            .contentShape(Rectangle())
                            .disabled(snapshot.selection.selectedTargets.count != 1 || !selectedPresentationHasExactCADAffordanceContext)
                        if let message = modelingPreview.errorMessage {
                            Text(message).foregroundStyle(.red)
                                .accessibilityIdentifier("Modeling.meshTarget.error")
                        }
                        Button("Cancel", action: cancelModelingOperation)
                            .contentShape(Rectangle())
                        Spacer()
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                inspectorPane
            }
        }
    }

    /// The canvas column: the header bar, then the canvas and the logs pane
    /// below it. The header is a sibling of the canvas rather than an overlay
    /// on it, so it takes no canvas area and punches no input-exclusion hole.
    private var canvasColumn: some View {
        VStack(spacing: 0) {
            workspaceCanvasHeader
            workArea
        }
    }

    private var workArea: some View {
        CollapsibleView(isExpanded: $isPreviewExpanded) {
            WorkspaceCanvasOverlayHost(
                isContextPanelVisible: isViewportContextPanelVisible,
                onHover: handleWorkspaceOverlayHover,
                onChromeGeometryChange: setViewportChromeGeometry
            ) {
                if let payload = modelingPreview.payload {
                    Viewport(
                        document: payload.document,
                        sourceIdentity: .presentation(payload.presentationScene.snapshotID),
                        displayMode: viewportDisplayMode,
                        controlSession: viewportControlSession,
                        presentationScene: payload.presentationScene,
                        presentationSceneNodeIDByOccurrenceID: payload.presentationSceneNodeIDByOccurrenceID,
                        workspaceRenderState: ViewportWorkspaceRenderState(
                            revision: snapshot.workspaceState.revision, ruler: snapshot.workspaceState.ruler
                        ),
                        objectSelectionIndex: ViewportObjectSelectionIndex(document: payload.document, selection: .empty),
                        canvasDragPreviewKind: nil,
                        allowsObjectAffordances: false,
                        selectedPresentationHasExactCADContext: false,
                        onPresentationFailure: reportViewportPresentationFailure
                    )
                    .overlay(alignment: .topLeading) {
                        Label("Preview — not applied", systemImage: "eye")
                            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12)
                    }
                } else {
                    viewportCanvas
                        .overlay(alignment: .top) {
                            if isCommandPaletteOpen {
                                commandPalette.padding(.top, 56)
                            }
                        }
                }
            } toolPalette: {
                floatingToolPalette
            } contextPanel: {
                viewportContextPanelContainer
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                WorkspaceFailureLogView(
                    records: failureLog.records,
                    onClear: { failureLog.clear() }
                )
                PreviewSurface(
                    document: snapshot.document.document,
                    ruler: snapshot.workspaceState.ruler,
                    evaluationStatus: snapshot.evaluationSnapshot.status,
                    evaluatedGeneration: snapshot.evaluationSnapshot.evaluatedGeneration,
                    evaluatedBodyCount: snapshot.evaluationSnapshot.bodyCount,
                    diagnostics: diagnostics
                )
            }
        } header: {
            Label("Logs", systemImage: "list.bullet.rectangle")
                .font(.headline)
        }
        .topPaneHeight(minimum: 420)
        .bottomPaneHeight(minimum: 140)
        .dividerDragStrip(height: 10)
        .collapsibleToggleHelp(expanded: "Hide Logs", collapsed: "Show Logs")
        // Keyboard focus is an input scope; visible canvas affordances are drawn by the viewport.
        .modifier(WorkspaceKeyboardScope(
            isFocused: $isWorkspaceFocused,
            handle: { handleWorkspaceKeyboardInput($0) },
            submit: { commitTypedTransformValues() }
        ))
        .onAppear {
            isWorkspaceFocused = true
        }
        .sheet(isPresented: $isTextDialogPresented) {
            WorkspaceTextDialog(
                text: $textDialogText,
                fontFamily: $textDialogFontFamily,
                sizeMeters: $textDialogSizeMeters,
                unit: snapshot.workspaceState.ruler.displayUnit,
                create: { createTextCurves() },
                cancel: { isTextDialogPresented = false }
            )
        }
        // The Tools menu is presented by the App; the active tool lives here.
        // One focused scene value joins them without moving the tool state out.
        .focusedSceneValue(
            \.workspaceToolCommands,
            WorkspaceToolCommands(
                selectedTool: selectedTool,
                activate: { activateTool($0) }
            )
        )
        // The Edit menu is presented by the App; it offers only what Core would accept.
        .focusedSceneValue(
            \.workspaceEditCommands,
            workspaceEditCommands
        )
        .onChange(of: selectionScope) { _, newScope in
            clearSelectionDragPreview()
            if newScope != .region {
                regionOffsetCommandState.deactivate()
            }
            if newScope != .edge {
                edgeOffsetCommandState.deactivate()
            }
            if newScope != .object && newScope != .face {
                dimensionCommandState.deactivate()
            }
            if newScope != .sketchEntity {
                slideCommandState.deactivate()
            }
            if newScope != .object {
                if transformSession?.topologyTargets.isEmpty != false
                    || newScope != Self.selectionScope(movedBy: transformSession?.topologyKind ?? .edges) {
                    transformSession = nil
                }
                mirrorSession = nil
            }
        }
        // A transform follows the objects it moves, and ends when the selection is something else.
        .onChange(of: snapshot.documentGeneration) { _, _ in
            refreshTransformFrame()
        }
        // Move Edges, Faces or Vertices ends when other things are selected; a move empties the
        // selection until the moved targets are selected again.
        .onChange(of: snapshot.selection.selectedTargets) { _, targets in
            if let transformSession, !transformSession.topologyTargets.isEmpty, !targets.isEmpty,
               Set(targets) != Set(transformSession.topologyTargets) {
                self.transformSession = nil
            }
            // A G1 tension typed for a Bridge Curve belongs to that selection: once another
            // selection replaces it, the unapplied value is dropped, so reselecting the bridge
            // shows its actual tension.
            if let input = bridgeTensionInput, selectedBridgeCurve?.sourceID != input.sourceID {
                bridgeTensionInput = nil
            }
        }
        .onChange(of: snapshot.selection.wholeSceneNodeIDs, initial: true) { _, _ in
            refreshSelectionMass()
        }
        .onChange(of: snapshot.documentGeneration) { _, _ in
            refreshSelectionMass()
        }
        // Boolean's tools are shown selected alone while they move, its bodies again after.
        .onChange(of: transformSession == nil) { _, ended in
            if ended, let booleanSession {
                selectTargets(booleanSession.operands.map { SelectionTarget(sceneNodeID: $0) })
            }
        }
        .onChange(of: snapshot.selection.wholeSceneNodeIDs) { _, ids in
            if let id = selectedSharedDefinitionID {
                do {
                    let shared = try sharedDefinitionSelection(id).get()
                    if Set(shared.placementNodeIDs) != Set(ids) { selectedSharedDefinitionID = nil }
                } catch {
                    selectedSharedDefinitionID = nil
                    reportToolStatus(error.localizedDescription, severity: .warning)
                }
            }
            if let transformSession, transformSession.topologyTargets.isEmpty, transformSession.sceneNodeIDs != ids {
                self.transformSession = nil
            }
            if let mirrorSession, mirrorSession.sceneNodeIDs != ids {
                self.mirrorSession = nil
            }
        }
    }

    private var viewportCanvas: some View {
        // The Section Analysis command's section replaces a selected construction plane's.
        let commandSection: SectionAnalysisResult? = if case .success(let analysis) = commandSectionAnalysisResult {
            analysis
        } else {
            nil
        }
        let sectionAnalysis = commandSection ?? selectedSectionAnalysisSummary
        let sectionClippingPlan = commandSection.map {
            SectionAnalysisClippingPlan(result: $0, retaining: WorkspaceSectionAnalysisSession.retainedSide)
        } ?? selectedSectionClippingPlan(for: sectionAnalysis)
        // Slide's Control toggle draws the project as it was when Slide started.
        let slideComparisonShown = slideComparison.displayed(snapshot)
        return Viewport(
            document: slideComparisonShown.document.document,
            sourceIdentity: .document(id: slideComparisonShown.document.document.id, generation: slideComparisonShown.documentGeneration),
            displayMode: viewportDisplayMode,
            controlSession: viewportControlSession,
            presentationScene: slideComparisonShown.viewport,
            presentationSceneNodeIDByOccurrenceID: slideComparisonShown.sceneNodeIDByOccurrenceID,
            workspaceRenderState: ViewportWorkspaceRenderState(
                revision: snapshot.workspaceState.revision,
                ruler: snapshot.workspaceState.ruler,
                sceneOverlayState: ViewportSceneOverlayState(
                    curveCurvatureDisplays: snapshot.workspaceState.curveCurvatureDisplays,
                    pointDisplays: snapshot.workspaceState.pointDisplays,
                    surfaceControlPointDisplays: snapshot.workspaceState.surfaceControlPointDisplays,
                    surfaceFrameDisplays: snapshot.workspaceState.surfaceFrameDisplays
                )
            ),
            currentEvaluation: slideComparisonShown.cadInteraction,
            objectRegistry: objectRegistry,
            renderInvalidation: slideComparisonShown.evaluationSnapshot.renderInvalidation,
            selection: displaySelection,
            objectSelectionIndex: viewportObjectSelectionIndex,
            selectionDragPreviewTargets: selectionDragPreviewTargets,
            presentationPreviewSceneNodeIDs: selectionDragPreviewSceneNodeIDs,
            patternArrayCurvePathReplacementPreviewRequest: patternArrayCurvePathReplacementPreviewRequest,
            surfaceAnalysis: selectedSurfaceAnalysisSummary,
            surfaceAnalysisOptions: surfaceAnalysisOptions,
            surfaceContinuity: selectedSurfaceContinuitySummary,
            sectionAnalysis: sectionAnalysis,
            sectionClippingPlan: sectionClippingPlan,
            sectionAnalysisHandle: sectionAnalysisSession.flatMap { placing in
                commandSection.map { section in
                    // The distance moves along the plane's source normal, before Flip.
                    ViewportSectionAnalysisDistanceHandle(
                        distanceMeters: placing.distanceMeters,
                        sourceNormal: placing.flipsNormal
                            ? Vector3D(x: -section.plane.normal.x, y: -section.plane.normal.y, z: -section.plane.normal.z)
                            : section.plane.normal
                    )
                }
            },
            snapResolutionOptions: activeSnapResolutionOptions(),
            canvasDragPreviewKind: canvasDragPreviewKind,
            canvasPlacementPreviewKind: canvasPlacementPreviewKind,
            canvasDragAxisConstraint: activeCanvasDragAxisConstraint,
            canvasDragSketchPlaneOverride: workspacePlaneMode.sketchPlane,
            projectionRequest: viewportProjectionRequest,
            cameraFrameRequest: viewportCameraFrameRequest,
            selectionHitPolicy: viewportPointerOwner.hitPolicy,
            bottomChromeReservedHeight: viewportBottomChromeReservedHeight,
            canvasOverlayExclusions: viewportChromeGeometry.exclusions,
            gridVisualSpacingMode: snapshot.workspaceState.viewportGridSettings.visualSpacingMode,
            cameraResetSignal: viewportCameraResetSignal,
            hoverClearSignal: viewportHoverClearSignal,
            showsConstructionPlaneHover: showsConstructionPlaneHover,
            measurementToolActive: selectedTool == .measure,
            pointPickActive: pointPickRequest != nil || placeSession != nil
                || transformSession?.pendingPoint != nil || mirrorSession != nil
                || arraySession?.pickingSlot != nil,
            showsAutomaticMeasurement: showsAutomaticBoundsRulers,
            showsBoundsReadout: showsBoundsReadout,
            measurementConstructionPlane: workspacePlaneMode.sketchPlane ?? activeConstructionPlane?.plane,
            measurementSeed: measurementSeed,
            allowsSelectionRectangle: allowsSelectionRectangle,
            allowsObjectAffordances: allowsObjectAffordances,
            meshSelectionDomain: meshSelectionDomain,
            onMeshElementPick: meshElementPickHandler,
            meshSelectionOverlay: meshSelectionOverlay,
            slotWidthMeters: slotProfileWidthMeters,
            sketchVertexOffsetDistanceMeters: sketchVertexOffsetDistanceMeters,
            edgeOffsetDistanceMeters: edgeOffsetDistanceMeters,
            sketchCornerTreatmentHandle: viewportSketchCornerTreatmentHandle,
            sketchJoinEndpointFeedback: viewportSketchJoinEndpointFeedback,
            transformGizmo: transformSession?.gizmo(
                distanceStepMeters: WorkspaceInteractionScaleDefaults(ruler: snapshot.workspaceState.ruler)
                    .operationStepMeters
            ),
            presentationCADInteractionSceneNodeIDs: exactPresentationCADSceneNodeIDs,
            selectedPresentationHasExactCADContext: selectedPresentationHasExactCADAffordanceContext,
            onPresentationOccurrencePick: presentationOccurrencePickHandler,
            onPresentationOccurrenceHover: presentationOccurrenceHoverHandler,
            onPick: handleViewportPick,
            onCanvasDrag: handleViewportDrag,
            onShiftScroll: viewportShiftScrollHandler,
            onReferenceLineAnchor: viewportReferenceLineAnchorHandler,
            onSelectionDrag: handleViewportSelectionDrag,
            onSelectionDragPreview: viewportSelectionDragPreviewHandler,
            onBodyPlacementCommit: viewportBodyPlacementCommitHandler,
            onBodyResizeCommit: viewportBodyResizeCommitHandler,
            onVertexDrag: viewportVertexDragHandler,
            onFaceDrag: viewportFaceDragHandler,
            onEdgeChamferDrag: viewportEdgeChamferDragHandler,
            onEdgeFilletDrag: viewportEdgeFilletDragHandler,
            onBoundarySurface: viewportBoundarySurfaceHandler,
            onRegionOffsetDrag: viewportRegionOffsetDragHandler,
            onEdgeOffsetDrag: viewportEdgeOffsetDragHandler,
            onSlotWidthDrag: viewportSlotWidthDragHandler,
            onSketchVertexOffsetDrag: viewportSketchVertexOffsetDragHandler,
            onSketchCornerTreatmentDrag: filletSession == nil ? nil : { target in
                handleViewportSketchCornerTreatmentDrag(target)
            },
            onPatternArrayLinearAxisDrag: viewportPatternArrayLinearAxisDragHandler,
            onSectionAnalysisDistanceDrag: sectionAnalysisSession == nil ? nil : { target in
                sectionAnalysisSession?.distanceMeters = target.distanceMeters
            },
            onIndependentCopyExtrudeDistanceDrag: viewportIndependentCopyExtrudeDistanceDragHandler,
            onIndependentCopyBodyDimensionDrag: viewportIndependentCopyBodyDimensionDragHandler,
            onPatternArrayRadialAngleDrag: viewportPatternArrayRadialAngleDragHandler,
            onPatternArrayCopyCountDrag: viewportPatternArrayCopyCountDragHandler,
            onPatternArrayCurveExtentDrag: viewportPatternArrayCurveExtentDragHandler,
            onPatternArrayCurvePathPointDrag: viewportPatternArrayCurvePathPointDragHandler,
            onPatternArrayOutputModeChange: viewportPatternArrayOutputModeChangeHandler,
            onSketchCurveHandleDrag: viewportSketchCurveHandleDragHandler,
            onSketchDimensionDrag: viewportSketchDimensionDragHandler,
            onSketchPointHandleDrag: viewportSketchPointHandleDragHandler,
            onBridgeCurveEndpointDrag: viewportBridgeCurveEndpointDragHandler,
            onSplineControlPointDrag: viewportSplineControlPointDragHandler,
            onSplineControlPointSlideDrag: viewportSplineControlPointSlideDragHandler,
            onPolySplineSurfaceVertexDrag: viewportPolySplineSurfaceVertexDragHandler,
            onSurfaceControlPointDrag: viewportSurfaceControlPointDragHandler,
            onSurfaceTrimEndpointDrag: viewportSurfaceTrimEndpointDragHandler,
            onSurfaceTrimControlPointDrag: viewportSurfaceTrimControlPointDragHandler,
            onPolySplineSurfaceVertexSlideDrag: viewportPolySplineSurfaceVertexSlideDragHandler,
            onSurfaceControlPointSlideDrag: viewportSurfaceControlPointSlideDragHandler,
            onSurfaceFrameDrag: viewportSurfaceFrameDragHandler,
            onConstructionPlaneHandleDrag: viewportConstructionPlaneHandleDragHandler,
            onCommandConfirm: viewportCommandConfirmHandler,
            onDeleteSelection: handleDeleteSelection,
            onDoubleClick: viewportDoubleClickHandler,
            onHover: viewportHoverHandler,
            onSnapCandidateKindChange: { kind in
                snapOverrideState.updateHoveredCandidateKind(kind)
            },
            onProjectionBasisChange: { basis in
                viewportProjectionBasis = basis
            },
            onCameraFrameChange: { frame in
                viewportCameraState.update(frame)
            },
            onCameraFrameRequestResult: { id, result in
                guard viewportCameraFrameRequest?.id == id else { return }
                viewportCameraFrameRequest = nil
                switch result {
                case .success:
                    reportToolStatus("Saved view applied.")
                case .failure(let error):
                    reportToolStatus("Saved view camera could not be applied: \(error.localizedDescription)", severity: .warning)
                }
            },
            onProjectedGridStepChange: { minorStep in
                viewportProjectedGridMinorStep = minorStep
            },
            onMeasurementStateChange: { state in
                // A dimension confirmed by click or right-click is added to Measurements at once.
                let wasSaved = viewportMeasurementState.canSave
                viewportMeasurementState = state
                if state.canSave, !wasSaved {
                    saveMeasurement(state)
                }
            },
            onPointPick: handleViewportPointPick,
            onNativeGestureRefusal: { error in
                // The viewport decides which native gesture refusals are
                // reportable and filters frame readiness before this point, so
                // the workspace records what it is handed and shows the same
                // text once, without recording it a second time.
                reportToolStatus(
                    recordFailure(error, operation: "Viewport.nativeGesture"),
                    severity: .warning,
                    recordsFailure: false
                )
            },
            onPresentationFailure: reportViewportPresentationFailure,
            onAffordanceUnavailable: { reason in reportToolStatus(reason, severity: .warning) }
        )
        .onChange(of: slideCommandState.isActive) { _, isActive in
            slideComparison.slideActivityChanged(isActive: isActive, current: snapshot)
        }
        .onModifierKeysChanged(mask: .control) { _, keys in
            let wasComparing = slideComparison.isComparing
            slideComparison.controlChanged(isHeld: keys.contains(.control))
            guard slideComparison.isComparing != wasComparing else { return }
            reportToolStatus(slideComparison.isComparing
                ? "Slide: before sliding; release Control for the result."
                : "Slide: the result.")
        }
    }

    private func setViewportChromeGeometry(_ geometry: WorkspaceCanvasChromeGeometry) {
        guard viewportChromeGeometry != geometry else {
            return
        }
        viewportChromeGeometry = geometry
    }

    private var inspectorPane: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $inspectorTab) {
                ForEach(WorkspaceInspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, WorkspaceInspectorLayout.panelHorizontalInset)
            .padding(.vertical, 8)
            .accessibilityIdentifier("WorkspaceInspector.tabs")

            Divider()

            Group {
                switch inspectorTab {
                case .properties:
                    inspectorContent
                case .definitions:
                    definitionsInspectorContent
                }
            }
            .id(snapshot.selection.selectedTargets)
            .id(snapshot.selection.selectedReferences)
        }
            .environment(\.inspectorInputSequencer, operationSequencer)
            .environment(\.inspectorInputDidSubmit, { isWorkspaceFocused = true })
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .accessibilityIdentifier("InspectorPane")
    }

    private var definitionsInspectorContent: some View {
        ScrollView(.vertical) {
            WorkspaceParameterInspectorView(
                state: workspaceParameterInspectorState,
                onRename: renameDocumentParameter,
                onUpsert: upsertParameterExpression,
                onDelete: deleteDocumentParameter
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, WorkspaceInspectorLayout.panelHorizontalInset)
            .padding(.vertical, WorkspaceInspectorLayout.panelVerticalInset)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("DefinitionsInspector")
    }

    private var viewportHoverHandler: ((ViewportHit?) -> Void)? {
        guard selectedTool == .select else {
            return nil
        }
        return { hit in
            handleViewportHover(hit)
        }
    }

    private var patternArrayCurvePathReplacementPreviewRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest? {
        guard let sourceID = patternArrayCurvePathPickState.sourceID,
              let candidate = patternArrayCurvePathPreviewCandidate else {
            return nil
        }
        return ViewportPatternArrayCurvePathReplacementPreviewRequest(
            sourceID: sourceID,
            path: candidate.path,
            title: candidate.title
        )
    }

    /// The selected bodies' move, rotate and scale gizmo; a running command that takes clicks has
    /// none, so a click on a selected body reaches the command.
    private var viewportBodyPlacementCommitHandler: (([ViewportBodyPlacementDragTarget]) async throws -> ViewportSourceIdentity)? {
        guard viewportPointerOwner.allows(.objectPlacement) else {
            return nil
        }
        return { target in
            try await handleViewportBodyPlacementCommit(target)
        }
    }

    private var viewportVertexDragHandler: ((ViewportVertexDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportVertexDrag(target)
        }
    }

    private var viewportFaceDragHandler: ((ViewportFaceDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.faceOffset),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportFaceDrag(target)
        }
    }

    private var viewportEdgeChamferDragHandler: ((ViewportEdgeChamferDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.edgeTreatment),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportEdgeChamferDrag(target)
        }
    }

    private var viewportEdgeFilletDragHandler: ((ViewportEdgeFilletDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.edgeTreatment),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportEdgeFilletDrag(target)
        }
    }

    private var viewportBoundarySurfaceHandler: ((SelectionTarget) -> Void)? {
        guard viewportPointerOwner.allows(.boundarySurface),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            if var draft = modelingDraft,
               draft.isSurfaceCreation, draft.kind == .bridge,
               draft.targets.count == 1 {
                if draft.targets[0] != target {
                    draft.targets.append(target)
                    modelingDraft = draft
                }
            } else {
                beginSurfaceModelingOperation()
                modelingDraft?.selectSurfaceOperation(.bridge)
                modelingDraft?.targets = [target]
            }
        }
    }

    private var viewportRegionOffsetDragHandler: ((ViewportRegionOffsetDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.regionOffset),
              regionOffsetCommandState.isActive,
              selectedRegionTargets.isEmpty == false else {
            return nil
        }
        return { target in
            handleViewportRegionOffsetDrag(target)
        }
    }

    private var viewportEdgeOffsetDragHandler: ((ViewportEdgeOffsetDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.edgeOffset),
              selectedPresentationHasExactCADAffordanceContext,
              edgeOffsetCommandState.isActive,
              selectedEdgeOffsetSupportResolution.isSupported else {
            return nil
        }
        return { target in
            handleViewportEdgeOffsetDrag(target)
        }
    }

    private var viewportSelectionDragPreviewHandler: ((ViewportSelectionDragTarget) -> Void)? {
        guard selectedTool == .select else {
            return nil
        }
        return { target in
            handleViewportSelectionDragPreview(target)
        }
    }

    private var viewportSlotWidthDragHandler: ((ViewportSlotWidthDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.slotWidth),
              slotProfileCommandState.isActive,
              selectedSlotSourceCurveTarget != nil else {
            return nil
        }
        return { target in
            handleViewportSlotWidthDrag(target)
        }
    }

    private var viewportSketchVertexOffsetDragHandler: ((ViewportSketchVertexOffsetDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing),
              selectedSketchVertexOffsetTarget != nil else {
            return nil
        }
        return { target in
            handleViewportSketchVertexOffsetDrag(target)
        }
    }

    private var viewportPatternArrayLinearAxisDragHandler: ((ViewportPatternArrayLinearAxisDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayLinearAxisDrag(target)
        }
    }

    private var viewportIndependentCopyExtrudeDistanceDragHandler: ((ViewportIndependentCopyExtrudeDistanceDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyExtrudeDistanceDrag(target)
        }
    }

    private var viewportIndependentCopyBodyDimensionDragHandler: ((ViewportIndependentCopyBodyDimensionDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyBodyDimensionDrag(target)
        }
    }

    private var viewportPatternArrayRadialAngleDragHandler: ((ViewportPatternArrayRadialAngleDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayRadialAngleDrag(target)
        }
    }

    private var viewportPatternArrayCopyCountDragHandler: ((ViewportPatternArrayCopyCountDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCopyCountDrag(target)
        }
    }

    private var viewportPatternArrayCurveExtentDragHandler: ((ViewportPatternArrayCurveExtentDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            guard viewportPointerOwner.allows(.featureParameters),
                  let state = patternArrayInspectorState(for: selectedSceneNodes),
                  state.sourceID == target.sourceID else {
                return
            }
            let service = patternArrayEditingService(sourceID: target.sourceID)
            switch target.extent {
            case .distance(let meters):
                service.setCurveExtentDistance(meters)
            case .ratio(let ratio):
                service.setCurveExtentRatio(ratio)
            }
        }
    }

    private var viewportPatternArrayCurvePathPointDragHandler: ((ViewportPatternArrayCurvePathPointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCurvePathPointDrag(target)
        }
    }

    private var viewportPatternArrayOutputModeChangeHandler: ((ViewportPatternArrayOutputModeTarget) -> Void)? {
        guard viewportPointerOwner.allows(.featureParameters),
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayOutputModeChange(target)
        }
    }

    private var viewportSketchCurveHandleDragHandler: ((ViewportSketchCurveHandleDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return nil
        }
        return { target in
            handleViewportSketchCurveHandleDrag(target)
        }
    }

    private var viewportSketchDimensionDragHandler: ((ViewportSketchDimensionDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return nil
        }
        return { target in
            handleViewportSketchDimensionDrag(target)
        }
    }

    private var viewportSketchPointHandleDragHandler: ((ViewportSketchPointHandleDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return nil
        }
        return { target in
            handleViewportSketchPointHandleDrag(target)
        }
    }

    private var viewportSplineControlPointDragHandler: ((ViewportSplineControlPointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return nil
        }
        return { target in
            handleViewportSplineControlPointDrag(target)
        }
    }

    private var viewportBridgeCurveEndpointDragHandler: ((ViewportBridgeCurveEndpointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return nil
        }
        return { target in
            handleViewportBridgeCurveEndpointDrag(target)
        }
    }

    private var viewportSplineControlPointSlideDragHandler: ((ViewportSplineControlPointSlideDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.sketchEntityEditing),
              slideCommandState.isCurveControlVerticesActive,
              !slideComparison.isComparing else {
            return nil
        }
        return { target in
            handleViewportSplineControlPointSlideDrag(target)
        }
    }

    private var viewportCommandConfirmHandler: (() -> Void)? {
        guard hasActiveWorkspaceCommand else {
            return nil
        }
        return {
            _ = confirmActiveWorkspaceCommand()
        }
    }

    private var viewportPolySplineSurfaceVertexDragHandler: ((ViewportPolySplineSurfaceVertexDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexDrag(target)
        }
    }

    private var viewportSurfaceControlPointDragHandler: ((ViewportSurfaceControlPointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointDrag(target)
        }
    }

    private var viewportSurfaceTrimEndpointDragHandler: ((ViewportSurfaceTrimEndpointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimEndpointDrag(target)
        }
    }

    private var viewportSurfaceTrimControlPointDragHandler: ((ViewportSurfaceTrimControlPointDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimControlPointDrag(target)
        }
    }

    private var viewportPolySplineSurfaceVertexSlideDragHandler: ((ViewportPolySplineSurfaceVertexSlideDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive,
              !slideComparison.isComparing else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexSlideDrag(target)
        }
    }

    private var viewportSurfaceControlPointSlideDragHandler: ((ViewportSurfaceControlPointSlideDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive,
              !slideComparison.isComparing else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointSlideDrag(target)
        }
    }

    private var viewportSurfaceFrameDragHandler: ((ViewportSurfaceFrameDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceFrameDrag(target)
        }
    }

    private var viewportConstructionPlaneHandleDragHandler: ((ViewportConstructionPlaneDragTarget) -> Void)? {
        guard viewportPointerOwner.allows(.constructionPlane),
              selectedConstructionPlaneEntry != nil else {
            return nil
        }
        return { target in
            handleViewportConstructionPlaneHandleDrag(target)
        }
    }

    private var allowsSelectionRectangle: Bool {
        selectedTool == .select && selectionScope.allowsSelectionRectangle
    }

    private var hasActiveWorkspaceCommand: Bool {
        cutCurveSession != nil
            || booleanSession != nil || bodyCutSession != nil
            || filletSession != nil
            || rebuildSession != nil
            || deformSession != nil
            || projectSession != nil
            || bridgeEdgeSession != nil
            || regionOffsetCommandState.isActive
            || edgeOffsetCommandState.isActive
            || slotProfileCommandState.isActive
            || slideCommandState.isActive
            || sectionAnalysisSession != nil
    }

    @discardableResult
    private func confirmActiveWorkspaceCommand() -> Bool {
        if cutCurveSession != nil {
            confirmCutCurve()
            return true
        }
        if booleanSession != nil {
            confirmBoolean()
            return true
        }
        if bodyCutSession != nil {
            confirmBodyCut()
            return true
        }
        if filletSession != nil {
            confirmFillet()
            return true
        }
        if rebuildSession != nil {
            confirmRebuild()
            return true
        }
        if deformSession != nil {
            confirmDeform()
            return true
        }
        if projectSession != nil {
            confirmProject()
            return true
        }
        if bridgeEdgeSession != nil {
            confirmBridgeEdge()
            return true
        }
        if slideCommandState.isCurveControlVerticesActive {
            slideCommandState.deactivate()
            reportToolStatus("Slide Curve CV complete.")
            return true
        }
        if slideCommandState.isSurfaceControlVerticesActive {
            slideCommandState.deactivate()
            reportToolStatus("Slide Surface CV complete.")
            return true
        }
        // Return and right-click create the running O command's result at its distance; the
        // command ends once the result exists and stays for another try when it is refused.
        if regionOffsetCommandState.isActive {
            let targets = selectedRegionTargets
            guard !targets.isEmpty else {
                regionOffsetCommandState.deactivate()
                return true
            }
            offsetSelectedRegions(
                targets,
                by: regionOffsetDistanceMeters,
                gapFill: regionOffsetGapFill,
                isSymmetric: regionOffsetCommandState.usesLockedDistance,
                combinesRegions: regionOffsetCommandState.usesCombinedRegions
            )
            return true
        }
        if edgeOffsetCommandState.isActive {
            let targets = selectedEdgeTargets
            guard !targets.isEmpty else {
                edgeOffsetCommandState.deactivate()
                return true
            }
            offsetSelectedEdges(
                targets,
                by: edgeOffsetDistanceMeters,
                gapFill: edgeOffsetGapFill,
                isSymmetric: edgeOffsetCommandState.usesLockedDistance
            )
            return true
        }
        if slotProfileCommandState.isVertexOffsetActive {
            if let entity = sketchCommandTargetResolver.entity(from: selectedSketchEntityResult),
               selectedSketchVertexOffsetHandle(entity) != nil {
                createCommandedVertexOffset(entity)
            } else {
                slotProfileCommandState.deactivate()
            }
            return true
        }
        if slotProfileCommandState.isActive {
            if let target = selectedCurveOffsetTarget {
                createCommandedCurveOffset(target)
            } else {
                slotProfileCommandState.deactivate()
            }
            return true
        }
        if sectionAnalysisSession != nil {
            confirmSectionAnalysis()
            return true
        }
        return false
    }

    /// The selected object's move and resize handles; a running command that takes clicks has
    /// none, so a click on the object reaches the command and a drag cannot move it midway.
    private var allowsObjectAffordances: Bool {
        viewportPointerOwner.allows(.objectPlacement)
            && selectedPresentationHasExactCADAffordanceContext
    }

    /// The selected box body's resize handles; they stand down with the other object handles
    /// while a command takes clicks, even when a Move inside it keeps the gizmo live.
    private var viewportBodyResizeCommitHandler: ((ViewportBodyResizeDragTarget) async throws -> ViewportSourceIdentity)? {
        guard viewportPointerOwner.allows(.objectHandles) else {
            return nil
        }
        return { target in
            try await handleViewportBodyResizeCommit(target)
        }
    }

    private var showsAutomaticBoundsRulers: Bool {
        WorkspaceMeasurementPresentationGate.showsBoundsRulers(
            selectedTool: selectedTool,
            hasOwningInteraction: hasBoundsPresentationOwningInteraction
        )
    }

    private var showsBoundsReadout: Bool {
        WorkspaceMeasurementPresentationGate.showsBoundsReadout(
            selectedTool: selectedTool,
            selectionScope: selectionScope,
            hasOwningInteraction: hasBoundsPresentationOwningInteraction
        )
    }

    /// Interactions that own the viewport while the bounds presentations would
    /// otherwise describe a selection the user is no longer editing.
    private var hasBoundsPresentationOwningInteraction: Bool {
        dimensionCommandState.isActive
            || modelingDraft != nil
            || meshDraft != nil
            || hasActiveWorkspaceCommand
            || modelingPreview.phase != .idle
            || historyPreviewTitle != nil
            || viewAlignedConstructionPlaneRequest != nil
    }

    private static func makeExactPresentationCADSceneNodeIDs(
        snapshot: ProjectViewSnapshot
    ) -> Set<SceneNodeID> {
        let resolver = MeshSourcePresentationCADAffordanceResolver()
        // One index of the evaluation's bodies serves every presented item.
        let evaluatedBodies = snapshot.cadInteraction.map { MeshSourcePresentationEvaluatedBodies($0.evaluatedDocument) }
        var availableCounts: [SceneNodeID: Int] = [:]
        var unavailableSceneNodeIDs: Set<SceneNodeID> = []
        for item in snapshot.viewport.items {
            guard let sceneNodeID = snapshot.sceneNodeID(for: item.occurrenceID) else {
                continue
            }
            guard case .available = resolver.resolve(
                      item: item,
                      sceneNodeID: sceneNodeID,
                      document: snapshot.document.document,
                      generation: snapshot.documentGeneration,
                      cadInteraction: snapshot.cadInteraction,
                      evaluatedBodies: evaluatedBodies
                  ) else {
                unavailableSceneNodeIDs.insert(sceneNodeID)
                continue
            }
            availableCounts[sceneNodeID, default: 0] += 1
        }
        return Set(availableCounts.compactMap { sceneNodeID, count in
            count == 1 && unavailableSceneNodeIDs.contains(sceneNodeID) == false
                ? sceneNodeID
                : nil
        })
    }

    private var presentationOccurrencePickHandler: (
        (SceneOccurrenceID, ViewportSelectionIntent) -> Void
    )? {
        if viewportPointerOwner.allows(.objectSelection) {
            return handlePresentationOccurrencePick
        }
        switch selectedTool {
        case .mesh:
            return { occurrenceID, _ in
                routeCanvasMesh(snapshot.sceneNodeID(for: occurrenceID))
            }
        default:
            return nil
        }
    }

    private var presentationOccurrenceHoverHandler: ((SceneOccurrenceID?) -> Void)? {
        guard viewportPointerOwner.allows(.objectSelection) else {
            return nil
        }
        return handlePresentationOccurrenceHover
    }

    private func handlePresentationOccurrencePick(
        _ occurrenceID: SceneOccurrenceID,
        intent: ViewportSelectionIntent
    ) {
        guard let sceneNodeID = snapshot.sceneNodeID(for: occurrenceID) else {
            reportToolStatus(
                "Presentation occurrence has no scene-node navigation target.",
                severity: .warning
            )
            return
        }
        applyViewportSelection(
            targets: [SelectionTarget(sceneNodeID: sceneNodeID)],
            intent: intent
        )
    }

    private func handlePresentationOccurrenceHover(_ occurrenceID: SceneOccurrenceID?) {
        guard let occurrenceID,
              let sceneNodeID = snapshot.sceneNodeID(for: occurrenceID) else {
            setHoveredTarget(nil)
            return
        }
        setHoveredTarget(SelectionTarget(sceneNodeID: sceneNodeID))
    }

    private var canvasDragPreviewKind: ViewportCanvasDragPreviewKind? {
        switch selectedTool {
        case .solid where solidShape != .box:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        case .sketch, .solid:
            .rectangle(
                widthMeters: activeSketchWidthInputMeters,
                heightMeters: activeSketchHeightInputMeters
            )
        case .polygon:
            .polygon(
                polygonToolState,
                radiusMeters: activeSketchLengthInputMeters,
                rotationAngleRadians: activeSketchAngleInputRadians
            )
        case .arc:
            .arc(
                radiusMeters: activeSketchLengthInputMeters,
                spanAngleRadians: activeSketchAngleInputRadians
            )
        case .spline:
            .spline
        case .circle:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        default:
            nil
        }
    }

    private var canvasPlacementPreviewKind: ViewportCanvasPlacementPreviewKind? {
        switch selectedTool {
        case .solid where solidShape != .box:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        case .sketch:
            .rectangle(
                widthMeters: activeSketchWidthInputMeters,
                heightMeters: activeSketchHeightInputMeters,
                fallback: .workspaceDefault
            )
        case .solid:
            .rectangle(
                widthMeters: activeSketchWidthInputMeters,
                heightMeters: activeSketchHeightInputMeters,
                fallback: .visibleCell
            )
        case .polygon:
            .polygon(
                polygonToolState,
                radiusMeters: activeSketchLengthInputMeters,
                rotationAngleRadians: activeSketchAngleInputRadians
            )
        case .arc:
            .arc(
                radiusMeters: activeSketchLengthInputMeters,
                spanAngleRadians: activeSketchAngleInputRadians
            )
        case .spline:
            .spline
        case .circle:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        case .select, .sweep, .mesh, .measure, .section, .surface:
            nil
        }
    }

    private var activeCanvasDragAxisConstraint: SketchAxisConstraint? {
        guard usesSketchAxisConstraint else {
            return nil
        }
        return sketchInputState.axisConstraint
    }

    private var activeSketchAxisTitle: String {
        sketchInputState.axisConstraint?.statusTitle ?? "Free"
    }

    private var activeSketchDimensionInputTitle: String {
        guard let focus = sketchInputState.dimensionInputFocus else {
            return "Off"
        }
        switch focus {
        case .length:
            guard let lengthMeters = sketchInputState.dimensionInputLengthMeters else {
                return focus.statusTitle
            }
            let length = WorkspaceInspectorNumberText.lengthString(
                fromMeters: lengthMeters,
                unit: snapshot.workspaceState.displayUnit
            )
            return "\(focus.statusTitle) \(length)"
        case .angle:
            guard let angleRadians = sketchInputState.dimensionInputAngleRadians else {
                return focus.statusTitle
            }
            let degrees = (angleRadians * 180.0 / Double.pi)
                .formatted(.number.precision(.fractionLength(0...2)))
            return "\(focus.statusTitle) \(degrees) deg"
        case .width:
            guard let widthMeters = sketchInputState.dimensionInputWidthMeters else {
                return focus.statusTitle
            }
            let width = WorkspaceInspectorNumberText.lengthString(
                fromMeters: widthMeters,
                unit: snapshot.workspaceState.displayUnit
            )
            return "\(focus.statusTitle) \(width)"
        case .height:
            guard let heightMeters = sketchInputState.dimensionInputHeightMeters else {
                return focus.statusTitle
            }
            let height = WorkspaceInspectorNumberText.lengthString(
                fromMeters: heightMeters,
                unit: snapshot.workspaceState.displayUnit
            )
            return "\(focus.statusTitle) \(height)"
        }
    }

    private var activeSketchLengthInputMeters: Double? {
        guard sketchInputState.dimensionInputFocus == .length,
              let lengthMeters = sketchInputState.dimensionInputLengthMeters,
              lengthMeters.isFinite,
              lengthMeters > 0.0 else {
            return nil
        }
        return lengthMeters
    }

    private var activeSketchAngleInputRadians: Double? {
        guard sketchInputState.dimensionInputFocus == .angle,
              let angleRadians = sketchInputState.dimensionInputAngleRadians,
              angleRadians.isFinite else {
            return nil
        }
        return angleRadians
    }

    private var activeSketchWidthInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let widthMeters = sketchInputState.dimensionInputWidthMeters,
              widthMeters.isFinite,
              widthMeters > 0.0 else {
            return nil
        }
        return widthMeters
    }

    private var activeSketchHeightInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let heightMeters = sketchInputState.dimensionInputHeightMeters,
              heightMeters.isFinite,
              heightMeters > 0.0 else {
            return nil
        }
        return heightMeters
    }

    private var isRectangleDimensionInputActive: Bool {
        switch sketchInputState.dimensionInputFocus {
        case .width, .height:
            return true
        case .length, .angle, nil:
            return false
        }
    }

    private var activeSketchDimensionInputFocuses: [SketchDimensionInputFocus] {
        switch selectedTool {
        case .sketch, .solid:
            [.width, .height]
        case .circle:
            [.length]
        case .polygon, .arc:
            [.length, .angle]
        case .spline:
            [.length, .angle]
        case .select, .sweep, .mesh, .measure, .section, .surface:
            []
        }
    }

    private var viewportShiftScrollHandler: ((ViewportScrollDirection) -> Bool)? {
        guard selectedTool == .polygon || arraySession != nil else {
            return nil
        }
        return { direction in
            handleViewportShiftScroll(direction)
        }
    }

    private var viewportReferenceLineAnchorHandler: ((Point2D) -> Bool)? {
        guard usesSketchAxisConstraint else {
            return nil
        }
        return { point in
            addSketchReferenceLineAnchor(at: point)
        }
    }

    private var usesSketchAxisConstraint: Bool {
        switch selectedTool {
        case .sketch, .polygon, .circle, .arc, .spline, .solid:
            true
        case .select, .sweep, .mesh, .measure, .section, .surface:
            false
        }
    }

    private var showsConstructionPlaneHover: Bool {
        switch selectedTool {
        case .sketch, .polygon, .circle, .arc, .spline, .solid, .section:
            true
        case .select, .sweep, .mesh, .measure, .surface:
            false
        }
    }

    /// The canvas header.
    ///
    /// The seats are laid out at the width they declare and never shrink; the
    /// readouts after them take what is left and stand down when it is not
    /// enough.
    /// `WorkspaceCanvasHeaderLayout` owns both halves of that budget and
    /// `WorkspaceCanvasHeaderLayoutTests` holds it to the narrowest width the
    /// canvas column is laid out at.
    private var workspaceCanvasHeader: some View {
        workspaceCanvasHeaderContent(
            presentation: WorkspaceTopBarPresentation(
                selectedTargetCount: selectedTargetCount,
                selectionScope: selectionScope
            )
        )
    }

    @ViewBuilder
    private func workspaceCanvasHeaderContent(
        presentation: WorkspaceTopBarPresentation
    ) -> some View {
        let scaleFitPromptState = workspaceScaleFitPromptState
        HStack(spacing: WorkspaceCanvasHeaderLayout.itemSpacing) {
            WorkspaceSelectionScopeControl(
                selection: $selectionScope,
                hoverHint: $headerHoverHint
            )
            workspaceCanvasHeaderDivider
            WorkspaceSnapControl(
                isGridSnapEnabled: $isGridSnapEnabled,
                isObjectTargetingEnabled: $isObjectTargetingEnabled,
                isFixedGridVisualSpacing: fixedGridVisualSpacingBinding,
                isConstructionPlaneSnapEnabled: $isConstructionPlaneSnapEnabled,
                hoverHint: $headerHoverHint
            )
            workspaceCanvasHeaderDivider
            WorkspacePlaneModeControl(
                selection: $workspacePlaneMode,
                hoverHint: $headerHoverHint
            )
            workspaceCanvasHeaderDivider
            workspaceViewportFitMenu
            workspaceViewportDisplayModeMenu
            workspaceViewportShadingButton
            workspaceCanvasHeaderPanelButton(.analysis)

            workspaceCanvasHeaderReadouts(
                presentation: presentation,
                scaleFitPromptState: scaleFitPromptState
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            workspaceCanvasHeaderPanelButton(.more)
        }
        .padding(.horizontal, WorkspaceCanvasHeaderLayout.horizontalPadding)
        .frame(height: WorkspaceCanvasHeaderLayout.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceCanvasHeader")
        .overlay(alignment: .topLeading) {
            if let hintText = headerHoverHint.text {
                workspaceCanvasHeaderHint(hintText)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 8)
                    .offset(y: WorkspaceCanvasHeaderLayout.height + 4)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(1)
    }

    /// A full description outside the header's fixed-height control row.
    private func workspaceCanvasHeaderHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("WorkspaceCanvasHeader.hint")
    }

    /// The header's readouts, which leave the row rather than truncate inside
    /// it.
    ///
    /// A chip compressed to an ellipsis still carries its icon, its padding
    /// and its background, so readouts that only truncated would keep a floor
    /// under the row and push the overflow button off the narrowest canvas
    /// column. They stand together while they fit, fall back to the scale-fit
    /// prompt alone, which is the only one of them that is an action, and
    /// leave the row when even that does not fit. What leaves stays reachable:
    /// the plane name, the scene counts and the canvas scale each have a row
    /// in the overflow panel, so a reading that yields the row is still a
    /// reading the narrowest window can get to.
    ///
    /// The cluster is the header's only flexible child, so it is also what
    /// holds the overflow button against the trailing edge.
    @ViewBuilder
    private func workspaceCanvasHeaderReadouts(
        presentation: WorkspaceTopBarPresentation,
        scaleFitPromptState: WorkspaceScaleFitPromptState?
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WorkspaceCanvasHeaderLayout.itemSpacing) {
                if let activeConstructionPlane {
                    workspaceValuePill(
                        "Plane",
                        activeConstructionPlane.name,
                        accessibilityIdentifier: "WorkspacePlane.activeName"
                    )
                }

                workspaceStatusChip(
                    presentation.selectionScopeTitle,
                    systemImage: presentation.selectionScopeSystemImage,
                    tint: .secondary
                )
                .accessibilityIdentifier("WorkspaceTopBar.SelectionScope")

                if let selectionTitle = presentation.selectionTitle {
                    workspaceStatusChip(
                        selectionTitle,
                        systemImage: "scope",
                        tint: .secondary
                    )
                }

                WorkspaceCanvasScaleReadoutView(camera: viewportCameraState,
                                               minorStep: viewportProjectedGridMinorStep)

                if let scaleFitPromptState {
                    workspaceScaleFitPromptButton(scaleFitPromptState)
                }
            }

            HStack(spacing: WorkspaceCanvasHeaderLayout.itemSpacing) {
                if let scaleFitPromptState {
                    workspaceScaleFitPromptButton(scaleFitPromptState)
                }
            }

            Color.clear
                .frame(width: 0.0, height: 0.0)
        }
    }

    private var workspaceCanvasHeaderDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(
                width: WorkspaceCanvasHeaderLayout.dividerWidth,
                height: WorkspaceCanvasHeaderLayout.dividerHeight
            )
    }

    /// One header seat that opens a popover.
    ///
    /// A popover rather than a `Menu`: `Menu` content on macOS is an `NSMenu`,
    /// which carries rows and cannot lay out the stacks, frames and backgrounds
    /// these panels are built from. One optional `presentedHeaderPanel` decides
    /// which panel is open, so opening one closes the other.
    private func workspaceCanvasHeaderPanelButton(
        _ panel: WorkspaceCanvasHeaderPanel
    ) -> some View {
        let isPresented = Binding(
            get: { presentedHeaderPanel == panel },
            set: { presentedHeaderPanel = $0 ? panel : nil }
        )
        return Button {
            presentedHeaderPanel = presentedHeaderPanel == panel ? nil : panel
        } label: {
            Image(systemName: panel.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(
                    width: WorkspaceCanvasHeaderLayout.controlSize.width,
                    height: WorkspaceCanvasHeaderLayout.controlSize.height
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .foregroundStyle(
                    presentedHeaderPanel == panel
                        ? Color.accentColor
                        : Color.primary.opacity(0.72)
                )
                .background {
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                        .fill(
                            presentedHeaderPanel == panel
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.06)
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.title)
        .workspaceHeaderControlName(
            panel.title,
            identifier: panel.accessibilityIdentifier,
            hint: $headerHoverHint
        )
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            workspaceCanvasHeaderPanelContent(panel)
        }
    }

    @ViewBuilder
    private func workspaceCanvasHeaderPanelContent(
        _ panel: WorkspaceCanvasHeaderPanel
    ) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WorkspaceCanvasPanelLayout.sectionSpacing) {
                switch panel {
                case .analysis:
                    workspaceSurfaceAnalysisPanelSections
                case .more:
                    workspaceOverflowPanelSections
                }
            }
            .padding(WorkspaceCanvasPanelLayout.contentPadding)
            .frame(width: WorkspaceCanvasPanelLayout.width, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .frame(width: WorkspaceCanvasPanelLayout.width)
        .frame(maxHeight: WorkspaceCanvasPanelLayout.maximumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(panel.accessibilityIdentifier).panel")
    }

    @ViewBuilder
    private var workspaceSurfaceAnalysisPanelSections: some View {
        workspacePanelSection("Analysis") {
            WorkspaceSurfaceAnalysisControl(options: $surfaceAnalysisOptions)
            workspaceValueRow(
                "Target",
                selectedSurfaceAnalysisSummary == nil ? "No supported target" : "Selected target",
                accessibilityIdentifier: "WorkspaceAnalysis.target"
            )
        }
    }

    @ViewBuilder
    private var workspaceOverflowPanelSections: some View {
        workspacePanelSection("Views") {
            WorkspaceCanvasScaleReadoutView(camera: viewportCameraState,
                                           minorStep: viewportProjectedGridMinorStep, isOverflow: true)
            Button {
                createSavedViewFromCurrentViewport()
            } label: {
                Label("Save Current", systemImage: "plus.viewfinder")
                    .font(.caption.weight(.medium))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .disabled(!viewportCameraState.isReady)
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.78))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .help("Save Current View")
            .accessibilityLabel("Save Current View")
            .accessibilityIdentifier("WorkspaceSavedView.createCurrent")

            if savedViews.isEmpty {
                workspaceValueRow("Saved", "None")
            } else {
                VStack(spacing: 5) {
                    ForEach(savedViews) { savedView in
                        workspaceSavedViewRow(savedView)
                    }
                }
            }
        }

        workspacePanelSection("Plane") {
            let planeSummary = savedConstructionPlaneSummary
            workspaceValueRow("Snap", constructionPlaneSnapSummary)
            if planeSummary.planes.isEmpty {
                workspaceValueRow("Saved", "None")
            } else {
                VStack(spacing: 5) {
                    ForEach(planeSummary.planes, id: \.id) { plane in
                        workspaceConstructionPlaneRow(plane)
                    }
                }
            }
            if viewAlignedConstructionPlaneRequest != nil {
                workspaceValueRow("Command", "Pick View Origin")
            }
        }

        if commandCatalog.hasDomainCommands {
            workspacePanelSection("Domain") {
                VStack(spacing: 5) {
                    ForEach(commandCatalog.domainCommands) { command in
                        WorkspaceDomainCommandRow(
                            command: command,
                            displayUnit: snapshot.workspaceState.displayUnit,
                            generation: snapshot.documentGeneration
                        ) { request in
                            try await runWorkspaceOperation {
                                guard let current = workspace.view else {
                                    throw ProjectWorkspaceActionError(
                                        code: .snapshotUnavailable,
                                        message: "The project workspace has no published view snapshot."
                                    )
                                }
                                let plan = try domainCommandDispatcher.dispatch(
                                    request,
                                    from: current
                                )
                                return try await workspace.execute(plan)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("WorkspaceDomainCommandList")
            }
        }

        workspacePanelSection("Scene") {
            workspaceValueRow(
                "Bodies",
                "\(snapshot.evaluationSnapshot.bodyCount)",
                accessibilityIdentifier: "WorkspaceScene.bodies"
            )
            workspaceValueRow(
                "Issues",
                diagnosticSummary,
                accessibilityIdentifier: "WorkspaceScene.issues"
            )
        }
    }

    private var workspaceViewportFitMenu: some View {
        Menu {
            Button {
                performViewportControl(.fitVisible)
            } label: {
                Label("Fit Visible Objects", systemImage: "viewfinder")
                    .contentShape(Rectangle())
            }
            .disabled(!viewportControlSession.canFitVisible)
            .accessibilityIdentifier("WorkspaceViewport.fitVisible")

            Button {
                performViewportControl(.fitSelected)
            } label: {
                Label("Fit Selected Objects", systemImage: "scope")
                    .contentShape(Rectangle())
            }
            .disabled(!viewportControlSession.canFitSelected)
            .accessibilityIdentifier("WorkspaceViewport.fitSelected")
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .contentShape(Rectangle())
        } primaryAction: {
            performViewportControl(.fitVisible)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: WorkspaceCanvasHeaderLayout.controlSize.width,
            height: WorkspaceCanvasHeaderLayout.controlSize.height
        )
        .disabled(!viewportControlSession.canFitVisible)
        .accessibilityLabel("Viewport Fit")
        .workspaceHeaderControlName(
            "Fit Visible or Selected Objects",
            identifier: "WorkspaceViewport.fit",
            hint: $headerHoverHint
        )
    }

    private func performViewportControl(_ action: ViewportControlAction) {
        do {
            _ = try viewportControlSession.perform(action)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private var workspaceViewportShadingButton: some View {
        Button {
            isViewportShadingPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(
                    width: WorkspaceCanvasHeaderLayout.controlSize.width,
                    height: WorkspaceCanvasHeaderLayout.controlSize.height
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewportControlSession.isReady)
        .accessibilityLabel("Viewport Shading")
        .workspaceHeaderControlName(
            "Viewport Shading",
            identifier: "WorkspaceViewport.shading",
            hint: $headerHoverHint
        )
        .popover(isPresented: $isViewportShadingPresented, arrowEdge: .bottom) {
            ViewportShadingPanel(
                shading: Binding(
                    get: { viewportControlSession.shading },
                    set: { performViewportControl(.setShading($0)) }
                ),
                displayMode: viewportDisplayMode
            )
        }
    }

    private var workspaceViewportDisplayModeMenu: some View {
        Menu {
            viewportDisplayModeButton(.solid)
            viewportDisplayModeButton(.solidWithEdges)
            viewportDisplayModeButton(.wireframe)
            viewportDisplayModeButton(.normals)
        } label: {
            Image(systemName: viewportDisplayModeSystemImage(viewportDisplayMode))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: WorkspaceCanvasHeaderLayout.controlSize.width,
            height: WorkspaceCanvasHeaderLayout.controlSize.height
        )
        .accessibilityLabel("Viewport Display Mode")
        .accessibilityValue(viewportDisplayModeTitle(viewportDisplayMode))
        .workspaceHeaderControlName(
            "Viewport Display Mode",
            identifier: "WorkspaceViewport.displayMode",
            hint: $headerHoverHint
        )
    }

    @ViewBuilder
    private func viewportDisplayModeButton(_ mode: ViewportDisplayMode) -> some View {
        Button {
            do {
                try viewportControlSession.perform(.setDisplayMode(mode))
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        } label: {
            HStack {
                Label(
                    viewportDisplayModeTitle(mode),
                    systemImage: viewportDisplayModeSystemImage(mode)
                )
                Spacer(minLength: 12)
                if viewportDisplayMode == mode {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
        }
        .help(viewportDisplayModeHelp(mode))
        .accessibilityIdentifier("WorkspaceViewport.displayMode.\(viewportDisplayModeTitle(mode))")
    }

    private func viewportDisplayModeHelp(_ mode: ViewportDisplayMode) -> String {
        switch mode {
        case .solid:
            "Shaded source face presentation."
        case .solidWithEdges:
            "Shaded presentation with source-face Mesh boundaries, not exact B-rep edges."
        case .wireframe:
            "Depth-tested source-face Mesh boundaries; not exact B-rep edges or X-ray selection."
        case .normals:
            "World-space face normals: X is red, Y is green, Z is blue; source winding determines the sign."
        }
    }

    private func viewportDisplayModeSystemImage(_ mode: ViewportDisplayMode) -> String {
        switch mode {
        case .solid:
            "cube.fill"
        case .solidWithEdges:
            "cube.transparent"
        case .wireframe:
            "square.grid.3x3"
        case .normals:
            "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    /// A document that would not build, left standing until it does.
    @ViewBuilder
    private var workspaceEvaluationFailureItem: some View {
        if case .failed(let message) = snapshot.evaluationSnapshot.status {
            Button {
                isPreviewExpanded = true
            } label: {
                workspaceStatusChip(
                    "Build failed: \(message)",
                    systemImage: evaluationStatusSystemImage,
                    tint: evaluationStatusTint
                )
                .frame(
                    maxWidth: WorkspaceChromeControlMetrics.statusMessageMaximumWidth,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Logs")
            .accessibilityLabel("Document Build Status")
            .accessibilityValue(message)
            .accessibilityIdentifier("WorkspaceDocument.evaluationFailure")
        }
    }

    /// The workspace's own prompts and refusals, on screen.
    ///
    /// Every pick instruction and every refused key is appended to `transientDiagnostics`, which
    /// until now was rendered only inside the Logs pane, and that pane starts closed. A user was
    /// being asked to pick a curve, and told why a command would not run, by sentences nothing
    /// displayed. This lives in the window toolbar rather than the canvas chrome because a
    /// sentence over the canvas covers the model it is talking about, and it opens the pane,
    /// because what fits here is the newest sentence and not the ones before it.
    @ViewBuilder
    private var workspaceStatusMessageItem: some View {
        if let diagnostic = transientDiagnostics.last {
            Button {
                isPreviewExpanded = true
            } label: {
                workspaceStatusChip(
                    diagnostic.message,
                    systemImage: workspaceStatusSystemImage(for: diagnostic.severity),
                    tint: workspaceStatusTint(for: diagnostic.severity)
                )
                .frame(
                    maxWidth: WorkspaceChromeControlMetrics.statusMessageMaximumWidth,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Logs")
            .accessibilityLabel("Workspace Status")
            .accessibilityValue(diagnostic.message)
            .accessibilityIdentifier("WorkspaceCommand.status")
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            workspaceEvaluationFailureItem
        }

        ToolbarItem(placement: .status) {
            workspaceStatusMessageItem
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                newProject()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .contentShape(Rectangle())
            }
            .help("New Document")

            Menu {
                Button("Surface Creation…") { beginSurfaceModelingOperation() }
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("Modeling.begin.surfaceCreation")
                Divider()
                ForEach(ModelingOperationDraft.Kind.allCases) { kind in
                    Button(kind.rawValue) { beginModelingOperation(kind) }
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("Modeling.begin.\(kind.rawValue)")
                }
                Button("Involute Gear…") {
                    beginGearEditing()
                }
                .contentShape(Rectangle())
                .accessibilityIdentifier("Modeling.begin.involuteGear")
                Divider()
                Button("Edit Mesh Elements") {
                    cancelModelingOperation()
                    selectedTool = .mesh
                }
                .contentShape(Rectangle())
                Button("Make Selected CAD Editable as Mesh…") { showsMakeEditableConfirmation = true }
                    .contentShape(Rectangle())
                    .disabled(snapshot.selection.selectedTargets.count != 1 || !selectedPresentationHasExactCADAffordanceContext)
                // Boolean and Cut run as viewport dialogs.
                Divider()
                ForEach(WorkspaceBodyOperation.allCases) { operation in
                    Button("\(operation.rawValue) (\(operation.shortcut))") { beginBodyOperation(operation) }
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("Modeling.begin.\(operation.rawValue)")
                }
            } label: {
                Label("Model", systemImage: "cube")
                    .contentShape(Rectangle())
            }
            .disabled(modelingPreview.isBusy)
            .accessibilityIdentifier("WorkspaceCommand.model")
            .sheet(item: $gearDraft) { draft in
                InvoluteGearEditorView(draft: draft,
                    parameters: snapshot.document.document.cadDocument.parameters,
                    tolerance: snapshot.document.document.modelingSettings.tolerance,
                    onCancel: { gearDraft = nil }, onPreview: { command in
                        gearDraft = nil
                        previewHistoryOperation(command, title: draft.featureID == nil ? "Create Gear" : "Edit Gear")
                    })
            }

            Button {
                toggleSectionAnalysis()
            } label: {
                Image(systemName: isSectionAnalysisShown ? "square.split.diagonal.fill" : "square.split.diagonal")
                    .contentShape(Rectangle())
            }
            .help(isSectionAnalysisShown ? "Remove Section Analysis" : "Section Analysis")
            .accessibilityIdentifier("WorkspaceCommand.sectionAnalysis")

            Button {
                isPreviewExpanded.toggle()
            } label: {
                Image(systemName: isPreviewExpanded ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .contentShape(Rectangle())
            }
            .help(isPreviewExpanded ? "Hide Logs" : "Show Logs")
            .accessibilityIdentifier("WorkspaceCommand.logs")

            Button {
                validateDocument()
            } label: {
                Image(systemName: "checkmark.seal")
                    .contentShape(Rectangle())
            }
            .help("Validate Document")
            .accessibilityIdentifier("WorkspaceCommand.validate")

            Button {
                isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .contentShape(Rectangle())
            }
            .help("Inspector")
            .accessibilityIdentifier("WorkspaceCommand.inspector")
        }
    }

    private var workspaceScaleSummary: WorkspaceScaleStatusSummary {
        WorkspaceScaleStatusSummary(ruler: snapshot.workspaceState.ruler)
    }

    private var currentWorkspaceScaleRecommendation: WorkspaceScaleRecommendation? {
        return WorkspaceScaleRecommendationService().recommendation(
            for: presentationMeasurementBounds,
            currentRuler: snapshot.workspaceState.ruler
        )
    }

    private var presentationMeasurementBounds: MeasurementResult.Bounds? {
        snapshot.viewport.worldBounds.map {
            MeasurementResult.Bounds(
                minX: $0.minimum.x,
                minY: $0.minimum.y,
                minZ: $0.minimum.z,
                maxX: $0.maximum.x,
                maxY: $0.maximum.y,
                maxZ: $0.maximum.z
            )
        }
    }

    private var workspaceScaleFitPromptState: WorkspaceScaleFitPromptState? {
        WorkspaceScaleFitPromptState(recommendation: currentWorkspaceScaleRecommendation)
    }

    private var fixedGridVisualSpacingBinding: Binding<Bool> {
        Binding(
            get: {
                snapshot.workspaceState.viewportGridSettings.visualSpacingMode == .fixed
            },
            set: { isFixed in
                applyViewportGridVisualSpacingMode(isFixed ? .fixed : .adaptive)
            }
        )
    }

    @ViewBuilder
    private func workspaceScaleFitPromptButton(
        _ state: WorkspaceScaleFitPromptState
    ) -> some View {
        if state.isActionable {
            Button {
                fitWorkspaceScaleToModel()
            } label: {
                Label {
                    Text(state.title)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "scope")
                        .symbolRenderingMode(.hierarchical)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
                .frame(minHeight: WorkspaceChromeControlMetrics.controlHeight)
                .background {
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                        .fill(Color.accentColor.opacity(0.14))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.help)
            .accessibilityIdentifier("WorkspaceScale.fitPrompt")
            .accessibilityLabel("Workspace Scale Fit")
            .accessibilityValue(state.accessibilityValue)
        } else {
            workspaceStatusChip(
                state.title,
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
            .help(state.help)
            .accessibilityIdentifier("WorkspaceScale.limitPrompt")
            .accessibilityLabel("Workspace Scale Limit")
            .accessibilityValue(state.accessibilityValue)
        }
    }

    private var floatingToolPalette: some View {
        WorkspaceToolPalette(
            selectedTool: selectedTool,
            solidShape: solidShape,
            selectedOperation: modelingDraft?.kind,
            activate: { activateTool($0) },
            activateSolid: activateSolidShape,
            beginModelingOperation: beginModelingOperation,
            activeBodyOperation: booleanSession != nil ? .boolean : bodyCutSession != nil ? .cut : nil,
            beginBodyOperation: beginBodyOperation,
            accessibilityIdentifier: { canvasToolIdentifier(for: $0) }
        )
    }

    private var isViewportContextPanelVisible: Bool {
        WorkspaceViewportContextPanelVisibility.isVisible(
            selectedTool: selectedTool,
            selectedTargetCount: selectedTargetCount,
            selectedReferenceCount: snapshot.selection.selectedReferences.count,
            runningCommandInputs: runningContextPanelCommandInputs
        )
    }

    /// The running commands `viewportContextPanelContent` holds a section for.
    private var runningContextPanelCommandInputs: Set<WorkspaceViewportContextPanelVisibility.CommandInput> {
        var inputs: Set<WorkspaceViewportContextPanelVisibility.CommandInput> = []
        if viewAlignedConstructionPlaneRequest != nil { inputs.insert(.viewAlignedConstructionPlane) }
        if cutCurveSession != nil { inputs.insert(.cutCurve) }
        if booleanSession != nil { inputs.insert(.boolean) }
        if bodyCutSession != nil { inputs.insert(.bodyCut) }
        if filletSession != nil { inputs.insert(.fillet) }
        if rebuildSession != nil { inputs.insert(.rebuild) }
        if deformSession != nil { inputs.insert(.deform) }
        if projectSession != nil { inputs.insert(.project) }
        if bridgeEdgeSession != nil { inputs.insert(.bridgeEdge) }
        if dimensionCommandState.isActive { inputs.insert(.dimension) }
        if placeSession != nil { inputs.insert(.place) }
        if transformSession != nil { inputs.insert(.transform) }
        if mirrorSession != nil { inputs.insert(.mirror) }
        if sectionAnalysisSession != nil || placedSectionQuery != nil { inputs.insert(.sectionAnalysis) }
        return inputs
    }

    private var viewportContextPanelSelectionPresentation: WorkspaceViewportContextPanelVisibility.SelectionPresentation {
        WorkspaceViewportContextPanelVisibility.selectionPresentation(
            selectedSceneNodeCount: selectedSceneNodes.count,
            selectedTargetCount: selectedTargetCount,
            selectedReferenceCount: snapshot.selection.selectedReferences.count
        )
    }

    private var viewportBottomChromeReservedHeight: CGFloat {
        isViewportContextPanelVisible ? viewportChromeGeometry.contextPanelHeight : 0.0
    }

    private var viewportContextPanelContainer: some View {
        ViewThatFits(in: .horizontal) {
            viewportContextPanelContent
                .fixedSize(horizontal: true, vertical: false)
                .workspaceCanvasTopChromeContainer()

            ScrollView(.horizontal) {
                viewportContextPanelContent
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.hidden)
            .workspaceCanvasTopChromeContainer(contentSized: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanelContainer")
    }

    private var viewportContextPanelContent: some View {
        HStack(spacing: 8) {
            if selectedTool == .measure {
                measurementContextPanelContent(viewportMeasurementState)
            } else if selectedTool == .sweep {
                let preview = SweepSelectionPlanningService(
                    document: snapshot.document.document,
                    selection: displaySelection
                ).preview()
                WorkspaceSweepContextPanel(
                    preview: preview,
                    sectionLabel: sweepPreviewSectionLabel(preview.section),
                    pathLabel: sweepPreviewFeatureLabel(preview.pathFeatureID)
                )
            } else if selectedTool == .polygon {
                WorkspacePolygonContextPanel(
                    tool: selectedTool,
                    state: polygonToolState,
                    planeTitle: workspacePlaneMode.title,
                    axisTitle: activeSketchAxisTitle,
                    referenceLineAnchorCount: sketchInputState.referenceLineAnchors.count,
                    dimensionInputTitle: activeSketchDimensionInputTitle,
                    isGridSnapEnabled: isGridSnapEnabled,
                    decreaseSideCount: { _ = adjustPolygonSideCount(by: -1) },
                    increaseSideCount: { _ = adjustPolygonSideCount(by: 1) },
                    toggleSizingMode: { _ = togglePolygonSizingMode() },
                    toggleInclinationMode: { _ = togglePolygonInclinationMode() },
                    toggleKnifeMode: { _ = togglePolygonCutsFaces() }
                ) {
                    workspaceSketchDimensionInputField
                }
            } else if dimensionCommandState.isActive {
                dimensionContextPanelContent()
            } else {
                switch viewportContextPanelSelectionPresentation {
                case .idle:
                    idleViewportContextPanelContent()
                case .targetSelection:
                    selectionContextPanelContent(selectedSceneNodes)
                case .referenceSelection:
                    referenceSelectionContextPanelContent(snapshot.selection.selectedReferences)
                }
            }
            if viewAlignedConstructionPlaneRequest != nil {
                workspaceContextDivider
                workspaceValuePill(
                    "CPlane",
                    "Pick Origin",
                    accessibilityIdentifier: "WorkspaceConstructionPlane.pickOrigin"
                )
            }
            if let cutCurveSession {
                workspaceContextDivider
                cutCurveContextPanelContent(cutCurveSession)
            }
            if let booleanSession {
                workspaceContextDivider
                booleanContextPanelContent(booleanSession)
            }
            if let bodyCutSession {
                workspaceContextDivider
                bodyCutContextPanelContent(bodyCutSession)
            }
            if let filletSession {
                workspaceContextDivider
                filletContextPanelContent(filletSession)
            }
            if let rebuildSession {
                workspaceContextDivider
                rebuildContextPanelContent(rebuildSession)
            }
            if let deformSession {
                workspaceContextDivider
                deformContextPanelContent(deformSession)
            }
            if let projectSession {
                workspaceContextDivider
                projectContextPanelContent(projectSession)
            }
            if let bridgeEdgeSession {
                workspaceContextDivider
                bridgeEdgeContextPanelContent(bridgeEdgeSession)
            }
            if let placeSession {
                workspaceContextDivider
                placeSessionContextPanelContent(placeSession)
            }
            if let transformSession {
                workspaceContextDivider
                transformSessionContextPanelContent(transformSession)
            }
            if let mirrorSession {
                workspaceContextDivider
                mirrorSessionContextPanelContent(mirrorSession)
            }
            if sectionAnalysisSession != nil || placedSectionQuery != nil {
                workspaceContextDivider
                sectionAnalysisContextPanelContent()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanel")
    }

    /// The transform's command dialog: mode, orientation, pivot, options and typed values; each typed
    /// value applies one motion.
    @ViewBuilder
    private func transformSessionContextPanelContent(_ transform: WorkspaceTransformSession) -> some View {
        workspaceValuePill(transform.title, transform.constraintName, accessibilityIdentifier: "WorkspaceTransform.mode")
        Menu(transform.orientation.rawValue) {
            ForEach(SceneTransformOrientation.allCases, id: \.self) { orientation in
                Button(orientation.rawValue) {
                    transformSession?.orientation = orientation
                    refreshTransformFrame()
                }
                .disabled(orientation == .pivot && transform.pickedPivot == nil)
            }
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceTransform.orientation")
        Menu(transform.pickedPivot == nil ? transform.pivotMode.rawValue : "picked") {
            ForEach(SceneTransformPivotMode.allCases, id: \.self) { mode in
                Button(mode.rawValue) {
                    transformSession?.choose(pivotMode: mode)
                    refreshTransformFrame()
                }
            }
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceTransform.pivot")
        Toggle("Snap", isOn: Binding(
            get: { transform.snapsToIncrements },
            set: { transformSession?.snapsToIncrements = $0 }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceTransform.snap")
        let unit = snapshot.workspaceState.ruler.displayUnit
        switch transform.mode {
        case .move:
            ForEach(SceneTransformAxis.allCases, id: \.self) { axis in
                transformOptionField(.distance(axis), unit: unit.symbol)
            }
        case .rotate:
            transformOptionField(.angle, unit: "deg")
            ForEach(SceneTransformAxis.allCases, id: \.self) { axis in
                transformValueField("Axis \(axis.rawValue.uppercased())", value: {
                    switch axis {
                    case .x: transform.rotationAxis.x
                    case .y: transform.rotationAxis.y
                    case .z: transform.rotationAxis.z
                    }
                }()) { value in
                    switch axis {
                    case .x: transformSession?.rotationAxis.x = value
                    case .y: transformSession?.rotationAxis.y = value
                    case .z: transformSession?.rotationAxis.z = value
                    }
                }
            }
        case .scale:
            if transform.hasFreestyleScaleAxis {
                transformOptionField(.ratio, unit: "x")
                transformOptionField(.length, unit: unit.symbol)
                Toggle("Uniform", isOn: Binding(
                    get: { transform.freestyleUniform },
                    set: { transformSession?.freestyleUniform = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .accessibilityIdentifier("WorkspaceTransform.uniform")
            } else {
                ForEach(SceneTransformAxis.allCases, id: \.self) { axis in
                    transformOptionField(.factor(axis), unit: "x")
                }
            }
        }
    }

    /// Mirror's command dialog: the plane and the Cut, Union and Instances options.
    @ViewBuilder
    private func mirrorSessionContextPanelContent(_ mirror: WorkspaceMirrorSession) -> some View {
        workspaceValuePill("Mirror", mirror.planeName, accessibilityIdentifier: "WorkspaceMirror.plane")
        Toggle("Cut down mirror plane", isOn: Binding(
            get: { mirror.options.cutsAtPlane },
            set: { mirrorSession?.options.cutsAtPlane = $0 }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceMirror.cut")
        Toggle("Union halves", isOn: Binding(
            get: { mirror.options.unionsHalves },
            set: { if $0 != mirror.options.unionsHalves { mirrorSession?.toggleUnion() } }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceMirror.union")
        Toggle("Make Instances", isOn: Binding(
            get: { mirror.options.makesInstances },
            set: { if $0 != mirror.options.makesInstances { mirrorSession?.toggleInstances() } }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceMirror.instances")
        Button("Mirror") { applyMirror() }
            .controlSize(.small)
            .accessibilityIdentifier("WorkspaceMirror.apply")
    }

    /// Whether Section Analysis's dialog is up or its slice is placed.
    private var isSectionAnalysisShown: Bool {
        sectionAnalysisSession != nil || placedSectionQuery != nil
    }

    /// The Section Analysis command's section: the dialog's while it is up, else the placed slice.
    private var commandSectionAnalysisResult: Result<SectionAnalysisResult, Error>? {
        guard let query = sectionAnalysisSession?.query(constructionPlane: effectiveSketchPlane(fallback: .xy))
                ?? placedSectionQuery else {
            return nil
        }
        do {
            return .success(try sectionAnalysisStateBuilder.analysis(for: query))
        } catch {
            return .failure(error)
        }
    }

    /// Section Analysis toggles: it starts the dialog, or removes the dialog or placed slice.
    private func toggleSectionAnalysis() {
        if isSectionAnalysisShown {
            sectionAnalysisSession = nil
            placedSectionQuery = nil
            reportToolStatus("Section Analysis removed.")
            return
        }
        let targets = snapshot.selection.selectedTargets
        let face = targets.count == 1 ? targets.first.flatMap { target -> SelectionTarget? in
            if case .face = target.component { return target }
            return nil
        } : nil
        let section = WorkspaceSectionAnalysisSession(
            selectedFace: face, previousPlane: snapshot.document.document.productMetadata.sectionAnalysisPlane
        )
        sectionAnalysisSession = section
        reportToolStatus(section.prompt)
    }

    /// OK, Return or right-click: the section becomes a fixed slice that stays until the command
    /// is run again.
    private func confirmSectionAnalysis() {
        guard sectionAnalysisSession != nil, let result = commandSectionAnalysisResult else { return }
        switch result {
        case .success(let analysis):
            placedSectionQuery = WorkspaceSectionAnalysisSession.placedQuery(for: analysis)
            // The plane is kept with the document so Previous restores it after reopening.
            submitSource(.setSectionAnalysisPlane(WorkspaceSectionAnalysisSession.placedPlane(for: analysis)))
            sectionAnalysisSession = nil
            isWorkspaceFocused = true
            reportToolStatus("Section placed. Run Section Analysis again to remove it.")
        case .failure(let error):
            reportToolStatus("Section Analysis: \(error.localizedDescription)", severity: .warning)
        }
    }

    /// Section Analysis's command dialog, or the placed slice's summary.
    @ViewBuilder
    private func sectionAnalysisContextPanelContent() -> some View {
        let result = commandSectionAnalysisResult
        if let section = sectionAnalysisSession {
            Picker("Plane", selection: Binding(
                get: { section.planeSource },
                set: { source in
                    do {
                        try sectionAnalysisSession?.choose(source)
                    } catch {
                        reportToolStatus(error.localizedDescription, severity: .warning)
                    }
                }
            )) {
                ForEach(WorkspaceSectionAnalysisSession.PlaneSource.allCases) { source in
                    Text(source.title).tag(source)
                        .disabled(!section.offers(source))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("WorkspaceSectionAnalysis.plane")
            let unit = snapshot.workspaceState.displayUnit
            HStack(spacing: 4) {
                Text("Distance").foregroundStyle(.secondary)
                TextField("Distance", value: Binding(
                    get: { section.distanceMeters / unit.metersPerUnit },
                    set: { sectionAnalysisSession?.distanceMeters = $0 * unit.metersPerUnit }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .focused($isSectionDistanceFocused)
                    .accessibilityIdentifier("WorkspaceSectionAnalysis.distance")
                Text(unit.symbol).foregroundStyle(.secondary)
            }
            .font(.caption)
            Toggle("Flip", isOn: Binding(
                get: { section.flipsNormal },
                set: { if $0 != section.flipsNormal { sectionAnalysisSession?.toggleFlip() } }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .accessibilityIdentifier("WorkspaceSectionAnalysis.flip")
            Button("OK") { confirmSectionAnalysis() }
                .controlSize(.small)
                .disabled(!(result.map { if case .success = $0 { true } else { false } } ?? false))
                .accessibilityIdentifier("WorkspaceSectionAnalysis.confirm")
        } else {
            workspaceValuePill("Section", "Placed", accessibilityIdentifier: "WorkspaceSectionAnalysis.placed")
            Button("Remove") { toggleSectionAnalysis() }
                .controlSize(.small)
                .accessibilityIdentifier("WorkspaceSectionAnalysis.remove")
        }
        switch result {
        case .success(let analysis) where !analysis.interferences.isEmpty:
            workspaceValuePill(
                "Interference",
                "\(analysis.interferences.count)",
                accessibilityIdentifier: "WorkspaceSectionAnalysis.interference"
            )
        case .failure(let error):
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .accessibilityIdentifier("WorkspaceSectionAnalysis.failure")
        default:
            EmptyView()
        }
    }

    /// A stored option field: submitting it changes the option without applying a motion.
    private func transformValueField(
        _ title: String,
        value: Double,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { value }, set: onCommit), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .accessibilityIdentifier("WorkspaceTransform.\(title.lowercased())")
        }
        .font(.caption)
    }

    /// A typed value field: it holds its text until Return, which applies the value as one motion
    /// and clears it.
    private func transformOptionField(_ field: WorkspaceTransformTypedField, unit: String) -> some View {
        HStack(spacing: 4) {
            Text(field.title).foregroundStyle(.secondary)
            TextField(field.title, text: Binding(
                get: { transformFieldTexts[field] ?? "" },
                set: { transformFieldTexts[field] = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceTransform.\(field.title.lowercased())")
            Text(unit).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    /// Place's phase and the options every placement of the session uses.
    @ViewBuilder
    private func placeSessionContextPanelContent(_ place: WorkspacePlaceSession) -> some View {
        workspaceValuePill(
            "Place",
            place.phase == .source ? "Pick Source" : "Pick Destination",
            accessibilityIdentifier: "WorkspacePlace.phase"
        )
        placeOptionField("Angle", field: .angle, value: place.angleDegrees, unit: "deg") { value in
            placeSession?.angleDegrees = value
        }
        placeOptionField("Scale", field: .scale, value: place.scale, unit: "x") { value in
            guard value > 0 else {
                reportToolStatus("Place scale must be greater than zero.", severity: .warning)
                return
            }
            placeSession?.scale = value
        }
        workspaceValuePill("Copies", "\(place.copyCount)", accessibilityIdentifier: "WorkspacePlace.copies")
        workspaceValuePill(
            "Output",
            place.output == .componentInstance ? "Instances" : "Copies",
            accessibilityIdentifier: "WorkspacePlace.output"
        )
        workspaceValuePill(
            "Up",
            place.upAxis.rawValue.uppercased() + (place.flipsOrientation ? " flipped" : ""),
            accessibilityIdentifier: "WorkspacePlace.up"
        )
    }

    private func placeOptionField(
        _ title: String,
        field: WorkspacePlaceOptionField,
        value: Double,
        unit: String,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { value }, set: onCommit), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .focused($focusedPlaceOption, equals: field)
                .accessibilityIdentifier("WorkspacePlace.\(title.lowercased())")
            Text(unit).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func measurementContextPanelContent(_ state: ViewportMeasurementState) -> some View {
        workspaceStatusChip(
            state.title,
            systemImage: "ruler",
            tint: state.distanceMeters == nil ? .secondary : .accentColor
        )
        if let distanceMeters = state.distanceMeters {
            let unit = snapshot.workspaceState.ruler.displayUnit
            workspaceValuePill(
                "Distance",
                "\(unit.value(fromMeters: distanceMeters).formatted(.number.precision(.fractionLength(0...3)))) \(unit.symbol)",
                accessibilityIdentifier: "WorkspaceMeasure.distance"
            )
        }
        if let boundsSummary = state.boundsSummary {
            Text(boundsSummary)
                .font(.caption2.monospacedDigit())
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .help(boundsSummary)
                .accessibilityIdentifier("WorkspaceMeasure.worldBounds")
        }
        WorkspaceSavedMeasurementsControl(
            resolutions: savedMeasurementResolutions,
            onDelete: deleteSavedMeasurement
        )
        Text(state.status ?? "Click a first point, then click a second point.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: .leading)
            .accessibilityIdentifier("WorkspaceMeasure.status")
    }

    /// The same Core resolution the viewport draws saved measurements from.
    private var savedMeasurementResolutions: [MeasurementAnnotationResolver.Resolution] {
        let document = snapshot.document.document
        return MeasurementAnnotationResolver().resolveAll(in: document) {
            try TopologySnapshotService().snapshot(
                document: document,
                objectRegistry: objectRegistry,
                currentEvaluation: snapshot.cadInteraction,
                currentGeneration: snapshot.documentGeneration
            )
        }
    }

    /// Saves the completed measurement as a persistent distance annotation.
    ///
    /// Anchors are built against the document the command runs on, so each
    /// endpoint is stored in the local frame of the placement it was picked
    /// under and follows that placement afterwards.
    /// Measure started with one edge or sketch curve selected measures across it.
    private func selectedCurveMeasurementSeed() -> ViewportMeasurementSeed? {
        guard snapshot.selection.selectedTargets.count == 1, let target = snapshot.selection.selectedTargets.first else {
            return nil
        }
        switch target.component {
        case .edge, .sketchEntity: break
        default: return nil
        }
        do {
            let document = snapshot.document.document
            let topology = try TopologySnapshotService().snapshot(
                document: document, objectRegistry: objectRegistry,
                currentEvaluation: snapshot.cadInteraction, currentGeneration: snapshot.documentGeneration
            )
            guard let points = try document.measuredCurvePoints(for: target, topology: topology) else { return nil }
            return ViewportMeasurementSeed(start: points.start, end: points.end)
        } catch {
            reportToolStatus("The selected curve cannot be measured: \(error.localizedDescription)", severity: .warning)
            return nil
        }
    }

    private func saveMeasurement(_ state: ViewportMeasurementState) {
        submitSource(name: "addMeasurementAnnotation", commands: { current in
            let document = current.document.document
            let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
            let annotation = try state.annotation(
                named: "Distance \(document.productMetadata.measurements.count + 1)", in: hierarchy
            )
            return [.addMeasurementAnnotation(annotation)]
        }) { _ in
            reportToolStatus("Measurement saved.")
        }
    }

    /// Deletes a saved measurement through its annotation scene node, which
    /// removes the annotation with it.
    private func deleteSavedMeasurement(_ id: MeasurementAnnotationID) {
        guard let sceneNodeID = snapshot.document.document.productMetadata.measurements[id]?.sceneNodeID else {
            reportToolStatus("The saved measurement has no annotation node to delete.", severity: .warning)
            return
        }
        submitSource(.deleteSceneNodes(ids: [sceneNodeID])) { _ in
            reportToolStatus("Saved measurement deleted.")
        }
    }

    @ViewBuilder
    private func idleViewportContextPanelContent() -> some View {
        workspaceStatusChip(
            selectedTool.title,
            systemImage: selectedTool.systemImage,
            tint: .accentColor
        )
        workspaceContextDivider
        workspaceValuePill("Plane", workspacePlaneMode.title)
        if usesSketchAxisConstraint {
            workspaceValuePill(
                "Axis",
                activeSketchAxisTitle,
                accessibilityIdentifier: "WorkspaceSketch.axisConstraint"
            )
            if sketchInputState.referenceLineAnchors.isEmpty == false {
                workspaceValuePill(
                    "Refs",
                    "\(sketchInputState.referenceLineAnchors.count)",
                    accessibilityIdentifier: "WorkspaceSketch.referenceLines"
                )
            }
            workspaceValuePill(
                "Input",
                activeSketchDimensionInputTitle,
                accessibilityIdentifier: "WorkspaceSketch.dimensionInputFocus"
            )
            workspaceSketchDimensionInputField
        }
    }

    @ViewBuilder
    private func referenceSelectionContextPanelContent(_ references: [SelectionReference]) -> some View {
        let summary = WorkspaceReferenceContextSummary(references: references)
        workspaceStatusChip(
            summary.familyTitle,
            systemImage: summary.systemImage,
            tint: .accentColor
        )
        workspaceValuePill(
            "Kind",
            summary.kindTitle,
            accessibilityIdentifier: "WorkspaceReference.kind"
        )
        if let directionTitle = summary.directionTitle {
            workspaceValuePill(
                "Dir",
                directionTitle,
                accessibilityIdentifier: "WorkspaceReference.direction"
            )
        }
        if let indexTitle = summary.indexTitle {
            workspaceValuePill(
                "Index",
                indexTitle,
                accessibilityIdentifier: "WorkspaceReference.index"
            )
        }
        if summary.showsReferenceCount {
            workspaceValuePill(
                "Refs",
                "\(summary.referenceCount)",
                accessibilityIdentifier: "WorkspaceReference.count"
            )
        }
    }

    @ViewBuilder
    private func selectionContextPanelContent(_ nodes: [SceneNode]) -> some View {
        let displayAction = WorkspaceSelectionDisplayAction(nodes: nodes)
        if let boundsSummary = viewportMeasurementState.boundsSummary {
            Text(boundsSummary)
                .font(.caption2.monospacedDigit())
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .help(boundsSummary)
                .accessibilityIdentifier("WorkspaceMeasure.worldBounds")
        }
        workspaceValuePill(
            "Target",
            selectedTargetSummary,
            accessibilityIdentifier: "WorkspaceSelection.target"
        )

        if regionOffsetCommandState.isActive, selectedRegionTargets.isEmpty == false {
            workspaceContextDivider
            regionOffsetContextPanelContent(selectedRegionTargets)
        }

        if edgeOffsetCommandState.isActive, selectedEdgeTargets.isEmpty == false {
            workspaceContextDivider
            edgeOffsetContextPanelContent(selectedEdgeTargets)
        }

        // A circle has the dialog only while its Offset runs: Slot, the idle dialog's default,
        // takes open curves.
        if !slotProfileCommandState.isVertexOffsetActive,
           let slotTarget = selectedSlotSourceCurveTarget
            ?? (slotProfileCommandState.isCurveOffsetActive ? selectedCurveOffsetTarget : nil) {
            workspaceContextDivider
            slotProfileContextPanelContent(slotTarget)
        }

        if let bridgeCurve = selectedBridgeCurve {
            workspaceContextDivider
            bridgeTensionContextPanelContent(bridgeCurve)
        }

        if slotProfileCommandState.isVertexOffsetActive,
           let entity = sketchCommandTargetResolver.entity(from: selectedSketchEntityResult),
           selectedSketchVertexOffsetHandle(entity) != nil {
            workspaceContextDivider
            vertexOffsetContextPanelContent(entity)
        }

        if slideCommandState.isCurveControlVerticesActive,
           let slideInput = selectedSplineControlPointSlideInput() {
            workspaceContextDivider
            splineControlPointSlideContextPanelContent(slideInput)
        }

        if slideCommandState.isSurfaceControlVerticesActive,
           selectedPolySplineSurfaceVertexTargets.isEmpty == false {
            workspaceContextDivider
            polySplineSurfaceVertexSlideContextPanelContent(selectedPolySplineSurfaceVertexTargets)
        }

        if slideCommandState.isSurfaceControlVerticesActive,
           selectedSurfaceControlPointReferences.isEmpty == false {
            workspaceContextDivider
            surfaceControlPointSlideContextPanelContent(selectedSurfaceControlPointReferences)
        } else if selectedTool == .select, selectionScope == .vertex,
                  selectedSurfaceControlPointReferences.isEmpty == false {
            workspaceContextDivider
            surfaceControlPointMoveOptionsContent()
        }

        if selectedConstructionPlaneTargets != nil {
            workspaceContextDivider
            workspaceIconButton(
                systemImage: "rectangle.dashed",
                help: "Create Construction Plane",
                accessibilityIdentifier: "WorkspaceConstructionPlane.createFromSelection"
            ) {
                _ = createConstructionPlaneFromSelectedTargets(alignsView: true)
            }
        }

        workspaceContextDivider

        workspaceIconButton(
            systemImage: displayAction.visibilitySystemImage,
            help: displayAction.visibilityHelp,
            accessibilityIdentifier: "WorkspaceSelection.visible"
        ) {
            let nodeIDs = nodes.map(\.id)
            let isVisible = displayAction.hidesSelection == false
            submitSource(name: "setSelectionVisibility") { current in
                try nodeIDs.map { id in
                    guard current.document.document.productMetadata.sceneNodes[id] != nil else {
                        throw EditorError(
                            code: .referenceUnresolved,
                            message: "Selected scene node \(id) no longer exists."
                        )
                    }
                    return .setSceneNodeVisibility(id: id, isVisible: isVisible)
                }
            }
        }

        workspaceIconButton(
            systemImage: displayAction.lockSystemImage,
            help: displayAction.lockHelp,
            accessibilityIdentifier: "WorkspaceSelection.locked"
        ) {
            let nodeIDs = nodes.map(\.id)
            let isLocked = displayAction.locksSelection
            submitSource(name: "setSelectionLock") { current in
                try nodeIDs.map { id in
                    guard current.document.document.productMetadata.sceneNodes[id] != nil else {
                        throw EditorError(
                            code: .referenceUnresolved,
                            message: "Selected scene node \(id) no longer exists."
                        )
                    }
                    return .setSceneNodeLock(id: id, isLocked: isLocked)
                }
            }
        }

        workspaceIconButton(
            systemImage: "arrow.counterclockwise",
            help: "Reset Transform",
            accessibilityIdentifier: "WorkspaceSelection.resetTransform"
        ) {
            submitSource(
                nodes.map { node in
                    .setSceneNodeTransform(id: node.id, localTransform: .identity)
                },
                name: "resetSelectionTransform"
            )
        }
        .disabled(nodes.allSatisfy { $0.localTransform.matrix == .identity })
    }

    @ViewBuilder
    private func dimensionContextPanelContent() -> some View {
        if let entry = dimensionCommandState.activeEntry,
           let currentValue = dimensionCommandState.currentValue {
            WorkspaceDimensionContextPanel(
                targetTitle: selectedTargetSummary,
                kindTitle: entry.label,
                sourceTitle: entry.sourceTitle,
                itemTitle: "\(dimensionCommandState.activeOrdinal)/\(dimensionCommandState.activeCount)",
                valueTitle: formattedDimensionValue(currentValue, kind: entry.valueKind),
                isInputModeActive: dimensionCommandState.isInputModeActive,
                canMoveBetweenDimensions: dimensionCommandState.activeCount >= 2,
                canCommit: dimensionCommandState.canCommit,
                focusPrevious: { dimensionCommandState.focusPrevious() },
                activateInputMode: { dimensionCommandState.activateInputMode() },
                focusNext: { dimensionCommandState.focusNext() },
                confirm: { commitDimensionCommand() },
                cancel: { dimensionCommandState.deactivate() }
            ) {
                workspaceDimensionInputField
            }
        }
    }

    @ViewBuilder
    private func splineControlPointSlideContextPanelContent(
        _ input: WorkspaceSplineControlPointSlideInput
    ) -> some View {
        WorkspaceCurveControlPointSlideContextPanel(
            controlPointCount: input.controlPointIndexes.count,
            distanceInput: commandDistanceInput(
                "Distance", meters: $sketchSplineControlPointSlideDistanceMeters,
                field: .slideDistance, accessibilityIdentifier: "WorkspaceSlideCV.distance"
            ),
            routeTitle: slideCommandState.routeTitle,
            slidePositiveU: {
                slideSelectedSplineControlPoints(
                    input.target,
                    controlPointIndexes: input.controlPointIndexes,
                    direction: .positiveU
                )
            },
            slideNegativeU: {
                slideSelectedSplineControlPoints(
                    input.target,
                    controlPointIndexes: input.controlPointIndexes,
                    direction: .negativeU
                )
            },
            slideNormal: {
                slideSelectedSplineControlPoints(
                    input.target,
                    controlPointIndexes: input.controlPointIndexes,
                    direction: .normal
                )
            },
            confirm: { _ = confirmActiveWorkspaceCommand() }
        )
    }

    @ViewBuilder
    private func polySplineSurfaceVertexSlideContextPanelContent(
        _ targets: [SelectionTarget]
    ) -> some View {
        WorkspaceSurfaceControlPointSlideContextPanel(
            controlPointCount: targets.count,
            distanceInput: commandDistanceInput(
                "Distance", meters: $polySplineSurfaceVertexSlideDistanceMeters,
                field: .slideDistance, accessibilityIdentifier: "WorkspaceSlideSurfaceCV.distance"
            ),
            routeTitle: slideCommandState.routeTitle,
            slidePositiveU: {
                slideSelectedPolySplineSurfaceVertices(targets, direction: .positiveU)
            },
            slideNegativeU: {
                slideSelectedPolySplineSurfaceVertices(targets, direction: .negativeU)
            },
            slideNormal: {
                slideSelectedPolySplineSurfaceVertices(targets, direction: .normal)
            },
            slidePositiveV: {
                slideSelectedPolySplineSurfaceVertices(targets, direction: .positiveV)
            },
            slideNegativeV: {
                slideSelectedPolySplineSurfaceVertices(targets, direction: .negativeV)
            },
            confirm: { _ = confirmActiveWorkspaceCommand() }
        )
    }

    /// Move Control Point's Proportional and Mirror options, which every control point drag uses.
    @ViewBuilder
    private func surfaceControlPointMoveOptionsContent() -> some View {
        let options = surfaceControlPointMoveOptions
        Menu("Proportional: \(options.proportional.rawValue)") {
            ForEach(SurfaceControlPointMoveOptions.Proportional.allCases, id: \.self) { mode in
                Button(mode.rawValue) { surfaceControlPointMoveOptions.proportional = mode }
            }
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceControlPointMove.proportional")
        if options.proportional != .none {
            transformValueField("Falloff U", value: options.falloffU) { value in
                guard value.isFinite, value > 0 else {
                    reportToolStatus("A falloff must be a positive number of control points.", severity: .warning)
                    return
                }
                surfaceControlPointMoveOptions.falloffU = value
            }
            transformValueField("Falloff V", value: options.falloffV) { value in
                guard value.isFinite, value > 0 else {
                    reportToolStatus("A falloff must be a positive number of control points.", severity: .warning)
                    return
                }
                surfaceControlPointMoveOptions.falloffV = value
            }
        }
        Menu("Mirror: \(options.mirrorAxis?.rawValue.uppercased() ?? "None")") {
            Button("None") { surfaceControlPointMoveOptions.mirrorAxis = nil }
            ForEach(SurfaceControlPointMoveOptions.MirrorAxis.allCases, id: \.self) { axis in
                Button(axis.rawValue.uppercased()) { surfaceControlPointMoveOptions.mirrorAxis = axis }
            }
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceControlPointMove.mirror")
    }

    @ViewBuilder
    private func surfaceControlPointSlideContextPanelContent(
        _ targets: [SelectionReference]
    ) -> some View {
        WorkspaceSurfaceControlPointSlideContextPanel(
            controlPointCount: targets.count,
            distanceInput: commandDistanceInput(
                "Distance", meters: $polySplineSurfaceVertexSlideDistanceMeters,
                field: .slideDistance, accessibilityIdentifier: "WorkspaceSlideSurfaceCV.distance"
            ),
            routeTitle: slideCommandState.routeTitle,
            slidePositiveU: {
                slideSelectedSurfaceControlPoints(targets, direction: .positiveU)
            },
            slideNegativeU: {
                slideSelectedSurfaceControlPoints(targets, direction: .negativeU)
            },
            slideNormal: {
                slideSelectedSurfaceControlPoints(targets, direction: .normal)
            },
            slidePositiveV: {
                slideSelectedSurfaceControlPoints(targets, direction: .positiveV)
            },
            slideNegativeV: {
                slideSelectedSurfaceControlPoints(targets, direction: .negativeV)
            },
            confirm: { _ = confirmActiveWorkspaceCommand() }
        )
    }

    @ViewBuilder
    private func slotProfileContextPanelContent(_ target: SelectionTarget) -> some View {
        WorkspaceSlotContextPanel(
            isActive: slotProfileCommandState.isActive,
            title: slotProfileCommandState.isActive ? slotProfileCommandState.title : "Slot",
            distanceInput: commandDistanceInput(
                slotProfileCommandState.output == .slot ? "Width" : "Distance",
                meters: $slotProfileWidthMeters,
                field: .curveOffset,
                accessibilityIdentifier: "WorkspaceSlot.width"
            ),
            inputModeTitle: slotProfileCommandState.inputModeTitle,
            symmetricTitle: slotProfileCommandState.isCurveOffsetActive
                ? (slotProfileCommandState.isSymmetric ? "On" : "Off") : nil,
            gapFillTitle: slotProfileCommandState.isCurveOffsetActive
                ? regionOffsetGapFillTitle(curveOffsetGapFill) : nil,
            create: { createCommandedCurveOffset(target) }
        )
    }

    /// Cut Curve's dialog: which list clicks pick, its two lists, Extend (Tab) and Cut.
    @ViewBuilder
    private func cutCurveContextPanelContent(_ cut: WorkspaceCutCurveSession) -> some View {
        workspaceStatusChip("Cut Curve", systemImage: "scissors", tint: .accentColor)
        Picker("Pick", selection: Binding(
            get: { cut.picking },
            set: { cutCurveSession?.picking = $0; if let prompt = cutCurveSession?.prompt { reportToolStatus(prompt) } }
        )) {
            Text("Targets \(cut.targets.count)").tag(WorkspaceCutCurveSession.Role.targets)
            Text("Cutters \(cut.cutters.count)").tag(WorkspaceCutCurveSession.Role.cutters)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceCutCurve.picking")
        Toggle("Extend (Tab)", isOn: Binding(
            get: { cut.extendsCutter },
            set: { cutCurveSession?.extendsCutter = $0 }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceCutCurve.extend")
        workspaceIconButton(
            systemImage: "scissors",
            help: "Cut",
            accessibilityIdentifier: "WorkspaceCutCurve.cut",
            action: { confirmCutCurve() }
        )
        .disabled(!cut.canCut)
    }

    /// Boolean's dialog: which list clicks pick, the operation (Q, W, Shift-E, Shift-Q), Keep Tools
    /// (T), each side's material and Combine.
    @ViewBuilder
    private func booleanContextPanelContent(_ boolean: WorkspaceBooleanSession) -> some View {
        workspaceStatusChip("Boolean", systemImage: "square.on.square", tint: .accentColor)
        Picker("Pick", selection: Binding(
            get: { boolean.picking },
            set: { booleanSession?.picking = $0; if let prompt = booleanSession?.prompt { reportToolStatus(prompt) } }
        )) {
            Text("Targets \(boolean.targets.count)").tag(WorkspaceBooleanSession.Role.targets)
            Text("Tools \(boolean.tools.count)").tag(WorkspaceBooleanSession.Role.tools)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceBoolean.picking")
        Picker("Operation", selection: Binding(
            get: { boolean.operation },
            set: { booleanSession?.setOperation($0) }
        )) {
            Text("Union (Q)").tag(BooleanOperation.union)
            Text("Difference (W)").tag(BooleanOperation.difference)
            Text("Intersect (⇧E)").tag(BooleanOperation.intersect)
            Text("Slice (⇧Q)").tag(BooleanOperation.slice)
            Text("Region").tag(BooleanOperation.region)
        }
        .fixedSize()
        .accessibilityIdentifier("WorkspaceBoolean.operation")
        Toggle("Keep Tools (T)", isOn: Binding(
            get: { boolean.keepTools },
            set: { booleanSession?.keepTools = $0 }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceBoolean.keepTools")
        Menu("Material") {
            Picker("Target", selection: Binding(
                get: { boolean.targetMaterial },
                set: { booleanSession?.targetMaterial = $0 }
            )) {
                ForEach(WorkspaceBooleanSession.materials, id: \.self) { Text(WorkspaceBooleanSession.title(of: $0)).tag($0) }
            }
            Picker("Tool", selection: Binding(
                get: { boolean.toolMaterial },
                set: { booleanSession?.toolMaterial = $0 }
            )) {
                ForEach(WorkspaceBooleanSession.materials, id: \.self) { Text(WorkspaceBooleanSession.title(of: $0)).tag($0) }
            }
        }
        .fixedSize()
        .disabled(!boolean.takesMaterials)
        .accessibilityIdentifier("WorkspaceBoolean.material")
        workspaceIconButton(
            systemImage: "checkmark",
            help: "Combine",
            accessibilityIdentifier: "WorkspaceBoolean.apply",
            action: { confirmBoolean() }
        )
        .disabled(!boolean.canApply)
    }

    /// Cut's dialog: which list clicks pick, Extend (E), along the view (S) and Cut.
    @ViewBuilder
    private func bodyCutContextPanelContent(_ cut: WorkspaceBodyCutSession) -> some View {
        workspaceStatusChip("Cut", systemImage: "scissors", tint: .accentColor)
        Picker("Pick", selection: Binding(
            get: { cut.picking },
            set: { bodyCutSession?.picking = $0; if let prompt = bodyCutSession?.prompt { reportToolStatus(prompt) } }
        )) {
            Text("Targets \(cut.targets.count)").tag(WorkspaceBodyCutSession.Role.targets)
            Text("Cutters \(cut.cutters.count)").tag(WorkspaceBodyCutSession.Role.cutters)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceBodyCut.picking")
        Toggle("Extend (E)", isOn: Binding(
            get: { cut.extendsCurves },
            set: { bodyCutSession?.extendsCurves = $0 }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceBodyCut.extend")
        Toggle("View (S)", isOn: Binding(
            get: { cut.viewDirection != nil },
            set: { if $0 != (bodyCutSession?.viewDirection != nil) { toggleBodyCutViewDirection() } }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
        .accessibilityIdentifier("WorkspaceBodyCut.view")
        workspaceIconButton(
            systemImage: "scissors",
            help: "Cut",
            accessibilityIdentifier: "WorkspaceBodyCut.cut",
            action: { confirmBodyCut() }
        )
        .disabled(!cut.canCut)
    }

    /// Offset Vertex's dialog on the selected curve end: its distance, which D focuses, and Create.
    @ViewBuilder
    private func vertexOffsetContextPanelContent(_ entity: InspectorSketchEntity) -> some View {
        WorkspaceSlotContextPanel(
            isActive: true,
            title: slotProfileCommandState.title,
            distanceInput: commandDistanceInput(
                "Distance", meters: $sketchVertexOffsetDistanceMeters, field: .curveOffset,
                accessibilityIdentifier: "WorkspaceVertexOffset.distance"
            ),
            inputModeTitle: slotProfileCommandState.inputModeTitle,
            symmetricTitle: nil,
            gapFillTitle: nil,
            create: { createCommandedVertexOffset(entity) }
        )
    }

    private func commandDistanceInput(
        _ title: String,
        meters: Binding<Double>,
        field: WorkspaceCommandDistanceField,
        accessibilityIdentifier: String
    ) -> WorkspaceCommandDistanceInput {
        WorkspaceCommandDistanceInput(
            title: title,
            meters: meters,
            unit: snapshot.workspaceState.ruler.displayUnit,
            field: field,
            focus: $focusedCommandDistance,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    @ViewBuilder
    private func edgeOffsetContextPanelContent(_ targets: [SelectionTarget]) -> some View {
        let supportResolution = edgeOffsetSupportStateResolver.resolution(for: targets)
        WorkspaceEdgeOffsetContextPanel(
            isSupported: supportResolution.isSupported,
            distanceInput: commandDistanceInput(
                "Distance", meters: $edgeOffsetDistanceMeters, field: .edgeOffset,
                accessibilityIdentifier: "WorkspaceEdgeOffset.distance"
            ),
            gapFillTitle: regionOffsetGapFillTitle(edgeOffsetGapFill),
            inputModeTitle: edgeOffsetCommandState.inputModeTitle,
            lockedDistanceTitle: edgeOffsetCommandState.usesLockedDistance ? "On" : "Off",
            supportTitle: edgeOffsetSupportStateResolver.supportTitle(for: supportResolution),
            offset: {
                offsetSelectedEdges(
                    targets,
                    by: edgeOffsetDistanceMeters,
                    gapFill: edgeOffsetGapFill,
                    isSymmetric: edgeOffsetCommandState.usesLockedDistance
                )
            }
        )
    }

    @ViewBuilder
    private func regionOffsetContextPanelContent(_ targets: [SelectionTarget]) -> some View {
        WorkspaceRegionOffsetContextPanel(
            distanceInput: commandDistanceInput(
                "Distance", meters: $regionOffsetDistanceMeters, field: .regionOffset,
                accessibilityIdentifier: "WorkspaceRegionOffset.distance"
            ),
            gapFillTitle: regionOffsetGapFillTitle(regionOffsetGapFill),
            inputModeTitle: regionOffsetCommandState.inputModeTitle,
            lockedDistanceTitle: regionOffsetCommandState.usesLockedDistance ? "On" : "Off",
            modeTitle: regionOffsetCommandState.usesCombinedRegions ? "Combined" : "Individual",
            offsetInward: {
                offsetSelectedRegions(
                    targets,
                    by: -abs(regionOffsetDistanceMeters),
                    gapFill: regionOffsetGapFill,
                    isSymmetric: regionOffsetCommandState.usesLockedDistance,
                    combinesRegions: regionOffsetCommandState.usesCombinedRegions
                )
            },
            offsetOutward: {
                offsetSelectedRegions(
                    targets,
                    by: abs(regionOffsetDistanceMeters),
                    gapFill: regionOffsetGapFill,
                    isSymmetric: regionOffsetCommandState.usesLockedDistance,
                    combinesRegions: regionOffsetCommandState.usesCombinedRegions
                )
            }
        )
    }

    private func workspaceConstructionPlaneRow(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) -> some View {
        let isRenaming = constructionPlaneRenameTargetID == entry.id
        let isSelected = entry.selectionTarget().map { snapshot.selection.containsTarget($0) } ?? false
        let identifierSuffix = String(describing: entry.id)
        return HStack(spacing: 6) {
            Button {
                activateConstructionPlane(entry.id)
            } label: {
                Image(systemName: entry.isActive ? "smallcircle.filled.circle" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(entry.isActive ? Color.accentColor : Color.primary.opacity(0.58))
            .help("Activate Construction Plane")
            .accessibilityLabel("Activate \(entry.name)")
            .accessibilityValue(entry.isActive ? "Active" : "Inactive")
            .accessibilityIdentifier("WorkspacePlane.activate.\(identifierSuffix)")

            if !isRenaming {
                Button {
                    activateAndAlignConstructionPlane(entry)
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.68))
                .help("Activate and Align View")
                .accessibilityLabel("Align View To \(entry.name)")
                .accessibilityIdentifier("WorkspacePlane.alignView.\(identifierSuffix)")

                Button {
                    updateConstructionPlaneFromView(entry)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.68))
                .help("Update Plane From View")
                .accessibilityLabel("Update \(entry.name) From View")
                .accessibilityIdentifier("WorkspacePlane.updateFromView.\(identifierSuffix)")
            }

            if isRenaming {
                TextField(
                    "Plane name",
                    text: Binding(
                        get: { constructionPlaneRenameText },
                        set: { constructionPlaneRenameText = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .onSubmit {
                    commitConstructionPlaneRename()
                }
                .accessibilityLabel("Construction Plane Name")
                .accessibilityValue(constructionPlaneRenameText)
                .accessibilityIdentifier("WorkspacePlane.renameField.\(identifierSuffix)")
            } else {
                Button {
                    selectConstructionPlane(entry)
                } label: {
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select Construction Plane")
                .accessibilityLabel("Select \(entry.name)")
                .accessibilityValue(isSelected ? "Selected" : "Available")
                .accessibilityIdentifier("WorkspacePlane.select.\(identifierSuffix)")
            }

            Button {
                if isRenaming {
                    commitConstructionPlaneRename()
                } else {
                    beginConstructionPlaneRename(entry)
                }
            } label: {
                Image(systemName: isRenaming ? "checkmark" : "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.72))
            .help(isRenaming ? "Commit Construction Plane Name" : "Rename Construction Plane")
            .accessibilityLabel(
                isRenaming ? "Commit Construction Plane Name" : "Rename \(entry.name)"
            )
            .accessibilityIdentifier("WorkspacePlane.rename.\(identifierSuffix)")

            if isRenaming {
                Button {
                    cancelConstructionPlaneRename()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.56))
                .help("Cancel Construction Plane Rename")
                .accessibilityLabel("Cancel Construction Plane Rename")
                .accessibilityIdentifier("WorkspacePlane.renameCancel.\(identifierSuffix)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isSelected || entry.isActive
                        ? Color.accentColor.opacity(isSelected ? 0.18 : 0.16)
                        : Color.primary.opacity(0.05)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected || entry.isActive
                        ? Color.accentColor.opacity(isSelected ? 0.62 : 0.38)
                        : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !isRenaming {
                    activateAndAlignConstructionPlane(entry)
                }
            }
        )
    }

    private func workspaceSavedViewRow(
        _ savedView: SavedView
    ) -> some View {
        let identifierSuffix = String(describing: savedView.id)
        return HStack(spacing: 6) {
            Button {
                applySavedView(savedView)
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Apply Saved View")
            .accessibilityLabel("Apply \(savedView.name)")
            .accessibilityIdentifier("WorkspaceSavedView.apply.\(identifierSuffix)")

            Button {
                applySavedView(savedView)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(savedView.name)
                        .font(.caption)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(savedViewBuilder.projectionTitle(for: savedView)) · \(savedViewBuilder.scaleTitle(for: savedView))")
                        .font(.caption2)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Apply Saved View")
            .accessibilityLabel("Apply \(savedView.name)")
            .accessibilityValue(savedViewBuilder.scaleTitle(for: savedView))
            .accessibilityIdentifier("WorkspaceSavedView.select.\(identifierSuffix)")

            Button {
                updateSavedViewFromCurrentViewport(savedView)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.68))
            .help("Update Saved View From Current View")
            .accessibilityLabel("Update \(savedView.name) From Current View")
            .accessibilityIdentifier("WorkspaceSavedView.update.\(identifierSuffix)")
            .disabled(!viewportCameraState.isReady)

            Button {
                removeSavedView(savedView)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.58))
            .help("Remove Saved View")
            .accessibilityLabel("Remove \(savedView.name)")
            .accessibilityIdentifier("WorkspaceSavedView.remove.\(identifierSuffix)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var workspaceSketchDimensionInputField: some View {
        if let focus = sketchInputState.dimensionInputFocus {
            HStack(spacing: 5) {
                Text(focus.statusTitle)
                    .foregroundStyle(.secondary)
                switch focus {
                case .length:
                    TextField(
                        focus.statusTitle,
                        text: workspaceSketchLengthInputBinding
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    Text(sketchDimensionLengthUnitSymbol(sketchInputState.dimensionInputLengthMeters))
                        .foregroundStyle(.secondary)
                case .angle:
                    TextField(
                        focus.statusTitle,
                        value: workspaceSketchAngleInputBinding,
                        formatter: inspectorNumberFormatter
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 54)
                    Text("deg")
                        .foregroundStyle(.secondary)
                case .width:
                    TextField(
                        focus.statusTitle,
                        text: workspaceSketchWidthInputBinding
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    Text(sketchDimensionLengthUnitSymbol(sketchInputState.dimensionInputWidthMeters))
                        .foregroundStyle(.secondary)
                case .height:
                    TextField(
                        focus.statusTitle,
                        text: workspaceSketchHeightInputBinding
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    Text(sketchDimensionLengthUnitSymbol(sketchInputState.dimensionInputHeightMeters))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("WorkspaceSketch.dimensionInputField")
        }
    }

    private var workspaceSketchLengthInputBinding: Binding<String> {
        Binding<String>(
            get: {
                sketchDimensionLengthInputText(sketchInputState.dimensionInputLengthMeters)
            },
            set: { text in
                setSketchDimensionInputLength(
                    text,
                    currentMeters: sketchInputState.dimensionInputLengthMeters
                )
            }
        )
    }

    private var workspaceSketchAngleInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                guard let angleRadians = sketchInputState.dimensionInputAngleRadians else {
                    return 0.0
                }
                return angleRadians * 180.0 / Double.pi
            },
            set: { value in
                _ = setSketchDimensionInputAngle(value * Double.pi / 180.0)
            }
        )
    }

    private var workspaceSketchWidthInputBinding: Binding<String> {
        Binding<String>(
            get: {
                sketchDimensionLengthInputText(sketchInputState.dimensionInputWidthMeters)
            },
            set: { text in
                setSketchDimensionInputWidth(
                    text,
                    currentMeters: sketchInputState.dimensionInputWidthMeters
                )
            }
        )
    }

    private var workspaceSketchHeightInputBinding: Binding<String> {
        Binding<String>(
            get: {
                sketchDimensionLengthInputText(sketchInputState.dimensionInputHeightMeters)
            },
            set: { text in
                setSketchDimensionInputHeight(
                    text,
                    currentMeters: sketchInputState.dimensionInputHeightMeters
                )
            }
        )
    }

    @ViewBuilder
    private var workspaceDimensionInputField: some View {
        if let entry = dimensionCommandState.activeEntry {
            let currentValue = dimensionCommandState.currentValue ?? entry.resolvedValue
            HStack(spacing: 5) {
                Text(entry.label)
                    .foregroundStyle(.secondary)
                TextField(
                    entry.label,
                    text: workspaceDimensionInputBinding
                )
                .multilineTextAlignment(.trailing)
                .frame(width: 86)
                Text(dimensionInputUnitSymbol(entry.valueKind, value: currentValue))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("WorkspaceDimension.inputField")
        }
    }

    private var workspaceDimensionInputBinding: Binding<String> {
        Binding<String>(
            get: {
                guard let entry = dimensionCommandState.activeEntry else {
                    return ""
                }
                return dimensionInputText(
                    dimensionCommandState.currentValue ?? 0.0,
                    kind: entry.valueKind
                )
            },
            set: { text in
                guard let entry = dimensionCommandState.activeEntry else {
                    return
                }
                let currentValue = dimensionCommandState.currentValue ?? entry.resolvedValue
                dimensionCommandState.setDraftText(
                    text,
                    defaultUnit: dimensionInputDefaultUnit(entry.valueKind, value: currentValue)
                )
            }
        )
    }

    private func sketchDimensionLengthInputText(_ meters: Double?) -> String {
        workspaceLengthFieldPresentation(
            fromMeters: meters ?? 0.0,
            preferredUnit: snapshot.workspaceState.displayUnit
        ).text
    }

    private func sketchDimensionLengthUnitSymbol(_ meters: Double?) -> String {
        sketchDimensionLengthDefaultUnit(meters).symbol
    }

    private func sketchDimensionLengthDefaultUnit(_ meters: Double?) -> LengthDisplayUnit {
        guard let meters else {
            return snapshot.workspaceState.displayUnit
        }
        return workspaceLengthFieldPresentation(
            fromMeters: meters,
            preferredUnit: snapshot.workspaceState.displayUnit
        ).unit
    }

    private func setSketchDimensionInputLength(
        _ text: String,
        currentMeters: Double?
    ) {
        guard let meters = workspaceLengthMeters(
            fromFieldText: text,
            defaultUnit: sketchDimensionLengthDefaultUnit(currentMeters)
        ) else {
            return
        }
        _ = setSketchDimensionInputLength(meters)
    }

    private func setSketchDimensionInputWidth(
        _ text: String,
        currentMeters: Double?
    ) {
        guard let meters = workspaceLengthMeters(
            fromFieldText: text,
            defaultUnit: sketchDimensionLengthDefaultUnit(currentMeters)
        ) else {
            return
        }
        _ = setSketchDimensionInputWidth(meters)
    }

    private func setSketchDimensionInputHeight(
        _ text: String,
        currentMeters: Double?
    ) {
        guard let meters = workspaceLengthMeters(
            fromFieldText: text,
            defaultUnit: sketchDimensionLengthDefaultUnit(currentMeters)
        ) else {
            return
        }
        _ = setSketchDimensionInputHeight(meters)
    }

    private func sweepPreviewFeatureLabel(_ featureID: FeatureID?) -> String {
        featureID.map { WorkspaceInspectorNumberText.shortID($0) } ?? "Missing"
    }

    private func sweepPreviewSectionLabel(_ section: SectionReference?) -> String {
        guard let section else {
            return "Missing"
        }
        return sweepSectionSummary(section)
    }

    private var evaluationStatusSystemImage: String {
        switch snapshot.evaluationSnapshot.status {
        case .notEvaluated:
            "circle.dashed"
        case .valid:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var evaluationStatusTint: Color {
        switch snapshot.evaluationSnapshot.status {
        case .notEvaluated:
            .secondary
        case .valid:
            .green
        case .failed:
            .red
        }
    }

    private func activateSolidShape(_ shape: WorkspaceSolidShape) {
        cancelModelingOperation()
        solidShape = shape
        activateTool(.solid)
    }

    private func activateTool(_ tool: ModelingTool) {
        isWorkspaceFocused = true
        measurementSeed = tool == .measure ? selectedCurveMeasurementSeed() : nil
        let hasTransientModelingOperation = modelingDraft != nil
            || meshDraft != nil
            || historyPreviewTitle != nil
            || modelingPreview.payload != nil
        if hasTransientModelingOperation,
           tool != .surface,
           (tool != selectedTool || tool == .select) {
            cancelModelingOperation()
        }
        if tool == .surface {
            beginSurfaceModelingOperation()
            return
        }
        if tool != .select {
            setHoveredSceneNode(nil)
            regionOffsetCommandState.deactivate()
            edgeOffsetCommandState.deactivate()
            slotProfileCommandState.deactivate()
            viewAlignedConstructionPlaneRequest = nil
            // A point pick belongs to the select tool; another tool's clicks are its own.
            pointPickRequest = nil
            placeSession = nil
            transformSession = nil
            mirrorSession = nil
            arraySession = nil
        }
        setActiveTool(tool)
        reportToolStatus(tool == .solid ? solidShape.activationPrompt : tool.activationPrompt)
    }

    private func beginSurfaceModelingOperation() {
        cancelModelingOperation()
        curvePickCommand = nil
        cutCurveSession = nil
        filletSession = nil
        var draft = ModelingOperationDraft(
            kind: .surfacePatch,
            selection: snapshot.selection,
            ruler: snapshot.workspaceState.ruler
        )
        draft.isSurfaceCreation = true
        modelingDraft = draft
        selectedTool = .select
        reportToolStatus(
            "Surface: \(ModelingTool.surface.activationPrompt) Cancel discards the draft."
        )
    }

    private func canvasToolIdentifier(for tool: ModelingTool) -> String {
        "CanvasTool.\(tool.rawValue)"
    }

    /// Who a viewport press belongs to: the running command that takes clicks, in the order a
    /// click reaches it, else direct editing in the selection scope under the select tool.
    /// `handleViewportPick`, the hit policy and every affordance handler read this one value.
    private var viewportPointerOwner: WorkspaceViewportPointerOwner {
        let scopePolicy = selectionScope.viewportSelectionHitPolicy
        let transforming = transformSession != nil
        if viewAlignedConstructionPlaneRequest != nil {
            return .pickingCommand(.viewAlignedConstructionPlane, hitPolicy: scopePolicy, scope: selectionScope, transforming: transforming)
        }
        if selectedTool == .select {
            if curvePickCommand != nil {
                return .pickingCommand(.curvePick, hitPolicy: scopePolicy, scope: selectionScope, transforming: transforming)
            }
            if let cutCurveSession {
                return .pickingCommand(.cutCurve, hitPolicy: cutCurveSession.viewportHitPolicy, scope: selectionScope, transforming: transforming)
            }
            if booleanSession != nil {
                return .pickingCommand(.boolean, hitPolicy: scopePolicy, scope: selectionScope, transforming: transforming)
            }
            if let bodyCutSession {
                return .pickingCommand(.bodyCut, hitPolicy: bodyCutSession.viewportHitPolicy, scope: selectionScope, transforming: transforming)
            }
            if let deformSession {
                return .pickingCommand(.deform, hitPolicy: deformSession.viewportHitPolicy, scope: selectionScope, transforming: transforming)
            }
            if slotProfileCommandState.isCurveOffsetActive, slotProfileCommandState.isFreestyle {
                return .pickingCommand(.freestyleOffset, hitPolicy: scopePolicy, scope: selectionScope, transforming: transforming)
            }
        }
        if modelingDraft?.kind == .constrainedSurface {
            return .pickingCommand(.constrainedSurfacePoints, hitPolicy: scopePolicy, scope: selectionScope, transforming: transforming)
        }
        if selectedTool == .select {
            return .directEditing(selectionScope)
        }
        return .tool(selectedTool, scope: selectionScope)
    }

    /// Hands a click to the running command that owns the viewport's clicks.
    private func routeViewportPick(_ target: ViewportCanvasTarget, to command: WorkspaceViewportPickingCommand) {
        switch command {
        case .viewAlignedConstructionPlane:
            guard let request = viewAlignedConstructionPlaneRequest else { return }
            createViewAlignedConstructionPlane(from: target, request: request)
        case .curvePick:
            guard let curvePickCommand else { return }
            applyCurvePick(curvePickCommand, at: target)
        case .cutCurve:
            pickCutCurve(at: target)
        case .boolean:
            pickBooleanBody(at: target)
        case .bodyCut:
            pickBodyCutOperand(at: target)
        case .deform:
            pickDeformFace(at: target)
        case .freestyleOffset:
            pickFreestyleOffset(at: target)
        case .constrainedSurfacePoints:
            let plane = effectiveSketchPlane(fallback: target.sketchPlane)
            guard let input = mappedCanvasInput(modelPoint: target.modelPoint,
                modelWorldPoint: target.modelWorldPoint,
                viewRayAnchorWorldPoint: target.viewRayAnchorWorldPoint, sketchPlane: plane) else { return }
            let snapped = snappedModelInput(input.point, modifierFlags: target.modifierFlags)
            guard let point = resolvedCanvasWorldPoint(for: snapped.point,
                snappedWorldPoint: snapped.worldPoint, fallbackWorldPoint: input.worldPoint,
                sketchPlane: plane) else { return }
            do { try modelingDraft?.appendWorldPoint(point, in: snapshot.document.document) }
            catch { reportToolStatus(error.localizedDescription, severity: .warning) }
        }
    }

    private func handleViewportPick(_ target: ViewportCanvasTarget) {
        if let command = viewportPointerOwner.pickingCommand {
            routeViewportPick(target, to: command)
            return
        }

        if selectedTool == .select {
            applyViewportSelection(hit: target.hit, intent: target.selectionIntent)
            return
        }

        let resolvesObjectTargets = isObjectTargetingEnabled
            || target.modifierFlags.containsControl
            || selectedTool == .mesh
        let effectiveHit = resolvesObjectTargets ? target.hit : nil
        let targetSceneNodeID: SceneNodeID?
        if let hit = effectiveHit {
            guard let sceneNodeID = selectionTargetResolver.sceneNodeID(for: hit) else {
                reportToolStatus(
                    "Viewport selection could not resolve a scene node.",
                    severity: .warning
                )
                return
            }
            targetSceneNodeID = sceneNodeID
        } else {
            targetSceneNodeID = nil
        }

        if selectedTool == .mesh {
            routeCanvasMesh(targetSceneNodeID)
            return
        }

        let sketchPlane = effectiveSketchPlane(fallback: target.sketchPlane)
        guard let canvasInput = mappedCanvasInput(
            modelPoint: target.modelPoint,
            modelWorldPoint: target.modelWorldPoint,
            viewRayAnchorWorldPoint: target.viewRayAnchorWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        let snappedInput = snappedModelInput(canvasInput.point, modifierFlags: target.modifierFlags)
        let worldPoint = resolvedCanvasWorldPoint(
            for: snappedInput.point,
            snappedWorldPoint: snappedInput.worldPoint,
            fallbackWorldPoint: canvasInput.worldPoint,
            sketchPlane: sketchPlane
        )
        let tool = selectedTool
        let polygonState = polygonToolState
        let currentSketchInputState = sketchInputState
        let placementCellMeters = viewportProjectedGridMinorStep?.meters
        let currentSolidShape = solidShape
        submitSource(name: "canvasClick") { current in
            let planner = WorkspaceCanvasCommandPlanner(
                context: WorkspaceCanvasCommandPlanner.Context(
                    document: current.document.document,
                    selection: current.selection,
                    workspaceState: current.workspaceState,
                    objectRegistry: current.objectRegistry,
                    polygonState: polygonState,
                    sketchInputState: currentSketchInputState
                ),
                solidShape: currentSolidShape
            )
            do {
                guard let command = try planner.clickCommand(
                    tool: tool,
                    targetSceneNodeID: targetSceneNodeID,
                    modelPoint: snappedInput.point,
                    modelWorldPoint: worldPoint,
                    sketchPlane: sketchPlane,
                    placementCellMeters: placementCellMeters
                ) else {
                    return []
                }
                return [command]
            } catch let failure as CanvasSketchCurveDrafts.Failure {
                throw EditorError(code: .commandInvalid, message: failure.message)
            }
        } completion: { results in
            try await finishCanvasSourceCommand(results.last)
        }
    }

    private func routeCanvasMesh(_ targetSceneNodeID: SceneNodeID?) {
        guard let targetSceneNodeID,
              snapshot.document.document.productMetadata.sceneNodes[targetSceneNodeID] != nil else {
            reportToolStatus(
                "Mesh editing requires an Authored Mesh target. Select a Mesh or use Make Selected CAD Editable.",
                severity: .warning
            )
            return
        }

        let isAuthoredMesh = hasAuthoredMeshPresentation(for: targetSceneNodeID)
        let task = enqueueWorkspaceOperation {
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            var selection = current.selection
            try selection.selectSceneNode(targetSceneNodeID, in: current.document.document)
            _ = try await workspace.applySelection(.replace(selection))
            return true
        }

        Task { @MainActor in
            do {
                _ = try await task.value
                meshDraft = nil
                if isAuthoredMesh {
                    reportToolStatus("Mesh editing: select elements in the canvas, then Preview and Apply.")
                } else {
                    reportToolStatus(
                        "The selected object is CAD geometry. Use Make Selected CAD Editable to create an editable Mesh.",
                        severity: .warning
                    )
                }
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func hasAuthoredMeshPresentation(for sceneNodeID: SceneNodeID) -> Bool {
        snapshot.viewport.items.contains { item in
            guard snapshot.sceneNodeID(for: item.occurrenceID) == sceneNodeID else {
                return false
            }
            if case .authoredMesh = item.sourceReference {
                return true
            }
            return false
        }
    }

    private func finishCanvasSourceCommand(_ result: CommandExecutionResult?) async throws {
        guard result?.didMutate == true else {
            return
        }
        setActiveTool(.select)
        guard let current = workspace.view,
              let newestSceneNodeID = newestVisibleSceneNodeID(
                  in: current.document.document.productMetadata
              ) else {
            return
        }
        var selection = SelectionModel.empty
        try selection.selectSceneNode(
            newestSceneNodeID,
            in: current.document.document
        )
        _ = try await workspace.applySelection(.replace(selection))
    }

    private func newestVisibleSceneNodeID(
        in metadata: ProductMetadata
    ) -> SceneNodeID? {
        var newestID: SceneNodeID?
        func visit(_ id: SceneNodeID) {
            guard let node = metadata.sceneNodes[id] else {
                return
            }
            if node.isVisible {
                newestID = id
            }
            for childID in node.childIDs {
                visit(childID)
            }
        }
        for rootID in metadata.rootSceneNodeIDs {
            visit(rootID)
        }
        return newestID
    }

    private func handleDeleteSelection() -> Bool {
        handleWorkspaceKeyboardInput(WorkspaceKeyboardInput(isDelete: true)) == .handled
    }

    private func handleWorkspaceKeyboardInput(_ input: WorkspaceKeyboardInput) -> KeyPress.Result {
        if modelingDraft?.kind == .constrainedSurface, input.characters.lowercased() == "z",
           input.modifiers == .control, input.phases.contains(.down) {
            modelingDraft?.undoConstrainedPoint()
            return .handled
        }
        guard let action = WorkspaceKeyboardRouter().action(
            for: input,
            context: workspaceKeyboardContext(for: input)
        ) else {
            return .ignored
        }
        return applyWorkspaceKeyboardAction(action)
    }

    private func workspaceKeyboardContext(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardContext {
        WorkspaceKeyboardContext(
            isSelectToolActive: selectedTool == .select,
            isPolygonToolActive: selectedTool == .polygon,
            usesSketchAxisConstraint: usesSketchAxisConstraint,
            isDimensionCommandActive: dimensionCommandState.isActive,
            isSlotProfileCommandActive: slotProfileCommandState.isActive,
            isCurveOffsetCommandActive: slotProfileCommandState.isCurveOffsetActive,
            isEdgeOffsetCommandActive: edgeOffsetCommandState.isActive,
            isRegionOffsetCommandActive: regionOffsetCommandState.isActive,
            isCurveControlVertexSlideActive: slideCommandState.isCurveControlVerticesActive,
            isSurfaceControlVertexSlideActive: slideCommandState.isSurfaceControlVerticesActive,
            selectionScope: selectionScope,
            hasCurveControlVertexSlideInput: !input.isDelete
                && slideCommandState.isCurveControlVerticesActive
                && selectedSplineControlPointSlideInput() != nil,
            hasSurfaceControlVertexSlideTargets: !input.isDelete
                && slideCommandState.isSurfaceControlVerticesActive
                && (!selectedPolySplineSurfaceVertexTargets.isEmpty
                    || !selectedSurfaceControlPointReferences.isEmpty),
            isPlaceSessionActive: placeSession != nil,
            isTransformSessionActive: transformSession != nil,
            isMirrorSessionActive: mirrorSession != nil,
            isArrayCreationSessionActive: arraySession != nil,
            isSectionAnalysisSessionActive: sectionAnalysisSession != nil,
            isCurvePickCommandActive: curvePickCommand != nil,
            isCutCurveSessionActive: cutCurveSession != nil,
            isBooleanSessionActive: booleanSession != nil,
            isBodyCutSessionActive: bodyCutSession != nil,
            hasBodyObjectSelection: !selectedBodyObjectIDs.isEmpty,
            isFilletSessionActive: filletSession != nil,
            isRebuildSessionActive: rebuildSession != nil,
            isDeformSessionActive: deformSession != nil,
            isProjectSessionActive: projectSession != nil,
            isBridgeEdgeSessionActive: bridgeEdgeSession != nil,
            isCommandPaletteOpen: isCommandPaletteOpen,
            hasBridgeableSelection: bridgeAction != nil,
            hasSelectedBridgeCurve: selectedBridgeCurve != nil,
            isBridgeTensionInputActive: selectedBridgeCurve.map { bridgeTensionInput?.sourceID == $0.sourceID } ?? false,
            hasAlignableVertexPair: alignVertexAction != nil,
            hasProjectableSelection: !snapshot.selection.selectedTargets.isEmpty,
            selectedSketchTargetCount: selectedSketchTargets.count,
            hasWholeObjectSelection: selectionScope == .object && !snapshot.selection.wholeSceneNodeIDs.isEmpty,
            hasMovableTopologySelection: selectedMovableTopology != nil
        )
    }

    private func applyWorkspaceKeyboardAction(
        _ action: WorkspaceKeyboardAction
    ) -> KeyPress.Result {
        switch action {
        case .deleteSelection:
            let ids = snapshot.selection.wholeSceneNodeIDs
            guard ids.isEmpty == false else {
                guard snapshot.selection.selectedTargets.isEmpty == false else {
                    return .ignored
                }
                reportToolStatus(
                    "Delete removes whole objects. The selection holds only sub-object targets.",
                    severity: .warning
                )
                return .handled
            }
            deleteSceneNodes(ids)
            return .handled
        case .focusPlaceOption(let field):
            focusedPlaceOption = field
            return .handled
        case .togglePlaceFlip:
            placeSession?.flipsOrientation.toggle()
            reportPlaceOptions()
            return .handled
        case .togglePlaceOutput:
            guard placeSession?.allowsInstances == true else {
                reportToolStatus("Pasted objects are placed as independent copies.", severity: .warning)
                return .handled
            }
            placeSession?.output = placeSession?.output == .componentInstance ? .independentCopy : .componentInstance
            if placeSession?.output == .componentInstance {
                placeSession?.booleanOperation = nil
            }
            reportPlaceOptions()
            return .handled
        case .setPlaceUpAxis(let axis):
            placeSession?.upAxis = axis
            reportPlaceOptions()
            return .handled
        case .addPlaceCopy:
            placeSession?.copyCount += 1
            reportPlaceOptions()
            return .handled
        case .transformMode(let mode):
            if transformSession == nil, let movable = selectedMovableTopology {
                beginTopologyMoveSession(movable.kind, targets: movable.targets, mode: mode)
            } else if transformSession == nil {
                beginTransformSession(mode, sceneNodeIDs: snapshot.selection.wholeSceneNodeIDs)
            } else {
                transformSession?.press(mode: mode)
                reportTransformOptions()
            }
            return .handled
        case .constrainTransform(let axis, let plane):
            transformSession?.press(axis: axis, plane: plane)
            reportTransformOptions()
            return .handled
        case .cycleTransformOrientation:
            transformSession?.cycleOrientation()
            refreshTransformFrame()
            reportTransformOptions()
            return .handled
        case .pickTransformPivot:
            transformSession?.pendingPoint = .pivot
            reportToolStatus(transformSession?.prompt ?? "")
            return .handled
        case .removeTransformPivot:
            transformSession?.removePivot()
            refreshTransformFrame()
            reportTransformOptions()
            return .handled
        case .beginTransformFreestyle:
            transformSession?.beginFreestyle()
            reportToolStatus(transformSession?.prompt ?? "")
            return .handled
        case .finishTransform:
            finishTransformSession()
            return .handled
        case .beginMirror:
            beginMirrorSession(sceneNodeIDs: snapshot.selection.wholeSceneNodeIDs)
            return .handled
        case .chooseMirrorAxis(let axis, let positive):
            do {
                try mirrorSession?.choose(axis: axis, positive: positive, constructionPlane: mirrorConstructionPlane)
                reportToolStatus(mirrorSession?.prompt ?? "")
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
            return .handled
        case .toggleMirrorInstances:
            mirrorSession?.toggleInstances()
            reportMirrorOptions()
            return .handled
        case .toggleMirrorUnion:
            mirrorSession?.toggleUnion()
            reportMirrorOptions()
            return .handled
        case .beginMirrorFreestyle:
            mirrorSession?.beginFreestyle()
            reportToolStatus(mirrorSession?.prompt ?? "")
            return .handled
        case .applyMirror:
            applyMirror()
            return .handled
        case .setArrayAxis(let axis):
            updateArrayInSession { shaping, source, frame in
                try shaping.distribution(of: source, alongWorldAxis: axis, patternFrame: frame)
            }
            return .handled
        case .toggleArrayInstances:
            guard let arraySession,
                  let source = snapshot.document.document.productMetadata.patternArrays[arraySession.sourceID] else {
                return .handled
            }
            let mode: PatternArrayOutputMode = source.outputMode == .componentInstance ? .independentCopy : .componentInstance
            submitSource(.updatePatternArray(id: source.id, name: nil, definitionID: nil, distribution: nil, outputMode: mode))
            reportToolStatus(mode == .componentInstance ? "Array: instances." : "Array: independent copies.")
            return .handled
        case .pickArraySecondDirection:
            arraySession?.pickSecondDirection()
            reportToolStatus(arraySession?.prompt ?? "")
            return .handled
        case .activateMeasure:
            activateTool(.measure)
            return .handled
        case .setMaterial, .forkMaterial, .removeMaterial:
            let ids = snapshot.selection.wholeSceneNodeIDs
            let command: EditorCommand
            let status: String
            switch action {
            case .setMaterial:
                command = .assignMaterial(ids: ids, materialID: nil)
                status = "Set Material: edit the material in the Properties inspector."
            case .forkMaterial:
                command = .forkMaterial(ids: ids)
                status = "Forked the material; edit the copy in the Properties inspector."
            default:
                command = .removeMaterial(ids: ids)
                status = "Removed the material."
            }
            submitSource(command) { result in
                guard result != nil else { return }
                inspectorTab = .properties
                reportToolStatus(status)
            }
            return .handled
        case .finishArrayCreation:
            arraySession = nil
            reportToolStatus("Array finished.")
            return .handled
        case .focusSectionAnalysisDistance:
            isSectionDistanceFocused = true
            return .handled
        case .flipSectionAnalysis:
            sectionAnalysisSession?.toggleFlip()
            return .handled
        case .confirmSectionAnalysis:
            confirmSectionAnalysis()
            return .handled
        case .confirmWorkspaceCommand:
            _ = confirmActiveWorkspaceCommand()
            return .handled
        case .setPlaceBoolean(let operation):
            placeSession?.booleanOperation = operation
            if operation != nil {
                placeSession?.output = .independentCopy
            }
            reportPlaceOptions()
            return .handled
        case .duplicateSelection:
            let ids = snapshot.selection.wholeSceneNodeIDs
            guard ids.isEmpty == false else {
                guard snapshot.selection.selectedTargets.isEmpty == false else {
                    return .ignored
                }
                reportToolStatus(
                    "Duplicate copies whole objects. The selection holds only sub-object targets.",
                    severity: .warning
                )
                return .handled
            }
            duplicateSceneNodes(ids)
            return .handled
        case .cancelActiveInteraction:
            return cancelActiveWorkspaceInteraction()
        case .setSelectionScope(let scope):
            guard scope.isEnabled else {
                return .ignored
            }
            selectionScope = scope
            return .handled
        case .beginSnapCandidateKindBypass:
            return snapOverrideState.beginCandidateKindBypass() ? .handled : .ignored
        case .endSnapCandidateKindBypass:
            snapOverrideState.endCandidateKindBypass()
            return .handled
        case .createConstructionPlane(let alignsView):
            return createConstructionPlaneFromSelectedTargets(alignsView: alignsView)
        case .createViewAlignedConstructionPlane(let pickOrigin):
            return createViewAlignedConstructionPlaneFromKeyboard(pickOrigin: pickOrigin)
        case .activateDimensionCommand:
            activateDimensionCommand()
            return .handled
        case .advanceDimensionInputRoute:
            dimensionCommandState.handleTab()
            return .handled
        case .commitDimensionCommand:
            commitDimensionCommand()
            return .handled
        case .cancelDimensionCommand:
            dimensionCommandState.deactivate()
            return .handled
        case .focusNextSketchDimensionInput:
            _ = focusNextSketchDimensionInput(
                availableFocuses: activeSketchDimensionInputFocuses
            )
            return .handled
        case .activateOffsetCommand:
            if selectedEdgeTargets.isEmpty == false {
                activateEdgeOffsetCommand()
            } else if selectedRegionTargets.isEmpty == false {
                activateRegionOffsetCommand()
            } else if selectedSketchVertexOffsetTarget != nil {
                activateVertexOffsetCommand()
            } else if selectedCurveOffsetTarget != nil {
                activateSlotProfileCommand()
            } else {
                activateRegionOffsetCommand()
            }
            return .handled
        case .activateSlotWidthInput:
            slotProfileCommandState.activateWidthInput()
            focusedCommandDistance = .curveOffset
            return .handled
        case .toggleCurveOffsetSymmetric:
            slotProfileCommandState.toggleSymmetric()
            return .handled
        case .toggleCurveOffsetFreestyle:
            slotProfileCommandState.toggleFreestyle()
            reportToolStatus(slotProfileCommandState.isFreestyle
                ? "Offset Freestyle: click where the offset passes, then Return or right-click."
                : "Offset: type the distance.")
            return .handled
        case .activateEdgeOffsetDistanceInput:
            edgeOffsetCommandState.activateDistanceInput()
            focusedCommandDistance = .edgeOffset
            return .handled
        case .activateRegionOffsetDistanceInput:
            regionOffsetCommandState.activateDistanceInput()
            focusedCommandDistance = .regionOffset
            return .handled
        case .cycleCurveOffsetGapFill:
            curveOffsetGapFill = edgeOffsetCommandState.gapFill(after: curveOffsetGapFill)
            reportToolStatus("Offset: gap fill \(regionOffsetGapFillTitle(curveOffsetGapFill)).")
            return .handled
        case .cycleEdgeOffsetGapFill:
            edgeOffsetGapFill = edgeOffsetCommandState.gapFill(after: edgeOffsetGapFill)
            return .handled
        case .cycleRegionOffsetGapFill:
            regionOffsetGapFill = regionOffsetCommandState.gapFill(after: regionOffsetGapFill)
            return .handled
        case .toggleEdgeOffsetLockedDistance:
            edgeOffsetCommandState.toggleLockedDistance()
            return .handled
        case .toggleRegionOffsetLockedDistance:
            regionOffsetCommandState.toggleLockedDistance()
            return .handled
        case .toggleCombinedRegions:
            regionOffsetCommandState.toggleCombinedRegions()
            if regionOffsetCommandState.usesCombinedRegions,
               selectedRegionTargets.count < 2 {
                reportToolStatus(
                    "Combined Offset Region requires multiple selected regions.",
                    severity: .warning
                )
            }
            return .handled
        case .activateSlideCommand:
            activateSlideCommand()
            return .handled
        case .activateTrimCommand:
            beginCurvePickCommand(.trim)
            return .handled
        case .beginFillet:
            guard let fillet = WorkspaceFilletSession(
                selectedSketchTargets: selectedSketchTargets, treatment: sketchCornerTreatment
            ) else {
                reportToolStatus("Fillet: select sketch curves or curve ends.", severity: .warning)
                return .handled
            }
            curvePickCommand = nil
            cutCurveSession = nil
            filletSession = fillet
            reportToolStatus("\(fillet.title): D types the distance, C switches Fillet and Chamfer, Return applies.")
            return .handled
        case .focusFilletDistance:
            focusedCommandDistance = .cornerTreatment
            return .handled
        case .toggleFilletTreatment:
            filletSession?.toggleTreatment()
            if let filletSession { reportToolStatus("\(filletSession.title).") }
            return .handled
        case .confirmFillet:
            confirmFillet()
            return .handled
        case .cancelFillet:
            filletSession = nil
            reportToolStatus("Fillet ended.")
            return .handled
        case .joinSketchCurves:
            let targets = selectedSketchTargets
            guard targets.count >= 2 else { return .ignored }
            if targets.count == 2 {
                submitSource(
                    .joinSketchCurves(
                        target: targets[0],
                        adjacentTarget: targets[1],
                        continuity: sketchCurveJoinContinuity
                    )
                )
            } else {
                submitSource(.joinSketchCurveChain(targets: targets, continuity: sketchCurveJoinContinuity))
            }
            return .handled
        case .unjoinSketchCurve:
            guard let target = selectedSketchTargets.first else { return .ignored }
            submitSource(.unjoinSketchCurve(target: target))
            return .handled
        case .raiseCurveDegree:
            guard let action = raiseCurveDegreeAction else { return .ignored }
            action()
            return .handled
        case .confirmRebuild:
            confirmRebuild()
            return .handled
        case .cancelRebuild:
            rebuildSession = nil
            reportToolStatus("Rebuild ended.")
            return .handled
        case .confirmDeform:
            confirmDeform()
            return .handled
        case .cancelDeform:
            deformSession = nil
            reportToolStatus("Deform ended.")
            return .handled
        case .confirmProject:
            confirmProject()
            return .handled
        case .cancelProject:
            projectSession = nil
            reportToolStatus("Project ended.")
            return .handled
        case .confirmBridgeEdge:
            confirmBridgeEdge()
            return .handled
        case .cancelBridgeEdge:
            bridgeEdgeSession = nil
            reportToolStatus("Bridge Edge ended.")
            return .handled
        case .cycleBridgeContinuity:
            guard let bridgeCurve = selectedBridgeCurve else { return .ignored }
            let order = BridgeCurveEndpointContinuity.allCases
            let next = order[(order.firstIndex(of: bridgeCurve.continuity.first).map { $0 + 1 } ?? 0) % order.count]
            submitSource(
                .setBridgeCurveParameters(
                    sourceID: bridgeCurve.sourceID,
                    firstEndpoint: nil,
                    secondEndpoint: nil,
                    continuity: BridgeCurveContinuity(first: next, second: next)
                )
            )
            reportToolStatus("Bridge continuity: \(next.rawValue.uppercased()).")
            return .handled
        case .projectToConstructionPlane:
            // Alternative Duplicate on faces: a solid of faces that close, else a sheet, then Move.
            let faces = snapshot.selection.selectedTargets.filter { target in
                if case .face = target.component { return true }
                return false
            }
            if !faces.isEmpty, faces.count == snapshot.selection.selectedTargets.count {
                submitSource(.duplicateBodyFaces(name: "Alternative Duplicate", targets: faces)) { result in
                    moveCreatedObjects(of: result)
                }
                return .handled
            }
            let curves = snapshot.selection.selectedTargets.filter { target in
                switch target.component {
                case .sketchEntity, .edge: return true
                default: return false
                }
            }
            if !curves.isEmpty {
                submitSource(
                    .projectSketchCurvesToConstructionPlane(
                        targets: curves,
                        plane: activeSketchPlane(),
                        name: nil
                    )
                ) { result in
                    moveCreatedObjects(of: result)
                }
                return .handled
            }
            let bodies = bodyOutlineProjectionTargets(from: selectedSceneNodes)
            guard !bodies.isEmpty else {
                reportToolStatus("Option-D duplicates faces, or projects curves, edges or bodies onto the construction plane.", severity: .warning)
                return .handled
            }
            projectSelectedBodyOutlinesToConstructionPlane(bodies)
            return .handled
        case .projectCurvesOntoFace:
            let selected = snapshot.selection.selectedTargets
            // Two whole bodies: Project Body Body, the curves where they meet.
            let bodyIntersectionTargets = selected.filter { target in
                target.component == .object
                    && snapshot.document.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.kind == .body
            }
            if bodyIntersectionTargets.count == 2, selected.count == 2 {
                submitSource(.projectBodyIntersection(first: bodyIntersectionTargets[0], second: bodyIntersectionTargets[1]))
                return .handled
            }
            let faces = selected.filter { if case .face = $0.component { return true }; return false }
            // Two sketch curves and nothing else: Project Curve Curve, where their extrusions meet.
            let curveIntersectionTargets = selectedSketchCurveTargets
            if faces.isEmpty, curveIntersectionTargets.count == 2, selected.count == 2 {
                submitSource(.projectCurveIntersection(first: curveIntersectionTargets[0], second: curveIntersectionTargets[1]))
                return .handled
            }
            let curves = selected.filter { target in
                switch target.component {
                case .sketchEntity, .edge: return true
                default: return false
                }
            }
            guard faces.count == 1, !curves.isEmpty else {
                reportToolStatus("Project: select curves and one face, two bodies or two curves.", severity: .warning)
                return .handled
            }
            guard let project = WorkspaceProjectSession(curves: curves, face: faces[0]) else { return .handled }
            projectSession = project
            reportToolStatus("Project: choose Normal or Vector, then OK, Return or right-click.")
            return .handled
        case .trimBridgeSources:
            guard let bridgeCurve = selectedBridgeCurve else { return .ignored }
            trimBridgeCurveSources(bridgeCurve)
            return .handled
        case .focusBridgeTension:
            guard let bridgeCurve = selectedBridgeCurve else { return .ignored }
            bridgeTensionInput = (bridgeCurve.sourceID, bridgeTensionValue(for: bridgeCurve))
            focusedCommandDistance = .bridgeTension
            reportToolStatus("Bridge: type the G1 tension; Return applies it to both ends.")
            return .handled
        case .applyBridgeTension:
            guard let bridgeCurve = selectedBridgeCurve else { return .ignored }
            applyBridgeG1Tension(bridgeCurve)
            return .handled
        case .cancelBridgeTension:
            bridgeTensionInput = nil
            return .handled
        case .bridgeSelection:
            guard let bridgeAction else {
                reportToolStatus("Bridge: select two sketch curves or two curve ends.", severity: .warning)
                return .handled
            }
            bridgeAction()
            return .handled
        case .beginCutCurve:
            beginCutCurve()
            return .handled
        case .beginBoolean:
            beginBoolean()
            return .handled
        case .setBooleanOperation(let operation):
            booleanSession?.setOperation(operation)
            if let prompt = booleanSession?.prompt { reportToolStatus(prompt) }
            return .handled
        case .toggleBooleanKeepTools:
            booleanSession?.keepTools.toggle()
            reportToolStatus("Boolean: Keep Tools \(booleanSession?.keepTools == true ? "on" : "off").")
            return .handled
        case .transformBooleanTools(let mode):
            transformBooleanTools(mode)
            return .handled
        case .confirmBoolean:
            confirmBoolean()
            return .handled
        case .cancelBoolean:
            booleanSession = nil
            reportToolStatus("Boolean ended.")
            return .handled
        case .beginBodyCut:
            beginBodyCut()
            return .handled
        case .switchBodyCutToCutCurve:
            bodyCutSession = nil
            beginCutCurve()
            return .handled
        case .toggleBodyCutViewDirection:
            toggleBodyCutViewDirection()
            return .handled
        case .toggleBodyCutExtend:
            bodyCutSession?.extendsCurves.toggle()
            reportToolStatus("Cut: Extend \(bodyCutSession?.extendsCurves == true ? "on" : "off").")
            return .handled
        case .confirmBodyCut:
            confirmBodyCut()
            return .handled
        case .cancelBodyCut:
            bodyCutSession = nil
            reportToolStatus("Cut ended.")
            return .handled
        case .cycleAlignContinuity:
            sketchVertexAlignmentContinuity = sketchVertexAlignmentContinuity.next
            reportToolStatus("Align Vertex: \(sketchVertexAlignmentContinuity.rawValue.uppercased()).")
            return .handled
        case .openCommandPalette:
            isCommandPaletteOpen = true
            return .handled
        case .closeCommandPalette:
            isCommandPaletteOpen = false
            isWorkspaceFocused = true
            return .handled
        case .toggleCutCurveScreenSpace:
            cutCurveSession?.usesScreenSpace.toggle()
            reportToolStatus("Cut Curve: Screen space \(cutCurveSession?.usesScreenSpace == true ? "on" : "off").")
            return .handled
        case .toggleCutCurveExtend:
            cutCurveSession?.extendsCutter.toggle()
            reportToolStatus("Cut Curve: Extend \(cutCurveSession?.extendsCutter == true ? "on" : "off").")
            return .handled
        case .confirmCutCurve:
            confirmCutCurve()
            return .handled
        case .cancelCutCurve:
            cutCurveSession = nil
            reportToolStatus("Cut Curve ended.")
            return .handled
        case .endCurvePickCommand:
            if let command = curvePickCommand { reportToolStatus("\(command.title) ended.") }
            curvePickCommand = nil
            return .handled
        case .slideCurveControlVertices(let direction):
            guard let input = selectedSplineControlPointSlideInput() else {
                return .ignored
            }
            slideSelectedSplineControlPoints(
                input.target,
                controlPointIndexes: input.controlPointIndexes,
                direction: direction
            )
            return .handled
        case .slideSurfaceControlVertices(let direction):
            let referenceTargets = selectedSurfaceControlPointReferences
            if referenceTargets.isEmpty == false {
                slideSelectedSurfaceControlPoints(referenceTargets, direction: direction)
                return .handled
            }
            let vertexTargets = selectedPolySplineSurfaceVertexTargets
            guard vertexTargets.isEmpty == false else {
                return .ignored
            }
            slideSelectedPolySplineSurfaceVertices(vertexTargets, direction: direction)
            return .handled
        case .adjustPolygonSideCount(let offset):
            _ = adjustPolygonSideCount(by: offset)
            return .handled
        case .toggleSketchAxisConstraint(let axisConstraint):
            _ = toggleSketchAxisConstraint(axisConstraint)
            return .handled
        case .togglePolygonSizingMode:
            _ = togglePolygonSizingMode()
            return .handled
        case .togglePolygonInclinationMode:
            _ = togglePolygonInclinationMode()
            return .handled
        case .togglePolygonCutsFaces:
            _ = togglePolygonCutsFaces()
            return .handled
        }
    }

    /// Backs out of one layer of whatever the workspace is in the middle of.
    ///
    /// The layers are ordered by how recently the user chose them. A running
    /// command is the most likely thing Escape means, and the selection it was
    /// working on survives so the command can be started again. A draft is next,
    /// because a tool that opened one and returned to Select leaves the draft
    /// reachable only through the panel that opened it. With nothing running the
    /// tool itself is the mode the user is stuck inside, and only then does
    /// Escape mean the selection. Nothing left to leave is reported unhandled so
    /// the key still travels outward to whatever is presented above the
    /// workspace.
    private func cancelActiveWorkspaceInteraction() -> KeyPress.Result {
        // Dimension is absent here on purpose: while it is taking typed input it
        // owns Escape as `.cancelDimensionCommand`, decided by the router before
        // the general path is reached.
        if slotProfileCommandState.isActive {
            slotProfileCommandState.deactivate()
            return .handled
        }
        if edgeOffsetCommandState.isActive {
            edgeOffsetCommandState.deactivate()
            return .handled
        }
        if regionOffsetCommandState.isActive {
            regionOffsetCommandState.deactivate()
            return .handled
        }
        if slideCommandState.isActive {
            slideCommandState.deactivate()
            return .handled
        }
        if patternArrayCurvePathPickState.isActive {
            patternArrayCurvePathPickState = .inactive
            return .handled
        }
        if pointPickRequest != nil {
            pointPickRequest = nil
            reportToolStatus("Point pick canceled.")
            return .handled
        }
        if placeSession != nil {
            placeSession = nil
            reportToolStatus("Place finished.")
            return .handled
        }
        if arraySession != nil {
            arraySession = nil
            reportToolStatus("Array finished.")
            return .handled
        }
        if mirrorSession?.freestylePoints != nil {
            mirrorSession?.freestylePoints = nil
            reportToolStatus(mirrorSession?.prompt ?? "")
            return .handled
        }
        if mirrorSession != nil {
            mirrorSession = nil
            reportToolStatus("Mirror canceled.")
            return .handled
        }
        if sectionAnalysisSession != nil {
            sectionAnalysisSession = nil
            reportToolStatus("Section Analysis canceled.")
            return .handled
        }
        if transformSession?.pendingPoint != nil {
            // Escape backs out of the pivot or freestyle pick first, keeping the transform.
            transformSession?.pendingPoint = nil
            transformSession?.freestylePoints = []
            reportToolStatus(transformSession?.prompt ?? "")
            return .handled
        }
        if transformSession != nil {
            finishTransformSession()
            return .handled
        }
        if viewAlignedConstructionPlaneRequest != nil {
            viewAlignedConstructionPlaneRequest = nil
            return .handled
        }
        if modelingDraft != nil
            || meshDraft != nil
            || historyPreviewTitle != nil
            || modelingPreview.payload != nil {
            cancelModelingOperation()
            return .handled
        }
        if selectedTool != .select {
            activateTool(.select)
            return .handled
        }
        guard snapshot.selection.selectedTargets.isEmpty == false
            || snapshot.selection.primarySceneNodeID != nil else {
            return .ignored
        }
        updateSelection { selection, _ in
            selection.clearSelection()
        }
        return .handled
    }

    private func activateDimensionCommand() {
        let objectTargets = selectedObjectDimensionTargets
        let sketchTargets = selectedSketchDimensionTargets
        let targets = objectTargets + sketchTargets
        guard !targets.isEmpty else {
            dimensionCommandState.deactivate()
            reportToolStatus(
                "Dimension requires a selected object, face, edge, or sketch curve target.",
                severity: .warning
            )
            return
        }

        do {
            let entries = try dimensionEntries(
                objectTargets: objectTargets,
                sketchTargets: sketchTargets
            )
            guard !entries.isEmpty else {
                dimensionCommandState.deactivate()
                reportToolStatus(
                    "Dimension found no editable values for the selected target.",
                    severity: .warning
                )
                return
            }
            dimensionCommandState.activate(entries: entries)
        } catch let error as EditorError {
            dimensionCommandState.deactivate()
            reportToolStatus(error.message, severity: .warning)
        } catch {
            dimensionCommandState.deactivate()
            reportToolStatus(String(describing: error), severity: .warning)
        }
    }

    private func dimensionEntries(
        objectTargets: [SelectionTarget],
        sketchTargets: [SelectionTarget]
    ) throws -> [DimensionCommandEntry] {
        var entries: [DimensionCommandEntry] = []
        if !objectTargets.isEmpty {
            let summary = try ObjectDimensionSummaryService().summarize(
                document: snapshot.document.document,
                targets: objectTargets,
                displayUnit: snapshot.workspaceState.displayUnit,
                objectRegistry: objectRegistry
            )
            entries += summary.entries.map(DimensionCommandEntry.init(object:))
        }
        if !sketchTargets.isEmpty {
            let sketchEntityTargets = sketchTargets.filter { target in
                if case .sketchEntity = target.component {
                    return true
                }
                return false
            }
            let generatedEdgeTargets = sketchTargets.filter { target in
                guard case .edge(let componentID) = target.component else {
                    return false
                }
                return componentID.generatedTopologySubshapeID != nil
            }
            if !sketchEntityTargets.isEmpty {
                let summary = try SketchDimensionSummaryService().summarize(
                    document: snapshot.document.document,
                    targets: sketchEntityTargets,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: objectRegistry
                )
                entries += summary.entries.map(DimensionCommandEntry.init(sketch:))
            }
            for target in generatedEdgeTargets {
                entries += try generatedEdgeDimensionEntries(for: target)
            }
        }
        return entries
    }

    private func generatedEdgeDimensionEntries(
        for target: SelectionTarget
    ) throws -> [DimensionCommandEntry] {
        do {
            let summary = try SketchDimensionSummaryService().summarize(
                document: snapshot.document.document,
                targets: [target],
                displayUnit: snapshot.workspaceState.displayUnit,
                objectRegistry: objectRegistry
            )
            return summary.entries.map(DimensionCommandEntry.init(sketch:))
        } catch let sketchError as EditorError {
            do {
                let summary = try ObjectDimensionSummaryService().summarize(
                    document: snapshot.document.document,
                    targets: [target],
                    displayUnit: snapshot.workspaceState.displayUnit,
                    objectRegistry: objectRegistry
                )
                return summary.entries.map(DimensionCommandEntry.init(object:))
            } catch let objectError as EditorError {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Dimension generated edge target is not an editable profile cap edge or extrusion depth edge. Sketch: \(sketchError.message) Object: \(objectError.message)"
                )
            }
        } catch {
            throw error
        }
    }

    /// Enter commits every value typed into the dimension entries, as one undoable change.
    private func commitDimensionCommand() {
        let pending = dimensionCommandState.pendingValues
        guard !pending.isEmpty else {
            dimensionCommandState.deactivate()
            return
        }
        var commands: [EditorCommand] = []
        for (entry, value) in pending {
            guard value.isFinite else {
                reportToolStatus("Dimension value must be finite.", severity: .warning)
                return
            }
            switch entry.source {
            case .object(let kind):
                guard value > 0.0 else {
                    reportToolStatus("Dimension value must be a positive length.", severity: .warning)
                    return
                }
                commands.append(.setObjectDimension(target: entry.target, kind: kind, value: .length(value, .meter)))
            case .sketch(let kind):
                let expression: CADExpression
                switch entry.valueKind {
                case .length:
                    guard value > 0.0 else {
                        reportToolStatus("Dimension value must be a positive length.", severity: .warning)
                        return
                    }
                    expression = .length(value, .meter)
                case .angle:
                    expression = .angle(value, .radian)
                }
                commands.append(.setSketchEntityDimension(target: entry.target, kind: kind, value: expression))
            }
        }
        submitSource(commands, name: "Set Dimensions")
        dimensionCommandState.deactivate()
    }

    private func createConstructionPlaneFromSelectedTargets(alignsView: Bool) -> KeyPress.Result {
        guard selectedConstructionPlaneTargets != nil else {
            // A key that silently did nothing taught the user nothing about why.
            // The refusal names the operands the plane can be built from instead.
            reportToolStatus(
                "Construction plane needs "
                    + WorkspaceConstructionPlaneTargetSelectionBuilder.acceptedSelectionDescription
                    + ".",
                severity: .warning
            )
            return .handled
        }
        let viewNormal = viewportProjectionBasis.viewNormal
        submitSource(name: "createConstructionPlaneFromTargets") { current in
            guard let targets = WorkspaceConstructionPlaneTargetSelectionBuilder(
                document: current.document.document,
                selection: current.selection
            ).constructionPlaneTargets else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Construction plane needs "
                        + WorkspaceConstructionPlaneTargetSelectionBuilder
                            .acceptedSelectionDescription
                        + "."
                )
            }
            return [
                .createConstructionPlaneFromTargets(
                    name: nextSceneNodeName(
                        prefix: "Custom Plane",
                        in: current.document.document
                    ),
                    targets: targets,
                    viewNormal: viewNormal
                ),
            ]
        } completion: { results in
            guard let id = results.last?.createdConstructionPlaneID else {
                return
            }
            let published = try await workspace.applyWorkspace([.setActiveConstructionPlane(id)])
            workspacePlaneMode = .adaptive
            if alignsView,
               let plane = published.document.document.productMetadata.constructionPlanes[id] {
                alignViewport(to: plane.plane, name: plane.name)
            }
        }
        return .handled
    }

    private func activateSlideCommand() {
        if selectedSplineControlPointSlideInput() != nil {
            activateSlideCurveControlVerticesCommand()
            return
        }
        let surfaceTargets = selectedPolySplineSurfaceVertexTargets
        if surfaceTargets.isEmpty == false {
            activateSlideSurfaceControlVerticesCommand()
            return
        }
        let surfaceReferences = selectedSurfaceControlPointReferences
        if surfaceReferences.isEmpty == false {
            activateSlideSurfaceControlVerticesCommand()
            return
        }
        if selectionScope == .vertex, selectedVertexTargets.isEmpty == false {
            reportToolStatus(
                "Slide Surface CV requires generated PolySpline surface CV selections.",
                severity: .warning
            )
            return
        }
        if case .success(let entity?) = selectedSketchEntityResult {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            reportToolStatus(
                entity.entityKind == "spline"
                    ? "Slide requires selected spline control vertices."
                    : "Slide Curve CV requires a spline curve target.",
                severity: .warning
            )
            return
        }
        selectionScope = .sketchEntity
        reportToolStatus(
            "Slide requires selected curve CVs or surface CVs.",
            severity: .warning
        )
    }

    private func activateSlideCurveControlVerticesCommand() {
        selectionScope = .sketchEntity
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.activateCurveControlVertices()
        reportToolStatus("Slide Curve CV active.")
    }

    private func activateSlideSurfaceControlVerticesCommand() {
        selectionScope = .vertex
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.activateSurfaceControlVertices()
        reportToolStatus("Slide Surface CV active.")
    }

    private func activateConstructionPlane(
        _ id: ConstructionPlaneSourceID,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) {
        applyWorkspace(commands: { current in
            guard current.document.document.productMetadata.constructionPlanes[id] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Construction plane no longer exists."
                )
            }
            return current.workspaceState.activeConstructionPlaneID == id
                ? []
                : [.setActiveConstructionPlane(id)]
        }) { published in
            workspacePlaneMode = .adaptive
            if let activeName = published.document.document.productMetadata.constructionPlanes[id]?.name {
                reportToolStatus("Active construction plane set to \(activeName).")
            }
            completion(published)
        }
    }

    private func activateAndAlignConstructionPlane(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        activateConstructionPlane(entry.id) { published in
            guard let plane = published.document.document.productMetadata.constructionPlanes[entry.id] else {
                return
            }
            alignViewport(to: plane.plane, name: plane.name)
        }
    }

    private func updateConstructionPlaneFromView(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        guard let viewNormal = viewportProjectionBasis.viewNormal else {
            reportToolStatus(
                "Construction plane update requires a resolved viewport normal.",
                severity: .warning
            )
            return
        }

        commitConstructionPlaneEdit(
            entry,
            successMessage: "Updated construction plane \(entry.name) from current view."
        ) { source, document in
            try WorkspaceConstructionPlaneEditBuilder().planePreservingOrigin(
                from: source.plane,
                viewNormal: viewNormal,
                tolerance: document.modelingSettings.tolerance
            )
        }
    }

    private func activateSelectedConstructionPlane() {
        guard let entry = selectedConstructionPlaneEntry else {
            reportToolStatus(
                "Select one construction plane to activate it.",
                severity: .warning
            )
            return
        }
        activateConstructionPlane(entry.id)
    }

    private func updateSelectedConstructionPlaneFromView() {
        guard let entry = selectedConstructionPlaneEntry else {
            reportToolStatus(
                "Select one construction plane to update it from the current view.",
                severity: .warning
            )
            return
        }
        updateConstructionPlaneFromView(entry)
    }

    private func setSelectedConstructionPlaneOriginComponent(
        _ component: WorkspaceConstructionPlaneOriginComponent,
        value: Double
    ) {
        guard let entry = selectedConstructionPlaneEntry else {
            reportToolStatus(
                "Select one construction plane before editing its origin.",
                severity: .warning
            )
            return
        }
        commitConstructionPlaneEdit(
            entry,
            successMessage: "Updated construction plane \(entry.name) origin."
        ) { source, document in
            try WorkspaceConstructionPlaneEditBuilder().planeSettingOriginComponent(
                component,
                value: value,
                on: source.plane,
                tolerance: document.modelingSettings.tolerance
            )
        }
    }

    private func setSelectedConstructionPlaneNormalComponent(
        _ component: WorkspaceConstructionPlaneNormalComponent,
        value: Double
    ) {
        guard let entry = selectedConstructionPlaneEntry else {
            reportToolStatus(
                "Select one construction plane before editing its normal.",
                severity: .warning
            )
            return
        }
        commitConstructionPlaneEdit(
            entry,
            successMessage: "Updated construction plane \(entry.name) normal."
        ) { source, document in
            try WorkspaceConstructionPlaneEditBuilder().planeSettingNormalComponent(
                component,
                value: value,
                on: source.plane,
                tolerance: document.modelingSettings.tolerance
            )
        }
    }

    private func commitConstructionPlaneEdit(
        _ entry: ConstructionPlaneSummaryResult.Entry,
        successMessage: String,
        plane: @escaping @MainActor @Sendable (
            ConstructionPlaneSource,
            DesignDocument
        ) throws -> SketchPlane
    ) {
        submitSource(name: "setConstructionPlane") { current in
            let document = current.document.document
            guard let source = document.productMetadata.constructionPlanes[entry.id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Construction plane no longer exists."
                )
            }
            return [
                .setConstructionPlane(
                    id: entry.id,
                    plane: try plane(source, document)
                ),
            ]
        } completion: { results in
            guard results.last != nil else {
                return
            }
            reportToolStatus(successMessage)
        }
    }

    private func selectConstructionPlane(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        guard let target = entry.selectionTarget() else {
            reportToolStatus(
                "Construction plane selection target is unavailable.",
                severity: .warning
            )
            return
        }
        submitSelectionMutation { selection, document in
            try selection.selectTarget(target, in: document)
        } completion: { _ in
            reportToolStatus("Selected construction plane \(entry.name).")
        }
    }

    private func alignViewport(
        to plane: SketchPlane,
        name: String
    ) {
        do {
            viewportProjectionRequest = ViewportProjectionRequest(
                basis: try ViewportProjectionBasis.aligned(to: plane)
            )
            reportToolStatus("View aligned to \(name).")
        } catch {
            reportToolStatus(
                "Construction plane view alignment failed.",
                severity: .warning
            )
        }
    }

    private func createSavedViewFromCurrentViewport() {
        let projectionBasis = viewportProjectionBasis
        guard let cameraFrame = viewportCameraState.frame else {
            reportToolStatus("The current camera cannot be captured. Reframe the view and try again.", severity: .warning)
            return
        }
        submitSource(name: "createSavedView") { current in
            let savedView = savedViewBuilder.makeSavedView(
                name: savedViewBuilder.nextSavedViewName(in: current.document.document),
                workspaceState: current.workspaceState,
                projectionBasis: projectionBasis,
                cameraFrame: cameraFrame
            )
            return [.createSavedView(savedView)]
        } completion: { results in
            if results.last != nil {
                reportToolStatus("Saved view created.")
            }
        }
    }

    private func updateSavedViewFromCurrentViewport(_ savedView: SavedView) {
        let savedViewID = savedView.id
        let projectionBasis = viewportProjectionBasis
        guard let cameraFrame = viewportCameraState.frame else {
            reportToolStatus("The current camera cannot be captured. Reframe the view and try again.", severity: .warning)
            return
        }
        submitSource(name: "updateSavedView") { current in
            guard let currentSavedView = current.document.document.productMetadata.savedViews[savedViewID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Saved view \(savedViewID) does not exist."
                )
            }
            var updatedView = savedViewBuilder.makeSavedView(
                name: currentSavedView.name,
                workspaceState: current.workspaceState,
                projectionBasis: projectionBasis,
                cameraFrame: cameraFrame
            )
            updatedView.id = savedViewID
            return [.updateSavedView(updatedView)]
        } completion: { results in
            if results.last != nil {
                reportToolStatus("Saved view \(savedView.name) updated.")
            }
        }
    }

    private func applySavedView(_ savedView: SavedView) {
        let savedViewID = savedView.id
        applyWorkspace(commands: { current in
            guard let currentSavedView = current.document.document.productMetadata.savedViews[savedViewID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Saved view \(savedViewID) no longer exists."
                )
            }
            _ = try savedViewBuilder.cameraFrameRequest(for: currentSavedView)
            return [.setRulerConfiguration(currentSavedView.displayScale.rulerConfiguration)]
        }) { published in
            guard let currentSavedView = published.document.document.productMetadata.savedViews[savedViewID] else {
                return
            }
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
            do {
                let cameraFrameRequest = try savedViewBuilder.cameraFrameRequest(for: currentSavedView)
                viewportCameraFrameRequest = cameraFrameRequest
                reportToolStatus("Applying saved view \(currentSavedView.name).")
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func removeSavedView(_ savedView: SavedView) {
        submitSource(.removeSavedView(id: savedView.id)) { result in
            if result != nil {
                reportToolStatus("Saved view \(savedView.name) removed.")
            }
        }
    }

    private func beginConstructionPlaneRename(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        constructionPlaneRenameTargetID = entry.id
        constructionPlaneRenameText = entry.name
    }

    private func cancelConstructionPlaneRename() {
        constructionPlaneRenameTargetID = nil
        constructionPlaneRenameText = ""
    }

    private func commitConstructionPlaneRename() {
        guard let id = constructionPlaneRenameTargetID else {
            return
        }
        let trimmedName = constructionPlaneRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            reportToolStatus(
                "Construction plane names must not be empty.",
                severity: .warning
            )
            return
        }

        submitSource(.renameConstructionPlane(id: id, name: trimmedName)) { result in
            if result != nil {
                cancelConstructionPlaneRename()
                reportToolStatus("Construction plane renamed to \(trimmedName).")
            }
        }
    }

    private func createViewAlignedConstructionPlaneFromKeyboard(pickOrigin: Bool) -> KeyPress.Result {
        guard let viewNormal = viewportProjectionBasis.viewNormal else {
            reportToolStatus(
                "View-aligned construction plane requires a resolved viewport normal.",
                severity: .warning
            )
            return .handled
        }

        if pickOrigin {
            viewAlignedConstructionPlaneRequest = ViewAlignedConstructionPlaneRequest(
                viewNormal: viewNormal
            )
            reportToolStatus("Click a point to set the view-aligned construction plane origin.")
            return .handled
        }

        viewAlignedConstructionPlaneRequest = nil
        createViewAlignedConstructionPlane(
            origin: .origin,
            viewNormal: viewNormal
        )
        return .handled
    }

    private func createViewAlignedConstructionPlane(
        from target: ViewportCanvasTarget,
        request: ViewAlignedConstructionPlaneRequest
    ) {
        let sketchPlane = effectiveSketchPlane(fallback: target.sketchPlane)
        guard let canvasInput = mappedCanvasInput(
            modelPoint: target.modelPoint,
            modelWorldPoint: target.modelWorldPoint,
            viewRayAnchorWorldPoint: target.viewRayAnchorWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            viewAlignedConstructionPlaneRequest = nil
            return
        }
        let snappedInput = snappedModelInput(canvasInput.point, modifierFlags: target.modifierFlags)
        guard let origin = resolvedSketchPlaneWorldPoint(
            for: snappedInput.point,
            snappedWorldPoint: snappedInput.worldPoint,
            fallbackWorldPoint: canvasInput.worldPoint,
            sketchPlane: sketchPlane
        ) else {
            viewAlignedConstructionPlaneRequest = nil
            return
        }
        viewAlignedConstructionPlaneRequest = nil
        createViewAlignedConstructionPlane(
            origin: origin,
            viewNormal: request.viewNormal
        )
    }

    private func createViewAlignedConstructionPlane(
        origin: Point3D,
        viewNormal: Vector3D
    ) {
        submitSource(name: "createViewAlignedConstructionPlane") { current in
            [
                .createViewAlignedConstructionPlane(
                    name: nextSceneNodeName(
                        prefix: "View Plane",
                        in: current.document.document
                    ),
                    origin: origin,
                    viewNormal: viewNormal
                ),
            ]
        } completion: { results in
            guard let id = results.last?.createdConstructionPlaneID else {
                return
            }
            _ = try await workspace.applyWorkspace([.setActiveConstructionPlane(id)])
            workspacePlaneMode = .adaptive
            reportToolStatus("View-aligned construction plane created.")
        }
    }

    private func activateRegionOffsetCommand() {
        guard selectedRegionTargets.isEmpty == false else {
            if selectionScope != .region {
                selectionScope = .region
            }
            reportToolStatus(
                "Offset Region requires a selected sketch region.",
                severity: .warning
            )
            return
        }
        selectionScope = .region
        edgeOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.deactivate()
        regionOffsetCommandState.activateArrowDrag()
    }

    private func activateEdgeOffsetCommand() {
        guard selectedEdgeTargets.isEmpty == false else {
            if selectionScope != .edge {
                selectionScope = .edge
            }
            reportToolStatus(
                "Offset Edge requires a selected edge.",
                severity: .warning
            )
            return
        }
        selectionScope = .edge
        regionOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.deactivate()
        edgeOffsetCommandState.activateDistanceInput()
        let supportResolution = edgeOffsetSupportStateResolver.resolution(for: selectedEdgeTargets)
        if supportResolution.isSupported == false,
           let message = supportResolution.diagnosticMessage {
            reportToolStatus(message, severity: .warning)
        }
    }

    /// O with a line or arc end selected: Offset Vertex, whose distance D types and Return applies.
    private func activateVertexOffsetCommand() {
        selectionScope = .sketchEntity
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slideCommandState.deactivate()
        slotProfileCommandState.beginVertexOffset()
        reportToolStatus("Offset Vertex: drag the handle or D to type the distance, Return creates it.")
    }

    private func activateSlotProfileCommand() {
        guard selectedCurveOffsetTarget != nil else {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            reportToolStatus(
                "Slot requires a selected open source curve.",
                severity: .warning
            )
            return
        }
        selectionScope = .sketchEntity
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slideCommandState.deactivate()
        if slotProfileCommandState.isCurveOffsetActive, selectedSlotSourceCurveTarget == nil {
            reportToolStatus("Slot takes an open curve; a circle is offset only.", severity: .warning)
            return
        }
        slotProfileCommandState.pressOffsetKey()
        reportToolStatus(slotProfileCommandState.isCurveOffsetActive
            ? "Offset: D types the distance, S makes it symmetric, O again makes a Slot."
            : "Slot: D types the width.")
    }

    private func handleViewportShiftScroll(_ direction: ViewportScrollDirection) -> Bool {
        if arraySession != nil {
            let delta = direction == .up ? 1 : -1
            updateArrayInSession { shaping, source, _ in
                try shaping.distribution(of: source, addingCopies: delta)
            }
            return true
        }
        guard selectedTool == .polygon else {
            return false
        }
        switch direction {
        case .up:
            _ = adjustPolygonSideCount(by: 1)
        case .down:
            _ = adjustPolygonSideCount(by: -1)
        }
        return true
    }

    private func handleViewportSelectionDrag(_ target: ViewportSelectionDragTarget) {
        clearSelectionDragPreview()
        let targets = mergedSelectionTargets(for: target)
        applyViewportSelection(targets: targets, intent: target.selectionIntent)
    }

    private func handleViewportSelectionDragPreview(_ target: ViewportSelectionDragTarget) {
        let targets = mergedSelectionTargets(for: target)
        guard selectionDragPreviewTargets != targets else {
            return
        }
        selectionDragPreviewTargets = targets
        selectionDragPreviewSceneNodeIDs = Set(targets.compactMap { target in
            guard case .object = target.component else {
                return nil
            }
            return target.sceneNodeID
        })
    }

    private func clearSelectionDragPreview() {
        selectionDragPreviewTargets = []
        selectionDragPreviewSceneNodeIDs = []
    }

    private func mergedSelectionTargets(
        for target: ViewportSelectionDragTarget
    ) -> [SelectionTarget] {
        var targets = selectionTargets(for: target.hits)
        for occurrenceID in target.presentationOccurrenceIDs {
            guard let sceneNodeID = snapshot.sceneNodeID(for: occurrenceID) else {
                continue
            }
            let selectionTarget = SelectionTarget(sceneNodeID: sceneNodeID)
            if targets.contains(selectionTarget) == false {
                targets.append(selectionTarget)
            }
        }
        return targets
    }

    /// Commits a released body transform as an atomic batch of placements, the
    /// way a released sketch transform commits its own. Both gizmos measure a
    /// world mutation and hand over the local frame that realises it, so both
    /// land on the one command that owns a scene node's frame.
    private func handleViewportBodyPlacementCommit(
        _ targets: [ViewportBodyPlacementDragTarget]
    ) async throws -> ViewportSourceIdentity {
        guard viewportPointerOwner.allows(.objectPlacement) else {
            throw ProjectWorkspaceActionError(
                code: .actionResultMismatch,
                message: "Body transforms commit only while the Select tool edits objects and no command takes the viewport's clicks."
            )
        }
        // A running Move, Rotate or Scale commits its drag as the session's transform, the same
        // command its typed and freestyle motions submit.
        let transform = transformSession
        return try await runWorkspaceOperation {
            _ = try await executeSource(name: "transformBodyPlacements") { current in
                if let transform {
                    return [try transform.dragCommand(targets)]
                }
                return try WorkspaceTransformMatrix.commands(placements: targets, in: current.document.document)
            }
            guard let published = workspace.view else {
                throw ProjectWorkspaceActionError(code: .snapshotUnavailable,
                                                  message: "The committed source has no published view.")
            }
            return .document(id: published.document.document.id, generation: published.documentGeneration)
        }
    }

    private func handleViewportBodyResizeCommit(_ target: ViewportBodyResizeDragTarget) async throws -> ViewportSourceIdentity {
        guard viewportPointerOwner.allows(.objectHandles) else {
            throw ProjectWorkspaceActionError(code: .actionResultMismatch,
                                              message: "Box resize requires the Select tool editing objects, with no command taking the viewport's clicks.")
        }
        return try await runWorkspaceOperation {
            _ = try await executeSource(name: "resizeBody") { current in
                try WorkspaceBodyResizeCommandPlanner.commands(target, in: current.document.document)
            }
            guard let published = workspace.view else {
                throw ProjectWorkspaceActionError(code: .snapshotUnavailable, message: "The resized source has no published view.")
            }
            return .document(id: published.document.document.id, generation: published.documentGeneration)
        }
    }

    private func handleViewportVertexDrag(_ target: ViewportVertexDragTarget) {
        guard viewportPointerOwner.allows(.bodyVertexEditing) else {
            return
        }
        submitSource(
            .moveBodyVertex(
                target: target.target,
                deltaX: .length(target.deltaX, .meter),
                deltaY: .length(target.deltaY, .meter)
            )
        )
    }

    private func handleViewportPolySplineSurfaceVertexDrag(_ target: ViewportPolySplineSurfaceVertexDragTarget) {
        guard viewportPointerOwner.allows(.bodyVertexEditing) else {
            return
        }
        submitSource(
            .movePolySplineSurfaceVertex(
                target: target.target,
                deltaX: .length(target.deltaX, .meter),
                deltaY: .length(target.deltaY, .meter),
                deltaZ: .length(target.deltaZ, .meter)
            )
        )
    }

    private func handleViewportSurfaceControlPointDrag(_ target: ViewportSurfaceControlPointDragTarget) {
        guard viewportPointerOwner.allows(.bodyVertexEditing) else {
            return
        }
        if !surfaceControlPointMoveOptions.isPlainMove {
            // The dragged control point is the active one; the rest of the selection moves with it.
            var options = surfaceControlPointMoveOptions
            options.mirrorPlane = workspacePlaneMode.sketchPlane ?? activeConstructionPlane?.plane ?? .xy
            let others = selectedSurfaceControlPointReferences.filter { $0 != target.target }
            submitSource(
                .moveSurfaceControlPointsProportionally(
                    targets: others + [target.target],
                    deltaX: .length(target.deltaX, .meter),
                    deltaY: .length(target.deltaY, .meter),
                    deltaZ: .length(target.deltaZ, .meter),
                    options: options
                )
            )
            return
        }
        submitSource(
            .moveSurfaceControlPoint(
                target: target.target,
                deltaX: .length(target.deltaX, .meter),
                deltaY: .length(target.deltaY, .meter),
                deltaZ: .length(target.deltaZ, .meter)
            )
        )
    }

    private func handleViewportSurfaceTrimEndpointDrag(_ target: ViewportSurfaceTrimEndpointDragTarget) {
        guard viewportPointerOwner.allows(.bodyVertexEditing) else {
            return
        }
        submitSource(
            .moveSurfaceTrimEndpoint(
                target: target.target,
                endpoint: target.endpoint,
                u: .scalar(target.u),
                v: .scalar(target.v)
            )
        )
    }

    private func handleViewportSurfaceTrimControlPointDrag(_ target: ViewportSurfaceTrimControlPointDragTarget) {
        guard viewportPointerOwner.allows(.bodyVertexEditing) else {
            return
        }
        submitSource(
            .moveSurfaceTrimControlPoint(
                target: target.target,
                controlPointIndex: target.controlPointIndex,
                u: .scalar(target.u),
                v: .scalar(target.v)
            )
        )
    }

    private func handleViewportPolySplineSurfaceVertexSlideDrag(
        _ target: ViewportPolySplineSurfaceVertexSlideDragTarget
    ) {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              slideCommandState.isSurfaceControlVerticesActive else {
            return
        }
        polySplineSurfaceVertexSlideDistanceMeters = max(abs(target.distance), 1.0e-9)
        slideSelectedPolySplineSurfaceVertices(
            target.targets,
            direction: target.direction,
            distanceMeters: target.distance
        )
    }

    private func handleViewportSurfaceControlPointSlideDrag(
        _ target: ViewportSurfaceControlPointSlideDragTarget
    ) {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              slideCommandState.isSurfaceControlVerticesActive else {
            return
        }
        polySplineSurfaceVertexSlideDistanceMeters = max(abs(target.distance), 1.0e-9)
        slideSelectedSurfaceControlPoints(
            target.targets,
            direction: target.direction,
            distanceMeters: target.distance
        )
    }

    private func handleViewportSurfaceFrameDrag(
        _ target: ViewportSurfaceFrameDragTarget
    ) {
        guard viewportPointerOwner.allows(.bodyVertexEditing),
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return
        }
        let uDistance = target.axis == .u ? target.distance : 0.0
        let vDistance = target.axis == .v ? target.distance : 0.0
        let normalDistance = target.axis == .normal ? target.distance : 0.0
        moveSelectedSurfaceControlPointsInFrame(
            target.targets,
            frame: target.query,
            uDistanceMeters: uDistance,
            vDistanceMeters: vDistance,
            normalDistanceMeters: normalDistance
        )
    }

    private func handleViewportConstructionPlaneHandleDrag(
        _ target: ViewportConstructionPlaneDragTarget
    ) {
        guard viewportPointerOwner.allows(.constructionPlane) else {
            return
        }

        do {
            guard let edit = try WorkspaceConstructionPlaneViewportDragCommitService().edit(
                for: target,
                entries: savedConstructionPlaneSummary.planes,
                tolerance: snapshot.document.document.modelingSettings.tolerance
            ) else {
                return
            }
            commitConstructionPlaneEdit(
                edit.entry,
                successMessage: edit.successMessage
            ) { source, document in
                switch target.handle {
                case .origin:
                    try WorkspaceConstructionPlaneEditBuilder().planeSettingOrigin(
                        target.origin,
                        on: source.plane,
                        tolerance: document.modelingSettings.tolerance
                    )
                case .normal:
                    try WorkspaceConstructionPlaneEditBuilder().planeSettingNormal(
                        target.normal,
                        on: source.plane,
                        tolerance: document.modelingSettings.tolerance
                    )
                }
            }
        } catch let error as EditorError {
            reportToolStatus(error.message, severity: .warning)
        } catch {
            reportToolStatus(
                "Construction plane viewport edit failed.",
                severity: .warning
            )
        }
    }

    private func handleViewportFaceDrag(_ target: ViewportFaceDragTarget) {
        guard viewportPointerOwner.allows(.faceOffset) else {
            return
        }
        submitSource(
            .offsetBodyFace(
                target: target.target,
                distance: .length(target.distance, .meter)
            )
        )
    }

    private func handleViewportEdgeChamferDrag(_ target: ViewportEdgeChamferDragTarget) {
        guard viewportPointerOwner.allows(.edgeTreatment) else {
            return
        }
        submitSource(
            .createBodyEdgeTreatment(
                name: "Chamfer", target: target.target,
                treatment: .chamfer(distance: .length(target.distance, .meter))
            )
        )
    }

    private func handleViewportEdgeFilletDrag(_ target: ViewportEdgeFilletDragTarget) {
        guard viewportPointerOwner.allows(.edgeTreatment) else {
            return
        }
        submitSource(
            .createBodyEdgeTreatment(
                name: "Fillet", target: target.target,
                treatment: .fillet(radius: .length(target.radius, .meter))
            )
        )
    }

    private func handleViewportRegionOffsetDrag(_ target: ViewportRegionOffsetDragTarget) {
        guard viewportPointerOwner.allows(.regionOffset) else {
            return
        }
        regionOffsetDistanceMeters = max(abs(target.distance), 1.0e-9)
        offsetSelectedRegions(
            [target.target],
            by: target.distance,
            gapFill: regionOffsetGapFill,
            isSymmetric: regionOffsetCommandState.usesLockedDistance,
            combinesRegions: regionOffsetCommandState.usesCombinedRegions
        )
    }

    private func handleViewportEdgeOffsetDrag(_ target: ViewportEdgeOffsetDragTarget) {
        guard viewportPointerOwner.allows(.edgeOffset),
              edgeOffsetCommandState.isActive else {
            return
        }
        edgeOffsetDistanceMeters = max(target.distance, 1.0e-9)
        offsetSelectedEdges(
            [target.target],
            by: edgeOffsetDistanceMeters,
            gapFill: edgeOffsetGapFill
        )
    }

    private func handleViewportSlotWidthDrag(_ target: ViewportSlotWidthDragTarget) {
        guard viewportPointerOwner.allows(.slotWidth),
              slotProfileCommandState.isActive else {
            return
        }
        slotProfileWidthMeters = max(target.width, 1.0e-9)
        createCommandedCurveOffset(target.target)
    }

    private func handleViewportSketchVertexOffsetDrag(_ target: ViewportSketchVertexOffsetDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        sketchVertexOffsetDistanceMeters = max(target.distance, 1.0e-9)
        submitSource(
            .offsetSketchVertex(
                target: target.target,
                handle: target.handle,
                distance: .length(sketchVertexOffsetDistanceMeters, .meter)
            )
        )
    }

    private func handleViewportPatternArrayLinearAxisDrag(
        _ target: ViewportPatternArrayLinearAxisDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let slot: PatternArrayEditingService.RectangularAxisSlot
        switch target.axisSlot {
        case .first:
            slot = .first
        case .second:
            slot = .second
        case .radial:
            patternArrayEditingService(sourceID: target.sourceID)
                .setRadialAxisDistance(target.distance)
            return
        }
        patternArrayEditingService(sourceID: target.sourceID).setRectangularAxisDistance(
            slot: slot,
            meters: target.distance
        )
    }

    private func handleViewportIndependentCopyExtrudeDistanceDrag(
        _ target: ViewportIndependentCopyExtrudeDistanceDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              target.distance.isFinite,
              target.distance > 0.0 else {
            return
        }
        submitSource(
            .setExtrudeDistance(
                featureID: target.featureID,
                distance: .length(target.distance, .meter)
            )
        )
    }

    private func handleViewportIndependentCopyBodyDimensionDrag(
        _ target: ViewportIndependentCopyBodyDimensionDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              target.value.isFinite,
              target.value > 0.0 else {
            return
        }
        submitSource(name: "setIndependentCopyBodyDimension") { current in
            guard let bodySceneNodeID = current.document.document.productMetadata.sceneNodes.first(
                where: { $0.value.reference == .body(target.featureID) }
            )?.key else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent copy body \(target.featureID) does not exist."
                )
            }
            let summary = try ObjectDimensionSummaryService().summarize(
                document: current.document.document,
                targets: [SelectionTarget(sceneNodeID: bodySceneNodeID)],
                displayUnit: current.workspaceState.displayUnit,
                objectRegistry: current.objectRegistry
            )
            func currentDimension(_ kind: ObjectDimensionKind) -> Double? {
                summary.entries.first { $0.kind == kind }?.resolvedMeters
            }
            switch target.kind {
            case .sizeX, .sizeZ:
                guard let sizeX = currentDimension(.sizeX),
                      let sizeY = currentDimension(.sizeY),
                      let sizeZ = currentDimension(.sizeZ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Independent copy cube dimensions are unavailable."
                    )
                }
                return [
                    .setCubeDimensions(
                        featureID: target.featureID,
                        sizeX: .length(target.kind == .sizeX ? target.value : sizeX, .meter),
                        sizeY: .length(sizeY, .meter),
                        sizeZ: .length(target.kind == .sizeZ ? target.value : sizeZ, .meter)
                    ),
                ]
            case .radius:
                guard let sizeY = currentDimension(.sizeY) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Independent copy cylinder height is unavailable."
                    )
                }
                return [
                    .setCylinderDimensions(
                        featureID: target.featureID,
                        radius: .length(target.value, .meter),
                        sizeY: .length(sizeY, .meter)
                    ),
                ]
            }
        }
    }

    private func handleViewportPatternArrayRadialAngleDrag(
        _ target: ViewportPatternArrayRadialAngleDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        patternArrayEditingService(sourceID: target.sourceID)
            .setRadialAngle(degrees: target.angleRadians * 180.0 / .pi)
    }

    private func handleViewportPatternArrayCopyCountDrag(
        _ target: ViewportPatternArrayCopyCountDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let service = patternArrayEditingService(sourceID: target.sourceID)
        switch target.slot {
        case .rectangularFirst:
            service.setRectangularAxisCopyCount(slot: .first, copyCount: target.copyCount)
        case .rectangularSecond:
            service.setRectangularAxisCopyCount(slot: .second, copyCount: target.copyCount)
        case .radialAngular:
            service.setRadialAngularCopyCount(target.copyCount)
        case .radialAxis:
            service.setRadialAxisCopyCount(target.copyCount)
        case .curve:
            service.setCurveCopyCount(target.copyCount)
        }
    }

    private func handleViewportPatternArrayOutputModeChange(_ target: ViewportPatternArrayOutputModeTarget) {
        guard viewportPointerOwner.allows(.featureParameters),
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        patternArrayEditingService(sourceID: target.sourceID).setOutputMode(target.outputMode)
    }

    private func handleViewportPatternArrayCurvePathPointDrag(
        _ target: ViewportPatternArrayCurvePathPointDragTarget
    ) {
        guard viewportPointerOwner.allows(.featureParameters),
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        patternArrayEditingService(sourceID: target.sourceID).setCurvePathPoint(
            index: target.pointIndex,
            point: target.point
        )
    }

    private func handleViewportSketchCurveHandleDrag(_ target: ViewportSketchCurveHandleDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        switch target.handle {
        case .circleRadius:
            if let radiusMeters = target.radiusMeters {
                setSelectedSketchCircleRadius(target.target, meters: radiusMeters)
            }
        case .arcRadius:
            if let radiusMeters = target.radiusMeters {
                setSelectedSketchArcRadius(target.target, meters: radiusMeters)
            }
        case .arcStartAngle:
            if let startAngleRadians = target.startAngleRadians {
                setSelectedSketchArcStartAngle(target.target, radians: startAngleRadians)
            }
        case .arcEndAngle:
            if let endAngleRadians = target.endAngleRadians {
                setSelectedSketchArcEndAngle(target.target, radians: endAngleRadians)
            }
        }
    }

    private func handleViewportSketchDimensionDrag(_ target: ViewportSketchDimensionDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        setSelectedSketchEntityDimension(
            target.target,
            kind: target.kind,
            value: target.value
        )
    }

    private func handleViewportSketchPointHandleDrag(_ target: ViewportSketchPointHandleDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        moveSelectedSketchEntityPoint(
            target.target,
            handle: target.handle,
            deltaX: target.deltaX,
            deltaY: target.deltaY
        )
    }

    private func handleViewportSplineControlPointDrag(_ target: ViewportSplineControlPointDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        moveSelectedSplineControlPoint(
            target.target,
            controlPointIndex: target.controlPointIndex,
            deltaX: target.deltaX,
            deltaY: target.deltaY
        )
    }

    private func handleViewportBridgeCurveEndpointDrag(_ target: ViewportBridgeCurveEndpointDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        switch target.role {
        case .first:
            submitSource(
                .setBridgeCurveParameters(
                    sourceID: target.sourceID,
                    firstEndpoint: target.endpoint,
                    secondEndpoint: nil,
                    continuity: nil
                )
            )
        case .second:
            submitSource(
                .setBridgeCurveParameters(
                    sourceID: target.sourceID,
                    firstEndpoint: nil,
                    secondEndpoint: target.endpoint,
                    continuity: nil
                )
            )
        }
    }

    private func handleViewportSplineControlPointSlideDrag(_ target: ViewportSplineControlPointSlideDragTarget) {
        guard viewportPointerOwner.allows(.sketchEntityEditing) else {
            return
        }
        sketchSplineControlPointSlideDistanceMeters = max(abs(target.distance), 1.0e-9)
        slideSelectedSplineControlPoints(
            target.target,
            controlPointIndexes: target.controlPointIndexes,
            direction: target.direction,
            distanceMeters: target.distance
        )
    }

    private func handleViewportDrag(_ drag: ViewportModelDrag) {
        let sketchPlane = effectiveSketchPlane(fallback: drag.sketchPlane)
        guard let startCanvasInput = mappedCanvasInput(
            modelPoint: drag.start,
            modelWorldPoint: drag.startWorldPoint,
            viewRayAnchorWorldPoint: drag.startViewRayAnchorWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        guard let endCanvasInput = mappedCanvasInput(
            modelPoint: drag.end,
            modelWorldPoint: drag.endWorldPoint,
            viewRayAnchorWorldPoint: drag.endViewRayAnchorWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        let resolution = ViewportCanvasDragSnapResolver().resolution(
            ViewportModelDrag(
                start: startCanvasInput.point,
                end: endCanvasInput.point,
                sketchPlane: sketchPlane,
                modifierFlags: drag.modifierFlags,
                startWorldPoint: startCanvasInput.worldPoint,
                endWorldPoint: endCanvasInput.worldPoint
            ),
            document: snapshot.document.document,
            ruler: snapshot.workspaceState.ruler,
            snapOptions: snapResolutionOptions(modifierFlags: drag.modifierFlags),
            axisConstraint: activeCanvasDragAxisConstraint
        )
        reportViewportDragSnapFailures(resolution)
        let resolvedDrag = resolution.drag
        let tool = selectedTool
        let currentSolidShape = solidShape
        let polygonState = polygonToolState
        let currentSketchInputState = sketchInputState
        submitSource(name: "canvasDrag") { current in
            let planner = WorkspaceCanvasCommandPlanner(
                context: WorkspaceCanvasCommandPlanner.Context(
                    document: current.document.document,
                    selection: current.selection,
                    workspaceState: current.workspaceState,
                    objectRegistry: current.objectRegistry,
                    polygonState: polygonState,
                    sketchInputState: currentSketchInputState
                ),
                solidShape: currentSolidShape
            )
            do {
                guard let command = try planner.dragCommand(
                    tool: tool,
                    startModelPoint: resolvedDrag.start,
                    endModelPoint: resolvedDrag.end,
                    sketchPlane: resolvedDrag.sketchPlane,
                    startWorldPoint: resolvedDrag.startWorldPoint,
                    endWorldPoint: resolvedDrag.endWorldPoint
                ) else {
                    return []
                }
                return [command]
            } catch let failure as CanvasSketchCurveDrafts.Failure {
                throw EditorError(code: .commandInvalid, message: failure.message)
            }
        } completion: { results in
            try await finishCanvasSourceCommand(results.last)
        }
    }

    private func reportViewportDragSnapFailures(_ resolution: ViewportCanvasDragSnapResolution) {
        for failureDescription in resolution.failureDescriptions {
            reportToolStatus(
                "Snapping failed and was skipped: \(failureDescription)",
                severity: .warning
            )
        }
    }

    private func mappedCanvasInput(
        modelPoint: Point2D,
        modelWorldPoint: Point3D?,
        viewRayAnchorWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> WorkspaceCanvasPlaneInputMapper.Result? {
        do {
            return try WorkspaceCanvasPlaneInputMapper(
                projectionBasis: viewportProjectionBasis
            ).map(
                modelPoint: modelPoint,
                modelWorldPoint: modelWorldPoint,
                viewRayAnchorWorldPoint: viewRayAnchorWorldPoint,
                sketchPlane: sketchPlane
            )
        } catch WorkspaceCanvasPlaneInputMapper.Failure.unresolvedViewNormal {
            reportToolStatus(
                "Canvas input requires a resolved viewport normal for the active construction plane.",
                severity: .warning
            )
        } catch WorkspaceCanvasPlaneInputMapper.Failure.viewRayParallelToPlane {
            reportToolStatus(
                "Canvas input is parallel to the active construction plane from this view.",
                severity: .warning
            )
        } catch WorkspaceCanvasPlaneInputMapper.Failure.unresolvedViewRayAnchor {
            reportToolStatus(
                "Canvas input needs a mounted viewport frame to place it on the active construction plane.",
                severity: .warning
            )
        } catch {
            reportToolStatus(
                "Canvas input could not be projected onto the active construction plane.",
                severity: .warning
            )
        }
        return nil
    }

    private func resolvedCanvasWorldPoint(
        for point: Point2D,
        snappedWorldPoint: Point3D?,
        fallbackWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        return resolvedSketchPlaneWorldPoint(
            for: point,
            snappedWorldPoint: snappedWorldPoint,
            fallbackWorldPoint: fallbackWorldPoint,
            sketchPlane: sketchPlane
        )
    }

    private func resolvedSketchPlaneWorldPoint(
        for point: Point2D,
        snappedWorldPoint: Point3D?,
        fallbackWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        do {
            return try WorkspaceCanvasPlaneInputMapper(
                projectionBasis: viewportProjectionBasis
            ).resolvedWorldPoint(
                for: point,
                snappedWorldPoint: snappedWorldPoint,
                fallbackWorldPoint: fallbackWorldPoint,
                sketchPlane: sketchPlane
            )
        } catch {
            reportToolStatus(
                "Canvas input world point could not be resolved on the active construction plane.",
                severity: .warning
            )
            return nil
        }
    }

    private func snappedModelInput(
        _ point: Point2D,
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> SnappedModelInput {
        let resolution = WorkspaceSnapInputResolver().resolve(
            point,
            in: snapshot.document.document,
            ruler: snapshot.workspaceState.ruler,
            options: snapResolutionOptions(
                referencePoint: referencePoint,
                modifierFlags: modifierFlags
            ),
            referencePoint: referencePoint,
            modifierFlags: modifierFlags
        )
        if let failureMessage = resolution.failureMessage {
            reportToolStatus(
                "Snapping failed and was skipped: \(failureMessage)",
                severity: .warning
            )
        }
        return resolution.input
    }

    private func snapResolutionOptions(
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> SnapResolutionOptions {
        WorkspaceSnapOptionsBuilder(
            isGridSnapEnabled: isGridSnapEnabled,
            isObjectTargetingEnabled: isObjectTargetingEnabled,
            isConstructionPlaneSnapEnabled: isConstructionPlaneSnapEnabled,
            constructionPlane: constructionPlaneSnapPlane,
            overrideState: snapOverrideState,
            referenceLineAnchors: sketchInputState.referenceLineAnchors
        ).options(
            referencePoint: referencePoint,
            modifierFlags: modifierFlags
        )
    }

    private func activeSnapResolutionOptions() -> SnapResolutionOptions? {
        return snapResolutionOptions()
    }

    private func effectiveSketchPlane(fallback: SketchPlane) -> SketchPlane {
        workspacePlaneMode.sketchPlane ?? activeSketchPlane(fallback: fallback)
    }

    private func handleViewportHover(_ hit: ViewportHit?) {
        guard let hit else {
            patternArrayCurvePathPreviewCandidate = nil
            setHoveredTarget(nil)
            return
        }

        if let reference = hit.selectionReference {
            patternArrayCurvePathPreviewCandidate = nil
            setHoveredReference(reference)
            return
        }
        guard let target = selectionTarget(for: hit) else {
            patternArrayCurvePathPreviewCandidate = nil
            setHoveredTarget(nil)
            return
        }
        updatePatternArrayCurvePathPreviewCandidate(for: target)
        setHoveredTarget(target)
    }

    private func handleWorkspaceOverlayHover(_ isHovered: Bool) {
        guard isHovered else {
            return
        }
        if viewportHoverClearSignal == Int.max {
            viewportHoverClearSignal = 1
        } else {
            viewportHoverClearSignal += 1
        }
        snapOverrideState.updateHoveredCandidateKind(nil)
        handleViewportHover(nil)
    }

    private func updatePatternArrayCurvePathPreviewCandidate(for target: SelectionTarget) {
        guard patternArrayCurvePathPickState.isActive else {
            patternArrayCurvePathPreviewCandidate = nil
            return
        }
        patternArrayCurvePathPreviewCandidate = PatternArrayCurvePathCandidate(
            target: target,
            document: snapshot.document.document
        )
    }

    private func applyViewportSelection(
        hit: ViewportHit?,
        intent: ViewportSelectionIntent
    ) {
        guard let hit else {
            applyViewportSelection(targets: [], intent: intent)
            return
        }

        if let reference = hit.selectionReference {
            applyViewportSelection(references: [reference], intent: intent)
            return
        }
        guard let target = selectionTarget(for: hit) else {
            if patternArrayCurvePathPickState.isActive {
                _ = applyPatternArrayCurvePathPick(targets: [])
            }
            return
        }

        applyViewportSelection(targets: [target], intent: intent)
    }

    private func applyViewportSelection(
        targets: [SelectionTarget],
        intent: ViewportSelectionIntent
    ) {
        clearSelectionDragPreview()
        if applyPatternArrayCurvePathPick(targets: targets) {
            return
        }
        switch intent {
        case .replace:
            guard !targets.isEmpty else {
                clearSelection { published in
                    dimensionCommandState.deactivate()
                    syncOffsetCommandAvailability(for: published.selection)
                }
                return
            }
            submitSelectionMutation { selection, document in
                try selection.selectTargets(targets, in: document)
            } completion: { published in
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability(for: published.selection)
            }
        case .toggle:
            guard !targets.isEmpty else {
                return
            }
            submitSelectionMutation { selection, document in
                var nextTargets = selection.selectedTargets
                for target in targets {
                    if let index = nextTargets.firstIndex(of: target) {
                        nextTargets.remove(at: index)
                    } else {
                        nextTargets.append(target)
                    }
                }
                try selection.selectTargets(nextTargets, in: document)
            } completion: { published in
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability(for: published.selection)
            }
        }
    }

    private func applyViewportSelection(
        references: [SelectionReference],
        intent: ViewportSelectionIntent
    ) {
        clearSelectionDragPreview()
        patternArrayCurvePathPreviewCandidate = nil
        switch intent {
        case .replace:
            guard !references.isEmpty else {
                clearSelection { published in
                    dimensionCommandState.deactivate()
                    syncOffsetCommandAvailability(for: published.selection)
                }
                return
            }
            submitSelectionMutation { selection, document in
                try selection.selectReferences(references, in: document)
            } completion: { published in
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability(for: published.selection)
            }
        case .toggle:
            guard !references.isEmpty else {
                return
            }
            submitSelectionMutation { selection, document in
                var nextReferences = selection.selectedReferences
                for reference in references {
                    if let index = nextReferences.firstIndex(of: reference) {
                        nextReferences.remove(at: index)
                    } else {
                        nextReferences.append(reference)
                    }
                }
                try selection.selectReferences(nextReferences, in: document)
            } completion: { published in
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability(for: published.selection)
            }
        }
    }

    private func applyPatternArrayCurvePathPick(targets: [SelectionTarget]) -> Bool {
        guard let target = patternArrayCurvePathPickState.target else {
            return false
        }
        let submitPath: (PatternArrayCurvePath) -> Void
        switch target {
        case .existing(let sourceID):
            submitPath = { submitPatternArrayCurvePath(sourceID: sourceID, path: $0) }
        case .newArray(let rootSceneNodeIDs):
            submitPath = { path in
                patternArrayCurvePathPreviewCandidate = nil
                patternArrayCurvePathPickState.cancel()
                submitPatternArrayCreation(
                    WorkspacePatternArrayCreationPlanner(metadata: snapshot.document.document.productMetadata)
                        .curve(rootSceneNodeIDs: rootSceneNodeIDs, path: path)
                )
            }
        }
        let outcome = PatternArrayCurvePathPickService(
            document: snapshot.document.document,
            submit: { submitSource($0) },
            submitPath: submitPath,
            report: { reportToolStatus($0, severity: $1) },
            sourceID: patternArrayCurvePathPickState.sourceID
        ).apply(targets: targets)
        switch outcome {
        case .waitingForCurve:
            break
        case .submitted:
            break
        case .failed:
            patternArrayCurvePathPreviewCandidate = nil
            patternArrayCurvePathPickState.cancel()
        }
        dimensionCommandState.deactivate()
        syncOffsetCommandAvailability()
        return true
    }

    private func submitPatternArrayCurvePath(
        sourceID: PatternArraySourceID,
        path: PatternArrayCurvePath
    ) {
        submitSource(name: "updatePatternArrayCurvePath") { current in
            guard let source = current.document.document.productMetadata.patternArrays[sourceID],
                  case .curve(var curve) = source.distribution else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Curve Array path pick requires an existing curve Pattern Array source."
                )
            }
            curve.path = path
            return [
                .updatePatternArray(
                    id: sourceID,
                    name: nil,
                    definitionID: nil,
                    distribution: .curve(curve),
                    outputMode: nil
                ),
            ]
        } completion: { results in
            guard results.last != nil else {
                return
            }
            patternArrayCurvePathPreviewCandidate = nil
            patternArrayCurvePathPickState.cancel()
            reportToolStatus("Curve Array path updated.")
        }
    }

    private func syncOffsetCommandAvailability() {
        syncOffsetCommandAvailability(for: snapshot.selection)
    }

    private func syncOffsetCommandAvailability(for selection: SelectionModel) {
        let classification = WorkspaceSelectionTargetClassification(selection: selection)
        if selectionScope != .region || classification.regionTargets.isEmpty {
            regionOffsetCommandState.deactivate()
        }
        if selectionScope != .edge || classification.edgeTargets.isEmpty {
            edgeOffsetCommandState.deactivate()
        }
    }

    /// The Command Palette: each command runs its key's action or its Edit menu item, after the
    /// palette closes and the keyboard is back with the canvas.
    private var commandPalette: some View {
        WorkspaceCommandPaletteView(
            isAvailable: { command in
                switch command.invocation {
                case .keyboard: true
                case .edit(let item): item.action(in: workspaceEditCommands) != nil
                }
            },
            run: { command in
                isCommandPaletteOpen = false
                isWorkspaceFocused = true
                switch command.invocation {
                case .keyboard(let action):
                    _ = applyWorkspaceKeyboardAction(action)
                case .edit(let item):
                    item.action(in: workspaceEditCommands)?()
                }
            },
            close: {
                isCommandPaletteOpen = false
                isWorkspaceFocused = true
            }
        )
    }

    /// Return or right-click while Fillet runs: the treatment at the dialog's distance as one step,
    /// every selected corner once; the dialog stays when it is refused.
    private func confirmFillet() {
        guard let fillet = filletSession else { return }
        sketchCornerTreatment = fillet.treatment
        // Core refuses a distance that is not positive.
        let distance = CADExpression.length(sketchCornerTreatmentDistanceMeters, .meter)
        let command: EditorCommand
        switch fillet.targets {
        case .vertices(let vertices):
            command = .applySketchCornerTreatments(vertices: vertices, distance: distance, treatment: fillet.treatment)
        case .curves(let target, let adjacent):
            command = .applySketchCornerTreatment(
                target: target, adjacentTarget: adjacent, distance: distance, treatment: fillet.treatment
            )
        }
        submitDialogCommand([command], name: fillet.title, instance: fillet.instance,
                            running: { filletSession?.instance }, end: { filletSession = nil },
                            done: { reportToolStatus("\(fillet.title) done.") })
    }

    /// Fillet's radius handle while its dialog runs, at the corner Core resolves for the first
    /// selected end or the two selected curves. A selection Core cannot resolve to one corner
    /// shows no handle; Apply reports why.
    private var viewportSketchCornerTreatmentHandle: ViewportSketchCornerTreatmentHandle? {
        guard let fillet = filletSession else { return nil }
        let target: SelectionTarget
        let adjacent: SelectionTarget?
        switch fillet.targets {
        case .vertices(let vertices):
            guard let first = vertices.first else { return nil }
            target = first
            adjacent = nil
        case .curves(let first, let second):
            target = first
            adjacent = second
        }
        let ends: SketchCornerTreatmentEnds
        do {
            ends = try snapshot.document.document.sketchCornerTreatmentEnds(target: target, adjacentTarget: adjacent)
        } catch {
            return nil
        }
        return ViewportSketchCornerTreatmentHandle(
            target: target,
            ends: ends,
            signedDistance: fillet.treatment == .fillet
                ? sketchCornerTreatmentDistanceMeters
                : -sketchCornerTreatmentDistanceMeters
        )
    }

    /// A drag of Fillet's radius handle: inward sets a Fillet radius, outward a Chamfer
    /// distance; Return or right-click still applies it.
    private func handleViewportSketchCornerTreatmentDrag(_ target: ViewportSketchCornerTreatmentDragTarget) {
        guard filletSession != nil else { return }
        sketchCornerTreatmentDistanceMeters = abs(target.signedDistance)
        filletSession?.treatment = target.signedDistance < 0 ? .chamfer : .fillet
        if let filletSession { reportToolStatus("\(filletSession.title): Return applies.") }
    }

    /// Fillet's dialog: Fillet or Chamfer (C), its distance (D) and Apply.
    @ViewBuilder
    private func filletContextPanelContent(_ fillet: WorkspaceFilletSession) -> some View {
        workspaceStatusChip(fillet.title, systemImage: "rectangle.roundedtop", tint: .accentColor)
        commandDistanceInput(
            "Distance", meters: $sketchCornerTreatmentDistanceMeters, field: .cornerTreatment,
            accessibilityIdentifier: "WorkspaceFillet.distance"
        )
        Picker("Treatment", selection: Binding(
            get: { fillet.treatment },
            set: { filletSession?.treatment = $0 }
        )) {
            Text("Fillet").tag(SketchCornerTreatment.fillet)
            Text("Chamfer (C)").tag(SketchCornerTreatment.chamfer)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceFillet.treatment")
        workspaceIconButton(
            systemImage: "checkmark",
            help: "Apply \(fillet.title)",
            accessibilityIdentifier: "WorkspaceFillet.apply",
            action: { confirmFillet() }
        )
    }

    /// Cut Curve (C): the selected sketch curves become its targets and cutter, and clicks on
    /// curves add to or remove from the list the dialog picks.
    private func beginCutCurve() {
        let curves = snapshot.selection.selectedTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchPointHandleReference == nil && componentID.sketchControlPointReference == nil
        }
        endCommandsBeforePickingCommand()
        let cut = WorkspaceCutCurveSession(selectedCurves: curves, extendsCutter: cutCurveExtendsCutter)
        cutCurveSession = cut
        selectTargets(cut.curves)
        reportToolStatus(cut.prompt)
    }

    /// A click while Cut Curve runs: the sketch curve under the pointer joins or leaves the list
    /// being picked.
    private func pickCutCurve(at target: ViewportCanvasTarget) {
        var resolver = selectionTargetResolver
        resolver.selectionScope = .sketchEntity
        guard var cut = cutCurveSession, let hit = target.hit else {
            reportToolStatus("Cut Curve: click on a sketch curve.", severity: .warning)
            return
        }
        // Screen space cuts along the view of the latest click.
        if let ray = target.pickRay { cut.viewDirection = ray.direction }
        guard let curve = resolver.selectionTarget(for: hit),
              case .sketchEntity(let componentID) = curve.component,
              let entity = componentID.sketchEntityReference else {
            // A face is a cutter.
            var faceResolver = selectionTargetResolver
            faceResolver.selectionScope = .face
            if cut.picking == .cutters, let face = faceResolver.selectionTarget(for: hit), case .face = face.component {
                cut.toggle(face)
                cutCurveSession = cut
                reportToolStatus(cut.prompt)
                return
            }
            cutCurveSession = cut
            reportToolStatus("Cut Curve: click on a sketch curve, or a face as a cutter.", severity: .warning)
            return
        }
        let whole = SelectionTarget(
            sceneNodeID: curve.sceneNodeID,
            component: .sketchEntity(.sketchEntity(featureID: entity.featureID, entityID: entity.entityID))
        )
        cut.toggle(whole)
        cutCurveSession = cut
        selectTargets(cut.curves)
        reportToolStatus(cut.prompt)
    }

    /// Return or right-click while Cut Curve runs: one cut of every target by every cutter; the
    /// dialog stays when the cut is refused.
    private func confirmCutCurve() {
        guard let cut = cutCurveSession else { return }
        guard cut.canCut else {
            reportToolStatus("Cut Curve needs at least one target and one cutter.", severity: .warning)
            return
        }
        cutCurveExtendsCutter = cut.extendsCutter
        submitDialogCommand(
            [.cutSketchCurves(targets: cut.targets, cutters: cut.cutters, options: cut.options)],
            name: "Cut Curve", instance: cut.instance,
            running: { cutCurveSession?.instance }, end: { cutCurveSession = nil },
            done: { reportToolStatus("Cut Curve done.") }
        )
    }

    /// Boolean or Cut from the palette or the Model menu, as Q or C starts it.
    private func beginBodyOperation(_ operation: WorkspaceBodyOperation) {
        switch operation {
        case .boolean: beginBoolean()
        case .cut: beginBodyCut()
        }
    }

    /// Ends Boolean's and Cut's dialogs on bodies, as another command starts.
    private func endBodyOperationDialogs() {
        booleanSession = nil
        bodyCutSession = nil
    }

    /// The selected whole body objects, in selection order, which Boolean and Cut act on.
    private var selectedBodyObjectIDs: [SceneNodeID] {
        let nodes = snapshot.document.document.productMetadata.sceneNodes
        var seen = Set<SceneNodeID>()
        return snapshot.selection.selectedTargets.compactMap { target in
            guard target.component == .object, nodes[target.sceneNodeID]?.reference?.kind == .body,
                  seen.insert(target.sceneNodeID).inserted else { return nil }
            return target.sceneNodeID
        }
    }

    /// Ends every command that takes the viewport's clicks, and the modes a new command
    /// replaces, before a command that takes clicks starts. `viewportPointerOwner` hands a click
    /// to the first running command in its order, so one left running would take the new
    /// command's clicks (a Boolean left under Deform took Deform's face picks).
    private func endCommandsBeforePickingCommand() {
        cancelModelingOperation()
        pointPickRequest = nil
        placeSession = nil
        transformSession = nil
        mirrorSession = nil
        arraySession = nil
        viewAlignedConstructionPlaneRequest = nil
        curvePickCommand = nil
        cutCurveSession = nil
        filletSession = nil
        rebuildSession = nil
        deformSession = nil
        if slotProfileCommandState.isFreestyle {
            slotProfileCommandState.deactivate()
        }
        endBodyOperationDialogs()
        if selectedTool != .select { _ = setActiveTool(.select) }
    }

    /// Boolean (Q): the selected bodies become its targets and tool, and clicks on bodies add to
    /// or remove from the list the dialog picks.
    private func beginBoolean() {
        let bodies = selectedBodyObjectIDs
        endCommandsBeforePickingCommand()
        let boolean = WorkspaceBooleanSession(selectedBodies: bodies)
        booleanSession = boolean
        selectTargets(boolean.operands.map { SelectionTarget(sceneNodeID: $0) })
        reportToolStatus(boolean.prompt)
    }

    /// A click while Boolean runs: the body under the pointer joins or leaves the list being picked.
    private func pickBooleanBody(at target: ViewportCanvasTarget) {
        var resolver = selectionTargetResolver
        resolver.selectionScope = .object
        guard var boolean = booleanSession, let hit = target.hit,
              let body = resolver.selectionTarget(for: hit),
              snapshot.document.document.productMetadata.sceneNodes[body.sceneNodeID]?.reference?.kind == .body else {
            reportToolStatus("Boolean: click on a body.", severity: .warning)
            return
        }
        boolean.toggle(body.sceneNodeID)
        booleanSession = boolean
        selectTargets(boolean.operands.map { SelectionTarget(sceneNodeID: $0) })
        reportToolStatus(boolean.prompt)
    }

    /// G, R or S while Boolean runs: moves the tools where they are displayed, which is where the
    /// Boolean combines them; the dialog stays and shows its bodies again when the move ends.
    private func transformBooleanTools(_ mode: WorkspaceTransformSession.Mode) {
        guard let boolean = booleanSession, !boolean.tools.isEmpty else {
            reportToolStatus("Boolean: pick a tool to move first.", severity: .warning)
            return
        }
        selectTargets(boolean.tools.map { SelectionTarget(sceneNodeID: $0) })
        beginTransformSession(mode, sceneNodeIDs: boolean.tools)
    }

    /// Return or right-click while Boolean runs: the Boolean of its bodies; the dialog stays when
    /// the Boolean is refused.
    private func confirmBoolean() {
        guard let boolean = booleanSession else { return }
        let command: EditorCommand
        do {
            command = try boolean.command(in: snapshot.document.document)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return
        }
        submitDialogCommand([command], name: "Boolean", instance: boolean.instance,
                            running: { booleanSession?.instance }, end: { booleanSession = nil },
                            done: { reportToolStatus("Boolean \(boolean.title) done.") })
    }

    /// Cut (C with bodies selected): the selected bodies are cut by the selected curve objects and
    /// faces; clicks add to or remove from the list the dialog picks.
    private func beginBodyCut() {
        let cut = WorkspaceBodyCutSession(
            selection: snapshot.selection.selectedTargets, in: snapshot.document.document
        )
        endCommandsBeforePickingCommand()
        bodyCutSession = cut
        reportToolStatus(cut.prompt)
    }

    /// A click while Cut runs: a body joins or leaves the targets; a face, or a curve object (a
    /// sketch through any of its curves), joins or leaves the cutters.
    private func pickBodyCutOperand(at target: ViewportCanvasTarget) {
        guard var cut = bodyCutSession, let hit = target.hit else {
            reportToolStatus("Cut: click on a body, a curve or a face.", severity: .warning)
            return
        }
        let document = snapshot.document.document
        var resolver = selectionTargetResolver
        switch cut.picking {
        case .targets:
            resolver.selectionScope = .object
            guard let body = resolver.selectionTarget(for: hit),
                  document.productMetadata.sceneNodes[body.sceneNodeID]?.reference?.kind == .body else {
                reportToolStatus("Cut: click on a body to cut.", severity: .warning)
                return
            }
            cut.toggle(target: body.sceneNodeID)
        case .cutters:
            resolver.selectionScope = .sketchEntity
            if let curve = resolver.selectionTarget(for: hit), case .sketchEntity = curve.component,
               let node = document.productMetadata.sceneNodes[curve.sceneNodeID],
               WorkspaceBodyCutSession.isCurveObject(node, in: document) {
                cut.toggle(cutter: .curve(node.id))
            } else {
                resolver.selectionScope = .face
                guard let face = resolver.selectionTarget(for: hit), case .face = face.component else {
                    reportToolStatus("Cut: click on a curve or a face to cut with.", severity: .warning)
                    return
                }
                cut.toggle(cutter: .face(face))
            }
        }
        bodyCutSession = cut
        reportToolStatus(cut.prompt)
    }

    /// S while Cut runs: curve cutters run along the current view, or along their planes' normals
    /// again. The cut reaches through its targets both ways, so the view's sense does not matter.
    private func toggleBodyCutViewDirection() {
        guard var cut = bodyCutSession else { return }
        if cut.viewDirection != nil {
            cut.viewDirection = nil
            reportToolStatus("Cut: along each curve's plane normal.")
        } else if let view = viewportProjectionBasis.viewNormal {
            cut.viewDirection = view
            reportToolStatus("Cut: along the view.")
        } else {
            reportToolStatus("Cut: the view has no direction to cut along.", severity: .warning)
            return
        }
        bodyCutSession = cut
    }

    /// Return or right-click while Cut runs: the cut; the dialog stays when the cut is refused.
    private func confirmBodyCut() {
        guard let cut = bodyCutSession else { return }
        let command: EditorCommand
        do {
            command = try cut.command()
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return
        }
        submitDialogCommand([command], name: "Cut", instance: cut.instance,
                            running: { bodyCutSession?.instance }, end: { bodyCutSession = nil },
                            done: { reportToolStatus("Cut done.") })
    }

    /// Starts Trim, Split Segment or Insert Knot, ending the command that held the clicks before.
    private func beginCurvePickCommand(_ command: WorkspaceCurvePickCommand) {
        endCommandsBeforePickingCommand()
        curvePickCommand = command
        reportToolStatus(command.prompt)
    }

    /// A Trim, Split Segment or Insert Knot click: the sketch curve under the pointer, in
    /// sketch-entity scope whatever the selection scope, and where the click's camera ray meets
    /// that curve's sketch plane.
    private func applyCurvePick(_ command: WorkspaceCurvePickCommand, at target: ViewportCanvasTarget) {
        var resolver = selectionTargetResolver
        resolver.selectionScope = .sketchEntity
        guard let hit = target.hit, let curve = resolver.selectionTarget(for: hit),
              case .sketchEntity = curve.component,
              let ray = target.pickRay else {
            reportToolStatus("\(command.title): click on a sketch curve.", severity: .warning)
            return
        }
        do {
            let point = try snapshot.document.document.sketchPlanePoint(
                alongRay: ray.origin, direction: ray.direction, on: curve
            )
            switch command {
            case .trim:
                submitSource(.trimSketchCurve(target: curve, point: point))
            case .splitSegment:
                submitSource(.splitSketchCurveAtPoint(target: curve, point: point))
            case .insertKnot:
                submitSource(.insertSketchSplineControlPointAtPoint(target: curve, point: point))
            case .bridge(let first):
                // The whole curve under the pointer, at the clicked fraction of it.
                let whole: SelectionTarget
                if case .sketchEntity(let componentID) = curve.component, let entity = componentID.sketchEntityReference {
                    whole = SelectionTarget(sceneNodeID: curve.sceneNodeID, component: .sketchEntity(.sketchEntity(featureID: entity.featureID, entityID: entity.entityID)))
                } else {
                    whole = curve
                }
                let end = SpatialBridgeEnd(
                    target: whole,
                    fraction: try snapshot.document.document.sketchCurveFraction(alongRay: ray.origin, direction: ray.direction, on: whole)
                )
                guard let first else {
                    curvePickCommand = .bridge(first: end)
                    reportToolStatus(WorkspaceCurvePickCommand.bridge(first: end).prompt)
                    return
                }
                curvePickCommand = nil
                submitSource(.createBridgeCurveBetweenEnds(first: first, second: end, continuity: .g1))
            }
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private func selectionTarget(for hit: ViewportHit) -> SelectionTarget? {
        selectionTargetResolver.selectionTarget(for: hit)
    }

    private func selectionTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        selectionTargetResolver.selectionTargets(for: hits)
    }

    private func setHoveredSceneNode(_ id: SceneNodeID?) {
        if id == nil {
            guard hoveredTarget != nil || hoveredReference != nil else {
                return
            }
        } else if displaySelection.hoveredSceneNodeID == id {
            return
        }
        _ = hoverSceneNode(id)
    }

    private func setHoveredTarget(_ target: SelectionTarget?) {
        if target == nil {
            guard hoveredTarget != nil || hoveredReference != nil else {
                return
            }
        } else if hoveredTarget == target {
            return
        }
        _ = hoverTarget(target)
    }

    private func setHoveredReference(_ reference: SelectionReference?) {
        if reference == nil {
            guard hoveredTarget != nil || hoveredReference != nil else {
                return
            }
        } else if hoveredReference == reference {
            return
        }
        _ = hoverReference(reference)
    }

    private func setHoveredSceneNode(_ id: SceneNodeID, isHovered: Bool) {
        if isHovered {
            setHoveredSceneNode(id)
        } else if displaySelection.hoveredSceneNodeID == id {
            setHoveredSceneNode(nil)
        }
    }

    @ViewBuilder
    private func componentDefinitionRow(_ id: ComponentDefinitionID) -> some View {
        switch sharedDefinitionSelection(id) {
        case .success(let shared):
            Button { selectSharedDefinition(id) } label: {
                Label {
                    HStack {
                        Text(shared.name)
                        Spacer(minLength: 8)
                        Text("\(shared.placementNodeIDs.count) objects")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    WorkspaceSidebarSymbol(systemName: "square.stack.3d.down.right")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(selectedSharedDefinitionID == id ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(shared.placementNodeIDs.isEmpty)
            .accessibilityIdentifier("SharedDefinition.select.\(id.description)")
            .help("Select every object using this shared shape")
        case .failure(let error):
            Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
        }
    }

    private func selectSharedDefinition(_ id: ComponentDefinitionID) {
        submitSelectionMutation({ selection, document in
            let shared = try SharedDefinitionSelection(definitionID: id, metadata: document.productMetadata)
            try selection.selectSceneNodes(shared.placementNodeIDs, in: document)
        }, completion: { _ in selectedSharedDefinitionID = id })
    }

    @ViewBuilder
    private var sharedDefinitionInspector: some View {
        if let id = selectedSharedDefinitionID {
            switch sharedDefinitionSelection(id) {
            case .success(let shared):
                inspectorSection("Shared Attributes") {
                    Text(shared.name).font(.headline)
                    Text("Applies to \(shared.placementNodeIDs.count) objects")
                    Text(shared.placementNodeIDs.compactMap { snapshot.document.document.productMetadata.sceneNodes[$0]?.name }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Position, rotation, scale and visibility remain individual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                objectShapeSection(shared.contentNodeIDs.compactMap { snapshot.document.document.productMetadata.sceneNodes[$0] }, showsPlacement: false)
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.red)
            }
        }
    }

    /// A shared definition's selection in the published document. Every definition's is made in
    /// one pass per document generation and read by each sidebar row and the inspector, where each
    /// read had rebuilt the scene hierarchy and its occurrences.
    private func sharedDefinitionSelection(_ id: ComponentDefinitionID) -> Result<SharedDefinitionSelection, any Error> {
        do {
            let all = try documentAnalysisCache.sharedDefinitions.value(for: snapshot.documentGeneration) {
                try SharedDefinitionSelection.all(in: snapshot.document.document.productMetadata)
            }
            guard let selection = all[id] else {
                return .failure(EditorError(code: .referenceUnresolved, message: "The shared definition no longer exists."))
            }
            return selection
        } catch {
            return .failure(error)
        }
    }

    private func sharedDefinitions(for nodes: [SceneNode]) throws -> [SharedDefinitionSelection] {
        let ids = Set(nodes.map(\.id))
        return try componentDefinitionIDs.compactMap { id in
            let shared = try sharedDefinitionSelection(id).get()
            return ids.isDisjoint(with: shared.placementNodeIDs) && ids.isDisjoint(with: shared.contentNodeIDs) ? nil : shared
        }
    }

    private func browserAssetRow(_ row: SidebarAssetRow) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            WorkspaceSidebarSymbol(systemName: row.systemImage)
        }
    }

    // MARK: - Scene Node Lifecycle

    /// Collects `ids` under a new group and leaves that group selected.
    private func groupSceneNodes(_ ids: [SceneNodeID]) {
        submitSource(name: "groupSceneNodes") { current in
            let metadata = current.document.document.productMetadata
            let state = WorkspaceSelectionPlacementActionState(
                metadata: metadata,
                selectedSceneNodeIDs: ids
            )
            guard state.canGroup else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The selection holds nothing that can be grouped."
                )
            }
            let name = SceneNodeNameAllocator().uniqueName(base: "Group", in: metadata)
            return [
                .groupSceneNodes(name: name, memberIDs: state.placeableIDs, origin: nil),
            ]
        } completion: { results in
            guard let groupID = results.last?.generatedIdentities.sceneNodeIDs.first else {
                return
            }
            selectSceneNodes([groupID])
        }
    }

    /// Dissolves the groups among `ids` and leaves the released members selected.
    ///
    /// The members are read before the command runs because afterwards the groups that named them
    /// are gone.
    private func ungroupSceneNodes(_ ids: [SceneNodeID]) {
        let metadata = snapshot.document.document.productMetadata
        let releasedIDs = WorkspaceSelectionPlacementActionState(
            metadata: metadata,
            selectedSceneNodeIDs: ids
        )
        .dissolvableGroupIDs
        .flatMap { metadata.sceneNodes[$0]?.childIDs ?? [] }

        submitSource(name: "ungroupSceneNodes") { current in
            let state = WorkspaceSelectionPlacementActionState(
                metadata: current.document.document.productMetadata,
                selectedSceneNodeIDs: ids
            )
            guard state.canUngroup else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The selection holds no group that can be dissolved."
                )
            }
            return state.dissolvableGroupIDs.map { .ungroupSceneNode(id: $0) }
        } completion: { _ in
            guard releasedIDs.isEmpty == false else { return }
            selectSceneNodes(releasedIDs)
        }
    }

    /// Deletes `ids` together with everything that cannot outlive them.
    ///
    /// A delete reaches past the selection whenever a selected feature has dependents, and by the
    /// time the user looks, the rows that would have shown it are gone. So the reach is reported.
    /// The Edit menu actions for the current selection.
    private var workspaceEditCommands: WorkspaceEditCommands {
        let duplicate: (@MainActor () -> Void)?
        if let ids = duplicableSelectionIDs {
            duplicate = { duplicateSceneNodes(ids) }
        } else {
            duplicate = nil
        }
        let arrayIDs = duplicableSelectionIDs
        func arrayAction(_ kind: WorkspacePatternArrayCreationPlanner.Kind) -> (@MainActor () -> Void)? {
            guard let arrayIDs else { return nil }
            return { beginPatternArrayCreation(kind, rootSceneNodeIDs: arrayIDs) }
        }
        let place: (@MainActor () -> Void)?
        if let ids = duplicableSelectionIDs {
            place = { beginPlaceSession(rootSceneNodeIDs: ids) }
        } else {
            place = nil
        }
        let copyWithPlacement: (@MainActor () -> Void)?
        if let ids = duplicableSelectionIDs {
            copyWithPlacement = {
                if let refusal = snapshot.document.document.productMetadata.placementCopyRefusal(for: ids) {
                    reportToolStatus(refusal.message, severity: .warning)
                    return
                }
                placeSession = nil
                let request = WorkspacePointPickRequest.copyReferencePoint(rootSceneNodeIDs: ids)
                pointPickRequest = request
                reportToolStatus(request.prompt)
            }
        } else {
            copyWithPlacement = nil
        }
        let mirror: (@MainActor () -> Void)?
        if let ids = duplicableSelectionIDs {
            mirror = { beginMirrorSession(sceneNodeIDs: ids) }
        } else {
            mirror = nil
        }
        return WorkspaceEditCommands(
            duplicate: duplicate,
            mirror: mirror,
            place: place,
            copyWithPlacement: copyWithPlacement,
            pasteWithPlacement: { beginPasteWithPlacement() },
            rectangularArray: arrayAction(.rectangular),
            radialArray: arrayAction(.radial),
            curveArray: arrayAction(.curve),
            completeEdge: completeEdgeAction,
            subdivide: subdivideAction,
            splitSegment: splitSegmentAction,
            bridge: bridgeAction,
            deleteRedundantTopology: deleteRedundantTopologyAction,
            text: { isTextDialogPresented = true },
            alignVertex: alignVertexAction,
            reverseCurves: reverseCurvesAction,
            createInstance: createInstanceAction,
            realizeInstances: realizeInstancesAction,
            insertKnot: selectedTool == .select ? insertKnotAction : nil,
            raiseCurveDegree: raiseCurveDegreeAction,
            convertVertex: convertVertexAction,
            rebuild: rebuildAction,
            deform: deformAction,
            createOutline: createOutlineAction
        )
    }

    /// The Bridge Curve the inspector shows for the selection, if one is selected.
    private var selectedBridgeCurve: InspectorBridgeCurve? {
        sketchCommandTargetResolver.entity(from: selectedSketchEntityResult)?.bridgeCurve
    }

    /// The selected sketch curves and vertices, in selection order.
    private var selectedSketchTargets: [SelectionTarget] {
        snapshot.selection.selectedTargets.filter { target in
            if case .sketchEntity = target.component { return true }
            return false
        }
    }

    /// Join Curves' endpoint feedback on the selected sketch curves, where J joins them: ends
    /// that meet another selected curve's end blue-green, the others purple. A selection Core
    /// cannot read shows none; J reports why.
    private var viewportSketchJoinEndpointFeedback: [SketchCurveJoinEndpointFeedback] {
        guard selectedTool == .select, selectionScope == .sketchEntity else { return [] }
        do {
            return try snapshot.document.document.sketchCurveJoinEndpointFeedback(targets: selectedSketchTargets)
        } catch {
            return []
        }
    }

    /// Bridge on two selected sketch curves or curve ends (Edit menu and L).
    private var bridgeAction: (@MainActor () -> Void)? {
        let targets = snapshot.selection.selectedTargets
        guard selectedTool == .select else { return nil }
        // Nothing selected: the ends are placed by clicking.
        if targets.isEmpty {
            return { beginCurvePickCommand(.bridge(first: nil)) }
        }
        guard targets.count == 2 else { return nil }
        if targets.allSatisfy({ if case .sketchEntity = $0.component { return true }; return false }),
           targets[0].sceneNodeID == targets[1].sceneNodeID {
            return { createBridge(joining: targets) }
        }
        // Two body edges: Bridge Edge's dialog, seeded with their nearest ends.
        if targets.allSatisfy({ if case .edge = $0.component { return true }; return false }) {
            return {
                do {
                    bridgeEdgeSession = WorkspaceBridgeEdgeSession(
                        nearest: try snapshot.document.document.spatialBridgeEnds(
                            joining: targets, objectRegistry: objectRegistry,
                            currentEvaluation: snapshot.cadInteraction, currentGeneration: snapshot.documentGeneration
                        )
                    )
                    reportToolStatus("Bridge Edge: choose the sides, continuity and tension, then OK, Return or right-click.")
                } catch {
                    reportToolStatus(error.localizedDescription, severity: .warning)
                }
            }
        }
        // Curves of different sketches: a spatial bridge at their nearest ends.
        guard targets.allSatisfy({ target in
            switch target.component {
            case .sketchEntity, .edge: return true
            default: return false
            }
        }) else { return nil }
        return {
            submitSource(name: "Bridge", commands: { current in
                let ends = try current.document.document.spatialBridgeEnds(
                    joining: targets, objectRegistry: current.objectRegistry,
                    currentEvaluation: current.cadInteraction, currentGeneration: current.documentGeneration
                )
                return [.createBridgeCurveBetweenEnds(first: ends.0, second: ends.1, continuity: .g1)]
            })
        }
    }

    /// Joins two curves at their nearest ends, or two curve ends, with a G1 Bridge Curve and selects
    /// it, so its continuity, tension and trim are edited in its inspector.
    private func createBridge(joining targets: [SelectionTarget]) {
        let existing = Set(snapshot.document.document.productMetadata.bridgeCurveSources.keys)
        submitSource(name: "Bridge", commands: { current in
            let ends = try current.document.document.bridgeEndpoints(for: targets)
            return [
                .createBridgeCurve(
                    featureID: ends.featureID,
                    firstEndpoint: ends.first,
                    secondEndpoint: ends.second,
                    continuity: .g1
                ),
            ]
        }) { results in
            guard results.last?.didMutate == true, let document = workspace.view?.document.document,
                  let created = document.productMetadata.bridgeCurveSources.first(where: { !existing.contains($0.key) })?.value,
                  let target = try SketchEntitySnapshotService().snapshot(document: document).entries.first(where: {
                      $0.entityID == created.entityID.description && $0.sceneNodeID == targets[0].sceneNodeID.description
                  })?.selectionTarget() else { return }
            selectTargets([target])
            reportToolStatus("Bridge: edit continuity, tension and trim in the inspector.")
        }
    }

    /// Text's curves: every contour of the typed text's glyphs, in the chosen font and size, as one
    /// closed spline of a new curve sketch on the active construction plane, the baseline starting
    /// at its origin.
    private func createTextCurves() {
        let contours: [[Point2D]]
        do {
            contours = try SketchTextOutliner().contours(
                of: textDialogText, fontName: textDialogFontFamily, size: textDialogSizeMeters
            )
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return
        }
        isTextDialogPresented = false
        var entities: [SketchEntityID: SketchEntity] = [:]
        for contour in contours {
            entities[SketchEntityID()] = .spline(SketchSpline(
                controlPoints: contour.map { SketchPoint(x: .length($0.x, .meter), y: .length($0.y, .meter)) },
                isClosed: true
            ))
        }
        submitSource(
            .createSketch(
                name: "Text",
                sketch: Sketch(plane: activeSketchPlane(), entities: entities),
                geometryRole: .curve
            )
        ) { result in
            if result?.didMutate == true { reportToolStatus("Text: \(contours.count) curves.") }
        }
    }

    /// Delete Redundant Topology on the selected spline (Edit menu, palette).
    private var deleteRedundantTopologyAction: (@MainActor () -> Void)? {
        guard let entity = sketchCommandTargetResolver.entity(from: selectedSketchEntityResult),
              entity.entityKind == "spline",
              let target = sketchCommandTargetResolver.slotSourceCurveTarget(for: entity) else { return nil }
        return {
            submitSource(.deleteRedundantSketchSplineJoints(target: target)) { result in
                if result?.didMutate == true { reportToolStatus("Delete Redundant Topology: joints one cubic spans removed.") }
            }
        }
    }

    /// Align Vertex on the selected curve end and the other selected end (Edit menu, palette), at
    /// the inspector's continuity, which Tab steps.
    private var alignVertexAction: (@MainActor () -> Void)? {
        let curves = selectedSketchCurveTargets
        if curves.count == 2, snapshot.selection.selectedTargets.count == 2 {
            // Align on two curves: their nearest ends, the second aligned with the first.
            return {
                submitSource(.alignSketchCurveEnds(
                    first: curves[0],
                    second: curves[1],
                    options: SketchVertexAlignmentOptions(continuity: sketchVertexAlignmentContinuity)
                ))
            }
        }
        guard let entity = sketchCommandTargetResolver.entity(from: selectedSketchEntityResult),
              selectedSketchVertexAlignmentReferenceTarget(for: entity) != nil else { return nil }
        return { alignSelectedSketchVertex(entity) }
    }

    /// The selected sketch curves themselves, not their vertices or control points.
    private var selectedSketchCurveTargets: [SelectionTarget] {
        snapshot.selection.selectedTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchEntityReference != nil
                && componentID.sketchPointHandleReference == nil
                && componentID.sketchControlPointReference == nil
        }
    }

    /// Raise Curve Degree on every selected sketch curve (Shift-S, Edit menu, palette), as one step;
    /// the raised curves' control points are selected, as Plasticity selects the new CVs.
    private var raiseCurveDegreeAction: (@MainActor () -> Void)? {
        let curves = selectedSketchCurveTargets
        guard !curves.isEmpty else { return nil }
        return {
            submitSource(.raiseSketchCurveDegree(targets: curves)) { result in
                guard result?.didMutate == true, let document = workspace.view?.document.document else { return }
                let raised = Set(curves.compactMap { target -> String? in
                    guard case .sketchEntity(let componentID) = target.component else { return nil }
                    return componentID.sketchEntityReference?.entityID.description
                })
                let entries: [SketchEntitySummaryResult.EntityEntry]
                do {
                    entries = try SketchEntitySnapshotService().snapshot(document: document).entries
                } catch {
                    reportToolStatus("Raise Curve Degree: the raised control points could not be read: \(error.localizedDescription)", severity: .warning)
                    return
                }
                let targets = entries.filter { raised.contains($0.entityID) }.flatMap { entry -> [SelectionTarget] in
                    guard let sceneNodeID = entry.sceneNodeID.flatMap(UUID.init(uuidString:)) else { return [] }
                    return entry.controlPointTargets.map {
                        SelectionTarget(
                            sceneNodeID: SceneNodeID(sceneNodeID),
                            component: .sketchEntity(SelectionComponentID(rawValue: $0.selectionComponentID))
                        )
                    }
                }
                if !targets.isEmpty { selectTargets(targets) }
                reportToolStatus("Raise Curve Degree: \(curves.count) curve\(curves.count == 1 ? "" : "s") one degree up.")
            }
        }
    }

    /// The one other whole curve selected beside a curve end, which Extend can reach.
    private func extendLimitCurveTarget(for entity: InspectorSketchEntity) -> SelectionTarget? {
        let others = selectedSketchCurveTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityReference else { return false }
            return reference.entityID != entity.entityID
        }
        if others.count == 1 { return others.first }
        // Extend to a sheet or solid: one whole body selected beside the curve end.
        let extendLimitBodies = snapshot.selection.selectedTargets.filter { target in
            target.component == .object
                && snapshot.document.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.kind == .body
        }
        return others.isEmpty && extendLimitBodies.count == 1 ? extendLimitBodies.first : nil
    }

    /// Rebuild Curve's dialog on the selected splines (Edit menu, palette).
    private var rebuildAction: (@MainActor () -> Void)? {
        let splines = selectedSketchCurveTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityReference,
                  case .sketch(let sketch)? = snapshot.document.document.cadDocument.designGraph.nodes[reference.featureID]?.operation,
                  case .spline? = sketch.entities[reference.entityID] else { return false }
            return true
        }
        guard !splines.isEmpty else { return nil }
        return {
            rebuildSession = WorkspaceRebuildSession(
                selectedCurves: splines,
                method: .points,
                pointCount: sketchRebuildControlPointCount,
                toleranceMeters: sketchRebuildToleranceMeters,
                keepsCorners: sketchRebuildKeepsCorners,
                degree: sketchRebuildExplicitDegree,
                spanCount: sketchRebuildExplicitSpanCount,
                weight: sketchRebuildExplicitWeight
            )
            reportToolStatus("Rebuild: choose the method, then OK, Return or right-click.")
        }
    }

    /// Rebuild Curve's dialog: Method, that method's values and OK.
    @ViewBuilder
    private func rebuildContextPanelContent(_ rebuild: WorkspaceRebuildSession) -> some View {
        workspaceStatusChip("Rebuild", systemImage: "point.3.filled.connected.trianglepath.dotted", tint: .accentColor)
        Picker("Method", selection: Binding(
            get: { rebuild.method },
            set: { rebuildSession?.method = $0 }
        )) {
            ForEach(WorkspaceRebuildSession.Method.allCases, id: \.self) { method in
                Text(method.title).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceRebuild.method")
        switch rebuild.method {
        case .points:
            Stepper(value: Binding(
                get: { rebuild.pointCount },
                set: { rebuildSession?.pointCount = $0 }
            ), in: WorkspaceRebuildSession.pointCountRange) {
                Text("Points \(rebuild.pointCount)").monospacedDigit().font(.caption)
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceRebuild.points")
        case .refit:
            TextField("Tolerance", value: Binding(
                get: { rebuild.toleranceMeters * 1000 },
                set: { rebuildSession?.toleranceMeters = max($0, 1.0e-6) / 1000 }
            ), format: .number)
            .frame(width: 64)
            .accessibilityIdentifier("WorkspaceRebuild.tolerance")
            Text("mm").font(.caption)
            Toggle("Keep corners", isOn: Binding(
                get: { rebuild.keepsCorners },
                set: { rebuildSession?.keepsCorners = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .accessibilityIdentifier("WorkspaceRebuild.keepCorners")
        case .explicitControl:
            Stepper(value: Binding(get: { rebuild.degree }, set: { rebuildSession?.degree = $0 }), in: CurveRebuildOptions.explicitControlDegrees) {
                Text("Degree \(rebuild.degree)").monospacedDigit().font(.caption)
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceRebuild.degree")
            Stepper(value: Binding(get: { rebuild.spanCount }, set: { rebuildSession?.spanCount = $0 }), in: CurveRebuildOptions.explicitControlSpanCounts(degree: rebuild.degree)) {
                Text("Spans \(rebuild.spanCount)").monospacedDigit().font(.caption)
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceRebuild.spans")
            TextField("Weight", value: Binding(
                get: { rebuild.weight },
                set: { rebuildSession?.weight = min(max($0, 0), 1) }
            ), format: .number)
            .frame(width: 48)
            .accessibilityIdentifier("WorkspaceRebuild.weight")
        }
        Button("OK") { confirmRebuild() }
            .accessibilityIdentifier("WorkspaceRebuild.ok")
    }

    /// Create Outline on the selected bodies (palette): the outlines are selected with a Move
    /// running so they are placed, as Project Outline's are.
    private var createOutlineAction: (@MainActor () -> Void)? {
        let bodies = snapshot.selection.selectedTargets.filter { target in
            target.component == .object
                && snapshot.document.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.kind == .body
        }
        guard selectedTool == .select, !bodies.isEmpty else { return nil }
        return {
            submitSource(.createBodyOutlines(targets: bodies, plane: activeSketchPlane())) { result in
                moveCreatedObjects(of: result)
            }
        }
    }

    /// Deform's dialog on the selected sketch curves (Deform Curve) or body objects (Deform Solid
    /// and Sheet) (palette); a selection holding both offers neither.
    private var deformAction: (@MainActor () -> Void)? {
        let curves = selectedSketchCurveTargets
        let bodies = selectedBodyObjectIDs
        guard selectedTool == .select, WorkspaceDeformSession(selectedCurves: curves, selectedBodies: bodies) != nil else {
            return nil
        }
        return {
            guard let deform = WorkspaceDeformSession(selectedCurves: curves, selectedBodies: bodies) else { return }
            endCommandsBeforePickingCommand()
            deformSession = deform
            reportToolStatus(deform.prompt)
        }
    }

    /// A click in Offset's Freestyle: the distance (with its side) that puts the offset through
    /// the snapped point, set as Offset's distance; Return or right-click creates it.
    private func pickFreestyleOffset(at target: ViewportCanvasTarget) {
        guard let curve = selectedCurveOffsetTarget else {
            reportToolStatus("Offset Freestyle: select one sketch curve.", severity: .warning)
            return
        }
        let plane = effectiveSketchPlane(fallback: target.sketchPlane)
        guard let input = mappedCanvasInput(modelPoint: target.modelPoint,
            modelWorldPoint: target.modelWorldPoint,
            viewRayAnchorWorldPoint: target.viewRayAnchorWorldPoint, sketchPlane: plane) else { return }
        let snapped = snappedModelInput(input.point, modifierFlags: target.modifierFlags)
        guard let point = resolvedCanvasWorldPoint(for: snapped.point,
            snappedWorldPoint: snapped.worldPoint, fallbackWorldPoint: input.worldPoint,
            sketchPlane: plane) else { return }
        do {
            slotProfileWidthMeters = try snapshot.document.document.freestyleOffsetDistance(target: curve, through: point)
            reportToolStatus("Offset Freestyle: Return or right-click creates it.")
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    /// A click while Deform runs: the face under the pointer becomes the reference face, then
    /// the target face.
    private func pickDeformFace(at target: ViewportCanvasTarget) {
        var resolver = selectionTargetResolver
        resolver.selectionScope = .face
        guard var deform = deformSession, let hit = target.hit, let face = resolver.selectionTarget(for: hit),
              case .face = face.component else {
            reportToolStatus("Deform: click on a face of a body.", severity: .warning)
            return
        }
        deform.pick(face: face)
        deformSession = deform
        reportToolStatus(deform.prompt)
    }

    /// Deforms the dialog's curves as one step once both faces are picked; the dialog stays for
    /// another try when Core refuses.
    private func confirmDeform() {
        guard let deform = deformSession else { return }
        guard let command = deform.command else {
            reportToolStatus(deform.prompt, severity: .warning)
            return
        }
        submitDialogCommand([command], name: "Deform", instance: deform.instance,
                            running: { deformSession?.instance }, end: { deformSession = nil },
                            done: { reportToolStatus("Deform: \(deform.subjectDescription) deformed.") })
    }

    /// Makes the dialog's edge bridge as one step; the dialog stays for another try when Core
    /// refuses.
    private func confirmBridgeEdge() {
        guard let bridge = bridgeEdgeSession else { return }
        submitDialogCommand([bridge.command], name: "Bridge Edge", instance: bridge.instance,
                            running: { bridgeEdgeSession?.instance }, end: { bridgeEdgeSession = nil },
                            done: { reportToolStatus("Bridge Edge done.") })
    }

    /// Bridge Edge's dialog: Side 1 and 2, each end's continuity and tension, and OK.
    @ViewBuilder
    private func bridgeEdgeContextPanelContent(_ bridge: WorkspaceBridgeEdgeSession) -> some View {
        workspaceStatusChip("Bridge Edge", systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .accentColor)
        ForEach([(title: "Side 1", path: \WorkspaceBridgeEdgeSession.firstAtEnd), (title: "Side 2", path: \.secondAtEnd)], id: \.title) { side in
            Picker(side.title, selection: Binding(get: { bridge[keyPath: side.path] }, set: { bridgeEdgeSession?[keyPath: side.path] = $0 })) {
                Text("Start").tag(false)
                Text("End").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceBridgeEdge.\(side.title)")
        }
        ForEach([(title: "Continuity 1", path: \WorkspaceBridgeEdgeSession.continuity.first), (title: "Continuity 2", path: \.continuity.second)], id: \.title) { end in
            Picker(end.title, selection: Binding(get: { bridge[keyPath: end.path] }, set: { bridgeEdgeSession?[keyPath: end.path] = $0 })) {
                ForEach(BridgeCurveEndpointContinuity.allCases, id: \.self) { level in
                    Text(level.rawValue.uppercased()).tag(level)
                }
            }
            .fixedSize()
            .accessibilityIdentifier("WorkspaceBridgeEdge.\(end.title)")
        }
        ForEach([(title: "Tension 1", path: \WorkspaceBridgeEdgeSession.tensions.first), (title: "Tension 2", path: \.tensions.second)], id: \.title) { end in
            TextField(end.title, value: Binding(get: { bridge[keyPath: end.path] }, set: { bridgeEdgeSession?[keyPath: end.path] = $0 }), format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceBridgeEdge.\(end.title)")
        }
        workspaceIconButton(
            systemImage: "checkmark",
            help: "Bridge",
            accessibilityIdentifier: "WorkspaceBridgeEdge.apply",
            action: { confirmBridgeEdge() }
        )
    }

    /// Projects the dialog's curves onto its face as one step; the dialog stays for another try
    /// when Core refuses.
    private func confirmProject() {
        guard let project = projectSession else { return }
        let normal: Vector3D
        do {
            normal = try SketchPlaneCoordinateSystem(plane: activeSketchPlane()).normal
        } catch {
            reportToolStatus("Project: the construction plane has no normal: \(error.localizedDescription)", severity: .warning)
            return
        }
        submitDialogCommand([project.command(constructionPlaneNormal: normal)], name: "Project",
                            instance: project.instance,
                            running: { projectSession?.instance }, end: { projectSession = nil },
                            done: { reportToolStatus("Project: \(project.curves.count) curve\(project.curves.count == 1 ? "" : "s") projected.") })
    }

    /// Project Curve Body's dialog: Method, Vector's direction and Bidirectional, and OK.
    @ViewBuilder
    private func projectContextPanelContent(_ project: WorkspaceProjectSession) -> some View {
        workspaceStatusChip("Project", systemImage: "arrow.down.to.line", tint: .accentColor)
        Picker("Method", selection: Binding(get: { project.method }, set: { projectSession?.method = $0 })) {
            ForEach(WorkspaceProjectSession.Method.allCases, id: \.self) { method in
                Text(method.title).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("WorkspaceProject.method")
        if project.method == .vector {
            ForEach(Array(zip(["X", "Y", "Z"], [\WorkspaceProjectSession.vectorX, \.vectorY, \.vectorZ])), id: \.0) { axis, path in
                TextField(axis, value: Binding(
                    get: { project[keyPath: path] },
                    set: { projectSession?[keyPath: path] = $0 }
                ), format: .number)
                .frame(width: 48)
                .accessibilityIdentifier("WorkspaceProject.vector\(axis)")
            }
            Toggle("Bidirectional", isOn: Binding(get: { project.isBidirectional }, set: { projectSession?.isBidirectional = $0 }))
                .accessibilityIdentifier("WorkspaceProject.bidirectional")
        }
        workspaceIconButton(
            systemImage: "checkmark",
            help: "Project",
            accessibilityIdentifier: "WorkspaceProject.apply",
            action: { confirmProject() }
        )
    }

    /// Deform Curve's dialog: the faces picked so far, U/V/N scale and offset, the flips, Keep
    /// Tools and OK.
    @ViewBuilder
    private func deformContextPanelContent(_ deform: WorkspaceDeformSession) -> some View {
        workspaceStatusChip("Deform", systemImage: "wand.and.rays", tint: .accentColor)
        Text(deform.step == .referenceFace ? "Reference face" : deform.step == .targetFace ? "Target face" : "Faces picked")
            .font(.caption)
            .accessibilityIdentifier("WorkspaceDeform.step")
        if deform.step == .options {
            ForEach(Array(zip(["U", "V", "N"], [\CurveDeformationOptions.scaleU, \.scaleV, \.scaleN])), id: \.0) { axis, path in
                TextField("Scale \(axis)", value: Binding(
                    get: { deform.options[keyPath: path] },
                    set: { deformSession?.options[keyPath: path] = $0 }
                ), format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceDeform.scale\(axis)")
            }
            ForEach(Array(zip(["U", "V"], [\CurveDeformationOptions.offsetU, \.offsetV])), id: \.0) { axis, path in
                TextField("Offset \(axis)", value: Binding(
                    get: { deform.options[keyPath: path] },
                    set: { deformSession?.options[keyPath: path] = $0 }
                ), format: .number)
                .frame(width: 56)
                .accessibilityIdentifier("WorkspaceDeform.offset\(axis)")
            }
            commandDistanceInput(
                "Offset N", meters: Binding(get: { deform.offsetNMeters }, set: { deformSession?.offsetNMeters = $0 }),
                field: .deformOffset, accessibilityIdentifier: "WorkspaceDeform.offsetN"
            )
            Toggle("Mirror", isOn: Binding(get: { deform.options.mirrors }, set: { deformSession?.options.mirrors = $0 }))
                .accessibilityIdentifier("WorkspaceDeform.mirror")
            Toggle("UV", isOn: Binding(get: { deform.options.flipsUV }, set: { deformSession?.options.flipsUV = $0 }))
                .accessibilityIdentifier("WorkspaceDeform.flipUV")
            Toggle("Normal", isOn: Binding(get: { deform.options.flipsNormal }, set: { deformSession?.options.flipsNormal = $0 }))
                .accessibilityIdentifier("WorkspaceDeform.flipNormal")
            Toggle("Keep Tools", isOn: Binding(get: { deform.options.keepsTools }, set: { deformSession?.options.keepsTools = $0 }))
                .accessibilityIdentifier("WorkspaceDeform.keepTools")
            workspaceIconButton(
                systemImage: "checkmark",
                help: "Deform",
                accessibilityIdentifier: "WorkspaceDeform.apply",
                action: { confirmDeform() }
            )
        }
    }

    /// Rebuilds every curve of the running dialog as one step; the dialog stays for another try
    /// when Core refuses.
    private func confirmRebuild() {
        guard let rebuild = rebuildSession else { return }
        submitDialogCommand(rebuild.targets.map { .rebuildSketchCurve(target: $0, options: rebuild.options) },
                            name: "Rebuild", instance: rebuild.instance,
                            running: { rebuildSession?.instance }, end: { rebuildSession = nil },
                            done: { reportToolStatus("Rebuild: \(rebuild.targets.count) curve\(rebuild.targets.count == 1 ? "" : "s") rebuilt.") })
    }

    /// A double-click on a vertex a spline passes through converts it (Convert Vertex); a
    /// double-click anywhere else does nothing more than its click.
    private func viewportDoubleClickHandler() {
        guard selectedTool == .select,
              let vertex = snapshot.selection.selectedTargets.first,
              snapshot.selection.selectedTargets.count == 1,
              case .sketchEntity(let componentID) = vertex.component,
              let reference = componentID.sketchControlPointReference,
              let entity = sketchCommandTargetResolver.entity(from: selectedSketchEntityResult),
              entity.entityKind == "spline",
              reference.index > 0, reference.index < entity.controlPoints.count - 1,
              entity.splineJointIndexes.contains(reference.index),
              let convert = convertVertexAction else { return }
        convert()
    }

    /// Convert Vertex on the selected spline vertex (Edit menu, palette).
    private var convertVertexAction: (@MainActor () -> Void)? {
        let vertices = snapshot.selection.selectedTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchControlPointReference != nil
        }
        guard vertices.count == 1, let vertex = vertices.first else { return nil }
        return {
            submitSource(.convertSketchSplineVertex(target: vertex)) { result in
                if result?.didMutate == true { reportToolStatus("Convert Vertex: the curve no longer passes through it.") }
            }
        }
    }

    /// Reverse Curve on every selected sketch curve (Edit menu, palette), as one step; Core refuses
    /// the whole step when one of them has no direction to reverse (a circle, or an arc until its
    /// direction is represented).
    private var reverseCurvesAction: (@MainActor () -> Void)? {
        let curves = snapshot.selection.selectedTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else { return false }
            return componentID.sketchEntityReference != nil
                && componentID.sketchPointHandleReference == nil
                && componentID.sketchControlPointReference == nil
        }
        guard !curves.isEmpty else { return nil }
        return {
            submitSource(curves.map { .reverseSketchCurve(target: $0) }, name: "Reverse Curve")
        }
    }

    /// Create Instance on the selection, offered when Core would copy it (Edit menu).
    private var createInstanceAction: (@MainActor () -> Void)? {
        guard let ids = duplicableSelectionIDs else { return nil }
        return { createInstance(of: ids) }
    }

    /// Create Instance (Edit menu): an instance of `ids` where they are, as one undo step, selected
    /// with a Move of it running so it is placed; Return or Escape ends the Move.
    private func createInstance(of ids: [SceneNodeID]) {
        submitSource(.placeSceneNodes(ids: ids, placements: [.identity], output: .componentInstance, boolean: nil)) { result in
            guard let generated = result?.generatedIdentities.sceneNodeIDs,
                  let metadata = workspace.view?.document.document.productMetadata else { return }
            let instanceIDs = generated.filter { metadata.sceneNodes[$0]?.reference?.kind == .componentInstance }
            guard !instanceIDs.isEmpty else { return }
            selectSceneNodes(instanceIDs)
            beginTransformSession(.move, sceneNodeIDs: instanceIDs)
        }
    }

    /// Realize Instances on the selected component instances (Edit menu).
    private var realizeInstancesAction: (@MainActor () -> Void)? {
        let document = snapshot.document.document
        let ids = snapshot.selection.wholeSceneNodeIDs.filter {
            document.productMetadata.sceneNodes[$0]?.reference?.kind == .componentInstance
        }
        guard !ids.isEmpty else { return nil }
        return {
            submitSource(.realizeComponentInstances(sceneNodeIDs: Array(ids))) { result in
                guard result?.didMutate == true else { return }
                reportToolStatus("Realized \(ids.count == 1 ? "the instance" : "\(ids.count) instances") as independent copies.")
            }
        }
    }

    /// Insert Knot from the Edit menu.
    private var insertKnotAction: @MainActor () -> Void {
        { beginCurvePickCommand(.insertKnot) }
    }

    /// Split Segment from the Edit menu, offered with the select tool.
    private var splitSegmentAction: (@MainActor () -> Void)? {
        guard selectedTool == .select else { return nil }
        return { beginCurvePickCommand(.splitSegment) }
    }

    private var curveRefinementPlanner: WorkspaceCurveRefinementPlanner {
        WorkspaceCurveRefinementPlanner(document: snapshot.document.document)
    }

    /// Complete Edge on the selected curves, or `nil` when none can be completed.
    private var completeEdgeAction: (@MainActor () -> Void)? {
        let commands = curveRefinementPlanner.completeEdgeCommands(for: snapshot.selection.selectedTargets)
        guard !commands.isEmpty else { return nil }
        return {
            submitSource(commands, name: "Complete Edge") { _ in
                reportToolStatus("Complete Edge extended \(commands.count == 1 ? "the curve" : "\(commands.count) curves").")
            }
        }
    }

    /// Subdivide on the selected splines and surfaces, or `nil` when none is selected. The control
    /// points it creates on curves become the selection.
    private var subdivideAction: (@MainActor () -> Void)? {
        do {
            let subdivision = try curveRefinementPlanner.subdivision(for: snapshot.selection.selectedTargets)
            guard !subdivision.commands.isEmpty else { return nil }
            return {
                submitSource(subdivision.commands, name: "Subdivide") { _ in
                    if !subdivision.createdControlPoints.isEmpty {
                        selectTargets(subdivision.createdControlPoints)
                    }
                    reportToolStatus("Subdivided.")
                }
            }
        } catch {
            return { reportToolStatus(error.localizedDescription, severity: .warning) }
        }
    }

    /// Starts making an array of `ids`: a rectangular array is made at once, a radial array waits
    /// for its center and a curve array for its path.
    private func beginPatternArrayCreation(
        _ kind: WorkspacePatternArrayCreationPlanner.Kind,
        rootSceneNodeIDs ids: [SceneNodeID]
    ) {
        let document = snapshot.document.document
        if let refusal = document.productMetadata.sceneCopyRefusal(for: ids) {
            reportToolStatus(refusal.message, severity: .warning)
            return
        }
        switch kind {
        case .rectangular:
            do {
                // Only the bounds space the array: the mesh volume spares an exact one.
                let measurement = try MeasurementService(volumeSource: .tessellatedMesh).measure(
                    document: document,
                    selection: snapshot.selection,
                    ruler: snapshot.workspaceState.ruler,
                    objectRegistry: objectRegistry,
                    currentEvaluation: snapshot.cadInteraction,
                    currentGeneration: snapshot.documentGeneration
                )
                guard let bounds = measurement.bounds else {
                    reportToolStatus("A rectangular array needs a selection with measurable bounds.", severity: .warning)
                    return
                }
                submitPatternArrayCreation(
                    try WorkspacePatternArrayCreationPlanner(metadata: document.productMetadata)
                        .rectangular(rootSceneNodeIDs: ids, selectionBounds: bounds),
                    originWorld: Point3D(
                        x: (bounds.minX + bounds.maxX) / 2,
                        y: (bounds.minY + bounds.maxY) / 2,
                        z: (bounds.minZ + bounds.maxZ) / 2
                    )
                )
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        case .radial:
            let request = WorkspacePointPickRequest.radialArrayCenter(rootSceneNodeIDs: ids)
            pointPickRequest = request
            reportToolStatus(request.prompt)
        case .curve:
            patternArrayCurvePathPickState.startNewArray(rootSceneNodeIDs: ids)
            reportToolStatus("Pick a sketch line, circle, arc or spline for the Curve Array path. Esc cancels.")
        }
    }

    /// Submits the array, selects it so the array inspector opens on it, and starts shaping it;
    /// rectangular directions are measured from `originWorld`.
    private func submitPatternArrayCreation(_ command: EditorCommand, originWorld: Point3D = .origin) {
        submitSource(command) { result in
            guard let sourceID = result?.generatedIdentities.patternArraySourceIDs.first,
                  let source = workspace.view?.document.document.productMetadata.patternArrays[sourceID] else {
                return
            }
            selectSceneNodes([source.rootSceneNodeID])
            var isRectangular = false
            if case .rectangular = source.distribution { isRectangular = true }
            let shaping = WorkspaceArrayCreationSession(
                sourceID: sourceID, originWorld: originWorld, isRectangular: isRectangular
            )
            arraySession = shaping
            reportToolStatus(shaping.prompt)
        }
    }

    /// Submits the array update `change` makes of the session's array in its own frame.
    private func updateArrayInSession(
        _ change: (inout WorkspaceArrayCreationSession, PatternArraySource, Transform3D) throws -> PatternArrayDistribution
    ) {
        guard var arrayCreation = arraySession else { return }
        let metadata = snapshot.document.document.productMetadata
        guard let source = metadata.patternArrays[arrayCreation.sourceID] else {
            arraySession = nil
            return
        }
        do {
            let frame = try SceneNodeHierarchy(metadata: metadata).parentWorldTransform(of: source.rootSceneNodeID)
            let distribution = try change(&arrayCreation, source, frame)
            arraySession = arrayCreation
            submitSource(.updatePatternArray(
                id: source.id, name: nil, definitionID: nil, distribution: distribution, outputMode: nil
            ))
            reportToolStatus(arrayCreation.prompt)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    /// A click sets the rectangular direction being picked to point at it, as far as it is.
    private func handleArrayDirectionPick(_ pick: ViewportPointPick) {
        switch pick {
        case .refused(let message):
            reportToolStatus(message, severity: .warning)
        case .point(let picked):
            do {
                let point = try exactPick(picked).point
                updateArrayInSession { shaping, source, frame in
                    try shaping.distribution(of: source, toward: point, patternFrame: frame)
                }
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func handleViewportPointPick(_ pick: ViewportPointPick) {
        if placeSession != nil {
            handlePlacePointPick(pick)
            return
        }
        if transformSession?.pendingPoint != nil {
            handleTransformPointPick(pick)
            return
        }
        if mirrorSession != nil {
            handleMirrorPointPick(pick)
            return
        }
        if arraySession?.pickingSlot != nil {
            handleArrayDirectionPick(pick)
            return
        }
        guard let request = pointPickRequest else {
            return
        }
        switch pick {
        case .refused(let message):
            reportToolStatus(message, severity: .warning)
        case .point(let picked):
            pointPickRequest = nil
            let exact: WorkspacePlaceSession.Reference
            do {
                exact = try exactPick(picked)
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
                return
            }
            let point = exact.point
            switch request {
            case .copyReferencePoint(let ids):
                do {
                    let document = snapshot.document.document
                    try WorkspaceSceneClipboard().write(WorkspaceScenePlacementPayload(
                        fragment: try document.sceneFragment(copying: ids),
                        basePoint: point,
                        baseNormal: exact.normal
                    ))
                    reportToolStatus("Copied \(ids.count) object(s) with placement. Paste with Placement places them.")
                } catch {
                    reportToolStatus(error.localizedDescription, severity: .warning)
                }
            case .radialArrayCenter(let ids):
                do {
                    let axis: Vector3D
                    if let plane = workspacePlaneMode.sketchPlane ?? activeConstructionPlane?.plane {
                        axis = try SketchPlaneCoordinateSystem(plane: plane).normal
                    } else {
                        axis = .unitZ
                    }
                    submitPatternArrayCreation(
                        try WorkspacePatternArrayCreationPlanner(metadata: snapshot.document.document.productMetadata)
                            .radial(rootSceneNodeIDs: ids, centerWorld: point, axisWorld: axis)
                    )
                } catch {
                    reportToolStatus(error.localizedDescription, severity: .warning)
                }
            }
        }
    }

    /// Starts Place for `ids`: the next click picks the source reference point.
    private func beginPlaceSession(rootSceneNodeIDs ids: [SceneNodeID]) {
        if let refusal = snapshot.document.document.productMetadata.sceneCopyRefusal(for: ids) {
            reportToolStatus(refusal.message, severity: .warning)
            return
        }
        pointPickRequest = nil
        curvePickCommand = nil
        cutCurveSession = nil
        filletSession = nil
        endBodyOperationDialogs()
        let place = WorkspacePlaceSession(rootSceneNodeIDs: ids)
        placeSession = place
        reportToolStatus(place.prompt)
    }

    /// Starts placing the objects Copy with Placement put on the pasteboard.
    private func beginPasteWithPlacement() {
        do {
            guard let payload = try WorkspaceSceneClipboard().read() else {
                reportToolStatus("Nothing copied with placement to paste.", severity: .warning)
                return
            }
            pointPickRequest = nil
            let place = WorkspacePlaceSession(pasting: payload)
            placeSession = place
            reportToolStatus(place.prompt)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    /// The construction plane Mirror's axis keys and freestyle line are read in.
    private var mirrorConstructionPlane: SketchPlane {
        workspacePlaneMode.sketchPlane ?? activeConstructionPlane?.plane ?? .xy
    }

    /// Starts Mirror on whole objects, across the construction plane's positive X.
    private func beginMirrorSession(sceneNodeIDs ids: [SceneNodeID]) {
        guard !ids.isEmpty else { return }
        do {
            pointPickRequest = nil
            placeSession = nil
            transformSession = nil
            curvePickCommand = nil
            cutCurveSession = nil
            filletSession = nil
            endBodyOperationDialogs()
            let mirror = try WorkspaceMirrorSession(sceneNodeIDs: ids, constructionPlane: mirrorConstructionPlane)
            mirrorSession = mirror
            reportToolStatus(mirror.prompt)
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private func reportMirrorOptions() {
        guard let mirrorSession else { return }
        let options = mirrorSession.options
        reportToolStatus(
            "Mirror across \(mirrorSession.planeName)"
                + (options.cutsAtPlane ? ", cut at the plane" : "")
                + (options.unionsHalves ? ", halves joined" : "")
                + (options.makesInstances ? ", as instances" : ", as copies")
                + "."
        )
    }

    /// Applies the mirror once, selects what it made and ends the session.
    private func applyMirror() {
        guard let mirror = mirrorSession else { return }
        mirrorSession = nil
        submitSource(mirror.command) { result in
            guard result != nil else { return }
            guard let generated = result?.generatedIdentities.sceneNodeIDs,
                  let metadata = workspace.view?.document.document.productMetadata, !generated.isEmpty else {
                reportToolStatus("Mirrored.")
                return
            }
            let generatedIDs = Set(generated)
            let childIDs = Set(generated.flatMap { metadata.sceneNodes[$0]?.childIDs ?? [] })
            selectSceneNodes(generated.filter { generatedIDs.contains($0) && !childIDs.contains($0) })
            reportToolStatus("Mirrored.")
        }
    }

    /// A click sets the plane tangent to the face clicked; in freestyle, clicks are the line's ends.
    private func handleMirrorPointPick(_ pick: ViewportPointPick) {
        guard var mirror = mirrorSession else { return }
        switch pick {
        case .refused(let message):
            reportToolStatus(message, severity: .warning)
        case .point(let picked):
            do {
                let exact = try exactPick(picked)
                if mirror.freestylePoints != nil {
                    try mirror.addFreestylePoint(exact.point, constructionPlane: mirrorConstructionPlane)
                } else {
                    guard let normal = exact.normal else {
                        reportToolStatus("Click a face to mirror across the plane touching it.", severity: .warning)
                        return
                    }
                    try mirror.choose(facePoint: exact.point, normal: normal)
                }
                mirrorSession = mirror
                reportToolStatus(mirror.prompt)
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    /// The selected objects' mass from their materials' densities, measured off the main actor
    /// when the selection or the document changes (`SelectionMassMeasurement`); no mass shows
    /// until the measurement for the current selection arrives, and a selection that cannot be
    /// measured shows none.
    private func refreshSelectionMass() {
        selectionMass = nil
        guard !snapshot.selection.wholeSceneNodeIDs.isEmpty else {
            selectionMassMeasurement.cancel()
            return
        }
        selectionMassMeasurement.measure(SelectionMassMeasurement.Request(
            document: snapshot.document.document,
            selection: snapshot.selection,
            ruler: snapshot.workspaceState.ruler,
            objectRegistry: objectRegistry,
            evaluation: snapshot.cadInteraction,
            generation: snapshot.documentGeneration
        )) { result in
            switch result {
            case .success(let mass):
                selectionMass = mass
            case .failure(let error):
                selectionMass = nil
                reportToolStatus("The selection's mass could not be measured: \(error.localizedDescription)", severity: .warning)
            }
        }
    }

    /// Starts Move, Rotate or Scale on whole objects.
    /// The selection scope whose targets a Move of `kind` moves.
    static func selectionScope(movedBy kind: BodyTopologyMoveKind) -> WorkspaceSelectionScope {
        switch kind {
        case .edges: .edge
        case .faces: .face
        case .vertices: .vertex
        }
    }

    /// The selected edges, faces or vertices, in their own scope, when they all belong to one body
    /// the kernel's direct edits can change.
    private var selectedMovableTopology: (kind: BodyTopologyMoveKind, targets: [SelectionTarget])? {
        let kind: BodyTopologyMoveKind
        switch selectionScope {
        case .edge: kind = .edges
        case .face: kind = .faces
        case .vertex: kind = .vertices
        default: return nil
        }
        let targets = snapshot.selection.selectedTargets
        guard let first = targets.first, targets.allSatisfy({ target in
            let componentID: SelectionComponentID
            switch (kind, target.component) {
            case (.edges, .edge(let id)), (.faces, .face(let id)), (.vertices, .vertex(let id)): componentID = id
            default: return false
            }
            return target.sceneNodeID == first.sceneNodeID && componentID.generatedTopologySubshapeID != nil
        }) else { return nil }
        return (kind, targets)
    }

    /// Move, Rotate or Scale (G, R, S) on selected edges, faces or vertices: typed motions and
    /// freestyle points move them with the kernel's direct edits.
    private func beginTopologyMoveSession(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        mode: WorkspaceTransformSession.Mode
    ) {
        guard let nodeID = targets.first?.sceneNodeID else { return }
        do {
            let hierarchy = try SceneNodeHierarchy(metadata: snapshot.document.document.productMetadata)
            var moving = WorkspaceTransformSession(sceneNodeIDs: [nodeID], mode: mode)
            moving.topologyTargets = targets
            moving.topologyKind = kind
            moving.topologyBodyWorldTransform = try hierarchy.worldTransform(of: nodeID)
            pointPickRequest = nil
            placeSession = nil
            curvePickCommand = nil
            cutCurveSession = nil
            filletSession = nil
            transformSession = moving
            transformFieldTexts = [:]
            refreshTransformFrame()
            if let transformSession { reportToolStatus(transformSession.prompt) }
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    /// Submits a transform motion; after a move of edges, faces or vertices the moved targets
    /// become the selection and the session's targets again.
    private func submitTransformCommand(_ command: EditorCommand) {
        let targets: [SelectionTarget]
        switch command {
        case .moveBodyEdges(let moved, _, _), .moveBodyFaces(let moved, _, _), .moveBodyVertices(let moved, _, _),
             .transformBodyTopology(_, let moved, _):
            targets = moved
        default:
            submitSource(command)
            return
        }
        submitSource(command) { result in
            guard result != nil, let nodeID = targets.first?.sceneNodeID,
                  let published = workspace.view,
                  let featureID = published.document.document.productMetadata.sceneNodes[nodeID]?.reference?.featureID else { return }
            do {
                // The published view carries the evaluation the commit produced.
                let moved = try published.document.document.topologyTargets(
                    following: targets, to: featureID, objectRegistry: objectRegistry,
                    currentEvaluation: published.cadInteraction, currentGeneration: published.documentGeneration
                )
                transformSession?.topologyTargets = moved
                selectTargets(moved)
                refreshTransformFrame()
            } catch {
                transformSession = nil
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func beginTransformSession(
        _ mode: WorkspaceTransformSession.Mode,
        sceneNodeIDs ids: [SceneNodeID]
    ) {
        guard !ids.isEmpty else { return }
        pointPickRequest = nil
        placeSession = nil
        curvePickCommand = nil
        cutCurveSession = nil
        filletSession = nil
        transformSession = WorkspaceTransformSession(sceneNodeIDs: ids, mode: mode)
        transformFieldTexts = [:]
        refreshTransformFrame()
        if let transformSession { reportToolStatus(transformSession.prompt) }
    }

    /// Resolves the transform frame for the current document; a frame that cannot be resolved
    /// ends the transform with the reason.
    private func refreshTransformFrame() {
        guard var transform = transformSession else { return }
        do {
            // A transform a command's completion starts moves what the command made, which only
            // the workspace's latest published view holds yet: this view value still holds the
            // one before it.
            let view = workspace.view ?? snapshot
            let document = view.document.document
            let bounds: MeasurementResult.Bounds?
            if transform.pickedPivot == nil, transform.pivotMode == .boundingBox {
                // The pivot bounds what the session moves: its own objects (a Boolean's tools
                // move while its dialog holds other bodies), or the moved topology.
                var moved = view.selection
                if transform.topologyTargets.isEmpty {
                    moved = SelectionModel()
                    try moved.selectTargets(transform.sceneNodeIDs.map { SelectionTarget(sceneNodeID: $0) }, in: document)
                }
                // Only the bounds place the pivot: the mesh volume spares an exact one.
                bounds = try MeasurementService(volumeSource: .tessellatedMesh).measure(
                    document: document,
                    selection: moved,
                    ruler: view.workspaceState.ruler,
                    objectRegistry: objectRegistry,
                    currentEvaluation: view.cadInteraction,
                    currentGeneration: view.documentGeneration
                ).bounds
            } else {
                bounds = nil
            }
            if bounds == nil, transform.pickedPivot == nil, transform.pivotMode == .boundingBox {
                // Measurements and other objects without solid bounds turn about their origins.
                transform.pivotMode = .median
                reportToolStatus("The selection has no measurable bounds; the pivot is the objects' origins.")
            }
            try transform.resolveFrame(
                metadata: document.productMetadata,
                constructionPlane: workspacePlaneMode.sketchPlane ?? activeConstructionPlane?.plane,
                selectionBounds: bounds
            )
            transformSession = transform
        } catch {
            transformSession = nil
            reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private func finishTransformSession() {
        guard let transformSession else { return }
        self.transformSession = nil
        transformFieldTexts = [:]
        reportToolStatus("\(transformSession.title) finished.")
    }

    private func reportTransformOptions() {
        guard let transformSession else { return }
        reportToolStatus(
            "\(transformSession.title): \(transformSession.constraintName), orientation "
                + transformSession.orientation.rawValue
                + ", pivot " + (transformSession.pickedPivot == nil ? transformSession.pivotMode.rawValue : "picked")
                + "."
        )
    }

    /// Submits one motion of the running transform.
    /// Applies every value typed into the transform dialog together as one motion and clears them.
    /// Returns false when a value is refused: the values stay for correction and the Return that
    /// submitted them goes no further.
    private func commitTypedTransformValues() -> Bool {
        guard transformSession != nil else { return true }
        let unit = snapshot.workspaceState.ruler.displayUnit
        var values: [WorkspaceTransformTypedField: Double] = [:]
        do {
            for (field, text) in transformFieldTexts {
                if let value = try field.value(of: text) { values[field] = value }
            }
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
        guard !values.isEmpty else { return true }
        guard applyTransformMotion({ transform in try transform.typedMotion(values, unit: unit) }) else {
            return false
        }
        transformFieldTexts = [:]
        return true
    }

    /// Submits the motion the running transform makes; false when it could not be made.
    @discardableResult
    private func applyTransformMotion(_ motion: (inout WorkspaceTransformSession) throws -> Transform3D) -> Bool {
        guard var transform = transformSession else { return false }
        do {
            let delta = try motion(&transform)
            transformSession = transform
            submitTransformCommand(try transform.command(worldDelta: delta))
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    /// V places the pivot; F's picks are the freestyle points, the last of which applies the motion.
    private func handleTransformPointPick(_ pick: ViewportPointPick) {
        guard var transform = transformSession, let role = transform.pendingPoint else { return }
        switch pick {
        case .refused(let message):
            reportToolStatus(message, severity: .warning)
        case .point(let picked):
            do {
                let exact = try exactPick(picked)
                switch role {
                case .pivot:
                    try transform.pickPivot(at: exact.point, normal: exact.normal)
                    transformSession = transform
                    refreshTransformFrame()
                    reportTransformOptions()
                case .freestyle:
                    let motion = try transform.addFreestylePoint(exact.point)
                    transformSession = transform
                    if let motion {
                        submitTransformCommand(try transform.command(worldDelta: motion))
                    }
                    reportToolStatus(transform.prompt)
                }
            } catch {
                transformSession?.freestylePoints = []
                transformSession?.pendingPoint = nil
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func reportPlaceOptions() {
        guard let placeSession else { return }
        let output = placeSession.output == .componentInstance ? "instances" : "copies"
        reportToolStatus(
            "Place: \(placeSession.copyCount) \(output)"
                + (placeSession.booleanOperation.map { ", \($0.rawValue) with the body clicked" } ?? ", new body")
                + ", up \(placeSession.upAxis.rawValue.uppercased())"
                + (placeSession.flipsOrientation ? ", flipped" : "")
                + ", angle \(placeSession.angleDegrees)°, scale \(placeSession.scale)."
        )
    }

    /// The first pick is the source reference; every later pick places the objects there.
    private func handlePlacePointPick(_ pick: ViewportPointPick) {
        guard var place = placeSession else { return }
        switch pick {
        case .refused(let message):
            reportToolStatus(message, severity: .warning)
        case .point(let picked):
            do {
                switch place.phase {
                case .source:
                    // A source normal comes only from the objects' own surface; a plane under
                    // them says nothing about which way they face.
                    place.pickSource(try exactPick(picked))
                    placeSession = place
                    reportToolStatus(place.prompt)
                case .destination:
                    var destination = try exactPick(picked)
                    // A destination on the construction plane lands on it with the plane's normal.
                    if destination.normal == nil, let plane = picked.plane {
                        destination.normal = try SketchPlaneCoordinateSystem(plane: plane).normal
                    }
                    destination.bodySceneNodeID = try pickedBodySceneNodeID(picked)
                    let command = try place.command(destination: destination)
                    submitSource(command) { result in
                        guard result != nil else { return }
                        reportToolStatus("Placed. Click another destination, or Esc to finish.")
                    }
                }
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    /// The scene node presenting the body a pick landed on; instances present no editable body.
    private func pickedBodySceneNodeID(_ picked: ViewportPickedPoint) throws -> SceneNodeID? {
        guard let occurrenceID = picked.occurrenceID else { return nil }
        let hierarchy = try SceneNodeHierarchy(metadata: snapshot.document.document.productMetadata)
        guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }),
              occurrence.componentInstanceID == nil else {
            return nil
        }
        return occurrence.sourceSceneNodeID
    }

    /// The picked point as exact geometry: a pick on a displayed CAD face becomes Swift-CAD's
    /// nearest point of that face with its outward normal; other picks keep their point and carry
    /// no surface normal.
    private func exactPick(_ picked: ViewportPickedPoint) throws -> WorkspacePlaceSession.Reference {
        guard let occurrenceID = picked.occurrenceID, let faceComponentID = picked.faceComponentID else {
            return WorkspacePlaceSession.Reference(point: picked.point, normal: nil)
        }
        let document = snapshot.document.document
        let topology = try TopologySnapshotService().snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: snapshot.cadInteraction,
            currentGeneration: snapshot.documentGeneration,
            metricPolicy: .omit
        )
        let exact = try PlacedSurfacePointResolver().exactPoint(
            near: picked.point,
            onFace: faceComponentID,
            of: occurrenceID,
            document: document,
            topology: topology
        )
        return WorkspacePlaceSession.Reference(point: exact.point, normal: exact.outwardNormal)
    }

    /// The whole-object selection when Duplicate accepts it, otherwise `nil`.
    private var duplicableSelectionIDs: [SceneNodeID]? {
        let ids = snapshot.selection.wholeSceneNodeIDs
        guard !ids.isEmpty,
              snapshot.document.document.productMetadata.sceneCopyRefusal(for: ids) == nil else {
            return nil
        }
        return ids
    }

    /// Copies `ids` in place as one undo step and selects the copies, so the Move gizmo moves them.
    private func duplicateSceneNodes(_ ids: [SceneNodeID]) {
        if let refusal = snapshot.document.document.productMetadata.sceneCopyRefusal(for: ids) {
            reportToolStatus(refusal.message, severity: .warning)
            return
        }
        submitSource(.duplicateSceneNodes(ids: ids)) { result in
            moveCreatedObjects(of: result)
        }
    }

    private func deleteSceneNodes(_ ids: [SceneNodeID]) {
        guard ids.isEmpty == false else { return }
        let plan: SceneNodeDeletionPlan
        do {
            plan = try SceneNodeDeletionPlanner().plan(
                metadata: snapshot.document.document.productMetadata,
                designGraph: snapshot.document.document.cadDocument.designGraph,
                ids: ids
            )
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return
        }
        submitSource(.deleteSceneNodes(ids: ids)) { result in
            guard result != nil, plan.dependentSceneNodeIDs.isEmpty == false else { return }
            reportToolStatus(
                """
                Deleted \(plan.sceneNodeIDs.count) objects, \
                including \(plan.dependentSceneNodeIDs.count) built from the selection.
                """
            )
        }
    }

    private var selectedSceneNodes: [SceneNode] {
        snapshot.selection.selectedSceneNodeIDs.compactMap { id in
            snapshot.document.document.productMetadata.sceneNodes[id]
        }
    }

    private var sketchEntityInspectorStateBuilder: WorkspaceSketchEntityInspectorStateBuilder {
        WorkspaceSketchEntityInspectorStateBuilder(
            document: snapshot.document.document,
            selection: snapshot.selection,
            displayUnit: snapshot.workspaceState.displayUnit,
            objectRegistry: objectRegistry,
            curveCurvatureDisplays: snapshot.workspaceState.curveCurvatureDisplays
        )
    }

    private var surfaceInspectorStateBuilder: WorkspaceSurfaceInspectorStateBuilder {
        WorkspaceSurfaceInspectorStateBuilder(
            document: snapshot.document.document,
            selection: snapshot.selection,
            currentEvaluation: snapshot.cadInteraction,
            documentGeneration: snapshot.documentGeneration,
            objectRegistry: objectRegistry,
            surfaceAnalysisOptions: surfaceAnalysisOptions.analysisOptions,
            workspaceState: snapshot.workspaceState,
            analysisCache: documentAnalysisCache
        )
    }

    private var sectionAnalysisStateBuilder: WorkspaceSectionAnalysisStateBuilder {
        WorkspaceSectionAnalysisStateBuilder(
            document: snapshot.document.document,
            currentEvaluation: snapshot.cadInteraction,
            documentGeneration: snapshot.documentGeneration,
            displayUnit: snapshot.workspaceState.displayUnit,
            objectRegistry: objectRegistry,
            analysisCache: documentAnalysisCache
        )
    }

    private var topologyEditInspectorStateBuilder: WorkspaceTopologyEditInspectorStateBuilder {
        WorkspaceTopologyEditInspectorStateBuilder(
            selection: snapshot.selection,
            selectedTargetSummary: selectedTargetSummary,
            faceOffsetStepMeters: defaultFaceOffsetStepMeters,
            edgeChamferStepMeters: defaultEdgeChamferStepMeters,
            edgeFilletRadiusMeters: defaultEdgeFilletRadiusMeters,
            vertexMoveStepMeters: defaultVertexMoveStepMeters,
            usesLockedRegionDistance: regionOffsetCommandState.usesLockedDistance,
            combinesRegions: regionOffsetCommandState.usesCombinedRegions
        )
    }

    private var constructionPlaneTargetSelectionBuilder: WorkspaceConstructionPlaneTargetSelectionBuilder {
        WorkspaceConstructionPlaneTargetSelectionBuilder(
            document: snapshot.document.document,
            selection: snapshot.selection
        )
    }

    private var selectionTargetClassification: WorkspaceSelectionTargetClassification {
        WorkspaceSelectionTargetClassification(selection: snapshot.selection)
    }

    private var selectionTargetResolver: WorkspaceSelectionTargetResolver {
        WorkspaceSelectionTargetResolver(
            document: snapshot.document.document,
            sceneBrowserRows: sceneBrowserRows,
            selectionScope: selectionScope,
            objectRegistry: objectRegistry,
            currentEvaluation: snapshot.cadInteraction,
            generation: snapshot.documentGeneration
        )
    }

    private var projectionTargetResolver: WorkspaceProjectionTargetResolver {
        WorkspaceProjectionTargetResolver(
            document: snapshot.document.document,
            selection: snapshot.selection,
            displayUnit: snapshot.workspaceState.displayUnit,
            objectRegistry: objectRegistry
        )
    }

    private var splineControlPointSelectionResolver: WorkspaceSplineControlPointSelectionResolver {
        WorkspaceSplineControlPointSelectionResolver(selection: snapshot.selection)
    }

    private var edgeOffsetSupportStateResolver: WorkspaceEdgeOffsetSupportStateResolver {
        WorkspaceEdgeOffsetSupportStateResolver(
            document: snapshot.document.document,
            selection: snapshot.selection,
            objectRegistry: objectRegistry
        )
    }

    private var sketchCommandTargetResolver: WorkspaceSketchCommandTargetResolver {
        WorkspaceSketchCommandTargetResolver()
    }

    private func patternArrayInspectorState(for nodes: [SceneNode]) -> PatternArrayInspectorState? {
        PatternArrayInspectorState(
            selectedNodes: nodes,
            sceneNodes: snapshot.document.document.productMetadata.sceneNodes,
            patternArrays: snapshot.document.document.productMetadata.patternArrays,
            summaryResult: patternArraySummaryCache.result(
                document: snapshot.document.document,
                generation: snapshot.documentGeneration,
                dirty: snapshot.isDirty
            )
        )
    }

    private var selectedTargetCount: Int {
        max(snapshot.selection.selectedTargets.count, snapshot.selection.selectedSceneNodeIDs.count)
    }

    private var selectedTargetSummary: String {
        let targets = snapshot.selection.selectedTargets
        guard !targets.isEmpty else {
            return "Object"
        }
        guard targets.count == 1, let target = targets.first else {
            return "\(targets.count) targets"
        }
        return selectionComponentTitle(target.component)
    }

    private var selectedFaceTarget: SelectionTarget? {
        topologyEditInspectorStateBuilder.faceTarget
    }

    private var selectedFaceTargets: [SelectionTarget] {
        topologyEditInspectorStateBuilder.faceTargets
    }

    private var selectedObjectDimensionTargets: [SelectionTarget] {
        selectionTargetClassification.objectDimensionTargets
    }

    private var selectedSketchDimensionTargets: [SelectionTarget] {
        selectionTargetClassification.sketchDimensionTargets
    }

    private var selectedEdgeTargets: [SelectionTarget] {
        topologyEditInspectorStateBuilder.edgeTargets
    }

    private var selectedEdgeOffsetSupportResolution: EdgeOffsetSupportFaceResolution {
        edgeOffsetSupportStateResolver.resolution(for: selectedEdgeTargets)
    }

    private var selectedVertexTarget: SelectionTarget? {
        topologyEditInspectorStateBuilder.vertexTarget
    }

    private var selectedVertexTargets: [SelectionTarget] {
        topologyEditInspectorStateBuilder.vertexTargets
    }

    private var selectedPolySplineSurfaceVertexTargets: [SelectionTarget] {
        selectedVertexTargets.filter(\.isGeneratedPolySplineSurfaceVertex)
    }

    private var selectedSurfaceControlPointReferences: [SelectionReference] {
        surfaceInspectorStateBuilder.surfaceControlPointReferences
    }

    private var selectedSurfaceParameterReferences: [SelectionReference] {
        surfaceInspectorStateBuilder.surfaceParameterReferences
    }

    private var selectedSketchPointTargets: [SelectionTarget] {
        constructionPlaneTargetSelectionBuilder.sketchPointTargets
    }

    private var selectedRegionTargets: [SelectionTarget] {
        topologyEditInspectorStateBuilder.regionTargets
    }

    private var selectedConstructionPlaneTargets: [SelectionTarget]? {
        constructionPlaneTargetSelectionBuilder.constructionPlaneTargets
    }

    /// The curve O offsets: an open curve, or a circle, which Slot does not take.
    private var selectedCurveOffsetTarget: SelectionTarget? {
        sketchCommandTargetResolver.curveOffsetTarget(
            for: sketchCommandTargetResolver.entity(from: selectedSketchEntityResult)
        )
    }

    private var selectedSlotSourceCurveTarget: SelectionTarget? {
        sketchCommandTargetResolver.slotSourceCurveTarget(
            for: sketchCommandTargetResolver.entity(from: selectedSketchEntityResult)
        )
    }

    private var selectedSketchVertexOffsetTarget: SelectionTarget? {
        sketchCommandTargetResolver.vertexOffsetTarget(
            for: sketchCommandTargetResolver.entity(from: selectedSketchEntityResult)
        )
    }

    private func selectedSketchEntityCutterTarget(
        excluding target: SelectionTarget
    ) -> SelectionTarget? {
        sketchEntityInspectorStateBuilder.cutterTarget(excluding: target)
    }

    private func selectedSketchCornerTreatmentAdjacentTarget(
        excluding target: SelectionTarget
    ) -> SelectionTarget? {
        sketchEntityInspectorStateBuilder.cornerTreatmentAdjacentTarget(excluding: target)
    }

    private func sketchCurveJoinInspectorState(
        for entity: InspectorSketchEntity
    ) -> SketchCurveJoinInspectorState {
        sketchEntityInspectorStateBuilder.joinState(for: entity)
    }

    private var selectedSketchEntityResult: Result<InspectorSketchEntity?, Error> {
        sketchEntityInspectorStateBuilder.selectedEntityResult()
    }

    private var selectedSurfaceControlPointInspectorStateResult:
        Result<SurfaceControlPointInspectorState?, Error> {
        surfaceInspectorStateBuilder.surfaceControlPointStateResult()
    }

    private var selectedSurfaceParameterInspectorStateResult:
        Result<SurfaceParameterInspectorState?, Error> {
        surfaceInspectorStateBuilder.surfaceParameterStateResult()
    }

    private var selectedSurfaceBoundaryContinuityStateResult:
        Result<SurfaceBoundaryContinuityInspectorState?, Error> {
        surfaceInspectorStateBuilder.surfaceBoundaryContinuityStateResult()
    }

    private var selectedSurfaceContinuitySummary: RupaCore.SurfaceContinuityResult? {
        surfaceInspectorStateBuilder.continuitySummary(for: selectedSceneNodes)
    }

    private var selectedSurfaceAnalysisSummary: SurfaceAnalysisResult? {
        surfaceInspectorStateBuilder.analysisSummary(for: selectedSceneNodes)
    }

    private var selectedSectionAnalysisSummary: SectionAnalysisResult? {
        sectionAnalysisStateBuilder.analysisSummary(for: selectedSceneNodes)
    }

    private func selectedSectionClippingPlan(
        for analysis: SectionAnalysisResult?
    ) -> SectionAnalysisClippingPlan? {
        guard let analysis,
              let retainedSide = sectionClippingMode.retainedSide else {
            return nil
        }
        return SectionAnalysisClippingPlan(
            result: analysis,
            retaining: retainedSide
        )
    }

    private func selectedSurfaceAnalysisResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceAnalysis?, Error> {
        surfaceInspectorStateBuilder.analysisResult(for: nodes)
    }

    private func selectedSurfaceContinuityResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceContinuity?, Error> {
        surfaceInspectorStateBuilder.continuityResult(for: nodes)
    }

    private func selectedSurfaceBasisStateResult(
        for nodes: [SceneNode]
    ) -> Result<SurfaceBasisInspectorState?, Error> {
        surfaceInspectorStateBuilder.surfaceBasisStateResult(for: nodes)
    }

    private var defaultFaceOffsetStepMeters: Double {
        workspaceInteractionScaleDefaults.operationStepMeters
    }

    private var defaultEdgeChamferStepMeters: Double {
        workspaceInteractionScaleDefaults.operationStepMeters
    }

    private var defaultEdgeFilletRadiusMeters: Double {
        workspaceInteractionScaleDefaults.operationStepMeters
    }

    private var defaultVertexMoveStepMeters: Double {
        workspaceInteractionScaleDefaults.operationStepMeters
    }

    private var defaultSketchEntityMoveStepMeters: Double {
        workspaceInteractionScaleDefaults.operationStepMeters
    }

    private var workspaceInteractionScaleDefaults: WorkspaceInteractionScaleDefaults {
        WorkspaceInteractionScaleDefaults(ruler: snapshot.workspaceState.ruler)
    }

    private func sketchCurveOperationControls(
        _ entity: InspectorSketchEntity,
        controls: [WorkspaceSketchCurveOperationControl]
    ) -> some View {
        WorkspaceSketchCurveOperationControlsView(
            entity: entity,
            controls: controls,
            state: sketchCurveOperationControlsState(for: entity),
            displayUnit: snapshot.workspaceState.displayUnit,
            extendDistanceMeters: $sketchExtendDistanceMeters,
            extendShape: $sketchExtendShape,
            vertexOffsetDistanceMeters: $sketchVertexOffsetDistanceMeters,
            cornerTreatmentDistanceMeters: $sketchCornerTreatmentDistanceMeters,
            cornerTreatment: $sketchCornerTreatment,
            joinContinuity: $sketchCurveJoinContinuity,
            vertexAlignmentContinuity: $sketchVertexAlignmentContinuity,
            vertexAlignmentDistanceMeters: $sketchVertexAlignmentDistanceMeters,
            vertexAlignmentParameter: sketchEntityInspectorStateBuilder.vertexAlignmentReferenceIsCurve(for: entity)
                ? $sketchVertexAlignmentParameter : nil,
            sliderMetersRange: { meters in
                lengthSliderMetersRange(for: meters)
            },
            onExtend: extendSelectedSketchCurve,
            onExtendToCurve: extendLimitCurveTarget(for: entity).map { limit in
                { target, shape in
                    submitSource(.extendSketchCurveToCurve(target: target, limit: limit, shape: shape))
                }
            },
            onOffsetVertex: offsetSelectedSketchVertex,
            onApplyCornerTreatment: applySelectedSketchCornerTreatment,
            onJoin: joinSelectedSketchCurves,
            onUnjoin: unjoinSelectedSketchCurve,
            onAlignVertex: alignSelectedSketchVertex,
            onProject: projectSelectedSketchCurvesToConstructionPlane
        )
    }

    private func sketchCurveOperationControlsState(
        for entity: InspectorSketchEntity
    ) -> WorkspaceSketchCurveOperationControlsState {
        sketchEntityInspectorStateBuilder.operationState(for: entity)
    }

    private func selectedSketchVertexOffsetHandle(_ entity: InspectorSketchEntity) -> SketchEntityPointHandle? {
        sketchCommandTargetResolver.vertexOffsetHandle(for: entity)
    }

    private func selectedSketchVertexAlignmentReferenceTarget(
        for entity: InspectorSketchEntity
    ) -> SelectionTarget? {
        sketchEntityInspectorStateBuilder.vertexAlignmentReferenceTarget(for: entity)
    }

    private func selectedSketchCurveProjectionTargets(
        for entity: InspectorSketchEntity
    ) -> [SelectionTarget] {
        projectionTargetResolver.sketchCurveProjectionTargets(for: entity)
    }

    private func selectionComponentTitle(_ component: SelectionComponent) -> String {
        switch component {
        case .object:
            return "Object"
        case .face(let face):
            return "\(selectionFaceTitle(face)) Face"
        case .edge(let edge):
            return "\(selectionEdgeTitle(edge)) Edge"
        case .vertex(let vertex):
            return "\(selectionVertexTitle(vertex)) Vertex"
        case .region:
            return "Region"
        case .sketchEntity:
            return "Source Curve"
        case .constructionPlane:
            return "Construction Plane"
        }
    }

    private func selectionFaceTitle(_ face: SelectionComponentID) -> String {
        switch face {
        case .bodyFaceFront:
            return "Front"
        case .bodyFaceBack:
            return "Back"
        case .bodyFaceTop:
            return "Top"
        case .bodyFaceBottom:
            return "Bottom"
        case .bodyFaceLeft:
            return "Left"
        case .bodyFaceRight:
            return "Right"
        case .bodyFaceSide:
            return "Side"
        default:
            return face.rawValue
        }
    }

    private func selectionEdgeTitle(_ edge: SelectionComponentID) -> String {
        switch edge {
        case .bodyEdgeLeftBottom:
            return "Left Bottom"
        case .bodyEdgeRightBottom:
            return "Right Bottom"
        case .bodyEdgeRightTop:
            return "Right Top"
        case .bodyEdgeLeftTop:
            return "Left Top"
        default:
            return edge.rawValue
        }
    }

    private func selectionVertexTitle(_ vertex: SelectionComponentID) -> String {
        vertex.rawValue
    }

    private var inspectorContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WorkspaceInspectorLayout.sectionSpacing) {
                if selectedSharedDefinitionID != nil {
                    sharedDefinitionInspector
                } else {
                    switch selectedSketchEntityResult {
                    case .success(let sketchEntity):
                        if let sketchEntity {
                            sketchEntityInspectorSections(sketchEntity)
                        } else {
                            nonSketchInspectorSections
                        }
                    case .failure(let error):
                        sketchEntityInspectorErrorSections(error)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, WorkspaceInspectorLayout.panelHorizontalInset)
            .padding(.vertical, WorkspaceInspectorLayout.panelVerticalInset)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("InspectorPanel")
    }

    @ViewBuilder
    private var nonSketchInspectorSections: some View {
        switch selectedSurfaceControlPointInspectorStateResult {
        case .success(let state):
            if let state {
                surfaceControlPointInspectorSection(state)
            } else {
                surfaceParameterOrObjectInspectorSections
            }
        case .failure(let error):
            surfaceControlPointInspectorErrorSections(error)
        }
    }

    @ViewBuilder
    private var surfaceParameterOrObjectInspectorSections: some View {
        switch selectedSurfaceParameterInspectorStateResult {
        case .success(let state):
            if let state {
                surfaceParameterInspectorSection(state)
            } else if selectedSceneNodes.isEmpty {
                canvasInspectorSections
            } else {
                objectInspectorSections(selectedSceneNodes)
            }
        case .failure(let error):
            surfaceParameterInspectorErrorSections(error)
        }
    }

    @ViewBuilder
    private var canvasInspectorSections: some View {
        WorkspaceDocumentInspectorView(
            state: workspaceDocumentInspectorState,
            setDisplayUnit: applyDisplayUnit,
            setWorkspaceScalePreset: {
                applyWorkspaceScalePreset($0)
            },
            fitWorkspaceScaleToModel: fitWorkspaceScaleToModel,
            applyWorkspaceRebaseTranslation: applyWorkspaceRebaseTranslation,
            setMinorTickMeters: { setRulerConfiguration(minorTickMeters: $0) },
            setMajorTickMeters: { setRulerConfiguration(majorTickMeters: $0) },
            setVisibleSpanMeters: { setRulerConfiguration(visibleSpanMeters: $0) },
            renameParameter: renameDocumentParameter,
            upsertParameterExpression: upsertParameterExpression,
            deleteParameter: deleteDocumentParameter
        )
    }

    private var workspaceDocumentInspectorState: WorkspaceDocumentInspectorState {
        let recommendationStates = workspaceDocumentRecommendationStates(
            bounds: presentationMeasurementBounds,
            ruler: snapshot.workspaceState.ruler,
            displayUnit: snapshot.workspaceState.displayUnit
        )
        return WorkspaceDocumentInspectorState(
            documentName: documentTitle,
            documentID: WorkspaceInspectorNumberText.shortID(snapshot.document.document.id),
            sourceUnitTitle: "m",
            displayUnit: snapshot.workspaceState.displayUnit,
            sourceFeatureCount: snapshot.document.document.cadDocument.designGraph.order.count,
            sceneNodeCount: snapshot.document.document.productMetadata.sceneNodes.count,
            selectedCount: snapshot.selection.selectedSceneNodeIDs.count,
            generatedBodyCount: snapshot.evaluationSnapshot.bodyCount,
            componentCount: snapshot.document.document.productMetadata.componentDefinitions.count,
            instanceCount: snapshot.document.document.productMetadata.componentInstances.count,
            evaluationTitle: evaluationStatusTitle,
            diagnosticSummary: diagnosticSummary,
            renderReasonTitle: renderInvalidationReasonTitle,
            renderGenerationTitle: renderInvalidationGenerationTitle,
            materialCount: snapshot.document.document.productMetadata.materialLibrary.materials.count,
            defaultMaterialTitle: defaultMaterialTitle,
            validationRuleCount: snapshot.document.document.productMetadata.validationRules.count,
            exportPresetCount: snapshot.document.document.productMetadata.exportPresets.count,
            ruler: snapshot.workspaceState.ruler,
            scaleRecommendation: recommendationStates.scale,
            scalePresetOptions: workspaceScalePresetOptionStates(
                ruler: snapshot.workspaceState.ruler
            ),
            precisionRecommendation: recommendationStates.precision,
            parameters: workspaceParameterInspectorState
        )
    }

    private var workspaceParameterInspectorState: WorkspaceParameterInspectorState {
        WorkspaceParameterInspectorState(
            result: ParameterListResult(
                document: snapshot.document.document,
                generation: snapshot.documentGeneration,
                dirty: snapshot.isDirty,
                diagnostics: diagnostics
            ),
            displayUnit: snapshot.workspaceState.displayUnit
        )
    }

    private func workspaceObjectOverviewInspectorState(
        for nodes: [SceneNode]
    ) -> WorkspaceObjectOverviewInspectorState {
        WorkspaceObjectOverviewInspectorStateBuilder(
            document: snapshot.document.document,
            displayUnit: snapshot.workspaceState.displayUnit,
            objectRegistry: objectRegistry,
            selectedTargetSummary: selectedTargetSummary,
            selectedTargetCount: selectedTargetCount
        )
        .state(for: nodes)
    }

    @ViewBuilder
    private func objectInspectorSections(_ nodes: [SceneNode]) -> some View {
        switch Result(catching: { try sharedDefinitions(for: nodes) }) {
        case .success(let definitions) where !definitions.isEmpty:
            let canEditPlacements = nodes.allSatisfy { node in
                !definitions.contains { shared in
                    shared.contentNodeIDs.contains(node.id) && !shared.placementNodeIDs.contains(node.id)
                }
            }
            if canEditPlacements {
                objectTransformInspectorSection(nodes)
            }
            inspectorSection("Shared Shape") {
                Text(canEditPlacements
                    ? "Placement changes affect only the selected objects."
                    : "This geometry is inside a shared definition. Select its scene placement to move it.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(definitions, id: \.definitionID) { shared in
                    Button { selectSharedDefinition(shared.definitionID) } label: {
                        Label("Edit \(shared.name) · \(shared.placementNodeIDs.count) objects", systemImage: "square.stack.3d.down.right")
                            .contentShape(Rectangle())
                    }
                }
                if let realize = realizeInstancesAction {
                    Button("Make Independent", action: realize).contentShape(Rectangle())
                }
            }
        case .success:
            independentObjectInspectorSections(nodes)
        case .failure(let error):
            Text(error.localizedDescription).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func independentObjectInspectorSections(_ nodes: [SceneNode]) -> some View {
        let overviewState = workspaceObjectOverviewInspectorState(for: nodes)
        objectTransformInspectorSection(nodes)
        objectShapeSection(nodes)
        DisclosureGroup("Object Details") {
            WorkspaceInspectorTextSectionView(section: overviewState.selectionSection)
            WorkspaceInspectorTextSectionView(section: overviewState.referenceSection)
            WorkspaceInspectorTextSectionView(section: overviewState.hierarchySection)
        }
        WorkspaceConstructionPlaneInspectorView(
            state: selectedConstructionPlaneInspectorState,
            displayUnit: snapshot.workspaceState.displayUnit,
            originSliderMetersRange: transformPositionSliderMetersRange,
            onSetOriginComponent: setSelectedConstructionPlaneOriginComponent,
            onSetNormalComponent: setSelectedConstructionPlaneNormalComponent,
            onActivate: activateSelectedConstructionPlane,
            onUpdateFromView: updateSelectedConstructionPlaneFromView
        )

        if let patternArrayState = patternArrayInspectorState(for: nodes) {
            patternArrayInspectorSection(patternArrayState)
        }

        sectionAnalysisInspectorSection(nodes)

        WorkspaceSurfaceInspectorView(
            basisStateResult: selectedSurfaceBasisStateResult(for: nodes),
            analysisResult: selectedSurfaceAnalysisResult(for: nodes),
            continuityResult: selectedSurfaceContinuityResult(for: nodes),
            boundaryContinuityStateResult: selectedSurfaceBoundaryContinuityStateResult,
            showsUnavailableSections: shouldShowSurfaceContinuitySection(for: nodes),
            displayUnit: snapshot.workspaceState.displayUnit,
            boundaryContinuityLevel: $surfaceBoundaryContinuityLevel,
            boundaryMatchSide: $surfaceBoundaryMatchSide,
            boundaryReferenceDirection: $surfaceBoundaryReferenceDirection,
            trimDomainULowerBound: $surfaceTrimDomainULowerBound,
            trimDomainUUpperBound: $surfaceTrimDomainUUpperBound,
            trimDomainVLowerBound: $surfaceTrimDomainVLowerBound,
            trimDomainVUpperBound: $surfaceTrimDomainVUpperBound,
            onMatchBoundaryContinuity: matchSurfaceBoundaryContinuity,
            onSetTrimDomain: setSurfaceTrimDomain,
            onSelectBasisReference: selectSurfaceBasisReference
        )

        projectCurvesToFaceSection()
        projectOutlineSection(nodes)
        WorkspaceTopologyEditInspectorView(
            state: topologyEditInspectorState(for: nodes),
            displayUnit: snapshot.workspaceState.displayUnit,
            faceDraftAngleDegrees: $faceDraftAngleDegrees,
            edgeOffsetDistanceMeters: $edgeOffsetDistanceMeters,
            edgeOffsetGapFill: $edgeOffsetGapFill,
            regionOffsetDistanceMeters: $regionOffsetDistanceMeters,
            regionOffsetGapFill: $regionOffsetGapFill,
            offsetSliderMetersRange: regionOffsetSliderMetersRange,
            onOffsetFace: { target, meters in
                offsetSelectedFace(target, by: meters)
            },
            onDeleteFaces: deleteSelectedFaces,
            onDraftFace: { targets, neutralTarget, angleDegrees in
                draftSelectedFaces(
                    targets,
                    neutralTarget: neutralTarget,
                    angleDegrees: angleDegrees
                )
            },
            onOffsetEdges: { targets, meters, gapFill in
                offsetSelectedEdges(targets, by: meters, gapFill: gapFill)
            },
            onProjectEdges: projectSelectedGeneratedEdgesToConstructionPlane,
            onFilletEdges: { targets, meters in
                beginEdgeTreatment(.fillet, targets: targets, meters: meters)
            },
            onChamferEdges: { targets, meters in
                beginEdgeTreatment(.chamfer, targets: targets, meters: meters)
            },
            onMoveVertex: { target, deltaX, deltaY in
                moveSelectedVertex(target, deltaX: deltaX, deltaY: deltaY)
            },
            onOffsetRegions: { targets, meters, gapFill, isSymmetric, combinesRegions in
                offsetSelectedRegions(
                    targets,
                    by: meters,
                    gapFill: gapFill,
                    isSymmetric: isSymmetric,
                    combinesRegions: combinesRegions
                )
            }
        )


    }

    /// The appearance each node in `nodes` can author.
    ///
    /// A node answering with nothing carries no appearance the Inspector can
    /// edit, so it is absent here and the section shows it no control. Core owns
    /// that answer. See `RupaCore/DESIGN.md`.
    private func objectAppearances(_ nodes: [SceneNode]) -> [SceneNodeID: RupaCore.Material] {
        let document = snapshot.document.document
        return nodes.reduce(into: [:]) { result, node in
            result[node.id] = document.authorableSceneNodeAppearance(id: node.id)
        }
    }

    private func objectTransformInspectorSection(_ nodes: [SceneNode]) -> some View {
        WorkspaceObjectTransformInspectorView(
            nodes: nodes,
            displayUnit: snapshot.workspaceState.displayUnit,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            materialOptions: sortedMaterialOptions,
            appearances: objectAppearances(nodes),
            onCommitProperties: { commands, name in
                submitSource(name: name) { current in
                    try commands.compactMap { command in
                        if case .setSceneNodeTransform(let id, let transform) = command {
                            return try WorkspaceTransformMatrix.command(setting: transform,
                                for: id, in: current.document.document)
                        }
                        return command
                    }
                }
            },
            mass: selectionMass,
            isBusy: modelingPreview.isBusy,
            onEditTransform: { component, value in
                let ids = nodes.map(\.id)
                submitSource(name: "Transform Objects") { current in
                    try WorkspaceTransformMatrix.commands(
                        replacing: component, with: value, nodeIDs: ids,
                        in: current.document.document)
                }
            }
        )
    }

    @ViewBuilder
    private func sectionAnalysisInspectorSection(_ nodes: [SceneNode]) -> some View {
        switch sectionAnalysisStateBuilder.analysisSummaryResult(for: nodes) {
        case .success(let analysis):
            if let analysis {
                inspectorSection("Section Analysis") {
                    workspaceInspectorValueRow("Plane", sectionAnalysisPlaneTitle(analysis.plane))
                    workspaceInspectorValueRow("Bodies", sectionAnalysisBodySummary(analysis))
                    workspaceInspectorValueRow("Contours", sectionAnalysisContourSummary(analysis))
                    workspaceInspectorValueRow("Segments", sectionAnalysisSegmentSummary(analysis))
                    inspectorControlRow("Clipping") {
                        Picker(
                            "",
                            selection: $sectionClippingMode
                        ) {
                            ForEach(WorkspaceSectionClippingMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: inspectorControlWidth)
                        .accessibilityIdentifier("InspectorSectionAnalysis.clipping")
                    }
                    workspaceInspectorValueRow("Clip State", sectionClippingMode.statusTitle)
                }
            }
        case .failure(let error):
            inspectorSection("Section Analysis") {
                workspaceInspectorValueRow("Status", "Unavailable")
                workspaceInspectorValueRow("Reason", error.localizedDescription)
            }
        }
    }

    private func sectionAnalysisPlaneTitle(
        _ plane: SectionAnalysisResult.Plane
    ) -> String {
        if let name = plane.sourceName,
           name.isEmpty == false {
            return name
        }
        if let id = plane.sourceID {
            return "\(sectionAnalysisPlaneSourceTitle(plane.sourceKind)) \(WorkspaceInspectorNumberText.shortID(id))"
        }
        return sectionAnalysisPlaneSourceTitle(plane.sourceKind)
    }

    private func sectionAnalysisPlaneSourceTitle(
        _ sourceKind: SectionAnalysisResult.PlaneSourceKind
    ) -> String {
        switch sourceKind {
        case .sketchPlane:
            "Sketch Plane"
        case .constructionPlane:
            "Construction Plane"
        case .activeConstructionPlane:
            "Active CPlane"
        case .sceneNode:
            "Scene Node"
        case .face:
            "Face"
        }
    }

    private func sectionAnalysisBodySummary(
        _ analysis: SectionAnalysisResult
    ) -> String {
        [
            "\(analysis.bodyCount) total",
            "\(analysis.intersectingBodyCount) intersecting",
            "\(analysis.spansPlaneBodyCount) spanning",
        ].joined(separator: ", ")
    }

    private func sectionAnalysisContourSummary(
        _ analysis: SectionAnalysisResult
    ) -> String {
        [
            "\(analysis.closedIntersectionContourCount) closed",
            "\(analysis.openIntersectionContourCount) open",
        ].joined(separator: ", ")
    }

    private func sectionAnalysisSegmentSummary(
        _ analysis: SectionAnalysisResult
    ) -> String {
        let suffix = analysis.truncatedIntersectionSegments ? " capped" : ""
        return "\(analysis.intersectionSegmentCount)\(suffix)"
    }

    private func topologyEditInspectorState(
        for nodes: [SceneNode]
    ) -> WorkspaceTopologyEditInspectorState {
        topologyEditInspectorStateBuilder.state(for: nodes)
    }

    private func patternArrayInspectorSection(_ state: PatternArrayInspectorState) -> some View {
        PatternArrayInspectorView(
            state: state,
            document: snapshot.document.document,
            workspaceState: snapshot.workspaceState,
            submit: { submitSource($0) },
            submitCurrent: { submitCurrentPatternArrayEdit(sourceID: state.sourceID, $0) },
            report: { reportToolStatus($0, severity: $1) },
            positionSliderMetersRange: transformPositionSliderMetersRange,
            defaultAxisDistanceMeters: workspaceInteractionScaleDefaults.operationStepMeters,
            isCurvePathPickActive: patternArrayCurvePathPickState.isPicking(sourceID: state.sourceID),
            onStartCurvePathPick: startPatternArrayCurvePathPick,
            onCancelCurvePathPick: cancelPatternArrayCurvePathPick
        )
    }

    private func patternArrayEditingService(
        sourceID: PatternArraySourceID
    ) -> PatternArrayEditingService {
        PatternArrayEditingService(
            document: snapshot.document.document,
            workspaceState: snapshot.workspaceState,
            submit: { submitSource($0) },
            report: { reportToolStatus($0, severity: $1) },
            sourceID: sourceID,
            submitCurrent: { submitCurrentPatternArrayEdit(sourceID: sourceID, $0) }
        )
    }

    private func submitCurrentPatternArrayEdit(
        sourceID: PatternArraySourceID,
        _ operation: @escaping PatternArrayEditingService.CurrentContextOperation
    ) {
        submitSource(name: "updatePatternArray") { current in
            guard current.document.document.productMetadata.patternArrays[sourceID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array source \(sourceID) no longer exists."
                )
            }
            var commands: [EditorCommand] = []
            let service = PatternArrayEditingService(
                document: current.document.document,
                workspaceState: current.workspaceState,
                submit: { commands.append($0) },
                report: { reportToolStatus($0, severity: $1) },
                sourceID: sourceID,
                submitCurrent: nil
            )
            operation(service)
            guard commands.isEmpty == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The pattern array edit is no longer applicable to the current source."
                )
            }
            return commands
        }
    }

    private func surfaceControlPointInspectorSection(
        _ state: SurfaceControlPointInspectorState
    ) -> some View {
        SurfaceControlPointInspectorView(
            state: state,
            workspaceState: snapshot.workspaceState,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            slideDistanceMeters: $polySplineSurfaceVertexSlideDistanceMeters,
            frameMoveUMeters: $surfaceControlPointFrameUMoveMeters,
            frameMoveVMeters: $surfaceControlPointFrameVMoveMeters,
            frameMoveNormalMeters: $surfaceControlPointFrameNormalMoveMeters,
            isSlideActive: slideCommandState.isSurfaceControlVerticesActive,
            slideRouteTitle: slideCommandState.routeTitle,
            onSetPointDisplay: setSurfaceControlPointDisplay,
            onSetFrameDisplay: setSurfaceFrameDisplay,
            onSetCoordinate: { axis, meters in
                setSurfaceControlPointCoordinate(axis, meters: meters, state: state)
            },
            onSetWeight: setSurfaceControlPointWeight,
            onMoveInFrame: { frame, uDistance, vDistance, normalDistance in
                moveSelectedSurfaceControlPointsInFrame(
                    state.selectedReferences,
                    frame: frame,
                    uDistanceMeters: uDistance,
                    vDistanceMeters: vDistance,
                    normalDistanceMeters: normalDistance
                )
            },
            onActivateSlide: activateSlideSurfaceControlVerticesCommand,
            onSlide: { direction in
                slideSelectedSurfaceControlPoints(
                    state.selectedReferences,
                    direction: direction
                )
            }
        )
    }

    private func surfaceParameterInspectorSection(
        _ state: SurfaceParameterInspectorState
    ) -> some View {
        SurfaceParameterInspectorView(
            state: state,
            knotInsertionValue: $surfaceKnotInsertionValue,
            spanSplitFraction: $surfaceSpanSplitFraction,
            knotMultiplicityValue: $surfaceKnotMultiplicityValue,
            onSetKnotValue: setSurfaceKnotValue,
            onInsertKnot: insertSurfaceKnot,
            onSplitSpan: splitSurfaceSpan,
            onSetKnotMultiplicity: setSurfaceKnotMultiplicity,
            onSetFrameDisplay: setSurfaceFrameDisplay
        )
    }

    private func selectSurfaceBasisReference(_ reference: SelectionReference) {
        submitSelectionMutation { selection, document in
            try selection.selectReference(reference, in: document)
        } completion: { published in
            dimensionCommandState.deactivate()
            syncOffsetCommandAvailability(for: published.selection)
            reportToolStatus("Surface basis reference selected.")
        }
    }

    @ViewBuilder
    private func surfaceControlPointInspectorErrorSections(_ error: Error) -> some View {
        inspectorSection("Surface CV") {
            inspectorRow("Target", selectedTargetSummary)
            inspectorRow("Status", "Unavailable")
            inspectorRow("Reason", error.localizedDescription)
        }
    }

    @ViewBuilder
    private func surfaceParameterInspectorErrorSections(_ error: Error) -> some View {
        inspectorSection("Surface Parameter") {
            inspectorRow("Target", selectedTargetSummary)
            inspectorRow("References", "\(selectedSurfaceParameterReferences.count)")
            inspectorRow("Status", "Unavailable")
            inspectorRow("Reason", error.localizedDescription)
        }
    }

    private func startPatternArrayCurvePathPick(sourceID: PatternArraySourceID) {
        patternArrayCurvePathPreviewCandidate = nil
        patternArrayCurvePathPickState.start(sourceID: sourceID)
        reportToolStatus("Pick a sketch line, circle, arc, or spline for the Curve Array path.")
    }

    private func cancelPatternArrayCurvePathPick() {
        patternArrayCurvePathPreviewCandidate = nil
        patternArrayCurvePathPickState.cancel()
        reportToolStatus("Curve Array path pick canceled.")
    }

    private func shouldShowSurfaceContinuitySection(for nodes: [SceneNode]) -> Bool {
        surfaceInspectorStateBuilder.showsContinuitySection(for: nodes)
    }

    @ViewBuilder
    private func projectCurvesToFaceSection() -> some View {
        if let faceTarget = selectedFaceTarget {
            let targets = selectedCurveProjectionTargetsForGeneratedFace(excluding: faceTarget)
            if targets.isEmpty == false {
                inspectorSection("Project") {
                    inspectorRow("Curve Targets", "\(targets.count)")
                    inspectorActionRow {
                        Button {
                            projectSelectedCurvesToGeneratedFace(targets, face: faceTarget)
                        } label: {
                            Label("Project Curves", systemImage: "square.on.square")
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("InspectorFace.projectCurves")
                    }
                }
            }
        }
    }

    private func selectedCurveProjectionTargetsForGeneratedFace(
        excluding faceTarget: SelectionTarget
    ) -> [SelectionTarget] {
        projectionTargetResolver.curveProjectionTargetsForGeneratedFace(excluding: faceTarget)
    }

    @ViewBuilder
    private func projectOutlineSection(_ nodes: [SceneNode]) -> some View {
        let targets = bodyOutlineProjectionTargets(from: nodes)
        if targets.isEmpty == false {
            inspectorSection("Project") {
                inspectorRow("Targets", "\(targets.count)")
                inspectorActionRow {
                    Button {
                        projectSelectedBodyOutlinesToConstructionPlane(targets)
                    } label: {
                        Label("Project Outline", systemImage: "pencil.and.outline")
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("InspectorObject.projectOutline")
                }
            }
        }
    }

    private func bodyOutlineProjectionTargets(
        from nodes: [SceneNode]
    ) -> [SelectionTarget] {
        projectionTargetResolver.bodyOutlineProjectionTargets(from: nodes)
    }

    @ViewBuilder
    private func sketchEntityInspectorErrorSections(_ error: Error) -> some View {
        WorkspaceSketchCurveSelectionErrorView(
            targetSummary: selectedTargetSummary,
            reason: error.localizedDescription
        )
    }

    @ViewBuilder
    private func sketchEntityInspectorSections(_ entity: InspectorSketchEntity) -> some View {
        WorkspaceSketchCurveInspectorView(
            entity: entity,
            targetSummary: selectedTargetSummary,
            displayUnit: snapshot.workspaceState.displayUnit,
            curvatureDisplay: curveCurvatureDisplay(for: entity),
            pointDisplay: pointDisplay(for: entity),
            showsCurveDisplayControls: entity.bridgeCurve == nil,
            onSetCurveCurvatureDisplay: setCurveCurvatureDisplay,
            onSetPointDisplay: setPointDisplay
        )

        if let bridgeCurve = entity.bridgeCurve {
            bridgeCurveInspectorSection(bridgeCurve)
        }

        inspectorSection("Curve Edit") {
            sketchEntityEditControls(entity)
        }
    }

    @ViewBuilder
    private func bridgeCurveInspectorSection(_ bridgeCurve: InspectorBridgeCurve) -> some View {
        WorkspaceBridgeCurveInspectorView(
            bridgeCurve: bridgeCurve,
            onSetParameter: setBridgeCurveParameter,
            onSetSense: setBridgeCurveSense,
            onSetTrimSide: setBridgeCurveTrimSide,
            onTrimSources: trimBridgeCurveSources,
            onSetCurvatureDisplay: setBridgeCurveCurvatureDisplay,
            onSetTension: setBridgeCurveTension,
            onSetContinuity: setBridgeCurveContinuity
        )
    }

    @ViewBuilder
    private func sketchEntityEditControls(_ entity: InspectorSketchEntity) -> some View {
        switch entity.entityKind {
        case "point":
            sketchEntityMoveControls(
                "Point",
                target: entity.target,
                handle: .point,
                accessibilityPrefix: "InspectorCurve.point"
            )
            sketchCurveOperationControls(entity, controls: [.alignment])
        case "line":
            if let length = sketchLineLength(for: entity) {
                lengthControl(
                    "Length",
                    meters: length,
                    sliderMetersRange: lengthSliderMetersRange(for: length)
                ) { meters in
                    setSelectedSketchEntityDimension(entity.target, kind: .length, meters: meters)
                }
            }
            if let angleDegrees = sketchLineAngleDegrees(for: entity) {
                numericControl(
                    "Angle",
                    values: [angleDegrees],
                    sliderRange: -360.0 ... 360.0
                ) { degrees in
                    setSelectedSketchEntityDimension(
                        entity.target,
                        kind: .angle,
                        value: .angle(degrees, .degree)
                    )
                } unitLabel: {
                    "deg"
                }
            }
            sketchEntityMoveControls(
                "Start",
                target: entity.target,
                handle: .lineStart,
                accessibilityPrefix: "InspectorCurve.lineStart"
            )
            sketchEntityMoveControls(
                "End",
                target: entity.target,
                handle: .lineEnd,
                accessibilityPrefix: "InspectorCurve.lineEnd"
            )
            sketchCurveOperationControls(
                entity,
                controls: [.alignment, .projection, .vertexOffset]
            )
            let slotTarget = sketchCommandTargetResolver.slotSourceCurveTarget(for: entity)
            if slotTarget != nil {
                lengthControl(
                    "Slot Width",
                    meters: slotProfileWidthMeters,
                    sliderMetersRange: lengthSliderMetersRange(for: slotProfileWidthMeters)
                ) { meters in
                    slotProfileWidthMeters = max(meters, 1.0e-9)
                }
            }
            numericControl(
                "Split",
                values: [sketchSplitFraction],
                sliderRange: 0.01 ... 0.99
            ) { fraction in
                sketchSplitFraction = min(max(fraction, 0.01), 0.99)
            } unitLabel: {
                "t"
            }
            sketchCurveOperationControls(
                entity,
                controls: [.extend, .cornerTreatment, .join]
            )
            inspectorActionRow {
                if let slotTarget {
                    Button {
                        createSlotFromOffsetCurve(slotTarget, width: slotProfileWidthMeters)
                    } label: {
                        Label("Slot", systemImage: "capsule")
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("InspectorCurve.line.createSlot")
                }

                Button {
                    reverseSelectedSketchCurve(entity.target)
                } label: {
                    Label("Reverse", systemImage: "arrow.left.arrow.right")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.reverse")

                Button {
                    splitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Split", systemImage: "scissors")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.split")

                Button {
                    trimSelectedSketchCurveSegment(entity.target)
                } label: {
                    Label("Trim", systemImage: "delete.left")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.trim")
            }
            if let cutter = selectedSketchEntityCutterTarget(excluding: entity.target) {
                cutCurveActionRow(entity.target, cutter: cutter, identifier: "InspectorCurve.line.cut")
            }
            let sagitta = sketchLineArcSagitta(for: entity)
            inspectorActionRow {
                Button {
                    convertSelectedSketchLineToArc(entity.target, sagitta: sagitta)
                } label: {
                    Label("Arc +\(formatted(sagitta))", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.convertArcPositive")

                Button {
                    convertSelectedSketchLineToArc(entity.target, sagitta: -sagitta)
                } label: {
                    Label("Arc -\(formatted(sagitta))", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.convertArcNegative")

                Button {
                    convertSelectedSketchLineToSpline(entity.target)
                } label: {
                    Label("Spline", systemImage: "point.3.connected.trianglepath.dotted")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.line.convertSpline")
            }
        case "circle":
            if let radius = entity.radius {
                lengthControl(
                    "Radius",
                    meters: radius,
                    sliderMetersRange: lengthSliderMetersRange(for: radius)
                ) { meters in
                    setSelectedSketchEntityDimension(entity.target, kind: .radius, meters: meters)
                }
            }
            sketchEntityMoveControls(
                "Center",
                target: entity.target,
                handle: .circleCenter,
                accessibilityPrefix: "InspectorCurve.circleCenter"
            )
            sketchCurveOperationControls(entity, controls: [.alignment, .projection])
            if let cutter = selectedSketchEntityCutterTarget(excluding: entity.target) {
                cutCurveActionRow(entity.target, cutter: cutter, identifier: "InspectorCurve.circle.cut")
            }
        case "arc":
            if let radius = entity.radius {
                lengthControl(
                    "Radius",
                    meters: radius,
                    sliderMetersRange: lengthSliderMetersRange(for: radius)
                ) { meters in
                    setSelectedSketchEntityDimension(entity.target, kind: .radius, meters: meters)
                }
            }
            if let startAngle = entity.startAngle,
               let endAngle = entity.endAngle {
                numericControl(
                    "Span Angle",
                    values: [arcSpanDegrees(startAngle: startAngle, endAngle: endAngle)],
                    sliderRange: 0.1 ... 359.9
                ) { degrees in
                    setSelectedSketchEntityDimension(
                        entity.target,
                        kind: .angle,
                        value: .angle(degrees, .degree)
                    )
                } unitLabel: {
                    "deg"
                }
            }
            if let startAngle = entity.startAngle {
                numericControl(
                    "Start Angle",
                    values: [WorkspaceInspectorNumberText.degrees(fromRadians: startAngle)],
                    sliderRange: -360.0 ... 360.0
                ) { degrees in
                    setSelectedSketchArcStartAngle(entity.target, degrees: degrees)
                } unitLabel: {
                    "deg"
                }
            }
            if let endAngle = entity.endAngle {
                numericControl(
                    "End Angle",
                    values: [WorkspaceInspectorNumberText.degrees(fromRadians: endAngle)],
                    sliderRange: -360.0 ... 360.0
                ) { degrees in
                    setSelectedSketchArcEndAngle(entity.target, degrees: degrees)
                } unitLabel: {
                    "deg"
                }
            }
            sketchEntityMoveControls(
                "Center",
                target: entity.target,
                handle: .arcCenter,
                accessibilityPrefix: "InspectorCurve.arcCenter"
            )
            sketchEntityMoveControls(
                "Start",
                target: entity.target,
                handle: .arcStart,
                accessibilityPrefix: "InspectorCurve.arcStart"
            )
            sketchEntityMoveControls(
                "End",
                target: entity.target,
                handle: .arcEnd,
                accessibilityPrefix: "InspectorCurve.arcEnd"
            )
            sketchCurveOperationControls(
                entity,
                controls: [.alignment, .projection, .vertexOffset]
            )
            let slotTarget = sketchCommandTargetResolver.slotSourceCurveTarget(for: entity)
            if slotTarget != nil {
                lengthControl(
                    "Slot Width",
                    meters: slotProfileWidthMeters,
                    sliderMetersRange: lengthSliderMetersRange(for: slotProfileWidthMeters)
                ) { meters in
                    slotProfileWidthMeters = max(meters, 1.0e-9)
                }
            }
            numericControl(
                "Split",
                values: [sketchSplitFraction],
                sliderRange: 0.01 ... 0.99
            ) { fraction in
                sketchSplitFraction = min(max(fraction, 0.01), 0.99)
            } unitLabel: {
                "t"
            }
            sketchCurveOperationControls(entity, controls: [.extend, .join])
            inspectorActionRow {
                if let slotTarget {
                    Button {
                        createSlotFromOffsetCurve(slotTarget, width: slotProfileWidthMeters)
                    } label: {
                        Label("Slot", systemImage: "capsule")
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("InspectorCurve.arc.createSlot")
                }

                Button {
                    splitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Split", systemImage: "scissors")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.arc.split")

                Button {
                    trimSelectedSketchCurveSegment(entity.target)
                } label: {
                    Label("Trim", systemImage: "delete.left")
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("InspectorCurve.arc.trim")
            }
            if let cutter = selectedSketchEntityCutterTarget(excluding: entity.target) {
                cutCurveActionRow(entity.target, cutter: cutter, identifier: "InspectorCurve.arc.cut")
            }
        case "spline":
            inspectorRow("Control Points", "\(entity.controlPoints.count)")
            if let start = entity.start {
                inspectorRow("Start", sketchPointSummary(start))
            }
            if let end = entity.end {
                inspectorRow("End", sketchPointSummary(end))
            }
            numericControl(
                "Split",
                values: [sketchSplitFraction],
                sliderRange: 0.01 ... 0.99
            ) { fraction in
                sketchSplitFraction = min(max(fraction, 0.01), 0.99)
            } unitLabel: {
                "t"
            }
            let slotTarget = sketchCommandTargetResolver.slotSourceCurveTarget(for: entity)
            if slotTarget != nil {
                lengthControl(
                    "Slot Width",
                    meters: slotProfileWidthMeters,
                    sliderMetersRange: lengthSliderMetersRange(for: slotProfileWidthMeters)
                ) { meters in
                    slotProfileWidthMeters = max(meters, 1.0e-9)
                }
                inspectorActionRow {
                    if let slotTarget {
                        Button {
                            createSlotFromOffsetCurve(slotTarget, width: slotProfileWidthMeters)
                        } label: {
                            Label("Slot", systemImage: "capsule")
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("InspectorCurve.spline.createSlot")
                    }
                }
            }
            sketchCurveOperationControls(entity, controls: [.projection, .extend])
            WorkspaceSplineEditOperationsView(
                target: entity.target,
                rebuildControlPointCount: $sketchRebuildControlPointCount,
                rebuildToleranceMeters: $sketchRebuildToleranceMeters,
                rebuildToleranceMetersRange: workspaceInteractionScaleDefaults.sketchRebuildToleranceRange,
                rebuildKeepsCorners: $sketchRebuildKeepsCorners,
                explicitDegree: $sketchRebuildExplicitDegree,
                explicitSpanCount: $sketchRebuildExplicitSpanCount,
                explicitWeight: $sketchRebuildExplicitWeight,
                onReverse: reverseSelectedSketchCurve,
                onSplit: splitSelectedSketchCurve,
                onInsertControlPoint: insertSelectedSketchSplineControlPoint,
                onRebuild: rebuildSelectedSketchCurve,
                onRefit: refitSelectedSketchCurve,
                onExplicit: explicitControlSelectedSketchCurve,
                onTrim: trimSelectedSketchCurveSegment
            )
            if entity.bridgeCurve != nil {
                inspectorRow("Edit", "Bridge Source")
            } else {
                WorkspaceSplineControlPointControlsView(
                    entity: entity,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    selectedControlPointIndexes: selectedSplineControlPointIndexes(for: entity),
                    selectedControlPointIndex: $selectedSplineControlPointIndex,
                    slideDistanceMeters: $sketchSplineControlPointSlideDistanceMeters,
                    slideCount: $sketchSplineControlPointSlideCount,
                    moveStepMeters: defaultSketchEntityMoveStepMeters,
                    slideDistanceSliderMetersRange: lengthSliderMetersRange(
                        for: sketchSplineControlPointSlideDistanceMeters
                    ),
                    onAddSmoothControlPoint: addSmoothSplineControlPointConstraint,
                    onMoveControlPoint: moveSelectedSplineControlPoint,
                    onSlideControlPoints: { target, controlPointIndexes, direction in
                        slideSelectedSplineControlPoints(
                            target,
                            controlPointIndexes: controlPointIndexes,
                            direction: direction
                        )
                    }
                )
                WorkspaceSplineEndpointConstraintControlsView(
                    entity: entity,
                    displayUnit: snapshot.workspaceState.displayUnit,
                    onAddLineTangency: { entity, endpoint, lineID in
                        addSplineEndpointTangentConstraint(
                            entity,
                            endpoint: endpoint,
                            lineID: lineID
                        )
                    },
                    onAddEndpointTangency: { entity, endpoint, target in
                        addTangentSplineEndpointsConstraint(
                            entity,
                            endpoint: endpoint,
                            target: target
                        )
                    },
                    onAddEndpointSmoothness: { entity, endpoint, target in
                        addSmoothSplineEndpointsConstraint(
                            entity,
                            endpoint: endpoint,
                            target: target
                        )
                    }
                )
            }
        default:
            inspectorRow("Edit", "Unsupported")
        }
    }

    @ViewBuilder
    private func sketchEntityMoveControls(
        _ title: String,
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        accessibilityPrefix: String
    ) -> some View {
        WorkspaceSketchEntityPointMoveControlsView(
            title: title,
            target: target,
            handle: handle,
            moveStepMeters: defaultSketchEntityMoveStepMeters,
            accessibilityPrefix: accessibilityPrefix
        ) { target, handle, deltaX, deltaY in
            moveSelectedSketchEntityPoint(
                target,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY
            )
        }
    }

    @ViewBuilder
    private func objectShapeSection(_ nodes: [SceneNode], showsPlacement: Bool = true) -> some View {
        switch Result(catching: {
            try objectShapeBuilder(in: snapshot).shapes(for: nodes)
        }) {
        case .success(let shapes):
            WorkspaceObjectShapeInspectorView(
                shapes: shapes,
                showsPlacement: showsPlacement,
                displayUnit: snapshot.workspaceState.displayUnit,
                positionSliderMetersRange: transformPositionSliderMetersRange,
                sizeSliderMetersRange: sizeSliderMetersRange,
                fallbackLengthSliderMetersRange: lengthSliderMetersRange(for: 0.0),
                onSetCenter: setObjectCenter,
                onSetSize: setObjectSize,
                onSetProperty: setObjectProperty
            )
        case .failure(let error):
            Text(error.localizedDescription).foregroundStyle(.red)
        }
    }

    private func objectShapeBuilder(in current: ProjectViewSnapshot) -> WorkspaceObjectShapeInspectorStateBuilder {
        WorkspaceObjectShapeInspectorStateBuilder(snapshot: current)
    }

    private func setObjectCenter(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shapes: [InspectorObjectShape]
    ) {
        let ids = shapes.map(\.id)
        submitSource(name: "setObjectCenter") { current in
            try objectShapeBuilder(in: current).centerCommands(axis, meters: meters, nodeIDs: ids)
        }
    }

    private func setObjectSize(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shapes: [InspectorObjectShape]
    ) {
        let ids = shapes.map(\.id)
        submitSource(name: "setObjectSize") { current in
            try WorkspaceObjectShapeInspectorStateBuilder.sizeCommands(
                axis, meters: meters, nodeIDs: ids, in: current.document.document,
                currentEvaluation: current.cadInteraction, currentGeneration: current.documentGeneration)
        }
    }

    private func offsetSelectedFace(
        _ target: SelectionTarget,
        by meters: Double
    ) {
        submitSource(
            .offsetBodyFace(
                target: target,
                distance: .length(meters, .meter)
            )
        )
    }

    private func deleteSelectedFaces(_ targets: [SelectionTarget]) {
        submitSource(.deleteBodyFaces(targets: targets))
    }

    private func draftSelectedFaces(
        _ targets: [SelectionTarget],
        neutralTarget: SelectionTarget,
        angleDegrees: Double
    ) {
        guard angleDegrees.isFinite else {
            reportToolStatus("Draft Face requires a finite angle.", severity: .warning)
            return
        }
        submitSource(
            .draftBodyFaces(
                targets: targets,
                neutralTarget: neutralTarget,
                angle: .angle(angleDegrees, .degree)
            )
        )
    }

    private func offsetSelectedEdges(
        _ targets: [SelectionTarget],
        by meters: Double,
        gapFill: OffsetCurveGapFill,
        isSymmetric: Bool = false
    ) {
        guard targets.count == 1, let target = targets.first else {
            reportToolStatus(
                "Offset Edge currently supports one selected edge.",
                severity: .warning
            )
            return
        }
        submitSource(
            .offsetCurve(
                target: target,
                // Core refuses a distance that is not positive.
                distance: .length(meters, .meter),
                options: OffsetCurveOptions(
                    isSymmetric: isSymmetric,
                    gapFill: gapFill
                ),
                vertexHandle: nil
            )
        ) { result in
            if result?.didMutate == true {
                edgeOffsetCommandState.deactivate()
            }
        }
    }

    private func beginEdgeTreatment(_ kind: ModelingOperationDraft.Kind, targets: [SelectionTarget], meters: Double) {
        beginModelingOperation(kind)
        modelingDraft?.targets = targets
        let value = workspaceLengthFieldPresentation(fromMeters: meters, preferredUnit: snapshot.workspaceState.displayUnit)
        modelingDraft?.distance = value.text + " " + value.unit.symbol
    }

    private func moveSelectedVertex(
        _ target: SelectionTarget,
        deltaX: Double,
        deltaY: Double
    ) {
        submitSource(
            .moveBodyVertex(
                target: target,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter)
            )
        )
    }

    private func offsetSelectedRegions(
        _ targets: [SelectionTarget],
        by meters: Double,
        gapFill: OffsetCurveGapFill,
        isSymmetric: Bool = false,
        combinesRegions: Bool = false
    ) {
        submitSource(
            .offsetRegions(
                targets: targets,
                distance: .length(meters, .meter),
                options: OffsetCurveOptions(
                    isSymmetric: isSymmetric,
                    gapFill: gapFill
                ),
                combinesRegions: combinesRegions
            )
        ) { result in
            if result?.didMutate == true {
                regionOffsetCommandState.deactivate()
            }
        }
    }

    private func moveSelectedSketchEntityPoint(
        _ target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: Double,
        deltaY: Double
    ) {
        submitSource(
            .moveSketchEntityPoint(
                target: target,
                handle: handle,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter)
            )
        )
    }

    private func moveSelectedSplineControlPoint(
        _ target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: Double,
        deltaY: Double
    ) {
        submitSource(
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: controlPointIndex,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter)
            )
        )
    }

    private func selectedSplineControlPointIndexes(for entity: InspectorSketchEntity) -> [Int] {
        splineControlPointSelectionResolver.selectedControlPointIndexes(for: entity)
    }

    private func selectedSplineControlPointSlideInput() -> WorkspaceSplineControlPointSlideInput? {
        guard case .success(let entity) = selectedSketchEntityResult else {
            return nil
        }
        return splineControlPointSelectionResolver.slideInput(for: entity)
    }

    private func slideSelectedSplineControlPoints(
        _ target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distanceMeters: Double? = nil
    ) {
        let resolvedDistanceMeters = distanceMeters ?? max(sketchSplineControlPointSlideDistanceMeters, 1.0e-9)
        submitSource(
            .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: controlPointIndexes,
                direction: direction,
                distance: .length(resolvedDistanceMeters, .meter)
            )
        )
    }

    private func slideSelectedPolySplineSurfaceVertices(
        _ targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double? = nil
    ) {
        let resolvedDistanceMeters = distanceMeters ?? max(polySplineSurfaceVertexSlideDistanceMeters, 1.0e-9)
        submitSource(
            .slidePolySplineSurfaceVertices(
                targets: targets,
                direction: direction,
                distance: .length(resolvedDistanceMeters, .meter)
            )
        )
    }

    private func setSurfaceControlPointDisplay(
        _ targets: [SelectionReference],
        isVisible: Bool
    ) {
        applyWorkspace(
            targets.map { target in
                .setSurfaceControlPointDisplay(target: target, isVisible: isVisible)
            }
        )
    }

    private func setSurfaceFrameDisplay(
        _ queries: [SurfaceFrameQuery],
        isVisible: Bool
    ) {
        applyWorkspace(
            queries.map { query in
                .setSurfaceFrameDisplay(query: query, isVisible: isVisible)
            }
        )
    }

    private func setSurfaceControlPointCoordinate(
        _ axis: SurfaceControlPointInspectorState.CoordinateAxis,
        meters: Double,
        state: SurfaceControlPointInspectorState
    ) {
        guard state.canEditCoordinates else {
            return
        }
        let references = state.entries.filter(\.isEditable).map(\.selectionReference)
        let analysisOptions = surfaceAnalysisOptions.analysisOptions
        submitSource(name: "moveSurfaceControlPoints") { current in
            let builder = WorkspaceSurfaceInspectorStateBuilder(
                document: current.document.document,
                selection: SelectionModel(selectedReferences: references),
                currentEvaluation: current.cadInteraction,
                documentGeneration: current.documentGeneration,
                objectRegistry: current.objectRegistry,
                surfaceAnalysisOptions: analysisOptions,
                workspaceState: current.workspaceState
            )
            let currentState: SurfaceControlPointInspectorState
            switch builder.surfaceControlPointStateResult() {
            case .success(let state?):
                currentState = state
            case .success(nil):
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "The edited surface control points no longer exist."
                )
            case .failure(let error):
                throw error
            }
            let editableEntries = currentState.entries.filter(\.isEditable)
            guard editableEntries.count == references.count else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "One or more edited surface control points no longer exist."
                )
            }
            var commands: [EditorCommand] = []
            for entry in editableEntries {
                let currentMeters: Double
                switch axis {
                case .x:
                    currentMeters = entry.point.x
                case .y:
                    currentMeters = entry.point.y
                case .z:
                    currentMeters = entry.point.z
                }
                let delta = meters - currentMeters
                guard abs(delta) > 1.0e-12 else {
                    continue
                }
                commands.append(
                    .moveSurfaceControlPoint(
                        target: entry.selectionReference,
                        deltaX: .length(axis == .x ? delta : 0.0, .meter),
                        deltaY: .length(axis == .y ? delta : 0.0, .meter),
                        deltaZ: .length(axis == .z ? delta : 0.0, .meter)
                    )
                )
            }
            return commands
        }
    }

    private func setSurfaceControlPointWeight(
        _ targets: [SelectionReference],
        weight: Double
    ) {
        submitSource(
            targets.map {
                .setSurfaceControlPointWeight(
                    target: $0,
                    weight: .scalar(max(weight, 1.0e-9))
                )
            },
            name: "setSurfaceControlPointWeights"
        )
    }

    private func setSurfaceKnotValue(
        _ target: SelectionReference,
        value: Double
    ) {
        let command: EditorCommand
        switch target {
        case .surface(.trimKnot(let reference)):
            command = .setSurfaceTrimKnotValue(
                target: .surface(.trim(reference.trim)),
                knotIndex: reference.knotIndex,
                value: .scalar(value)
            )
        default:
            command = .setSurfaceKnotValue(
                target: target,
                value: .scalar(value)
            )
        }
        submitSource(command)
    }

    private func insertSurfaceKnot(
        _ target: SelectionReference,
        value: Double
    ) {
        let command: EditorCommand
        switch target {
        case .surface(.trimKnot), .surface(.trimSpan):
            command = .insertSurfaceTrimKnot(
                target: target,
                value: .scalar(value)
            )
        default:
            command = .insertSurfaceKnot(
                target: target,
                value: .scalar(value)
            )
        }
        submitSource(command)
    }

    private func splitSurfaceSpan(
        _ target: SelectionReference,
        fraction: Double
    ) {
        submitSource(
            .splitSurfaceSpan(
                target: target,
                fraction: .scalar(fraction)
            )
        )
    }

    private func setSurfaceKnotMultiplicity(
        _ target: SelectionReference,
        multiplicity: Int
    ) {
        let command: EditorCommand
        switch target {
        case .surface(.trimKnot(let reference)):
            command = .setSurfaceTrimKnotMultiplicity(
                target: .surface(.trim(reference.trim)),
                knotIndex: reference.knotIndex,
                multiplicity: multiplicity
            )
        default:
            command = .setSurfaceKnotMultiplicity(
                target: target,
                multiplicity: multiplicity
            )
        }
        submitSource(command)
    }

    private func matchSurfaceBoundaryContinuity(
        target: SelectionReference,
        reference: SelectionReference,
        level: SurfaceBoundaryContinuityLevel,
        matchSide: SurfaceBoundaryMatchSide,
        referenceDirection: SurfaceBoundaryReferenceDirection
    ) {
        submitSource(
            .matchSurfaceBoundaryContinuity(
                target: target,
                reference: reference,
                level: level,
                matchSide: matchSide,
                referenceDirection: referenceDirection
            )
        )
    }

    private func setSurfaceTrimDomain(
        target: SelectionReference,
        uLowerBound: Double,
        uUpperBound: Double,
        vLowerBound: Double,
        vUpperBound: Double
    ) {
        submitSource(
            .setSurfaceTrimDomain(
                target: target,
                uLowerBound: .scalar(uLowerBound),
                uUpperBound: .scalar(uUpperBound),
                vLowerBound: .scalar(vLowerBound),
                vUpperBound: .scalar(vUpperBound)
            )
        )
    }

    private func slideSelectedSurfaceControlPoints(
        _ targets: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double? = nil
    ) {
        let resolvedDistanceMeters = distanceMeters ?? max(polySplineSurfaceVertexSlideDistanceMeters, 1.0e-9)
        submitSource(
            .slideSurfaceControlPoints(
                targets: targets,
                direction: direction,
                distance: .length(resolvedDistanceMeters, .meter)
            )
        )
    }

    private func moveSelectedSurfaceControlPointsInFrame(
        _ targets: [SelectionReference],
        frame: SurfaceFrameQuery,
        uDistanceMeters: Double,
        vDistanceMeters: Double,
        normalDistanceMeters: Double
    ) {
        submitSource(
            .moveSurfaceControlPointsInFrame(
                targets: targets,
                frame: frame,
                uDistance: .length(uDistanceMeters, .meter),
                vDistance: .length(vDistanceMeters, .meter),
                normalDistance: .length(normalDistanceMeters, .meter)
            )
        )
    }

    private func curveCurvatureDisplay(
        for entity: InspectorSketchEntity
    ) -> CurveCurvatureDisplay? {
        snapshot.workspaceState.curveCurvatureDisplays[
            .sketchEntity(
                featureID: entity.sourceFeatureID,
                entityID: entity.entityID
            )
        ]
    }

    private func pointDisplay(
        for entity: InspectorSketchEntity
    ) -> PointDisplay? {
        snapshot.workspaceState.pointDisplays[
            .sketchEntity(
                featureID: entity.sourceFeatureID,
                entityID: entity.entityID
            )
        ]
    }

    private func setCurveCurvatureDisplay(
        _ entity: InspectorSketchEntity,
        isVisible: Bool,
        combScale: Double
    ) {
        setCurveCurvatureDisplay(
            target: entity.target,
            isVisible: isVisible,
            combScale: max(combScale, 1.0e-6)
        )
    }

    private func setPointDisplay(
        _ entity: InspectorSketchEntity,
        isVisible: Bool
    ) {
        setPointDisplay(
            target: entity.target,
            isVisible: isVisible
        )
    }

    private func setBridgeCurveTension(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        level: InspectorBridgeCurveTensionLevel,
        value: Double
    ) {
        let nextValue = max(value, 1.0e-6)
        submitBridgeCurveEndpointEdit(
            sourceID: bridgeCurve.sourceID,
            endpoint: endpoint,
            name: "setBridgeCurveTension"
        ) { nextEndpoint in
            Self.setBridgeTensionLevel(
                &nextEndpoint.tension,
                level: level,
                value: nextValue
            )
        }
    }

    private static func setBridgeTensionLevel(
        _ tension: inout BridgeCurveTension,
        level: InspectorBridgeCurveTensionLevel,
        value: Double
    ) {
        switch level {
        case .first:
            tension.first = .scalar(value)
        case .second:
            tension.second = .scalar(value)
        case .third:
            tension.third = .scalar(value)
        }
    }

    private func setBridgeCurveParameter(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        value: Double
    ) {
        let clampedValue = min(max(value, 0.0), 1.0)
        submitBridgeCurveEndpointEdit(
            sourceID: bridgeCurve.sourceID,
            endpoint: endpoint,
            name: "setBridgeCurveParameter"
        ) { nextEndpoint in
            nextEndpoint.parameter = .scalar(clampedValue)
        }
    }

    private func setBridgeCurveSense(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint
    ) {
        submitBridgeCurveEndpointEdit(
            sourceID: bridgeCurve.sourceID,
            endpoint: endpoint,
            name: "toggleBridgeCurveSense"
        ) { nextEndpoint in
            nextEndpoint.reversesSense.toggle()
        }
    }

    private func setBridgeCurveTrimSide(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        trimSide: BridgeCurveTrimSide
    ) {
        submitBridgeCurveEndpointEdit(
            sourceID: bridgeCurve.sourceID,
            endpoint: endpoint,
            name: "setBridgeCurveTrimSide"
        ) { nextEndpoint in
            nextEndpoint.trimSide = trimSide
        }
    }

    private func submitBridgeCurveEndpointEdit(
        sourceID: BridgeCurveSourceID,
        endpoint: InspectorBridgeCurveEndpoint,
        name: String,
        edit: @escaping @MainActor @Sendable (inout BridgeCurveEndpoint) -> Void
    ) {
        submitSource(name: name) { current in
            guard let source = current.document.document.productMetadata.bridgeCurveSources[sourceID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve source no longer exists."
                )
            }
            var nextEndpoint: BridgeCurveEndpoint
            switch endpoint {
            case .first:
                nextEndpoint = source.firstEndpoint
            case .second:
                nextEndpoint = source.secondEndpoint
            }
            edit(&nextEndpoint)
            return [
                .setBridgeCurveParameters(
                    sourceID: sourceID,
                    firstEndpoint: endpoint == .first ? nextEndpoint : nil,
                    secondEndpoint: endpoint == .second ? nextEndpoint : nil,
                    continuity: nil
                ),
            ]
        }
    }

    /// The G1 tension the Bridge Curve's field shows: the one typed for it, or its start's first
    /// tension.
    private func bridgeTensionValue(for bridgeCurve: InspectorBridgeCurve) -> Double {
        guard let input = bridgeTensionInput, input.sourceID == bridgeCurve.sourceID else {
            return bridgeCurve.firstTension.first
        }
        return input.value
    }

    @ViewBuilder
    private func bridgeTensionContextPanelContent(_ bridgeCurve: InspectorBridgeCurve) -> some View {
        WorkspaceCommandScalarInput(
            title: "G1 Tension (D)",
            value: Binding(
                get: { bridgeTensionValue(for: bridgeCurve) },
                set: { bridgeTensionInput = (bridgeCurve.sourceID, $0) }
            ),
            field: .bridgeTension,
            focus: $focusedCommandDistance,
            accessibilityIdentifier: "WorkspaceBridge.g1Tension"
        )
        workspaceIconButton(
            systemImage: "checkmark",
            help: "Apply G1 Tension to both ends",
            accessibilityIdentifier: "WorkspaceBridge.applyTension",
            action: { applyBridgeG1Tension(bridgeCurve) }
        )
    }

    /// Return or the panel's apply: both ends of the Bridge Curve take the typed G1 tension (its
    /// first tension, the one G1 continuity uses) as one step; Core refuses one that is not
    /// positive, and the typed value stays for another try.
    private func applyBridgeG1Tension(_ bridgeCurve: InspectorBridgeCurve) {
        let sourceID = bridgeCurve.sourceID
        let tension = bridgeTensionValue(for: bridgeCurve)
        submitSource(name: "setBridgeCurveTension", commands: { current in
            guard let source = current.document.document.productMetadata.bridgeCurveSources[sourceID] else {
                throw EditorError(code: .referenceUnresolved, message: "Bridge curve source no longer exists.")
            }
            var firstEndpoint = source.firstEndpoint
            var secondEndpoint = source.secondEndpoint
            firstEndpoint.tension.first = .scalar(tension)
            secondEndpoint.tension.first = .scalar(tension)
            return [
                .setBridgeCurveParameters(
                    sourceID: sourceID,
                    firstEndpoint: firstEndpoint,
                    secondEndpoint: secondEndpoint,
                    continuity: nil
                ),
            ]
        }) { _ in
            bridgeTensionInput = nil
        }
    }

    /// Trim on the selected Bridge Curve (inspector, Q): turns it on, or off again, restoring the
    /// curves it trimmed.
    private func trimBridgeCurveSources(_ bridgeCurve: InspectorBridgeCurve) {
        submitSource(
            .setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nil,
                secondEndpoint: nil,
                continuity: nil,
                trimsSourceCurves: !bridgeCurve.trimsSourceCurves
            )
        )
    }

    private func setBridgeCurveCurvatureDisplay(
        _ bridgeCurve: InspectorBridgeCurve,
        isVisible: Bool,
        combScale: Double
    ) {
        setCurveCurvatureDisplay(
            target: bridgeCurve.target,
            isVisible: isVisible,
            combScale: max(combScale, 1.0e-6)
        )
    }

    private func setBridgeCurveContinuity(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        continuity: BridgeCurveEndpointContinuity
    ) {
        let sourceID = bridgeCurve.sourceID
        submitSource(name: "setBridgeCurveContinuity") { current in
            guard let source = current.document.document.productMetadata.bridgeCurveSources[sourceID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve source no longer exists."
                )
            }
            var nextContinuity = source.continuity
            switch endpoint {
            case .first:
                nextContinuity.first = continuity
            case .second:
                nextContinuity.second = continuity
            }
            return [
                .setBridgeCurveParameters(
                    sourceID: sourceID,
                    firstEndpoint: nil,
                    secondEndpoint: nil,
                    continuity: nextContinuity
                ),
            ]
        }
    }

    private func addSmoothSplineControlPointConstraint(
        _ entity: InspectorSketchEntity,
        controlPointIndex: Int
    ) {
        submitSource(
            .addSketchConstraint(
                featureID: entity.sourceFeatureID,
                constraint: .smoothSplineControlPoint(
                    entity: entity.entityID,
                    index: controlPointIndex
                )
            )
        )
    }

    private func addSplineEndpointTangentConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        lineID: SketchEntityID
    ) {
        guard let feature = snapshot.document.document.cadDocument.designGraph.nodes[entity.sourceFeatureID],
              case .sketch(let sketch) = feature.operation else {
            reportToolStatus(
                "Spline tangency requires an existing sketch feature.",
                severity: .warning
            )
            return
        }
        let orientation: SketchTangentOrientation
        do {
            orientation = try snapshot.document.document.splineLineTangentOrientation(
                splineID: entity.entityID,
                endpoint: endpoint,
                lineID: lineID,
                in: sketch
            )
        } catch let error as EditorError {
            reportToolStatus(error.message, severity: .warning)
            return
        } catch {
            reportToolStatus(
                "Spline tangency could not resolve the current geometry.",
                severity: .warning
            )
            return
        }
        submitSource(
            .addSketchConstraint(
                featureID: entity.sourceFeatureID,
                constraint: .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: SketchSplineEndpointReference(
                        splineID: entity.entityID,
                        endpoint: endpoint
                    ),
                    line: lineID,
                    orientation: orientation
                ))
            )
        )
    }

    /// Joined endpoints of differing kinds flow in the same parameter
    /// direction, so the tangent orientation is aligned exactly when the
    /// endpoint kinds differ.
    private func splineEndpointPairOrientation(
        _ endpoint: SketchSplineEndpoint,
        _ target: SketchSplineEndpointReference
    ) -> SketchTangentOrientation {
        endpoint == target.endpoint ? .opposed : .aligned
    }

    private func addTangentSplineEndpointsConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        target: SketchSplineEndpointReference
    ) {
        submitSource(
            .addSketchConstraint(
                featureID: entity.sourceFeatureID,
                constraint: .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: SketchSplineEndpointReference(
                        splineID: entity.entityID,
                        endpoint: endpoint
                    ),
                    second: target,
                    orientation: splineEndpointPairOrientation(endpoint, target)
                ))
            )
        )
    }

    private func addSmoothSplineEndpointsConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        target: SketchSplineEndpointReference
    ) {
        submitSource(
            .addSketchConstraint(
                featureID: entity.sourceFeatureID,
                constraint: .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: SketchSplineEndpointReference(
                        splineID: entity.entityID,
                        endpoint: endpoint
                    ),
                    second: target,
                    orientation: splineEndpointPairOrientation(endpoint, target)
                ))
            )
        )
    }

    private func setSelectedSketchCircleRadius(
        _ target: SelectionTarget,
        meters: Double
    ) {
        submitSource(
            .setSketchCircleParameters(
                target: target,
                center: nil,
                radius: .length(max(meters, 1.0e-9), .meter)
            )
        )
    }

    private func setSelectedSketchArcRadius(
        _ target: SelectionTarget,
        meters: Double
    ) {
        submitSource(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: .length(max(meters, 1.0e-9), .meter),
                startAngle: nil,
                endAngle: nil
            )
        )
    }

    private func setSelectedSketchArcStartAngle(
        _ target: SelectionTarget,
        degrees: Double
    ) {
        submitSource(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: nil,
                startAngle: .angle(degrees, .degree),
                endAngle: nil
            )
        )
    }

    private func setSelectedSketchArcStartAngle(
        _ target: SelectionTarget,
        radians: Double
    ) {
        submitSource(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: nil,
                startAngle: .angle(radians, .radian),
                endAngle: nil
            )
        )
    }

    private func setSelectedSketchArcEndAngle(
        _ target: SelectionTarget,
        degrees: Double
    ) {
        submitSource(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: nil,
                startAngle: nil,
                endAngle: .angle(degrees, .degree)
            )
        )
    }

    private func setSelectedSketchArcEndAngle(
        _ target: SelectionTarget,
        radians: Double
    ) {
        submitSource(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: nil,
                startAngle: nil,
                endAngle: .angle(radians, .radian)
            )
        )
    }

    private func setSelectedSketchEntityDimension(
        _ target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        meters: Double
    ) {
        setSelectedSketchEntityDimension(
            target,
            kind: kind,
            value: .length(max(meters, 1.0e-9), .meter)
        )
    }

    private func setSelectedSketchEntityDimension(
        _ target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) {
        submitSource(
            .setSketchEntityDimension(
                target: target,
                kind: kind,
                value: value
            )
        )
    }

    private func convertSelectedSketchLineToArc(
        _ target: SelectionTarget,
        sagitta: Double
    ) {
        submitSource(
            .convertSketchLineToArc(
                target: target,
                sagitta: .length(sagitta, .meter)
            )
        )
    }

    private func convertSelectedSketchLineToSpline(
        _ target: SelectionTarget
    ) {
        submitSource(.convertSketchLineToSpline(target: target))
    }

    private func reverseSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        submitSource(.reverseSketchCurve(target: target))
    }

    private func extendSelectedSketchCurve(
        _ target: SelectionTarget,
        shape: ExtendCurveShape
    ) {
        submitSource(
            .extendSketchCurve(
                target: target,
                distance: .length(max(sketchExtendDistanceMeters, 1.0e-9), .meter),
                shape: shape
            )
        )
    }

    private func applySelectedSketchCornerTreatment(
        _ target: SelectionTarget
    ) {
        let adjacentTarget: SelectionTarget?
        if case .sketchEntity(let componentID) = target.component,
           componentID.sketchEntityReference != nil {
            adjacentTarget = selectedSketchCornerTreatmentAdjacentTarget(excluding: target)
        } else {
            adjacentTarget = nil
        }
        submitSource(
            .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: .length(max(sketchCornerTreatmentDistanceMeters, 1.0e-9), .meter),
                treatment: sketchCornerTreatment
            )
        )
    }

    private func offsetSelectedSketchVertex(
        _ entity: InspectorSketchEntity
    ) {
        guard let handle = selectedSketchVertexOffsetHandle(entity) else {
            return
        }
        submitSource(
            .offsetSketchVertex(
                target: entity.target,
                handle: handle,
                distance: .length(max(sketchVertexOffsetDistanceMeters, 1.0e-9), .meter)
            )
        )
    }

    /// The running Offset Vertex's result at its distance; the command ends once it exists.
    private func createCommandedVertexOffset(_ entity: InspectorSketchEntity) {
        guard let handle = selectedSketchVertexOffsetHandle(entity) else { return }
        submitSource(
            .offsetSketchVertex(
                target: entity.target,
                handle: handle,
                // Core refuses a distance that is not positive.
                distance: .length(sketchVertexOffsetDistanceMeters, .meter)
            )
        ) { result in
            if result?.didMutate == true {
                slotProfileCommandState.deactivate()
            }
        }
    }

    private func splitSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let fraction = min(max(sketchSplitFraction, 0.01), 0.99)
        submitSource(
            .splitSketchCurve(
                target: target,
                fraction: .scalar(fraction)
            )
        )
    }

    private func insertSelectedSketchSplineControlPoint(
        _ target: SelectionTarget
    ) {
        let fraction = min(max(sketchSplitFraction, 0.01), 0.99)
        submitSource(
            .insertSketchSplineControlPoint(
                target: target,
                fraction: .scalar(fraction)
            )
        )
    }

    private func rebuildSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        submitSource(
            .rebuildSketchCurve(
                target: target,
                options: .points(controlPointCount: sketchRebuildControlPointCount)
            )
        )
    }

    private func refitSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let toleranceRange = workspaceInteractionScaleDefaults.sketchRebuildToleranceRange
        let tolerance = min(
            max(sketchRebuildToleranceMeters, toleranceRange.lowerBound),
            toleranceRange.upperBound
        )
        submitSource(
            .rebuildSketchCurve(
                target: target,
                options: .refit(
                    tolerance: .length(tolerance, .meter),
                    keepsCorners: sketchRebuildKeepsCorners
                )
            )
        )
    }

    private func explicitControlSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        submitSource(
            .rebuildSketchCurve(
                target: target,
                options: .explicitControl(
                    degree: sketchRebuildExplicitDegree,
                    spanCount: sketchRebuildExplicitSpanCount,
                    weight: min(max(sketchRebuildExplicitWeight, 0.0), 1.0)
                )
            )
        )
    }

    private func trimSelectedSketchCurveSegment(
        _ target: SelectionTarget
    ) {
        submitSource(.trimSketchCurveSegment(target: target))
    }

    private func cutSelectedSketchCurve(
        _ target: SelectionTarget,
        cutter: SelectionTarget
    ) {
        submitSource(
            .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions(extendsCutter: cutCurveExtendsCutter)
            )
        )
    }

    /// Cut Curve's dialog row: Extend lets the cutter reach the target along its line or circle.
    @ViewBuilder
    private func cutCurveActionRow(_ target: SelectionTarget, cutter: SelectionTarget, identifier: String) -> some View {
        inspectorActionRow {
            Button {
                cutSelectedSketchCurve(target, cutter: cutter)
            } label: {
                Label("Cut", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier(identifier)
            Toggle("Extend", isOn: $cutCurveExtendsCutter)
                .toggleStyle(.checkbox)
                .font(.caption)
                .accessibilityIdentifier("\(identifier).extend")
        }
    }

    private func joinSelectedSketchCurves(
        _ entity: InspectorSketchEntity
    ) {
        guard let adjacentTarget = sketchCurveJoinInspectorState(for: entity).joinAdjacentTarget else {
            return
        }
        submitSource(
            .joinSketchCurves(
                target: entity.target,
                adjacentTarget: adjacentTarget,
                continuity: sketchCurveJoinContinuity
            )
        )
    }

    private func unjoinSelectedSketchCurve(
        _ entity: InspectorSketchEntity
    ) {
        guard sketchCurveJoinInspectorState(for: entity).canUnjoin else {
            return
        }
        submitSource(.unjoinSketchCurve(target: entity.target))
    }

    private func alignSelectedSketchVertex(
        _ entity: InspectorSketchEntity
    ) {
        guard let referenceTarget = selectedSketchVertexAlignmentReferenceTarget(for: entity) else {
            return
        }
        submitSource(
            .alignSketchVertex(
                target: entity.target,
                reference: referenceTarget,
                options: SketchVertexAlignmentOptions(
                    continuity: sketchVertexAlignmentContinuity,
                    referenceParameter: sketchEntityInspectorStateBuilder.vertexAlignmentReferenceIsCurve(for: entity)
                        ? .scalar(sketchVertexAlignmentParameter) : nil,
                    targetContinuityDistance: sketchVertexAlignmentContinuity == .g0
                        ? nil : sketchVertexAlignmentDistanceMeters.map { .length($0, .meter) },
                    referenceContinuityDistance: sketchVertexAlignmentContinuity == .g0
                        ? nil : sketchVertexAlignmentDistanceMeters.map { .length($0, .meter) }
                )
            )
        )
    }

    private func projectSelectedSketchCurvesToConstructionPlane(
        _ entity: InspectorSketchEntity
    ) {
        let targets = selectedSketchCurveProjectionTargets(for: entity)
        guard targets.isEmpty == false else {
            return
        }
        submitSource(
            .projectSketchCurvesToConstructionPlane(
                targets: targets,
                plane: activeSketchPlane(),
                name: nil
            )
        )
    }

    private func projectSelectedGeneratedEdgesToConstructionPlane(
        _ targets: [SelectionTarget]
    ) {
        guard targets.isEmpty == false else {
            return
        }
        submitSource(
            .projectSketchCurvesToConstructionPlane(
                targets: targets,
                plane: activeSketchPlane(),
                name: nil
            )
        )
    }

    private func projectSelectedCurvesToGeneratedFace(
        _ targets: [SelectionTarget],
        face: SelectionTarget
    ) {
        guard targets.isEmpty == false else {
            return
        }
        submitSource(
            .projectCurvesToGeneratedFace(
                targets: targets,
                face: face,
                name: nil
            )
        )
    }

    private func projectSelectedBodyOutlinesToConstructionPlane(
        _ targets: [SelectionTarget]
    ) {
        guard targets.isEmpty == false else {
            return
        }
        submitSource(
            .projectBodyOutlinesToConstructionPlane(
                targets: targets,
                plane: activeSketchPlane(),
                name: nil
            )
        ) { result in
            moveCreatedObjects(of: result)
        }
    }

    /// Selects the objects a command created, the generated nodes no other generated node holds,
    /// and starts a Move of them, so a duplicate or an outline is placed before it is left, as
    /// Plasticity places it before OK.
    private func moveCreatedObjects(of result: CommandExecutionResult?) {
        guard result?.didMutate == true,
              let generated = result?.generatedIdentities.sceneNodeIDs,
              let metadata = workspace.view?.document.document.productMetadata else { return }
        let generatedIDs = Set(generated)
        let childIDs = Set(generated.flatMap { metadata.sceneNodes[$0]?.childIDs ?? [] })
        let roots = generated.filter { generatedIDs.contains($0) && !childIDs.contains($0) && metadata.sceneNodes[$0] != nil }
        guard !roots.isEmpty else { return }
        selectSceneNodes(roots)
        beginTransformSession(.move, sceneNodeIDs: roots)
    }

    /// The running O command's result: Offset Planar Curve with its Symmetric option, or Slot.
    private func createCommandedCurveOffset(_ target: SelectionTarget) {
        guard slotProfileCommandState.isCurveOffsetActive else {
            createSlotFromOffsetCurve(target, width: slotProfileWidthMeters)
            return
        }
        submitSource(
            .offsetCurve(
                target: target,
                // The typed distance's sign chooses the side; Core refuses zero.
                distance: .length(slotProfileWidthMeters, .meter),
                options: OffsetCurveOptions(
                    mode: .offset, isSymmetric: slotProfileCommandState.isSymmetric, gapFill: curveOffsetGapFill
                ),
                vertexHandle: nil
            )
        ) { result in
            if result?.didMutate == true {
                slotProfileCommandState.deactivate()
            }
        }
    }

    private func createSlotFromOffsetCurve(
        _ target: SelectionTarget,
        width meters: Double
    ) {
        submitSource(
            .offsetCurve(
                target: target,
                // Core refuses a width that is not positive.
                distance: .length(meters, .meter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: nil
            )
        ) { result in
            if result?.didMutate == true {
                slotProfileCommandState.deactivate()
            }
        }
    }


    private var transformPositionSliderMetersRange: ClosedRange<Double> {
        let span = snapshot.workspaceState.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return -span ... span
    }

    private var sizeSliderMetersRange: ClosedRange<Double> {
        let visibleSpan = snapshot.workspaceState.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return 0.0 ... visibleSpan
    }

    private var sortedMaterialOptions: [WorkspaceObjectMaterialOption] {
        snapshot.document.document.productMetadata.materialLibrary.materials
            .sorted { lhs, rhs in
                lhs.value.name.localizedStandardCompare(rhs.value.name) == .orderedAscending
            }
            .map { id, material in
                WorkspaceObjectMaterialOption(id: id, name: material.name)
            }
    }

    private func setObjectProperty(
        _ property: ObjectPropertyDefinition,
        value: ObjectPropertyValue,
        for shapes: [InspectorObjectShape]
    ) {
        let dimension: ObjectDimensionKind? = switch property.renderBinding {
        case .sizeX: .sizeX
        case .sizeY: .sizeY
        case .sizeZ: .sizeZ
        case .radius: .radius
        default: nil
        }
        if let dimension, case .length(let meters) = value,
           shapes.allSatisfy({ $0.size != nil }) {
            let ids = shapes.map(\.id)
            submitSource(name: "setObjectDimension") { current in
                try WorkspaceObjectShapeInspectorStateBuilder.dimensionCommands(
                    dimension, meters: meters, nodeIDs: ids, in: current.document.document,
                    currentEvaluation: current.cadInteraction, currentGeneration: current.documentGeneration)
            }
            return
        }
        let ids = shapes.map(\.id)
        submitSource(name: "setObjectProperty") { _ in
            guard value.valueKind == property.valueKind else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(property.title) expects a \(property.valueKind.rawValue) value."
                )
            }
            return ids.map { id in
                .setSceneNodeObjectProperty(
                    id: id,
                    propertyID: property.id,
                    value: value
                )
            }
        }
    }

    private func lengthSliderMetersRange(for meters: Double) -> ClosedRange<Double> {
        workspaceLengthSliderMetersRange(
            for: meters,
            ruler: snapshot.workspaceState.ruler
        )
    }

    private var regionOffsetSliderMetersRange: ClosedRange<Double> {
        lengthSliderMetersRange(for: regionOffsetDistanceMeters)
    }

    private func regionOffsetGapFillTitle(_ gapFill: OffsetCurveGapFill) -> String {
        switch gapFill {
        case .round:
            return "Round"
        case .linear:
            return "Linear"
        case .natural:
            return "Natural"
        }
    }

    private func sketchPointSummary(_ point: SketchEntitySummaryResult.Point) -> String {
        "x \(formatted(point.x)), y \(formatted(point.y))"
    }

    private func pointSummary(_ point: Point3D) -> String {
        "x \(formatted(point.x)), y \(formatted(point.y)), z \(formatted(point.z))"
    }

    private func vectorSummary(_ vector: Vector3D) -> String {
        let x = vector.x.formatted(.number.precision(.fractionLength(0...3)))
        let y = vector.y.formatted(.number.precision(.fractionLength(0...3)))
        let z = vector.z.formatted(.number.precision(.fractionLength(0...3)))
        return "x \(x), y \(y), z \(z)"
    }

    private func sketchLineLength(for entity: InspectorSketchEntity) -> Double? {
        guard let start = entity.start,
              let end = entity.end else {
            return nil
        }
        return sketchLineLength(start: start, end: end)
    }

    private func sketchLineLength(
        start: SketchEntitySummaryResult.Point,
        end: SketchEntitySummaryResult.Point
    ) -> Double? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        return length.isFinite && length > 0.0 ? length : nil
    }

    private func sketchLineAngleDegrees(for entity: InspectorSketchEntity) -> Double? {
        guard let start = entity.start,
              let end = entity.end else {
            return nil
        }
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let angle = atan2(deltaY, deltaX)
        return angle.isFinite ? WorkspaceInspectorNumberText.degrees(fromRadians: angle) : nil
    }

    private func sketchLineArcSagitta(for entity: InspectorSketchEntity) -> Double {
        guard let length = sketchLineLength(for: entity) else {
            return defaultSketchEntityMoveStepMeters
        }
        let ruler = snapshot.workspaceState.ruler.normalizedForWorkspaceScale()
        let bounded = min(
            length / 4.0,
            max(ruler.visibleSpanMeters / 20.0, ruler.minorTickMeters)
        )
        return max(bounded, defaultSketchEntityMoveStepMeters)
    }

    private func valueSummary(_ values: [String]) -> String {
        var uniqueValues: [String] = []
        var seenValues: Set<String> = []
        for value in values {
            guard seenValues.insert(value).inserted else {
                continue
            }
            uniqueValues.append(value)
        }
        guard !uniqueValues.isEmpty else {
            return "None"
        }
        if uniqueValues.count == 1 {
            return uniqueValues[0]
        }
        let visibleValues = uniqueValues.prefix(3).joined(separator: ", ")
        if uniqueValues.count > 3 {
            return "\(visibleValues), +\(uniqueValues.count - 3)"
        }
        return visibleValues
    }

    private func sweepSectionSummary(_ section: SectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(WorkspaceInspectorNumberText.shortID(profile.featureID))"
        case .curve(let curve):
            return "Curve \(WorkspaceInspectorNumberText.shortID(curve.featureID))"
        }
    }

    private var diagnosticSummary: String {
        let diagnostics = diagnostics
        let failures = failureLog.records.count
        guard !diagnostics.isEmpty || failures > 0 else {
            return "None"
        }
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(failures) failures, \(errors) errors, "
            + "\(warnings) warnings, \(info) info"
    }

    private var renderInvalidationReasonTitle: String {
        switch snapshot.evaluationSnapshot.renderInvalidation.reason {
        case .none:
            return "None"
        case .evaluated:
            return "Evaluated"
        case .evaluationFailed:
            return "Evaluation Failed"
        }
    }

    private var renderInvalidationGenerationTitle: String {
        guard let generation = snapshot.evaluationSnapshot.renderInvalidation.generation else {
            return "None"
        }
        return "\(generation.value)"
    }

    private var defaultMaterialTitle: String {
        let library = snapshot.document.document.productMetadata.materialLibrary
        guard let defaultMaterialID = library.defaultMaterialID else {
            return "None"
        }
        return library.materials[defaultMaterialID]?.name ?? "Missing"
    }

    private func lengthControl(
        _ title: String,
        meters: Double,
        sliderMetersRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        workspaceLengthControl(
            title,
            values: [meters],
            displayUnit: snapshot.workspaceState.displayUnit,
            sliderMetersRange: sliderMetersRange
        ) { nextMeters in
            onChange(max(nextMeters, 0.0))
        }
    }

    private var inspectorNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }

    private func setRulerConfiguration(
        minorTickMeters: Double? = nil,
        majorTickMeters: Double? = nil,
        visibleSpanMeters: Double? = nil
    ) {
        applyWorkspace(commands: { current in
            var ruler = current.workspaceState.ruler
            if let minorTickMeters {
                ruler.minorTickMeters = minorTickMeters
            }
            if let majorTickMeters {
                ruler.majorTickMeters = majorTickMeters
            }
            if let visibleSpanMeters {
                ruler.visibleSpanMeters = visibleSpanMeters
            }
            return [.setRulerConfiguration(ruler.normalizedForWorkspaceScale())]
        }) { published in
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
            if visibleSpanMeters != nil {
                requestViewportCameraReset()
            }
        }
    }

    private func applyDisplayUnit(_ unit: LengthDisplayUnit) {
        setDisplayUnit(unit) { published in
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
        }
    }

    private func applyViewportGridVisualSpacingMode(
        _ visualSpacingMode: ViewportGridVisualSpacingMode
    ) {
        setViewportGridSettings(
            ViewportGridSettings(visualSpacingMode: visualSpacingMode)
        )
    }

    private func applyWorkspaceRebaseTranslation(_ translation: Vector3D) {
        submitSource(.rebaseWorkspaceOrigin(translation: translation)) { result in
            guard result != nil,
                  let published = workspace.view else {
                return
            }
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
        }
    }

    private func applyWorkspaceScalePreset(_ preset: WorkspaceScalePreset) {
        setRulerConfiguration(preset.rulerConfiguration.normalizedForWorkspaceScale()) { _ in
            requestViewportCameraReset()
        }
    }

    private func fitWorkspaceScaleToModel() {
        let task = enqueueWorkspaceOperation {
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            let plan = WorkspaceScaleFitService().plan(
                bounds: current.viewport.worldBounds.map {
                    MeasurementResult.Bounds(
                        minX: $0.minimum.x,
                        minY: $0.minimum.y,
                        minZ: $0.minimum.z,
                        maxX: $0.maximum.x,
                        maxY: $0.maximum.y,
                        maxZ: $0.maximum.z
                    )
                },
                ruler: current.workspaceState.ruler
            )
            switch plan.action {
            case .alreadyFits:
                reportToolStatus("Workspace scale already fits the current presentation geometry.")
                return current
            case .unsupportedRange:
                reportToolStatus(
                    "Workspace scale cannot fit the current presentation geometry within the supported preset range.",
                    severity: .warning
                )
                return current
            case .applyPreset(let preset):
                let published = try await workspace.applyWorkspace(
                    .setRulerConfiguration(
                        preset.rulerConfiguration.normalizedForWorkspaceScale()
                    )
                )
                resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
                requestViewportCameraReset()
                return published
            }
        }
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func requestViewportCameraReset() {
        viewportCameraResetSignal += 1
    }

    private func upsertParameterExpression(
        name: String,
        expression: String,
        kind: QuantityKind
    ) async -> Bool {
        await performSource(name: "upsertParameter") { current in
            let parsedExpression = try ParameterExpressionParser().parseForUpsert(
                expression,
                parameterName: name,
                parameters: current.document.document.cadDocument.parameters,
                targetKind: kind,
                defaults: ParameterExpressionDefaults(
                    lengthUnit: current.workspaceState.displayUnit,
                    angleUnit: .degree
                )
            )
            return [
                .upsertParameter(
                    name: name,
                    expression: parsedExpression,
                    kind: kind
                ),
            ]
        }.last?.didMutate == true
    }

    private func renameDocumentParameter(
        currentName: String,
        newName: String
    ) async -> Bool {
        await performSource(
            .renameParameter(
                currentName: currentName,
                newName: newName
            )
        )?.didMutate == true
    }

    private func deleteDocumentParameter(name: String) async -> Bool {
        await performSource(.deleteParameter(name: name))?.didMutate == true
    }

    private func resetWorkspaceInteractionScaleDefaults(ruler: RulerConfiguration) {
        let defaults = WorkspaceInteractionScaleDefaults(ruler: ruler)
        sketchSplineControlPointSlideDistanceMeters = defaults.operationStepMeters
        polySplineSurfaceVertexSlideDistanceMeters = defaults.operationStepMeters
        surfaceControlPointFrameUMoveMeters = defaults.surfaceFrameTangentialMoveMeters
        surfaceControlPointFrameVMoveMeters = defaults.surfaceFrameTangentialMoveMeters
        surfaceControlPointFrameNormalMoveMeters = defaults.surfaceFrameNormalMoveMeters
        sketchRebuildToleranceMeters = defaults.sketchRebuildToleranceMeters
        sketchExtendDistanceMeters = defaults.operationStepMeters
        sketchVertexOffsetDistanceMeters = defaults.operationStepMeters
        sketchCornerTreatmentDistanceMeters = defaults.operationStepMeters
        regionOffsetDistanceMeters = defaults.operationStepMeters
        edgeOffsetDistanceMeters = defaults.operationStepMeters
        slotProfileWidthMeters = defaults.slotWidthMeters
    }

    private func inspectorRow(_ title: String, _ meters: Double) -> some View {
        inspectorControlRow(title) {
            Text(formatted(meters))
                .monospacedDigit()
        }
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        workspaceInspectorValueRow(title, value)
    }

    private func sceneNodeKindTitle(for reference: SceneNodeReference?) -> String {
        guard let reference else {
            return "Group"
        }
        switch reference.kind {
        case .feature:
            return "Feature"
        case .body:
            return "Body"
        case .sketch:
            return "Sketch"
        case .componentInstance:
            return "Component Instance"
        case .construction:
            return "Construction"
        case .authoredMesh:
            return "Authored Mesh"
        }
    }

    private var evaluationStatusTitle: String {
        switch snapshot.evaluationSnapshot.status {
        case .notEvaluated:
            return "Not Evaluated"
        case .valid:
            return "Valid"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private func formatted(_ meters: Double) -> String {
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: meters,
            preferredUnit: snapshot.workspaceState.displayUnit
        )
    }

    private func formattedDimensionValue(
        _ value: Double,
        kind: DimensionCommandEntry.ValueKind
    ) -> String {
        switch kind {
        case .length:
            let unit = dimensionInputDefaultUnit(kind, value: value)
            return WorkspaceInspectorNumberText.lengthString(
                fromMeters: value,
                unit: unit
            )
        case .angle:
            return WorkspaceInspectorNumberText.formattedDegrees(WorkspaceInspectorNumberText.degrees(fromRadians: value))
        }
    }

    private func dimensionInputText(
        _ value: Double,
        kind: DimensionCommandEntry.ValueKind
    ) -> String {
        switch kind {
        case .length:
            return workspaceLengthFieldPresentation(
                fromMeters: value,
                preferredUnit: snapshot.workspaceState.displayUnit
            ).text
        case .angle:
            return WorkspaceInspectorNumberText.string(from: WorkspaceInspectorNumberText.degrees(fromRadians: value))
        }
    }

    private func dimensionInputUnitSymbol(
        _ kind: DimensionCommandEntry.ValueKind,
        value: Double
    ) -> String {
        switch kind {
        case .length:
            return dimensionInputDefaultUnit(kind, value: value).symbol
        case .angle:
            return "deg"
        }
    }

    private func dimensionInputDefaultUnit(
        _ kind: DimensionCommandEntry.ValueKind,
        value: Double
    ) -> LengthDisplayUnit {
        switch kind {
        case .length:
            return workspaceLengthFieldPresentation(
                fromMeters: value,
                preferredUnit: snapshot.workspaceState.displayUnit
            ).unit
        case .angle:
            return snapshot.workspaceState.displayUnit
        }
    }

    private func arcSpanDegrees(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return WorkspaceInspectorNumberText.degrees(fromRadians: span)
    }

}
