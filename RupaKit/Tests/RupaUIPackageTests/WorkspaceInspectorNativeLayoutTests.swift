import AppKit
import RupaKit
import SwiftUI
import Testing
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [280.0, 320.0])
func workspaceInspectorDisplaysFullLabelsAndValues(width: Double) throws {
    let labels = ["Document ID", "Source Features", "Generated Bodies", "Render Generation",
                  "A deliberately long property label that must remain entirely readable",
                  "生成されたオブジェクトの詳細なプロパティ名"]
    let value = "A long diagnostic value with details that must wrap instead of disappearing behind an ellipsis."
    for label in labels {
        let row = ImageRenderer(content: workspaceInspectorValueRow(label, value).frame(width: width))
        let rendered = try #require(row.nsImage)
        let available = width - 2 * WorkspaceInspectorLayout.rowHorizontalPadding
            - inspectorLabelWidth - inspectorRowSpacing
        let expectedValue = ImageRenderer(content: Text(value)
            .font(.system(size: 11).weight(.medium))
            .fixedSize(horizontal: false, vertical: true).frame(width: available))
        let expectedLabel = ImageRenderer(content: Text(label)
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true).frame(width: inspectorLabelWidth))
        let labelHeight = try #require(expectedLabel.nsImage).size.height
        let valueHeight = try #require(expectedValue.nsImage).size.height
        #expect(abs(rendered.size.width - width) < 0.5)
        #expect(rendered.size.height >= max(labelHeight, valueHeight)
            + 2 * WorkspaceInspectorLayout.rowVerticalPadding)
        #expect(rendered.size.height > WorkspaceInspectorLayout.rowMinimumHeight)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceInspectorUsesCompactNativeColumnAndPreservesDeclaredWidth() async throws {
    _ = NSApplication.shared
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let initial = try await workspace.evaluate()
    let controller = NSHostingController(rootView: MainView(
        workspace: workspace,
        operationSequencer: ProjectWorkspaceOperationSequencer()
    ))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_400, height: 800),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
    window.contentViewController = controller
    let host = controller.view
    window.setContentSize(NSSize(width: 1_400, height: 800))
    defer {
        window.contentViewController = nil
        window.close()
    }
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(!window.isVisible && !window.isKeyWindow)
    for _ in 0..<50 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }

    func verticalSplits(in view: NSView) -> [NSSplitView] {
        let children = view.subviews.flatMap { verticalSplits(in: $0) }
        guard let split = view as? NSSplitView, split.isVertical else { return children }
        return [split] + children
    }
    let splits = verticalSplits(in: host)
    let widths = splits.map { $0.arrangedSubviews.map(\.frame.width) }
    for split in splits {
        // NavigationSplitView can overlay its sidebar; each frame must remain contained.
        for column in split.arrangedSubviews where !split.isSubviewCollapsed(column) && !column.isHidden {
            #expect(column.frame.minX >= split.bounds.minX - 1)
            #expect(column.frame.maxX <= split.bounds.maxX + 1,
                    "Column overflows its native split: \(column.frame), bounds: \(split.bounds)")
        }
        #expect(split.bounds.width <= host.bounds.width + 1)
    }
    let inspector = try #require(splits.last {
        $0.arrangedSubviews.count >= 2
            && ($0.arrangedSubviews.last?.frame.width ?? 0) <= 360
    }, "Expected a native inspector beside the viewport, found split widths: \(widths)")
    let column = try #require(inspector.arrangedSubviews.last)
    // HSplitPane's trailing width includes the native divider, just as the
    // editor split contract measures setPosition(_:ofDividerAt:).
    #expect(column.frame.width + inspector.dividerThickness >= WorkspaceInspectorLayout.minimumColumnWidth)
    #expect(column.frame.width <= 360)

    func expectFullDetailHeight() {
        let frame = inspector.convert(inspector.bounds, to: host)
        let bottomGap = host.isFlipped
            ? host.bounds.maxY - frame.maxY
            : frame.minY - host.bounds.minY
        #expect(abs(bottomGap) <= 1,
                "Detail leaves unused space below it: \(frame), host: \(host.bounds)")
        for pane in inspector.arrangedSubviews where !pane.isHidden {
            #expect(abs(pane.frame.height - inspector.bounds.height) <= 1)
        }
    }
    expectFullDetailHeight()

    let dividerIndex = inspector.arrangedSubviews.count - 2
    inspector.setPosition(
        inspector.bounds.width - inspector.dividerThickness - 380,
        ofDividerAt: dividerIndex
    )
    for _ in 0..<50 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    let resizedWidth = column.frame.width
    // MainView declares a fixed trailing width. A divider move may be visible
    // transiently, but settled layout must clamp it back to that declaration.
    #expect(abs(resizedWidth + inspector.dividerThickness - WorkspaceInspectorLayout.idealColumnWidth) <= 1)
    for height in [1_024.0, 720.0] {
        window.setContentSize(NSSize(width: 1_600, height: height))
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(column.frame.width == resizedWidth)
        expectFullDetailHeight()
    }
    #expect(workspace.view?.authorityCoordinate == initial.authorityCoordinate)

    // The minimum-size window must contain the entire inspector, not just its split.
    window.setContentSize(NSSize(width: 1_120, height: 720))
    for _ in 0..<50 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    let inspectorFrame = column.convert(column.bounds, to: host)
    #expect(inspectorFrame.maxX <= host.bounds.maxX + 1,
            "Inspector exceeds the window: \(inspectorFrame), host: \(host.bounds)")

    func expectScrollContentContained(in view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            #expect(document.frame.width <= scroll.contentView.bounds.width + 1,
                    "Inspector content exceeds its viewport: \(document.frame), viewport: \(scroll.contentView.bounds)")
        }
        for child in view.subviews { expectScrollContentContained(in: child) }
    }
    expectScrollContentContained(in: column)
}
