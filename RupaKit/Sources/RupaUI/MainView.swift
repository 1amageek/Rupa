import Foundation
import MacComponent
import RupaCore
import RupaPreview
import RupaRendering
import SwiftUI

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
    @State private var selectedSplineControlPointIndex: Int
    @State private var sketchSplineControlPointSlideDistanceMeters: Double
    @State private var polySplineSurfaceVertexSlideDistanceMeters: Double
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
    @State private var edgeOffsetDistanceMeters: Double
    @State private var edgeOffsetGapFill: OffsetCurveGapFill
    @State private var edgeOffsetCommandState: EdgeOffsetCommandState
    @State private var dimensionCommandState: DimensionCommandState
    @State private var slotProfileWidthMeters: Double
    @State private var slotProfileCommandState: SlotProfileCommandState
    @State private var viewportProjectionBasis: ViewportProjectionBasis
    @State private var viewAlignedConstructionPlaneRequest: ViewAlignedConstructionPlaneRequest?
    @State private var viewportProjectionRequest: ViewportProjectionRequest?
    @State private var constructionPlaneRenameTargetID: ConstructionPlaneSourceID?
    @State private var constructionPlaneRenameText: String
    @State private var hoveredViewportPickingBackend: ViewportPickingBackend?
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
        objectRegistry: ObjectTypeRegistry = .builtIn,
        agentHost: (any WorkspaceAgentHost)? = nil,
        documentURL: URL? = nil
    ) {
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
        self._selectedSplineControlPointIndex = State(initialValue: 0)
        self._sketchSplineControlPointSlideDistanceMeters = State(initialValue: 0.001)
        self._polySplineSurfaceVertexSlideDistanceMeters = State(initialValue: 0.001)
        self._sketchSplineControlPointSlideCount = State(initialValue: 1)
        self._slideCommandState = State(initialValue: .inactive)
        self._sketchSplitFraction = State(initialValue: 0.5)
        self._sketchRebuildControlPointCount = State(initialValue: 7)
        self._sketchRebuildToleranceMeters = State(initialValue: 0.001)
        self._sketchRebuildKeepsCorners = State(initialValue: true)
        self._sketchRebuildExplicitDegree = State(initialValue: 3)
        self._sketchRebuildExplicitSpanCount = State(initialValue: 2)
        self._sketchRebuildExplicitWeight = State(initialValue: 0.5)
        self._sketchExtendDistanceMeters = State(initialValue: 0.001)
        self._sketchExtendShape = State(initialValue: .natural)
        self._sketchVertexOffsetDistanceMeters = State(initialValue: 0.001)
        self._sketchCornerTreatmentDistanceMeters = State(initialValue: 0.001)
        self._sketchCornerTreatment = State(initialValue: .fillet)
        self._sketchCurveJoinContinuity = State(initialValue: .g0)
        self._sketchVertexAlignmentContinuity = State(initialValue: .g0)
        self._regionOffsetDistanceMeters = State(initialValue: 0.001)
        self._regionOffsetGapFill = State(initialValue: .round)
        self._regionOffsetCommandState = State(initialValue: .inactive)
        self._edgeOffsetDistanceMeters = State(initialValue: 0.001)
        self._edgeOffsetGapFill = State(initialValue: .round)
        self._edgeOffsetCommandState = State(initialValue: .inactive)
        self._dimensionCommandState = State(initialValue: .inactive)
        self._slotProfileWidthMeters = State(initialValue: 0.002)
        self._slotProfileCommandState = State(initialValue: .inactive)
        self._viewportProjectionBasis = State(initialValue: .isometric)
        self._viewAlignedConstructionPlaneRequest = State(initialValue: nil)
        self._viewportProjectionRequest = State(initialValue: nil)
        self._constructionPlaneRenameTargetID = State(initialValue: nil)
        self._constructionPlaneRenameText = State(initialValue: "")
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
                    curveCurvatureDisplays: session.document.productMetadata.curveCurvatureDisplays,
                    pointDisplays: session.document.productMetadata.pointDisplays,
                    snapResolutionOptions: activeSnapResolutionOptions(),
                    canvasDragPreviewKind: canvasDragPreviewKind,
                    canvasDragAxisConstraint: activeCanvasDragAxisConstraint,
                    canvasDragSketchPlaneOverride: workspacePlaneMode.sketchPlane,
                    projectionRequest: viewportProjectionRequest,
                    selectionHitPolicy: selectionScope.viewportSelectionHitPolicy,
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
                    onSplineControlPointDrag: viewportSplineControlPointDragHandler,
                    onSplineControlPointSlideDrag: viewportSplineControlPointSlideDragHandler,
                    onPolySplineSurfaceVertexDrag: viewportPolySplineSurfaceVertexDragHandler,
                    onSurfaceControlPointDrag: viewportSurfaceControlPointDragHandler,
                    onPolySplineSurfaceVertexSlideDrag: viewportPolySplineSurfaceVertexSlideDragHandler,
                    onSurfaceControlPointSlideDrag: viewportSurfaceControlPointSlideDragHandler,
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
                    .padding(.top, 12)
                    .padding(.horizontal, 14)
            }
            .overlay(alignment: .leading) {
                floatingToolPalette
                    .padding(.leading, 14)
            }
            .overlay(alignment: .trailing) {
                workspaceUtilityRail
                    .padding(.trailing, 14)
            }
            .overlay(alignment: .bottom) {
                viewportContextPanel
                    .padding(.bottom, 14)
                    .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .focusable()
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
              selectedSlotSourceLineTarget != nil else {
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
            let unit = session.document.displayUnit
            let value = unit.value(fromMeters: lengthMeters)
                .formatted(.number.precision(.fractionLength(0...4)))
            return "\(focus.statusTitle) \(value) \(unit.symbol)"
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
            let unit = session.document.displayUnit
            let value = unit.value(fromMeters: widthMeters)
                .formatted(.number.precision(.fractionLength(0...4)))
            return "\(focus.statusTitle) \(value) \(unit.symbol)"
        case .height:
            guard let heightMeters = session.sketchInputState.dimensionInputHeightMeters else {
                return focus.statusTitle
            }
            let unit = session.document.displayUnit
            let value = unit.value(fromMeters: heightMeters)
                .formatted(.number.precision(.fractionLength(0...4)))
            return "\(focus.statusTitle) \(value) \(unit.symbol)"
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
        HStack(spacing: 10) {
            Label(documentTitle, systemImage: "cube.transparent")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)

            workspaceDivider

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

            workspaceStatusChip(
                session.document.displayUnit.symbol,
                systemImage: "ruler",
                tint: .secondary
            )

            Spacer(minLength: 12)

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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 760)
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

    private var floatingToolPalette: some View {
        WorkspaceToolPalette(
            selectedTool: session.selectedTool,
            activate: { activateTool($0) },
            help: { toolHelp(for: $0) },
            accessibilityIdentifier: { canvasToolIdentifier(for: $0) }
        )
    }

    private var workspaceUtilityRail: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                }
                workspaceValueRow("Step", formatted(session.document.ruler.minorTickMeters))
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
        .padding(10)
        .frame(width: 178, alignment: .topLeading)
        .workspaceGlassContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceUtilityRail")
    }

    private var viewportContextPanel: some View {
        HStack(spacing: 10) {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .workspaceGlassContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanel")
    }

    @ViewBuilder
    private func selectionContextPanelContent(_ nodes: [SceneNode]) -> some View {
        let primaryNode = nodes.last
        Label(primaryNode?.name ?? "Selection", systemImage: "scope")
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: 180, alignment: .leading)

        workspaceContextDivider

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

        if let slotTarget = selectedSlotSourceLineTarget {
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
            let nodeTranslation = translation(for: node)
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
        _ input: (target: SelectionTarget, controlPointIndexes: [Int])
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
        let supportResolution = edgeOffsetSupportResolution(for: targets)
        WorkspaceEdgeOffsetContextPanel(
            isSupported: supportResolution.isSupported,
            distanceTitle: formatted(edgeOffsetDistanceMeters),
            gapFillTitle: regionOffsetGapFillTitle(edgeOffsetGapFill),
            inputModeTitle: edgeOffsetCommandState.inputModeTitle,
            lockedDistanceTitle: edgeOffsetCommandState.usesLockedDistance ? "On" : "Off",
            supportTitle: edgeOffsetSupportTitle(supportResolution),
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
                Text(entry.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .fill(entry.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    entry.isActive ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.10),
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
                        value: workspaceSketchLengthInputBinding,
                        formatter: inspectorNumberFormatter
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 54)
                    Text(session.document.displayUnit.symbol)
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
                        value: workspaceSketchWidthInputBinding,
                        formatter: inspectorNumberFormatter
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 54)
                    Text(session.document.displayUnit.symbol)
                        .foregroundStyle(.secondary)
                case .height:
                    TextField(
                        focus.statusTitle,
                        value: workspaceSketchHeightInputBinding,
                        formatter: inspectorNumberFormatter
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 54)
                    Text(session.document.displayUnit.symbol)
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

    private var workspaceSketchLengthInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let unit = session.document.displayUnit
                return unit.value(fromMeters: session.sketchInputState.dimensionInputLengthMeters ?? 0.0)
            },
            set: { value in
                let unit = session.document.displayUnit
                _ = session.setSketchDimensionInputLength(unit.meters(from: value))
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

    private var workspaceSketchWidthInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let unit = session.document.displayUnit
                return unit.value(fromMeters: session.sketchInputState.dimensionInputWidthMeters ?? 0.0)
            },
            set: { value in
                let unit = session.document.displayUnit
                _ = session.setSketchDimensionInputWidth(unit.meters(from: value))
            }
        )
    }

    private var workspaceSketchHeightInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let unit = session.document.displayUnit
                return unit.value(fromMeters: session.sketchInputState.dimensionInputHeightMeters ?? 0.0)
            },
            set: { value in
                let unit = session.document.displayUnit
                _ = session.setSketchDimensionInputHeight(unit.meters(from: value))
            }
        )
    }

    @ViewBuilder
    private var workspaceDimensionInputField: some View {
        if let entry = dimensionCommandState.activeEntry {
            HStack(spacing: 5) {
                Text(entry.label)
                    .foregroundStyle(.secondary)
                TextField(
                    entry.label,
                    value: workspaceDimensionInputBinding,
                    formatter: inspectorNumberFormatter
                )
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                Text(dimensionInputUnitSymbol(entry.valueKind))
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

    private var workspaceDimensionInputBinding: Binding<Double> {
        Binding<Double>(
            get: {
                guard let entry = dimensionCommandState.activeEntry else {
                    return 0.0
                }
                return displayedDimensionValue(
                    dimensionCommandState.currentValue ?? 0.0,
                    kind: entry.valueKind
                )
            },
            set: { value in
                guard let entry = dimensionCommandState.activeEntry else {
                    return
                }
                dimensionCommandState.setDraftValue(
                    modelDimensionValue(value, kind: entry.valueKind)
                )
            }
        )
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
            guard let sceneNodeID = sceneNodeID(for: hit) else {
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

        let snappedInput = snappedModelInput(target.modelPoint, modifierFlags: target.modifierFlags)
        let result = session.activateSelectedToolFromCanvas(
            targetSceneNodeID: targetSceneNodeID,
            modelPoint: snappedInput.point,
            modelWorldPoint: snappedInput.topologyWorldPoint ?? target.modelWorldPoint,
            sketchPlane: effectiveSketchPlane(fallback: target.sketchPlane)
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func handleWorkspaceKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if let snapOverrideResult = handleSnapOverrideKeyPress(keyPress) {
            return snapOverrideResult
        }
        guard keyPress.phase.contains(.down) || keyPress.phase.contains(.repeat) else {
            return .ignored
        }
        if let constructionPlaneResult = handleConstructionPlaneKeyPress(keyPress) {
            return constructionPlaneResult
        }

        guard !keyPress.modifiers.contains(.command),
              !keyPress.modifiers.contains(.control),
              !keyPress.modifiers.contains(.option) else {
            return .ignored
        }

        if let dimensionResult = handleDimensionKeyPress(keyPress) {
            return dimensionResult
        }

        if keyPress.key == .tab,
           usesSketchAxisConstraint {
            _ = session.focusNextSketchDimensionInput(
                availableFocuses: activeSketchDimensionInputFocuses
            )
            return .handled
        }

        let key = keyPress.characters.lowercased()
        if let offsetCurveResult = handleOffsetCurveKeyPress(key) {
            return offsetCurveResult
        }

        if let slideCommandResult = handleSlideCommandKeyPress(keyPress) {
            return slideCommandResult
        }

        if session.selectedTool == .polygon {
            switch keyPress.key {
            case .upArrow:
                _ = session.adjustPolygonSideCount(by: 1)
                return .handled
            case .downArrow:
                _ = session.adjustPolygonSideCount(by: -1)
                return .handled
            default:
                break
            }
        }

        if usesSketchAxisConstraint,
           let axisConstraint = SketchAxisConstraint(rawValue: key) {
            _ = session.toggleSketchAxisConstraint(axisConstraint)
            return .handled
        }

        guard session.selectedTool == .polygon else {
            return .ignored
        }

        switch key {
        case "c":
            _ = session.togglePolygonSizingMode()
            return .handled
        case "v":
            _ = session.togglePolygonInclinationMode()
            return .handled
        case "k":
            _ = session.togglePolygonCutsFaces()
            return .handled
        default:
            return .ignored
        }
    }

    private func handleSnapOverrideKeyPress(_ keyPress: KeyPress) -> KeyPress.Result? {
        guard keyPress.characters.lowercased() == "x" else {
            return nil
        }
        if keyPress.phase.contains(.up) {
            snapOverrideState.endCandidateKindBypass()
            return .handled
        }
        guard (keyPress.phase.contains(.down) || keyPress.phase.contains(.repeat)),
              keyPress.modifiers.contains(.shift),
              !keyPress.modifiers.contains(.command),
              !keyPress.modifiers.contains(.control),
              !keyPress.modifiers.contains(.option) else {
            return nil
        }
        return snapOverrideState.beginCandidateKindBypass() ? .handled : .ignored
    }

    private func handleDimensionKeyPress(_ keyPress: KeyPress) -> KeyPress.Result? {
        if dimensionCommandState.isActive {
            switch keyPress.key {
            case .tab:
                dimensionCommandState.handleTab()
                return .handled
            case .return:
                commitDimensionCommand()
                return .handled
            case .escape:
                dimensionCommandState.deactivate()
                return .handled
            default:
                break
            }
        }

        guard session.selectedTool == .select,
              keyPress.characters == "=" else {
            return nil
        }
        activateDimensionCommand()
        return .handled
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

    private func handleSlideCommandKeyPress(_ keyPress: KeyPress) -> KeyPress.Result? {
        guard session.selectedTool == .select else {
            return nil
        }

        let key = keyPress.characters.lowercased()
        if key == "g", keyPress.modifiers.contains(.shift) {
            activateSlideCommand()
            return .handled
        }

        guard selectionScope == .sketchEntity,
              slideCommandState.isCurveControlVerticesActive,
              let input = selectedSplineControlPointSlideInput() else {
            if selectionScope == .vertex,
               slideCommandState.isSurfaceControlVerticesActive {
                let vertexTargets = selectedPolySplineSurfaceVertexTargets
                let referenceTargets = selectedSurfaceControlPointReferences
                guard vertexTargets.isEmpty == false || referenceTargets.isEmpty == false else {
                    return nil
                }
                let direction: PolySplineSurfaceVertexSlideDirection
                switch key {
                case "u":
                    direction = keyPress.modifiers.contains(.shift) ? .negativeU : .positiveU
                case "n":
                    direction = .normal
                case "v":
                    direction = keyPress.modifiers.contains(.shift) ? .negativeV : .positiveV
                default:
                    return nil
                }
                if referenceTargets.isEmpty == false {
                    slideSelectedSurfaceControlPoints(
                        referenceTargets,
                        direction: direction
                    )
                } else {
                    slideSelectedPolySplineSurfaceVertices(
                        vertexTargets,
                        direction: direction
                    )
                }
                return .handled
            }
            return nil
        }

        let direction: SplineControlPointSlideDirection
        switch key {
        case "u":
            direction = keyPress.modifiers.contains(.shift) ? .negativeU : .positiveU
        case "n":
            direction = .normal
        default:
            return nil
        }

        slideSelectedSplineControlPoints(
            input.target,
            controlPointIndexes: input.controlPointIndexes,
            direction: direction
        )
        return .handled
    }

    private func handleConstructionPlaneKeyPress(_ keyPress: KeyPress) -> KeyPress.Result? {
        guard session.selectedTool == .select,
              keyPress.key == .space,
              !keyPress.modifiers.contains(.command),
              !keyPress.modifiers.contains(.option) else {
            return nil
        }
        if keyPress.modifiers.contains(.control) {
            return handleViewAlignedConstructionPlaneKeyPress(keyPress)
        }
        guard let targets = selectedConstructionPlaneTargets else {
            return nil
        }
        let alignsView = !keyPress.modifiers.contains(.shift)
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

    private func handleViewAlignedConstructionPlaneKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let viewNormal = viewportProjectionBasis.viewNormal else {
            session.reportToolStatus(
                "View-aligned construction plane requires a resolved viewport normal.",
                severity: .warning
            )
            isPreviewExpanded = true
            return .handled
        }

        if keyPress.modifiers.contains(.shift) {
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
        let snappedPoint = snappedModelPoint(target.modelPoint, modifierFlags: target.modifierFlags)
        let sketchPlane = effectiveSketchPlane(fallback: target.sketchPlane)
        let origin: Point3D
        do {
            origin = try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: snappedPoint)
        } catch {
            viewAlignedConstructionPlaneRequest = nil
            session.reportToolStatus(
                "View-aligned construction plane origin could not be resolved.",
                severity: .warning
            )
            isPreviewExpanded = true
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

    private func handleOffsetCurveKeyPress(_ key: String) -> KeyPress.Result? {
        guard session.selectedTool == .select else {
            return nil
        }

        switch key {
        case "o":
            if selectedEdgeTargets.isEmpty == false {
                activateEdgeOffsetCommand()
            } else if selectedRegionTargets.isEmpty == false {
                activateRegionOffsetCommand()
            } else if selectedSlotSourceLineTarget != nil {
                activateSlotProfileCommand()
            } else {
                activateRegionOffsetCommand()
            }
            return .handled
        case "d":
            if slotProfileCommandState.isActive {
                slotProfileCommandState.activateWidthInput()
                return .handled
            }
            if edgeOffsetCommandState.isActive {
                edgeOffsetCommandState.activateDistanceInput()
                return .handled
            }
            guard regionOffsetCommandState.isActive else {
                return nil
            }
            regionOffsetCommandState.activateDistanceInput()
            return .handled
        case "v":
            if edgeOffsetCommandState.isActive {
                edgeOffsetGapFill = edgeOffsetCommandState.gapFill(after: edgeOffsetGapFill)
                return .handled
            }
            guard regionOffsetCommandState.isActive else {
                return nil
            }
            regionOffsetGapFill = regionOffsetCommandState.gapFill(after: regionOffsetGapFill)
            return .handled
        case "s":
            if edgeOffsetCommandState.isActive {
                edgeOffsetCommandState.toggleLockedDistance()
                return .handled
            }
            guard regionOffsetCommandState.isActive else {
                return nil
            }
            regionOffsetCommandState.toggleLockedDistance()
            return .handled
        case "i":
            guard regionOffsetCommandState.isActive else {
                return nil
            }
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
        default:
            return nil
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
        let supportResolution = edgeOffsetSupportResolution(for: selectedEdgeTargets)
        if supportResolution.isSupported == false,
           let message = supportResolution.diagnosticMessage {
            session.reportToolStatus(message, severity: .warning)
            isPreviewExpanded = true
        }
    }

    private func activateSlotProfileCommand() {
        guard selectedSlotSourceLineTarget != nil else {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            session.reportToolStatus(
                "Slot requires a selected source line.",
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
        let startInput = snappedModelInput(drag.start, modifierFlags: drag.modifierFlags)
        let startPoint = startInput.point
        let constrainedEndPoint = activeCanvasDragAxisConstraint?.constrainedCanvasPoint(
            drag.end,
            from: startPoint,
            on: sketchPlane
        ) ?? drag.end
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
        let endWorldPoint = activeCanvasDragAxisConstraint == nil ? endInput.topologyWorldPoint : nil
        let dragEndWorldPoint = activeCanvasDragAxisConstraint == nil ? drag.endWorldPoint : nil
        let result = session.activateSelectedToolFromCanvasDrag(
            startModelPoint: startPoint,
            endModelPoint: endPoint,
            sketchPlane: sketchPlane,
            startWorldPoint: startInput.topologyWorldPoint ?? drag.startWorldPoint,
            endWorldPoint: endWorldPoint ?? dragEndWorldPoint
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func snappedModelPoint(
        _ point: Point2D,
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> Point2D {
        snappedModelInput(
            point,
            referencePoint: referencePoint,
            modifierFlags: modifierFlags
        ).point
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
        let interval = max(session.document.ruler.minorTickMeters, 1.0e-9)
        return SnapResolutionOptions(
            usesGrid: isGridSnapEnabled,
            usesObjects: isObjectTargetingEnabled,
            objectTargetingOverride: snapOverrideState.objectTargetingOverride(for: modifierFlags),
            suppressedCandidateKinds: snapOverrideState.suppressedCandidateKinds,
            usesConstructionPlaneProjection: isConstructionPlaneSnapEnabled,
            constructionPlane: constructionPlaneSnapPlane,
            gridIntervalMeters: interval,
            objectSearchRadiusMeters: max(min(interval * 2.0, 0.01), 1.0e-6),
            maximumCandidateCount: 16,
            referencePoint: referencePoint,
            referenceLineAnchors: session.sketchInputState.referenceLineAnchors
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
        guard let sceneNodeID = sceneNodeID(for: hit) else {
            return nil
        }
        if let component = directSelectionComponent(for: hit) {
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        }

        switch selectionScope {
        case .object:
            return SelectionTarget(sceneNodeID: sceneNodeID)
        case .face:
            guard let component = faceSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .edge:
            guard let component = edgeSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .vertex:
            guard let component = vertexSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .region:
            guard let component = directSelectionComponent(for: hit) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .sketchEntity:
            guard let component = sketchEntitySelectionComponent(for: hit) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        }
    }

    private func directSelectionComponent(for hit: ViewportHit) -> SelectionComponent? {
        guard let component = hit.selectionComponent else {
            return nil
        }
        switch (selectionScope, component) {
        case (.face, .face(_)),
             (.edge, .edge(_)),
             (.vertex, .vertex(_)),
             (.region, .region(_)),
             (.sketchEntity, .sketchEntity(_)):
            return component
        case (.object, _):
            return nil
        default:
            return nil
        }
    }

    private func sketchEntitySelectionComponent(for hit: ViewportHit) -> SelectionComponent? {
        guard hit.kind == .sketch,
              let sketchEntityID = hit.sketchEntityID else {
            return nil
        }
        if let controlPointIndex = hit.sketchControlPointIndex {
            return .sketchEntity(
                .sketchControlPoint(
                    featureID: hit.featureID,
                    entityID: sketchEntityID,
                    index: controlPointIndex
                )
            )
        }
        if let pointHandle = hit.sketchPointHandle {
            return .sketchEntity(
                .sketchPointHandle(
                    featureID: hit.featureID,
                    entityID: sketchEntityID,
                    handle: pointHandle
                )
            )
        }
        return .sketchEntity(
            .sketchEntity(
                featureID: hit.featureID,
                entityID: sketchEntityID
            )
        )
    }

    private func faceSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyFace = hit.bodyFace else {
            return nil
        }
        if let generatedComponentID = generatedTopologyComponentID(
            for: sceneNodeID,
            bodyFace: bodyFace
        ) {
            return .face(generatedComponentID)
        }
        return .face(selectionFace(for: bodyFace))
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyFace: ViewportBodyFace
    ) -> SelectionComponentID? {
        let bodyFace = coreBodyFace(for: bodyFace)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                bodyFace: bodyFace,
                in: session.document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func edgeSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyEdge = hit.bodyEdge else {
            return nil
        }
        if let generatedComponentID = generatedTopologyComponentID(
            for: sceneNodeID,
            bodyEdge: bodyEdge
        ) {
            return .edge(generatedComponentID)
        }
        return .edge(selectionEdge(for: bodyEdge))
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyEdge: ViewportBodyEdge
    ) -> SelectionComponentID? {
        let cornerEdge = bodyCornerEdge(for: bodyEdge)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                cornerEdge: cornerEdge,
                in: session.document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func vertexSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyVertex = hit.bodyVertex,
              let generatedComponentID = generatedTopologyComponentID(
                for: sceneNodeID,
                bodyVertex: bodyVertex
              ) else {
            return nil
        }
        return .vertex(generatedComponentID)
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyVertex: ViewportBodyVertex
    ) -> SelectionComponentID? {
        let cornerVertex = bodyCornerVertex(for: bodyVertex)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                cornerVertex: cornerVertex,
                in: session.document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func coreBodyFace(for bodyFace: ViewportBodyFace) -> BodyFace {
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

    private func bodyCornerEdge(for bodyEdge: ViewportBodyEdge) -> BodyCornerEdge {
        switch bodyEdge {
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

    private func bodyCornerVertex(for bodyVertex: ViewportBodyVertex) -> BodyCornerVertex {
        switch bodyVertex {
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

    private func selectionFace(for bodyFace: ViewportBodyFace) -> SelectionComponentID {
        switch bodyFace {
        case .front:
            return .bodyFaceFront
        case .back:
            return .bodyFaceBack
        case .top:
            return .bodyFaceTop
        case .bottom:
            return .bodyFaceBottom
        case .left:
            return .bodyFaceLeft
        case .right:
            return .bodyFaceRight
        case .side:
            return .bodyFaceSide
        }
    }

    private func selectionEdge(for bodyEdge: ViewportBodyEdge) -> SelectionComponentID {
        switch bodyEdge {
        case .leftBottom:
            return .bodyEdgeLeftBottom
        case .rightBottom:
            return .bodyEdgeRightBottom
        case .rightTop:
            return .bodyEdgeRightTop
        case .leftTop:
            return .bodyEdgeLeftTop
        }
    }

    private func uniqueObjectTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        guard selectionScope == .object else {
            return []
        }
        var targets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for hit in hits {
            guard let id = sceneNodeID(for: hit) else {
                continue
            }
            let target = SelectionTarget(sceneNodeID: id)
            guard seenTargets.insert(target).inserted else {
                continue
            }
            targets.append(target)
        }
        return targets
    }

    private func selectionTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        switch selectionScope {
        case .object:
            uniqueObjectTargets(for: hits)
        case .sketchEntity:
            uniqueSketchEntityTargets(for: hits)
        case .face,
             .edge,
             .vertex,
             .region:
            uniqueSelectionTargets(for: hits)
        }
    }

    private func uniqueSketchEntityTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        let targets = uniqueSelectionTargets(for: hits)
        let pointTargets = targets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else {
                return false
            }
            return componentID.sketchPointReference != nil
        }
        return pointTargets.isEmpty ? targets : pointTargets
    }

    private func uniqueSelectionTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        var targets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for hit in hits {
            guard let target = selectionTarget(for: hit),
                  seenTargets.insert(target).inserted else {
                continue
            }
            targets.append(target)
        }
        return targets
    }

    private func sceneNodeID(for hit: ViewportHit) -> SceneNodeID? {
        if let sceneNodeID = hit.sceneNodeID,
           session.document.productMetadata.sceneNodes[sceneNodeID] != nil {
            return sceneNodeID
        }
        let expectedKind: SceneNodeReference.Kind = switch hit.kind {
        case .sketch:
            .sketch
        case .body:
            .body
        }

        for row in sceneBrowserRows {
            guard let reference = session.document.productMetadata.sceneNodes[row.id]?.reference else {
                continue
            }
            if reference.kind == expectedKind, reference.featureID == hit.featureID {
                return row.id
            }
        }

        for row in sceneBrowserRows {
            guard let reference = session.document.productMetadata.sceneNodes[row.id]?.reference else {
                continue
            }
            if reference.featureID == hit.featureID {
                return row.id
            }
        }
        return nil
    }

    private func setHoveredSceneNode(_ id: SceneNodeID?) {
        guard session.selection.hoveredSceneNodeID != id else {
            return
        }
        _ = session.hoverSceneNode(id)
    }

    private func setHoveredTarget(_ target: SelectionTarget?) {
        guard session.selection.hoveredTarget != target else {
            return
        }
        _ = session.hoverTarget(target)
    }

    private func setHoveredReference(_ reference: SelectionReference?) {
        guard session.selection.hoveredReference != reference else {
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
        let targets = selectedFaceTargets
        guard targets.count == 1 else {
            return nil
        }
        return targets.first
    }

    private var selectedFaceTargets: [SelectionTarget] {
        let targets = session.selection.selectedTargets
        return targets.filter { target in
            if case .face = target.component {
                return true
            }
            return false
        }
    }

    private var selectedObjectDimensionTargets: [SelectionTarget] {
        session.selection.selectedTargets.filter { target in
            switch target.component {
            case .object, .face:
                return true
            case .edge, .vertex, .sketchEntity, .region:
                return false
            }
        }
    }

    private var selectedSketchDimensionTargets: [SelectionTarget] {
        session.selection.selectedTargets.filter { target in
            switch target.component {
            case .sketchEntity:
                return true
            case .edge(let componentID):
                return componentID.generatedTopologyPersistentName != nil
            case .object, .face, .vertex, .region:
                return false
            }
        }
    }

    private var selectedEdgeTargets: [SelectionTarget] {
        session.selection.selectedTargets.filter { target in
            if case .edge = target.component {
                return true
            }
            return false
        }
    }

    private var selectedEdgeOffsetSupportResolution: EdgeOffsetSupportFaceResolution {
        edgeOffsetSupportResolution(for: selectedEdgeTargets)
    }

    private func edgeOffsetSupportResolution(
        for targets: [SelectionTarget]
    ) -> EdgeOffsetSupportFaceResolution {
        guard targets.count == 1,
              let target = targets.first else {
            return .unavailable("Offset Edge currently supports one selected edge.")
        }
        do {
            return try EdgeOffsetSupportFaceResolver().resolve(
                edgeTarget: target,
                selection: session.selection,
                document: session.document,
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            return .unavailable(error.message)
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    private func edgeOffsetSupportTitle(
        _ resolution: EdgeOffsetSupportFaceResolution
    ) -> String {
        switch (resolution.status, resolution.source) {
        case (.supported, .selectedFace):
            return "Selected Face"
        case (.supported, .inferredCapFace):
            return "Cap Face"
        case (.ambiguous, _):
            return "Ambiguous"
        case (.unavailable, _):
            return "Missing"
        case (.notApplicable, _):
            return "Unsupported"
        case (.supported, nil):
            return "Ready"
        }
    }

    private var selectedVertexTarget: SelectionTarget? {
        let targets = selectedVertexTargets
        guard targets.count == 1, let target = targets.first else {
            return nil
        }
        return target
    }

    private var selectedVertexTargets: [SelectionTarget] {
        session.selection.selectedTargets.filter { target in
            if case .vertex = target.component {
                return true
            }
            return false
        }
    }

    private var selectedPolySplineSurfaceVertexTargets: [SelectionTarget] {
        selectedVertexTargets.filter(\.isGeneratedPolySplineSurfaceVertex)
    }

    private var selectedSurfaceControlPointReferences: [SelectionReference] {
        session.selection.selectedReferences.filter { reference in
            if case .surface(.controlPoint) = reference {
                return true
            }
            return false
        }
    }

    private var selectedSketchPointTargets: [SelectionTarget] {
        let sketchEntityTargets = session.selection.selectedTargets.filter { target in
            if case .sketchEntity = target.component {
                return true
            }
            return false
        }
        guard sketchEntityTargets.isEmpty == false else {
            return []
        }
        let explicitPointTargets = sketchEntityTargets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else {
                return false
            }
            return componentID.sketchPointReference != nil
        }
        do {
            let pointTargets = try SketchEntitySummaryService()
                .summarize(document: session.document)
                .entries
                .filter { $0.entityKind == "point" }
                .compactMap { $0.selectionTarget() }
            let pointTargetSet = Set(pointTargets)
            return sketchEntityTargets.filter { target in
                if explicitPointTargets.contains(target) {
                    return true
                }
                return pointTargetSet.contains(target)
            }
        } catch {
            return explicitPointTargets
        }
    }

    private var selectedRegionTargets: [SelectionTarget] {
        session.selection.selectedTargets.filter { target in
            if case .region = target.component {
                return true
            }
            return false
        }
    }

    private var selectedConstructionPlaneTargets: [SelectionTarget]? {
        let targets = session.selection.selectedTargets
        guard targets.isEmpty == false else {
            return nil
        }
        let faceTargets = selectedFaceTargets
        let edgeTargets = selectedEdgeTargets
        let regionTargets = selectedRegionTargets
        let pointTargets = selectedVertexTargets + selectedSketchPointTargets
        if targets.count == 1,
           faceTargets.count == 1 || regionTargets.count == 1 {
            return targets
        }
        if targets.count == 2,
           faceTargets.count == 1,
           edgeTargets.count == 1 {
            return targets
        }
        if targets.count >= 2,
           edgeTargets.isEmpty,
           targets.count == faceTargets.count + regionTargets.count {
            return targets
        }
        if targets.count >= 2,
           targets.count == pointTargets.count {
            return targets
        }
        return nil
    }

    private var selectedSlotSourceLineTarget: SelectionTarget? {
        switch selectedSketchEntityResult {
        case .success(let entity):
            guard entity?.entityKind == "line" else {
                return nil
            }
            return entity?.target
        case .failure:
            return nil
        }
    }

    private var selectedSketchVertexOffsetTarget: SelectionTarget? {
        switch selectedSketchEntityResult {
        case .success(let entity):
            guard let entity,
                  selectedSketchVertexOffsetHandle(entity) != nil else {
                return nil
            }
            return entity.target
        case .failure:
            return nil
        }
    }

    private func selectedSketchEntityCutterTarget(
        excluding target: SelectionTarget
    ) -> SelectionTarget? {
        session.selection.selectedTargets.first { candidate in
            guard candidate != target,
                  case .sketchEntity = candidate.component,
                  let kind = sketchEntityKind(for: candidate),
                  ["line", "circle", "arc"].contains(kind) else {
                return false
            }
            return true
        }
    }

    private func selectedSketchCornerTreatmentAdjacentTarget(
        excluding target: SelectionTarget
    ) -> SelectionTarget? {
        session.selection.selectedTargets.first { candidate in
            guard candidate != target,
                  case .sketchEntity = candidate.component,
                  let kind = sketchEntityKind(for: candidate),
                  ["line", "arc"].contains(kind) else {
                return false
            }
            return true
        }
    }

    private func sketchCurveJoinInspectorState(
        for entity: InspectorSketchEntity
    ) -> SketchCurveJoinInspectorState {
        var entityKindsByTarget: [SelectionTarget: String] = [:]
        for target in session.selection.selectedTargets {
            entityKindsByTarget[target] = sketchEntityKind(for: target)
        }
        return SketchCurveJoinInspectorState(
            entityKind: entity.entityKind,
            sourceFeatureID: entity.sourceFeatureID,
            entityID: entity.entityID,
            target: entity.target,
            joinedCurveSourceID: entity.joinedCurveSourceID,
            joinedCurveGroupSourceID: entity.joinedCurveGroupSourceID,
            selectedTargets: session.selection.selectedTargets,
            entityKindsByTarget: entityKindsByTarget
        )
    }

    private var selectedSketchEntityResult: Result<InspectorSketchEntity?, Error> {
        do {
            return .success(try resolveSelectedSketchEntity())
        } catch {
            return .failure(error)
        }
    }

    private var selectedSurfaceControlPointInspectorStateResult:
        Result<SurfaceControlPointInspectorState?, Error> {
        guard !selectedSurfaceControlPointReferences.isEmpty else {
            return .success(nil)
        }
        do {
            let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
            guard let state = SurfaceControlPointInspectorState(
                selectedReferences: selectedSurfaceControlPointReferences,
                summaryResult: summary
            ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selected surface control point references could not be resolved in the current surface source summary."
                )
            }
            return .success(state)
        } catch {
            return .failure(error)
        }
    }

    private var selectedSurfaceContinuitySummary: RupaCore.SurfaceContinuityResult? {
        switch selectedSurfaceContinuitySummaryResult(for: selectedSceneNodes) {
        case .success(let summary):
            return summary
        case .failure:
            return nil
        }
    }

    private var selectedSurfaceAnalysisSummary: SurfaceAnalysisResult? {
        switch selectedSurfaceAnalysisSummaryResult(for: selectedSceneNodes) {
        case .success(let summary):
            return summary
        case .failure:
            return nil
        }
    }

    private func selectedSurfaceAnalysisSummaryResult(
        for nodes: [SceneNode]
    ) -> Result<SurfaceAnalysisResult?, Error> {
        do {
            return .success(try resolveSelectedSurfaceAnalysisSummary(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    private func selectedSurfaceAnalysisResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceAnalysis?, Error> {
        do {
            return .success(try resolveSelectedSurfaceAnalysis(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    private func selectedSurfaceContinuitySummaryResult(
        for nodes: [SceneNode]
    ) -> Result<RupaCore.SurfaceContinuityResult?, Error> {
        do {
            return .success(try resolveSelectedSurfaceContinuitySummary(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    private func selectedSurfaceContinuityResult(
        for nodes: [SceneNode]
    ) -> Result<InspectorSurfaceContinuity?, Error> {
        do {
            return .success(try resolveSelectedSurfaceContinuity(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    private var defaultFaceOffsetStepMeters: Double {
        0.001
    }

    private var defaultEdgeChamferStepMeters: Double {
        0.001
    }

    private var defaultEdgeFilletRadiusMeters: Double {
        0.001
    }

    private var defaultVertexMoveStepMeters: Double {
        0.001
    }

    private var defaultSketchEntityMoveStepMeters: Double {
        0.001
    }

    @ViewBuilder
    private func sketchCurveExtendControls(_ entity: InspectorSketchEntity) -> some View {
        lengthControl(
            "Extend",
            meters: sketchExtendDistanceMeters,
            sliderRange: lengthSliderRange(for: sketchExtendDistanceMeters)
        ) { meters in
            sketchExtendDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorControlRow("Shape") {
            Picker("", selection: $sketchExtendShape) {
                ForEach(ExtendCurveShape.allCases, id: \.self) { shape in
                    Text(extendCurveShapeTitle(shape)).tag(shape)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("InspectorCurve.extendShape")
        }
        inspectorActionRow {
            Button {
                extendSelectedSketchCurve(entity.target)
            } label: {
                Label("Extend", systemImage: "arrow.up.right.line")
            }
            .disabled(canExtendSketchCurve(entity) == false)
            .accessibilityIdentifier("InspectorCurve.extend")
        }
    }

    private func canExtendSketchCurve(_ entity: InspectorSketchEntity) -> Bool {
        guard case .sketchEntity(let componentID) = entity.target.component else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.entityID == entity.entityID else {
                return false
            }
            switch (entity.entityKind, reference.handle) {
            case ("line", .lineStart),
                 ("line", .lineEnd),
                 ("arc", .arcStart),
                 ("arc", .arcEnd):
                return true
            default:
                return false
            }
        }
        if let reference = componentID.sketchControlPointReference {
            guard entity.entityKind == "spline",
                  reference.entityID == entity.entityID else {
                return false
            }
            return reference.index == 0 || reference.index == entity.controlPoints.count - 1
        }
        return false
    }

    @ViewBuilder
    private func sketchVertexOffsetControls(_ entity: InspectorSketchEntity) -> some View {
        lengthControl(
            "Vertex Offset",
            meters: sketchVertexOffsetDistanceMeters,
            sliderRange: lengthSliderRange(for: sketchVertexOffsetDistanceMeters)
        ) { meters in
            sketchVertexOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorActionRow {
            Button {
                offsetSelectedSketchVertex(entity)
            } label: {
                Label("Offset Vertex", systemImage: "arrow.left.and.right")
            }
            .disabled(selectedSketchVertexOffsetHandle(entity) == nil)
            .accessibilityIdentifier("InspectorCurve.offsetVertex")
        }
    }

    private func selectedSketchVertexOffsetHandle(_ entity: InspectorSketchEntity) -> SketchEntityPointHandle? {
        SketchVertexOffsetInspectorState(
            entityKind: entity.entityKind,
            entityID: entity.entityID,
            target: entity.target
        )
        .handle
    }

    @ViewBuilder
    private func sketchCornerTreatmentControls(_ entity: InspectorSketchEntity) -> some View {
        lengthControl(
            "Corner",
            meters: sketchCornerTreatmentDistanceMeters,
            sliderRange: lengthSliderRange(for: sketchCornerTreatmentDistanceMeters)
        ) { meters in
            sketchCornerTreatmentDistanceMeters = max(meters, 1.0e-9)
        }
        inspectorControlRow("Treatment") {
            Picker("", selection: $sketchCornerTreatment) {
                ForEach(SketchCornerTreatment.allCases, id: \.self) { treatment in
                    Text(sketchCornerTreatmentTitle(treatment)).tag(treatment)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.cornerTreatment")
        }
        inspectorActionRow {
            Button {
                applySelectedSketchCornerTreatment(entity.target)
            } label: {
                Label(
                    sketchCornerTreatmentTitle(sketchCornerTreatment),
                    systemImage: sketchCornerTreatment == .fillet ? "circle.dashed" : "line.diagonal"
                )
            }
            .disabled(canApplySketchCornerTreatment(entity) == false)
            .accessibilityIdentifier("InspectorCurve.cornerTreatment.apply")
        }
    }

    @ViewBuilder
    private func sketchCurveJoinControls(_ entity: InspectorSketchEntity) -> some View {
        let joinState = sketchCurveJoinInspectorState(for: entity)
        inspectorControlRow("Continuity") {
            Picker("", selection: $sketchCurveJoinContinuity) {
                ForEach([SketchCurveJoinContinuity.g0, .g1], id: \.self) { continuity in
                    Text(sketchCurveJoinContinuityTitle(continuity)).tag(continuity)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).joinContinuity")
        }
        inspectorActionRow {
            Button {
                joinSelectedSketchCurves(entity)
            } label: {
                Label("Join", systemImage: "link.badge.plus")
            }
            .disabled(!joinState.canJoin)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).join")

            Button {
                unjoinSelectedSketchCurve(entity)
            } label: {
                Label("Unjoin", systemImage: "link.badge.minus")
            }
            .disabled(!joinState.canUnjoin)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).unjoin")
        }
    }

    private func sketchCurveJoinContinuityTitle(_ continuity: SketchCurveJoinContinuity) -> String {
        switch continuity {
        case .g0:
            "G0"
        case .g1:
            "G1"
        case .g2:
            "G2"
        }
    }

    @ViewBuilder
    private func sketchVertexAlignmentControls(_ entity: InspectorSketchEntity) -> some View {
        inspectorControlRow("Align") {
            Picker("", selection: $sketchVertexAlignmentContinuity) {
                ForEach(SketchVertexAlignmentContinuity.allCases, id: \.self) { continuity in
                    Text(sketchVertexAlignmentContinuityTitle(continuity)).tag(continuity)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).alignContinuity")
        }
        inspectorActionRow {
            Button {
                alignSelectedSketchVertex(entity)
            } label: {
                Label("Align", systemImage: "arrow.triangle.merge")
            }
            .disabled(selectedSketchVertexAlignmentReferenceTarget(for: entity) == nil)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).alignVertex")
        }
    }

    private func sketchVertexAlignmentContinuityTitle(_ continuity: SketchVertexAlignmentContinuity) -> String {
        switch continuity {
        case .g0:
            "G0"
        case .g1:
            "G1"
        case .g2:
            "G2"
        }
    }

    private func selectedSketchVertexAlignmentReferenceTarget(
        for entity: InspectorSketchEntity
    ) -> SelectionTarget? {
        guard isSketchVertexAlignmentTarget(entity.target, entityKind: entity.entityKind) else {
            return nil
        }
        let referenceTargets = session.selection.selectedTargets.filter { target in
            guard target != entity.target,
                  let entityKind = sketchEntityKind(for: target) else {
                return false
            }
            return isSketchVertexAlignmentTarget(target, entityKind: entityKind)
        }
        guard referenceTargets.count == 1 else {
            return nil
        }
        return referenceTargets.first
    }

    private func isSketchVertexAlignmentTarget(
        _ target: SelectionTarget,
        entityKind: String
    ) -> Bool {
        guard case .sketchEntity(let componentID) = target.component else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference {
            switch (entityKind, reference.handle) {
            case ("point", .point),
                 ("line", .lineStart),
                 ("line", .lineEnd),
                 ("arc", .arcStart),
                 ("arc", .arcEnd):
                return true
            default:
                return false
            }
        }
        if let reference = componentID.sketchControlPointReference,
           entityKind == "spline",
           let controlPointCount = sketchSplineControlPointCount(for: target) {
            return reference.index == 0 || reference.index == controlPointCount - 1
        }
        return false
    }

    private func sketchSplineControlPointCount(for target: SelectionTarget) -> Int? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = sketchEntityReference(in: componentID),
              let sceneNode = session.document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = session.document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              case .spline(let spline) = sketch.entities[reference.entityID] else {
            return nil
        }
        return spline.controlPoints.count
    }

    private func sketchEntityReference(
        in componentID: SelectionComponentID
    ) -> (featureID: FeatureID, entityID: SketchEntityID)? {
        if let reference = componentID.sketchEntityReference {
            return reference
        }
        if let reference = componentID.sketchPointHandleReference {
            return (reference.featureID, reference.entityID)
        }
        if let reference = componentID.sketchControlPointReference {
            return (reference.featureID, reference.entityID)
        }
        return nil
    }

    @ViewBuilder
    private func sketchCurveProjectionControls(_ entity: InspectorSketchEntity) -> some View {
        inspectorActionRow {
            Button {
                projectSelectedSketchCurvesToConstructionPlane(entity)
            } label: {
                Label("Project", systemImage: "square.on.square")
            }
            .disabled(selectedSketchCurveProjectionTargets(for: entity).isEmpty)
            .accessibilityIdentifier("InspectorCurve.\(entity.entityKind).project")
        }
    }

    private func selectedSketchCurveProjectionTargets(
        for entity: InspectorSketchEntity
    ) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in session.selection.selectedTargets {
            guard let curveTarget = wholeSketchCurveTarget(for: target) else {
                continue
            }
            let key = "\(curveTarget.sceneNodeID.description):\(String(describing: curveTarget.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(curveTarget)
            }
        }
        if projectedTargets.isEmpty,
           let fallback = wholeSketchCurveTarget(for: entity.target) {
            projectedTargets.append(fallback)
        }
        return projectedTargets
    }

    private func wholeSketchCurveTarget(for target: SelectionTarget) -> SelectionTarget? {
        guard case .sketchEntity(let componentID) = target.component else {
            return nil
        }
        let reference = sketchEntityReference(in: componentID)
        guard let reference else {
            return nil
        }
        let curveTarget = SelectionTarget(
            sceneNodeID: target.sceneNodeID,
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: reference.featureID,
                    entityID: reference.entityID
                )
            )
        )
        guard let kind = sketchEntityKind(for: curveTarget),
              ["line", "circle", "arc", "spline"].contains(kind) else {
            return nil
        }
        return curveTarget
    }

    private func canApplySketchCornerTreatment(_ entity: InspectorSketchEntity) -> Bool {
        guard case .sketchEntity(let componentID) = entity.target.component,
              entity.entityKind == "line" || entity.entityKind == "arc" else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference,
           reference.entityID == entity.entityID {
            switch reference.handle {
            case .lineStart,
                 .lineEnd:
                return entity.entityKind == "line"
            case .arcStart,
                 .arcEnd:
                return entity.entityKind == "arc"
            case .point,
                 .circleCenter,
                 .arcCenter:
                return false
            }
        }
        guard componentID.sketchEntityReference?.entityID == entity.entityID else {
            return false
        }
        return selectedSketchCornerTreatmentAdjacentTarget(excluding: entity.target) != nil
    }

    private func extendCurveShapeTitle(_ shape: ExtendCurveShape) -> String {
        switch shape {
        case .natural:
            "Natural"
        case .linear:
            "Linear"
        case .soft:
            "Soft"
        case .reflective:
            "Reflective"
        case .arc:
            "Arc"
        }
    }

    private func sketchCornerTreatmentTitle(_ treatment: SketchCornerTreatment) -> String {
        switch treatment {
        case .fillet:
            "Fillet"
        case .chamfer:
            "Chamfer"
        }
    }

    private func resolveSelectedSketchEntity() throws -> InspectorSketchEntity? {
        guard let target = session.selection.primaryTarget,
              case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            return nil
        }
        guard let sceneNode = session.document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = session.document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selected source curve could not be resolved."
            )
        }
        let analysis = try inspectorCurveAnalysis(
            featureID: reference.featureID,
            entityID: reference.entityID
        )
        let joinedCurveSourceID = session.document.productMetadata.joinedCurveSources.values.first { source in
            source.featureID == reference.featureID && source.retainedEntityID == reference.entityID
        }?.id
        let joinedCurveGroupSource = session.document.productMetadata.joinedCurveGroupSources.values.first { source in
            source.featureID == reference.featureID && source.memberEntityIDs.contains(reference.entityID)
        }

        switch entity {
        case .point(let point):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "point",
                analysis: analysis,
                center: try resolvedSketchPoint(point)
            )
        case .line(let line):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "line",
                analysis: analysis,
                joinedCurveSourceID: joinedCurveSourceID,
                joinedCurveGroupSourceID: joinedCurveGroupSource?.id,
                joinedCurveGroupContinuity: joinedCurveGroupSource?.continuity,
                start: try resolvedSketchPoint(line.start),
                end: try resolvedSketchPoint(line.end)
            )
        case .circle(let circle):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "circle",
                analysis: analysis,
                center: try resolvedSketchPoint(circle.center),
                radius: try resolvedSketchValue(circle.radius, kind: .length)
            )
        case .arc(let arc):
            let center = try resolvedSketchPoint(arc.center)
            let radius = try resolvedSketchValue(arc.radius, kind: .length)
            let startAngle = try resolvedSketchValue(arc.startAngle, kind: .angle)
            let endAngle = try resolvedSketchValue(arc.endAngle, kind: .angle)
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "arc",
                analysis: analysis,
                joinedCurveGroupSourceID: joinedCurveGroupSource?.id,
                joinedCurveGroupContinuity: joinedCurveGroupSource?.continuity,
                start: pointOnSketchCircle(center: center, radius: radius, angle: startAngle),
                end: pointOnSketchCircle(center: center, radius: radius, angle: endAngle),
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        case .spline(let spline):
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedSketchPoint(point)
            }
            let bridgeCurve = try inspectorBridgeCurve(
                featureID: reference.featureID,
                entityID: reference.entityID
            )
            let smoothIndexes = Set(
                sketch.constraints.compactMap { constraint -> Int? in
                    guard case let .smoothSplineControlPoint(entityID, index) = constraint,
                          entityID == reference.entityID else {
                        return nil
                    }
                    return index
                }
            )
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "spline",
                analysis: analysis,
                bridgeCurve: bridgeCurve,
                start: controlPoints.first,
                end: controlPoints.last,
                controlPoints: controlPoints,
                smoothSplineControlPointIndexes: smoothIndexes,
                tangentLineCandidates: try inspectorLineCandidates(in: sketch, excluding: reference.entityID),
                tangentSplineEndpointCandidates: try inspectorSplineEndpointCandidates(
                    in: sketch,
                    excluding: reference.entityID
                ),
                startTangentLineIDs: splineEndpointTangentLineIDs(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endTangentLineIDs: splineEndpointTangentLineIDs(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                ),
                startTangentSplineEndpoints: tangentSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endTangentSplineEndpoints: tangentSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                ),
                startSmoothSplineEndpoints: smoothSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endSmoothSplineEndpoints: smoothSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                )
            )
        }
    }

    private func sketchEntityKind(for target: SelectionTarget) -> String? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityReference,
              let sceneNode = session.document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = session.document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            return nil
        }
        switch entity {
        case .point:
            return "point"
        case .line:
            return "line"
        case .circle:
            return "circle"
        case .arc:
            return "arc"
        case .spline:
            return "spline"
        }
    }

    private func resolveSelectedSurfaceAnalysis(
        for nodes: [SceneNode]
    ) throws -> InspectorSurfaceAnalysis? {
        guard let result = try resolveSelectedSurfaceAnalysisSummary(for: nodes) else {
            return nil
        }
        let faces = selectedSurfaceAnalysisFaces(result.faces, nodes: nodes)
        return InspectorSurfaceAnalysis(
            bSplineFaceCount: faces.count,
            sampleCount: faces.reduce(0) { $0 + $1.samples.count },
            uCurvatureCombCount: faces.reduce(0) { partial, face in
                partial + face.curvatureCombs.filter { $0.direction == .u }.count
            },
            vCurvatureCombCount: faces.reduce(0) { partial, face in
                partial + face.curvatureCombs.filter { $0.direction == .v }.count
            },
            trimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.count
            },
            innerTrimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.filter { $0.role == .inner }.count
            },
            openTrimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.filter { !$0.isClosed }.count
            },
            trimBoundaryEdgeCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.reduce(0) { boundaryPartial, boundary in
                    boundaryPartial + boundary.edgeCount
                }
            },
            faces: faces.map { face in
                InspectorSurfaceFaceAnalysis(
                    id: face.faceID,
                    facePersistentNames: face.facePersistentNames,
                    uDegree: face.uDegree,
                    vDegree: face.vDegree,
                    uControlPointCount: face.uControlPointCount,
                    vControlPointCount: face.vControlPointCount,
                    sampleCount: face.samples.count,
                    trimBoundaryCount: face.trimBoundaries.count,
                    innerTrimBoundaryCount: face.trimBoundaries.filter { $0.role == .inner }.count,
                    openTrimBoundaryCount: face.trimBoundaries.filter { !$0.isClosed }.count,
                    trimBoundaryEdgeCount: face.trimBoundaries.reduce(0) { partial, boundary in
                        partial + boundary.edgeCount
                    },
                    trimBoundaryLength: face.trimBoundaries.reduce(0.0) { partial, boundary in
                        partial + boundary.estimatedLength
                    },
                    maxUNormalChangePerLength: face.maxUNormalChangePerLength,
                    maxVNormalChangePerLength: face.maxVNormalChangePerLength,
                    maxNormalAngle: face.maxNormalAngle,
                    maxAbsUNormalCurvature: face.maxAbsUNormalCurvature,
                    maxAbsVNormalCurvature: face.maxAbsVNormalCurvature,
                    maxAbsPrincipalCurvature: face.maxAbsPrincipalCurvature,
                    maxAbsGaussianCurvature: face.maxAbsGaussianCurvature,
                    minimumPrincipalDirection: face.samples.first?.minimumPrincipalDirection,
                    maximumPrincipalDirection: face.samples.first?.maximumPrincipalDirection
                )
            },
            diagnostics: result.diagnostics
        )
    }

    private func resolveSelectedSurfaceAnalysisSummary(
        for nodes: [SceneNode]
    ) throws -> SurfaceAnalysisResult? {
        guard nodes.count == 1, let node = nodes.first else {
            return nil
        }
        let selectedPersistentNames = selectedGeneratedTopologyPersistentNames()
        guard selectedPersistentNames.isEmpty == false || node.object?.geometryRole == .surface else {
            return nil
        }

        let result = try SurfaceAnalysisService(
            options: surfaceAnalysisOptions.analysisOptions
        ).analyze(
            document: session.document,
            objectRegistry: objectRegistry,
            currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation
        )
        guard result.counts.bSplineFaceCount > 0 else {
            return nil
        }
        return result
    }

    private func selectedSurfaceAnalysisFaces(
        _ faces: [SurfaceAnalysisResult.FaceAnalysis],
        nodes: [SceneNode]
    ) -> [SurfaceAnalysisResult.FaceAnalysis] {
        let selectedPersistentNames = selectedGeneratedTopologyPersistentNames()
        if selectedPersistentNames.isEmpty == false {
            return faces.filter { face in
                surfaceAnalysisFace(face, containsAny: selectedPersistentNames)
            }
        }
        let selectedFeatureIDs = Set(
            nodes.compactMap { node -> String? in
                guard node.reference?.kind == .body else {
                    return nil
                }
                return node.reference?.featureID?.description
            }
        )
        guard selectedFeatureIDs.isEmpty == false else {
            return []
        }
        return faces.filter { face in
            guard let sourceFeatureID = face.sourceFeatureID else {
                return false
            }
            return selectedFeatureIDs.contains(sourceFeatureID)
        }
    }

    private func resolveSelectedSurfaceContinuity(
        for nodes: [SceneNode]
    ) throws -> InspectorSurfaceContinuity? {
        guard let result = try resolveSelectedSurfaceContinuitySummary(for: nodes) else {
            return nil
        }
        let selectedPersistentNames = selectedGeneratedTopologyPersistentNames()
        let adjacencies: [RupaCore.SurfaceContinuityResult.Adjacency]
        if selectedPersistentNames.isEmpty {
            adjacencies = result.adjacencies
        } else {
            adjacencies = result.adjacencies.filter { adjacency in
                surfaceAdjacency(adjacency, containsAny: selectedPersistentNames)
            }
        }
        return InspectorSurfaceContinuity(
            bSplineFaceCount: result.counts.bSplineFaceCount,
            sharedEdgeCount: result.counts.sharedEdgeCount,
            g0AdjacencyCount: result.counts.g0AdjacencyCount,
            g1AdjacencyCount: result.counts.g1AdjacencyCount,
            g2AdjacencyCount: result.counts.g2AdjacencyCount,
            unresolvedG2AdjacencyCount: result.counts.unresolvedG2AdjacencyCount,
            adjacencies: adjacencies.map { adjacency in
                InspectorSurfaceAdjacency(
                    id: adjacency.edgeID,
                    edgePersistentNames: adjacency.edgePersistentNames,
                    firstFacePersistentName: adjacency.firstFacePersistentName,
                    secondFacePersistentName: adjacency.secondFacePersistentName,
                    continuity: adjacency.continuity,
                    positionGap: adjacency.positionGap,
                    normalAngle: adjacency.normalAngle,
                    curvatureGap: adjacency.curvatureGap,
                    requiresCurvatureContinuitySolve: adjacency.requiresCurvatureContinuitySolve
                )
            },
            diagnostics: result.diagnostics
        )
    }

    private func resolveSelectedSurfaceContinuitySummary(
        for nodes: [SceneNode]
    ) throws -> RupaCore.SurfaceContinuityResult? {
        guard nodes.count == 1, let node = nodes.first else {
            return nil
        }
        let selectedPersistentNames = selectedGeneratedTopologyPersistentNames()
        guard selectedPersistentNames.isEmpty == false || node.object?.geometryRole == .surface else {
            return nil
        }

        let result = try SurfaceContinuityService().summarize(
            document: session.document,
            objectRegistry: objectRegistry,
            currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation
        )
        guard result.counts.bSplineFaceCount > 0 else {
            return nil
        }
        return result
    }

    private func selectedGeneratedTopologyPersistentNames() -> Set<String> {
        var names = Set<String>()
        for target in session.selection.selectedTargets {
            let componentID: SelectionComponentID?
            switch target.component {
            case .object, .sketchEntity, .region, .vertex:
                componentID = nil
            case .face(let id), .edge(let id):
                componentID = id
            }
            guard let name = componentID?.generatedTopologyPersistentName else {
                continue
            }
            names.insert(name)
        }
        return names
    }

    private func surfaceAdjacency(
        _ adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        containsAny persistentNames: Set<String>
    ) -> Bool {
        if let firstFacePersistentName = adjacency.firstFacePersistentName,
           persistentNames.contains(firstFacePersistentName) {
            return true
        }
        if let secondFacePersistentName = adjacency.secondFacePersistentName,
           persistentNames.contains(secondFacePersistentName) {
            return true
        }
        return adjacency.edgePersistentNames.contains { persistentNames.contains($0) }
    }

    private func surfaceAnalysisFace(
        _ face: SurfaceAnalysisResult.FaceAnalysis,
        containsAny persistentNames: Set<String>
    ) -> Bool {
        if face.facePersistentNames.contains(where: { persistentNames.contains($0) }) {
            return true
        }
        return face.edgePersistentNames.contains { persistentNames.contains($0) }
    }

    private func inspectorBridgeCurve(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> InspectorBridgeCurve? {
        guard let source = session.document.productMetadata.bridgeCurveSources.values.first(where: {
            $0.featureID == featureID && $0.entityID == entityID
        }) else {
            return nil
        }
        return InspectorBridgeCurve(
            sourceID: source.id,
            firstEndpoint: source.firstEndpoint,
            secondEndpoint: source.secondEndpoint,
            continuity: source.continuity,
            trimsSourceCurves: source.trimsSourceCurves,
            firstParameter: try inspectorBridgeCurveParameter(source.firstEndpoint),
            secondParameter: try inspectorBridgeCurveParameter(source.secondEndpoint),
            firstTension: try inspectorBridgeCurveTension(source.firstEndpoint.tension),
            secondTension: try inspectorBridgeCurveTension(source.secondEndpoint.tension)
        )
    }

    private func inspectorBridgeCurveParameter(
        _ endpoint: BridgeCurveEndpoint
    ) throws -> Double {
        if let parameter = endpoint.parameter {
            return try resolvedSketchValue(parameter, kind: .scalar)
        }
        switch endpoint.reference {
        case .lineStart,
             .arcStart:
            return 0.0
        case .lineEnd,
             .arcEnd:
            return 1.0
        case .splineControlPoint(_, let index):
            return index == 0 ? 0.0 : 1.0
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return 0.0
        }
    }

    private func inspectorBridgeCurveTension(
        _ tension: BridgeCurveTension
    ) throws -> InspectorBridgeCurveTension {
        InspectorBridgeCurveTension(
            first: try resolvedSketchValue(tension.first, kind: .scalar),
            second: try resolvedSketchValue(tension.second, kind: .scalar),
            third: try resolvedSketchValue(tension.third, kind: .scalar)
        )
    }

    private func inspectorCurveAnalysis(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> InspectorCurveAnalysis? {
        let result = try CurveAnalysisService(samplesPerSegment: 16).analyze(
            document: session.document,
            featureID: featureID,
            entityID: entityID,
            objectRegistry: objectRegistry
        )
        guard let curve = result.curves.first else {
            return nil
        }
        return InspectorCurveAnalysis(
            sampleCount: curve.samples.count,
            approximateLength: curve.approximateLength,
            maxAbsCurvature: curve.maxAbsCurvature,
            continuityJoins: result.continuityJoins.enumerated().map { index, join in
                InspectorCurveContinuityJoin(
                    id: "\(join.sourceFeatureID):\(join.firstReference):\(join.secondReference):\(index)",
                    joinKind: join.joinKind,
                    requiredContinuity: join.requiredContinuity,
                    actualContinuity: join.continuity,
                    positionGap: join.positionGap,
                    tangentAngle: join.tangentAngle,
                    curvatureGap: join.curvatureGap,
                    constraintKinds: join.constraintKinds,
                    firstReference: join.firstReference,
                    secondReference: join.secondReference
                )
            }
        )
    }

    private func inspectorLineCandidates(
        in sketch: Sketch,
        excluding entityID: SketchEntityID
    ) throws -> [InspectorSketchLineCandidate] {
        try sketch.entities.compactMap { candidateID, entity -> InspectorSketchLineCandidate? in
            guard candidateID != entityID,
                  case let .line(line) = entity else {
                return nil
            }
            return InspectorSketchLineCandidate(
                id: candidateID,
                start: try resolvedSketchPoint(line.start),
                end: try resolvedSketchPoint(line.end)
            )
        }
        .sorted { lhs, rhs in
            lhs.id.description.localizedStandardCompare(rhs.id.description) == .orderedAscending
        }
    }

    private func inspectorSplineEndpointCandidates(
        in sketch: Sketch,
        excluding entityID: SketchEntityID
    ) throws -> [InspectorSplineEndpointCandidate] {
        try sketch.entities.flatMap { candidateID, entity -> [InspectorSplineEndpointCandidate] in
            guard candidateID != entityID,
                  case let .spline(spline) = entity,
                  let start = spline.controlPoints.first,
                  let end = spline.controlPoints.last else {
                return []
            }
            return [
                InspectorSplineEndpointCandidate(
                    splineID: candidateID,
                    endpoint: .start,
                    point: try resolvedSketchPoint(start)
                ),
                InspectorSplineEndpointCandidate(
                    splineID: candidateID,
                    endpoint: .end,
                    point: try resolvedSketchPoint(end)
                ),
            ]
        }
        .sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func splineEndpointTangentLineIDs(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchEntityID> {
        Set(sketch.constraints.compactMap { constraint -> SketchEntityID? in
            guard case let .splineEndpointTangent(candidateSplineID, candidateEndpoint, lineID) = constraint,
                  candidateSplineID == splineID,
                  candidateEndpoint == endpoint else {
                return nil
            }
            return lineID
        })
    }

    private func tangentSplineEndpointReferences(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchSplineEndpointReference> {
        let selectedEndpoint = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
        return Set(sketch.constraints.compactMap { constraint -> SketchSplineEndpointReference? in
            guard case let .tangentSplineEndpoints(first, second) = constraint else {
                return nil
            }
            if first == selectedEndpoint {
                return second
            }
            if second == selectedEndpoint {
                return first
            }
            return nil
        })
    }

    private func smoothSplineEndpointReferences(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchSplineEndpointReference> {
        let selectedEndpoint = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
        return Set(sketch.constraints.compactMap { constraint -> SketchSplineEndpointReference? in
            guard case let .smoothSplineEndpoints(first, second) = constraint else {
                return nil
            }
            if first == selectedEndpoint {
                return second
            }
            if second == selectedEndpoint {
                return first
            }
            return nil
        })
    }

    private func resolvedSketchPoint(_ point: SketchPoint) throws -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: try resolvedSketchValue(point.x, kind: .length),
            y: try resolvedSketchValue(point.y, kind: .length)
        )
    }

    private func resolvedSketchValue(
        _ expression: CADExpression,
        kind: QuantityKind
    ) throws -> Double {
        let quantity = try session.document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Selected source curve expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func pointOnSketchCircle(
        center: SketchEntitySummaryResult.Point,
        radius: Double,
        angle: Double
    ) -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
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

    private var inspectorLabelWidth: CGFloat { 124 }
    private var inspectorControlWidth: CGFloat { 104 }
    private var inspectorUnitWidth: CGFloat { 36 }
    private var inspectorRowSpacing: CGFloat { 10 }
    private var inspectorSliderLeadingPadding: CGFloat {
        inspectorLabelWidth + inspectorRowSpacing
    }

    private var inspectorContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
            } else if selectedSceneNodes.isEmpty {
                canvasInspectorSections
            } else {
                objectInspectorSections(selectedSceneNodes)
            }
        case .failure(let error):
            surfaceControlPointInspectorErrorSections(error)
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorControlRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: inspectorRowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorActionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: inspectorRowSpacing) {
            Spacer()
                .frame(width: inspectorLabelWidth)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var canvasInspectorSections: some View {
        inspectorSection("Document") {
            inspectorRow("Name", documentTitle)
            inspectorRow("Document ID", shortID(session.document.id))
            inspectorRow("Source Unit", "m")
            inspectorRow("Display Unit", session.document.displayUnit.symbol)
        }

        inspectorSection("Scene") {
            inspectorRow("Source Features", "\(session.document.cadDocument.designGraph.order.count)")
            inspectorRow("Scene Nodes", "\(session.document.productMetadata.sceneNodes.count)")
            inspectorRow("Selected", "\(session.selection.selectedSceneNodeIDs.count)")
            inspectorRow("Generated Bodies", "\(session.evaluatedBodyCount)")
            inspectorRow("Components", "\(session.document.productMetadata.componentDefinitions.count)")
            inspectorRow("Instances", "\(session.document.productMetadata.componentInstances.count)")
        }

        inspectorSection("Evaluation") {
            inspectorRow("Evaluation", evaluationStatusTitle)
            inspectorRow("Diagnostics", diagnosticSummary)
            inspectorRow("Render Reason", renderInvalidationReasonTitle)
            inspectorRow("Render Generation", renderInvalidationGenerationTitle)
        }

        inspectorSection("Assets") {
            inspectorRow("Materials", "\(session.document.productMetadata.materialLibrary.materials.count)")
            inspectorRow("Default Material", defaultMaterialTitle)
            inspectorRow("Validation Rules", "\(session.document.productMetadata.validationRules.count)")
            inspectorRow("Export Presets", "\(session.document.productMetadata.exportPresets.count)")
        }

        inspectorSection("Units") {
            displayUnitPicker
        }

        inspectorSection("Ruler") {
            lengthControl(
                "Minor",
                meters: session.document.ruler.minorTickMeters,
                sliderRange: 0.01 ... 100.0
            ) { meters in
                setRulerConfiguration(minorTickMeters: meters)
            }
            lengthControl(
                "Major",
                meters: session.document.ruler.majorTickMeters,
                sliderRange: 0.1 ... 1_000.0
            ) { meters in
                setRulerConfiguration(majorTickMeters: meters)
            }
            lengthControl(
                "Visible",
                meters: session.document.ruler.visibleSpanMeters,
                sliderRange: 1.0 ... 100_000.0
            ) { meters in
                setRulerConfiguration(visibleSpanMeters: meters)
            }
        }
    }

    @ViewBuilder
    private func objectInspectorSections(_ nodes: [SceneNode]) -> some View {
        inspectorSection(nodes.count == 1 ? "Selection" : "Selection Group") {
            if nodes.count == 1, let node = nodes.first {
                inspectorRow("Name", node.name)
                inspectorRow("Object", objectTitle(for: node))
                inspectorRow("Target", selectedTargetSummary)
                inspectorRow("Geometry", geometryTitle(for: node))
                inspectorRow("Scene Node ID", shortID(node.id))
                inspectorRow("Primary", "Yes")
            } else {
                inspectorRow("Objects", "\(nodes.count)")
                inspectorRow("Targets", "\(selectedTargetCount)")
                inspectorRow("Primary", nodes.last?.name ?? "None")
                inspectorRow("Object Types", valueSummary(nodes.map { objectTitle(for: $0) }))
                inspectorRow("Geometry", valueSummary(nodes.map { geometryTitle(for: $0) }))
                inspectorRow("Visible Objects", "\(nodes.filter { $0.isVisible }.count)")
                inspectorRow("Locked Objects", "\(nodes.filter { $0.isLocked }.count)")
            }
        }

        if let patternArrayState = patternArrayInspectorState(for: nodes) {
            patternArrayInspectorSection(patternArrayState)
        }

        inspectorSection("Reference") {
            if nodes.count == 1, let node = nodes.first {
                if let object = node.object {
                    objectSourceInspectorRows(for: object)
                }
                inspectorRow("Reference", referenceTitle(for: node.reference))
                if let reference = node.reference {
                    referenceInspectorRows(for: reference)
                } else {
                    inspectorRow("Role", "Group")
                }
            } else {
                inspectorRow("References", referenceSummary(for: nodes))
                inspectorRow("Feature Links", "\(nodes.compactMap { $0.reference?.featureID }.count)")
                inspectorRow("Component Links", "\(nodes.compactMap { $0.reference?.componentInstanceID }.count)")
            }
        }

        inspectorSection("Hierarchy") {
            if nodes.count == 1, let node = nodes.first {
                inspectorRow("Parent", parentTitle(for: node.id))
                inspectorRow("Children", "\(node.childIDs.count)")
                inspectorRow("Descendants", "\(descendantCount(for: node.id))")
            } else {
                inspectorRow("Parents", parentSummary(for: nodes))
                inspectorRow("Children", "\(nodes.reduce(0) { $0 + $1.childIDs.count })")
                inspectorRow("Descendants", "\(nodes.reduce(0) { $0 + descendantCount(for: $1.id) })")
            }
        }

        inspectorSection("State") {
            boolChoicePicker(
                "Visible",
                nodes: nodes,
                keyPath: \.isVisible
            ) { id, isVisible in
                session.setSceneNodeVisibility(id, isVisible: isVisible)
            }

            boolChoicePicker(
                "Locked",
                nodes: nodes,
                keyPath: \.isLocked
            ) { id, isLocked in
                session.setSceneNodeLock(id, isLocked: isLocked)
            }
        }

        surfaceAnalysisSection(nodes)
        surfaceContinuitySection(nodes)

        projectCurvesToFaceSection()
        projectOutlineSection(nodes)
        faceEditSection(nodes)
        edgeEditSection(nodes)
        vertexEditSection(nodes)
        regionEditSection()

        objectShapeSection(nodes)

        inspectorSection("Position") {
            transformLengthControl(
                "X",
                values: nodes.map { translation(for: $0).x },
                sliderRange: transformPositionSliderRange
            ) { meters in
                setTransformComponent(.translationX, to: meters, for: nodes)
            }
            transformLengthControl(
                "Y",
                values: nodes.map { translation(for: $0).y },
                sliderRange: transformPositionSliderRange
            ) { meters in
                setTransformComponent(.translationY, to: meters, for: nodes)
            }
            transformLengthControl(
                "Z",
                values: nodes.map { translation(for: $0).z },
                sliderRange: transformPositionSliderRange
            ) { meters in
                setTransformComponent(.translationZ, to: meters, for: nodes)
            }
        }

        inspectorSection("Transform Scale") {
            numericControl(
                "X",
                values: nodes.map { scale(for: $0).x },
                sliderRange: 0.01 ... 10.0
            ) { value in
                setTransformComponent(.scaleX, to: max(value, 0.0001), for: nodes)
            }
            numericControl(
                "Y",
                values: nodes.map { scale(for: $0).y },
                sliderRange: 0.01 ... 10.0
            ) { value in
                setTransformComponent(.scaleY, to: max(value, 0.0001), for: nodes)
            }
            numericControl(
                "Z",
                values: nodes.map { scale(for: $0).z },
                sliderRange: 0.01 ... 10.0
            ) { value in
                setTransformComponent(.scaleZ, to: max(value, 0.0001), for: nodes)
            }
        }

        inspectorSection("Material") {
            materialPicker(nodes)
        }

        inspectorSection("Transform") {
            inspectorRow("Local", transformSummary(for: nodes))
            inspectorRow("Custom", "\(nodes.filter { $0.localTransform.matrix != .identity }.count)")
            if nodes.count == 1, let node = nodes.first {
                matrixInspectorRows(node.localTransform.matrix.values)
            }

            inspectorActionRow {
                Button("Reset Transform") {
                    for node in nodes {
                        session.setSceneNodeTransform(node.id, localTransform: .identity)
                    }
                }
                .disabled(nodes.allSatisfy { $0.localTransform.matrix == .identity })
            }
        }
    }

    private func patternArrayInspectorSection(_ state: PatternArrayInspectorState) -> some View {
        PatternArrayInspectorView(
            state: state,
            session: session,
            positionSliderRange: transformPositionSliderRange,
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
            positionSliderRange: transformPositionSliderRange,
            slideDistanceMeters: $polySplineSurfaceVertexSlideDistanceMeters,
            isSlideActive: slideCommandState.isSurfaceControlVerticesActive,
            slideRouteTitle: slideCommandState.routeTitle,
            onSetPointDisplay: setSurfaceControlPointDisplay,
            onSetCoordinate: { axis, meters in
                setSurfaceControlPointCoordinate(axis, meters: meters, state: state)
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

    @ViewBuilder
    private func surfaceControlPointInspectorErrorSections(_ error: Error) -> some View {
        inspectorSection("Surface CV") {
            inspectorRow("Target", selectedTargetSummary)
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

    private func boolChoicePicker(
        _ title: String,
        nodes: [SceneNode],
        keyPath: KeyPath<SceneNode, Bool>,
        apply: @escaping (SceneNodeID, Bool) -> Void
    ) -> some View {
        inspectorControlRow(title) {
            Picker(
                "",
                selection: Binding(
                    get: {
                        boolChoice(nodes: nodes, keyPath: keyPath)
                    },
                    set: { choice in
                        switch choice {
                        case .mixed:
                            return
                        case .on:
                            for node in nodes {
                                apply(node.id, true)
                            }
                        case .off:
                            for node in nodes {
                                apply(node.id, false)
                            }
                        }
                    }
                )
            ) {
                ForEach(InspectorBoolChoice.allCases) { choice in
                    Text(choice.rawValue)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func boolChoice(
        nodes: [SceneNode],
        keyPath: KeyPath<SceneNode, Bool>
    ) -> InspectorBoolChoice {
        guard let first = nodes.first?[keyPath: keyPath],
              nodes.allSatisfy({ $0[keyPath: keyPath] == first }) else {
            return .mixed
        }
        return first ? .on : .off
    }

    @ViewBuilder
    private func surfaceAnalysisSection(_ nodes: [SceneNode]) -> some View {
        switch selectedSurfaceAnalysisResult(for: nodes) {
        case .success(let analysis):
            if let analysis {
                inspectorSection("Surface Analysis") {
                    inspectorRow("B-spline Faces", "\(analysis.bSplineFaceCount)")
                    inspectorRow("UV Samples", "\(analysis.sampleCount)")
                    inspectorRow(
                        "Comb Samples",
                        "\(analysis.uCurvatureCombCount) U, \(analysis.vCurvatureCombCount) V"
                    )
                    inspectorRow(
                        "Trim Boundaries",
                        surfaceTrimBoundarySummary(
                            boundaryCount: analysis.trimBoundaryCount,
                            innerCount: analysis.innerTrimBoundaryCount,
                            openCount: analysis.openTrimBoundaryCount
                        )
                    )
                    inspectorRow("Trim Edges", "\(analysis.trimBoundaryEdgeCount)")
                    if analysis.faces.isEmpty {
                        inspectorRow("Target", "No B-spline face")
                    } else {
                        ForEach(analysis.faces) { face in
                            inspectorRow("Face", surfaceAnalysisFaceSummary(face))
                            inspectorRow("Degree", "\(face.uDegree) U, \(face.vDegree) V")
                            inspectorRow(
                                "Control Net",
                                "\(face.uControlPointCount) U x \(face.vControlPointCount) V"
                            )
                            inspectorRow("Samples", "\(face.sampleCount)")
                            inspectorRow(
                                "Trim Boundary",
                                surfaceTrimBoundarySummary(
                                    boundaryCount: face.trimBoundaryCount,
                                    innerCount: face.innerTrimBoundaryCount,
                                    openCount: face.openTrimBoundaryCount
                                )
                            )
                            inspectorRow("Trim Edges", "\(face.trimBoundaryEdgeCount)")
                            inspectorRow("Trim Length", formatted(face.trimBoundaryLength))
                            inspectorRow(
                                "U Curvature",
                                formattedCurvature(face.maxAbsUNormalCurvature)
                            )
                            inspectorRow(
                                "V Curvature",
                                formattedCurvature(face.maxAbsVNormalCurvature)
                            )
                            inspectorRow(
                                "Principal Curvature",
                                formattedCurvature(face.maxAbsPrincipalCurvature)
                            )
                            if let direction = face.minimumPrincipalDirection {
                                inspectorRow(
                                    "Min Direction",
                                    formattedSurfaceDirection(direction)
                                )
                            }
                            if let direction = face.maximumPrincipalDirection {
                                inspectorRow(
                                    "Max Direction",
                                    formattedSurfaceDirection(direction)
                                )
                            }
                            inspectorRow(
                                "Gaussian Curvature",
                                formattedGaussianCurvature(face.maxAbsGaussianCurvature)
                            )
                            inspectorRow(
                                "U Normal Change",
                                formattedCurvature(face.maxUNormalChangePerLength)
                            )
                            inspectorRow(
                                "V Normal Change",
                                formattedCurvature(face.maxVNormalChangePerLength)
                            )
                            inspectorRow(
                                "Max Normal Angle",
                                formattedDegrees(degrees(fromRadians: face.maxNormalAngle))
                            )
                        }
                    }
                    if analysis.diagnostics.isEmpty == false {
                        inspectorRow("Diagnostics", surfaceDiagnosticsSummary(analysis.diagnostics))
                    }
                }
            }
        case .failure(let error):
            if shouldShowSurfaceContinuitySection(for: nodes) {
                inspectorSection("Surface Analysis") {
                    inspectorRow("Status", "Unavailable")
                    inspectorRow("Reason", error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func surfaceContinuitySection(_ nodes: [SceneNode]) -> some View {
        switch selectedSurfaceContinuityResult(for: nodes) {
        case .success(let continuity):
            if let continuity {
                inspectorSection("Surface Continuity") {
                    inspectorRow("B-spline Faces", "\(continuity.bSplineFaceCount)")
                    inspectorRow("Shared Edges", "\(continuity.sharedEdgeCount)")
                    inspectorRow("Continuity", surfaceContinuityCountsSummary(continuity))
                    inspectorRow("G2 Solve", surfaceContinuitySolveSummary(continuity))
                    if continuity.adjacencies.isEmpty {
                        inspectorRow("Adjacency", "None for target")
                    } else {
                        ForEach(continuity.adjacencies) { adjacency in
                            inspectorRow("Edge", surfaceAdjacencyEdgeSummary(adjacency))
                            inspectorRow("Faces", surfaceAdjacencyFaceSummary(adjacency))
                            inspectorRow("Status", surfaceAdjacencyContinuitySummary(adjacency))
                            if let normalAngle = adjacency.normalAngle {
                                inspectorRow("Normal Angle", formattedDegrees(degrees(fromRadians: normalAngle)))
                            }
                            inspectorRow("Position Gap", formatted(adjacency.positionGap))
                            if let curvatureGap = adjacency.curvatureGap {
                                inspectorRow("Curvature Gap", formattedCurvature(curvatureGap))
                            }
                            inspectorRow(
                                "G2 Required",
                                adjacency.requiresCurvatureContinuitySolve ? "Yes" : "No"
                            )
                        }
                    }
                    if continuity.diagnostics.isEmpty == false {
                        inspectorRow("Diagnostics", surfaceDiagnosticsSummary(continuity.diagnostics))
                    }
                }
            }
        case .failure(let error):
            if shouldShowSurfaceContinuitySection(for: nodes) {
                inspectorSection("Surface Continuity") {
                    inspectorRow("Status", "Unavailable")
                    inspectorRow("Reason", error.localizedDescription)
                }
            }
        }
    }

    private func shouldShowSurfaceContinuitySection(for nodes: [SceneNode]) -> Bool {
        guard nodes.count == 1, let node = nodes.first else {
            return false
        }
        return node.object?.geometryRole == .surface
            || selectedGeneratedTopologyPersistentNames().isEmpty == false
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
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in session.selection.selectedTargets where target != faceTarget {
            let curveTarget: SelectionTarget?
            if let sketchCurveTarget = wholeSketchCurveTarget(for: target) {
                curveTarget = sketchCurveTarget
            } else if case .edge(let componentID) = target.component,
                      componentID.generatedTopologyPersistentName != nil {
                curveTarget = target
            } else {
                curveTarget = nil
            }
            guard let curveTarget else {
                continue
            }
            let key = "\(curveTarget.sceneNodeID.description):\(String(describing: curveTarget.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(curveTarget)
            }
        }
        return projectedTargets
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
        guard session.selection.selectedTargets.allSatisfy({ $0.component == .object }) else {
            return []
        }
        return nodes.compactMap { node in
            guard node.reference?.kind == .body else {
                return nil
            }
            return SelectionTarget(sceneNodeID: node.id)
        }
    }

    @ViewBuilder
    private func faceEditSection(_ nodes: [SceneNode]) -> some View {
        if nodes.count == 1, let faceTarget = selectedFaceTarget {
            inspectorSection("Face Edit") {
                inspectorRow("Target", selectedTargetSummary)
                inspectorActionRow {
                    Button {
                        offsetSelectedFace(faceTarget, by: -defaultFaceOffsetStepMeters)
                    } label: {
                        Label("Offset -\(formatted(defaultFaceOffsetStepMeters))", systemImage: "minus")
                    }
                    .accessibilityIdentifier("InspectorFace.offsetNegative")

                    Button {
                        offsetSelectedFace(faceTarget, by: defaultFaceOffsetStepMeters)
                    } label: {
                        Label("Offset +\(formatted(defaultFaceOffsetStepMeters))", systemImage: "plus")
                    }
                    .accessibilityIdentifier("InspectorFace.offsetPositive")
                }
            }
        }
    }

    @ViewBuilder
    private func edgeEditSection(_ nodes: [SceneNode]) -> some View {
        let edgeTargets = selectedEdgeTargets
        let projectableEdgeTargets = generatedEdgeProjectionTargets(from: edgeTargets)
        if nodes.count == 1, edgeTargets.isEmpty == false {
            inspectorSection("Edge Edit") {
                inspectorRow("Targets", "\(edgeTargets.count)")
                edgeOffsetDistanceControl
                edgeOffsetGapFillPicker
                inspectorActionRow {
                    Button {
                        offsetSelectedEdges(
                            edgeTargets,
                            by: edgeOffsetDistanceMeters,
                            gapFill: edgeOffsetGapFill
                        )
                    } label: {
                        Label("Offset \(formatted(edgeOffsetDistanceMeters))", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityIdentifier("InspectorEdge.offset")
                }

                inspectorActionRow {
                    Button {
                        projectSelectedGeneratedEdgesToConstructionPlane(projectableEdgeTargets)
                    } label: {
                        Label("Project", systemImage: "square.on.square")
                    }
                    .disabled(projectableEdgeTargets.isEmpty)
                    .accessibilityIdentifier("InspectorEdge.project")
                }

                inspectorActionRow {
                    Button {
                        filletSelectedEdges(edgeTargets, radius: defaultEdgeFilletRadiusMeters)
                    } label: {
                        Label("Fillet \(formatted(defaultEdgeFilletRadiusMeters))", systemImage: "circle.dashed")
                    }
                    .accessibilityIdentifier("InspectorEdge.fillet")

                    Button {
                        chamferSelectedEdges(edgeTargets, by: defaultEdgeChamferStepMeters)
                    } label: {
                        Label("Chamfer \(formatted(defaultEdgeChamferStepMeters))", systemImage: "line.diagonal")
                    }
                    .accessibilityIdentifier("InspectorEdge.chamfer")
                }
            }
        }
    }

    private func generatedEdgeProjectionTargets(
        from targets: [SelectionTarget]
    ) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in targets {
            guard case .edge(let componentID) = target.component,
                  componentID.generatedTopologyPersistentName != nil else {
                continue
            }
            let key = "\(target.sceneNodeID.description):\(String(describing: target.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(target)
            }
        }
        return projectedTargets
    }

    private var edgeOffsetDistanceControl: some View {
        lengthControl(
            "Offset",
            meters: edgeOffsetDistanceMeters,
            sliderRange: regionOffsetSliderRange
        ) { meters in
            edgeOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        .accessibilityIdentifier("InspectorEdge.offsetDistance")
    }

    private var edgeOffsetGapFillPicker: some View {
        inspectorControlRow("Gap Fill") {
            Picker(
                "",
                selection: $edgeOffsetGapFill
            ) {
                ForEach(OffsetCurveGapFill.allCases, id: \.self) { gapFill in
                    Text(regionOffsetGapFillTitle(gapFill))
                        .tag(gapFill)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
        .accessibilityIdentifier("InspectorEdge.gapFill")
    }

    @ViewBuilder
    private func vertexEditSection(_ nodes: [SceneNode]) -> some View {
        if nodes.count == 1, let vertexTarget = selectedVertexTarget {
            inspectorSection("Vertex Edit") {
                inspectorRow("Target", selectedTargetSummary)
                inspectorActionRow {
                    Button {
                        moveSelectedVertex(vertexTarget, deltaX: -defaultVertexMoveStepMeters, deltaY: 0.0)
                    } label: {
                        Label("X -\(formatted(defaultVertexMoveStepMeters))", systemImage: "arrow.left")
                    }
                    .accessibilityIdentifier("InspectorVertex.moveXNegative")

                    Button {
                        moveSelectedVertex(vertexTarget, deltaX: defaultVertexMoveStepMeters, deltaY: 0.0)
                    } label: {
                        Label("X +\(formatted(defaultVertexMoveStepMeters))", systemImage: "arrow.right")
                    }
                    .accessibilityIdentifier("InspectorVertex.moveXPositive")
                }
                inspectorActionRow {
                    Button {
                        moveSelectedVertex(vertexTarget, deltaX: 0.0, deltaY: -defaultVertexMoveStepMeters)
                    } label: {
                        Label("Y -\(formatted(defaultVertexMoveStepMeters))", systemImage: "arrow.down")
                    }
                    .accessibilityIdentifier("InspectorVertex.moveYNegative")

                    Button {
                        moveSelectedVertex(vertexTarget, deltaX: 0.0, deltaY: defaultVertexMoveStepMeters)
                    } label: {
                        Label("Y +\(formatted(defaultVertexMoveStepMeters))", systemImage: "arrow.up")
                    }
                    .accessibilityIdentifier("InspectorVertex.moveYPositive")
                }
            }
        }
    }

    @ViewBuilder
    private func regionEditSection() -> some View {
        let regionTargets = selectedRegionTargets
        if regionTargets.isEmpty == false {
            inspectorSection("Region Edit") {
                inspectorRow("Targets", regionTargets.count == 1 ? selectedTargetSummary : "\(regionTargets.count)")
                regionOffsetDistanceControl
                regionOffsetGapFillPicker
                inspectorActionRow {
                    Button {
                        offsetSelectedRegions(
                            regionTargets,
                            by: -regionOffsetDistanceMeters,
                            gapFill: regionOffsetGapFill,
                            isSymmetric: regionOffsetCommandState.usesLockedDistance,
                            combinesRegions: regionOffsetCommandState.usesCombinedRegions
                        )
                    } label: {
                        Label("Inward", systemImage: "minus.circle")
                    }
                    .accessibilityIdentifier("InspectorRegion.offsetInward")

                    Button {
                        offsetSelectedRegions(
                            regionTargets,
                            by: regionOffsetDistanceMeters,
                            gapFill: regionOffsetGapFill,
                            isSymmetric: regionOffsetCommandState.usesLockedDistance,
                            combinesRegions: regionOffsetCommandState.usesCombinedRegions
                        )
                    } label: {
                        Label("Outward", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("InspectorRegion.offsetOutward")
                }
            }
        }
    }

    private var regionOffsetDistanceControl: some View {
        lengthControl(
            "Distance",
            meters: regionOffsetDistanceMeters,
            sliderRange: regionOffsetSliderRange
        ) { meters in
            regionOffsetDistanceMeters = max(meters, 1.0e-9)
        }
        .accessibilityIdentifier("InspectorRegion.distance")
    }

    private var regionOffsetGapFillPicker: some View {
        inspectorControlRow("Gap Fill") {
            Picker(
                "",
                selection: $regionOffsetGapFill
            ) {
                ForEach(OffsetCurveGapFill.allCases, id: \.self) { gapFill in
                    Text(regionOffsetGapFillTitle(gapFill))
                        .tag(gapFill)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
        .accessibilityIdentifier("InspectorRegion.gapFill")
    }

    @ViewBuilder
    private func sketchEntityInspectorErrorSections(_ error: Error) -> some View {
        inspectorSection("Curve Selection") {
            inspectorRow("Target", selectedTargetSummary)
            inspectorRow("Status", "Unavailable")
            inspectorRow("Reason", error.localizedDescription)
        }
    }

    @ViewBuilder
    private func sketchEntityInspectorSections(_ entity: InspectorSketchEntity) -> some View {
        inspectorSection("Curve Selection") {
            inspectorRow("Kind", sketchEntityKindTitle(entity.entityKind))
            inspectorRow("Target", selectedTargetSummary)
            inspectorRow("Source", entity.sourceFeatureName ?? shortID(entity.sourceFeatureID))
            inspectorRow("Source ID", shortID(entity.sourceFeatureID))
            inspectorRow("Entity ID", shortID(entity.entityID))
            if let joinedCurveSourceID = entity.joinedCurveSourceID {
                inspectorRow("Join Source", shortID(joinedCurveSourceID))
            }
            if let joinedCurveGroupSourceID = entity.joinedCurveGroupSourceID {
                inspectorRow("Join Group", shortID(joinedCurveGroupSourceID))
            }
            if let continuity = entity.joinedCurveGroupContinuity {
                inspectorRow("Join Continuity", sketchCurveJoinContinuityTitle(continuity))
            }
            if let center = entity.center {
                inspectorRow("Center", sketchPointSummary(center))
            }
            if let start = entity.start {
                inspectorRow("Start", sketchPointSummary(start))
            }
            if let end = entity.end {
                inspectorRow("End", sketchPointSummary(end))
            }
        }

        if let analysis = entity.analysis {
            sketchEntityAnalysisSection(entity, analysis: analysis)
        }

        if let bridgeCurve = entity.bridgeCurve {
            bridgeCurveInspectorSection(bridgeCurve)
        }

        inspectorSection("Curve Edit") {
            sketchEntityEditControls(entity)
        }
    }

    @ViewBuilder
    private func sketchEntityAnalysisSection(
        _ entity: InspectorSketchEntity,
        analysis: InspectorCurveAnalysis
    ) -> some View {
        inspectorSection("Curve Analysis") {
            inspectorRow("Samples", "\(analysis.sampleCount)")
            inspectorRow("Length", analysis.approximateLength)
            inspectorRow("Max Curvature", formattedCurvature(analysis.maxAbsCurvature))
            let display = curveCurvatureDisplay(for: entity)
            inspectorRow("Curvature Comb", display == nil ? "Off" : "On")
            if analysis.maxAbsCurvature <= 1.0e-12 {
                inspectorRow("Comb Output", "Flat curve")
            }
            inspectorActionRow {
                Button {
                    setCurveCurvatureDisplay(
                        entity,
                        isVisible: display == nil,
                        combScale: display?.combScale ?? CurveCurvatureDisplay.defaultCombScale
                    )
                } label: {
                    Label(
                        display == nil ? "Show Comb" : "Hide Comb",
                        systemImage: display == nil ? "waveform.path.ecg" : "eye.slash"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.curvatureComb.toggle")
            }
            if let display {
                numericControl(
                    "Comb Scale",
                    values: [display.combScale],
                    sliderRange: 0.01 ... max(1.0, display.combScale * 2.0)
                ) { value in
                    setCurveCurvatureDisplay(
                        entity,
                        isVisible: true,
                        combScale: max(value, 1.0e-6)
                    )
                }
            }
            let pointDisplay = pointDisplay(for: entity)
            inspectorRow("Points", pointDisplayTitle(pointDisplay))
            inspectorActionRow {
                Button {
                    setPointDisplay(
                        entity,
                        isVisible: pointDisplay?.isVisible == false
                    )
                } label: {
                    Label(
                        pointDisplay?.isVisible == false ? "Show Points" : "Hide Points",
                        systemImage: pointDisplay?.isVisible == false ? "smallcircle.filled.circle" : "eye.slash"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.points.toggle")
            }
            if analysis.continuityJoins.isEmpty {
                inspectorRow("Continuity", "No joins")
            } else {
                inspectorRow("Continuity", "\(analysis.continuityJoins.count) joins")
                ForEach(analysis.continuityJoins) { join in
                    inspectorRow("Join", curveContinuityJoinSummary(join))
                    inspectorRow("Gap", formatted(join.positionGap))
                    if let tangentAngle = join.tangentAngle {
                        inspectorRow("Tangent", formattedDegrees(degrees(fromRadians: tangentAngle)))
                    }
                    if let curvatureGap = join.curvatureGap {
                        inspectorRow("Curvature", formattedCurvature(curvatureGap))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bridgeCurveInspectorSection(_ bridgeCurve: InspectorBridgeCurve) -> some View {
        inspectorSection("Bridge Source") {
            inspectorRow("Source ID", shortID(bridgeCurve.sourceID))
            inspectorRow("Continuity", bridgeContinuityTitle(bridgeCurve.continuity))
            inspectorRow("Trim", bridgeCurve.trimsSourceCurves ? "Source curves trimmed" : "Off")
            inspectorRow("Start Continuity", bridgeEndpointContinuityTitle(bridgeCurve.continuity.first))
            inspectorRow("End Continuity", bridgeEndpointContinuityTitle(bridgeCurve.continuity.second))
            inspectorRow("First", sketchReferenceTitle(bridgeCurve.firstEndpoint.reference))
            inspectorRow("Second", sketchReferenceTitle(bridgeCurve.secondEndpoint.reference))
            bridgeCurveParameterControl(
                "Start Value",
                value: bridgeCurve.firstParameter
            ) { value in
                setBridgeCurveParameter(bridgeCurve, endpoint: .first, value: value)
            }
            bridgeCurveParameterControl(
                "End Value",
                value: bridgeCurve.secondParameter
            ) { value in
                setBridgeCurveParameter(bridgeCurve, endpoint: .second, value: value)
            }
            inspectorActionRow {
                Button {
                    setBridgeCurveSense(bridgeCurve, endpoint: .first)
                } label: {
                    Label(
                        bridgeCurve.firstEndpoint.reversesSense ? "Start Sense Reversed" : "Start Sense",
                        systemImage: "arrow.left.and.right"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.bridge.startSense")

                Button {
                    setBridgeCurveSense(bridgeCurve, endpoint: .second)
                } label: {
                    Label(
                        bridgeCurve.secondEndpoint.reversesSense ? "End Sense Reversed" : "End Sense",
                        systemImage: "arrow.left.and.right"
                    )
                }
                .accessibilityIdentifier("InspectorCurve.bridge.endSense")
            }
            inspectorActionRow {
                Button {
                    trimBridgeCurveSources(bridgeCurve)
                } label: {
                    Label("Trim Sources", systemImage: "scissors")
                }
                .disabled(bridgeCurve.trimsSourceCurves)
                .accessibilityIdentifier("InspectorCurve.bridge.trimSources")
            }
            bridgeCurveTensionControl(
                "Start Tension 1",
                value: bridgeCurve.firstTension.first
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .first, level: .first, value: value)
            }
            bridgeCurveTensionControl(
                "Start Tension 2",
                value: bridgeCurve.firstTension.second
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .first, level: .second, value: value)
            }
            bridgeCurveTensionControl(
                "Start Tension 3",
                value: bridgeCurve.firstTension.third
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .first, level: .third, value: value)
            }
            bridgeCurveTensionControl(
                "End Tension 1",
                value: bridgeCurve.secondTension.first
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .second, level: .first, value: value)
            }
            bridgeCurveTensionControl(
                "End Tension 2",
                value: bridgeCurve.secondTension.second
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .second, level: .second, value: value)
            }
            bridgeCurveTensionControl(
                "End Tension 3",
                value: bridgeCurve.secondTension.third
            ) { value in
                setBridgeCurveTension(bridgeCurve, endpoint: .second, level: .third, value: value)
            }
            inspectorActionRow {
                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .first, continuity: .g0)
                } label: {
                    Label("Start G0", systemImage: "smallcircle.filled.circle")
                }
                .disabled(bridgeCurve.continuity.first == .g0)
                .accessibilityIdentifier("InspectorCurve.bridge.startContinuityG0")

                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .first, continuity: .g1)
                } label: {
                    Label("Start G1", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .disabled(bridgeCurve.continuity.first == .g1)
                .accessibilityIdentifier("InspectorCurve.bridge.startContinuityG1")

                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .first, continuity: .g2)
                } label: {
                    Label("Start G2", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(bridgeCurve.continuity.first == .g2)
                .accessibilityIdentifier("InspectorCurve.bridge.startContinuityG2")
            }
            inspectorActionRow {
                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .second, continuity: .g0)
                } label: {
                    Label("End G0", systemImage: "smallcircle.filled.circle")
                }
                .disabled(bridgeCurve.continuity.second == .g0)
                .accessibilityIdentifier("InspectorCurve.bridge.endContinuityG0")

                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .second, continuity: .g1)
                } label: {
                    Label("End G1", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .disabled(bridgeCurve.continuity.second == .g1)
                .accessibilityIdentifier("InspectorCurve.bridge.endContinuityG1")

                Button {
                    setBridgeCurveContinuity(bridgeCurve, endpoint: .second, continuity: .g2)
                } label: {
                    Label("End G2", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(bridgeCurve.continuity.second == .g2)
                .accessibilityIdentifier("InspectorCurve.bridge.endContinuityG2")
            }
        }
    }

    private func bridgeCurveTensionControl(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        numericControl(
            title,
            values: [value],
            sliderRange: bridgeTensionSliderRange(for: value)
        ) { nextValue in
            onChange(max(nextValue, 1.0e-6))
        }
    }

    private func bridgeCurveParameterControl(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        numericControl(
            title,
            values: [value],
            sliderRange: 0.0 ... 1.0
        ) { nextValue in
            onChange(min(max(nextValue, 0.0), 1.0))
        }
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
            sketchVertexAlignmentControls(entity)
        case "line":
            if let length = sketchLineLength(for: entity) {
                lengthControl(
                    "Length",
                    meters: length,
                    sliderRange: lengthSliderRange(for: length)
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
            sketchVertexAlignmentControls(entity)
            sketchCurveProjectionControls(entity)
            sketchVertexOffsetControls(entity)
            lengthControl(
                "Slot Width",
                meters: slotProfileWidthMeters,
                sliderRange: lengthSliderRange(for: slotProfileWidthMeters)
            ) { meters in
                slotProfileWidthMeters = max(meters, 1.0e-9)
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
            sketchCurveExtendControls(entity)
            sketchCornerTreatmentControls(entity)
            sketchCurveJoinControls(entity)
            inspectorActionRow {
                Button {
                    createSlotFromOffsetCurve(entity.target, width: slotProfileWidthMeters)
                } label: {
                    Label("Slot", systemImage: "capsule")
                }
                .accessibilityIdentifier("InspectorCurve.line.createSlot")

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
                    sliderRange: lengthSliderRange(for: radius)
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
            sketchVertexAlignmentControls(entity)
            sketchCurveProjectionControls(entity)
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
                    sliderRange: lengthSliderRange(for: radius)
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
            sketchVertexAlignmentControls(entity)
            sketchCurveProjectionControls(entity)
            sketchVertexOffsetControls(entity)
            numericControl(
                "Split",
                values: [sketchSplitFraction],
                sliderRange: 0.01 ... 0.99
            ) { fraction in
                sketchSplitFraction = min(max(fraction, 0.01), 0.99)
            } unitLabel: {
                "t"
            }
            sketchCurveExtendControls(entity)
            sketchCurveJoinControls(entity)
            inspectorActionRow {
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
            sketchCurveProjectionControls(entity)
            sketchCurveExtendControls(entity)
            inspectorControlRow("Rebuild CVs") {
                Stepper(
                    value: $sketchRebuildControlPointCount,
                    in: 4 ... 31,
                    step: 3
                ) {
                    Text("\(sketchRebuildControlPointCount)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("InspectorCurve.spline.rebuildControlPointCount")
            }
            numericControl(
                "Refit Tol",
                values: [sketchRebuildToleranceMeters],
                sliderRange: 0.00001 ... 0.01
            ) { tolerance in
                sketchRebuildToleranceMeters = min(max(tolerance, 0.00001), 0.01)
            } unitLabel: {
                "m"
            }
            inspectorControlRow("Keep Corners") {
                Toggle("", isOn: $sketchRebuildKeepsCorners)
                    .labelsHidden()
                    .accessibilityIdentifier("InspectorCurve.spline.refitKeepCorners")
            }
            inspectorControlRow("Degree") {
                Stepper(
                    value: $sketchRebuildExplicitDegree,
                    in: 1 ... 7
                ) {
                    Text("\(sketchRebuildExplicitDegree)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("InspectorCurve.spline.explicitDegree")
            }
            inspectorControlRow("Spans") {
                Stepper(
                    value: $sketchRebuildExplicitSpanCount,
                    in: 1 ... 64
                ) {
                    Text("\(sketchRebuildExplicitSpanCount)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("InspectorCurve.spline.explicitSpans")
            }
            numericControl(
                "Weight",
                values: [sketchRebuildExplicitWeight],
                sliderRange: 0.0 ... 1.0
            ) { weight in
                sketchRebuildExplicitWeight = min(max(weight, 0.0), 1.0)
            }
            .accessibilityIdentifier("InspectorCurve.spline.explicitWeight")
            inspectorActionRow {
                Button {
                    reverseSelectedSketchCurve(entity.target)
                } label: {
                    Label("Reverse", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("InspectorCurve.spline.reverse")

                Button {
                    splitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Split", systemImage: "scissors")
                }
                .accessibilityIdentifier("InspectorCurve.spline.split")

                Button {
                    insertSelectedSketchSplineControlPoint(entity.target)
                } label: {
                    Label("Insert CV", systemImage: "plus")
                }
                .accessibilityIdentifier("InspectorCurve.spline.insertControlPoint")

                Button {
                    rebuildSelectedSketchCurve(entity.target)
                } label: {
                    Label("Rebuild", systemImage: "point.3.filled.connected.trianglepath.dotted")
                }
                .accessibilityIdentifier("InspectorCurve.spline.rebuild")

                Button {
                    refitSelectedSketchCurve(entity.target)
                } label: {
                    Label("Refit", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("InspectorCurve.spline.refit")

                Button {
                    explicitControlSelectedSketchCurve(entity.target)
                } label: {
                    Label("Explicit", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("InspectorCurve.spline.explicit")

                Button {
                    trimSelectedSketchCurveSegment(entity.target)
                } label: {
                    Label("Trim", systemImage: "delete.left")
                }
                .accessibilityIdentifier("InspectorCurve.spline.trim")
            }
            if entity.bridgeCurve != nil {
                inspectorRow("Edit", "Bridge Source")
            } else {
                splineControlPointControls(entity)
                splineEndpointTangencyControls(entity)
                splineEndpointSmoothControls(entity)
            }
        default:
            inspectorRow("Edit", "Unsupported")
        }
    }

    @ViewBuilder
    private func splineControlPointControls(_ entity: InspectorSketchEntity) -> some View {
        if entity.controlPoints.isEmpty {
            inspectorRow("Control Point", "None")
        } else {
            let index = clampedSplineControlPointIndex(for: entity)
            let selectedControlPointIndexes = selectedSplineControlPointIndexes(for: entity)
            let indexBounds = 0 ... max(entity.controlPoints.count - 1, 0)
            inspectorControlRow("Control Point") {
                Stepper(
                    value: Binding<Int>(
                        get: { clampedSplineControlPointIndex(for: entity) },
                        set: { selectedSplineControlPointIndex = clamped($0, in: entity.controlPoints.indices) }
                    ),
                    in: indexBounds
                ) {
                    Text("\(index + 1) / \(entity.controlPoints.count)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("InspectorCurve.spline.controlPointIndex")
            }
            inspectorRow("Point", sketchPointSummary(entity.controlPoints[index]))
            splineSmoothConstraintControls(entity, controlPointIndex: index)
            splineControlPointMoveControls(
                "Point \(index + 1)",
                target: entity.target,
                controlPointIndex: index,
                accessibilityPrefix: "InspectorCurve.spline.controlPoint"
            )
            numericControl(
                "Slide CV",
                values: [sketchSplineControlPointSlideDistanceMeters],
                sliderRange: lengthSliderRange(for: sketchSplineControlPointSlideDistanceMeters)
            ) { distance in
                sketchSplineControlPointSlideDistanceMeters = max(distance, 1.0e-9)
            } unitLabel: {
                "m"
            }
            if selectedControlPointIndexes.isEmpty {
                let slideCountBounds = 1 ... max(entity.controlPoints.count - index, 1)
                inspectorControlRow("Slide Count") {
                    Stepper(
                        value: Binding<Int>(
                            get: { min(max(sketchSplineControlPointSlideCount, slideCountBounds.lowerBound), slideCountBounds.upperBound) },
                            set: { sketchSplineControlPointSlideCount = min(max($0, slideCountBounds.lowerBound), slideCountBounds.upperBound) }
                        ),
                        in: slideCountBounds
                    ) {
                        Text("\(min(max(sketchSplineControlPointSlideCount, slideCountBounds.lowerBound), slideCountBounds.upperBound))")
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("InspectorCurve.spline.slideCount")
                }
            } else {
                inspectorRow("Selected CVs", splineControlPointSelectionSummary(selectedControlPointIndexes))
            }
            splineControlPointSlideControls(
                target: entity.target,
                controlPointIndexes: selectedControlPointIndexes.isEmpty
                    ? selectedSplineControlPointSlideIndexes(
                        startIndex: index,
                        maximumControlPointCount: entity.controlPoints.count
                    )
                    : selectedControlPointIndexes,
                accessibilityPrefix: "InspectorCurve.spline.controlPoint"
            )
        }
    }

    @ViewBuilder
    private func splineSmoothConstraintControls(
        _ entity: InspectorSketchEntity,
        controlPointIndex index: Int
    ) -> some View {
        if isSmoothableSplineControlPoint(index, controlPointCount: entity.controlPoints.count) {
            if entity.smoothSplineControlPointIndexes.contains(index) {
                inspectorRow("Smooth", "On")
            } else {
                inspectorActionRow {
                    Button {
                        addSmoothSplineControlPointConstraint(entity, controlPointIndex: index)
                    } label: {
                        Label("Smooth", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .accessibilityIdentifier("InspectorCurve.spline.smoothControlPoint")
                }
            }
        } else {
            inspectorRow("Smooth", "Unavailable")
        }
    }

    @ViewBuilder
    private func splineEndpointTangencyControls(_ entity: InspectorSketchEntity) -> some View {
        if entity.tangentLineCandidates.isEmpty && entity.tangentSplineEndpointCandidates.isEmpty {
            inspectorRow("Endpoint Tangency", "No Targets")
        } else {
            if hasSplineEndpointTangency(entity, endpoint: .start) {
                inspectorRow(
                    "Start Tangent",
                    splineEndpointTangencySummary(
                        lineIDs: entity.startTangentLineIDs,
                        endpoints: entity.startTangentSplineEndpoints
                    )
                )
            }
            if hasSplineEndpointTangency(entity, endpoint: .end) {
                inspectorRow(
                    "End Tangent",
                    splineEndpointTangencySummary(
                        lineIDs: entity.endTangentLineIDs,
                        endpoints: entity.endTangentSplineEndpoints
                    )
                )
            }
            inspectorActionRow {
                if hasSplineEndpointTangency(entity, endpoint: .start) == false {
                    splineEndpointTangencyMenu(
                        "Start Tangent",
                        entity: entity,
                        endpoint: .start
                    )
                } else {
                    Label("Start On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.startTangentOn")
                }

                if hasSplineEndpointTangency(entity, endpoint: .end) == false {
                    splineEndpointTangencyMenu(
                        "End Tangent",
                        entity: entity,
                        endpoint: .end
                    )
                } else {
                    Label("End On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.endTangentOn")
                }
            }
        }
    }

    private func splineEndpointTangencyMenu(
        _ title: String,
        entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint
    ) -> some View {
        Menu {
            if entity.tangentLineCandidates.isEmpty == false {
                Section("Lines") {
                    ForEach(entity.tangentLineCandidates) { candidate in
                        Button {
                            addSplineEndpointTangentConstraint(
                                entity,
                                endpoint: endpoint,
                                lineID: candidate.id
                            )
                        } label: {
                            Label(sketchLineCandidateTitle(candidate), systemImage: "line.diagonal")
                        }
                    }
                }
            }
            if entity.tangentSplineEndpointCandidates.isEmpty == false {
                Section("Splines") {
                    ForEach(entity.tangentSplineEndpointCandidates) { candidate in
                        Button {
                            addTangentSplineEndpointsConstraint(
                                entity,
                                endpoint: endpoint,
                                target: candidate.reference
                            )
                        } label: {
                            Label(sketchSplineEndpointCandidateTitle(candidate), systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                }
            }
        } label: {
            Label(title, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .accessibilityIdentifier("InspectorCurve.spline.\(endpoint.rawValue)Tangent")
    }

    private func hasSplineEndpointTangency(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint
    ) -> Bool {
        switch endpoint {
        case .start:
            return entity.startTangentLineIDs.isEmpty == false ||
                entity.startTangentSplineEndpoints.isEmpty == false
        case .end:
            return entity.endTangentLineIDs.isEmpty == false ||
                entity.endTangentSplineEndpoints.isEmpty == false
        }
    }

    @ViewBuilder
    private func splineEndpointSmoothControls(_ entity: InspectorSketchEntity) -> some View {
        if entity.tangentSplineEndpointCandidates.isEmpty {
            inspectorRow("Endpoint Smooth", "No Targets")
        } else {
            if hasSplineEndpointSmoothness(entity, endpoint: .start) {
                inspectorRow(
                    "Start Smooth",
                    splineEndpointSmoothSummary(endpoints: entity.startSmoothSplineEndpoints)
                )
            }
            if hasSplineEndpointSmoothness(entity, endpoint: .end) {
                inspectorRow(
                    "End Smooth",
                    splineEndpointSmoothSummary(endpoints: entity.endSmoothSplineEndpoints)
                )
            }
            inspectorActionRow {
                if hasSplineEndpointSmoothness(entity, endpoint: .start) == false {
                    splineEndpointSmoothMenu(
                        "Start Smooth",
                        entity: entity,
                        endpoint: .start
                    )
                } else {
                    Label("Start On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.startSmoothOn")
                }

                if hasSplineEndpointSmoothness(entity, endpoint: .end) == false {
                    splineEndpointSmoothMenu(
                        "End Smooth",
                        entity: entity,
                        endpoint: .end
                    )
                } else {
                    Label("End On", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("InspectorCurve.spline.endSmoothOn")
                }
            }
        }
    }

    private func splineEndpointSmoothMenu(
        _ title: String,
        entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint
    ) -> some View {
        Menu {
            ForEach(entity.tangentSplineEndpointCandidates) { candidate in
                Button {
                    addSmoothSplineEndpointsConstraint(
                        entity,
                        endpoint: endpoint,
                        target: candidate.reference
                    )
                } label: {
                    Label(sketchSplineEndpointCandidateTitle(candidate), systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        } label: {
            Label(title, systemImage: "point.3.connected.trianglepath.dotted")
        }
        .accessibilityIdentifier("InspectorCurve.spline.\(endpoint.rawValue)Smooth")
    }

    private func hasSplineEndpointSmoothness(
        _ entity: InspectorSketchEntity,
        endpoint: SketchSplineEndpoint
    ) -> Bool {
        switch endpoint {
        case .start:
            return entity.startSmoothSplineEndpoints.isEmpty == false
        case .end:
            return entity.endSmoothSplineEndpoints.isEmpty == false
        }
    }

    @ViewBuilder
    private func splineControlPointMoveControls(
        _ title: String,
        target: SelectionTarget,
        controlPointIndex: Int,
        accessibilityPrefix: String
    ) -> some View {
        inspectorControlRow("\(title) X") {
            HStack(spacing: 6) {
                sketchEntityMoveButton(
                    systemImage: "arrow.left",
                    help: "Move \(title.lowercased()) negative X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXNegative"
                ) {
                    moveSelectedSplineControlPoint(
                        target,
                        controlPointIndex: controlPointIndex,
                        deltaX: -defaultSketchEntityMoveStepMeters,
                        deltaY: 0.0
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.right",
                    help: "Move \(title.lowercased()) positive X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXPositive"
                ) {
                    moveSelectedSplineControlPoint(
                        target,
                        controlPointIndex: controlPointIndex,
                        deltaX: defaultSketchEntityMoveStepMeters,
                        deltaY: 0.0
                    )
                }
            }
        }
        inspectorControlRow("\(title) Y") {
            HStack(spacing: 6) {
                sketchEntityMoveButton(
                    systemImage: "arrow.down",
                    help: "Move \(title.lowercased()) negative Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYNegative"
                ) {
                    moveSelectedSplineControlPoint(
                        target,
                        controlPointIndex: controlPointIndex,
                        deltaX: 0.0,
                        deltaY: -defaultSketchEntityMoveStepMeters
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.up",
                    help: "Move \(title.lowercased()) positive Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYPositive"
                ) {
                    moveSelectedSplineControlPoint(
                        target,
                        controlPointIndex: controlPointIndex,
                        deltaX: 0.0,
                        deltaY: defaultSketchEntityMoveStepMeters
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func splineControlPointSlideControls(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        accessibilityPrefix: String
    ) -> some View {
        inspectorControlRow("Slide") {
            HStack(spacing: 6) {
                sketchEntityMoveButton(
                    systemImage: "arrow.right",
                    help: "Slide control point positive U",
                    accessibilityIdentifier: "\(accessibilityPrefix).slidePositiveU"
                ) {
                    slideSelectedSplineControlPoints(
                        target,
                        controlPointIndexes: controlPointIndexes,
                        direction: .positiveU
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.left",
                    help: "Slide control point negative U",
                    accessibilityIdentifier: "\(accessibilityPrefix).slideNegativeU"
                ) {
                    slideSelectedSplineControlPoints(
                        target,
                        controlPointIndexes: controlPointIndexes,
                        direction: .negativeU
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.up.right",
                    help: "Slide control point normal",
                    accessibilityIdentifier: "\(accessibilityPrefix).slideNormal"
                ) {
                    slideSelectedSplineControlPoints(
                        target,
                        controlPointIndexes: controlPointIndexes,
                        direction: .normal
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sketchEntityMoveControls(
        _ title: String,
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        accessibilityPrefix: String
    ) -> some View {
        inspectorControlRow("\(title) X") {
            HStack(spacing: 6) {
                sketchEntityMoveButton(
                    systemImage: "arrow.left",
                    help: "Move \(title.lowercased()) negative X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXNegative"
                ) {
                    moveSelectedSketchEntityPoint(
                        target,
                        handle: handle,
                        deltaX: -defaultSketchEntityMoveStepMeters,
                        deltaY: 0.0
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.right",
                    help: "Move \(title.lowercased()) positive X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXPositive"
                ) {
                    moveSelectedSketchEntityPoint(
                        target,
                        handle: handle,
                        deltaX: defaultSketchEntityMoveStepMeters,
                        deltaY: 0.0
                    )
                }
            }
        }
        inspectorControlRow("\(title) Y") {
            HStack(spacing: 6) {
                sketchEntityMoveButton(
                    systemImage: "arrow.down",
                    help: "Move \(title.lowercased()) negative Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYNegative"
                ) {
                    moveSelectedSketchEntityPoint(
                        target,
                        handle: handle,
                        deltaX: 0.0,
                        deltaY: -defaultSketchEntityMoveStepMeters
                    )
                }
                sketchEntityMoveButton(
                    systemImage: "arrow.up",
                    help: "Move \(title.lowercased()) positive Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYPositive"
                ) {
                    moveSelectedSketchEntityPoint(
                        target,
                        handle: handle,
                        deltaX: 0.0,
                        deltaY: defaultSketchEntityMoveStepMeters
                    )
                }
            }
        }
    }

    private func sketchEntityMoveButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func objectShapeSection(_ nodes: [SceneNode]) -> some View {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: session.document,
            currentEvaluation: session.currentEvaluation,
            documentGeneration: session.generation
        )
        let shapes = nodes.map { objectShape(for: $0, in: scene) }
        if shapes.allSatisfy({ $0 != nil }) {
            let resolvedShapes = shapes.compactMap { $0 }
            inspectorSection("Shape") {
                inspectorRow("Object", valueSummary(resolvedShapes.map(objectShapeTitle)))
                inspectorRow(
                    "Source",
                    valueSummary(resolvedShapes.map { $0.definition?.sourceRepresentation.title ?? "Unknown" })
                )
                inspectorRow(
                    "Generated",
                    valueSummary(resolvedShapes.map {
                        $0.definition?.generatedRepresentation(for: $0.properties).title ?? "Unknown"
                    })
                )
                objectCenterControls(resolvedShapes)
                if resolvedShapes.allSatisfy({ $0.typeID == .cube || $0.typeID == .cylinder }) {
                    objectSizeControls(resolvedShapes)
                }
                objectSchemaPropertyRows(resolvedShapes)
            }
        } else {
            inspectorSection("Shape") {
                inspectorRow("Object", "Mixed or Unsupported")
            }
        }
    }

    @ViewBuilder
    private func objectCenterControls(_ shapes: [InspectorObjectShape]) -> some View {
        transformLengthControl(
            "Center X",
            values: shapes.map { $0.center.x },
            sliderRange: transformPositionSliderRange
        ) { meters in
            setObjectCenter(.x, to: meters, for: shapes)
        }
        transformLengthControl(
            "Center Y",
            values: shapes.map { $0.center.y },
            sliderRange: transformPositionSliderRange
        ) { meters in
            setObjectCenter(.y, to: meters, for: shapes)
        }
        transformLengthControl(
            "Center Z",
            values: shapes.map { $0.center.z },
            sliderRange: transformPositionSliderRange
        ) { meters in
            setObjectCenter(.z, to: meters, for: shapes)
        }
    }

    @ViewBuilder
    private func objectSizeControls(_ shapes: [InspectorObjectShape]) -> some View {
        transformLengthControl(
            "Size X",
            values: shapes.map { $0.size.x },
            sliderRange: sizeSliderRange
        ) { meters in
            setObjectSize(.x, to: meters, for: shapes)
        }
        transformLengthControl(
            "Size Y",
            values: shapes.map { $0.size.y },
            sliderRange: sizeSliderRange
        ) { meters in
            setObjectSize(.y, to: meters, for: shapes)
        }
        transformLengthControl(
            "Size Z",
            values: shapes.map { $0.size.z },
            sliderRange: sizeSliderRange
        ) { meters in
            setObjectSize(.z, to: meters, for: shapes)
        }
    }

    private func objectShape(
        for node: SceneNode,
        in scene: ViewportScene
    ) -> InspectorObjectShape? {
        guard let object = node.object,
              object.typeID != nil else {
            return nil
        }
        guard let featureID = node.reference?.featureID else {
            return nil
        }
        guard let item = scene.items.first(where: { $0.featureID == featureID }) else {
            return nil
        }
        let translation = translation(for: node)
        let sourceCenter: InspectorVector3D
        let size: InspectorVector3D
        let cylinder: InspectorCylinderShape?
        switch item.kind {
        case .body(let component):
            sourceCenter = InspectorVector3D(
                x: Double(item.modelBounds.midX),
                y: (component.yMinMeters + component.yMaxMeters) / 2.0,
                z: Double(item.modelBounds.midY)
            )
            size = InspectorVector3D(
                x: component.sizeXMeters,
                y: component.sizeYMeters,
                z: component.sizeZMeters
            )
            cylinder = component.cylinder.map { cylinder in
                InspectorCylinderShape(
                    topRadius: cylinder.topRadiusMeters,
                    bottomRadius: cylinder.bottomRadiusMeters,
                    sideSegments: cylinder.sideSegments,
                    verticalSegments: cylinder.verticalSegments,
                    angleDegrees: cylinder.angleDegrees,
                    hasCaps: cylinder.hasCaps,
                    hollow: cylinder.hollowMeters,
                    cornerRadius: cylinder.cornerRadiusMeters,
                    cornerSideSegments: cylinder.cornerSideSegments
                )
            }
        case .sketch:
            sourceCenter = InspectorVector3D(
                x: Double(item.modelBounds.midX),
                y: 0.0,
                z: Double(item.modelBounds.midY)
            )
            size = InspectorVector3D(
                x: Double(item.modelBounds.width),
                y: 0.0,
                z: Double(item.modelBounds.height)
            )
            cylinder = nil
        }
        return InspectorObjectShape(
            id: node.id,
            featureID: featureID,
            typeID: object.typeID,
            definition: objectDefinition(for: object.typeID),
            properties: object.properties,
            sourceCenter: sourceCenter,
            center: InspectorVector3D(
                x: sourceCenter.x + translation.x,
                y: sourceCenter.y + translation.y,
                z: sourceCenter.z + translation.z
            ),
            size: size,
            cylinder: cylinder
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
            var values = normalizedMatrixValues(node.localTransform.matrix.values)
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

    private func selectedSplineControlPointSlideIndexes(
        startIndex: Int,
        maximumControlPointCount: Int
    ) -> [Int] {
        guard maximumControlPointCount > 0 else {
            return []
        }
        let clampedStartIndex = min(max(startIndex, 0), maximumControlPointCount - 1)
        let requestedCount = max(sketchSplineControlPointSlideCount, 1)
        let upperBound = min(maximumControlPointCount, clampedStartIndex + requestedCount)
        return Array(clampedStartIndex..<upperBound)
    }

    private func selectedSplineControlPointIndexes(for entity: InspectorSketchEntity) -> [Int] {
        var indexes: [Int] = []
        var seenIndexes: Set<Int> = []
        for target in session.selection.selectedTargets {
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchControlPointReference,
                  reference.featureID == entity.sourceFeatureID,
                  reference.entityID == entity.entityID,
                  entity.controlPoints.indices.contains(reference.index),
                  seenIndexes.insert(reference.index).inserted else {
                continue
            }
            indexes.append(reference.index)
        }
        return indexes
    }

    private func selectedSplineControlPointSlideInput() -> (target: SelectionTarget, controlPointIndexes: [Int])? {
        guard case .success(let entity?) = selectedSketchEntityResult,
              entity.entityKind == "spline" else {
            return nil
        }
        let selectedIndexes = selectedSplineControlPointIndexes(for: entity)
        guard selectedIndexes.isEmpty == false else {
            return nil
        }
        return (
            entity.target,
            selectedIndexes
        )
    }

    private func splineControlPointSelectionSummary(_ indexes: [Int]) -> String {
        guard indexes.isEmpty == false else {
            return "None"
        }
        let labels = indexes.sorted().map { String($0 + 1) }.joined(separator: ", ")
        if indexes.count == 1 {
            return "1 CV: \(labels)"
        }
        return "\(indexes.count) CVs: \(labels)"
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

    private func pointDisplayTitle(_ display: PointDisplay?) -> String {
        guard let display else {
            return "Default"
        }
        return display.isVisible ? "Visible" : "Hidden"
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
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.firstEndpoint.reference,
                    parameter: bridgeCurve.firstEndpoint.parameter,
                    reversesSense: bridgeCurve.firstEndpoint.reversesSense,
                    tension: tension
                )
            )
        case .second:
            var tension = bridgeCurve.secondEndpoint.tension
            setBridgeTensionLevel(&tension, level: level, value: nextValue)
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.secondEndpoint.reference,
                    parameter: bridgeCurve.secondEndpoint.parameter,
                    reversesSense: bridgeCurve.secondEndpoint.reversesSense,
                    tension: tension
                )
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
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.firstEndpoint.reference,
                    parameter: .scalar(clampedValue),
                    reversesSense: bridgeCurve.firstEndpoint.reversesSense,
                    tension: bridgeCurve.firstEndpoint.tension
                )
            )
        case .second:
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.secondEndpoint.reference,
                    parameter: .scalar(clampedValue),
                    reversesSense: bridgeCurve.secondEndpoint.reversesSense,
                    tension: bridgeCurve.secondEndpoint.tension
                )
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
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.firstEndpoint.reference,
                    parameter: bridgeCurve.firstEndpoint.parameter,
                    reversesSense: !bridgeCurve.firstEndpoint.reversesSense,
                    tension: bridgeCurve.firstEndpoint.tension
                )
            )
        case .second:
            result = session.setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                secondEndpoint: BridgeCurveEndpoint(
                    reference: bridgeCurve.secondEndpoint.reference,
                    parameter: bridgeCurve.secondEndpoint.parameter,
                    reversesSense: !bridgeCurve.secondEndpoint.reversesSense,
                    tension: bridgeCurve.secondEndpoint.tension
                )
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
        let tolerance = min(max(sketchRebuildToleranceMeters, 0.00001), 0.01)
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
        var values = normalizedMatrixValues(node.localTransform.matrix.values)
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

    private func transformLengthControl(
        _ title: String,
        values: [Double],
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let unit = session.document.displayUnit
        return numericControl(
            title,
            values: values.map { unit.value(fromMeters: $0) },
            sliderRange: sliderRange
        ) { value in
            onChange(unit.meters(from: value))
        } unitLabel: {
            unit.symbol
        }
    }

    private func numericControl(
        _ title: String,
        values: [Double],
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void,
        unitLabel: () -> String = { "" }
    ) -> some View {
        let commonValue = commonInspectorValue(values)
        let textBinding = Binding<String>(
            get: {
                if let commonValue {
                    return commonValue.formatted(.number.precision(.fractionLength(0...6)))
                }
                return "Mixed"
            },
            set: { text in
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmedText), value.isFinite else {
                    return
                }
                onChange(value)
            }
        )
        let sliderBinding = Binding<Double>(
            get: {
                min(max(commonValue ?? 0.0, sliderRange.lowerBound), sliderRange.upperBound)
            },
            set: { value in
                onChange(value)
            }
        )
        let unit = unitLabel()

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                HStack(spacing: 6) {
                    TextField(title, text: textBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: inspectorControlWidth)
                    if !unit.isEmpty {
                        Text(unit)
                            .foregroundStyle(.secondary)
                            .frame(width: inspectorUnitWidth, alignment: .leading)
                    }
                }
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
    }

    private var transformPositionSliderRange: ClosedRange<Double> {
        let unit = session.document.displayUnit
        let span = max(unit.value(fromMeters: session.document.ruler.visibleSpanMeters), 1.0)
        return -span ... span
    }

    private var sizeSliderRange: ClosedRange<Double> {
        let unit = session.document.displayUnit
        let visibleSpan = max(unit.value(fromMeters: session.document.ruler.visibleSpanMeters), 1.0)
        return 0.0 ... visibleSpan
    }

    private func commonInspectorValue(_ values: [Double]) -> Double? {
        guard let first = values.first,
              first.isFinite else {
            return nil
        }
        for value in values {
            guard value.isFinite,
                  abs(value - first) <= 1.0e-9 else {
                return nil
            }
        }
        return first
    }

    private func translation(for node: SceneNode) -> InspectorVector3D {
        let values = normalizedMatrixValues(node.localTransform.matrix.values)
        return InspectorVector3D(x: values[12], y: values[13], z: values[14])
    }

    private func scale(for node: SceneNode) -> InspectorVector3D {
        let values = normalizedMatrixValues(node.localTransform.matrix.values)
        return InspectorVector3D(x: values[0], y: values[5], z: values[10])
    }

    private func setTransformComponent(
        _ component: InspectorTransformComponent,
        to value: Double,
        for nodes: [SceneNode]
    ) {
        for node in nodes {
            var values = normalizedMatrixValues(node.localTransform.matrix.values)
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

    private func normalizedMatrixValues(_ values: [Double]) -> [Double] {
        guard values.count == 16 else {
            return Matrix4x4.identity.values
        }
        return values
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

    @ViewBuilder
    private func materialPicker(_ nodes: [SceneNode]) -> some View {
        let materialIDs = sortedMaterialIDs
        if materialIDs.isEmpty {
            inspectorRow("Material", "No Materials")
        } else {
            inspectorControlRow("Material") {
                Picker(
                    "",
                    selection: Binding(
                        get: {
                            materialChoice(for: nodes)
                        },
                        set: { choice in
                            switch choice {
                            case .mixed:
                                return
                            case .none:
                                for node in nodes {
                                    session.setSceneNodeMaterial(node.id, materialID: nil)
                                }
                            case .material(let materialID):
                                for node in nodes {
                                    session.setSceneNodeMaterial(node.id, materialID: materialID)
                                }
                            }
                        }
                    )
                ) {
                    if materialChoice(for: nodes) == .mixed {
                        Text("Mixed").tag(InspectorMaterialChoice.mixed)
                    }
                    Text("None").tag(InspectorMaterialChoice.none)
                    ForEach(materialIDs, id: \.self) { materialID in
                        if let material = session.document.productMetadata.materialLibrary.materials[materialID] {
                            Text(material.name)
                                .tag(InspectorMaterialChoice.material(materialID))
                        }
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(minWidth: inspectorControlWidth)
            }
        }
    }

    private var sortedMaterialIDs: [MaterialID] {
        session.document.productMetadata.materialLibrary.materials
            .sorted { lhs, rhs in
                lhs.value.name.localizedStandardCompare(rhs.value.name) == .orderedAscending
            }
            .map(\.key)
    }

    private func materialChoice(for nodes: [SceneNode]) -> InspectorMaterialChoice {
        guard let first = nodes.first?.materialID else {
            if nodes.allSatisfy({ $0.materialID == nil }) {
                return .none
            }
            return .mixed
        }
        guard nodes.allSatisfy({ $0.materialID == first }) else {
            return .mixed
        }
        return .material(first)
    }

    @ViewBuilder
    private func referenceInspectorRows(for reference: SceneNodeReference) -> some View {
        switch reference.kind {
        case .feature, .body, .sketch:
            if let featureID = reference.featureID {
                inspectorRow("Feature ID", shortID(featureID))
                if let feature = session.document.cadDocument.designGraph.nodes[featureID] {
                    inspectorRow("Feature Name", feature.name ?? "Unnamed Feature")
                    switch feature.operation {
                    case .sketch:
                        inspectorRow("Operation", "Sketch")
                    case .extrude(let extrude):
                        inspectorRow("Operation", "Extrude")
                        inspectorRow("Profile Source", shortID(extrude.profile.featureID))
                    case .revolve(let revolve):
                        inspectorRow("Operation", "Revolve")
                        inspectorRow("Profile Source", shortID(revolve.profile.featureID))
                        inspectorRow("Axis Origin", pointSummary(revolve.axis.origin))
                        inspectorRow("Axis Direction", vectorSummary(revolve.axis.direction))
                    case .sweep(let sweep):
                        inspectorRow("Operation", "Sweep")
                        inspectorRow("Sections", valueSummary(sweep.sections.map(sweepSectionSummary)))
                        inspectorRow("Path Source", shortID(sweep.path.featureID))
                        if sweep.guides.isEmpty == false {
                            inspectorRow("Guides", valueSummary(sweep.guides.map { shortID($0.featureID) }))
                        }
                    case .polySpline(let polySpline):
                        inspectorRow("Operation", "PolySpline")
                        inspectorRow("Mesh Vertices", "\(polySpline.sourceMesh.positions.count)")
                        inspectorRow("Mesh Triangles", "\(polySpline.sourceMesh.indices.count / 3)")
                    case .faceLoopOffset(let faceLoopOffset):
                        inspectorRow("Operation", "Offset Face Loop")
                        inspectorRow("Target", shortID(faceLoopOffset.target.featureID))
                        inspectorRow("Gap Fill", faceLoopOffset.gapFill.rawValue.capitalized)
                    case .edgeOffset(let edgeOffset):
                        inspectorRow("Operation", "Offset Edge")
                        inspectorRow("Target", shortID(edgeOffset.target.featureID))
                        inspectorRow("Support Face", "\(edgeOffset.supportFacePersistentName.components.count) components")
                        inspectorRow("Gap Fill", edgeOffset.gapFill.rawValue.capitalized)
                    case .faceKnife(let faceKnife):
                        inspectorRow("Operation", "Face Knife")
                        inspectorRow("Target", shortID(faceKnife.target.featureID))
                        inspectorRow("Loop Points", "\(faceKnife.loop.count)")
                    case .bridgeCurve(let bridgeCurve):
                        inspectorRow("Operation", "Bridge Curve")
                        inspectorRow("Start Continuity", String(describing: bridgeCurve.start.requiredLevel).capitalized)
                        inspectorRow("End Continuity", String(describing: bridgeCurve.end.requiredLevel).capitalized)
                        inspectorRow("Samples", "\(bridgeCurve.sampleCount)")
                    case .curveEdit(let curveEdit):
                        inspectorRow("Operation", "Curve Edit")
                        inspectorRow("Source", shortID(curveEdit.source.featureID))
                        inspectorRow("Curve Index", "\(curveEdit.source.curveIndex)")
                        inspectorRow("Edits", "\(curveEdit.edits.count)")
                    case .curveOffset(let curveOffset):
                        inspectorRow("Operation", "Curve Offset")
                        inspectorRow("Source", shortID(curveOffset.source.featureID))
                        inspectorRow("Curve Index", "\(curveOffset.source.curveIndex)")
                        inspectorRow("Side", curveOffset.side.rawValue.capitalized)
                        inspectorRow("Samples", "\(curveOffset.sampleCount)")
                    case .curveTrim(let curveTrim):
                        inspectorRow("Operation", "Curve Trim")
                        inspectorRow("Source", shortID(curveTrim.source.featureID))
                        inspectorRow("Curve Index", "\(curveTrim.source.curveIndex)")
                        inspectorRow("Samples", "\(curveTrim.sampleCount)")
                    }
                    inspectorRow("Inputs", valueSummary(feature.inputs.map { $0.role.rawValue }))
                    inspectorRow("Outputs", valueSummary(feature.outputs.map { $0.role.rawValue }))
                    inspectorRow("Suppressed", feature.isSuppressed ? "Yes" : "No")
                } else {
                    inspectorRow("Feature", "Missing")
                }
            }
        case .componentInstance:
            if let componentInstanceID = reference.componentInstanceID {
                inspectorRow("Instance ID", shortID(componentInstanceID))
                if let instance = session.document.productMetadata.componentInstances[componentInstanceID] {
                    inspectorRow("Instance", instance.name)
                    inspectorRow("Definition", componentDefinitionName(for: instance.definitionID))
                    inspectorRow("Properties", "\(instance.properties.count)")
                } else {
                    inspectorRow("Instance", "Missing")
                }
            }
        case .construction:
            inspectorRow("Role", "Construction")
        }
    }

    @ViewBuilder
    private func objectSourceInspectorRows(for object: ObjectDescriptor) -> some View {
        inspectorRow("Object Role", object.category.title)
        if let geometryRole = object.geometryRole {
            inspectorRow("Geometry Role", geometryRole.title)
        }
        if let typeID = object.typeID {
            inspectorRow("Object Type ID", typeID.rawValue)
            if let definition = objectDefinition(for: typeID) {
                inspectorRow("Source", definition.sourceRepresentation.title)
                inspectorRow("Generated", definition.generatedRepresentation(for: object.properties).title)
            }
            inspectorRow("Properties", "\(object.properties.values.count)")
        }
        if let sourceFeatureID = object.sourceFeatureID {
            inspectorRow("Source Feature", shortID(sourceFeatureID))
        }
        if let sourceSection = object.sourceSection {
            inspectorRow("Source Section", bodySourceSectionSummary(sourceSection))
        }
        if let componentInstanceID = object.componentInstanceID {
            inspectorRow("Component Instance", shortID(componentInstanceID))
        }
    }

    private func objectTitle(for node: SceneNode) -> String {
        if let definition = objectDefinition(for: node.object?.typeID) {
            return definition.title
        }
        if let category = node.object?.category {
            return category.title
        }
        return sceneNodeKindTitle(for: node.reference)
    }

    private func geometryTitle(for node: SceneNode) -> String {
        guard let object = node.object else {
            return "None"
        }
        if let definition = objectDefinition(for: object.typeID),
           let geometryRole = object.geometryRole {
            return "\(geometryRole.title) / \(definition.title)"
        }
        if let geometryRole = object.geometryRole {
            return geometryRole.title
        }
        return object.category.title
    }

    private func objectShapeTitle(_ shape: InspectorObjectShape) -> String {
        if let definition = shape.definition {
            return definition.title
        }
        return shape.typeID?.rawValue ?? "Object"
    }

    @ViewBuilder
    private func objectSchemaPropertyRows(_ shapes: [InspectorObjectShape]) -> some View {
        let definitions = sharedObjectPropertyDefinitions(for: shapes)
        if !definitions.isEmpty {
            ForEach(definitions) { property in
                objectPropertyControl(property, shapes: shapes)
            }
        }
    }

    @ViewBuilder
    private func objectPropertyControl(
        _ property: ObjectPropertyDefinition,
        shapes: [InspectorObjectShape]
    ) -> some View {
        let values = shapes.map { $0.properties.value(for: property.id, default: property.defaultValue) }
        if !property.isEditable || property.inspectorControl == .readOnly {
            inspectorRow(property.title, valueSummary(values.map(formattedObjectProperty)))
        } else {
            switch property.valueKind {
            case .length:
                let unit = session.document.displayUnit
                let meters = values.compactMap { value -> Double? in
                    if case .length(let meters) = value {
                        return meters
                    }
                    return nil
                }
                if meters.count == values.count {
                    let range = lengthRange(for: property)
                    numericControl(
                        property.title,
                        values: meters.map { unit.value(fromMeters: $0) },
                        sliderRange: unit.value(fromMeters: range.lowerBound) ... unit.value(fromMeters: range.upperBound)
                    ) { value in
                        setObjectProperty(property, value: .length(unit.meters(from: value)), for: shapes)
                    } unitLabel: {
                        unit.symbol
                    }
                } else {
                    inspectorRow(property.title, "Mixed")
                }
            case .number:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .number($0) }
            case .integer:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .integer(Int($0.rounded())) }
            case .angle:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .angle($0) }
            case .boolean:
                booleanObjectPropertyControl(property, values: values, shapes: shapes)
            case .text, .material:
                inspectorRow(property.title, valueSummary(values.map(formattedObjectProperty)))
            }
        }
    }

    @ViewBuilder
    private func numericObjectPropertyControl(
        _ property: ObjectPropertyDefinition,
        values: [ObjectPropertyValue],
        shapes: [InspectorObjectShape],
        makeValue: @escaping (Double) -> ObjectPropertyValue
    ) -> some View {
        let numbers = values.compactMap { value -> Double? in
            switch value {
            case .number(let number), .angle(let number):
                return number
            case .integer(let integer):
                return Double(integer)
            default:
                return nil
            }
        }
        if numbers.count == values.count {
            let range = property.numericRange.map { $0.lowerBound ... $0.upperBound } ?? 0.0 ... 100.0
            numericControl(
                property.title,
                values: numbers,
                sliderRange: range
            ) { value in
                setObjectProperty(property, value: makeValue(value), for: shapes)
            }
        } else {
            inspectorRow(property.title, "Mixed")
        }
    }

    private func booleanObjectPropertyControl(
        _ property: ObjectPropertyDefinition,
        values: [ObjectPropertyValue],
        shapes: [InspectorObjectShape]
    ) -> some View {
        let commonValue = commonObjectBoolean(values)
        let binding = Binding<InspectorBoolChoice>(
            get: {
                guard let commonValue else {
                    return .mixed
                }
                return commonValue ? .on : .off
            },
            set: { choice in
                switch choice {
                case .mixed:
                    return
                case .on:
                    setObjectProperty(property, value: .boolean(true), for: shapes)
                case .off:
                    setObjectProperty(property, value: .boolean(false), for: shapes)
                }
            }
        )
        return inspectorControlRow(property.title) {
            Picker(property.title, selection: binding) {
                ForEach(InspectorBoolChoice.allCases) { choice in
                    Text(choice.rawValue)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
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

    private func lengthRange(for property: ObjectPropertyDefinition) -> ClosedRange<Double> {
        if let numericRange = property.numericRange {
            return numericRange.lowerBound ... numericRange.upperBound
        }
        return 0.0 ... max(session.document.ruler.visibleSpanMeters, 1.0)
    }

    private func lengthSliderRange(for meters: Double) -> ClosedRange<Double> {
        let unit = session.document.displayUnit
        let upperMeters = max(meters * 4.0, session.document.ruler.visibleSpanMeters, 0.001)
        return 0.0 ... max(unit.value(fromMeters: upperMeters), 0.0001)
    }

    private func bridgeTensionSliderRange(for value: Double) -> ClosedRange<Double> {
        0.05 ... max(3.0, value * 2.0)
    }

    private var regionOffsetSliderRange: ClosedRange<Double> {
        lengthSliderRange(for: regionOffsetDistanceMeters)
    }

    private func commonObjectBoolean(_ values: [ObjectPropertyValue]) -> Bool? {
        guard let first = values.first,
              case .boolean(let firstValue) = first else {
            return nil
        }
        for value in values {
            guard case .boolean(let boolValue) = value,
                  boolValue == firstValue else {
                return nil
            }
        }
        return firstValue
    }

    private func sharedObjectPropertyDefinitions(
        for shapes: [InspectorObjectShape]
    ) -> [ObjectPropertyDefinition] {
        guard let firstTypeID = shapes.first?.typeID,
              shapes.allSatisfy({ $0.typeID == firstTypeID }),
              let definition = objectDefinition(for: firstTypeID) else {
            return []
        }
        var existingPropertyIDs: Set<ObjectPropertyID> = []
        if shapes.allSatisfy({ $0.typeID == .cube || $0.typeID == .cylinder }) {
            existingPropertyIDs.formUnion(["size.x", "size.y", "size.z"])
        }
        return definition.properties.filter { !existingPropertyIDs.contains($0.id) }
    }

    private func objectDefinition(
        for typeID: ObjectTypeID?
    ) -> ObjectTypeDefinition? {
        objectRegistry.definition(for: typeID)
    }

    private func formattedObjectProperty(_ value: ObjectPropertyValue) -> String {
        switch value {
        case .length(let meters):
            formatted(meters)
        case .number(let number):
            number.formatted(.number.precision(.fractionLength(0...4)))
        case .integer(let integer):
            "\(integer)"
        case .boolean(let boolean):
            boolean ? "Yes" : "No"
        case .angle(let degrees):
            formattedDegrees(degrees)
        case .text(let text):
            text
        case .material(let materialID):
            materialID.map { shortID($0) } ?? "None"
        }
    }

    private func sketchEntityKindTitle(_ kind: String) -> String {
        switch kind {
        case "point":
            return "Point"
        case "line":
            return "Line"
        case "circle":
            return "Circle"
        case "arc":
            return "Arc"
        case "spline":
            return "Spline"
        default:
            return kind
        }
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

    private func curveContinuityJoinSummary(_ join: InspectorCurveContinuityJoin) -> String {
        var parts = [
            continuityJoinKindTitle(join.joinKind),
            continuityTitle(join.actualContinuity),
        ]
        if let requiredContinuity = join.requiredContinuity {
            parts.append("requires \(continuityTitle(requiredContinuity))")
        }
        let constraints = constraintKindsSummary(join.constraintKinds)
        if constraints.isEmpty == false {
            parts.append(constraints)
        }
        return parts.joined(separator: " / ")
    }

    private func continuityJoinKindTitle(_ kind: CurveAnalysisResult.ContinuityJoinKind) -> String {
        switch kind {
        case .internalSplineKnot:
            return "Internal knot"
        case .constrainedEndpoint:
            return "Endpoint"
        }
    }

    private func continuityTitle(_ level: CurveAnalysisResult.ContinuityLevel) -> String {
        switch level {
        case .disconnected:
            return "Disconnected"
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func surfaceContinuityTitle(_ level: RupaCore.SurfaceContinuityResult.ContinuityLevel) -> String {
        switch level {
        case .disconnected:
            return "Disconnected"
        case .g0:
            return "G0"
        case .g1:
            return "G1"
        case .g2:
            return "G2"
        }
    }

    private func surfaceContinuityCountsSummary(_ continuity: InspectorSurfaceContinuity) -> String {
        [
            "\(continuity.g0AdjacencyCount) G0",
            "\(continuity.g1AdjacencyCount) G1",
            "\(continuity.g2AdjacencyCount) G2",
        ]
        .joined(separator: ", ")
    }

    private func surfaceContinuitySolveSummary(_ continuity: InspectorSurfaceContinuity) -> String {
        continuity.unresolvedG2AdjacencyCount == 0
            ? "Not required"
            : "\(continuity.unresolvedG2AdjacencyCount) required"
    }

    private func surfaceAdjacencyEdgeSummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        let names = adjacency.edgePersistentNames.map(surfacePersistentNameTail)
        return valueSummary(names.isEmpty ? [shortID(adjacency.id)] : names)
    }

    private func surfaceAdjacencyFaceSummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        valueSummary([
            surfacePersistentNameTail(adjacency.firstFacePersistentName),
            surfacePersistentNameTail(adjacency.secondFacePersistentName),
        ])
    }

    private func surfaceAdjacencyContinuitySummary(_ adjacency: InspectorSurfaceAdjacency) -> String {
        var parts = [surfaceContinuityTitle(adjacency.continuity)]
        if adjacency.requiresCurvatureContinuitySolve {
            parts.append("G2 solve required")
        }
        return parts.joined(separator: " / ")
    }

    private func surfaceAnalysisFaceSummary(_ face: InspectorSurfaceFaceAnalysis) -> String {
        let names = face.facePersistentNames.map(surfacePersistentNameTail)
        return valueSummary(names.isEmpty ? [shortID(face.id)] : names)
    }

    private func surfaceTrimBoundarySummary(
        boundaryCount: Int,
        innerCount: Int,
        openCount: Int
    ) -> String {
        var parts = ["\(boundaryCount) total"]
        if innerCount > 0 {
            parts.append("\(innerCount) inner")
        }
        if openCount > 0 {
            parts.append("\(openCount) open")
        }
        return parts.joined(separator: ", ")
    }

    private func surfacePersistentNameTail(_ name: String?) -> String {
        guard let name, name.isEmpty == false else {
            return "Unknown"
        }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    private func surfaceDiagnosticsSummary(_ diagnostics: [EditorDiagnostic]) -> String {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(errors) errors, \(warnings) warnings, \(info) info"
    }

    private func constraintKindsSummary(_ kinds: [String]) -> String {
        kinds.map { kind in
            switch kind {
            case "coincident":
                return "Coincident"
            case "tangentSplineEndpoints":
                return "Tangent"
            case "smoothSplineEndpoints":
                return "Smooth"
            case "splineKnot":
                return "Spline knot"
            default:
                return kind
            }
        }
        .joined(separator: ", ")
    }

    private func formattedCurvature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...4)))) 1/m"
    }

    private func formattedGaussianCurvature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...4)))) 1/m^2"
    }

    private func formattedSurfaceDirection(_ vector: SurfaceAnalysisResult.Vector) -> String {
        let x = vector.x.formatted(.number.precision(.fractionLength(0...3)))
        let y = vector.y.formatted(.number.precision(.fractionLength(0...3)))
        let z = vector.z.formatted(.number.precision(.fractionLength(0...3)))
        return "x \(x), y \(y), z \(z)"
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

    private func sketchLineCandidateTitle(_ candidate: InspectorSketchLineCandidate) -> String {
        if let length = sketchLineLength(start: candidate.start, end: candidate.end) {
            return "Line \(shortID(candidate.id))  \(formatted(length))"
        }
        return "Line \(shortID(candidate.id))"
    }

    private func bridgeContinuityTitle(_ continuity: BridgeCurveContinuity) -> String {
        "\(bridgeEndpointContinuityTitle(continuity.first)) / \(bridgeEndpointContinuityTitle(continuity.second))"
    }

    private func bridgeEndpointContinuityTitle(_ continuity: BridgeCurveEndpointContinuity) -> String {
        switch continuity {
        case .g0:
            return "G0 Position"
        case .g1:
            return "G1 Tangent"
        case .g2:
            return "G2 Curvature"
        case .g3:
            return "G3 Curvature"
        }
    }

    private func sketchReferenceTitle(_ reference: SketchReference) -> String {
        switch reference {
        case .entity(let entityID):
            return "Entity \(shortID(entityID))"
        case .lineStart(let entityID):
            return "Line \(shortID(entityID)) Start"
        case .lineEnd(let entityID):
            return "Line \(shortID(entityID)) End"
        case .circleCenter(let entityID):
            return "Circle \(shortID(entityID)) Center"
        case .circleRadius(let entityID):
            return "Circle \(shortID(entityID)) Radius"
        case .arcCenter(let entityID):
            return "Arc \(shortID(entityID)) Center"
        case .arcStart(let entityID):
            return "Arc \(shortID(entityID)) Start"
        case .arcEnd(let entityID):
            return "Arc \(shortID(entityID)) End"
        case .arcRadius(let entityID):
            return "Arc \(shortID(entityID)) Radius"
        case .splineControlPoint(let entityID, let index):
            return "Spline \(shortID(entityID)) Point \(index + 1)"
        }
    }

    private func sketchSplineEndpointCandidateTitle(_ candidate: InspectorSplineEndpointCandidate) -> String {
        "Spline \(shortID(candidate.splineID)) \(candidate.endpoint.rawValue)"
    }

    private func splineEndpointTangencySummary(
        lineIDs: Set<SketchEntityID>,
        endpoints: Set<SketchSplineEndpointReference>
    ) -> String {
        let lineSummaries = lineIDs.map { "Line \(shortID($0))" }
        let endpointSummaries = endpoints.map { "Spline \(shortID($0.splineID)) \($0.endpoint.rawValue)" }
        return (lineSummaries + endpointSummaries)
            .sorted()
            .joined(separator: ", ")
    }

    private func splineEndpointSmoothSummary(
        endpoints: Set<SketchSplineEndpointReference>
    ) -> String {
        endpoints.map { "Spline \(shortID($0.splineID)) \($0.endpoint.rawValue)" }
            .sorted()
            .joined(separator: ", ")
    }

    private func clampedSplineControlPointIndex(for entity: InspectorSketchEntity) -> Int {
        clamped(selectedSplineControlPointIndex, in: entity.controlPoints.indices)
    }

    private func isSmoothableSplineControlPoint(_ index: Int, controlPointCount: Int) -> Bool {
        index > 0 && index < controlPointCount - 1 && index.isMultiple(of: 3)
    }

    private func clamped(_ value: Int, in range: Range<Int>) -> Int {
        guard let lowerBound = range.first,
              let upperBound = range.last else {
            return 0
        }
        return min(max(value, lowerBound), upperBound)
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
        let bounded = min(length / 4.0, max(session.document.ruler.visibleSpanMeters / 20.0, 0.001))
        return max(bounded, defaultSketchEntityMoveStepMeters)
    }

    @ViewBuilder
    private func matrixInspectorRows(_ values: [Double]) -> some View {
        if values.count == 16 {
            inspectorRow("M1", matrixRow(values, row: 0))
            inspectorRow("M2", matrixRow(values, row: 1))
            inspectorRow("M3", matrixRow(values, row: 2))
            inspectorRow("M4", matrixRow(values, row: 3))
        } else {
            inspectorRow("Matrix", "Invalid")
        }
    }

    private func matrixRow(_ values: [Double], row: Int) -> String {
        let offset = row * 4
        return values[offset ..< offset + 4]
            .map { formattedMatrixValue($0) }
            .joined(separator: "  ")
    }

    private func formattedMatrixValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private func transformSummary(for nodes: [SceneNode]) -> String {
        let identityCount = nodes.filter { $0.localTransform.matrix == .identity }.count
        if identityCount == nodes.count {
            return "Identity"
        }
        if identityCount == 0 {
            return nodes.count == 1 ? "Custom Matrix" : "Custom Matrices"
        }
        return "Mixed"
    }

    private func referenceTitle(for reference: SceneNodeReference?) -> String {
        guard let reference else {
            return "Group"
        }
        return sceneNodeKindTitle(for: reference)
    }

    private func referenceSummary(for nodes: [SceneNode]) -> String {
        valueSummary(nodes.map { referenceTitle(for: $0.reference) })
    }

    private func parentTitle(for id: SceneNodeID) -> String {
        guard let parent = parentSceneNode(for: id) else {
            return "Root"
        }
        return parent.name
    }

    private func parentSummary(for nodes: [SceneNode]) -> String {
        valueSummary(nodes.map { parentTitle(for: $0.id) })
    }

    private func parentSceneNode(for id: SceneNodeID) -> SceneNode? {
        session.document.productMetadata.sceneNodes.values.first { node in
            node.childIDs.contains(id)
        }
    }

    private func descendantCount(for id: SceneNodeID) -> Int {
        guard let node = session.document.productMetadata.sceneNodes[id] else {
            return 0
        }
        return node.childIDs.reduce(node.childIDs.count) { count, childID in
            count + descendantCount(for: childID)
        }
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

    private func bodySourceSectionSummary(_ section: BodySourceSectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(shortID(profile.featureID))"
        case .curve(let featureID):
            return "Curve \(shortID(featureID))"
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

    private var displayUnitPicker: some View {
        inspectorControlRow("Display Unit") {
            Picker(
                "",
                selection: Binding(
                    get: { session.document.displayUnit },
                    set: { session.setDisplayUnit($0) }
                )
            ) {
                ForEach(LengthDisplayUnit.allCases) { unit in
                    Text(unit.symbol)
                        .tag(unit)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func lengthControl(
        _ title: String,
        meters: Double,
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let unit = session.document.displayUnit
        let value = unit.value(fromMeters: meters)
        let fieldBinding = Binding<Double>(
            get: { value },
            set: { newValue in
                onChange(unit.meters(from: max(newValue, 0.0)))
            }
        )
        let sliderBinding = Binding<Double>(
            get: { min(max(value, sliderRange.lowerBound), sliderRange.upperBound) },
            set: { newValue in
                onChange(unit.meters(from: newValue))
            }
        )

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                HStack(spacing: 6) {
                    TextField(title, value: fieldBinding, formatter: inspectorNumberFormatter)
                        .multilineTextAlignment(.trailing)
                        .frame(width: inspectorControlWidth)
                    Text(unit.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: inspectorUnitWidth, alignment: .leading)
                }
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
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

        let minimum = ruler.displayUnit.meters(from: 0.0001)
        ruler.minorTickMeters = max(ruler.minorTickMeters, minimum)
        ruler.majorTickMeters = max(ruler.majorTickMeters, ruler.minorTickMeters * 2.0)
        ruler.visibleSpanMeters = max(ruler.visibleSpanMeters, ruler.majorTickMeters)
        session.setRulerConfiguration(ruler)
    }

    private func inspectorRow(_ title: String, _ meters: Double) -> some View {
        inspectorControlRow(title) {
            Text(formatted(meters))
                .monospacedDigit()
        }
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        inspectorControlRow(title) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .textSelection(.enabled)
        }
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
        let unit = session.document.displayUnit
        let value = unit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(unit.symbol)"
    }

    private func formattedDimensionValue(
        _ value: Double,
        kind: DimensionCommandEntry.ValueKind
    ) -> String {
        switch kind {
        case .length:
            return formatted(value)
        case .angle:
            return formattedDegrees(degrees(fromRadians: value))
        }
    }

    private func displayedDimensionValue(
        _ value: Double,
        kind: DimensionCommandEntry.ValueKind
    ) -> Double {
        switch kind {
        case .length:
            return session.document.displayUnit.value(fromMeters: value)
        case .angle:
            return degrees(fromRadians: value)
        }
    }

    private func modelDimensionValue(
        _ value: Double,
        kind: DimensionCommandEntry.ValueKind
    ) -> Double {
        switch kind {
        case .length:
            return session.document.displayUnit.meters(from: value)
        case .angle:
            return value * Double.pi / 180.0
        }
    }

    private func dimensionInputUnitSymbol(_ kind: DimensionCommandEntry.ValueKind) -> String {
        switch kind {
        case .length:
            return session.document.displayUnit.symbol
        case .angle:
            return "deg"
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
