import Foundation
import MacComponent
import RupaCore
import RupaDomainFoundation
import RupaKit
import RupaPreview
import RupaRendering
import SwiftUI

@MainActor
public struct MainView: View {
    private let workspace: ProjectWorkspace
    private let domainRegistry: DomainRegistry
    private let operationSequencer: ProjectWorkspaceOperationSequencer
    private let newProject: @MainActor () -> Void

    public init(
        workspace: ProjectWorkspace,
        domainRegistry: DomainRegistry = DomainRegistry(),
        operationSequencer: ProjectWorkspaceOperationSequencer,
        newProject: @escaping @MainActor () -> Void = {}
    ) {
        self.workspace = workspace
        self.domainRegistry = domainRegistry
        self.operationSequencer = operationSequencer
        self.newProject = newProject
    }

    public var body: some View {
        Group {
            if let snapshot = workspace.view {
                ProjectMainViewContent(
                    workspace: workspace,
                    snapshot: snapshot,
                    domainRegistry: domainRegistry,
                    operationSequencer: operationSequencer,
                    newProject: newProject
                )
                .id(snapshot.documentLifetimeID)
            } else {
                ProgressView("Loading Project")
                    .frame(minWidth: 1_120, minHeight: 720)
            }
        }
    }
}

@MainActor
private struct ProjectMainViewContent: View {
    private let workspace: ProjectWorkspace
    private let snapshot: ProjectViewSnapshot
    @State private var selectedTool: ModelingTool
    @State private var polygonToolState: PolygonToolState
    @State private var sketchInputState: SketchInputState
    @State private var transientDiagnostics: [EditorDiagnostic]
    @State private var hoveredTarget: SelectionTarget?
    @State private var hoveredReference: SelectionReference?
    @State private var isPreviewExpanded: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var isInspectorPresented: Bool
    @State private var sidebarSearchText: String
    @State private var workspacePlaneMode: WorkspacePlaneMode
    @State private var selectionScope: WorkspaceSelectionScope
    @State private var selectionDragPreviewTargets: [SelectionTarget]
    @State private var selectionDragPreviewSceneNodeIDs: Set<SceneNodeID>
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
    @State private var viewportOverlayExclusions: [ViewportCanvasOverlayExclusion]
    @State private var viewportCameraResetSignal: Int
    @State private var isUtilityRailExpanded: Bool
    @State private var viewAlignedConstructionPlaneRequest: ViewAlignedConstructionPlaneRequest?
    @State private var viewportProjectionRequest: ViewportProjectionRequest?
    @State private var viewportCameraFrame: ViewportCameraFrame
    @State private var viewportCameraFrameRequest: ViewportCameraFrameRequest?
    @State private var viewportProjectedGridStepMeters: Double?
    @State private var constructionPlaneRenameTargetID: ConstructionPlaneSourceID?
    @State private var constructionPlaneRenameText: String
    @State private var hoveredViewportPickingBackend: ViewportPickingBackend?
    @State private var viewportHoverClearSignal: Int
    private let operationSequencer: ProjectWorkspaceOperationSequencer
    @FocusState private var isWorkspaceFocused: Bool

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
        isInspectorPresented: Bool = false,
        isUtilityRailExpanded: Bool = false,
        domainRegistry: DomainRegistry = DomainRegistry(),
        operationSequencer: ProjectWorkspaceOperationSequencer,
        newProject: @escaping @MainActor () -> Void = {}
    ) {
        let editingDefaults = WorkspaceInteractionScaleDefaults(ruler: snapshot.workspaceState.ruler)
        let ruler = snapshot.workspaceState.ruler.normalizedForWorkspaceScale()
        self.workspace = workspace
        self.snapshot = snapshot
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
        self._viewportContextPanelHeight = State(initialValue: 0.0)
        self._viewportOverlayExclusions = State(initialValue: [])
        self._viewportCameraResetSignal = State(initialValue: 0)
        self._isUtilityRailExpanded = State(initialValue: isUtilityRailExpanded)
        self._viewAlignedConstructionPlaneRequest = State(initialValue: nil)
        self._viewportProjectionRequest = State(initialValue: nil)
        self._viewportCameraFrame = State(initialValue: ViewportCameraFrame(
            target: .origin,
            visibleHeightMeters: ruler.visibleSpanMeters,
            camera: .identity
        ))
        self._viewportCameraFrameRequest = State(initialValue: nil)
        self._viewportProjectedGridStepMeters = State(initialValue: nil)
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

    private func reportToolStatus(
        _ message: String,
        severity: EditorDiagnostic.Severity = .info
    ) {
        transientDiagnostics.append(
            EditorDiagnostic(severity: severity, message: message)
        )
    }

    private func enqueueWorkspaceOperation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
        let expectedDocumentLifetimeID = snapshot.documentLifetimeID
        return operationSequencer.enqueue(
            operationGuard: {
                guard workspace.view?.documentLifetimeID == expectedDocumentLifetimeID else {
                    throw ProjectWorkspaceActionError(
                        code: .documentLifetimeMismatch,
                        message: "The queued UI operation belongs to a replaced project document."
                    )
                }
            },
            operation
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
                isPreviewExpanded = true
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
        let task = enqueueWorkspaceOperation {
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            var selection = current.selection
            try mutation(&selection, current.document.document)
            let published = try await workspace.applySelection(.replace(selection))
            completion(published)
            return published
        }
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
                isPreviewExpanded = true
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
        var selection = snapshot.selection
        do {
            try update(&selection, snapshot.document.document)
            submitSelectionMutation(update)
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
        let task = enqueueWorkspaceOperation {
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
                isPreviewExpanded = true
            }
        }
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
            isPreviewExpanded = true
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
        if commit.diagnostics.isEmpty == false {
            isPreviewExpanded = true
        }
        return commit.commandResults
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
        case .sketch, .polygon, .arc, .spline, .solid, .surface:
            return true
        case .select, .sweep, .mesh, .measure, .section:
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
        guard let name = snapshot.document.document.cadDocument.metadata.name,
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
            WorkspaceCanvasOverlayHost(
                isContextPanelVisible: isViewportContextPanelVisible,
                onHover: handleWorkspaceOverlayHover,
                onContextPanelHeightChange: setViewportContextPanelHeight,
                onExclusionsChange: setViewportOverlayExclusions
            ) {
                viewportCanvas
            } topBar: {
                workspaceTopBar
            } toolPalette: {
                floatingToolPalette
            } utilityRail: {
                workspaceUtilityRail
            } contextPanel: {
                viewportContextPanelContainer
            }
        } content: {
            PreviewSurface(
                document: snapshot.document.document,
                ruler: snapshot.workspaceState.ruler,
                evaluationStatus: snapshot.evaluationSnapshot.status,
                evaluatedGeneration: snapshot.evaluationSnapshot.evaluatedGeneration,
                evaluatedBodyCount: snapshot.evaluationSnapshot.bodyCount,
                diagnostics: diagnostics
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
        }
    }

    private var viewportCanvas: some View {
        let sectionAnalysis = selectedSectionAnalysisSummary
        let scaleSummary = workspaceScaleSummary
        let scaleFitPromptState = workspaceScaleFitPromptState
        return Viewport(
            document: snapshot.document.document,
            presentationScene: snapshot.viewport,
            presentationSceneNodeIDByOccurrenceID: snapshot.sceneNodeIDByOccurrenceID,
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
            currentEvaluation: snapshot.cadInteraction,
            documentGeneration: snapshot.documentGeneration,
            objectRegistry: objectRegistry,
            renderInvalidation: snapshot.evaluationSnapshot.renderInvalidation,
            selection: displaySelection,
            objectSelectionIndex: viewportObjectSelectionIndex,
            selectionDragPreviewTargets: selectionDragPreviewTargets,
            presentationPreviewSceneNodeIDs: selectionDragPreviewSceneNodeIDs,
            patternArrayCurvePathReplacementPreviewRequest: patternArrayCurvePathReplacementPreviewRequest,
            surfaceAnalysis: selectedSurfaceAnalysisSummary,
            surfaceAnalysisOptions: surfaceAnalysisOptions,
            surfaceContinuity: selectedSurfaceContinuitySummary,
            sectionAnalysis: sectionAnalysis,
            sectionClippingPlan: selectedSectionClippingPlan(for: sectionAnalysis),
            snapResolutionOptions: activeSnapResolutionOptions(),
            canvasDragPreviewKind: canvasDragPreviewKind,
            canvasPlacementPreviewKind: canvasPlacementPreviewKind,
            canvasDragAxisConstraint: activeCanvasDragAxisConstraint,
            canvasDragSketchPlaneOverride: workspacePlaneMode.sketchPlane,
            projectionRequest: viewportProjectionRequest,
            cameraFrameRequest: viewportCameraFrameRequest,
            selectionHitPolicy: selectionScope.viewportSelectionHitPolicy,
            bottomChromeReservedHeight: viewportBottomChromeReservedHeight,
            canvasOverlayExclusions: viewportOverlayExclusions,
            gridVisualSpacingMode: snapshot.workspaceState.viewportGridSettings.visualSpacingMode,
            workspaceScalePresetTitle: scaleSummary.presetTitle,
            workspaceScalePresetOptions: WorkspaceScalePreset.profiles,
            canFitWorkspaceScaleToModel: scaleFitPromptState?.isActionable == true,
            canSelectSmallerWorkspaceScale: scaleSummary.smallerPreset != nil,
            canSelectLargerWorkspaceScale: scaleSummary.largerPreset != nil,
            cameraResetSignal: viewportCameraResetSignal,
            hoverClearSignal: viewportHoverClearSignal,
            showsConstructionPlaneHover: showsConstructionPlaneHover,
            allowsSelectionRectangle: allowsSelectionRectangle,
            allowsObjectAffordances: allowsObjectAffordances,
            slotWidthMeters: slotProfileWidthMeters,
            sketchVertexOffsetDistanceMeters: sketchVertexOffsetDistanceMeters,
            edgeOffsetDistanceMeters: edgeOffsetDistanceMeters,
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
            onBodyMoveDrag: viewportBodyMoveDragHandler,
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
            onConstructionPlaneHandleDrag: viewportConstructionPlaneHandleDragHandler,
            onCommandConfirm: viewportCommandConfirmHandler,
            onFitWorkspaceScaleToModel: fitWorkspaceScaleToModel,
            onSelectSmallerWorkspaceScale: selectSmallerWorkspaceScalePreset,
            onSelectLargerWorkspaceScale: selectLargerWorkspaceScalePreset,
            onSelectWorkspaceScalePreset: applyWorkspaceScalePreset,
            onHover: viewportHoverHandler,
            onSnapCandidateKindChange: { kind in
                snapOverrideState.updateHoveredCandidateKind(kind)
            },
            onProjectionBasisChange: { basis in
                viewportProjectionBasis = basis
            },
            onCameraFrameChange: { frame in
                viewportCameraFrame = frame
            },
            onProjectedGridStepChange: { stepMeters in
                viewportProjectedGridStepMeters = stepMeters
            }
        )
    }

    private func setViewportContextPanelHeight(_ height: CGFloat) {
        guard abs(viewportContextPanelHeight - height) > 0.5 else {
            return
        }
        viewportContextPanelHeight = height
    }

    private func setViewportOverlayExclusions(_ exclusions: [ViewportCanvasOverlayExclusion]) {
        guard viewportOverlayExclusions != exclusions else {
            return
        }
        viewportOverlayExclusions = exclusions
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

    private var viewportBodyMoveDragHandler: ((ViewportBodyMoveDragTarget) -> Void)? {
        guard selectionScope.allowsPresentationOccurrencePick(for: selectedTool),
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportBodyMoveDrag(target)
        }
    }

    private var viewportVertexDragHandler: ((ViewportVertexDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportVertexDrag(target)
        }
    }

    private var viewportFaceDragHandler: ((ViewportFaceDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .face,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportFaceDrag(target)
        }
    }

    private var viewportEdgeChamferDragHandler: ((ViewportEdgeChamferDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .edge,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportEdgeChamferDrag(target)
        }
    }

    private var viewportEdgeFilletDragHandler: ((ViewportEdgeFilletDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .edge,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportEdgeFilletDrag(target)
        }
    }

    private var viewportRegionOffsetDragHandler: ((ViewportRegionOffsetDragTarget) -> Void)? {
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectionScope == .edge,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectionScope == .sketchEntity,
              selectedSketchVertexOffsetTarget != nil else {
            return nil
        }
        return { target in
            handleViewportSketchVertexOffsetDrag(target)
        }
    }

    private var viewportPatternArrayLinearAxisDragHandler: ((ViewportPatternArrayLinearAxisDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayLinearAxisDrag(target)
        }
    }

    private var viewportIndependentCopyExtrudeDistanceDragHandler: ((ViewportIndependentCopyExtrudeDistanceDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyExtrudeDistanceDrag(target)
        }
    }

    private var viewportIndependentCopyBodyDimensionDragHandler: ((ViewportIndependentCopyBodyDimensionDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext else {
            return nil
        }
        return { target in
            handleViewportIndependentCopyBodyDimensionDrag(target)
        }
    }

    private var viewportPatternArrayRadialAngleDragHandler: ((ViewportPatternArrayRadialAngleDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayRadialAngleDrag(target)
        }
    }

    private var viewportPatternArrayCopyCountDragHandler: ((ViewportPatternArrayCopyCountDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCopyCountDrag(target)
        }
    }

    private var viewportPatternArrayCurveExtentDragHandler: ((ViewportPatternArrayCurveExtentDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayCurvePathPointDrag(target)
        }
    }

    private var viewportPatternArrayOutputModeChangeHandler: ((ViewportPatternArrayOutputModeTarget) -> Void)? {
        guard selectedTool == .select,
              selectedPresentationHasExactCADAffordanceContext,
              patternArrayInspectorState(for: selectedSceneNodes) != nil else {
            return nil
        }
        return { target in
            handleViewportPatternArrayOutputModeChange(target)
        }
    }

    private var viewportSketchCurveHandleDragHandler: ((ViewportSketchCurveHandleDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchCurveHandleDrag(target)
        }
    }

    private var viewportSketchDimensionDragHandler: ((ViewportSketchDimensionDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchDimensionDrag(target)
        }
    }

    private var viewportSketchPointHandleDragHandler: ((ViewportSketchPointHandleDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSketchPointHandleDrag(target)
        }
    }

    private var viewportSplineControlPointDragHandler: ((ViewportSplineControlPointDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportSplineControlPointDrag(target)
        }
    }

    private var viewportBridgeCurveEndpointDragHandler: ((ViewportBridgeCurveEndpointDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
            return nil
        }
        return { target in
            handleViewportBridgeCurveEndpointDrag(target)
        }
    }

    private var viewportSplineControlPointSlideDragHandler: ((ViewportSplineControlPointSlideDragTarget) -> Void)? {
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexDrag(target)
        }
    }

    private var viewportSurfaceControlPointDragHandler: ((ViewportSurfaceControlPointDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointDrag(target)
        }
    }

    private var viewportSurfaceTrimEndpointDragHandler: ((ViewportSurfaceTrimEndpointDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimEndpointDrag(target)
        }
    }

    private var viewportSurfaceTrimControlPointDragHandler: ((ViewportSurfaceTrimControlPointDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceTrimControlPointDrag(target)
        }
    }

    private var viewportPolySplineSurfaceVertexSlideDragHandler: ((ViewportPolySplineSurfaceVertexSlideDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive else {
            return nil
        }
        return { target in
            handleViewportPolySplineSurfaceVertexSlideDrag(target)
        }
    }

    private var viewportSurfaceControlPointSlideDragHandler: ((ViewportSurfaceControlPointSlideDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive else {
            return nil
        }
        return { target in
            handleViewportSurfaceControlPointSlideDrag(target)
        }
    }

    private var viewportSurfaceFrameDragHandler: ((ViewportSurfaceFrameDragTarget) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .vertex,
              selectedPresentationHasExactCADAffordanceContext,
              slideCommandState.isSurfaceControlVerticesActive == false else {
            return nil
        }
        return { target in
            handleViewportSurfaceFrameDrag(target)
        }
    }

    private var viewportConstructionPlaneHandleDragHandler: ((ViewportConstructionPlaneDragTarget) -> Void)? {
        guard selectedTool == .select,
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
        regionOffsetCommandState.isActive
            || edgeOffsetCommandState.isActive
            || slotProfileCommandState.isActive
            || slideCommandState.isActive
    }

    @discardableResult
    private func confirmActiveWorkspaceCommand() -> Bool {
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
        if regionOffsetCommandState.isActive {
            regionOffsetCommandState.deactivate()
            reportToolStatus("Offset Region complete.")
            return true
        }
        if edgeOffsetCommandState.isActive {
            edgeOffsetCommandState.deactivate()
            reportToolStatus("Offset Edge complete.")
            return true
        }
        if slotProfileCommandState.isActive {
            slotProfileCommandState.deactivate()
            reportToolStatus("Slot complete.")
            return true
        }
        return false
    }

    private var allowsObjectAffordances: Bool {
        selectedTool == .select
            && selectionScope == .object
            && selectedPresentationHasExactCADAffordanceContext
    }

    private static func makeExactPresentationCADSceneNodeIDs(
        snapshot: ProjectViewSnapshot
    ) -> Set<SceneNodeID> {
        let resolver = MeshSourcePresentationCADAffordanceResolver()
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
                      cadInteraction: snapshot.cadInteraction
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
        guard selectedTool == .select,
              selectionScope == .object else {
            return nil
        }
        return handlePresentationOccurrencePick
    }

    private var presentationOccurrenceHoverHandler: ((SceneOccurrenceID?) -> Void)? {
        guard selectedTool == .select,
              selectionScope == .object else {
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
            isPreviewExpanded = true
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
        case .surface:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        default:
            nil
        }
    }

    private var canvasPlacementPreviewKind: ViewportCanvasPlacementPreviewKind? {
        switch selectedTool {
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
        case .surface:
            .circle(radiusMeters: activeSketchLengthInputMeters)
        case .select, .sweep, .mesh, .measure, .section:
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
        guard selectedTool == .polygon else {
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
        case .sketch, .polygon, .arc, .spline, .solid, .surface:
            true
        case .select, .sweep, .mesh, .measure, .section:
            false
        }
    }

    private var showsConstructionPlaneHover: Bool {
        switch selectedTool {
        case .sketch, .polygon, .arc, .spline, .solid, .surface, .section:
            true
        case .select, .sweep, .mesh, .measure:
            false
        }
    }

    private var workspaceTopBar: some View {
        workspaceTopBarContent(
            presentation: WorkspaceTopBarPresentation(selectedTargetCount: selectedTargetCount)
        )
    }

    @ViewBuilder
    private func workspaceTopBarContent(
        presentation: WorkspaceTopBarPresentation
    ) -> some View {
        // Canvas overlay chrome only carries viewport-local state (selection
        // count and scale). Document/window-level actions (logs, validation,
        // inspector) live in the Navigation toolbar, so the container is only
        // rendered when there is viewport-local content to show.
        let scaleFitPromptState = workspaceScaleFitPromptState
        if presentation.selectionTitle != nil || scaleFitPromptState != nil {
            HStack(spacing: WorkspaceChromeControlMetrics.itemSpacing) {
                if let selectionTitle = presentation.selectionTitle {
                    workspaceStatusChip(
                        selectionTitle,
                        systemImage: "scope",
                        tint: .secondary
                    )
                }

                if let scaleFitPromptState {
                    workspaceScaleFitPromptButton(scaleFitPromptState)
                }
            }
            .workspaceCanvasTopChromeContainer()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("WorkspaceTopBar")
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                newProject()
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New Document")

            Button {
                isPreviewExpanded.toggle()
            } label: {
                Image(systemName: isPreviewExpanded ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
            }
            .help(isPreviewExpanded ? "Hide Logs" : "Show Logs")
            .accessibilityIdentifier("WorkspaceCommand.logs")

            Button {
                submitSource(.validateDocument)
            } label: {
                Image(systemName: "checkmark.seal")
            }
            .help("Validate Document")
            .accessibilityIdentifier("WorkspaceCommand.validate")

            Button {
                isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
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

    private var floatingToolPalette: some View {
        WorkspaceToolPalette(
            selectedTool: selectedTool,
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
        ScrollView(.vertical) {
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
                    workspaceValueRow("Grid", snapshot.workspaceState.viewportGridSettings.visualSpacingMode.title)
                    workspaceValueRow("Step", scaleSummary.minorStepTitle)
                    workspaceValueRow("Major", scaleSummary.majorStepTitle)
                    workspaceValueRow("Visible", scaleSummary.visibleSpanTitle)
                }

                workspaceRailSection("Views") {
                    Button {
                        createSavedViewFromCurrentViewport()
                    } label: {
                        Label("Save Current", systemImage: "plus.viewfinder")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
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
                    if let activeConstructionPlane = activeConstructionPlane {
                        workspaceValueRow("Active", activeConstructionPlane.name)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Active Construction Plane")
                            .accessibilityValue(activeConstructionPlane.name)
                            .accessibilityIdentifier("WorkspacePlane.activeName")
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

                if commandCatalog.hasDomainCommands {
                    workspaceRailSection("Domain") {
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

                workspaceRailSection("Scene") {
                    workspaceValueRow("Bodies", "\(snapshot.evaluationSnapshot.bodyCount)")
                    workspaceValueRow("Nodes", "\(snapshot.document.document.productMetadata.sceneNodes.count)")
                    workspaceValueRow("Issues", diagnosticSummary)
                }
            }
            .padding(WorkspaceUtilityRailLayout.contentPadding)
        }
        .scrollIndicators(.hidden)
        .frame(width: WorkspaceUtilityRailLayout.expandedWidth, alignment: .topLeading)
        .frame(maxHeight: WorkspaceUtilityRailLayout.maximumExpandedHeight, alignment: .topLeading)
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
                || activeConstructionPlane != nil
                || viewAlignedConstructionPlaneRequest != nil,
            surfaceAnalysisTitle: surfaceAnalysisOverlaySummary,
            isSurfaceAnalysisActive: surfaceAnalysisOverlaySummary != "Off",
            savedViewCount: savedViews.count,
            diagnosticTitle: diagnosticSummary,
            hasDiagnostics: !diagnostics.isEmpty
        ) {
            setUtilityRailExpanded(true)
        }
    }

    private func setUtilityRailExpanded(_ isExpanded: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            isUtilityRailExpanded = isExpanded
        }
    }

    private var isViewportContextPanelVisible: Bool {
        WorkspaceViewportContextPanelVisibility.isVisible(
            selectedTool: selectedTool,
            selectedTargetCount: selectedTargetCount,
            selectedReferenceCount: snapshot.selection.selectedReferences.count,
            isDimensionCommandActive: dimensionCommandState.isActive,
            hasViewAlignedConstructionPlaneRequest: viewAlignedConstructionPlaneRequest != nil
        )
    }

    private var viewportContextPanelSelectionPresentation: WorkspaceViewportContextPanelVisibility.SelectionPresentation {
        WorkspaceViewportContextPanelVisibility.selectionPresentation(
            selectedSceneNodeCount: selectedSceneNodes.count,
            selectedTargetCount: selectedTargetCount,
            selectedReferenceCount: snapshot.selection.selectedReferences.count
        )
    }

    private var viewportBottomChromeReservedHeight: CGFloat {
        isViewportContextPanelVisible ? viewportContextPanelHeight : 0.0
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
            if selectedTool == .sweep {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewportContextPanel")
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
        let primaryNode = nodes.last
        workspaceValuePill("Targets", "\(selectedTargetCount)")
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
        if nodes.isEmpty == false {
            workspaceValuePill("Visible", "\(nodes.filter(\.isVisible).count)")
            workspaceValuePill("Locked", "\(nodes.filter(\.isLocked).count)")
        }

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
            systemImage: primaryNode?.isVisible == false ? "eye.slash" : "eye",
            help: primaryNode?.isVisible == false ? "Show Selection" : "Hide Selection",
            accessibilityIdentifier: "WorkspaceSelection.visible"
        ) {
            let nodeIDs = nodes.map(\.id)
            submitSource(name: "setSelectionVisibility") { current in
                try nodeIDs.map { id in
                    guard let node = current.document.document.productMetadata.sceneNodes[id] else {
                        throw EditorError(
                            code: .referenceUnresolved,
                            message: "Selected scene node \(id) no longer exists."
                        )
                    }
                    return .setSceneNodeVisibility(id: id, isVisible: !node.isVisible)
                }
            }
        }

        workspaceIconButton(
            systemImage: primaryNode?.isLocked == true ? "lock" : "lock.open",
            help: primaryNode?.isLocked == true ? "Unlock Selection" : "Lock Selection",
            accessibilityIdentifier: "WorkspaceSelection.locked"
        ) {
            let nodeIDs = nodes.map(\.id)
            submitSource(name: "setSelectionLock") { current in
                try nodeIDs.map { id in
                    guard let node = current.document.document.productMetadata.sceneNodes[id] else {
                        throw EditorError(
                            code: .referenceUnresolved,
                            message: "Selected scene node \(id) no longer exists."
                        )
                    }
                    return .setSceneNodeLock(id: id, isLocked: !node.isLocked)
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
        let isSelected = entry.selectionTarget().map { snapshot.selection.containsTarget($0) } ?? false
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
                .accessibilityLabel("Align View To \(entry.name)")
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
                .lineLimit(1)
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
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(savedViewBuilder.projectionTitle(for: savedView)) · \(savedViewBuilder.scaleTitle(for: savedView))")
                        .font(.caption2)
                        .lineLimit(1)
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.68))
            .help("Update Saved View From Current View")
            .accessibilityLabel("Update \(savedView.name) From Current View")
            .accessibilityIdentifier("WorkspaceSavedView.update.\(identifierSuffix)")

            Button {
                removeSavedView(savedView)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
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

    private func activateTool(_ tool: ModelingTool) {
        if tool != .select {
            setHoveredSceneNode(nil)
            regionOffsetCommandState.deactivate()
            edgeOffsetCommandState.deactivate()
            slotProfileCommandState.deactivate()
            viewAlignedConstructionPlaneRequest = nil
        }
        let result = setActiveTool(tool)
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

        if selectedTool == .select {
            applyViewportSelection(hit: target.hit, intent: target.selectionIntent)
            return
        }

        let resolvesObjectTargets = isObjectTargetingEnabled || target.modifierFlags.containsControl
        let effectiveHit = resolvesObjectTargets ? target.hit : nil
        let targetSceneNodeID: SceneNodeID?
        if let hit = effectiveHit {
            guard let sceneNodeID = selectionTargetResolver.sceneNodeID(for: hit) else {
                reportToolStatus(
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
        switch selectedTool {
        case .measure:
            measureCanvasTarget(targetSceneNodeID)
        case .mesh:
            inspectCanvasMesh(targetSceneNodeID)
        default:
            let tool = selectedTool
            let polygonState = polygonToolState
            let currentSketchInputState = sketchInputState
            let placementCellMeters = viewportProjectedGridStepMeters
            submitSource(name: "canvasClick") { current in
                let planner = WorkspaceCanvasCommandPlanner(
                    context: WorkspaceCanvasCommandPlanner.Context(
                        document: current.document.document,
                        selection: current.selection,
                        workspaceState: current.workspaceState,
                        objectRegistry: current.objectRegistry,
                        polygonState: polygonState,
                        sketchInputState: currentSketchInputState
                    )
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
    }

    private func measureCanvasTarget(_ targetSceneNodeID: SceneNodeID?) {
        let task = enqueueWorkspaceOperation {
            guard let current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            var selection = current.selection
            try selection.selectSceneNode(targetSceneNodeID, in: current.document.document)
            let selected = try await workspace.applySelection(.replace(selection))
            let result = try MeasurementService().measure(
                document: selected.document.document,
                selection: selected.selection,
                ruler: selected.workspaceState.ruler,
                objectRegistry: selected.objectRegistry,
                currentEvaluation: selected.cadInteraction,
                currentGeneration: selected.documentGeneration
            )
            reportToolStatus(result.message)
            isPreviewExpanded = true
        }
        observeWorkspaceOperation(task)
    }

    private func inspectCanvasMesh(_ targetSceneNodeID: SceneNodeID?) {
        let task = enqueueWorkspaceOperation {
            guard var current = workspace.view else {
                throw ProjectWorkspaceActionError(
                    code: .snapshotUnavailable,
                    message: "The project workspace has no published view snapshot."
                )
            }
            if let targetSceneNodeID {
                var selection = current.selection
                try selection.selectSceneNode(targetSceneNodeID, in: current.document.document)
                current = try await workspace.applySelection(.replace(selection))
            }
            let summary = try MeshSummaryService().summarize(
                document: current.document.document,
                ruler: current.workspaceState.ruler,
                objectRegistry: current.objectRegistry,
                currentEvaluation: current.cadInteraction,
                currentGeneration: current.documentGeneration
            )
            reportToolStatus(summary.message)
            isPreviewExpanded = true
        }
        observeWorkspaceOperation(task)
    }

    private func observeWorkspaceOperation<Result: Sendable>(
        _ task: Task<Result, Error>
    ) {
        Task { @MainActor in
            do {
                _ = try await task.value
            } catch {
                reportToolStatus(error.localizedDescription, severity: .warning)
                isPreviewExpanded = true
            }
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
            isSelectToolActive: selectedTool == .select,
            isPolygonToolActive: selectedTool == .polygon,
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
            _ = focusNextSketchDimensionInput(
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
                reportToolStatus(
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
                reportToolStatus(
                    "Dimension found no editable values for the selected target.",
                    severity: .warning
                )
                isPreviewExpanded = true
                return
            }
            dimensionCommandState.activate(entries: entries)
        } catch let error as EditorError {
            dimensionCommandState.deactivate()
            reportToolStatus(error.message, severity: .warning)
            isPreviewExpanded = true
        } catch {
            dimensionCommandState.deactivate()
            reportToolStatus(String(describing: error), severity: .warning)
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

    private func commitDimensionCommand() {
        guard let entry = dimensionCommandState.activeEntry,
              let value = dimensionCommandState.currentValue,
              value.isFinite else {
            reportToolStatus(
                "Dimension value must be finite.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        let command: EditorCommand
        switch entry.source {
        case .object(let kind):
            guard value > 0.0 else {
                reportToolStatus(
                    "Dimension value must be a positive length.",
                    severity: .warning
                )
                isPreviewExpanded = true
                return
            }
            command = .setObjectDimension(
                target: entry.target,
                kind: kind,
                value: .length(value, .meter)
            )
        case .sketch(let kind):
            let expression: CADExpression
            switch entry.valueKind {
            case .length:
                guard value > 0.0 else {
                    reportToolStatus(
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
            command = .setSketchEntityDimension(
                target: entry.target,
                kind: kind,
                value: expression
            )
        }
        submitSource(command) { result in
            if result?.diagnostics.isEmpty == false || result == nil {
                isPreviewExpanded = true
            }
        }
        dimensionCommandState.deactivate()
    }

    private func createConstructionPlaneFromSelectedTargets(alignsView: Bool) -> KeyPress.Result {
        guard selectedConstructionPlaneTargets != nil else {
            return .ignored
        }
        let viewNormal = viewportProjectionBasis.viewNormal
        submitSource(name: "createConstructionPlaneFromTargets") { current in
            guard let targets = WorkspaceConstructionPlaneTargetSelectionBuilder(
                document: current.document.document,
                selection: current.selection
            ).constructionPlaneTargets else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Construction plane creation requires a supported current selection."
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
                isPreviewExpanded = true
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
            return
        }
        selectionScope = .sketchEntity
        reportToolStatus(
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
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
            if results.last == nil {
                isPreviewExpanded = true
            } else {
                reportToolStatus(successMessage)
            }
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
        }
    }

    private func createSavedViewFromCurrentViewport() {
        let projectionBasis = viewportProjectionBasis
        let cameraFrame = viewportCameraFrame
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
            } else {
                isPreviewExpanded = true
            }
        }
    }

    private func updateSavedViewFromCurrentViewport(_ savedView: SavedView) {
        let savedViewID = savedView.id
        let projectionBasis = viewportProjectionBasis
        let cameraFrame = viewportCameraFrame
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
            } else {
                isPreviewExpanded = true
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
            return [.setRulerConfiguration(currentSavedView.displayScale.rulerConfiguration)]
        }) { published in
            guard let currentSavedView = published.document.document.productMetadata.savedViews[savedViewID] else {
                return
            }
            resetWorkspaceInteractionScaleDefaults(ruler: published.workspaceState.ruler)
            let cameraFrameRequest = savedViewBuilder.cameraFrameRequest(for: currentSavedView)
            viewportProjectionRequest = ViewportProjectionRequest(basis: cameraFrameRequest.basis)
            viewportCameraFrameRequest = cameraFrameRequest
            reportToolStatus("Saved view \(currentSavedView.name) applied.")
        }
    }

    private func removeSavedView(_ savedView: SavedView) {
        submitSource(.removeSavedView(id: savedView.id)) { result in
            if result != nil {
                reportToolStatus("Saved view \(savedView.name) removed.")
            } else {
                isPreviewExpanded = true
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
            isPreviewExpanded = true
            return
        }

        submitSource(.renameConstructionPlane(id: id, name: trimmedName)) { result in
            if result == nil {
                isPreviewExpanded = true
            } else {
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
            isPreviewExpanded = true
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
                isPreviewExpanded = true
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
            reportToolStatus(
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
            reportToolStatus(message, severity: .warning)
            isPreviewExpanded = true
        }
    }

    private func activateSlotProfileCommand() {
        guard selectedSlotSourceCurveTarget != nil else {
            if selectionScope != .sketchEntity {
                selectionScope = .sketchEntity
            }
            reportToolStatus(
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

    private func handleViewportBodyMoveDrag(_ target: ViewportBodyMoveDragTarget) {
        guard selectedTool == .select,
              selectionScope == .object else {
            return
        }
        submitSource(
            .moveBody(
                target: target.target,
                deltaX: .length(target.deltaX, .meter),
                deltaY: .length(target.deltaY, .meter)
            )
        )
    }

    private func handleViewportVertexDrag(_ target: ViewportVertexDragTarget) {
        guard selectedTool == .select,
              selectionScope == .vertex else {
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
        guard selectedTool == .select,
              selectionScope == .vertex else {
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
        guard selectedTool == .select,
              selectionScope == .vertex else {
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
        guard selectedTool == .select,
              selectionScope == .vertex else {
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
        guard selectedTool == .select,
              selectionScope == .vertex else {
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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

    private func handleViewportConstructionPlaneHandleDrag(
        _ target: ViewportConstructionPlaneDragTarget
    ) {
        guard selectedTool == .select else {
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
            isPreviewExpanded = true
        } catch {
            reportToolStatus(
                "Construction plane viewport edit failed.",
                severity: .warning
            )
            isPreviewExpanded = true
        }
    }

    private func handleViewportFaceDrag(_ target: ViewportFaceDragTarget) {
        guard selectedTool == .select,
              selectionScope == .face else {
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
        guard selectedTool == .select,
              selectionScope == .edge else {
            return
        }
        submitSource(
            .chamferBodyEdges(
                targets: [target.target],
                distance: .length(target.distance, .meter)
            )
        )
    }

    private func handleViewportEdgeFilletDrag(_ target: ViewportEdgeFilletDragTarget) {
        guard selectedTool == .select,
              selectionScope == .edge else {
            return
        }
        submitSource(
            .filletBodyEdges(
                targets: [target.target],
                radius: .length(target.radius, .meter),
                segmentCount: 8
            )
        )
    }

    private func handleViewportRegionOffsetDrag(_ target: ViewportRegionOffsetDragTarget) {
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectionScope == .sketchEntity,
              slotProfileCommandState.isActive else {
            return
        }
        slotProfileWidthMeters = max(target.width, 1.0e-9)
        createSlotFromOffsetCurve(target.target, width: slotProfileWidthMeters)
    }

    private func handleViewportSketchVertexOffsetDrag(_ target: ViewportSketchVertexOffsetDragTarget) {
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              let state = patternArrayInspectorState(for: selectedSceneNodes),
              state.sourceID == target.sourceID else {
            return
        }
        patternArrayEditingService(sourceID: target.sourceID).setOutputMode(target.outputMode)
    }

    private func handleViewportPatternArrayCurvePathPointDrag(
        _ target: ViewportPatternArrayCurvePathPointDragTarget
    ) {
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
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
        guard selectedTool == .select,
              selectionScope == .sketchEntity else {
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
        guard selectedTool == .select,
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
                )
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
            isPreviewExpanded = true
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
        } catch {
            reportToolStatus(
                "Canvas input could not be projected onto the active construction plane.",
                severity: .warning
            )
        }
        isPreviewExpanded = true
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
            isPreviewExpanded = true
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
        guard let sourceID = patternArrayCurvePathPickState.sourceID else {
            return false
        }
        let outcome = PatternArrayCurvePathPickService(
            document: snapshot.document.document,
            submit: { submitSource($0) },
            submitPath: { submitPatternArrayCurvePath(sourceID: sourceID, path: $0) },
            report: { reportToolStatus($0, severity: $1) },
            sourceID: sourceID
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
                isPreviewExpanded = true
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
    private func componentBrowserRow(_ id: SceneNodeID, depth: Int) -> some View {
        if let node = snapshot.document.document.productMetadata.sceneNodes[id] {
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
        if let definition = snapshot.document.document.productMetadata.componentDefinitions[id] {
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
        if let instance = snapshot.document.document.productMetadata.componentInstances[id] {
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
        case .authoredMesh:
            return "square.3.layers.3d"
        }
    }

    private func toggleSceneNodeVisibility(_ id: SceneNodeID) {
        submitSource(name: "toggleSceneNodeVisibility") { current in
            guard let node = current.document.document.productMetadata.sceneNodes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id) no longer exists."
                )
            }
            return [.setSceneNodeVisibility(id: id, isVisible: !node.isVisible)]
        }
    }

    private func toggleSceneNodeLock(_ id: SceneNodeID) {
        submitSource(name: "toggleSceneNodeLock") { current in
            guard let node = current.document.document.productMetadata.sceneNodes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id) no longer exists."
                )
            }
            return [.setSceneNodeLock(id: id, isLocked: !node.isLocked)]
        }
    }

    private func toggleComponentInstanceVisibility(_ id: ComponentInstanceID) {
        submitSource(name: "toggleComponentInstanceVisibility") { current in
            guard let instance = current.document.document.productMetadata.componentInstances[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Component instance \(id) no longer exists."
                )
            }
            return [
                .setComponentInstanceVisibility(id: id, isVisible: !instance.isVisible),
            ]
        }
    }

    private func toggleComponentInstanceLock(_ id: ComponentInstanceID) {
        submitSource(name: "toggleComponentInstanceLock") { current in
            guard let instance = current.document.document.productMetadata.componentInstances[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Component instance \(id) no longer exists."
                )
            }
            return [.setComponentInstanceLock(id: id, isLocked: !instance.isLocked)]
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
            workspaceState: snapshot.workspaceState
        )
    }

    private var sectionAnalysisStateBuilder: WorkspaceSectionAnalysisStateBuilder {
        WorkspaceSectionAnalysisStateBuilder(
            document: snapshot.document.document,
            currentEvaluation: snapshot.cadInteraction,
            documentGeneration: snapshot.documentGeneration,
            displayUnit: snapshot.workspaceState.displayUnit,
            objectRegistry: objectRegistry
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
            objectRegistry: objectRegistry
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
        let recommendationStates = workspaceDocumentRecommendationStates(
            bounds: presentationMeasurementBounds,
            ruler: snapshot.workspaceState.ruler,
            displayUnit: snapshot.workspaceState.displayUnit
        )
        return WorkspaceDocumentInspectorState(
            documentName: documentTitle,
            documentID: shortID(snapshot.document.document.id),
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
        let overviewState = workspaceObjectOverviewInspectorState(for: nodes)
        WorkspaceInspectorTextSectionView(section: overviewState.selectionSection)
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

        WorkspaceInspectorTextSectionView(section: overviewState.referenceSection)
        WorkspaceInspectorTextSectionView(section: overviewState.hierarchySection)
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
            displayUnit: snapshot.workspaceState.displayUnit,
            positionSliderMetersRange: transformPositionSliderMetersRange,
            materialOptions: sortedMaterialOptions,
            onSetVisibility: { id, isVisible in
                submitSource(.setSceneNodeVisibility(id: id, isVisible: isVisible))
            },
            onSetLock: { id, isLocked in
                submitSource(.setSceneNodeLock(id: id, isLocked: isLocked))
            },
            onSetTransformComponent: { component, value in
                setTransformComponent(component, to: value, for: nodes)
            },
            onSetMaterial: { id, materialID in
                submitSource(.setSceneNodeMaterial(id: id, materialID: materialID))
            },
            onResetTransform: {
                submitSource(
                    nodes.map { node in
                        .setSceneNodeTransform(id: node.id, localTransform: .identity)
                    },
                    name: "resetObjectInspectorTransform"
                )
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
    private func objectShapeSection(_ nodes: [SceneNode]) -> some View {
        let shapes = WorkspaceObjectShapeInspectorStateBuilder(
            document: snapshot.document.document,
            currentEvaluation: snapshot.cadInteraction,
            documentGeneration: snapshot.documentGeneration,
            objectRegistry: objectRegistry,
            ruler: snapshot.workspaceState.ruler
        )
        .shapes(for: nodes)
        WorkspaceObjectShapeInspectorView(
            shapes: shapes,
            displayUnit: snapshot.workspaceState.displayUnit,
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
        let sceneNodeIDs = shapes.map(\.id)
        submitSource(name: "setObjectCenter") { current in
            let currentShapes = currentObjectShapes(sceneNodeIDs: sceneNodeIDs, in: current)
            guard currentShapes.count == sceneNodeIDs.count else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "One or more edited object shapes no longer exist."
                )
            }
            var commands: [EditorCommand] = []
            for shape in currentShapes {
                guard let node = current.document.document.productMetadata.sceneNodes[shape.id] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Object scene node \(shape.id) no longer exists."
                    )
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
                let matrix = try Matrix4x4(values: values)
                commands.append(
                    .setSceneNodeTransform(
                        id: node.id,
                        localTransform: Transform3D(matrix: matrix)
                    )
                )
            }
            return commands
        }
    }

    private func setObjectSize(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shapes: [InspectorObjectShape]
    ) {
        let sizeMeters = max(meters, 1.0e-9)
        let sceneNodeIDs = shapes.map(\.id)
        submitSource(name: "setObjectSize") { current in
            let currentShapes = currentObjectShapes(sceneNodeIDs: sceneNodeIDs, in: current)
            guard currentShapes.count == sceneNodeIDs.count else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "One or more resized object shapes no longer exist."
                )
            }
            var commands: [EditorCommand] = []
            for shape in currentShapes {
                switch shape.typeID {
                case .some(.cube):
                    commands.append(
                        contentsOf: try cubeSizeCommands(
                            axis,
                            to: sizeMeters,
                            for: shape,
                            document: current.document.document
                        )
                    )
                case .some(.cylinder):
                    commands.append(
                        contentsOf: try cylinderSizeCommands(
                            axis,
                            to: sizeMeters,
                            for: shape,
                            document: current.document.document
                        )
                    )
                default:
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Object \(shape.id) no longer supports direct size editing."
                    )
                }
            }
            return commands
        }
    }

    private func currentObjectShapes(
        sceneNodeIDs: [SceneNodeID],
        in current: ProjectViewSnapshot
    ) -> [InspectorObjectShape] {
        let document = current.document.document
        let nodes = sceneNodeIDs.compactMap { document.productMetadata.sceneNodes[$0] }
        return WorkspaceObjectShapeInspectorStateBuilder(
            document: document,
            currentEvaluation: current.cadInteraction,
            documentGeneration: current.documentGeneration,
            objectRegistry: current.objectRegistry,
            ruler: current.workspaceState.ruler
        )
        .shapes(for: nodes) ?? []
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
            isPreviewExpanded = true
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
            isPreviewExpanded = true
            return
        }
        submitSource(
            .offsetCurve(
                target: target,
                distance: .length(max(meters, 1.0e-9), .meter),
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

    private func chamferSelectedEdges(
        _ targets: [SelectionTarget],
        by meters: Double
    ) {
        submitSource(
            .chamferBodyEdges(
                targets: targets,
                distance: .length(meters, .meter)
            )
        )
    }

    private func filletSelectedEdges(
        _ targets: [SelectionTarget],
        radius meters: Double
    ) {
        submitSource(
            .filletBodyEdges(
                targets: targets,
                radius: .length(meters, .meter),
                segmentCount: 8
            )
        )
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
        )
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

    private func trimBridgeCurveSources(_ bridgeCurve: InspectorBridgeCurve) {
        submitSource(
            .setBridgeCurveParameters(
                sourceID: bridgeCurve.sourceID,
                firstEndpoint: nil,
                secondEndpoint: nil,
                continuity: nil,
                trimsSourceCurves: true
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
        _ target: SelectionTarget
    ) {
        submitSource(
            .extendSketchCurve(
                target: target,
                distance: .length(max(sketchExtendDistanceMeters, 1.0e-9), .meter),
                shape: sketchExtendShape
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
                options: CutCurveOptions()
            )
        )
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
                    continuity: sketchVertexAlignmentContinuity
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
        )
    }

    private func createSlotFromOffsetCurve(
        _ target: SelectionTarget,
        width meters: Double
    ) {
        submitSource(
            .offsetCurve(
                target: target,
                distance: .length(max(meters, 1.0e-9), .meter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: nil
            )
        ) { result in
            if result?.didMutate == true {
                slotProfileCommandState.deactivate()
            }
        }
    }

    private func cubeSizeCommands(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shape: InspectorObjectShape,
        document: DesignDocument
    ) throws -> [EditorCommand] {
        var commands: [EditorCommand] = [
            .setCubeDimensions(
                featureID: shape.featureID,
                sizeX: .length(axis == .x ? meters : shape.size.x, .meter),
                sizeY: .length(axis == .y ? meters : shape.size.y, .meter),
                sizeZ: .length(axis == .z ? meters : shape.size.z, .meter)
            )
        ]
        if axis == .y,
           let centerCommand = try preserveObjectCenterCommandAfterYResize(
               to: meters,
               for: shape,
               document: document
           ) {
            commands.append(centerCommand)
        }
        return commands
    }

    private func cylinderSizeCommands(
        _ axis: InspectorObjectAxis,
        to meters: Double,
        for shape: InspectorObjectShape,
        document: DesignDocument
    ) throws -> [EditorCommand] {
        guard shape.cylinder != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Object \(shape.id) is no longer a cylinder."
            )
        }
        let radius = axis == .y ? max(shape.size.x, shape.size.z) / 2.0 : meters / 2.0
        var commands: [EditorCommand] = [
            .setCylinderDimensions(
                featureID: shape.featureID,
                radius: .length(max(radius, 1.0e-9), .meter),
                sizeY: .length(axis == .y ? meters : shape.size.y, .meter)
            )
        ]
        if axis == .y,
           let centerCommand = try preserveObjectCenterCommandAfterYResize(
               to: meters,
               for: shape,
               document: document
           ) {
            commands.append(centerCommand)
        }
        return commands
    }

    private func preserveObjectCenterCommandAfterYResize(
        to sizeYMeters: Double,
        for shape: InspectorObjectShape,
        document: DesignDocument
    ) throws -> EditorCommand? {
        guard shape.size.y > 1.0e-9,
              let node = document.productMetadata.sceneNodes[shape.id] else {
            return nil
        }
        let sourceCenterRatio = shape.sourceCenter.y / shape.size.y
        let nextSourceCenterY = sourceCenterRatio * sizeYMeters
        var values = WorkspaceTransformMatrix.normalizedValues(node.localTransform.matrix.values)
        values[InspectorTransformComponent.translationY.matrixIndex] = shape.center.y - nextSourceCenterY
        let matrix = try Matrix4x4(values: values)
        return .setSceneNodeTransform(
            id: node.id,
            localTransform: Transform3D(matrix: matrix)
        )
    }

    private var transformPositionSliderMetersRange: ClosedRange<Double> {
        let span = snapshot.workspaceState.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return -span ... span
    }

    private var sizeSliderMetersRange: ClosedRange<Double> {
        let visibleSpan = snapshot.workspaceState.ruler.normalizedForWorkspaceScale().visibleSpanMeters
        return 0.0 ... visibleSpan
    }

    private func setTransformComponent(
        _ component: InspectorTransformComponent,
        to value: Double,
        for nodes: [SceneNode]
    ) {
        let sceneNodeIDs = nodes.map(\.id)
        let matrixIndex = component.matrixIndex
        submitSource(name: "setTransformComponent") { current in
            var commands: [EditorCommand] = []
            for sceneNodeID in sceneNodeIDs {
                guard let node = current.document.document.productMetadata.sceneNodes[sceneNodeID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Scene node \(sceneNodeID) no longer exists."
                    )
                }
                var values = WorkspaceTransformMatrix.normalizedValues(node.localTransform.matrix.values)
                values[matrixIndex] = value
                let matrix = try Matrix4x4(values: values)
                commands.append(
                    .setSceneNodeTransform(
                        id: node.id,
                        localTransform: Transform3D(matrix: matrix)
                    )
                )
            }
            return commands
        }
    }

    private func extrudeFeatureID(for node: SceneNode) -> FeatureID? {
        guard let featureID = node.reference?.featureID,
              let feature = snapshot.document.document.cadDocument.designGraph.nodes[featureID],
              case .extrude = feature.operation else {
            return nil
        }
        return featureID
    }

    private func resolvedExtrudeDistance(featureID: FeatureID) -> Double? {
        guard let feature = snapshot.document.document.cadDocument.designGraph.nodes[featureID],
              case .extrude(let extrude) = feature.operation else {
            return nil
        }
        do {
            let quantity = try snapshot.document.document.cadDocument.parameters.resolvedValue(for: extrude.distance)
            guard quantity.kind == .length else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
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
        guard value.valueKind == property.valueKind else {
            return
        }
        submitSource(
            shapes.map { shape in
                .setSceneNodeObjectProperty(
                    id: shape.id,
                    propertyID: property.id,
                    value: value
                )
            },
            name: "setObjectProperty"
        )
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
        return angle.isFinite ? degrees(fromRadians: angle) : nil
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

    private func sweepSectionSummary(_ section: SweepSectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(shortID(profile.featureID))"
        case .curve(let curve):
            return "Curve \(shortID(curve.featureID))"
        }
    }

    private var diagnosticSummary: String {
        let diagnostics = diagnostics
        guard !diagnostics.isEmpty else {
            return "None"
        }
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(errors) errors, \(warnings) warnings, \(info) info"
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

    private func selectSmallerWorkspaceScalePreset() {
        guard let preset = workspaceScaleSummary.smallerPreset else {
            return
        }
        applyWorkspaceScalePreset(preset)
    }

    private func selectLargerWorkspaceScalePreset() {
        guard let preset = workspaceScaleSummary.largerPreset else {
            return
        }
        applyWorkspaceScalePreset(preset)
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
                isPreviewExpanded = true
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

    private func componentDefinitionName(for id: ComponentDefinitionID) -> String {
        snapshot.document.document.productMetadata.componentDefinitions[id]?.name ?? "Missing Definition"
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
                preferredUnit: snapshot.workspaceState.displayUnit
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
                preferredUnit: snapshot.workspaceState.displayUnit
            ).unit
        case .angle:
            return snapshot.workspaceState.displayUnit
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

}
