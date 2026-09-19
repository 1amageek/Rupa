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
    } topBar: {
        Color.red.frame(width: 100, height: 30)
    } toolPalette: {
        Color.blue.frame(width: 30, height: 150)
    } utilityRail: {
        Color.green.frame(width: 40, height: 180)
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
    #expect(geometry.exclusions.count == 4)
    for exclusion in geometry.exclusions {
        #expect(CGRect(x: 0, y: 0, width: 400, height: 300).contains(exclusion.rect))
    }
    let rail = try #require(geometry.exclusions.first { $0.fittingEdges == .trailing })
    #expect(rail.rect.maxX == 400)
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
