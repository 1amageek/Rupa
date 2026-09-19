import RupaRendering
import SwiftUI

struct WorkspaceCanvasOverlayHost<Content: View, TopBar: View, ToolPalette: View, UtilityRail: View, ContextPanel: View>: View {
    var isContextPanelVisible: Bool
    var onHover: (Bool) -> Void
    var onChromeGeometryChange: (WorkspaceCanvasChromeGeometry) -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var topBar: () -> TopBar
    @ViewBuilder var toolPalette: () -> ToolPalette
    @ViewBuilder var utilityRail: () -> UtilityRail
    @ViewBuilder var contextPanel: () -> ContextPanel
    @State private var store = WorkspaceCanvasChromeRectStore()

    var body: some View {
        ZStack {
            content()
                .zIndex(0)
        }
        .overlay(alignment: .topTrailing) {
            trailingChrome
        }
        .overlay(alignment: .leading) {
            toolPalette()
                .padding(.leading, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayChrome(.toolPalette, onChange: setChromeRect)
                .onHover(perform: onHover)
        }
        .overlay(alignment: .bottom) {
            if isContextPanelVisible {
                contextPanel()
                    .padding(.bottom, WorkspaceCanvasOverlayLayout.edgePadding)
                    .padding(.horizontal, WorkspaceCanvasOverlayLayout.edgePadding)
                    .workspaceCanvasOverlayChrome(.contextPanel, onChange: setChromeRect)
                    .onHover(perform: onHover)
                    .onDisappear {
                        clearChromeRect(.contextPanel)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceCanvasArea")
        .accessibilityLabel("Workspace canvas area")
        .coordinateSpace(name: WorkspaceCanvasOverlayLayout.coordinateSpaceName)
        .overlayPreferenceValue(WorkspaceToolNameHint.Preference.self) { hint in
            WorkspaceToolNameHint.overlay(hint)
        }
    }

    /// The chrome the canvas carries on its trailing side.
    ///
    /// The top bar and the utility rail are laid out over the same canvas, so
    /// they share one vertical budget rather than being laid out as two
    /// independent overlays, which lets the rail grow through the corner the
    /// bar holds whenever the canvas is shorter than the height the rail
    /// declares -- which is what opening the bottom logs pane does to it.
    /// `WorkspaceTrailingChromeLayout` owns how that budget is divided.
    private var trailingChrome: some View {
        WorkspaceTrailingChromeLayout(
            spacing: WorkspaceCanvasOverlayLayout.edgePadding
        ) {
            topBar()
                .padding(.top, WorkspaceCanvasOverlayLayout.edgePadding)
                .padding(.horizontal, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayChrome(.topBar, onChange: setChromeRect)
                .onHover(perform: onHover)
            utilityRail()
                .padding(.trailing, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayChrome(.utilityRail, onChange: setChromeRect)
                .onHover(perform: onHover)
        }
    }

    /// Records one chrome's measured rectangle.
    ///
    /// The host accumulates rectangles rather than reading a preference bound
    /// into this body. A bound preference would make this body both the reader
    /// and the producer of one value inside a single update, leaving the
    /// measurement with no owner outside the view that produced it. The
    /// rectangles live in a reference this body never reads, so what the view
    /// graph sees is the published value and nothing else.
    @MainActor
    private func setChromeRect(_ id: WorkspaceCanvasOverlayChromeID, _ rect: CGRect) {
        guard store.rects[id] != rect else {
            return
        }
        store.rects[id] = rect
        schedulePublication()
    }

    /// Withdraws a chrome's rectangle when that chrome leaves the overlay.
    ///
    /// The accumulated rectangles outlive the views that produced them, so a
    /// context panel that is hidden and shown again would otherwise republish
    /// the rectangle it had before it went away.
    @MainActor
    private func clearChromeRect(_ id: WorkspaceCanvasOverlayChromeID) {
        guard store.rects[id] != nil else {
            return
        }
        store.rects.removeValue(forKey: id)
        schedulePublication()
    }

    // Chrome rectangles are layout output. The workspace stores what this host
    // publishes and hands it straight back to the viewport in `content()`,
    // whose fitting insets and control-context identity derive from it, so the
    // publication is an input to the same subtree that produced the
    // measurement. Publishing on the next MainActor tick keeps the measuring
    // pass and the write that depends on it in separate passes, and replacing
    // a pending publication collapses a settling sequence into the value that
    // survives the frame. A superseded publication carries no operation
    // meaning, so dropping it reports nothing.
    @MainActor
    private func schedulePublication() {
        store.publication?.cancel()
        let geometry = WorkspaceCanvasChromeGeometry(chromeRects: store.rects)
        store.publication = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            onChromeGeometryChange(geometry)
        }
    }
}

private enum WorkspaceCanvasOverlayLayout {
    static let edgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let coordinateSpaceName = "WorkspaceCanvasOverlaySpace"
}

private extension View {
    /// Reports this chrome's rectangle in the overlay coordinate space once the
    /// layout that produced it has completed.
    @MainActor
    func workspaceCanvasOverlayChrome(
        _ id: WorkspaceCanvasOverlayChromeID,
        onChange: @escaping @MainActor (WorkspaceCanvasOverlayChromeID, CGRect) -> Void
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(WorkspaceCanvasOverlayLayout.coordinateSpaceName))
        } action: { rect in
            onChange(id, rect)
        }
    }
}
