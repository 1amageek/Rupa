import AppKit
import RupaCore
import RupaKit
import RupaProject
import RupaRendering
import SwiftUI
import Testing
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasOverlayExclusionsUseCanvasLocalCoordinates() async throws {
    _ = NSApplication.shared
    var geometry = WorkspaceCanvasChromeGeometry.empty
    let host = WorkspaceCanvasOverlayHost(
        isContextPanelVisible: true, onHover: { _ in },
        onChromeGeometryChange: { geometry = $0 }
    ) {
        Color.clear
    } toolPalette: {
        Color.blue.frame(width: 30, height: 150)
    } contextPanel: {
        Color.orange.frame(width: 180, height: 30)
    }
    .frame(width: 400, height: 300)
    .padding(80)
    let controller = NSHostingController(rootView: host)
    let window = NSWindow(contentRect: NSRect(x: 150, y: 120, width: 560, height: 460),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    #expect(!window.isVisible && !window.isKeyWindow)
    defer { window.contentViewController = nil; window.close() }
    for _ in 0..<20 {
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(geometry.exclusions.count == 2)
    for exclusion in geometry.exclusions {
        #expect(CGRect(x: 0, y: 0, width: 400, height: 300).contains(exclusion.rect))
    }
    // The canvas carries chrome on the leading and bottom edges and on no
    // others, so nothing is reserved against the trailing edge the header used
    // to float over.
    #expect(!geometry.exclusions.contains { $0.fittingEdges == .trailing })
    #expect(!geometry.exclusions.contains { $0.fittingEdges == .top })
    // The exclusion covers the gap the palette keeps from the canvas edge as
    // well as the palette itself, so it starts at the edge rather than at the
    // palette, and the viewport fits its content clear of both.
    let palette = try #require(geometry.exclusions.first { $0.fittingEdges == .leading })
    #expect(palette.rect.minX == 0.0)
    #expect(palette.rect.width == 30.0 + ViewportCanvasChromeMetrics.edgePadding)
    // The reserved height is the context panel's own measured height, not a
    // second measurement of the same view and not a rounded exclusion edge.
    #expect(geometry.contextPanelHeight == 30.0 + ViewportCanvasChromeMetrics.edgePadding)
    let panel = try #require(geometry.exclusions.first { $0.fittingEdges == .bottom })
    #expect(panel.rect.height == geometry.contextPanelHeight)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasToolbarPaletteKeepsNarrowScrollableHitRegion() async throws {
    _ = NSApplication.shared
    let content = Color.clear
        .overlay(alignment: .leading) {
            WorkspaceToolPalette(
                selectedTool: .select,
                activate: { _ in },
                accessibilityIdentifier: { "CanvasTool.\($0.rawValue)" }
            )
        }
    let controller = NSHostingController(rootView: content)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false
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
    func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
    let scroll = try #require(scrollViews(in: controller.view).first)
    let document = try #require(scroll.documentView)
    #expect(scroll.frame.width <= 50)
    #expect(scroll.frame.height <= 300)
    #expect(document.bounds.height > scroll.contentSize.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
    scroll.reflectScrolledClipView(scroll.contentView)
    #expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 1)
}
