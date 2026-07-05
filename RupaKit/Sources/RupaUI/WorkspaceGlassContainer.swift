import RupaRendering
import SwiftUI

extension View {
    func workspaceGlassContainer() -> some View {
        viewportCanvasGlassChrome()
    }

    func workspaceCanvasTopChromeContainer(contentSized: Bool = true) -> some View {
        modifier(WorkspaceCanvasTopChromeContainer(contentSized: contentSized))
    }
}

private struct WorkspaceCanvasTopChromeContainer: ViewModifier {
    var contentSized: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let chrome = content
            .padding(.horizontal, WorkspaceChromeControlMetrics.containerHorizontalPadding)
            .frame(height: WorkspaceChromeControlMetrics.containerHeight)
            .viewportCanvasTopChrome()

        if contentSized {
            chrome.fixedSize(horizontal: true, vertical: false)
        } else {
            chrome
        }
    }
}
