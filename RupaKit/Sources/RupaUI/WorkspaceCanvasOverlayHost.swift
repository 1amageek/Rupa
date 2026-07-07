import RupaRendering
import SwiftUI

struct WorkspaceCanvasOverlayHost<Content: View, TopBar: View, ToolPalette: View, UtilityRail: View, ContextPanel: View>: View {
    var isContextPanelVisible: Bool
    var onHover: (Bool) -> Void
    var onContextPanelHeightChange: (CGFloat) -> Void
    var onExclusionsChange: ([ViewportCanvasOverlayExclusion]) -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var topBar: () -> TopBar
    @ViewBuilder var toolPalette: () -> ToolPalette
    @ViewBuilder var utilityRail: () -> UtilityRail
    @ViewBuilder var contextPanel: () -> ContextPanel

    var body: some View {
        ZStack {
            content()
                .zIndex(0)
        }
        .coordinateSpace(name: WorkspaceCanvasOverlayLayout.coordinateSpaceName)
        .overlay(alignment: .topTrailing) {
            topBar()
                .padding(.top, WorkspaceCanvasOverlayLayout.edgePadding)
                .padding(.horizontal, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayExclusion(.topBar)
                .onHover(perform: onHover)
        }
        .overlay(alignment: .leading) {
            toolPalette()
                .padding(.leading, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayExclusion(.toolPalette)
                .onHover(perform: onHover)
        }
        .overlay(alignment: .trailing) {
            utilityRail()
                .padding(.trailing, WorkspaceCanvasOverlayLayout.edgePadding)
                .workspaceCanvasOverlayExclusion(.utilityRail)
                .onHover(perform: onHover)
        }
        .overlay(alignment: .bottom) {
            if isContextPanelVisible {
                contextPanel()
                    .padding(.bottom, WorkspaceCanvasOverlayLayout.edgePadding)
                    .padding(.horizontal, WorkspaceCanvasOverlayLayout.edgePadding)
                    .workspaceCanvasContextPanelHeight()
                    .workspaceCanvasOverlayExclusion(.contextPanel)
                    .onHover(perform: onHover)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(ViewportContextPanelHeightPreferenceKey.self) { height in
            onContextPanelHeightChange(WorkspaceCanvasOverlayGeometry.normalizedHeight(height))
        }
        .onPreferenceChange(WorkspaceCanvasOverlayExclusionRectPreferenceKey.self) { rectsByID in
            onExclusionsChange(WorkspaceCanvasOverlayGeometry.normalizedExclusions(rectsByID))
        }
    }
}

private enum WorkspaceCanvasOverlayLayout {
    static let edgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let coordinateSpaceName = "WorkspaceCanvasOverlaySpace"
}

private enum WorkspaceCanvasOverlayGeometry {
    static func normalizedHeight(_ height: CGFloat) -> CGFloat {
        max(0.0, height.rounded(.up))
    }

    static func normalizedExclusions(
        _ rectsByID: [WorkspaceCanvasOverlayChromeID: CGRect]
    ) -> [ViewportCanvasOverlayExclusion] {
        rectsByID.compactMap { id, rect in
            guard rect.isNull == false,
                  rect.isEmpty == false,
                  rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite else {
                return nil
            }

            let minX = rect.minX.rounded(.down)
            let minY = rect.minY.rounded(.down)
            let maxX = rect.maxX.rounded(.up)
            let maxY = rect.maxY.rounded(.up)
            let normalized = CGRect(
                x: minX,
                y: minY,
                width: max(0.0, maxX - minX),
                height: max(0.0, maxY - minY)
            )
            guard normalized.isEmpty == false else {
                return nil
            }
            return ViewportCanvasOverlayExclusion(
                rect: normalized,
                fittingEdges: id.fittingEdges
            )
        }
        .sorted { left, right in
            if left.rect.minY != right.rect.minY {
                return left.rect.minY < right.rect.minY
            }
            if left.rect.minX != right.rect.minX {
                return left.rect.minX < right.rect.minX
            }
            if left.rect.width != right.rect.width {
                return left.rect.width < right.rect.width
            }
            return left.rect.height < right.rect.height
        }
    }
}

private struct WorkspaceCanvasOverlayExclusionRectPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceCanvasOverlayChromeID: CGRect] = [:]

    static func reduce(
        value: inout [WorkspaceCanvasOverlayChromeID: CGRect],
        nextValue: () -> [WorkspaceCanvasOverlayChromeID: CGRect]
    ) {
        value.merge(nextValue()) { _, next in next }
    }
}

private struct ViewportContextPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func workspaceCanvasOverlayExclusion(_ id: WorkspaceCanvasOverlayChromeID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkspaceCanvasOverlayExclusionRectPreferenceKey.self,
                    value: [
                        id: proxy.frame(
                            in: .named(WorkspaceCanvasOverlayLayout.coordinateSpaceName)
                        ),
                    ]
                )
            }
        }
    }

    func workspaceCanvasContextPanelHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ViewportContextPanelHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}
