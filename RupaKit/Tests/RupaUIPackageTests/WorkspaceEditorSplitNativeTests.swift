import AppKit
import MacComponent
import SwiftUI
import Testing
@testable import RupaUI

/// The detail column's split, built the way `MainView.editorDetailPane`
/// builds it, driven through the transition that adds and removes the
/// inspector and through a change of the size it lays out at.
///
/// The split owns how it divides its bounds. It applies the opening width its
/// caller declares once, when the arranged column count changes, and from then
/// on only clamps the division it redistributes; so a declared range is a
/// drift allowance, and the caller declares a single width instead. The width
/// is declared on the pane rather than on the pane's content, because a fixed
/// width inside the column only centres the content in whatever column the
/// split handed it. What this test holds is that the inspector arrives at the
/// declared width, flush with the split's trailing edge, that a change of the
/// split's own size leaves that width alone, that withdrawing the inspector
/// gives the whole split back to the canvas, and that re-adding it opens the
/// column at the declared width again. See `RupaUI/DESIGN.md`.
///
/// The declared width measures from the split's trailing edge to the leading
/// edge of the divider, which is where `setPosition(_:ofDividerAt:)` puts the
/// number it is given, so the column itself measures the declared width less
/// the divider's thickness.
private let declaredInspectorWidth: CGFloat = 320

@MainActor
private func editorSplit(showsInspector: Bool, width: CGFloat = 1120) -> AnyView {
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
        .trailingPaneWidth(
            declaredInspectorWidth,
            minimum: declaredInspectorWidth,
            maximum: declaredInspectorWidth
        )
        .dividerDragStrip(width: 10)
        .frame(width: width, height: 720)
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
    // The inspector arrives at the width the pane declares, pinned to the
    // split's trailing edge with only the divider between it and the canvas.
    // Both columns stay inside the split's own bounds.
    #expect(inspector.width == declaredInspectorWidth - divided.split.dividerThickness)
    #expect(abs(inspector.maxX - divided.split.bounds.maxX) <= 1.0)
    #expect(inspector.minX - canvas.maxX <= divided.split.dividerThickness + 10.0)
    #expect(inspector.minX >= canvas.maxX)
    #expect(canvas.minX >= divided.split.bounds.minX)

    // Laying the same two columns out at a different size redistributes the
    // division. The canvas absorbs the change; the declared column does not
    // scale with it, in either direction.
    for width in [1400.0, 1120.0, 900.0] {
        controller.rootView = editorSplit(showsInspector: true, width: width)
        window.setContentSize(NSSize(width: width, height: 720))
        try await settle()
        let resized = try columns()
        let resizedInspector = try #require(resized.frames.last)
        #expect(resizedInspector.width == declaredInspectorWidth - resized.split.dividerThickness)
        #expect(abs(resizedInspector.maxX - resized.split.bounds.maxX) <= 1.0)
    }

    // Withdrawing the inspector rebuilds the hosted columns. The canvas has to
    // take the whole split back, not keep the width the division gave it.
    controller.rootView = editorSplit(showsInspector: false)
    window.setContentSize(NSSize(width: 1120, height: 720))
    try await settle()
    let undivided = try columns()
    #expect(undivided.frames.count == 1)
    let full = try #require(undivided.frames.first)
    #expect(abs(full.width - undivided.split.bounds.width) <= 1.0)
    #expect(full.width > canvas.width + 100.0)

    // Re-adding it rebuilds them again and opens the column at the declared
    // width rather than at whatever division the rebuild would produce.
    controller.rootView = editorSplit(showsInspector: true)
    try await settle()
    let restored = try columns()
    #expect(restored.frames.count == 2)
    let restoredInspector = try #require(restored.frames.last)
    let restoredCanvas = try #require(restored.frames.first)
    #expect(restoredInspector.width == declaredInspectorWidth - restored.split.dividerThickness)
    #expect(abs(restoredInspector.maxX - restored.split.bounds.maxX) <= 1.0)
    #expect(abs(restoredCanvas.width - canvas.width) <= 1.0)
}
