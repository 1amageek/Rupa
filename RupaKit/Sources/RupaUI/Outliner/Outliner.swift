import RupaCore
import RupaProject
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct Outliner: View {
    let metadata: ProductMetadata
    let selectedIDs: Set<SceneNodeID>
    let generation: DocumentGeneration
    let canFrameSelection: Bool
    let pendingStateIDs: Set<SceneNodeID>
    @Binding var searchText: String
    let onIntent: (OutlinerIntent) -> Void

    @State private var filter: OutlinerVisibilityFilter = .all
    @State private var expandedIDs: Set<SceneNodeID> = []
    @State private var renamingID: SceneNodeID?
    @State private var renameDraft = ""
    @State private var actionError: String?
    @State private var dragSession: OutlinerMoveDragSession?
    @State private var dropDestination: OutlinerDropDestination?
    @State private var hoveredRowID: SceneNodeID?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var focusedRenameID: SceneNodeID?

    private static let dragType = UTType(exportedAs: "team.stamp.rupa.outliner.scene-move")

    init(
        metadata: ProductMetadata,
        selectedIDs: Set<SceneNodeID>,
        generation: DocumentGeneration = DocumentGeneration(0),
        canFrameSelection: Bool = false,
        pendingStateIDs: Set<SceneNodeID> = [],
        searchText: Binding<String>,
        onIntent: @escaping (OutlinerIntent) -> Void
    ) {
        self.metadata = metadata
        self.selectedIDs = selectedIDs
        self.generation = generation
        self.canFrameSelection = canFrameSelection
        self.pendingStateIDs = pendingStateIDs
        self._searchText = searchText
        self.onIntent = onIntent
        self._expandedIDs = State(initialValue: Set(metadata.rootSceneNodeIDs))
    }

    private func makeProjection() -> OutlinerProjection {
        OutlinerProjection.make(
            metadata: metadata,
            expandedIDs: expandedIDs,
            searchText: searchText,
            filter: filter
        )
    }

    var body: some View {
        let currentProjection = makeProjection()
        VStack(spacing: 0) {
            controls(projection: currentProjection)
            List(selection: selectionBinding(projection: currentProjection)) {
                ForEach(currentProjection.rows) { row in
                    rowView(row, projection: currentProjection)
                        .tag(row.id)
                        .overlay {
                            dropFeedback(for: row)
                                .allowsHitTesting(false)
                        }
                        .onDrop(
                            of: [Self.dragType],
                            delegate: rowDropDelegate(row: row)
                        )
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("WorkspaceSidebar.outliner.tree")
            Text(dragSession == nil ? "" : "Move to Scene Root")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(dragSession == nil ? 0 : 0.35))
                .opacity(dragSession == nil ? 0 : 1)
                .accessibilityHidden(dragSession == nil)
                .onDrop(
                    of: [Self.dragType],
                    delegate: rootDropDelegate()
                )
        }
        .searchable(text: $searchText, prompt: "Search Scene")
        .onKeyPress(phases: .all) { keyPress in
            guard keyPress.phase.contains(.down) else {
                return .ignored
            }
            if isRenameKey(keyPress) {
                beginRenameForSelection(projection: currentProjection)
                return .handled
            }
            if isDeleteKey(keyPress) {
                return deleteSelection(projection: currentProjection)
            }
            return .ignored
        }
        .onDisappear {
            hoveredRowID = nil
            cancelDrag()
            onIntent(.hover(nil, isHovered: false))
        }
        .alert("Outliner Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "The action could not be completed.")
        }
        .onChange(of: actionError) { _, message in
            // Every Outliner refusal funnels through this one alert, so the
            // surface is the operation and one recorder covers every site.
            guard let message else { return }
            WorkspaceFailureLog.shared.record(
                refusal: message,
                operation: "Outliner"
            )
        }
        .onChange(of: metadata) { _, _ in
            cancelDrag()
            expandedIDs = expandedIDs.intersection(Set(metadata.sceneNodes.keys))
            if let renamingID, metadata.sceneNodes[renamingID] == nil {
                cancelRename()
            }
        }
        .onChange(of: generation) { _, _ in
            cancelDrag()
        }
    }

    private func isRenameKey(_ keyPress: KeyPress) -> Bool {
        keyPress.characters.caseInsensitiveCompare("F2") == .orderedSame
            || keyPress.characters == "\u{F705}"
    }

    private func isDeleteKey(_ keyPress: KeyPress) -> Bool {
        keyPress.key == .delete || keyPress.key == .deleteForward
    }

    /// Deletes the tree's current selection.
    ///
    /// An empty selection and an active rename leave the key alone so it still reaches the
    /// responder that owns it; a selection Core would refuse is reported rather than dropped.
    private func deleteSelection(projection: OutlinerProjection) -> KeyPress.Result {
        guard renamingID == nil else {
            return .ignored
        }
        let ids = orderedSelectedIDs(projection: projection)
        guard ids.isEmpty == false else {
            return .ignored
        }
        let lifecycle = lifecycle(ids: ids, projection: projection)
        guard lifecycle.canDelete else {
            actionError = "Roots, locked scene nodes, and generated pattern outputs cannot be deleted."
            return .handled
        }
        onIntent(.delete(ids: lifecycle.deletableIDs))
        return .handled
    }

    private func controls(projection: OutlinerProjection) -> some View {
        HStack(spacing: 6) {
            Picker("Filter", selection: $filter) {
                ForEach(OutlinerVisibilityFilter.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("WorkspaceSidebar.outliner.filter")

            Menu {
                Button("Show All") { onIntent(.showAll) }
                    .accessibilityIdentifier("WorkspaceSidebar.outliner.showAll")
                Button("Isolate Selection") {
                    let ids = orderedSelectedIDs(projection: projection)
                    guard !ids.isEmpty,
                          projection.canMutate(ids: ids) else {
                        actionError = "Generated pattern outputs cannot be isolated individually. Select the pattern root."
                        return
                    }
                    onIntent(.isolate(ids: ids))
                }
                .disabled(!projection.canMutate(ids: orderedSelectedIDs(projection: projection)))
            } label: {
                WorkspaceSidebarSymbol(systemName: "ellipsis.circle")
                    .accessibilityLabel("Outliner Actions")
            }
            .menuStyle(.borderlessButton)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func rowView(_ row: OutlinerRow, projection: OutlinerProjection) -> some View {
        let showsActions = hoveredRowID == row.id || pendingStateIDs.contains(row.id) || voiceOverEnabled
        return HStack(spacing: 4) {
            Button {
                toggleExpansion(for: row.id)
            } label: {
                Group {
                    if row.hasChildren {
                        Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 13, height: 18)
                .foregroundStyle(row.hasChildren ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!row.hasChildren)
            .accessibilityHidden(!row.hasChildren)
            .accessibilityLabel(row.hasChildren
                ? (row.isExpanded ? "Collapse \(row.name)" : "Expand \(row.name)")
                : "No children"
            )

            if renamingID == row.id {
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRenameID, equals: row.id)
                    .onSubmit { commitRename(for: row) }
                    .onExitCommand { cancelRename() }
                    .accessibilityIdentifier("WorkspaceSidebar.outliner.renameField")
            } else {
                HStack(spacing: 4) {
                    WorkspaceSidebarSymbol(systemName: row.systemImage)
                        .foregroundStyle(row.isGeneratedOutput ? .secondary : .primary)
                        .accessibilityLabel(row.kindTitle)
                        .help(row.kindTitle)
                    Text(row.name)
                        .font(.system(size: 12, weight: row.depth == 0 ? .medium : .regular))
                        .foregroundStyle(row.isVisible ? .primary : .secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(row.disabledReason ?? "")
                    if row.isGeneratedOutput {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Generated output")
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onDrag {
                    makeDragProvider(for: row, projection: projection)
                }
                .onDragSessionUpdated { update in
                    handleDragSessionUpdate(update)
                }
                Button {
                    guard row.canMutateState else {
                        actionError = row.disabledReason
                        return
                    }
                    sendRowVisibility(for: row.id, isVisible: !row.isVisible)
                } label: {
                    WorkspaceSidebarSymbol(
                        systemName: pendingStateIDs.contains(row.id) ? "hourglass" : (row.isVisible ? "eye" : "eye.slash"),
                        size: 11
                    )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(row.isVisible ? .primary : .secondary)
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
                .disabled(!showsActions || !row.canMutateState || pendingStateIDs.contains(row.id))
                .accessibilityLabel(row.isVisible ? "Hide \(row.name)" : "Show \(row.name)")
                .accessibilityValue(pendingStateIDs.contains(row.id) ? "Updating" : (row.isVisible ? "Visible" : "Hidden"))
                .accessibilityIdentifier("WorkspaceSidebar.visibility.\(row.id)")
                .help(pendingStateIDs.contains(row.id) ? "Updating \(row.name)…" : (row.isVisible ? "Hide \(row.name)" : "Show \(row.name)"))

                Button {
                    guard row.canMutateState else {
                        actionError = row.disabledReason
                        return
                    }
                    sendRowLock(for: row.id, isLocked: !row.isLocked)
                } label: {
                    WorkspaceSidebarSymbol(
                        systemName: pendingStateIDs.contains(row.id) ? "hourglass" : (row.isLocked ? "lock.fill" : "lock.open"),
                        size: 11
                    )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(row.isLocked ? .primary : .secondary)
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
                .disabled(!showsActions || !row.canMutateState || pendingStateIDs.contains(row.id))
                .accessibilityLabel(row.isLocked ? "Unlock \(row.name)" : "Lock \(row.name)")
                .accessibilityValue(pendingStateIDs.contains(row.id) ? "Updating" : (row.isLocked ? "Locked" : "Unlocked"))
                .accessibilityIdentifier("WorkspaceSidebar.lock.\(row.id)")
                .help(pendingStateIDs.contains(row.id) ? "Updating \(row.name)…" : (row.isLocked ? "Unlock \(row.name)" : "Lock \(row.name)"))
            }
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .frame(minHeight: 22)
        .background(alignment: .leading) {
            if row.depth > 0 {
                Path { path in
                    for level in 0..<row.depth {
                        let x = CGFloat(level) * 18 + 6
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: 22))
                    }
                    let branchX = CGFloat(row.depth - 1) * 18 + 6
                    path.move(to: CGPoint(x: branchX, y: 11))
                    path.addLine(to: CGPoint(x: branchX + 9, y: 11))
                }
                .stroke(.tertiary, lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                hoveredRowID = row.id
            } else if hoveredRowID == row.id {
                hoveredRowID = nil
            }
            onIntent(.hover(row.id, isHovered: isHovered))
        }
        .accessibilityIdentifier("WorkspaceSidebar.outliner.row.\(row.id)")
        .contextMenu {
            if row.canRename {
                Button("Rename") { beginRename(row) }
                    .disabled(selectedIDs.contains(row.id) && selectedIDs.count > 1)
            }
            Divider()
            Button("Show") { sendContextVisibility(for: row.id, isVisible: true, projection: projection) }
                .disabled(!contextCanMutate(row.id, projection: projection))
            Button("Hide") { sendContextVisibility(for: row.id, isVisible: false, projection: projection) }
                .disabled(!contextCanMutate(row.id, projection: projection))
            Button("Lock") { sendContextLock(for: row.id, isLocked: true, projection: projection) }
                .disabled(!contextCanMutate(row.id, projection: projection))
            Button("Unlock") { sendContextLock(for: row.id, isLocked: false, projection: projection) }
                .disabled(!contextCanMutate(row.id, projection: projection))
            Divider()
            Button("Isolate Selection") {
                let ids = orderedSelectedIDs(for: row.id, projection: projection)
                guard projection.canMutate(ids: ids) else {
                    actionError = "Generated pattern outputs cannot be isolated individually. Select the pattern root."
                    return
                }
                onIntent(.isolate(ids: ids))
            }
            .disabled(!contextCanMutate(row.id, projection: projection))
            Button("Frame Current Selection") {
                onIntent(.frameCurrentSelection)
            }
            .disabled(!OutlinerProjection.frameSelectionIsEnabled(
                rowID: row.id,
                selectedIDs: selectedIDs,
                canFrameSelection: canFrameSelection
            ))
            Divider()
            let lifecycle = contextLifecycle(for: row.id, projection: projection)
            Button(lifecycle.groupActionTitle) {
                sendContextGroup(for: row.id, projection: projection)
            }
            .disabled(!lifecycle.canGroup)
            Button(lifecycle.ungroupActionTitle) {
                sendContextUngroup(for: row.id, projection: projection)
            }
            .disabled(!lifecycle.canUngroup)
            Divider()
            Button("Delete", role: .destructive) {
                sendContextDelete(for: row.id, projection: projection)
            }
            .disabled(!lifecycle.canDelete)
        }
    }

    private func selectionBinding(projection: OutlinerProjection) -> Binding<Set<SceneNodeID>> {
        Binding(
            get: { selectedIDs },
            set: { ids in
                let orderedIDs = projection.allRows.map(\.id).filter { ids.contains($0) }
                onIntent(.select(orderedIDs))
            }
        )
    }

    private func orderedSelectedIDs(projection: OutlinerProjection) -> [SceneNodeID] {
        projection.allRows.map(\.id).filter { selectedIDs.contains($0) }
    }

    private func orderedSelectedIDs(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) -> [SceneNodeID] {
        let ids = contextIDs(for: contextID, projection: projection)
        settleSelection(for: contextID)
        return ids
    }

    /// Folds an unselected context row into the selection, so that what the tree shows afterwards is
    /// what the action was taken on.
    private func settleSelection(for contextID: SceneNodeID) {
        guard !selectedIDs.contains(contextID) else {
            return
        }
        onIntent(.select([contextID]))
    }

    /// The rows a context action would act on, without settling the selection.
    ///
    /// Availability is read while the menu lays out, so it cannot be answered by the variant that
    /// folds an unselected row into the selection first.
    private func contextIDs(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) -> [SceneNodeID] {
        OutlinerProjection.contextSelection(
            rowID: contextID,
            selectedIDs: selectedIDs,
            orderedIDs: projection.allRows.map(\.id)
        )
    }

    private func contextCanMutate(
        _ contextID: SceneNodeID,
        projection: OutlinerProjection
    ) -> Bool {
        if selectedIDs.contains(contextID) {
            return projection.canMutate(ids: selectedIDs)
        }
        return projection.canMutate(ids: [contextID])
    }

    private func contextLifecycle(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) -> OutlinerLifecycleAvailability {
        lifecycle(ids: contextIDs(for: contextID, projection: projection), projection: projection)
    }

    private func lifecycle(
        ids: [SceneNodeID],
        projection: OutlinerProjection
    ) -> OutlinerLifecycleAvailability {
        OutlinerLifecycleAvailability(ids: ids, metadata: metadata, projection: projection)
    }

    private func sendContextGroup(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) {
        let lifecycle = contextLifecycle(for: contextID, projection: projection)
        guard lifecycle.canGroup else {
            actionError = "Locked, source-owned, or root scene nodes cannot be grouped."
            return
        }
        settleSelection(for: contextID)
        onIntent(.group(ids: lifecycle.groupableIDs))
    }

    private func sendContextUngroup(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) {
        let lifecycle = contextLifecycle(for: contextID, projection: projection)
        guard lifecycle.canUngroup else {
            actionError = "Only an unlocked group that holds no geometry of its own can be dissolved."
            return
        }
        settleSelection(for: contextID)
        onIntent(.ungroup(ids: lifecycle.dissolvableIDs))
    }

    private func sendContextDelete(
        for contextID: SceneNodeID,
        projection: OutlinerProjection
    ) {
        let lifecycle = contextLifecycle(for: contextID, projection: projection)
        guard lifecycle.canDelete else {
            actionError = "Roots, locked scene nodes, and generated pattern outputs cannot be deleted."
            return
        }
        settleSelection(for: contextID)
        onIntent(.delete(ids: lifecycle.deletableIDs))
    }

    private func makeDragProvider(
        for row: OutlinerRow,
        projection: OutlinerProjection
    ) -> NSItemProvider {
        let ids = selectedIDs.contains(row.id)
            ? projection.allRows.map(\.id).filter { selectedIDs.contains($0) }
            : [row.id]
        guard projection.canMove(ids: ids) else {
            actionError = "Locked or source-owned scene nodes cannot be moved."
            cancelDrag()
            return NSItemProvider()
        }

        let moveSession = OutlinerMoveDragSession(
            nonce: UUID(),
            ids: ids,
            expectedGeneration: generation
        )
        dragSession = moveSession
        let provider = NSItemProvider()
        let payload = OutlinerMoveDragSession.payload(for: moveSession.nonce)
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.dragType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    private func rowDropDelegate(row: OutlinerRow) -> OutlinerDropDelegate {
        let parentID = row.parentID
        let siblings = parentID.flatMap { metadata.sceneNodes[$0]?.childIDs }
            ?? metadata.rootSceneNodeIDs
        return OutlinerDropDelegate(
            acceptedType: Self.dragType,
            isLocalDragActive: { self.dragSession != nil },
            resolveDestination: { location in
                guard let destination = OutlinerProjection.dropDestination(
                    rowID: row.id,
                    parentID: parentID,
                    siblingIDs: siblings,
                    locationY: Double(location.y),
                    metadata: self.metadata
                ) else {
                    return nil
                }
                if destination.parentID == row.id,
                   destination.beforeSiblingID == nil,
                   !OutlinerProjection.canReceiveChildren(row) {
                    return nil
                }
                return destination
            },
            updateHighlight: { destination in
                self.dropDestination = destination
            },
            perform: { providers, destination in
                self.handleDrop(providers: providers, destination: destination)
            }
        )
    }

    private func rootDropDelegate() -> OutlinerDropDelegate {
        OutlinerDropDelegate(
            acceptedType: Self.dragType,
            isLocalDragActive: { self.dragSession != nil },
            resolveDestination: { _ in OutlinerProjection.rootDropDestination() },
            updateHighlight: { destination in
                self.dropDestination = destination
            },
            perform: { providers, destination in
                self.handleDrop(providers: providers, destination: destination)
            }
        )
    }

    private func handleDrop(
        providers: [NSItemProvider],
        destination: OutlinerDropDestination
    ) -> Bool {
        guard let provider = providers.first else {
            cancelDrag()
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: Self.dragType.identifier) { data, _ in
            let token = data.flatMap(OutlinerMoveDragSession.nonce(from:))
            Task { @MainActor in
                self.finishDrop(nonce: token, destination: destination)
            }
        }
        return true
    }

    private func finishDrop(
        nonce: UUID?,
        destination: OutlinerDropDestination
    ) {
        guard let moveSession = dragSession else {
            return
        }
        guard let nonce else {
            actionError = "This Outliner drag is no longer valid."
            cancelDrag()
            return
        }
        guard moveSession.nonce == nonce else {
            return
        }
        guard moveSession.matches(nonce: nonce, generation: generation) else {
            actionError = "The scene changed during the drag. Start the move again."
            cancelDrag()
            return
        }
        do {
            try OutlinerSourceCommandPlanner.validateMove(
                ids: moveSession.ids,
                parentID: destination.parentID,
                beforeSiblingID: destination.beforeSiblingID,
                in: metadata
            )
            onIntent(.move(
                ids: moveSession.ids,
                parentID: destination.parentID,
                beforeSiblingID: destination.beforeSiblingID,
                expectedGeneration: moveSession.expectedGeneration
            ))
        } catch {
            actionError = moveErrorMessage(error)
        }
        cancelDrag()
    }

    private func moveErrorMessage(_ error: Error) -> String {
        if let editorError = error as? EditorError {
            return editorError.message
        }
        return "The scene move could not be completed."
    }

    private func cancelDrag() {
        dragSession = nil
        dropDestination = nil
    }

    private func handleDragSessionUpdate(_ update: DragSession) {
        switch update.phase {
        case .ended(let operation):
            if operation != .move {
                cancelDrag()
            }
        case .initial, .active, .dataTransferCompleted:
            break
        @unknown default:
            cancelDrag()
        }
    }

    @ViewBuilder
    private func dropFeedback(for row: OutlinerRow) -> some View {
        let siblings = row.parentID.flatMap { metadata.sceneNodes[$0]?.childIDs }
            ?? metadata.rootSceneNodeIDs
        let nextSiblingID: SceneNodeID? = {
            guard let index = siblings.firstIndex(of: row.id) else { return nil }
            let nextIndex = siblings.index(after: index)
            return nextIndex < siblings.endIndex ? siblings[nextIndex] : nil
        }()
        let isBefore = dropDestination == OutlinerDropDestination(
            parentID: row.parentID,
            beforeSiblingID: row.id
        )
        let isAfter = nextSiblingID == nil
            && dropDestination == OutlinerDropDestination(
                parentID: row.parentID,
                beforeSiblingID: nil
            )
        let isParent = dropDestination == OutlinerDropDestination(
            parentID: row.id,
            beforeSiblingID: nil
        )

        ZStack {
            if isParent {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.tint, lineWidth: 2)
            }
            if isBefore {
                Rectangle()
                    .fill(.tint)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if isAfter {
                Rectangle()
                    .fill(.tint)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func toggleExpansion(for id: SceneNodeID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    private func beginRenameForSelection(projection: OutlinerProjection) {
        let selected = orderedSelectedIDs(projection: projection)
        guard selected.count == 1,
              let row = projection.row(for: selected[0]) else { return }
        beginRename(row)
    }

    private func beginRename(_ row: OutlinerRow) {
        guard row.canRename else {
            actionError = row.disabledReason ?? "Rename requires one selected editable scene node."
            return
        }
        if selectedIDs.contains(row.id) {
            guard selectedIDs.count == 1 else {
                actionError = "Rename requires one selected editable scene node."
                return
            }
        } else {
            onIntent(.select([row.id]))
        }
        renamingID = row.id
        renameDraft = row.name
        focusedRenameID = row.id
    }

    private func commitRename(for row: OutlinerRow) {
        guard let normalized = OutlinerProjection.normalizedRename(renameDraft) else {
            actionError = "A scene node name cannot be empty."
            return
        }
        onIntent(.rename(id: row.id, name: normalized))
        cancelRename()
    }

    private func cancelRename() {
        focusedRenameID = nil
        renamingID = nil
        renameDraft = ""
    }

    private func sendRowVisibility(for id: SceneNodeID, isVisible: Bool) {
        onIntent(.setVisibility(ids: [id], isVisible: isVisible))
    }

    private func sendRowLock(for id: SceneNodeID, isLocked: Bool) {
        onIntent(.setLock(ids: [id], isLocked: isLocked))
    }

    private func sendContextVisibility(
        for id: SceneNodeID,
        isVisible: Bool,
        projection: OutlinerProjection
    ) {
        onIntent(.setVisibility(
            ids: orderedSelectedIDs(for: id, projection: projection),
            isVisible: isVisible
        ))
    }

    private func sendContextLock(
        for id: SceneNodeID,
        isLocked: Bool,
        projection: OutlinerProjection
    ) {
        onIntent(.setLock(
            ids: orderedSelectedIDs(for: id, projection: projection),
            isLocked: isLocked
        ))
    }

}
