import SwiftUI

struct WorkspaceToolNameHint: ViewModifier {
    var title: String
    var edge: HorizontalEdge
    @State private var isHovered = false

    struct Hint {
        var title: String
        var edge: HorizontalEdge
        var bounds: Anchor<CGRect>
    }

    struct Preference: PreferenceKey {
        static var defaultValue: Hint? { nil }

        static func reduce(value: inout Hint?, nextValue: () -> Hint?) {
            if let next = nextValue() { value = next }
        }
    }

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .anchorPreference(key: Preference.self, value: .bounds) { bounds in
                isHovered ? Hint(title: title, edge: edge, bounds: bounds) : nil
            }
    }

    @ViewBuilder
    static func overlay(_ hint: Hint?) -> some View {
        if let hint {
            GeometryReader { geometry in
                let bounds = geometry[hint.bounds]
                Color.clear.overlay(alignment: hint.edge == .trailing ? .topLeading : .topTrailing) {
                    Text(hint.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
                        .frame(height: WorkspaceChromeControlMetrics.controlHeight)
                        .background(.regularMaterial, in: RoundedRectangle(
                            cornerRadius: WorkspaceChromeControlMetrics.cornerRadius
                        ))
                        .fixedSize()
                        .offset(
                            x: hint.edge == .trailing
                                ? bounds.maxX + WorkspaceCanvasOverlayLayout.edgePadding
                                : bounds.minX - geometry.size.width - WorkspaceCanvasOverlayLayout.edgePadding,
                            y: bounds.midY - WorkspaceChromeControlMetrics.controlHeight / 2
                        )
                        .accessibilityIdentifier("WorkspaceToolNameHint")
                        .accessibilityLabel(hint.title)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
