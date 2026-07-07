import RupaRendering
import SwiftUI

struct WorkspaceCanvasOverlayHost<Content: View, TopBar: View, ToolPalette: View, UtilityRail: View, ContextPanel: View>: View {
    var isContextPanelVisible: Bool
    var onHover: (Bool) -> Void
    var onContextPanelHeightChange: (CGFloat) -> Void
    var onExclusionRectsChange: ([CGRect]) -> Void
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
            onExclusionRectsChange(WorkspaceCanvasOverlayGeometry.normalizedExclusionRects(rectsByID))
        }
    }
}

private enum WorkspaceCanvasOverlayLayout {
    static let edgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let coordinateSpaceName = "WorkspaceCanvasOverlaySpace"
}

private enum WorkspaceCanvasOverlayChromeID: Hashable {
    case topBar
    case toolPalette
    case utilityRail
    case contextPanel
}

private enum WorkspaceCanvasOverlayGeometry {
    static func normalizedHeight(_ height: CGFloat) -> CGFloat {
        max(0.0, height.rounded(.up))
    }

    static func normalizedExclusionRects(
        _ rectsByID: [WorkspaceCanvasOverlayChromeID: CGRect]
    ) -> [CGRect] {
        rectsByID.values.compactMap { rect in
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
            return normalized.isEmpty ? nil : normalized
        }
        .sorted { left, right in
            if left.minY != right.minY {
                return left.minY < right.minY
            }
            if left.minX != right.minX {
                return left.minX < right.minX
            }
            if left.width != right.width {
                return left.width < right.width
            }
            return left.height < right.height
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
