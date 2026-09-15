import AppKit
import MacComponent
import SwiftUI
import Testing
@testable import RupaUI

/// The detail column's split, built the way `MainView.editorDetailPane`
/// builds it, driven through the transition that adds and removes the
/// inspector.
///
/// The split owns how it divides its bounds. The pane minimums this split
/// declares are enforced only from the NSSplitViewDelegate constrain
/// callbacks, which AppKit calls while a divider is dragged; adding a child is
/// not a drag, so they take no part in the division a newly added pane
/// receives. A fixed width on the pane's content does not decide it either:
/// the column keeps the width the split hands it and the content is centred
/// inside, which is why the inspector is left to fill whatever column it is
/// given. What this test holds is that the inspector arrives as a real column
/// flush with the split's trailing edge, that withdrawing it gives the whole
/// split back to the canvas, and that re-adding it restores the same
/// division. See `RupaUI/DESIGN.md`.
@MainActor
private func editorSplit(showsInspector: Bool) -> AnyView {
    // The split is hosted at a definite size, the way the detail column hands
    // it the proposal it was given. A representable carries no fitting size of
    // its own, so a root view without one collapses the window around it.
    AnyView(
        HSplitPane {
            Color.clear
            if showsInspector {
                Color.blue
            }
        }
        .leadingPaneWidth(minimum: 560)
        .trailingPaneWidth(minimum: 320)
        .dividerDragStrip(width: 10)
        .frame(width: 1120, height: 720)
    )
}

@MainActor
private func splitView(in view: NSView) -> NSSplitView? {
    (view as? NSSplitView) ?? view.subviews.lazy.compactMap { splitView(in: $0) }.first
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceEditorSplitHoldsTheInspectorFlushWhenItIsAddedAndRemoved() async throws {
    _ = NSApplication.shared
    let controller = NSHostingController(rootView: editorSplit(showsInspector: true))
    let window = NSWindow(
        contentRect: NSRect(x: 120, y: 120, width: 1120, height: 720),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }

    func settle() async throws {
        for _ in 0..<20 {
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func columns() throws -> (split: NSSplitView, frames: [CGRect]) {
        let split = try #require(splitView(in: controller.view))
        return (split, split.arrangedSubviews.map(\.frame))
    }

    try await settle()
    let divided = try columns()
    #expect(divided.frames.count == 2)
    let inspector = try #require(divided.frames.last)
    let canvas = try #require(divided.frames.first)
    // The inspector arrives as a column wide enough to lay its content out,
    // pinned to the split's trailing edge with only the divider between it and
    // the canvas. Both columns stay inside the split's own bounds.
    #expect(inspector.width >= 320)
    #expect(abs(inspector.maxX - divided.split.bounds.maxX) <= 1.0)
    #expect(inspector.minX - canvas.maxX <= divided.split.dividerThickness + 10.0)
    #expect(inspector.minX >= canvas.maxX)
    #expect(canvas.minX >= divided.split.bounds.minX)

    // Withdrawing the inspector rebuilds the hosted columns. The canvas has to
    // take the whole split back, not keep the width the division gave it.
    controller.rootView = editorSplit(showsInspector: false)
    try await settle()
    let undivided = try columns()
    #expect(undivided.frames.count == 1)
    let full = try #require(undivided.frames.first)
    #expect(abs(full.width - undivided.split.bounds.width) <= 1.0)
    #expect(full.width > canvas.width + 100.0)

    // Re-adding it rebuilds them again and restores the same division.
    controller.rootView = editorSplit(showsInspector: true)
    try await settle()
    let restored = try columns()
    #expect(restored.frames.count == 2)
    let restoredInspector = try #require(restored.frames.last)
    let restoredCanvas = try #require(restored.frames.first)
    #expect(abs(restoredInspector.width - inspector.width) <= 1.0)
    #expect(abs(restoredInspector.maxX - restored.split.bounds.maxX) <= 1.0)
    #expect(abs(restoredCanvas.width - canvas.width) <= 1.0)
}
