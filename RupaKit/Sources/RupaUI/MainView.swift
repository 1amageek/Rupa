import Foundation
import MacComponent
import RupaCore
import RupaPreview
import RupaRendering
import SwiftUI

private enum WorkspaceCanvasOverlayLayout {
    static let edgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let topChromeHeight: CGFloat = ViewportCanvasChromeMetrics.topControlHeight
}

private struct ViewportContextPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
public struct MainView: View {
    @State private var session: EditorSession
    @State private var isPreviewExpanded: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var isInspectorPresented: Bool
    @State private var sidebarSearchText: String
    @State private var workspacePlaneMode: WorkspacePlaneMode
    @State private var selectionScope: WorkspaceSelectionScope
    @State private var selectionDragPreviewTargets: [SelectionTarget]
    @State private var patternArrayCurvePathPickState: PatternArrayCurvePathPickState
    @State private var patternArrayCurvePathPreviewCandidate: PatternArrayCurvePathCandidate?
    @State private var patternArraySummaryCache: PatternArraySummaryCache
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
    @State private var regionOffsetDistanceMeters: Double
    @State private var regionOffsetGapFill: OffsetCurveGapFill
    @State private var regionOffsetCommandState: RegionOffsetCommandState
    @State private var faceDraftAngleDegrees: Double
    @State private var edgeOffsetDistanceMeters: Double
    @State private var edgeOffsetGapFill: OffsetCurveGapFill
    @State private var edgeOffsetCommandState: EdgeOffsetCommandState
    @State private var dimensionCommandState: DimensionCommandState
    @State private var slotProfileWidthMeters: Double
    @State private var slotProfileCommandState: SlotProfileCommandState
    @State private var viewportProjectionBasis: ViewportProjectionBasis
    @State private var viewportContextPanelHeight: CGFloat
    @State private var viewportCameraResetSignal: Int
    @State private var isUtilityRailExpanded: Bool
    @State private var viewAlignedConstructionPlaneRequest: ViewAlignedConstructionPlaneRequest?
    @State private var viewportProjectionRequest: ViewportProjectionRequest?
    @State private var constructionPlaneRenameTargetID: ConstructionPlaneSourceID?
    @State private var constructionPlaneRenameText: String
    @State private var hoveredViewportPickingBackend: ViewportPickingBackend?
    @State private var viewportHoverClearSignal: Int
    @State private var agentSessionID: UUID?
    @FocusState private var isWorkspaceFocused: Bool

    private let objectRegistry: ObjectTypeRegistry
    private let agentHost: (any WorkspaceAgentHost)?
    private let documentURL: URL?

    public init(
        session: EditorSession = EditorSession(),
        isPreviewExpanded: Bool = false,
        columnVisibility: NavigationSplitViewVisibility = .all,
        isInspectorPresented: Bool = false,
        isUtilityRailExpanded: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        agentHost: (any WorkspaceAgentHost)? = nil,
        documentURL: URL? = nil
    ) {
        let editingDefaults = WorkspaceInteractionScaleDefaults(ruler: session.document.ruler)
        self._session = State(initialValue: session)
        self._isPreviewExpanded = State(initialValue: isPreviewExpanded)
        self._columnVisibility = State(initialValue: columnVisibility)
        self._isInspectorPresented = State(initialValue: isInspectorPresented)
        self._sidebarSearchText = State(initialValue: "")
        self._workspacePlaneMode = State(initialValue: .adaptive)
        self._selectionScope = State(initialValue: .object)
        self._selectionDragPreviewTargets = State(initialValue: [])
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
        self._viewportContextPanelHeight = State(initialValue: 0.0)
        self._viewportCameraResetSignal = State(initialValue: 0)
        self._isUtilityRailExpanded = State(initialValue: isUtilityRailExpanded)
        self._viewAlignedConstructionPlaneRequest = State(initialValue: nil)
        self._viewportProjectionRequest = State(initialValue: nil)
        self._constructionPlaneRenameTargetID = State(initialValue: nil)
        self._constructionPlaneRenameText = State(initialValue: "")
        self._viewportHoverClearSignal = State(initialValue: 0)
        self.objectRegistry = objectRegistry
        self.agentHost = agentHost
        self.documentURL = documentURL
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            editorDetailPane
                .navigationTitle(documentTitle)
                .toolbar {
                    editorToolbar
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1_120, minHeight: 720)
        .task {
            await activateAgentSessionIfNeeded()
        }
        .onDisappear {
            deactivateAgentSession()
        }
    }

    private var sidebar: some View {
        List(selection: selectedSceneNodeIDsBinding) {
            Section("Scenes") {
                ForEach(filteredSceneBrowserRows) { row in
                    componentBrowserRow(row.id, depth: row.depth)
                        .tag(row.id)
                }
            }

            if !filteredComponentDefinitionIDs.isEmpty {
                Section("Component Definitions") {
                    ForEach(filteredComponentDefinitionIDs, id: \.self) { id in
                        componentDefinitionRow(id)
                    }
                }
            }

            if !filteredComponentInstanceIDs.isEmpty {
                Section("Component Instances") {
                    ForEach(filteredComponentInstanceIDs, id: \.self) { id in
                        componentInstanceRow(id)
                    }
                }
            }

            if hasVisibleAssetRows {
                Section("Assets") {
                    ForEach(materialAssetRows) { row in
                        browserAssetRow(row)
                    }
                    ForEach(validationRuleAssetRows) { row in
                        browserAssetRow(row)
                    }
                    ForEach(exportPresetAssetRows) { row in
                        browserAssetRow(row)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $sidebarSearchText, prompt: "Search Browser")
        .navigationTitle("Browser")
    }

    private var selectedSceneNodeIDsBinding: Binding<Set<SceneNodeID>> {
        Binding(
            get: {
                Set(session.selection.selectedSceneNodeIDs)
            },
            set: { ids in
                let orderedIDs = sceneBrowserRows.map(\.id).filter { ids.contains($0) }
                patternArrayCurvePathPickState.cancel()
                _ = session.selectSceneNodes(orderedIDs)
                dimensionCommandState.deactivate()
            }
        )
    }

    private var documentTitle: String {
        guard let name = session.document.cadDocument.metadata.name,
              !name.isEmpty else {
            return "Untitled"
        }
        return name
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

    private var surfaceAnalysisDensitySummary: String {
        "\(surfaceAnalysisOptions.sampleDensity.samplesPerDirection) x \(surfaceAnalysisOptions.sampleDensity.samplesPerDirection)"
    }

    private var constructionPlaneSnapPlane: SketchPlane? {
        guard isConstructionPlaneSnapEnabled else {
            return nil
        }
        if let explicitPlane = workspacePlaneMode.sketchPlane {
            return explicitPlane
        }
        return session.activeConstructionPlane?.plane
    }

    private var constructionPlaneSnapSummary: String {
        guard isConstructionPlaneSnapEnabled else {
            return "Off"
        }
        if workspacePlaneMode.sketchPlane != nil {
            return workspacePlaneMode.title
        }
        if let activeConstructionPlane = session.activeConstructionPlane {
            return activeConstructionPlane.name
        }
        return "No Plane"
    }

    private var savedConstructionPlaneSummary: ConstructionPlaneSummaryResult {
        ConstructionPlaneSummaryService().summarize(document: session.document)
    }

    private var sceneBrowserRows: [SceneBrowserRow] {
        var rows: [SceneBrowserRow] = []
        let metadata = session.document.productMetadata

        func append(_ id: SceneNodeID, depth: Int) {
            guard let node = metadata.sceneNodes[id] else {
                return
            }
            rows.append(SceneBrowserRow(id: id, depth: depth))
            for childID in node.childIDs {
                append(childID, depth: depth + 1)
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
            guard let node = session.document.productMetadata.sceneNodes[row.id] else {
                return false
            }
            return matchesSidebarSearch(node.name, sceneNodeKindTitle(for: node.reference))
        }
    }

    private var componentDefinitionIDs: [ComponentDefinitionID] {
        session.document.productMetadata.componentDefinitions.values
            .sorted { $0.name < $1.name }
            .map(\.id)
    }

    private var filteredComponentDefinitionIDs: [ComponentDefinitionID] {
        guard !normalizedSidebarSearchText.isEmpty else {
            return componentDefinitionIDs
        }

        return componentDefinitionIDs.filter { id in
            guard let definition = session.document.productMetadata.componentDefinitions[id] else {
                return false
            }
            return matchesSidebarSearch(definition.name, "Component Definition")
        }
    }

    private var componentInstanceIDs: [ComponentInstanceID] {
        session.document.productMetadata.componentInstances.values
            .sorted { $0.name < $1.name }
            .map(\.id)
    }

    private var filteredComponentInstanceIDs: [ComponentInstanceID] {
        guard !normalizedSidebarSearchText.isEmpty else {
            return componentInstanceIDs
        }

        return componentInstanceIDs.filter { id in
            guard let instance = session.document.productMetadata.componentInstances[id] else {
                return false
            }
            return matchesSidebarSearch(instance.name, "Component Instance")
        }
    }

    private var materialAssetRows: [SidebarAssetRow] {
        session.document.productMetadata.materialLibrary.materials.values
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
        session.document.productMetadata.validationRules.values
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
        session.document.productMetadata.exportPresets.values
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

    @ViewBuilder
    private var editorDetailPane: some View {
        if isInspectorPresented {
            HSplitPane {
                workArea
                inspectorPane
            }
            .leadingPaneWidth(minimum: 560)
            .trailingPaneWidth(minimum: 320)
            .dividerDragStrip(width: 10)
        } else {
            workArea
        }
    }

    private var workArea: some View {
        CollapsibleView(isExpanded: $isPreviewExpanded) {
            ZStack {
                let sectionAnalysis = selectedSectionAnalysisSummary
                Viewport(
                    document: session.document,
                    currentEvaluation: session.currentEvaluation,
                    documentGeneration: session.generation,
                    objectRegistry: objectRegistry,
                    evaluationStatus: session.evaluationStatus,
                    renderInvalidation: session.renderInvalidation,
                    selection: session.selection,
                    selectionDragPreviewTargets: selectionDragPreviewTargets,
                    patternArrayCurvePathReplacementPreviewRequest: patternArrayCurvePathReplacementPreviewRequest,
                    surfaceAnalysis: selectedSurfaceAnalysisSummary,
                    surfaceAnalysisOptions: surfaceAnalysisOptions,
                    surfaceContinuity: selectedSurfaceContinuitySummary,
                    sectionAnalysis: sectionAnalysis,
                    sectionClippingPlan: selectedSectionClippingPlan(for: sectionAnalysis),
                    curveCurvatureDisplays: session.document.productMetadata.curveCurvatureDisplays,
                    pointDisplays: session.document.productMetadata.pointDisplays,
                    snapResolutionOptions: activeSnapResolutionOptions(),
                    canvasDragPreviewKind: canvasDragPreviewKind,
                    canvasDragAxisConstraint: activeCanvasDragAxisConstraint,
                    canvasDragSketchPlaneOverride: workspacePlaneMode.sketchPlane,
                    projectionRequest: viewportProjectionRequest,
                    selectionHitPolicy: selectionScope.viewportSelectionHitPolicy,
                    bottomChromeReservedHeight: viewportContextPanelHeight,
                    gridVisualSpacingMode: session.document.productMetadata.viewportGridSettings.visualSpacingMode,
                    cameraResetSignal: viewportCameraResetSignal,
                    hoverClearSignal: viewportHoverClearSignal,
                    showsConstructionPlaneHover: showsConstructionPlaneHover,
                    allowsSelectionRectangle: allowsSelectionRectangle,
                    allowsObjectAffordances: allowsObjectAffordances,
                    slotWidthMeters: slotProfileWidthMeters,
                    sketchVertexOffsetDistanceMeters: sketchVertexOffsetDistanceMeters,
                    edgeOffsetDistanceMeters: edgeOffsetDistanceMeters,
                    onPick: handleViewportPick,
                    onCanvasDrag: handleViewportDrag,
                    onShiftScroll: viewportShiftScrollHandler,
                    onReferenceLineAnchor: viewportReferenceLineAnchorHandler,
                    onSelectionDrag: handleViewportSelectionDrag,
                    onSelectionDragPreview: viewportSelectionDragPreviewHandler,
                    onVertexDrag: viewportVertexDragHandler,
                    onFaceDrag: viewportFaceDragHandler,
                    onEdgeChamferDrag: viewportEdgeChamferDragHandler,
                    onEdgeFilletDrag: viewportEdgeFilletDragHandler,
                    onRegionOffsetDrag: viewportRegionOffsetDragHandler,
                    onEdgeOffsetDrag: viewportEdgeOffsetDragHandler,
                    onSlotWidthDrag: viewportSlotWidthDragHandler,
                    onSketchVertexOffsetDrag: viewportSketchVertexOffsetDragHandler,
                    onPatternArrayLinearAxisDrag: viewportPatternArrayLinearAxisDragHandler,
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
                    onCommandConfirm: viewportCommandConfirmHandler,
                    onHover: viewportHoverHandler,
                    onSnapCandidateKindChange: { kind in
                        snapOverrideState.updateHoveredCandidateKind(kind)
                    },
                    onProjectionBasisChange: { basis in
                        viewportProjectionBasis = basis
                    }
                )
                .zIndex(0)
            }
            .overlay(alignment: .top) {
                workspaceTopBar
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .onHover(perform: handleWorkspaceOverlayHover)
            }
            .overlay(alignment: .leading) {
                floatingToolPalette
                    .padding(.leading, 8)
                    .onHover(perform: handleWorkspaceOverlayHover)
            }
            .overlay(alignment: .trailing) {
                workspaceUtilityRail
                    .padding(.trailing, 8)
                    .onHover(perform: handleWorkspaceOverlayHover)
            }
            .overlay(alignment: .bottom) {
                viewportContextPanelContainer
                    .padding(.bottom, WorkspaceCanvasOverlayLayout.edgePadding)
                    .padding(.horizontal, WorkspaceCanvasOverlayLayout.edgePadding)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ViewportContextPanelHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                    .onHover(perform: handleWorkspaceOverlayHover)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(ViewportContextPanelHeightPreferenceKey.self) { height in
                let normalizedHeight = max(0.0, height.rounded(.up))
                if abs(viewportContextPanelHeight - normalizedHeight) > 0.5 {
                    viewportContextPanelHeight = normalizedHeight
                }
            }
        } content: {
            PreviewSurface(
                document: session.document,
                evaluationStatus: session.evaluationStatus,
                evaluatedGeneration: session.evaluatedGeneration,
                evaluatedBodyCount: session.evaluatedBodyCount,
                diagnostics: session.diagnostics
            )
        } header: {
            Label("Logs", systemImage: "list.bullet.rectangle")
                .font(.headline)
        }
        .topPaneHeight(minimum: 420)
        .bottomPaneHeight(minimum: 140)
        .dividerDragStrip(height: 10)
        .collapsibleToggleHelp(expanded: "Hide Logs", collapsed: "Show Logs")
        .frame(minWidth: 560)
        // Keyboard focus is an input scope; visible canvas affordances are drawn by the viewport.
        .focusable()
        .focusEffectDisabled()
        .focused($isWorkspaceFocused)
        .onAppear {
            isWorkspaceFocused = true
        }
        .onKeyPress(phases: .all) { keyPress in
            handleWorkspaceKeyPress(keyPress)
        }
        .onChange(of: selectionScope) { _, newScope in
            selectionDragPreviewTargets = []
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
        }
    }

    private var inspectorPane: some View {
        inspectorContent
            .frame(
                minWidth: 320,
                idealWidth: 420,
                maxWidth: 440,
                maxHeight: .infinity,
                alignment: .top
            )
            .accessibilityIdentifier("InspectorPane")
    }

    private var viewportHoverHandler: ((ViewportHit?) -> Void)? {
        guard session.selectedTool == .select else {
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

    private var viewportVertexDragHandler: ((ViewportVertexDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return nil
        }
        return { target in
            handleViewportVertexDrag(target)
        }
    }

    private var viewportFaceDragHandler: ((ViewportFaceDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .face else {
            return nil
        }
        return { target in
            handleViewportFaceDrag(target)
        }
    }

    private var viewportEdgeChamferDragHandler: ((ViewportEdgeChamferDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .edge else {
            return nil
        }
        return { target in
            handleViewportEdgeChamferDrag(target)
        }
    }

    private var viewportEdgeFilletDragHandler: ((ViewportEdgeFilletDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .edge else {
            return nil
        }
        return { target in
            handleViewportEdgeFilletDrag(target)
        }
    }

    private var viewportRegionOffsetDragHandler: ((ViewportRegionOffsetDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .region,
              regionOffsetCommandState.isActive,
              selectedRegionTargets.isEmpty == false else {
            return nil
        }
        return { target in
            handleViewportRegionOffsetDrag(target)
        }
    }

    private var viewportEdgeOffsetDragHandler: ((ViewportEdgeOffsetDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .edge,
              edgeOffsetCommandState.isActive,
              selectedEdgeOffsetSupportResolution.isSupported else {
            return nil
        }
        return { target in
            handleViewportEdgeOffsetDrag(target)
        }
    }

    private var viewportSelectionDragPreviewHandler: ((ViewportSelectionDragTarget) -> Void)? {
        guard session.selectedTool == .select else {
            return nil
        }
        return { target in
            handleViewportSelectionDragPreview(target)
        }
    }

    private var viewportSlotWidthDragHandler: ((ViewportSlotWidthDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity,
              slotProfileCommandState.isActive,
              selectedSlotSourceCurveTarget != nil else {
            return nil
        }
        return { target in
            handleViewportSlotWidthDrag(target)
        }
    }

    private var viewportSketchVertexOffsetDragHandler: ((ViewportSketchVertexOffsetDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity,
              selectedSketchVertexOffsetTarget != nil else {
            return nil
        }
        return { target in
            handleViewportSketchVertexOffsetDrag(target)
        }
    }

    private var viewportPatternArrayLinearAxisDragHandler: ((ViewportPatternArrayLinearAxisDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayLinearAxisDrag(target)
        }
    }

    private var viewportIndependentCopyExtrudeDistanceDragHandler: ((ViewportIndependentCopyExtrudeDistanceDragTarget) -> Void)? {
        guard session.selectedTool == .select else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyExtrudeDistanceDrag(target)
        }
    }

    private var viewportIndependentCopyBodyDimensionDragHandler: ((ViewportIndependentCopyBodyDimensionDragTarget) -> Void)? {
        guard session.selectedTool == .select else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyBodyDimensionDrag(target)
        }
    }

    private var viewportPatternArrayRadialAngleDragHandler: ((ViewportPatternArrayRadialAngleDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayRadialAngleDrag(target)
        }
    }

    private var viewportPatternArrayCopyCountDragHandler: ((ViewportPatternArrayCopyCountDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCopyCountDrag(target)
        }
    }

    private var viewportPatternArrayCurveExtentDragHandler: ((ViewportPatternArrayCurveExtentDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            guard session.selectedTool == .select,
                  let state = patternArrayInspectorState(for: selectedSceneNodes),
                  state.sourceID == target.sourceID else {
                return
            }
            let service = PatternArrayEditingService(
                session: session,
                sourceID: target.sourceID
            )
            let result: CommandExecutionResult?
            switch target.extent {
            case .distance(let meters):
                result = service.setCurveExtentDistance(meters)
            case .ratio(let ratio):
                result = service.setCurveExtentRatio(ratio)
            }
            if result?.diagnostics.isEmpty == false {
                isPreviewExpanded = true
            }
        }
    }

    private var viewportPatternArrayCurvePathPointDragHandler: ((ViewportPatternArrayCurvePathPointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCurvePathPointDrag(target)
        }
    }

    private var viewportPatternArrayOutputModeChangeHandler: ((ViewportPatternArrayOutputModeTarget) -> Void)? {
        guard session.selectedTool == .select,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayOutputModeChange(target)
        }
    }

    private var viewportSketchCurveHandleDragHandler: ((ViewportSketchCurveHandleDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchCurveHandleDrag(target)
        }
    }

    private var viewportSketchDimensionDragHandler: ((ViewportSketchDimensionDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchDimensionDrag(target)
        }
    }

    private var viewportSketchPointHandleDragHandler: ((ViewportSketchPointHandleDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchPointHandleDrag(target)
        }
    }

    private var viewportSplineControlPointDragHandler: ((ViewportSplineControlPointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSplineControlPointDrag(target)
        }
    }

    private var viewportBridgeCurveEndpointDragHandler: ((ViewportBridgeCurveEndpointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportBridgeCurveEndpointDrag(target)
        }
    }

    private var viewportSplineControlPointSlideDragHandler: ((ViewportSplineControlPointSlideDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity,
              slideCommandState.isCurveControlVerticesActive else {
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
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexDrag(target)
        }
    }

    private var viewportSurfaceControlPointDragHandler: ((ViewportSurfaceControlPointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointDrag(target)
        }
    }

    private var viewportSurfaceTrimEndpointDragHandler: ((ViewportSurfaceTrimEndpointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimEndpointDrag(target)
        }
    }

    private var viewportSurfaceTrimControlPointDragHandler: ((ViewportSurfaceTrimControlPointDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimControlPointDrag(target)
        }
    }

    private var viewportPolySplineSurfaceVertexSlideDragHandler: ((ViewportPolySplineSurfaceVertexSlideDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexSlideDrag(target)
        }
    }

    private var viewportSurfaceControlPointSlideDragHandler: ((ViewportSurfaceControlPointSlideDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointSlideDrag(target)
        }
    }

    private var viewportSurfaceFrameDragHandler: ((ViewportSurfaceFrameDragTarget) -> Void)? {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceFrameDrag(target)
        }
    }

    private var allowsSelectionRectangle: Bool {
        session.selectedTool == .select && selectionScope.allowsSelectionRectangle
    }

    private var hasActiveWorkspaceCommand: Bool {
        regionOffsetCommandState.isActive
            || edgeOffsetCommandState.isActive
            || slotProfileCommandState.isActive
            || slideCommandState.isActive
    }

    @discardableResult
    private func confirmActiveWorkspaceCommand() -> Bool {
        if slideCommandState.isCurveControlVerticesActive {
            slideCommandState.deactivate()
            session.reportToolStatus("Slide Curve CV complete.")
            return true
        }
        if slideCommandState.isSurfaceControlVerticesActive {
            slideCommandState.deactivate()
            session.reportToolStatus("Slide Surface CV complete.")
            return true
        }
        if regionOffsetCommandState.isActive {
            regionOffsetCommandState.deactivate()
            session.reportToolStatus("Offset Region complete.")
            return true
        }
        if edgeOffsetCommandState.isActive {
            edgeOffsetCommandState.deactivate()
            session.reportToolStatus("Offset Edge complete.")
            return true
        }
        if slotProfileCommandState.isActive {
            slotProfileCommandState.deactivate()
            session.reportToolStatus("Slot complete.")
            return true
        }
        return false
    }

    private var allowsObjectAffordances: Bool {
        session.selectedTool == .select && selectionScope == .object
    }

    private var canvasDragPreviewKind: ViewportCanvasDragPreviewKind? {
        switch session.selectedTool {
        case .sketch, .solid:
            .rectangle(
                widthMeters: activeSketchWidthInputMeters,
                heightMeters: activeSketchHeightInputMeters
            )
        case .polygon:
            .polygon(
                session.polygonToolState,
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
        default:
            nil
        }
    }

    private var activeCanvasDragAxisConstraint: SketchAxisConstraint? {
        guard usesSketchAxisConstraint else {
            return nil
        }
        return session.sketchInputState.axisConstraint
    }

    private var activeSketchAxisTitle: String {
        session.sketchInputState.axisConstraint?.statusTitle ?? "Free"
    }

    private var activeSketchDimensionInputTitle: String {
        guard let focus = session.sketchInputState.dimensionInputFocus else {
            return "Off"
        }
        switch focus {
        case .length:
            guard let lengthMeters = session.sketchInputState.dimensionInputLengthMeters else {
                return focus.statusTitle
            }
            let length = WorkspaceInspectorNumberText.lengthString(
                fromMeters: lengthMeters,
                unit: session.document.displayUnit
            )
            return "\(focus.statusTitle) \(length)"
        case .angle:
            guard let angleRadians = session.sketchInputState.dimensionInputAngleRadians else {
                return focus.statusTitle
            }
            let degrees = (angleRadians * 180.0 / Double.pi)
                .formatted(.number.precision(.fractionLength(0...2)))
            return "\(focus.statusTitle) \(degrees) deg"
        case .width:
            guard let widthMeters = session.sketchInputState.dimensionInputWidthMeters else {
                return focus.statusTitle
            }
            let width = WorkspaceInspectorNumberText.lengthString(
                fromMeters: widthMeters,
                unit: session.document.displayUnit
            )
            return "\(focus.statusTitle) \(width)"
        case .height:
            guard let heightMeters = session.sketchInputState.dimensionInputHeightMeters else {
                return focus.statusTitle
            }
            let height = WorkspaceInspectorNumberText.lengthString(
                fromMeters: heightMeters,
                unit: session.document.displayUnit
            )
            return "\(focus.statusTitle) \(height)"
        }
    }

    private var activeSketchLengthInputMeters: Double? {
        guard session.sketchInputState.dimensionInputFocus == .length,
              let lengthMeters = session.sketchInputState.dimensionInputLengthMeters,
              lengthMeters.isFinite,
              lengthMeters > 0.0 else {
            return nil
        }
        return lengthMeters
    }

    private var activeSketchAngleInputRadians: Double? {
        guard session.sketchInputState.dimensionInputFocus == .angle,
              let angleRadians = session.sketchInputState.dimensionInputAngleRadians,
              angleRadians.isFinite else {
            return nil
        }
        return angleRadians
    }

    private var activeSketchWidthInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let widthMeters = session.sketchInputState.dimensionInputWidthMeters,
              widthMeters.isFinite,
              widthMeters > 0.0 else {
            return nil
        }
        return widthMeters
    }

    private var activeSketchHeightInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let heightMeters = session.sketchInputState.dimensionInputHeightMeters,
              heightMeters.isFinite,
              heightMeters > 0.0 else {
            return nil
        }
        return heightMeters
    }

    private var isRectangleDimensionInputActive: Bool {
        switch session.sketchInputState.dimensionInputFocus {
        case .width, .height:
            return true
        case .length, .angle, nil:
            return false
        }
    }

    private var activeSketchDimensionInputFocuses: [SketchDimensionInputFocus] {
        switch session.selectedTool {
        case .sketch, .solid:
            [.width, .height]
        case .surface:
            [.length]
        case .polygon, .arc:
            [.length, .angle]
        case .spline:
            [.length, .angle]
        case .select, .sweep, .mesh, .measure, .section:
            []
        }
    }

    private var viewportShiftScrollHandler: ((ViewportScrollDirection) -> Bool)? {
        guard session.selectedTool == .polygon else {
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
            session.addSketchReferenceLineAnchor(at: point)
        }
    }

    private var usesSketchAxisConstraint: Bool {
        switch session.selectedTool {
        case .sketch, .polygon, .arc, .spline, .solid, .surface:
            true
        case .select, .sweep, .mesh, .measure, .section:
            false
        }
    }

    private var showsConstructionPlaneHover: Bool {
        switch session.selectedTool {
        case .sketch, .polygon, .arc, .spline, .solid, .surface, .section:
            true
        case .select, .sweep, .mesh, .measure:
            false
        }
    }

    private var workspaceTopBar: some View {
        HStack(spacing: 8) {
            workspaceStatusChip(
                evaluationStatusTitle,
                systemImage: evaluationStatusSystemImage,
                tint: evaluationStatusTint
            )

            workspaceStatusChip(
                "\(selectedTargetCount) selected",
                systemImage: "scope",
                tint: .secondary
            )

            if let scaleFitPromptState = workspaceScaleFitPromptState {
                workspaceScaleFitPromptButton(scaleFitPromptState)
            }

            workspaceScaleMenu

            workspaceIconButton(
                systemImage: isPreviewExpanded ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                help: isPreviewExpanded ? "Hide Logs" : "Show Logs",
                accessibilityIdentifier: "WorkspaceCommand.logs"
            ) {
                isPreviewExpanded.toggle()
            }

            workspaceIconButton(
                systemImage: "checkmark.seal",
                help: "Validate Document",
                accessibilityIdentifier: "WorkspaceCommand.validate"
            ) {
                session.validateDocument()
            }

            workspaceIconButton(
                systemImage: isInspectorPresented ? "sidebar.trailing" : "sidebar.trailing",
                help: "Inspector",
                accessibilityIdentifier: "WorkspaceCommand.inspector"
            ) {
                isInspectorPresented.toggle()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: WorkspaceCanvasOverlayLayout.topChromeHeight)
        .fixedSize(horizontal: true, vertical: false)
        .workspaceGlassContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceTopBar")
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.resetDocument()
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New Document")

            Button {
                session.validateDocument()
            } label: {
                Image(systemName: "checkmark.seal")
            }
            .help("Validate Document")

            Button {
                isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Inspector")
            .accessibilityIdentifier("InspectorToggle")
        }
    }

    private var workspaceScaleSummary: WorkspaceScaleStatusSummary {
        WorkspaceScaleStatusSummary(ruler: session.document.ruler)
    }

    private var currentWorkspaceScaleRecommendation: WorkspaceScaleRecommendation? {
        let workspaceBounds = session.currentEvaluation.flatMap {
            WorkspaceBoundsService().bounds(for: $0.evaluatedDocument)
        }
        return WorkspaceScaleRecommendationService().recommendation(
            for: workspaceBounds,
            currentRuler: session.document.ruler
        )
    }

    private var workspaceScaleFitPromptState: WorkspaceScaleFitPromptState? {
        WorkspaceScaleFitPromptState(recommendation: currentWorkspaceScaleRecommendation)
    }

    private var fixedGridVisualSpacingBinding: Binding<Bool> {
        Binding(
            get: {
                session.document.productMetadata.viewportGridSettings.visualSpacingMode == .fixed
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
                        .lineLimit(1)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "scope")
                        .symbolRenderingMode(.hierarchical)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
                .frame(height: WorkspaceChromeControlMetrics.controlHeight)
                .background {
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                        .fill(Color.accentColor.opacity(0.14))
                }
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

    private var workspaceScaleMenu: some View {
        let summary = workspaceScaleSummary
        return Menu {
            Section("Current") {
                Text(summary.detailTitle)
            }
            if let recommendation = currentWorkspaceScaleRecommendation {
                Section("Model Fit") {
                    if recommendation.isActionable {
                        Button {
                            fitWorkspaceScaleToModel()
                        } label: {
                            Label("Fit to \(recommendation.recommendedPreset.title)", systemImage: "scope")
                        }
                    } else {
                        Text("Beyond supported workspace range")
                    }
                }
            }
            if summary.smallerPreset != nil || summary.largerPreset != nil {
                Section("Adjust") {
                    if let smallerPreset = summary.smallerPreset {
                        Button {
                            applyWorkspaceScalePreset(smallerPreset)
                        } label: {
                            Label("Smaller Workspace: \(smallerPreset.title)", systemImage: "minus.circle")
                        }
                    }
                    if let largerPreset = summary.largerPreset {
                        Button {
                            applyWorkspaceScalePreset(largerPreset)
                        } label: {
                            Label("Larger Workspace: \(largerPreset.title)", systemImage: "plus.circle")
                        }
                    }
                }
            }
            Section("Scale Preset") {
                ForEach(WorkspaceScalePreset.profiles, id: \.preset) { profile in
                    let preset = profile.preset
                    Button {
                        applyWorkspaceScalePreset(preset)
                    } label: {
                        Text(profile.menuTitle)
                    }
                }
            }
            Section("Display Unit") {
                ForEach(LengthDisplayUnit.allCases) { unit in
                    Button(unit.symbol) {
                        applyDisplayUnit(unit)
                    }
                }
            }
        } label: {
            Label {
                Text(summary.compactTitle)
                    .lineLimit(1)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "ruler")
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
            .frame(height: WorkspaceChromeControlMetrics.controlHeight)
            .background {
                RoundedRectangle(
                    cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                    style: .continuous
                )
                    .fill(Color.secondary.opacity(0.12))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Workspace Scale")
        .accessibilityIdentifier("WorkspaceScale.menu")
        .accessibilityLabel("Workspace Scale")
        .accessibilityValue(summary.accessibilityValue)
    }

    private var floatingToolPalette: some View {
        WorkspaceToolPalette(
            selectedTool: session.selectedTool,
            activate: { activateTool($0) },
            help: { toolHelp(for: $0) },
            accessibilityIdentifier: { canvasToolIdentifier(for: $0) }
        )
    }

    private var workspaceUtilityRail: some View {
        Group {
            if isUtilityRailExpanded {
                expandedWorkspaceUtilityRail
            } else {
                collapsedWorkspaceUtilityRail
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceUtilityRail")
    }

    private var expandedWorkspaceUtilityRail: some View {
        VStack(alignment: .leading, spacing: WorkspaceUtilityRailLayout.sectionSpacing) {
            workspaceUtilityRailHeader

            workspaceRailSection("Select") {
                WorkspaceSelectionScopeControl(selection: $selectionScope)
            }

            workspaceRailSection("Snap") {
                HStack(spacing: 6) {
                    workspaceToggleButton(
                        isOn: $isGridSnapEnabled,
                        systemImage: "grid",
                        title: "Grid",
                        help: "Grid Snap",
                        accessibilityIdentifier: "WorkspaceSnap.grid"
                    )
                    workspaceToggleButton(
                        isOn: $isObjectTargetingEnabled,
                        systemImage: "dot.scope",
                        title: "Object",
                        help: "Object Targeting",
                        accessibilityIdentifier: "WorkspaceSnap.object"
                    )
                    workspaceToggleButton(
                        isOn: fixedGridVisualSpacingBinding,
                        systemImage: "lock",
                        title: "Fixed",
                        help: "Fixed Visual Grid",
                        accessibilityIdentifier: "WorkspaceGrid.fixed"
                    )
                }
                let scaleSummary = workspaceScaleSummary
                workspaceValueRow("Scale", "\(scaleSummary.presetTitle) · \(scaleSummary.displayUnitTitle)")
                workspaceValueRow("Grid", session.document.productMetadata.viewportGridSettings.visualSpacingMode.title)
                workspaceValueRow("Step", scaleSummary.minorStepTitle)
                workspaceValueRow("Major", scaleSummary.majorStepTitle)
                workspaceValueRow("Visible", scaleSummary.visibleSpanTitle)
            }

            workspaceRailSection("Plane") {
                let planeSummary = savedConstructionPlaneSummary
                WorkspacePlaneModeControl(selection: $workspacePlaneMode)
                workspaceToggleButton(
                    isOn: $isConstructionPlaneSnapEnabled,
                    systemImage: "square.grid.2x2",
                    title: "2D",
                    help: "2D Construction Plane Snap",
                    accessibilityIdentifier: "WorkspacePlane.twoDSnap"
                )
                if let activeConstructionPlane = session.activeConstructionPlane {
                    workspaceValueRow("Active", activeConstructionPlane.name)
                }
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

            workspaceRailSection("Analysis") {
                WorkspaceSurfaceAnalysisControl(options: $surfaceAnalysisOptions)
                workspaceValueRow("Overlay", surfaceAnalysisOverlaySummary)
                workspaceValueRow("Samples", surfaceAnalysisDensitySummary)
            }

            workspaceRailSection("Scene") {
                workspaceValueRow("Bodies", "\(session.evaluatedBodyCount)")
                workspaceValueRow("Nodes", "\(session.document.productMetadata.sceneNodes.count)")
                workspaceValueRow("Issues", diagnosticSummary)
            }
        }
        .padding(WorkspaceUtilityRailLayout.contentPadding)
        .frame(width: WorkspaceUtilityRailLayout.expandedWidth, alignment: .topLeading)
        .workspaceGlassContainer()
        .accessibilityIdentifier("WorkspaceUtilityRail.expanded")
    }

    private var workspaceUtilityRailHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("Controls")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            workspaceIconButton(
                systemImage: "chevron.right",
                help: "Collapse Canvas Controls",
                accessibilityIdentifier: "WorkspaceUtilityRail.collapse"
            ) {
                setUtilityRailExpanded(false)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var collapsedWorkspaceUtilityRail: some View {
        WorkspaceUtilityRailCompactView(
            selectionScope: selectionScope,
            isGridSnapEnabled: isGridSnapEnabled,
            isObjectTargetingEnabled: isObjectTargetingEnabled,
            constructionPlaneTitle: constructionPlaneSnapSummary,
            isConstructionPlaneActive: workspacePlaneMode != .adaptive
                || session.activeConstructionPlane != nil
                || viewAlignedConstructionPlaneRequest != nil,
            surfaceAnalysisTitle: surfaceAnalysisOverlaySummary,
            isSurfaceAnalysisActive: surfaceAnalysisOverlaySummary != "Off",
            diagnosticTitle: diagnosticSummary,
            hasDiagnostics: !session.diagnostics.isEmpty
        ) {
            setUtilityRailExpanded(true)
        }
    }

    private func setUtilityRailExpanded(_ isExpanded: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            isUtilityRailExpanded = isExpanded
        }
    }

    private var viewportContextPanelContainer: some View {
        ViewThatFits(in: .horizontal) {
            viewportContextPanelContent
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(height: WorkspaceCanvasOverlayLayout.topChromeHeight)
                .workspaceGlassContainer()

            ScrollView(.horizontal) {
                viewportContextPanelContent
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
            .frame(height: WorkspaceCanvasOverlayLayout.topChromeHeight)
            .workspaceGlassContainer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanelContainer")
    }

    private var viewportContextPanelContent: some View {
        HStack(spacing: 8) {
            if session.selectedTool == .sweep {
                let preview = session.sweepSelectionPreview()
                WorkspaceSweepContextPanel(
                    preview: preview,
                    sectionLabel: sweepPreviewSectionLabel(preview.section),
                    pathLabel: sweepPreviewFeatureLabel(preview.pathFeatureID)
                )
            } else if session.selectedTool == .polygon {
                WorkspacePolygonContextPanel(
                    tool: session.selectedTool,
                    state: session.polygonToolState,
                    planeTitle: workspacePlaneMode.title,
                    axisTitle: activeSketchAxisTitle,
                    referenceLineAnchorCount: session.sketchInputState.referenceLineAnchors.count,
                    dimensionInputTitle: activeSketchDimensionInputTitle,
                    isGridSnapEnabled: isGridSnapEnabled,
                    decreaseSideCount: { _ = session.adjustPolygonSideCount(by: -1) },
                    increaseSideCount: { _ = session.adjustPolygonSideCount(by: 1) },
                    toggleSizingMode: { _ = session.togglePolygonSizingMode() },
                    toggleInclinationMode: { _ = session.togglePolygonInclinationMode() },
                    toggleKnifeMode: { _ = session.togglePolygonCutsFaces() }
                ) {
                    workspaceSketchDimensionInputField
                }
            } else if dimensionCommandState.isActive {
                dimensionContextPanelContent()
            } else if selectedSceneNodes.isEmpty {
                workspaceStatusChip(
                    session.selectedTool.title,
                    systemImage: session.selectedTool.systemImage,
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
                    workspaceValuePill(
                        "Refs",
                        "\(session.sketchInputState.referenceLineAnchors.count)",
                        accessibilityIdentifier: "WorkspaceSketch.referenceLines"
                    )
                    workspaceValuePill(
                        "Input",
                        activeSketchDimensionInputTitle,
                        accessibilityIdentifier: "WorkspaceSketch.dimensionInputFocus"
                    )
                    workspaceSketchDimensionInputField
                }
                workspaceValuePill("Select", selectionScope.title)
                if let qualitySummary = selectionQualitySummary {
                    workspaceValuePill(
                        "Quality",
                        qualitySummary.ratingTitle,
                        accessibilityIdentifier: "WorkspaceQuality.rating"
                    )
                    workspaceValuePill(
                        "Gate",
                        qualitySummary.attentionGateTitle,
                        accessibilityIdentifier: "WorkspaceQuality.gate"
                    )
                }
                viewportPickingPills
                workspaceValuePill("Grid", isGridSnapEnabled ? "On" : "Off")
                workspaceValuePill("Object", isObjectTargetingEnabled ? "On" : "Off")
                workspaceValuePill("2D", constructionPlaneSnapSummary)
                workspaceValuePill("Analysis", surfaceAnalysisOverlaySummary)
            } else {
                selectionContextPanelContent(selectedSceneNodes)
            }
            if viewAlignedConstructionPlaneRequest != nil {
                workspaceContextDivider
                workspaceValuePill(
                    "CPlane",
                    "Pick Origin",
                    accessibilityIdentifier: "WorkspaceConstructionPlane.pickOrigin"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanel")
    }

    @ViewBuilder
    private func selectionContextPanelContent(_ nodes: [SceneNode]) -> some View {
        let primaryNode = nodes.last
        workspaceValuePill("Objects", "\(nodes.count)")
        workspaceValuePill(
            "Target",
            selectedTargetSummary,
            accessibilityIdentifier: "WorkspaceSelection.target"
        )
        if let qualitySummary = selectionQualitySummary {
            workspaceValuePill(
                "Quality",
                qualitySummary.ratingTitle,
                accessibilityIdentifier: "WorkspaceQuality.rating"
            )
            workspaceValuePill(
                "Gate",
                qualitySummary.attentionGateTitle,
                accessibilityIdentifier: "WorkspaceQuality.gate"
            )
        }
        viewportPickingPills
        workspaceValuePill("Visible", "\(nodes.filter(\.isVisible).count)")
        workspaceValuePill("Locked", "\(nodes.filter(\.isLocked).count)")

        if regionOffsetCommandState.isActive, selectedRegionTargets.isEmpty == false {
            workspaceContextDivider
            regionOffsetContextPanelContent(selectedRegionTargets)
        }

        if edgeOffsetCommandState.isActive, selectedEdgeTargets.isEmpty == false {
            workspaceContextDivider
            edgeOffsetContextPanelContent(selectedEdgeTargets)
        }

        if let slotTarget = selectedSlotSourceCurveTarget {
            workspaceContextDivider
            slotProfileContextPanelContent(slotTarget)
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
        }

        if nodes.count == 1, let node = nodes.first {
            let nodeTranslation = WorkspaceTransformMatrix.translation(for: node)
            workspaceValuePill("X", formatted(nodeTranslation.x))
            workspaceValuePill("Y", formatted(nodeTranslation.y))
            workspaceValuePill("Z", formatted(nodeTranslation.z))
        }

        workspaceContextDivider

        workspaceIconButton(
            systemImage: primaryNode?.isVisible == false ? "eye.slash" : "eye",
            help: primaryNode?.isVisible == false ? "Show Selection" : "Hide Selection",
            accessibilityIdentifier: "WorkspaceSelection.visible"
        ) {
            for node in nodes {
                session.setSceneNodeVisibility(node.id, isVisible: !node.isVisible)
            }
        }

        workspaceIconButton(
            systemImage: primaryNode?.isLocked == true ? "lock" : "lock.open",
            help: primaryNode?.isLocked == true ? "Unlock Selection" : "Lock Selection",
            accessibilityIdentifier: "WorkspaceSelection.locked"
        ) {
            for node in nodes {
                session.setSceneNodeLock(node.id, isLocked: !node.isLocked)
            }
        }

        workspaceIconButton(
            systemImage: "arrow.counterclockwise",
            help: "Reset Transform",
            accessibilityIdentifier: "WorkspaceSelection.resetTransform"
        ) {
            for node in nodes {
                session.setSceneNodeTransform(node.id, localTransform: .identity)
            }
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
            distanceTitle: formatted(sketchSplineControlPointSlideDistanceMeters),
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
            distanceTitle: formatted(polySplineSurfaceVertexSlideDistanceMeters),
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

    @ViewBuilder
    private func surfaceControlPointSlideContextPanelContent(
        _ targets: [SelectionReference]
    ) -> some View {
        WorkspaceSurfaceControlPointSlideContextPanel(
            controlPointCount: targets.count,
            distanceTitle: formatted(polySplineSurfaceVertexSlideDistanceMeters),
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
            widthTitle: formatted(slotProfileWidthMeters),
            inputModeTitle: slotProfileCommandState.inputModeTitle,
            create: { createSlotFromOffsetCurve(target, width: slotProfileWidthMeters) }
        )
    }

    @ViewBuilder
    private func edgeOffsetContextPanelContent(_ targets: [SelectionTarget]) -> some View {
        let supportResolution = edgeOffsetSupportStateResolver.resolution(for: targets)
        WorkspaceEdgeOffsetContextPanel(
            isSupported: supportResolution.isSupported,
            distanceTitle: formatted(edgeOffsetDistanceMeters),
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
            distanceTitle: formatted(regionOffsetDistanceMeters),
            gapFillTitle: regionOffsetGapFillTitle(regionOffsetGapFill),
            inputModeTitle: regionOffsetCommandState.inputModeTitle,
            lockedDistanceTitle: regionOffsetCommandState.usesLockedDistance ? "On" : "Off",
            modeTitle: regionOffsetCommandState.usesCombinedRegions ? "Combined" : "Individual",
            offsetInward: {
                offsetSelectedRegions(
                    targets,
                    by: -regionOffsetDistanceMeters,
                    gapFill: regionOffsetGapFill,
                    isSymmetric: regionOffsetCommandState.usesLockedDistance,
                    combinesRegions: regionOffsetCommandState.usesCombinedRegions
                )
            },
            offsetOutward: {
                offsetSelectedRegions(
                    targets,
                    by: regionOffsetDistanceMeters,
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
        let isSelected = entry.selectionTarget().map { session.selection.containsTarget($0) } ?? false
        let identifierSuffix = String(describing: entry.id)
        return HStack(spacing: 6) {
            Button {
                activateConstructionPlane(entry.id)
            } label: {
                Image(systemName: entry.isActive ? "smallcircle.filled.circle" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
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
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.68))
                .help("Activate and Align View")
                .accessibilityIdentifier("WorkspacePlane.alignView.\(identifierSuffix)")

                Button {
                    updateConstructionPlaneFromView(entry)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.68))
                .help("Update Plane From View")
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
                .lineLimit(1)
                .onSubmit {
                    commitConstructionPlaneRename()
                }
                .accessibilityIdentifier("WorkspacePlane.renameField.\(identifierSuffix)")
            } else {
                Button {
                    selectConstructionPlane(entry)
                } label: {
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select Construction Plane")
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.72))
            .help(isRenaming ? "Commit Construction Plane Name" : "Rename Construction Plane")
            .accessibilityIdentifier("WorkspacePlane.rename.\(identifierSuffix)")

            if isRenaming {
                Button {
                    cancelConstructionPlaneRename()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.56))
                .help("Cancel Construction Plane Rename")
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

    @ViewBuilder
    private var workspaceSketchDimensionInputField: some View {
        if let focus = session.sketchInputState.dimensionInputFocus {
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
                    Text(sketchDimensionLengthUnitSymbol(session.sketchInputState.dimensionInputLengthMeters))
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
                    Text(sketchDimensionLengthUnitSymbol(session.sketchInputState.dimensionInputWidthMeters))
                        .foregroundStyle(.secondary)
                case .height:
                    TextField(
                        focus.statusTitle,
                        text: workspaceSketchHeightInputBinding
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    Text(sketchDimensionLengthUnitSymbol(session.sketchInputState.dimensionInputHeightMeters))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
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
                sketchDimensionLengthInputText(session.sketchInputState.dimensionInputLengthMeters)
            },
            set: { text in
                setSketchDimensionInputLength(
                    text,
                    currentMeters: session.sketchInputState.dimensionInputLengthMeters
                )
            }
        )
    }

    private var workspaceSketchAngleInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                guard let angleRadians = session.sketchInputState.dimensionInputAngleRadians else {
                    return 0.0
                }
                return angleRadians * 180.0 / Double.pi
            },
            set: { value in
                _ = session.setSketchDimensionInputAngle(value * Double.pi / 180.0)
            }
        )
    }

    private var workspaceSketchWidthInputBinding: Binding<String> {
        Binding<String>(
            get: {
                sketchDimensionLengthInputText(session.sketchInputState.dimensionInputWidthMeters)
            },
            set: { text in
                setSketchDimensionInputWidth(
                    text,
                    currentMeters: session.sketchInputState.dimensionInputWidthMeters
                )
            }
        )
    }

    private var workspaceSketchHeightInputBinding: Binding<String> {
        Binding<String>(
            get: {
                sketchDimensionLengthInputText(session.sketchInputState.dimensionInputHeightMeters)
            },
            set: { text in
                setSketchDimensionInputHeight(
                    text,
                    currentMeters: session.sketchInputState.dimensionInputHeightMeters
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
            .lineLimit(1)
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
            preferredUnit: session.document.displayUnit
        ).text
    }

    private func sketchDimensionLengthUnitSymbol(_ meters: Double?) -> String {
        sketchDimensionLengthDefaultUnit(meters).symbol
    }

    private func sketchDimensionLengthDefaultUnit(_ meters: Double?) -> LengthDisplayUnit {
        guard let meters else {
            return session.document.displayUnit
        }
        return workspaceLengthFieldPresentation(
            fromMeters: meters,
            preferredUnit: session.document.displayUnit
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
        _ = session.setSketchDimensionInputLength(meters)
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
        _ = session.setSketchDimensionInputWidth(meters)
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
        _ = session.setSketchDimensionInputHeight(meters)
    }

    private func sweepPreviewFeatureLabel(_ featureID: FeatureID?) -> String {
        featureID.map { shortID($0) } ?? "Missing"
    }

    private func sweepPreviewSectionLabel(_ section: SweepSectionReference?) -> String {
        guard let section else {
            return "Missing"
        }
        return sweepSectionSummary(section)
    }

    private var selectionQualitySummary: WorkspaceSelectionQualitySummary? {
        WorkspaceSelectionQualitySummary(scope: selectionScope)
    }

    private var activeViewportPickingBackend: ViewportPickingBackend {
        hoveredViewportPickingBackend ?? .projectedCPU
    }

    @ViewBuilder
    private var viewportPickingPills: some View {
        workspaceValuePill(
            "Pick",
            activeViewportPickingBackend.title,
            accessibilityIdentifier: "WorkspacePicking.backend"
        )
        if activeViewportPickingBackend.isExactIdentityBacked == false {
            workspaceValuePill(
                "Next",
                ViewportPickingBackend.identityBuffer.title,
                accessibilityIdentifier: "WorkspacePicking.nextBackend"
            )
        }
    }

    private var evaluationStatusSystemImage: String {
        switch session.evaluationStatus {
        case .notEvaluated:
            "circle.dashed"
        case .valid:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var evaluationStatusTint: Color {
        switch session.evaluationStatus {
        case .notEvaluated:
            .secondary
        case .valid:
            .green
        case .failed:
            .red
        }
    }

    private func activateTool(_ tool: ModelingTool) {
        if tool != .select {
            setHoveredSceneNode(nil)
            regionOffsetCommandState.deactivate()
            edgeOffsetCommandState.deactivate()
            slotProfileCommandState.deactivate()
            viewAlignedConstructionPlaneRequest = nil
        }
        let result = session.activateTool(tool)
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func toolHelp(for tool: ModelingTool) -> String {
        switch tool {
        case .select:
            "Select Components"
        case .sketch:
            "Create Rectangle Sketch"
        case .polygon:
            "Create Regular Polygon"
        case .arc:
            "Create Arc Curve"
        case .spline:
            "Create Spline Curve"
        case .solid:
            "Create Box"
        case .sweep:
            "Create Sweep from selected profile, selected guides, and clicked path"
        case .surface:
            "Create Circle Profile"
        case .mesh:
            "Inspect Evaluated Meshes"
        case .measure:
            "Show Measurement Summary"
        case .section:
            "Create Section Plane"
        }
    }

    private func canvasToolIdentifier(for tool: ModelingTool) -> String {
        "CanvasTool.\(tool.rawValue)"
    }

    private func handleViewportPick(_ target: ViewportCanvasTarget) {
        if let request = viewAlignedConstructionPlaneRequest {
            createViewAlignedConstructionPlane(from: target, request: request)
            return
        }

        if session.selectedTool == .select {
            applyViewportSelection(hit: target.hit, intent: target.selectionIntent)
            return
        }

        let resolvesObjectTargets = isObjectTargetingEnabled || target.modifierFlags.containsControl
        let effectiveHit = resolvesObjectTargets ? target.hit : nil
        let targetSceneNodeID: SceneNodeID?
        if let hit = effectiveHit {
            guard let sceneNodeID = selectionTargetResolver.sceneNodeID(for: hit) else {
                session.reportToolStatus(
                    "Viewport selection could not resolve a scene node.",
                    severity: .warning
                )
                isPreviewExpanded = true
                return
            }
            targetSceneNodeID = sceneNodeID
        } else {
            targetSceneNodeID = nil
        }

        let sketchPlane = effectiveSketchPlane(fallback: target.sketchPlane)
        guard let canvasInput = mappedCanvasInput(
            modelPoint: target.modelPoint,
            modelWorldPoint: target.modelWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        let snappedInput = snappedModelInput(canvasInput.point, modifierFlags: target.modifierFlags)
        let result = session.activateSelectedToolFromCanvas(
            targetSceneNodeID: targetSceneNodeID,
            modelPoint: snappedInput.point,
            modelWorldPoint: resolvedCanvasWorldPoint(
                for: snappedInput.point,
                topologyWorldPoint: snappedInput.topologyWorldPoint,
                fallbackWorldPoint: canvasInput.worldPoint,
                sketchPlane: sketchPlane
            ),
            sketchPlane: sketchPlane
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func handleWorkspaceKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let action = WorkspaceKeyboardRouter().action(
            for: keyPress,
            context: workspaceKeyboardContext
        ) else {
            return .ignored
        }
        return applyWorkspaceKeyboardAction(action)
    }

    private var workspaceKeyboardContext: WorkspaceKeyboardContext {
        WorkspaceKeyboardContext(
            isSelectToolActive: session.selectedTool == .select,
            isPolygonToolActive: session.selectedTool == .polygon,
            usesSketchAxisConstraint: usesSketchAxisConstraint,
            isDimensionCommandActive: dimensionCommandState.isActive,
            isSlotProfileCommandActive: slotProfileCommandState.isActive,
            isEdgeOffsetCommandActive: edgeOffsetCommandState.isActive,
            isRegionOffsetCommandActive: regionOffsetCommandState.isActive,
            isCurveControlVertexSlideActive: slideCommandState.isCurveControlVerticesActive,
            isSurfaceControlVertexSlideActive: slideCommandState.isSurfaceControlVerticesActive,
            selectionScope: selectionScope,
            hasCurveControlVertexSlideInput: selectedSplineControlPointSlideInput() != nil,
            hasSurfaceControlVertexSlideTargets: selectedPolySplineSurfaceVertexTargets.isEmpty == false
                || selectedSurfaceControlPointReferences.isEmpty == false,
            hasConstructionPlaneTargets: selectedConstructionPlaneTargets != nil
        )
    }

    private func applyWorkspaceKeyboardAction(
        _ action: WorkspaceKeyboardAction
    ) -> KeyPress.Result {
        switch action {
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
            _ = session.focusNextSketchDimensionInput(
                availableFocuses: activeSketchDimensionInputFocuses
            )
            return .handled
        case .activateOffsetCommand:
            if selectedEdgeTargets.isEmpty == false {
                activateEdgeOffsetCommand()
            } else if selectedRegionTargets.isEmpty == false {
                activateRegionOffsetCommand()
            } else if selectedSlotSourceCurveTarget != nil {
                activateSlotProfileCommand()
            } else {
                activateRegionOffsetCommand()
            }
            return .handled
        case .activateSlotWidthInput:
            slotProfileCommandState.activateWidthInput()
            return .handled
        case .activateEdgeOffsetDistanceInput:
            edgeOffsetCommandState.activateDistanceInput()
            return .handled
        case .activateRegionOffsetDistanceInput:
            regionOffsetCommandState.activateDistanceInput()
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
                session.reportToolStatus(
                    "Combined Offset Region requires multiple selected regions.",
                    severity: .warning
                )
                isPreviewExpanded = true
            }
            return .handled
        case .activateSlideCommand:
            activateSlideCommand()
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
            _ = session.adjustPolygonSideCount(by: offset)
            return .handled
        case .toggleSketchAxisConstraint(let axisConstraint):
            _ = session.toggleSketchAxisConstraint(axisConstraint)
            return .handled
        case .togglePolygonSizingMode:
            _ = session.togglePolygonSizingMode()
            return .handled
        case .togglePolygonInclinationMode:
            _ = session.togglePolygonInclinationMode()
            return .handled
        case .togglePolygonCutsFaces:
            _ = session.togglePolygonCutsFaces()
            return .handled
        }
    }

    private func activateDimensionCommand() {
        let objectTargets = selectedObjectDimensionTargets
        let sketchTargets = selectedSketchDimensionTargets
        let targets = objectTargets + sketchTargets
        guard !targets.isEmpty else {
            dimensionCommandState.deactivate()
            session.reportToolStatus(
                "Dimension requires a selected object, face, edge, or sketch curve target.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        do {
            let entries = try dimensionEntries(
                objectTargets: objectTargets,
                sketchTargets: sketchTargets
            )
            guard !entries.isEmpty else {
                dimensionCommandState.deactivate()
                session.reportToolStatus(
                    "Dimension found no editable values for the selected target.",
                    severity: .warning
                )
                isPreviewExpanded = true
                return
            }
            dimensionCommandState.activate(entries: entries)
        } catch let error as EditorError {
            dimensionCommandState.deactivate()
            session.reportToolStatus(error.message, severity: .warning)
            isPreviewExpanded = true
        } catch {
            dimensionCommandState.deactivate()
            session.reportToolStatus(String(describing: error), severity: .warning)
            isPreviewExpanded = true
        }
    }

    private func dimensionEntries(
        objectTargets: [SelectionTarget],
        sketchTargets: [SelectionTarget]
    ) throws -> [DimensionCommandEntry] {
        var entries: [DimensionCommandEntry] = []
        if !objectTargets.isEmpty {
            let summary = try ObjectDimensionSummaryService().summarize(
                document: session.document,
                targets: objectTargets,
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
                return componentID.generatedTopologyPersistentName != nil
            }
            if !sketchEntityTargets.isEmpty {
                let summary = try SketchDimensionSummaryService().summarize(
                    document: session.document,
                    targets: sketchEntityTargets,
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
                document: session.document,
                targets: [target],
                objectRegistry: objectRegistry
            )
            return summary.entries.map(DimensionCommandEntry.init(sketch:))
        } catch let sketchError as EditorError {
            do {
                let summary = try ObjectDimensionSummaryService().summarize(
                    document: session.document,
                    targets: [target],
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

    private func commitDimensionCommand() {
        guard let entry = dimensionCommandState.activeEntry,
              let value = dimensionCommandState.currentValue,
              value.isFinite else {
            session.reportToolStatus(
                "Dimension value must be finite.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        let result: CommandExecutionResult?
        switch entry.source {
        case .object(let kind):
            guard value > 0.0 else {
                session.reportToolStatus(
                    "Dimension value must be a positive length.",
                    severity: .warning
                )
                isPreviewExpanded = true
                return
            }
            result = session.setObjectDimension(
                target: entry.target,
                kind: kind,
                value: .length(value, .meter)
            )
        case .sketch(let kind):
            let expression: CADExpression
            switch entry.valueKind {
            case .length:
                guard value > 0.0 else {
                    session.reportToolStatus(
                        "Dimension value must be a positive length.",
                        severity: .warning
                    )
                    isPreviewExpanded = true
                    return
                }
                expression = .length(value, .meter)
            case .angle:
                expression = .angle(value, .radian)
            }
            result = session.setSketchEntityDimension(
                target: entry.target,
                kind: kind,
                value: expression
            )
        }
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
        dimensionCommandState.deactivate()
    }

    private func createConstructionPlaneFromSelectedTargets(alignsView: Bool) -> KeyPress.Result {
        guard let targets = selectedConstructionPlaneTargets else {
            return .ignored
        }
        let result = session.createConstructionPlaneFromTargets(
            targets,
            viewNormal: viewportProjectionBasis.viewNormal
        )
        workspacePlaneMode = .adaptive
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        } else if alignsView {
            if let activeConstructionPlane = session.activeConstructionPlane {
                alignViewport(
                    to: activeConstructionPlane.plane,
                    name: activeConstructionPlane.name
                )
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
            session.reportToolStatus(
                "Slide Surface CV requires generated PolySpline surface CV selections.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }
        if case .success(let entity?) = selectedSketchEntityResult {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            session.reportToolStatus(
                entity.entityKind == "spline"
                    ? "Slide requires selected spline control vertices."
                    : "Slide Curve CV requires a spline curve target.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }
        selectionScope = .sketchEntity
        session.reportToolStatus(
            "Slide requires selected curve CVs or surface CVs.",
            severity: .warning
        )
        isPreviewExpanded = true
    }

    private func activateSlideCurveControlVerticesCommand() {
        selectionScope = .sketchEntity
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.activateCurveControlVertices()
        session.reportToolStatus("Slide Curve CV active.")
    }

    private func activateSlideSurfaceControlVerticesCommand() {
        selectionScope = .vertex
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slotProfileCommandState.deactivate()
        slideCommandState.activateSurfaceControlVertices()
        session.reportToolStatus("Slide Surface CV active.")
    }

    @discardableResult
    private func activateConstructionPlane(_ id: ConstructionPlaneSourceID) -> Bool {
        if session.document.productMetadata.activeConstructionPlaneID == id {
            return true
        }
        let result = session.setActiveConstructionPlane(id: id)
        workspacePlaneMode = .adaptive
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
            return false
        } else if let activeName = session.activeConstructionPlane?.name {
            session.reportToolStatus("Active construction plane set to \(activeName).")
        }
        return true
    }

    private func activateAndAlignConstructionPlane(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        guard activateConstructionPlane(entry.id) else {
            return
        }
        alignViewport(to: entry.plane, name: entry.name)
    }

    private func updateConstructionPlaneFromView(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        guard let viewNormal = viewportProjectionBasis.viewNormal else {
            session.reportToolStatus(
                "Construction plane update requires a resolved viewport normal.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        do {
            let plane = try WorkspaceConstructionPlaneEditBuilder().planePreservingOrigin(
                from: entry.plane,
                viewNormal: viewNormal
            )
            let result = session.setConstructionPlane(id: entry.id, plane: plane)
            if result?.diagnostics.isEmpty == false || result == nil {
                isPreviewExpanded = true
            } else {
                session.reportToolStatus("Updated construction plane \(entry.name) from current view.")
            }
        } catch let error as EditorError {
            session.reportToolStatus(error.message, severity: .warning)
            isPreviewExpanded = true
        } catch {
            session.reportToolStatus(
                "Construction plane update failed.",
                severity: .warning
            )
            isPreviewExpanded = true
        }
    }

    private func selectConstructionPlane(
        _ entry: ConstructionPlaneSummaryResult.Entry
    ) {
        guard let target = entry.selectionTarget() else {
            session.reportToolStatus(
                "Construction plane selection target is unavailable.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }
        guard session.selectTarget(target) else {
            isPreviewExpanded = true
            return
        }
        session.reportToolStatus("Selected construction plane \(entry.name).")
    }

    private func alignViewport(
        to plane: SketchPlane,
        name: String
    ) {
        do {
            viewportProjectionRequest = ViewportProjectionRequest(
                basis: try ViewportProjectionBasis.aligned(to: plane)
            )
            session.reportToolStatus("View aligned to \(name).")
        } catch {
            session.reportToolStatus(
                "Construction plane view alignment failed.",
                severity: .warning
            )
            isPreviewExpanded = true
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
            session.reportToolStatus(
                "Construction plane names must not be empty.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        let result = session.renameConstructionPlane(id: id, name: trimmedName)
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        } else {
            cancelConstructionPlaneRename()
            session.reportToolStatus("Construction plane renamed to \(trimmedName).")
        }
    }

    private func createViewAlignedConstructionPlaneFromKeyboard(pickOrigin: Bool) -> KeyPress.Result {
        guard let viewNormal = viewportProjectionBasis.viewNormal else {
            session.reportToolStatus(
                "View-aligned construction plane requires a resolved viewport normal.",
                severity: .warning
            )
            isPreviewExpanded = true
            return .handled
        }

        if pickOrigin {
            viewAlignedConstructionPlaneRequest = ViewAlignedConstructionPlaneRequest(
                viewNormal: viewNormal
            )
            session.reportToolStatus("Click a point to set the view-aligned construction plane origin.")
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
            sketchPlane: sketchPlane
        ) else {
            viewAlignedConstructionPlaneRequest = nil
            return
        }
        let snappedInput = snappedModelInput(canvasInput.point, modifierFlags: target.modifierFlags)
        guard let origin = resolvedSketchPlaneWorldPoint(
            for: snappedInput.point,
            topologyWorldPoint: snappedInput.topologyWorldPoint,
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
        let result = session.createViewAlignedConstructionPlane(
            origin: origin,
            viewNormal: viewNormal
        )
        workspacePlaneMode = .adaptive
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        } else {
            session.reportToolStatus("View-aligned construction plane created.")
        }
    }

    private func activateRegionOffsetCommand() {
        guard selectedRegionTargets.isEmpty == false else {
            if selectionScope != .region {
                selectionScope = .region
            }
            session.reportToolStatus(
                "Offset Region requires a selected sketch region.",
                severity: .warning
            )
            isPreviewExpanded = true
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
            session.reportToolStatus(
                "Offset Edge requires a selected edge.",
                severity: .warning
            )
            isPreviewExpanded = true
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
            session.reportToolStatus(message, severity: .warning)
            isPreviewExpanded = true
        }
    }

    private func activateSlotProfileCommand() {
        guard selectedSlotSourceCurveTarget != nil else {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            session.reportToolStatus(
                "Slot requires a selected open source curve.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }
        selectionScope = .sketchEntity
        regionOffsetCommandState.deactivate()
        edgeOffsetCommandState.deactivate()
        slideCommandState.deactivate()
        slotProfileCommandState.activateWidthInput()
    }

    private func handleViewportShiftScroll(_ direction: ViewportScrollDirection) -> Bool {
        guard session.selectedTool == .polygon else {
            return false
        }
        switch direction {
        case .up:
            _ = session.adjustPolygonSideCount(by: 1)
        case .down:
            _ = session.adjustPolygonSideCount(by: -1)
        }
        return true
    }

    private func handleViewportSelectionDrag(_ target: ViewportSelectionDragTarget) {
        selectionDragPreviewTargets = []
        let targets = selectionTargets(for: target.hits)
        applyViewportSelection(targets: targets, intent: target.selectionIntent)
    }

    private func handleViewportSelectionDragPreview(_ target: ViewportSelectionDragTarget) {
        let targets = selectionTargets(for: target.hits)
        guard selectionDragPreviewTargets != targets else {
            return
        }
        selectionDragPreviewTargets = targets
    }

    private func handleViewportVertexDrag(_ target: ViewportVertexDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return
        }
        let result = session.moveBodyVertex(
            target: target.target,
            deltaX: .length(target.deltaX, .meter),
            deltaY: .length(target.deltaY, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPolySplineSurfaceVertexDrag(_ target: ViewportPolySplineSurfaceVertexDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return
        }
        let result = session.movePolySplineSurfaceVertex(
            target: target.target,
            deltaX: .length(target.deltaX, .meter),
            deltaY: .length(target.deltaY, .meter),
            deltaZ: .length(target.deltaZ, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSurfaceControlPointDrag(_ target: ViewportSurfaceControlPointDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return
        }
        let result = session.moveSurfaceControlPoint(
            target: target.target,
            deltaX: .length(target.deltaX, .meter),
            deltaY: .length(target.deltaY, .meter),
            deltaZ: .length(target.deltaZ, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSurfaceTrimEndpointDrag(_ target: ViewportSurfaceTrimEndpointDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return
        }
        let result = session.moveSurfaceTrimEndpoint(
            target: target.target,
            endpoint: target.endpoint,
            u: .scalar(target.u),
            v: .scalar(target.v)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSurfaceTrimControlPointDrag(_ target: ViewportSurfaceTrimControlPointDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .vertex else {
            return
        }
        let result = session.moveSurfaceTrimControlPoint(
            target: target.target,
            controlPointIndex: target.controlPointIndex,
            u: .scalar(target.u),
            v: .scalar(target.v)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPolySplineSurfaceVertexSlideDrag(
        _ target: ViewportPolySplineSurfaceVertexSlideDragTarget
    ) {
        guard session.selectedTool == .select,
              selectionScope == .vertex,
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
        guard session.selectedTool == .select,
              selectionScope == .vertex,
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
        guard session.selectedTool == .select,
              selectionScope == .vertex,
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

    private func handleViewportFaceDrag(_ target: ViewportFaceDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .face else {
            return
        }
        let result = session.offsetBodyFace(
            target: target.target,
            distance: .length(target.distance, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportEdgeChamferDrag(_ target: ViewportEdgeChamferDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .edge else {
            return
        }
        let result = session.chamferBodyEdges(
            targets: [target.target],
            distance: .length(target.distance, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportEdgeFilletDrag(_ target: ViewportEdgeFilletDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .edge else {
            return
        }
        let result = session.filletBodyEdges(
            targets: [target.target],
            radius: .length(target.radius, .meter),
            segmentCount: 8
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportRegionOffsetDrag(_ target: ViewportRegionOffsetDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .region else {
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
        guard session.selectedTool == .select,
              selectionScope == .edge,
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
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity,
              slotProfileCommandState.isActive else {
            return
        }
        slotProfileWidthMeters = max(target.width, 1.0e-9)
        createSlotFromOffsetCurve(target.target, width: slotProfileWidthMeters)
    }

    private func handleViewportSketchVertexOffsetDrag(_ target: ViewportSketchVertexOffsetDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return
        }
        sketchVertexOffsetDistanceMeters = max(target.distance, 1.0e-9)
        let result = session.offsetSketchVertex(
            target: target.target,
            handle: target.handle,
            distance: .length(sketchVertexOffsetDistanceMeters, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPatternArrayLinearAxisDrag(
        _ target: ViewportPatternArrayLinearAxisDragTarget
    ) {
        guard session.selectedTool == .select,
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
            let result = PatternArrayEditingService(
                session: session,
                sourceID: target.sourceID
            ).setRadialAxisDistance(target.distance)
            if result?.diagnostics.isEmpty == false {
                isPreviewExpanded = true
            }
            return
        }
        let result = PatternArrayEditingService(
            session: session,
            sourceID: target.sourceID
        ).setRectangularAxisDistance(
            slot: slot,
            meters: target.distance
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportIndependentCopyExtrudeDistanceDrag(
        _ target: ViewportIndependentCopyExtrudeDistanceDragTarget
    ) {
        guard session.selectedTool == .select,
              target.distance.isFinite,
              target.distance > 0.0 else {
            return
        }
        session.setExtrudeDistance(
            featureID: target.featureID,
            distance: .length(target.distance, .meter)
        )
    }

    private func handleViewportIndependentCopyBodyDimensionDrag(
        _ target: ViewportIndependentCopyBodyDimensionDragTarget
    ) {
        guard session.selectedTool == .select,
              target.value.isFinite,
              target.value > 0.0,
              let bodySceneNodeID = sceneNodeID(forBodyFeatureID: target.featureID) else {
            return
        }
        let summary: ObjectDimensionSummaryResult
        do {
            summary = try ObjectDimensionSummaryService().summarize(
                document: session.document,
                targets: [SelectionTarget(sceneNodeID: bodySceneNodeID)],
                objectRegistry: objectRegistry
            )
        } catch {
            isPreviewExpanded = true
            return
        }
        func currentDimension(_ kind: ObjectDimensionKind) -> Double? {
            summary.entries.first { $0.kind == kind }?.resolvedMeters
        }
        switch target.kind {
        case .sizeX, .sizeZ:
            guard let sizeX = currentDimension(.sizeX),
                  let sizeY = currentDimension(.sizeY),
                  let sizeZ = currentDimension(.sizeZ) else {
                return
            }
            session.setCubeDimensions(
                featureID: target.featureID,
                sizeX: .length(target.kind == .sizeX ? target.value : sizeX, .meter),
                sizeY: .length(sizeY, .meter),
                sizeZ: .length(target.kind == .sizeZ ? target.value : sizeZ, .meter)
            )
        case .radius:
            guard let sizeY = currentDimension(.sizeY) else {
                return
            }
            session.setCylinderDimensions(
                featureID: target.featureID,
                radius: .length(target.value, .meter),
                sizeY: .length(sizeY, .meter)
            )
        }
    }

    private func sceneNodeID(forBodyFeatureID featureID: FeatureID) -> SceneNodeID? {
        session.document.productMetadata.sceneNodes.first { _, node in
            node.reference == .body(featureID)
        }?.key
    }

    private func handleViewportPatternArrayRadialAngleDrag(
        _ target: ViewportPatternArrayRadialAngleDragTarget
    ) {
        guard session.selectedTool == .select,
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let result = PatternArrayEditingService(
            session: session,
            sourceID: target.sourceID
        ).setRadialAngle(degrees: target.angleRadians * 180.0 / .pi)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPatternArrayCopyCountDrag(
        _ target: ViewportPatternArrayCopyCountDragTarget
    ) {
        guard session.selectedTool == .select,
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let service = PatternArrayEditingService(
            session: session,
            sourceID: target.sourceID
        )
        let result: CommandExecutionResult?
        switch target.slot {
        case .rectangularFirst:
            result = service.setRectangularAxisCopyCount(slot: .first, copyCount: target.copyCount)
        case .rectangularSecond:
            result = service.setRectangularAxisCopyCount(slot: .second, copyCount: target.copyCount)
        case .radialAngular:
            result = service.setRadialAngularCopyCount(target.copyCount)
        case .radialAxis:
            result = service.setRadialAxisCopyCount(target.copyCount)
        case .curve:
            result = service.setCurveCopyCount(target.copyCount)
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPatternArrayOutputModeChange(_ target: ViewportPatternArrayOutputModeTarget) {
        guard session.selectedTool == .select,
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let result = PatternArrayEditingService(
            session: session,
            sourceID: target.sourceID
        ).setOutputMode(target.outputMode)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportPatternArrayCurvePathPointDrag(
        _ target: ViewportPatternArrayCurvePathPointDragTarget
    ) {
        guard session.selectedTool == .select,
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        let result = PatternArrayEditingService(
            session: session,
            sourceID: target.sourceID
        ).setCurvePathPoint(
            index: target.pointIndex,
            point: target.point
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSketchCurveHandleDrag(_ target: ViewportSketchCurveHandleDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
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
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return
        }
        setSelectedSketchEntityDimension(
            target.target,
            kind: target.kind,
            value: target.value
        )
    }

    private func handleViewportSketchPointHandleDrag(_ target: ViewportSketchPointHandleDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
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
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
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
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
            return
        }
        let result: CommandExecutionResult?
        switch target.role {
        case .first:
            result = session.setBridgeCurveParameters(
                sourceID: target.sourceID,
                firstEndpoint: target.endpoint
            )
        case .second:
            result = session.setBridgeCurveParameters(
                sourceID: target.sourceID,
                secondEndpoint: target.endpoint
            )
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSplineControlPointSlideDrag(_ target: ViewportSplineControlPointSlideDragTarget) {
        guard session.selectedTool == .select,
              selectionScope == .sketchEntity else {
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
            sketchPlane: sketchPlane
        ) else {
            return
        }
        guard let endCanvasInput = mappedCanvasInput(
            modelPoint: drag.end,
            modelWorldPoint: drag.endWorldPoint,
            sketchPlane: sketchPlane
        ) else {
            return
        }
        let startInput = snappedModelInput(startCanvasInput.point, modifierFlags: drag.modifierFlags)
        let startPoint = startInput.point
        let constrainedEndPoint = activeCanvasDragAxisConstraint?.constrainedCanvasPoint(
            endCanvasInput.point,
            from: startPoint,
            on: sketchPlane
        ) ?? endCanvasInput.point
        let endInput = snappedModelInput(
            constrainedEndPoint,
            referencePoint: startPoint,
            modifierFlags: drag.modifierFlags
        )
        let snappedEndPoint = endInput.point
        let endPoint = activeCanvasDragAxisConstraint?.constrainedCanvasPoint(
            snappedEndPoint,
            from: startPoint,
            on: sketchPlane
        ) ?? snappedEndPoint
        let startWorldPoint = resolvedCanvasWorldPoint(
            for: startPoint,
            topologyWorldPoint: startInput.topologyWorldPoint,
            fallbackWorldPoint: startCanvasInput.worldPoint,
            sketchPlane: sketchPlane
        )
        let endWorldPoint = activeCanvasDragAxisConstraint == nil
            ? resolvedCanvasWorldPoint(
                for: endPoint,
                topologyWorldPoint: endInput.topologyWorldPoint,
                fallbackWorldPoint: endCanvasInput.worldPoint,
                sketchPlane: sketchPlane
            )
            : resolvedConstrainedCanvasWorldPoint(
                for: endPoint,
                sketchPlane: sketchPlane
            )
        let result = session.activateSelectedToolFromCanvasDrag(
            startModelPoint: startPoint,
            endModelPoint: endPoint,
            sketchPlane: sketchPlane,
            startWorldPoint: startWorldPoint,
            endWorldPoint: endWorldPoint
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func mappedCanvasInput(
        modelPoint: Point2D,
        modelWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> WorkspaceCanvasPlaneInputMapper.Result? {
        do {
            return try WorkspaceCanvasPlaneInputMapper(
                projectionBasis: viewportProjectionBasis
            ).map(
                modelPoint: modelPoint,
                modelWorldPoint: modelWorldPoint,
                sketchPlane: sketchPlane
            )
        } catch WorkspaceCanvasPlaneInputMapper.Failure.unresolvedViewNormal {
            session.reportToolStatus(
                "Canvas input requires a resolved viewport normal for the active construction plane.",
                severity: .warning
            )
        } catch WorkspaceCanvasPlaneInputMapper.Failure.viewRayParallelToPlane {
            session.reportToolStatus(
                "Canvas input is parallel to the active construction plane from this view.",
                severity: .warning
            )
        } catch {
            session.reportToolStatus(
                "Canvas input could not be projected onto the active construction plane.",
                severity: .warning
            )
        }
        isPreviewExpanded = true
        return nil
    }

    private func resolvedCanvasWorldPoint(
        for point: Point2D,
        topologyWorldPoint: Point3D?,
        fallbackWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        if let topologyWorldPoint {
            return topologyWorldPoint
        }
        guard case .plane = sketchPlane else {
            return fallbackWorldPoint
        }
        return resolvedSketchPlaneWorldPoint(
            for: point,
            topologyWorldPoint: nil,
            sketchPlane: sketchPlane
        )
    }

    private func resolvedConstrainedCanvasWorldPoint(
        for point: Point2D,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        guard case .plane = sketchPlane else {
            return nil
        }
        return resolvedSketchPlaneWorldPoint(
            for: point,
            topologyWorldPoint: nil,
            sketchPlane: sketchPlane
        )
    }

    private func resolvedSketchPlaneWorldPoint(
        for point: Point2D,
        topologyWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        if let topologyWorldPoint {
            return topologyWorldPoint
        }
        do {
            return try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: point)
        } catch {
            session.reportToolStatus(
                "Canvas input world point could not be resolved on the active construction plane.",
                severity: .warning
            )
            isPreviewExpanded = true
            return nil
        }
    }

    private func snappedModelInput(
        _ point: Point2D,
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> SnappedModelInput {
        guard isGridSnapEnabled
            || isObjectTargetingEnabled
            || modifierFlags.containsControl
            || !session.sketchInputState.referenceLineAnchors.isEmpty else {
            return SnappedModelInput(point: point)
        }
        do {
            let result = try SnapResolver().resolve(
                point: point,
                in: session.document,
                options: snapResolutionOptions(
                    referencePoint: referencePoint,
                    modifierFlags: modifierFlags
                )
            )
            return SnappedModelInput(
                point: result.resolvedPoint,
                topologyWorldPoint: result.selectedTopologyWorldPoint
            )
        } catch {
            return SnappedModelInput(point: gridSnappedModelPoint(point))
        }
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
            referenceLineAnchors: session.sketchInputState.referenceLineAnchors
        ).options(
            referencePoint: referencePoint,
            modifierFlags: modifierFlags
        )
    }

    private func activeSnapResolutionOptions() -> SnapResolutionOptions? {
        return snapResolutionOptions()
    }

    private func gridSnappedModelPoint(_ point: Point2D) -> Point2D {
        guard isGridSnapEnabled else {
            return point
        }
        let interval = max(session.document.ruler.minorTickMeters, 1.0e-9)
        return Point2D(
            x: (point.x / interval).rounded() * interval,
            y: (point.y / interval).rounded() * interval
        )
    }

    private func effectiveSketchPlane(fallback: SketchPlane) -> SketchPlane {
        workspacePlaneMode.sketchPlane ?? session.activeSketchPlane(fallback: fallback)
    }

    private func handleViewportHover(_ hit: ViewportHit?) {
        guard let hit else {
            patternArrayCurvePathPreviewCandidate = nil
            hoveredViewportPickingBackend = nil
            setHoveredTarget(nil)
            return
        }

        hoveredViewportPickingBackend = hit.pickingBackend
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
            document: session.document
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
        selectionDragPreviewTargets = []
        if applyPatternArrayCurvePathPick(targets: targets) {
            return
        }
        switch intent {
        case .replace:
            guard !targets.isEmpty else {
                session.clearSelection()
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability()
                return
            }
            _ = session.selectTargets(targets)
        case .toggle:
            guard !targets.isEmpty else {
                return
            }
            var nextTargets = session.selection.selectedTargets
            for target in targets {
                if let index = nextTargets.firstIndex(of: target) {
                    nextTargets.remove(at: index)
                } else {
                    nextTargets.append(target)
                }
            }
            _ = session.selectTargets(nextTargets)
        }
        dimensionCommandState.deactivate()
        syncOffsetCommandAvailability()
    }

    private func applyViewportSelection(
        references: [SelectionReference],
        intent: ViewportSelectionIntent
    ) {
        selectionDragPreviewTargets = []
        patternArrayCurvePathPreviewCandidate = nil
        switch intent {
        case .replace:
            guard !references.isEmpty else {
                session.clearSelection()
                dimensionCommandState.deactivate()
                syncOffsetCommandAvailability()
                return
            }
            _ = session.selectReferences(references)
        case .toggle:
            guard !references.isEmpty else {
                return
            }
            var nextReferences = session.selection.selectedReferences
            for reference in references {
                if let index = nextReferences.firstIndex(of: reference) {
                    nextReferences.remove(at: index)
                } else {
                    nextReferences.append(reference)
                }
            }
            _ = session.selectReferences(nextReferences)
        }
        dimensionCommandState.deactivate()
        syncOffsetCommandAvailability()
    }

    private func applyPatternArrayCurvePathPick(targets: [SelectionTarget]) -> Bool {
        guard let sourceID = patternArrayCurvePathPickState.sourceID else {
            return false
        }
        let outcome = PatternArrayCurvePathPickService(
            session: session,
            sourceID: sourceID
        ).apply(targets: targets)
        switch outcome {
        case .waitingForCurve:
            break
        case .applied, .failed:
            patternArrayCurvePathPreviewCandidate = nil
            patternArrayCurvePathPickState.cancel()
        }
        dimensionCommandState.deactivate()
        syncOffsetCommandAvailability()
        return true
    }

    private func syncOffsetCommandAvailability() {
        if selectionScope != .region || selectedRegionTargets.isEmpty {
            regionOffsetCommandState.deactivate()
        }
        if selectionScope != .edge || selectedEdgeTargets.isEmpty {
            edgeOffsetCommandState.deactivate()
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
            guard session.selection.hoveredTarget != nil ||
                session.selection.hoveredReference != nil else {
                return
            }
        } else if session.selection.hoveredSceneNodeID == id {
            return
        }
        _ = session.hoverSceneNode(id)
    }

    private func setHoveredTarget(_ target: SelectionTarget?) {
        if target == nil {
            guard session.selection.hoveredTarget != nil ||
                session.selection.hoveredReference != nil else {
                return
            }
        } else if session.selection.hoveredTarget == target {
            return
        }
        _ = session.hoverTarget(target)
    }

    private func setHoveredReference(_ reference: SelectionReference?) {
        if reference == nil {
            guard session.selection.hoveredTarget != nil ||
                session.selection.hoveredReference != nil else {
                return
            }
        } else if session.selection.hoveredReference == reference {
            return
        }
        _ = session.hoverReference(reference)
    }

    private func setHoveredSceneNode(_ id: SceneNodeID, isHovered: Bool) {
        if isHovered {
            setHoveredSceneNode(id)
        } else if session.selection.hoveredSceneNodeID == id {
            setHoveredSceneNode(nil)
        }
    }

    @ViewBuilder
    private func componentBrowserRow(_ id: SceneNodeID, depth: Int) -> some View {
        if let node = session.document.productMetadata.sceneNodes[id] {
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: CGFloat(depth) * 12)

                Image(systemName: sceneNodeSystemImage(for: node.reference))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .lineLimit(1)

                    Text(sceneNodeKindTitle(for: node.reference))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                sceneNodeControlButton(
                    systemImage: node.isVisible ? "eye" : "eye.slash",
                    help: node.isVisible ? "Hide Component" : "Show Component"
                ) {
                    toggleSceneNodeVisibility(id)
                }

                sceneNodeControlButton(
                    systemImage: node.isLocked ? "lock" : "lock.open",
                    help: node.isLocked ? "Unlock Component" : "Lock Component"
                ) {
                    toggleSceneNodeLock(id)
                }
            }
            .onHover { isHovered in
                setHoveredSceneNode(id, isHovered: isHovered)
            }
        }
    }

    @ViewBuilder
    private func componentDefinitionRow(_ id: ComponentDefinitionID) -> some View {
        if let definition = session.document.productMetadata.componentDefinitions[id] {
            Label {
                HStack {
                    Text(definition.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(definition.rootSceneNodeIDs.count) roots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "square.stack.3d.down.right")
            }
        }
    }

    @ViewBuilder
    private func componentInstanceRow(_ id: ComponentInstanceID) -> some View {
        if let instance = session.document.productMetadata.componentInstances[id] {
            HStack(spacing: 6) {
                Image(systemName: "cube.transparent")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(instance.name)
                        .lineLimit(1)

                    Text(componentDefinitionName(for: instance.definitionID))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                sceneNodeControlButton(
                    systemImage: instance.isVisible ? "eye" : "eye.slash",
                    help: instance.isVisible ? "Hide Component Instance" : "Show Component Instance"
                ) {
                    toggleComponentInstanceVisibility(id)
                }

                sceneNodeControlButton(
                    systemImage: instance.isLocked ? "lock" : "lock.open",
                    help: instance.isLocked ? "Unlock Component Instance" : "Lock Component Instance"
                ) {
                    toggleComponentInstanceLock(id)
                }
            }
        }
    }

    private func browserAssetRow(_ row: SidebarAssetRow) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: row.systemImage)
        }
    }

    private func sceneNodeControlButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func sceneNodeSystemImage(for reference: SceneNodeReference?) -> String {
        guard let reference else {
            return "square.stack.3d.down.right"
        }
        switch reference.kind {
        case .feature:
            return "point.3.filled.connected.trianglepath.dotted"
        case .body:
            return "cube"
        case .sketch:
            return "pencil.and.outline"
        case .componentInstance:
            return "cube.transparent"
        case .construction:
            return "axis.3d"
        }
    }

    private func toggleSceneNodeVisibility(_ id: SceneNodeID) {
        guard let node = session.document.productMetadata.sceneNodes[id] else {
            return
        }
        session.setSceneNodeVisibility(id, isVisible: !node.isVisible)
    }

    private func toggleSceneNodeLock(_ id: SceneNodeID) {
        guard let node = session.document.productMetadata.sceneNodes[id] else {
            return
        }
        session.setSceneNodeLock(id, isLocked: !node.isLocked)
    }

    private func toggleComponentInstanceVisibility(_ id: ComponentInstanceID) {
        guard let instance = session.document.productMetadata.componentInstances[id] else {
            return
        }
        session.setComponentInstanceVisibility(id, isVisible: !instance.isVisible)
    }

    private func toggleComponentInstanceLock(_ id: ComponentInstanceID) {
        guard let instance = session.document.productMetadata.componentInstances[id] else {
            return
        }
        session.setComponentInstanceLock(id, isLocked: !instance.isLocked)
    }

    private var selectedSceneNodes: [SceneNode] {
        session.selection.selectedSceneNodeIDs.compactMap { id in
            session.document.productMetadata.sceneNodes[id]
        }
    }

    private var sketchEntityInspectorStateBuilder: WorkspaceSketchEntityInspectorStateBuilder {
        WorkspaceSketchEntityInspectorStateBuilder(
            document: session.document,
            selection: session.selection,
            objectRegistry: objectRegistry
        )
    }

    private var surfaceInspectorStateBuilder: WorkspaceSurfaceInspectorStateBuilder {
        WorkspaceSurfaceInspectorStateBuilder(
            document: session.document,
            selection: session.selection,
            currentEvaluation: session.currentEvaluation,
            documentGeneration: session.generation,
            objectRegistry: objectRegistry,
            surfaceAnalysisOptions: surfaceAnalysisOptions.analysisOptions
        )
    }

    private var sectionAnalysisStateBuilder: WorkspaceSectionAnalysisStateBuilder {
        WorkspaceSectionAnalysisStateBuilder(
            document: session.document,
            currentEvaluation: session.currentEvaluation,
            documentGeneration: session.generation,
            objectRegistry: objectRegistry
        )
    }

    private var topologyEditInspectorStateBuilder: WorkspaceTopologyEditInspectorStateBuilder {
        WorkspaceTopologyEditInspectorStateBuilder(
            selection: session.selection,
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
            document: session.document,
            selection: session.selection
        )
    }

    private var selectionTargetClassification: WorkspaceSelectionTargetClassification {
        WorkspaceSelectionTargetClassification(selection: session.selection)
    }

    private var selectionTargetResolver: WorkspaceSelectionTargetResolver {
        WorkspaceSelectionTargetResolver(
            document: session.document,
            sceneBrowserRows: sceneBrowserRows,
            selectionScope: selectionScope,
            objectRegistry: objectRegistry
        )
    }

    private var projectionTargetResolver: WorkspaceProjectionTargetResolver {
        WorkspaceProjectionTargetResolver(
            document: session.document,
            selection: session.selection,
            objectRegistry: objectRegistry
        )
    }

    private var splineControlPointSelectionResolver: WorkspaceSplineControlPointSelectionResolver {
        WorkspaceSplineControlPointSelectionResolver(selection: session.selection)
    }

    private var edgeOffsetSupportStateResolver: WorkspaceEdgeOffsetSupportStateResolver {
        WorkspaceEdgeOffsetSupportStateResolver(
            document: session.document,
            selection: session.selection,
            objectRegistry: objectRegistry
        )
    }

    private var sketchCommandTargetResolver: WorkspaceSketchCommandTargetResolver {
        WorkspaceSketchCommandTargetResolver()
    }

    private func patternArrayInspectorState(for nodes: [SceneNode]) -> PatternArrayInspectorState? {
        PatternArrayInspectorState(
            selectedNodes: nodes,
            sceneNodes: session.document.productMetadata.sceneNodes,
            patternArrays: session.document.productMetadata.patternArrays,
            summaryResult: patternArraySummaryCache.result(
                document: session.document,
                generation: session.generation,
                dirty: session.isDirty
            )
        )
    }

    private var selectedTargetCount: Int {
        max(session.selection.selectedTargets.count, session.selection.selectedSceneNodeIDs.count)
    }

    private var selectedTargetSummary: String {
        let targets = session.selection.selectedTargets
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

    private func selectedSurfaceAnalysisSummaryResult(
        for nodes: [SceneNode]
    ) -> Result<SurfaceAnalysisResult?, Error> {
        surfaceInspectorStateBuilder.analysisSummaryResult(for: nodes)
    }

    private func selectedSurfaceAnalysisResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceAnalysis?, Error> {
        surfaceInspectorStateBuilder.analysisResult(for: nodes)
    }

    private func selectedSurfaceContinuitySummaryResult(
        for nodes: [SceneNode]
    ) -> Result<RupaCore.SurfaceContinuityResult?, Error> {
        surfaceInspectorStateBuilder.continuitySummaryResult(for: nodes)
    }

    private func selectedSurfaceContinuityResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceContinuity?, Error> {
        surfaceInspectorStateBuilder.continuityResult(for: nodes)
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
        WorkspaceInteractionScaleDefaults(ruler: session.document.ruler)
    }

    private func sketchCurveOperationControls(
        _ entity: InspectorSketchEntity,
        controls: [WorkspaceSketchCurveOperationControl]
    ) -> some View {
        WorkspaceSketchCurveOperationControlsView(
            entity: entity,
            controls: controls,
            state: sketchCurveOperationControlsState(for: entity),
            displayUnit: session.document.displayUnit,
            extendDistanceMeters: $sketchExtendDistanceMeters,
            extendShape: $sketchExtendShape,
            vertexOffsetDistanceMeters: $sketchVertexOffsetDistanceMeters,
            cornerTreatmentDistanceMeters: $sketchCornerTreatmentDistanceMeters,
            cornerTreatment: $sketchCornerTreatment,
            joinContinuity: $sketchCurveJoinContinuity,
            vertexAlignmentContinuity: $sketchVertexAlignmentContinuity,
            sliderMetersRange: { meters in
                lengthSliderMetersRange(for: meters)
            },
            onExtend: extendSelectedSketchCurve,
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
            .padding(.horizontal, WorkspaceInspectorLayout.panelHorizontalInset)
            .padding(.vertical, WorkspaceInspectorLayout.panelVerticalInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        let workspaceBounds = session.currentEvaluation.flatMap {
            WorkspaceBoundsService().bounds(for: $0.evaluatedDocument)
        }
        let recommendationStates = workspaceDocumentRecommendationStates(
            bounds: workspaceBounds,
            ruler: session.document.ruler,
            displayUnit: session.document.displayUnit
        )
        return WorkspaceDocumentInspectorState(
            documentName: documentTitle,
            documentID: shortID(session.document.id),
            sourceUnitTitle: "m",
            displayUnit: session.document.displayUnit,
            sourceFeatureCount: session.document.cadDocument.designGraph.order.count,
            sceneNodeCount: session.document.productMetadata.sceneNodes.count,
            selectedCount: session.selection.selectedSceneNodeIDs.count,
            generatedBodyCount: session.evaluatedBodyCount,
            componentCount: session.document.productMetadata.componentDefinitions.count,
            instanceCount: session.document.productMetadata.componentInstances.count,
            evaluationTitle: evaluationStatusTitle,
            diagnosticSummary: diagnosticSummary,
            renderReasonTitle: renderInvalidationReasonTitle,
            renderGenerationTitle: renderInvalidationGenerationTitle,
            materialCount: session.document.productMetadata.materialLibrary.materials.count,
            defaultMaterialTitle: defaultMaterialTitle,
            validationRuleCount: session.document.productMetadata.validationRules.count,
            exportPresetCount: session.document.productMetadata.exportPresets.count,
            ruler: session.document.ruler,
            scaleRecommendation: recommendationStates.scale,
            scalePresetOptions: workspaceDocumentScalePresetOptionStates(
                ruler: session.document.ruler
            ),
            precisionRecommendation: recommendationStates.precision,
            parameters: workspaceParameterInspectorState
        )
    }

    private var workspaceParameterInspectorState: WorkspaceParameterInspectorState {
        WorkspaceParameterInspectorState(
            result: ParameterListResult(
                document: session.document,
                generation: session.generation,
                dirty: session.isDirty,
                diagnostics: session.diagnostics
            ),
            displayUnit: session.document.displayUnit
        )
    }

    private func workspaceObjectOverviewInspectorState(
        for nodes: [SceneNode]
    ) -> WorkspaceObjectOverviewInspectorState {
        WorkspaceObjectOverviewInspectorStateBuilder(
            document: session.document,
            objectRegistry: objectRegistry,
            selectedTargetSummary: selectedTargetSummary,
            selectedTargetCount: selectedTargetCount
        )
        .state(for: nodes)
    }

    @ViewBuilder
    private func objectInspectorSections(_ nodes: [SceneNode]) -> some View {
        let overviewState = workspaceObjectOverviewInspectorState(for: nodes)
        WorkspaceInspectorTextSectionView(section: overviewState.selectionSection)

        if let patternArrayState = patternArrayInspectorState(for: nodes) {
            patternArrayInspectorSection(patternArrayState)
        }

        WorkspaceInspectorTextSectionView(section: overviewState.referenceSection)
        WorkspaceInspectorTextSectionView(section: overviewState.hierarchySection)
        sectionAnalysisInspectorSection(nodes)

        WorkspaceSurfaceInspectorView(
            analysisResult: selectedSurfaceAnalysisResult(for: nodes),
            continuityResult: selectedSurfaceContinuityResult(for: nodes),
            boundaryContinuityStateResult: selectedSurfaceBoundaryContinuityStateResult,
            showsUnavailableSections: shouldShowSurfaceContinuitySection(for: nodes),
            displayUnit: session.document.displayUnit,
            boundaryContinuityLevel: $surfaceBoundaryContinuityLevel,
            boundaryMatchSide: $surfaceBoundaryMatchSide,
            boundaryReferenceDirection: $surfaceBoundaryReferenceDirection,
            trimDomainULowerBound: $surfaceTrimDomainULowerBound,
            trimDomainUUpperBound: $surfaceTrimDomainUUpperBound,
            trimDomainVLowerBound: $surfaceTrimDomainVLowerBound,
            trimDomainVUpperBound: $surfaceTrimDomainVUpperBound,
            onMatchBoundaryContinuity: matchSurfaceBoundaryContinuity,
            onSetTrimDomain: setSurfaceTrimDomain
        )

        projectCurvesToFaceSection()
        projectOutlineSection(nodes)
        WorkspaceTopologyEditInspectorView(
            state: topologyEditInspectorState(for: nodes),
            displayUnit: session.document.displayUnit,
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
            onDraftFace: { target, neutralTarget, angleDegrees in
                draftSelectedFace(
                    target,
                    neutralTarget: neutralTarget,
                    angleDegrees: angleDegrees
                )
            },
            onOffsetEdges: { targets, meters, gapFill in
                offsetSelectedEdges(targets, by: meters, gapFill: gapFill)
            },
            onProjectEdges: projectSelectedGeneratedEdgesToConstructionPlane,
            onFilletEdges: { targets, meters in
                filletSelectedEdges(targets, radius: meters)
            },
            onChamferEdges: { targets, meters in
                chamferSelectedEdges(targets, by: meters)
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

        objectShapeSection(nodes)

        WorkspaceObjectTransformInspectorView(
            nodes: nodes,
            displayUnit: session.document.displayUnit,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            materialOptions: sortedMaterialOptions,
            onSetVisibility: { id, isVisible in
                session.setSceneNodeVisibility(id, isVisible: isVisible)
            },
            onSetLock: { id, isLocked in
                session.setSceneNodeLock(id, isLocked: isLocked)
            },
            onSetTransformComponent: { component, value in
                setTransformComponent(component, to: value, for: nodes)
            },
            onSetMaterial: { id, materialID in
                session.setSceneNodeMaterial(id, materialID: materialID)
            },
            onResetTransform: {
                for node in nodes {
                    session.setSceneNodeTransform(node.id, localTransform: .identity)
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
            return "\(sectionAnalysisPlaneSourceTitle(plane.sourceKind)) \(shortID(id))"
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
            session: session,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            defaultAxisDistanceMeters: workspaceInteractionScaleDefaults.operationStepMeters,
            isCurvePathPickActive: patternArrayCurvePathPickState.isPicking(sourceID: state.sourceID),
            onStartCurvePathPick: startPatternArrayCurvePathPick,
            onCancelCurvePathPick: cancelPatternArrayCurvePathPick
        )
    }

    private func surfaceControlPointInspectorSection(
        _ state: SurfaceControlPointInspectorState
    ) -> some View {
        SurfaceControlPointInspectorView(
            state: state,
            session: session,
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
        session.reportToolStatus("Pick a sketch line, circle, arc, or spline for the Curve Array path.")
    }

    private func cancelPatternArrayCurvePathPick() {
        patternArrayCurvePathPreviewCandidate = nil
        patternArrayCurvePathPickState.cancel()
        session.reportToolStatus("Curve Array path pick canceled.")
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
            displayUnit: session.document.displayUnit,
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
                    }
                    .accessibilityIdentifier("InspectorCurve.line.createSlot")
                }

                Button {
                    reverseSelectedSketchCurve(entity.target)
                } label: {
                    Label("Reverse", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("InspectorCurve.line.reverse")

                Button {
                    splitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Split", systemImage: "scissors")
                }
                .accessibilityIdentifier("InspectorCurve.line.split")

                Button {
                    trimSelectedSketchCurveSegment(entity.target)
                } label: {
                    Label("Trim", systemImage: "delete.left")
                }
                .accessibilityIdentifier("InspectorCurve.line.trim")
            }
            if let cutter = selectedSketchEntityCutterTarget(excluding: entity.target) {
                inspectorActionRow {
                    Button {
                        cutSelectedSketchCurve(entity.target, cutter: cutter)
                    } label: {
                        Label("Cut", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .accessibilityIdentifier("InspectorCurve.line.cut")
                }
            }
            let sagitta = sketchLineArcSagitta(for: entity)
            inspectorActionRow {
                Button {
                    convertSelectedSketchLineToArc(entity.target, sagitta: sagitta)
                } label: {
                    Label("Arc +\(formatted(sagitta))", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .accessibilityIdentifier("InspectorCurve.line.convertArcPositive")

                Button {
                    convertSelectedSketchLineToArc(entity.target, sagitta: -sagitta)
                } label: {
                    Label("Arc -\(formatted(sagitta))", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .accessibilityIdentifier("InspectorCurve.line.convertArcNegative")

                Button {
                    convertSelectedSketchLineToSpline(entity.target)
                } label: {
                    Label("Spline", systemImage: "point.3.connected.trianglepath.dotted")
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
                inspectorActionRow {
                    Button {
                        cutSelectedSketchCurve(entity.target, cutter: cutter)
                    } label: {
                        Label("Cut", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .accessibilityIdentifier("InspectorCurve.circle.cut")
                }
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
                    values: [degrees(fromRadians: startAngle)],
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
                    values: [degrees(fromRadians: endAngle)],
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
                    }
                    .accessibilityIdentifier("InspectorCurve.arc.createSlot")
                }

                Button {
                    splitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Split", systemImage: "scissors")
                }
                .accessibilityIdentifier("InspectorCurve.arc.split")

                Button {
                    trimSelectedSketchCurveSegment(entity.target)
                } label: {
                    Label("Trim", systemImage: "delete.left")
                }
                .accessibilityIdentifier("InspectorCurve.arc.trim")
            }
            if let cutter = selectedSketchEntityCutterTarget(excluding: entity.target) {
                inspectorActionRow {
                    Button {
                        cutSelectedSketchCurve(entity.target, cutter: cutter)
                    } label: {
                        Label("Cut", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .accessibilityIdentifier("InspectorCurve.arc.cut")
                }
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
                    displayUnit: session.document.displayUnit,
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
                    displayUnit: session.document.displayUnit,
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
    private func objectShapeSection(_ nodes: [SceneNode]) -> some View {
        let shapes = WorkspaceObjectShapeInspectorStateBuilder(
            document: session.document,
            currentEvaluation: session.currentEvaluation,
            documentGeneration: session.generation,
            objectRegistry: objectRegistry
        )
        .shapes(for: nodes)
        WorkspaceObjectShapeInspectorView(
            shapes: shapes,
            displayUnit: session.document.displayUnit,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            sizeSliderMetersRange: sizeSliderMetersRange,
            fallbackLengthSliderMetersRange: lengthSliderMetersRange(for: 0.0),
            onSetCenter: setObjectCenter,
            onSetSize: setObjectSize,
            onSetProperty: setObjectProperty
        )
    }

    private func setObjectCenter(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shapes: [InspectorObjectShape]
    ) {
        for shape in shapes {
            guard let node = session.document.productMetadata.sceneNodes[shape.id] else {
                continue
            }
            var values = WorkspaceTransformMatrix.normalizedValues(node.localTransform.matrix.values)
            switch axis {
            case .x:
                values[InspectorTransformComponent.translationX.matrixIndex] = meters - shape.sourceCenter.x
            case .y:
                values[InspectorTransformComponent.translationY.matrixIndex] = meters - shape.sourceCenter.y
            case .z:
                values[InspectorTransformComponent.translationZ.matrixIndex] = meters - shape.sourceCenter.z
            }
            do {
                let matrix = try Matrix4x4(values: values)
                session.setSceneNodeTransform(
                    node.id,
                    localTransform: Transform3D(matrix: matrix)
                )
            } catch {
                session.reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func setObjectSize(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shapes: [InspectorObjectShape]
    ) {
        let sizeMeters = max(meters, 1.0e-9)
        for shape in shapes {
            switch shape.typeID {
            case .some(.cube):
                setCubeSize(axis, to: sizeMeters, for: shape)
            case .some(.cylinder):
                setCylinderSize(axis, to: sizeMeters, for: shape)
            default:
                continue
            }
        }
    }

    private func offsetSelectedFace(
        _ target: SelectionTarget,
        by meters: Double
    ) {
        let result = session.offsetBodyFace(
            target: target,
            distance: .length(meters, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func deleteSelectedFaces(_ targets: [SelectionTarget]) {
        let result = session.deleteBodyFaces(targets: targets)
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func draftSelectedFace(
        _ target: SelectionTarget,
        neutralTarget: SelectionTarget,
        angleDegrees: Double
    ) {
        guard angleDegrees.isFinite else {
            session.reportToolStatus("Draft Face requires a finite angle.", severity: .warning)
            isPreviewExpanded = true
            return
        }
        let result = session.draftBodyFaces(
            targets: [target],
            neutralTarget: neutralTarget,
            angle: .angle(angleDegrees, .degree)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func offsetSelectedEdges(
        _ targets: [SelectionTarget],
        by meters: Double,
        gapFill: OffsetCurveGapFill,
        isSymmetric: Bool = false
    ) {
        guard targets.count == 1, let target = targets.first else {
            session.reportToolStatus(
                "Offset Edge currently supports one selected edge.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }
        let result = session.offsetCurve(
            target: target,
            distance: .length(max(meters, 1.0e-9), .meter),
            options: OffsetCurveOptions(
                isSymmetric: isSymmetric,
                gapFill: gapFill
            ),
            vertexHandle: nil
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
        if result?.didMutate == true {
            edgeOffsetCommandState.deactivate()
        }
    }

    private func chamferSelectedEdges(
        _ targets: [SelectionTarget],
        by meters: Double
    ) {
        let result = session.chamferBodyEdges(
            targets: targets,
            distance: .length(meters, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func filletSelectedEdges(
        _ targets: [SelectionTarget],
        radius meters: Double
    ) {
        let result = session.filletBodyEdges(
            targets: targets,
            radius: .length(meters, .meter),
            segmentCount: 8
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func moveSelectedVertex(
        _ target: SelectionTarget,
        deltaX: Double,
        deltaY: Double
    ) {
        let result = session.moveBodyVertex(
            target: target,
            deltaX: .length(deltaX, .meter),
            deltaY: .length(deltaY, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func offsetSelectedRegions(
        _ targets: [SelectionTarget],
        by meters: Double,
        gapFill: OffsetCurveGapFill,
        isSymmetric: Bool = false,
        combinesRegions: Bool = false
    ) {
        let result = session.offsetRegions(
            targets: targets,
            distance: .length(meters, .meter),
            options: OffsetCurveOptions(
                isSymmetric: isSymmetric,
                gapFill: gapFill
            ),
            combinesRegions: combinesRegions
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func moveSelectedSketchEntityPoint(
        _ target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: Double,
        deltaY: Double
    ) {
        let result = session.moveSketchEntityPoint(
            target: target,
            handle: handle,
            deltaX: .length(deltaX, .meter),
            deltaY: .length(deltaY, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func moveSelectedSplineControlPoint(
        _ target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: Double,
        deltaY: Double
    ) {
        let result = session.moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: controlPointIndex,
            deltaX: .length(deltaX, .meter),
            deltaY: .length(deltaY, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
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
        let result = session.slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: controlPointIndexes,
            direction: direction,
            distance: .length(resolvedDistanceMeters, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func slideSelectedPolySplineSurfaceVertices(
        _ targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double? = nil
    ) {
        let resolvedDistanceMeters = distanceMeters ?? max(polySplineSurfaceVertexSlideDistanceMeters, 1.0e-9)
        let result = session.slidePolySplineSurfaceVertices(
            targets: targets,
            direction: direction,
            distance: .length(resolvedDistanceMeters, .meter)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceControlPointDisplay(
        _ targets: [SelectionReference],
        isVisible: Bool
    ) {
        var shouldExpandPreview = false
        for target in targets {
            let result = session.setSurfaceControlPointDisplay(
                target: target,
                isVisible: isVisible
            )
            if result?.diagnostics.isEmpty == false || result == nil {
                shouldExpandPreview = true
            }
        }
        if shouldExpandPreview {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceFrameDisplay(
        _ queries: [SurfaceFrameQuery],
        isVisible: Bool
    ) {
        var shouldExpandPreview = false
        for query in queries {
            let result = session.setSurfaceFrameDisplay(
                query: query,
                isVisible: isVisible
            )
            if result?.diagnostics.isEmpty == false || result == nil {
                shouldExpandPreview = true
            }
        }
        if shouldExpandPreview {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceControlPointCoordinate(
        _ axis: SurfaceControlPointInspectorState.CoordinateAxis,
        meters: Double,
        state: SurfaceControlPointInspectorState
    ) {
        guard state.canEditCoordinates else {
            return
        }

        var shouldExpandPreview = false
        for entry in state.entries where entry.isEditable {
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

            let result = session.moveSurfaceControlPoint(
                target: entry.selectionReference,
                deltaX: .length(axis == .x ? delta : 0.0, .meter),
                deltaY: .length(axis == .y ? delta : 0.0, .meter),
                deltaZ: .length(axis == .z ? delta : 0.0, .meter)
            )
            if result?.diagnostics.isEmpty == false || result == nil {
                shouldExpandPreview = true
            }
        }
        if shouldExpandPreview {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceControlPointWeight(
        _ targets: [SelectionReference],
        weight: Double
    ) {
        var shouldExpandPreview = false
        for target in targets {
            let result = session.setSurfaceControlPointWeight(
                target: target,
                weight: .scalar(max(weight, 1.0e-9))
            )
            if result?.diagnostics.isEmpty == false || result == nil {
                shouldExpandPreview = true
            }
        }
        if shouldExpandPreview {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceKnotValue(
        _ target: SelectionReference,
        value: Double
    ) {
        let result: CommandExecutionResult?
        switch target {
        case .surface(.trimKnot(let reference)):
            result = session.setSurfaceTrimKnotValue(
                target: .surface(.trim(reference.trim)),
                knotIndex: reference.knotIndex,
                value: .scalar(value)
            )
        default:
            result = session.setSurfaceKnotValue(
                target: target,
                value: .scalar(value)
            )
        }
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func insertSurfaceKnot(
        _ target: SelectionReference,
        value: Double
    ) {
        let result: CommandExecutionResult?
        switch target {
        case .surface(.trimKnot), .surface(.trimSpan):
            result = session.insertSurfaceTrimKnot(
                target: target,
                value: .scalar(value)
            )
        default:
            result = session.insertSurfaceKnot(
                target: target,
                value: .scalar(value)
            )
        }
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func splitSurfaceSpan(
        _ target: SelectionReference,
        fraction: Double
    ) {
        let result = session.splitSurfaceSpan(
            target: target,
            fraction: .scalar(fraction)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceKnotMultiplicity(
        _ target: SelectionReference,
        multiplicity: Int
    ) {
        let result: CommandExecutionResult?
        switch target {
        case .surface(.trimKnot(let reference)):
            result = session.setSurfaceTrimKnotMultiplicity(
                target: .surface(.trim(reference.trim)),
                knotIndex: reference.knotIndex,
                multiplicity: multiplicity
            )
        default:
            result = session.setSurfaceKnotMultiplicity(
                target: target,
                multiplicity: multiplicity
            )
        }
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func matchSurfaceBoundaryContinuity(
        target: SelectionReference,
        reference: SelectionReference,
        level: SurfaceBoundaryContinuityLevel,
        matchSide: SurfaceBoundaryMatchSide,
        referenceDirection: SurfaceBoundaryReferenceDirection
    ) {
        let result = session.matchSurfaceBoundaryContinuity(
            target: target,
            reference: reference,
            level: level,
            matchSide: matchSide,
            referenceDirection: referenceDirection
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func setSurfaceTrimDomain(
        target: SelectionReference,
        uLowerBound: Double,
        uUpperBound: Double,
        vLowerBound: Double,
        vUpperBound: Double
    ) {
        let result = session.setSurfaceTrimDomain(
            target: target,
            uLowerBound: .scalar(uLowerBound),
            uUpperBound: .scalar(uUpperBound),
            vLowerBound: .scalar(vLowerBound),
            vUpperBound: .scalar(vUpperBound)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func slideSelectedSurfaceControlPoints(
        _ targets: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double? = nil
    ) {
        let resolvedDistanceMeters = distanceMeters ?? max(polySplineSurfaceVertexSlideDistanceMeters, 1.0e-9)
        let result = session.slideSurfaceControlPoints(
            targets: targets,
            direction: direction,
            distance: .length(resolvedDistanceMeters, .meter)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func moveSelectedSurfaceControlPointsInFrame(
        _ targets: [SelectionReference],
        frame: SurfaceFrameQuery,
        uDistanceMeters: Double,
        vDistanceMeters: Double,
        normalDistanceMeters: Double
    ) {
        let result = session.moveSurfaceControlPointsInFrame(
            targets: targets,
            frame: frame,
            uDistance: .length(uDistanceMeters, .meter),
            vDistance: .length(vDistanceMeters, .meter),
            normalDistance: .length(normalDistanceMeters, .meter)
        )
        if result?.diagnostics.isEmpty == false || result == nil {
            isPreviewExpanded = true
        }
    }

    private func curveCurvatureDisplay(
        for entity: InspectorSketchEntity
    ) -> CurveCurvatureDisplay? {
        session.document.productMetadata.curveCurvatureDisplays[
            .sketchEntity(
                featureID: entity.sourceFeatureID,
                entityID: entity.entityID
            )
        ]
    }

    private func pointDisplay(
        for entity: InspectorSketchEntity
    ) -> PointDisplay? {
        session.document.productMetadata.pointDisplays[
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
        let result = session.setCurveCurvatureDisplay(
            target: entity.target,
            isVisible: isVisible,
            combScale: max(combScale, 1.0e-6)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setPointDisplay(
        _ entity: InspectorSketchEntity,
        isVisible: Bool
    ) {
        let result = session.setPointDisplay(
            target: entity.target,
            isVisible: isVisible
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeCurveTension(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        level: InspectorBridgeCurveTensionLevel,
        value: Double
    ) {
        let nextValue = max(value, 1.0e-6)
        let result: CommandExecutionResult?
        switch endpoint {
        case .first:
            var tension = bridgeCurve.firstEndpoint.tension
            setBridgeTensionLevel(&tension, level: level, value: nextValue)
            var nextEndpoint = bridgeCurve.firstEndpoint
            nextEndpoint.tension = tension
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nextEndpoint
            )
        case .second:
            var tension = bridgeCurve.secondEndpoint.tension
            setBridgeTensionLevel(&tension, level: level, value: nextValue)
            var nextEndpoint = bridgeCurve.secondEndpoint
            nextEndpoint.tension = tension
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: nextEndpoint
            )
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeTensionLevel(
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
        let result: CommandExecutionResult?
        switch endpoint {
        case .first:
            var nextEndpoint = bridgeCurve.firstEndpoint
            nextEndpoint.parameter = .scalar(clampedValue)
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nextEndpoint
            )
        case .second:
            var nextEndpoint = bridgeCurve.secondEndpoint
            nextEndpoint.parameter = .scalar(clampedValue)
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: nextEndpoint
            )
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeCurveSense(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint
    ) {
        let result: CommandExecutionResult?
        switch endpoint {
        case .first:
            var nextEndpoint = bridgeCurve.firstEndpoint
            nextEndpoint.reversesSense.toggle()
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nextEndpoint
            )
        case .second:
            var nextEndpoint = bridgeCurve.secondEndpoint
            nextEndpoint.reversesSense.toggle()
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: nextEndpoint
            )
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeCurveTrimSide(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        trimSide: BridgeCurveTrimSide
    ) {
        let result: CommandExecutionResult?
        switch endpoint {
        case .first:
            var nextEndpoint = bridgeCurve.firstEndpoint
            nextEndpoint.trimSide = trimSide
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nextEndpoint
            )
        case .second:
            var nextEndpoint = bridgeCurve.secondEndpoint
            nextEndpoint.trimSide = trimSide
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: nextEndpoint
            )
        }
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func trimBridgeCurveSources(_ bridgeCurve: InspectorBridgeCurve) {
        let result = session.setBridgeCurveParameters(
            sourceID: bridgeCurve.sourceID,
            trimsSourceCurves: true
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeCurveCurvatureDisplay(
        _ bridgeCurve: InspectorBridgeCurve,
        isVisible: Bool,
        combScale: Double
    ) {
        let result = session.setCurveCurvatureDisplay(
            target: bridgeCurve.target,
            isVisible: isVisible,
            combScale: max(combScale, 1.0e-6)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setBridgeCurveContinuity(
        _ bridgeCurve: InspectorBridgeCurve,
        endpoint: InspectorBridgeCurveEndpoint,
        continuity: BridgeCurveEndpointContinuity
    ) {
        var nextContinuity = bridgeCurve.continuity
        switch endpoint {
        case .first:
            nextContinuity.first = continuity
        case .second:
            nextContinuity.second = continuity
        }
        let result = session.setBridgeCurveParameters(
            sourceID: bridgeCurve.sourceID,
            continuity: nextContinuity
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func addSmoothSplineControlPointConstraint(
        _ entity: InspectorSketchEntity,
        controlPointIndex: Int
    ) {
        let result = session.addSketchConstraint(
            featureID: entity.sourceFeatureID,
            constraint: .smoothSplineControlPoint(
                entity: entity.entityID,
                index: controlPointIndex
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func addSplineEndpointTangentConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        lineID: SketchEntityID
    ) {
        let result = session.addSketchConstraint(
            featureID: entity.sourceFeatureID,
            constraint: .splineEndpointTangent(
                spline: entity.entityID,
                endpoint: endpoint,
                line: lineID
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func addTangentSplineEndpointsConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        target: SketchSplineEndpointReference
    ) {
        let result = session.addSketchConstraint(
            featureID: entity.sourceFeatureID,
            constraint: .tangentSplineEndpoints(
                first: SketchSplineEndpointReference(
                    splineID: entity.entityID,
                    endpoint: endpoint
                ),
                second: target
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func addSmoothSplineEndpointsConstraint(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint,
        target: SketchSplineEndpointReference
    ) {
        let result = session.addSketchConstraint(
            featureID: entity.sourceFeatureID,
            constraint: .smoothSplineEndpoints(
                first: SketchSplineEndpointReference(
                    splineID: entity.entityID,
                    endpoint: endpoint
                ),
                second: target
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchCircleRadius(
        _ target: SelectionTarget,
        meters: Double
    ) {
        let result = session.setSketchCircleParameters(
            target: target,
            center: nil,
            radius: .length(max(meters, 1.0e-9), .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchArcRadius(
        _ target: SelectionTarget,
        meters: Double
    ) {
        let result = session.setSketchArcParameters(
            target: target,
            center: nil,
            radius: .length(max(meters, 1.0e-9), .meter),
            startAngle: nil,
            endAngle: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchArcStartAngle(
        _ target: SelectionTarget,
        degrees: Double
    ) {
        let result = session.setSketchArcParameters(
            target: target,
            center: nil,
            radius: nil,
            startAngle: .angle(degrees, .degree),
            endAngle: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchArcStartAngle(
        _ target: SelectionTarget,
        radians: Double
    ) {
        let result = session.setSketchArcParameters(
            target: target,
            center: nil,
            radius: nil,
            startAngle: .angle(radians, .radian),
            endAngle: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchArcEndAngle(
        _ target: SelectionTarget,
        degrees: Double
    ) {
        let result = session.setSketchArcParameters(
            target: target,
            center: nil,
            radius: nil,
            startAngle: nil,
            endAngle: .angle(degrees, .degree)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func setSelectedSketchArcEndAngle(
        _ target: SelectionTarget,
        radians: Double
    ) {
        let result = session.setSketchArcParameters(
            target: target,
            center: nil,
            radius: nil,
            startAngle: nil,
            endAngle: .angle(radians, .radian)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
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
        let result = session.setSketchEntityDimension(
            target: target,
            kind: kind,
            value: value
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func convertSelectedSketchLineToArc(
        _ target: SelectionTarget,
        sagitta: Double
    ) {
        let result = session.convertSketchLineToArc(
            target: target,
            sagitta: .length(sagitta, .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func convertSelectedSketchLineToSpline(
        _ target: SelectionTarget
    ) {
        let result = session.convertSketchLineToSpline(target: target)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func reverseSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let result = session.reverseSketchCurve(target: target)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func extendSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let result = session.extendSketchCurve(
            target: target,
            distance: .length(max(sketchExtendDistanceMeters, 1.0e-9), .meter),
            shape: sketchExtendShape
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
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
        let result = session.applySketchCornerTreatment(
            target: target,
            adjacentTarget: adjacentTarget,
            distance: .length(max(sketchCornerTreatmentDistanceMeters, 1.0e-9), .meter),
            treatment: sketchCornerTreatment
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func offsetSelectedSketchVertex(
        _ entity: InspectorSketchEntity
    ) {
        guard let handle = selectedSketchVertexOffsetHandle(entity) else {
            return
        }
        let result = session.offsetSketchVertex(
            target: entity.target,
            handle: handle,
            distance: .length(max(sketchVertexOffsetDistanceMeters, 1.0e-9), .meter)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func splitSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let fraction = min(max(sketchSplitFraction, 0.01), 0.99)
        let result = session.splitSketchCurve(
            target: target,
            fraction: .scalar(fraction)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func insertSelectedSketchSplineControlPoint(
        _ target: SelectionTarget
    ) {
        let fraction = min(max(sketchSplitFraction, 0.01), 0.99)
        let result = session.insertSketchSplineControlPoint(
            target: target,
            fraction: .scalar(fraction)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func rebuildSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let result = session.rebuildSketchCurve(
            target: target,
            options: .points(controlPointCount: sketchRebuildControlPointCount)
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func refitSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let toleranceRange = workspaceInteractionScaleDefaults.sketchRebuildToleranceRange
        let tolerance = min(
            max(sketchRebuildToleranceMeters, toleranceRange.lowerBound),
            toleranceRange.upperBound
        )
        let result = session.rebuildSketchCurve(
            target: target,
            options: .refit(
                tolerance: .length(tolerance, .meter),
                keepsCorners: sketchRebuildKeepsCorners
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func explicitControlSelectedSketchCurve(
        _ target: SelectionTarget
    ) {
        let result = session.rebuildSketchCurve(
            target: target,
            options: .explicitControl(
                degree: sketchRebuildExplicitDegree,
                spanCount: sketchRebuildExplicitSpanCount,
                weight: min(max(sketchRebuildExplicitWeight, 0.0), 1.0)
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func trimSelectedSketchCurveSegment(
        _ target: SelectionTarget
    ) {
        let result = session.trimSketchCurveSegment(target: target)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func cutSelectedSketchCurve(
        _ target: SelectionTarget,
        cutter: SelectionTarget
    ) {
        let result = session.cutSketchCurve(
            target: target,
            cutter: cutter
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func joinSelectedSketchCurves(
        _ entity: InspectorSketchEntity
    ) {
        guard let adjacentTarget = sketchCurveJoinInspectorState(for: entity).joinAdjacentTarget else {
            return
        }
        let result = session.joinSketchCurves(
            target: entity.target,
            adjacentTarget: adjacentTarget,
            continuity: sketchCurveJoinContinuity
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func unjoinSelectedSketchCurve(
        _ entity: InspectorSketchEntity
    ) {
        guard sketchCurveJoinInspectorState(for: entity).canUnjoin else {
            return
        }
        let result = session.unjoinSketchCurve(target: entity.target)
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func alignSelectedSketchVertex(
        _ entity: InspectorSketchEntity
    ) {
        guard let referenceTarget = selectedSketchVertexAlignmentReferenceTarget(for: entity) else {
            return
        }
        let result = session.alignSketchVertex(
            target: entity.target,
            reference: referenceTarget,
            options: SketchVertexAlignmentOptions(
                continuity: sketchVertexAlignmentContinuity
            )
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func projectSelectedSketchCurvesToConstructionPlane(
        _ entity: InspectorSketchEntity
    ) {
        let targets = selectedSketchCurveProjectionTargets(for: entity)
        guard targets.isEmpty == false else {
            return
        }
        let result = session.projectSketchCurvesToConstructionPlane(
            targets: targets,
            plane: nil,
            name: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func projectSelectedGeneratedEdgesToConstructionPlane(
        _ targets: [SelectionTarget]
    ) {
        guard targets.isEmpty == false else {
            return
        }
        let result = session.projectSketchCurvesToConstructionPlane(
            targets: targets,
            plane: nil,
            name: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func projectSelectedCurvesToGeneratedFace(
        _ targets: [SelectionTarget],
        face: SelectionTarget
    ) {
        guard targets.isEmpty == false else {
            return
        }
        let result = session.projectCurvesToGeneratedFace(
            targets: targets,
            face: face,
            name: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func projectSelectedBodyOutlinesToConstructionPlane(
        _ targets: [SelectionTarget]
    ) {
        guard targets.isEmpty == false else {
            return
        }
        let result = session.projectBodyOutlinesToConstructionPlane(
            targets: targets,
            plane: nil,
            name: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
    }

    private func createSlotFromOffsetCurve(
        _ target: SelectionTarget,
        width meters: Double
    ) {
        let result = session.offsetCurve(
            target: target,
            distance: .length(max(meters, 1.0e-9), .meter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        )
        if result?.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
        if result?.didMutate == true {
            slotProfileCommandState.deactivate()
        }
    }

    private func setCubeSize(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shape: InspectorObjectShape
    ) {
        session.setCubeDimensions(
            featureID: shape.featureID,
            sizeX: .length(axis == .x ? meters : shape.size.x, .meter),
            sizeY: .length(axis == .y ? meters : shape.size.y, .meter),
            sizeZ: .length(axis == .z ? meters : shape.size.z, .meter)
        )
        if axis == .y {
            preserveObjectCenterAfterYResize(to: meters, for: shape)
        }
    }

    private func setCylinderSize(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shape: InspectorObjectShape
    ) {
        guard shape.cylinder != nil else {
            return
        }
        let radius = axis == .y ? max(shape.size.x, shape.size.z) / 2.0 : meters / 2.0
        session.setCylinderDimensions(
            featureID: shape.featureID,
            radius: .length(max(radius, 1.0e-9), .meter),
            sizeY: .length(axis == .y ? meters : shape.size.y, .meter)
        )
        if axis == .y {
            preserveObjectCenterAfterYResize(to: meters, for: shape)
        }
    }

    private func preserveObjectCenterAfterYResize(
        to sizeYMeters: Double,
        for shape: InspectorObjectShape
    ) {
        guard shape.size.y > 1.0e-9,
              let node = session.document.productMetadata.sceneNodes[shape.id] else {
            return
        }
        let sourceCenterRatio = shape.sourceCenter.y / shape.size.y
        let nextSourceCenterY = sourceCenterRatio * sizeYMeters
        var values = WorkspaceTransformMatrix.normalizedValues(node.localTransform.matrix.values)
        values[InspectorTransformComponent.translationY.matrixIndex] = shape.center.y - nextSourceCenterY
        do {
            let matrix = try Matrix4x4(values: values)
            session.setSceneNodeTransform(
                node.id,
                localTransform: Transform3D(matrix: matrix)
            )
        } catch {
            session.reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private var transformPositionSliderMetersRange: ClosedRange<Double> {
        let span = session.document.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return -span ... span
    }

    private var sizeSliderMetersRange: ClosedRange<Double> {
        let visibleSpan = session.document.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return 0.0 ... visibleSpan
    }

    private func setTransformComponent(
        _ component: InspectorTransformComponent,
        to value: Double,
        for nodes: [SceneNode]
    ) {
        for node in nodes {
            var values = WorkspaceTransformMatrix.normalizedValues(node.localTransform.matrix.values)
            values[component.matrixIndex] = value
            do {
                let matrix = try Matrix4x4(values: values)
                session.setSceneNodeTransform(
                    node.id,
                    localTransform: Transform3D(matrix: matrix)
                )
            } catch {
                session.reportToolStatus(error.localizedDescription, severity: .warning)
            }
        }
    }

    private func extrudeFeatureID(for node: SceneNode) -> FeatureID? {
        guard let featureID = node.reference?.featureID,
              let feature = session.document.cadDocument.designGraph.nodes[featureID],
              case .extrude = feature.operation else {
            return nil
        }
        return featureID
    }

    private func resolvedExtrudeDistance(featureID: FeatureID) -> Double? {
        guard let feature = session.document.cadDocument.designGraph.nodes[featureID],
              case .extrude(let extrude) = feature.operation else {
            return nil
        }
        do {
            let quantity = try session.document.cadDocument.parameters.resolvedValue(for: extrude.distance)
            guard quantity.kind == .length else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    private var sortedMaterialOptions: [WorkspaceObjectMaterialOption] {
        session.document.productMetadata.materialLibrary.materials
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
        guard value.valueKind == property.valueKind else {
            return
        }
        for shape in shapes {
            session.setSceneNodeObjectProperty(
                shape.id,
                propertyID: property.id,
                value: value
            )
        }
    }

    private func lengthSliderMetersRange(for meters: Double) -> ClosedRange<Double> {
        workspaceLengthSliderMetersRange(
            for: meters,
            ruler: session.document.ruler
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
        return angle.isFinite ? degrees(fromRadians: angle) : nil
    }

    private func sketchLineArcSagitta(for entity: InspectorSketchEntity) -> Double {
        guard let length = sketchLineLength(for: entity) else {
            return defaultSketchEntityMoveStepMeters
        }
        let ruler = session.document.ruler.normalizedForWorkspaceScale()
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

    private func sweepSectionSummary(_ section: SweepSectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(shortID(profile.featureID))"
        case .curve(let curve):
            return "Curve \(shortID(curve.featureID))"
        }
    }

    private var diagnosticSummary: String {
        let diagnostics = session.diagnostics
        guard !diagnostics.isEmpty else {
            return "None"
        }
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(errors) errors, \(warnings) warnings, \(info) info"
    }

    private var renderInvalidationReasonTitle: String {
        switch session.renderInvalidation.reason {
        case .none:
            return "None"
        case .evaluated:
            return "Evaluated"
        case .evaluationFailed:
            return "Evaluation Failed"
        }
    }

    private var renderInvalidationGenerationTitle: String {
        guard let generation = session.renderInvalidation.generation else {
            return "None"
        }
        return "\(generation.value)"
    }

    private var defaultMaterialTitle: String {
        let library = session.document.productMetadata.materialLibrary
        guard let defaultMaterialID = library.defaultMaterialID else {
            return "None"
        }
        return library.materials[defaultMaterialID]?.name ?? "Missing"
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
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
            displayUnit: session.document.displayUnit,
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
        var ruler = session.document.ruler
        if let minorTickMeters {
            ruler.minorTickMeters = minorTickMeters
        }
        if let majorTickMeters {
            ruler.majorTickMeters = majorTickMeters
        }
        if let visibleSpanMeters {
            ruler.visibleSpanMeters = visibleSpanMeters
        }

        session.setRulerConfiguration(ruler.normalizedForWorkspaceScale())
        if visibleSpanMeters != nil {
            requestViewportCameraReset()
        }
    }

    private func applyDisplayUnit(_ unit: LengthDisplayUnit) {
        session.setDisplayUnit(unit)
        resetWorkspaceInteractionScaleDefaults()
    }

    private func applyViewportGridVisualSpacingMode(
        _ visualSpacingMode: ViewportGridVisualSpacingMode
    ) {
        session.setViewportGridSettings(
            ViewportGridSettings(visualSpacingMode: visualSpacingMode)
        )
    }

    private func applyWorkspaceRebaseTranslation(_ translation: Vector3D) {
        session.rebaseWorkspaceOrigin(translation: translation)
        resetWorkspaceInteractionScaleDefaults()
    }

    private func applyWorkspaceScalePreset(_ preset: WorkspaceScalePreset) {
        session.setRulerConfiguration(preset.rulerConfiguration.normalizedForWorkspaceScale())
        resetWorkspaceInteractionScaleDefaults()
        requestViewportCameraReset()
    }

    private func fitWorkspaceScaleToModel() {
        do {
            let plan = try WorkspaceScaleFitService().plan(
                document: session.document,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            )
            switch plan.action {
            case .alreadyFits:
                session.reportToolStatus("Workspace scale already fits the current model.")
            case .unsupportedRange:
                session.reportToolStatus(
                    "Workspace scale cannot fit the current model within the supported preset range.",
                    severity: .warning
                )
            case .applyPreset(let preset):
                session.perform(.setRulerConfiguration(preset.rulerConfiguration.normalizedForWorkspaceScale()))
                resetWorkspaceInteractionScaleDefaults()
                requestViewportCameraReset()
            }
        } catch {
            session.reportToolStatus(error.localizedDescription, severity: .warning)
        }
    }

    private func requestViewportCameraReset() {
        viewportCameraResetSignal += 1
    }

    private func upsertParameterExpression(
        name: String,
        expression: String,
        kind: QuantityKind
    ) -> Bool {
        do {
            let parsedExpression = try ParameterExpressionParser().parseForUpsert(
                expression,
                parameterName: name,
                parameters: session.document.cadDocument.parameters,
                targetKind: kind,
                defaults: ParameterExpressionDefaults(
                    lengthUnit: session.document.displayUnit,
                    angleUnit: .degree
                )
            )
            return session.perform(
                .upsertParameter(
                    name: name,
                    expression: parsedExpression,
                    kind: kind
                )
            ) != nil
        } catch let error as EditorError {
            session.reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            session.reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    private func renameDocumentParameter(
        currentName: String,
        newName: String
    ) -> Bool {
        do {
            let result = try session.execute(
                .renameParameter(
                    currentName: currentName,
                    newName: newName
                )
            )
            return result.didMutate
        } catch let error as EditorError {
            session.reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            session.reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    private func deleteDocumentParameter(name: String) -> Bool {
        session.perform(.deleteParameter(name: name)) != nil
    }

    private func resetWorkspaceInteractionScaleDefaults() {
        let defaults = workspaceInteractionScaleDefaults
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
        }
    }

    private func componentDefinitionName(for id: ComponentDefinitionID) -> String {
        session.document.productMetadata.componentDefinitions[id]?.name ?? "Missing Definition"
    }

    private var evaluationStatusTitle: String {
        switch session.evaluationStatus {
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
            preferredUnit: session.document.displayUnit
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
            return formattedDegrees(degrees(fromRadians: value))
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
                preferredUnit: session.document.displayUnit
            ).text
        case .angle:
            return WorkspaceInspectorNumberText.string(from: degrees(fromRadians: value))
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
                preferredUnit: session.document.displayUnit
            ).unit
        case .angle:
            return session.document.displayUnit
        }
    }

    private func formattedDegrees(_ degrees: Double) -> String {
        "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
    }

    private func degrees(fromRadians radians: Double) -> Double {
        radians * 180.0 / Double.pi
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
        return degrees(fromRadians: span)
    }

    private func activateAgentSessionIfNeeded() async {
        guard let agentHost else {
            return
        }

        if agentSessionID == nil {
            agentSessionID = agentHost.register(
                session: session,
                path: documentURL
            )
        }
        await agentHost.start()
    }

    private func deactivateAgentSession() {
        guard let agentHost, let agentSessionID else {
            return
        }

        agentHost.unregister(id: agentSessionID)
        self.agentSessionID = nil
    }
}
