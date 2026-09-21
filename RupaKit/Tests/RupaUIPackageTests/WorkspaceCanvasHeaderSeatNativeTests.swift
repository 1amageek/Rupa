import AppKit
import SwiftUI
import Testing
@testable import RupaUI

/// The header's width budget is arithmetic over the widths its seats declare,
/// and the budget is what keeps the row inside the narrowest canvas column.
/// A seat that mounts wider than it declares would push a later seat off that
/// column while the arithmetic still said the row fits, so each seat is
/// measured against the number the budget counted.
@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasHeaderSeatsMountAtTheWidthsTheyDeclare() async throws {
    _ = NSApplication.shared
    let scope = try await mountedFittingSize(
        WorkspaceSelectionScopeControl(
            selection: .constant(.object),
            hoverHint: .constant(WorkspaceHoverHint())
        )
    )
    #expect(scope.width == WorkspaceSelectionScopeControlLayout.contentWidth)
    #expect(scope.height == WorkspaceSelectionScopeControlLayout.buttonSize.height)

    let snaps = try await mountedFittingSize(
        WorkspaceSnapControl(
            isGridSnapEnabled: .constant(true),
            isObjectTargetingEnabled: .constant(false),
            isFixedGridVisualSpacing: .constant(false),
            isConstructionPlaneSnapEnabled: .constant(true),
            hoverHint: .constant(WorkspaceHoverHint())
        )
    )
    #expect(snaps.width == WorkspaceSnapControlLayout.contentWidth)
    #expect(snaps.height == WorkspaceSnapControlLayout.buttonSize.height)

    let planes = try await mountedFittingSize(
        WorkspacePlaneModeControl(
            selection: .constant(.adaptive),
            hoverHint: .constant(WorkspaceHoverHint())
        )
    )
    #expect(planes.width == WorkspacePlaneModeControlLayout.contentWidth)
    #expect(planes.height == WorkspacePlaneModeControlLayout.buttonSize.height)

    #expect(
        scope.width + snaps.width + planes.width
            <= WorkspaceCanvasHeaderLayout.fixedSeatsWidth
    )
}

/// Mounts one header seat in an off-screen window and reports the size it
/// asks for. The window is the narrowest the canvas column is laid out at, so
/// a seat that wanted more than it declares has the room to show it.
@MainActor
private func mountedFittingSize(_ content: some View) async throws -> CGSize {
    let controller = NSHostingController(rootView: content)
    let window = NSWindow(
        contentRect: NSRect(
            x: 0.0,
            y: 0.0,
            width: WorkspaceEditorSplitLayout.minimumCanvasWidth,
            height: WorkspaceCanvasHeaderLayout.height
        ),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    #expect(!window.isVisible && !window.isKeyWindow)
    defer {
        window.contentViewController = nil
        window.close()
    }
    for _ in 0..<20 {
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    return controller.sizeThatFits(in: window.contentLayoutRect.size)
}
