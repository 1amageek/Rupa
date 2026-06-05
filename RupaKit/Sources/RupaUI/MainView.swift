import Foundation
import MacComponent
import RupaCore
import RupaPreview
import RupaRendering
import SwiftCAD
import SwiftUI

@MainActor
public struct MainView: View {
    @State private var session: EditorSession
    @State private var isPreviewExpanded: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var isInspectorPresented: Bool
    @State private var sidebarSearchText: String
    @State private var agentSessionID: UUID?

    private let objectRegistry: ObjectTypeRegistry
    private let agentHost: AgentHost?
    private let documentURL: URL?

    public init(
        session: EditorSession = EditorSession(),
        isPreviewExpanded: Bool = false,
        columnVisibility: NavigationSplitViewVisibility = .all,
        isInspectorPresented: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        agentHost: AgentHost? = nil,
        documentURL: URL? = nil
    ) {
        self._session = State(initialValue: session)
        self._isPreviewExpanded = State(initialValue: isPreviewExpanded)
        self._columnVisibility = State(initialValue: columnVisibility)
        self._isInspectorPresented = State(initialValue: isInspectorPresented)
        self._sidebarSearchText = State(initialValue: "")
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
                _ = session.selectSceneNodes(orderedIDs)
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
            ZStack(alignment: .bottom) {
                Viewport(
                    document: session.document,
                    objectRegistry: objectRegistry,
                    evaluationStatus: session.evaluationStatus,
                    renderInvalidation: session.renderInvalidation,
                    selection: session.selection,
                    showsCanvasDragPlaceholder: showsRectangleDragPlaceholder,
                    showsConstructionPlaneHover: showsConstructionPlaneHover,
                    allowsSelectionRectangle: session.selectedTool == .select,
                    onPick: handleViewportPick,
                    onCanvasDrag: handleViewportDrag,
                    onSelectionDrag: handleViewportSelectionDrag,
                    onHover: viewportHoverHandler
                )
                .zIndex(0)

                floatingToolPalette
                    .padding(.bottom, 14)
                    .zIndex(1)
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

    private var showsRectangleDragPlaceholder: Bool {
        switch session.selectedTool {
        case .sketch, .solid:
            true
        default:
            false
        }
    }

    private var showsConstructionPlaneHover: Bool {
        switch session.selectedTool {
        case .sketch, .solid, .surface, .section:
            true
        case .select, .mesh, .measure:
            false
        }
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
        HStack(spacing: 6) {
            ForEach(ModelingTool.allCases) { tool in
                toolPaletteButton(tool)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: -8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CanvasToolPalette")
    }

    private func toolPaletteButton(_ tool: ModelingTool) -> some View {
        let isSelected = session.selectedTool == tool

        return Button {
            activateTool(tool)
        } label: {
            toolPaletteIcon(tool, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(toolHelp(for: tool))
        .accessibilityLabel(tool.title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier(canvasToolIdentifier(for: tool))
    }

    private func toolPaletteIcon(_ tool: ModelingTool, isSelected: Bool) -> some View {
        Image(systemName: tool.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.001))
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.56) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            }
            .contentShape(Circle())
    }

    private func activateTool(_ tool: ModelingTool) {
        if tool != .select {
            setHoveredSceneNode(nil)
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
        case .solid:
            "Create Box"
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
        if session.selectedTool == .select {
            applyViewportSelection(hit: target.hit, intent: target.selectionIntent)
            return
        }

        let targetSceneNodeID: SceneNodeID?
        if let hit = target.hit {
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

        let result = session.activateSelectedToolFromCanvas(
            targetSceneNodeID: targetSceneNodeID,
            modelPoint: target.modelPoint,
            sketchPlane: target.sketchPlane
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func handleViewportSelectionDrag(_ target: ViewportSelectionDragTarget) {
        let sceneNodeIDs = uniqueSceneNodeIDs(for: target.hits)
        applyViewportSelection(ids: sceneNodeIDs, intent: target.selectionIntent)
    }

    private func handleViewportDrag(_ drag: ViewportModelDrag) {
        let result = session.activateSelectedToolFromCanvasDrag(
            startModelPoint: drag.start,
            endModelPoint: drag.end,
            sketchPlane: drag.sketchPlane
        )
        if result.revealsDiagnostics {
            isPreviewExpanded = true
        }
    }

    private func handleViewportHover(_ hit: ViewportHit?) {
        guard let hit else {
            setHoveredSceneNode(nil)
            return
        }

        guard let sceneNodeID = sceneNodeID(for: hit) else {
            setHoveredSceneNode(nil)
            return
        }
        setHoveredSceneNode(sceneNodeID)
    }

    private func applyViewportSelection(
        hit: ViewportHit?,
        intent: ViewportSelectionIntent
    ) {
        guard let hit else {
            applyViewportSelection(ids: [], intent: intent)
            return
        }

        guard let sceneNodeID = sceneNodeID(for: hit) else {
            session.reportToolStatus(
                "Viewport selection could not resolve a scene node.",
                severity: .warning
            )
            isPreviewExpanded = true
            return
        }

        applyViewportSelection(ids: [sceneNodeID], intent: intent)
    }

    private func applyViewportSelection(
        ids: [SceneNodeID],
        intent: ViewportSelectionIntent
    ) {
        switch intent {
        case .replace:
            guard !ids.isEmpty else {
                session.clearSelection()
                return
            }
            _ = session.selectSceneNodes(ids)
        case .toggle:
            guard !ids.isEmpty else {
                return
            }
            var nextIDs = session.selection.selectedSceneNodeIDs
            for id in ids {
                if let index = nextIDs.firstIndex(of: id) {
                    nextIDs.remove(at: index)
                } else {
                    nextIDs.append(id)
                }
            }
            _ = session.selectSceneNodes(nextIDs)
        }
    }

    private func uniqueSceneNodeIDs(for hits: [ViewportHit]) -> [SceneNodeID] {
        var ids: [SceneNodeID] = []
        var seenIDs: Set<SceneNodeID> = []
        for hit in hits {
            guard let id = sceneNodeID(for: hit),
                  seenIDs.insert(id).inserted else {
                continue
            }
            ids.append(id)
        }
        return ids
    }

    private func sceneNodeID(for hit: ViewportHit) -> SceneNodeID? {
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

    private struct SceneBrowserRow: Identifiable {
        var id: SceneNodeID
        var depth: Int
    }

    private struct SidebarAssetRow: Identifiable {
        var id: String
        var title: String
        var subtitle: String
        var systemImage: String
    }

    private enum InspectorBoolChoice: String, CaseIterable, Identifiable {
        case mixed = "Mixed"
        case on = "On"
        case off = "Off"

        var id: String {
            rawValue
        }
    }

    private enum InspectorTransformComponent {
        case translationX
        case translationY
        case translationZ
        case scaleX
        case scaleY
        case scaleZ

        var matrixIndex: Int {
            switch self {
            case .translationX:
                12
            case .translationY:
                13
            case .translationZ:
                14
            case .scaleX:
                0
            case .scaleY:
                5
            case .scaleZ:
                10
            }
        }
    }

    private enum InspectorMaterialChoice: Hashable, Identifiable {
        case mixed
        case none
        case material(MaterialID)

        var id: String {
            switch self {
            case .mixed:
                "mixed"
            case .none:
                "none"
            case .material(let id):
                id.description
            }
        }
    }

    private struct InspectorVector3D: Equatable {
        var x: Double
        var y: Double
        var z: Double
    }

    private struct InspectorObjectShape: Identifiable, Equatable {
        var id: SceneNodeID
        var featureID: FeatureID
        var typeID: ObjectTypeID?
        var definition: ObjectTypeDefinition?
        var properties: ObjectPropertySet
        var sourceCenter: InspectorVector3D
        var center: InspectorVector3D
        var size: InspectorVector3D
        var cylinder: InspectorCylinderShape?
    }

    private struct InspectorCylinderShape: Equatable {
        var topRadius: Double
        var bottomRadius: Double
        var sideSegments: Int
        var verticalSegments: Int
        var angleDegrees: Double
        var hasCaps: Bool
        var hollow: Double
        var cornerRadius: Double
        var cornerSideSegments: Int
    }

    private enum InspectorObjectAxis: Equatable {
        case x
        case y
        case z
    }

    private var selectedSceneNodes: [SceneNode] {
        session.selection.selectedSceneNodeIDs.compactMap { id in
            session.document.productMetadata.sceneNodes[id]
        }
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
                if selectedSceneNodes.isEmpty {
                    canvasInspectorSections
                } else {
                    objectInspectorSections(selectedSceneNodes)
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
                inspectorRow("Geometry", geometryTitle(for: node))
                inspectorRow("Scene Node ID", shortID(node.id))
                inspectorRow("Primary", "Yes")
            } else {
                inspectorRow("Objects", "\(nodes.count)")
                inspectorRow("Primary", nodes.last?.name ?? "None")
                inspectorRow("Object Types", valueSummary(nodes.map { objectTitle(for: $0) }))
                inspectorRow("Geometry", valueSummary(nodes.map { geometryTitle(for: $0) }))
                inspectorRow("Visible Objects", "\(nodes.filter { $0.isVisible }.count)")
                inspectorRow("Locked Objects", "\(nodes.filter { $0.isLocked }.count)")
            }
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
    private func objectShapeSection(_ nodes: [SceneNode]) -> some View {
        let shapes = nodes.map { objectShape(for: $0) }
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

    private func objectShape(for node: SceneNode) -> InspectorObjectShape? {
        guard let object = node.object,
              object.typeID != nil else {
            return nil
        }
        guard let featureID = node.reference?.featureID else {
            return nil
        }
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: session.document)
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
        if let sourceProfileFeatureID = object.sourceProfileFeatureID {
            inspectorRow("Source Profile", shortID(sourceProfileFeatureID))
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

    private func formattedDegrees(_ degrees: Double) -> String {
        "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
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
