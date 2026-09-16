import AppKit
import CoreGraphics
import RupaRendering
import SwiftUI
import Testing
@testable import RupaUI

/// The canvas overlay carries two chromes on its trailing side: the top bar in
/// the corner and the utility rail beside the canvas. Both are laid out over
/// the same canvas, so unless they share one vertical budget the rail grows
/// into the corner the top bar already holds as soon as the canvas is short —
/// which is what opening the bottom logs pane does to it.
///
/// What this test holds is that the rail the host publishes never covers the
/// top bar it publishes, that a canvas with room to spare still opens the rail
/// to the height it declares, and that the rail stays centred on the canvas
/// where the tool palette on the leading side is centred. Sharing the budget
/// by stacking the rail under the bar would satisfy the first two and move the
/// rail off that centre line. See `RupaUI/DESIGN.md`.
private let canvasWidth: CGFloat = 1352.0

/// A canvas tall enough for the rail to open fully, and the canvas the logs
/// pane leaves behind.
private let roomyCanvasHeight: CGFloat = 700.0
private let shortCanvasHeight: CGFloat = 360.0

private let topBarSize = CGSize(width: 169.0, height: 26.0)
private let railWidth: CGFloat = 178.0
private let railMaximumHeight: CGFloat = 620.0

@MainActor
private final class ChromeGeometryRecorder {
    var geometry = WorkspaceCanvasChromeGeometry.empty
}

@MainActor
private func canvasOverlay(
    height: CGFloat,
    recorder: ChromeGeometryRecorder
) -> AnyView {
    AnyView(
        WorkspaceCanvasOverlayHost(
            isContextPanelVisible: false,
            onHover: { _ in },
            onChromeGeometryChange: { geometry in
                MainActor.assumeIsolated { recorder.geometry = geometry }
            }
        ) {
            Color.clear
        } topBar: {
            Color.red.frame(width: topBarSize.width, height: topBarSize.height)
        } toolPalette: {
            Color.green.frame(width: 38.0, height: 300.0)
        } utilityRail: {
            Color.blue
                .frame(width: railWidth)
                .frame(maxHeight: railMaximumHeight)
        } contextPanel: {
            EmptyView()
        }
        .frame(width: canvasWidth, height: height)
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasOverlayKeepsTheUtilityRailOutOfTheTopBarCorner() async throws {
    _ = NSApplication.shared
    let recorder = ChromeGeometryRecorder()
    let controller = NSHostingController(
        rootView: canvasOverlay(height: roomyCanvasHeight, recorder: recorder)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 80.0, y: 80.0, width: canvasWidth, height: roomyCanvasHeight),
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

    func chrome(_ edges: ViewportCanvasFittingEdges) throws -> CGRect {
        let exclusion = try #require(
            recorder.geometry.exclusions.first { $0.fittingEdges == edges }
        )
        return exclusion.rect
    }

    try await settle()
    let roomyTopBar = try chrome(.top)
    let roomyRail = try chrome(.trailing)
    let roomyPalette = try chrome(.leading)
    // A canvas with room to spare opens the rail to the height it declares,
    // and the rail leaves the corner to the top bar.
    #expect(roomyRail.height >= railMaximumHeight)
    #expect(roomyRail.height <= railMaximumHeight + 2.0)
    #expect(roomyRail.intersects(roomyTopBar) == false)
    #expect(roomyRail.minY >= roomyTopBar.maxY)
    // The rail sits on the canvas's centre line, which is the line the tool
    // palette on the leading side sits on.
    #expect(abs(roomyRail.midY - roomyPalette.midY) <= 1.0)
    #expect(abs(roomyRail.midY - roomyCanvasHeight / 2.0) <= 1.0)

    // The logs pane takes half the canvas away. The rail has to give the
    // corner up rather than grow through it.
    controller.rootView = canvasOverlay(height: shortCanvasHeight, recorder: recorder)
    window.setContentSize(NSSize(width: canvasWidth, height: shortCanvasHeight))
    try await settle()
    let shortTopBar = try chrome(.top)
    let shortRail = try chrome(.trailing)
    let shortPalette = try chrome(.leading)
    #expect(shortRail.height > 0.0)
    #expect(shortRail.height < shortCanvasHeight)
    #expect(shortRail.intersects(shortTopBar) == false)
    #expect(shortRail.minY >= shortTopBar.maxY)
    // Giving height up does not move the rail off the centre line either.
    #expect(abs(shortRail.midY - shortPalette.midY) <= 1.0)
    #expect(abs(shortRail.midY - shortCanvasHeight / 2.0) <= 1.0)
}
