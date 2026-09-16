import AppKit
import Testing
@testable import RupaRendering

/// `hitTest(_:)` is handed a point in the superview's coordinate system, and
/// AppKit's own container views are not flipped. The input surface is, and the
/// canvas host publishes its chrome exclusions in the surface's own flipped
/// coordinates. Comparing the two directly mirrors every asymmetric exclusion
/// about the viewport's horizontal centre line, so the chrome the rect
/// describes stops receiving clicks and the canvas stops receiving them at the
/// mirror position instead.
///
/// What these tests hold is that the surface refuses input where the published
/// rect actually covers, and that the hit test and the mouse-event path agree
/// on that one place. See `RupaRendering/DESIGN.md`.
private let viewportSize = CGSize(width: 1352.0, height: 962.0)

/// The badge the canvas host puts in the viewport's top-leading corner,
/// measured the way `ViewportCanvasChromeLayout` publishes it: flipped
/// coordinates, origin at the viewport's top-leading corner.
private let badgeExclusion = CGRect(x: 0.0, y: 0.0, width: 152.0, height: 36.0)

/// A point inside the badge, stated in the unflipped superview's coordinates,
/// where `hitTest(_:)` receives it.
private let pointOnBadge = CGPoint(x: 40.0, y: viewportSize.height - 18.0)

/// The same point reflected about the viewport's horizontal centre line. The
/// badge does not cover it, so the canvas has to keep it.
private let pointMirroringBadge = CGPoint(x: 40.0, y: 18.0)

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportInputSurfaceRefusesInputWhereTheChromeRectCovers() throws {
    _ = NSApplication.shared
    let container = NSView(frame: CGRect(origin: .zero, size: viewportSize))
    #expect(container.isFlipped == false)

    let surface = ViewportInputSurface.InputView(frame: container.bounds)
    container.addSubview(surface)
    #expect(surface.isFlipped)
    surface.inputExclusionRects = [badgeExclusion]

    #expect(surface.hitTest(pointOnBadge) == nil)
    #expect(surface.hitTest(pointMirroringBadge) === surface)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportInputSurfaceHitTestAndMouseEventAgreeOnTheExcludedPlace() throws {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: CGRect(origin: CGPoint(x: 120.0, y: 120.0), size: viewportSize),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    let container = NSView(frame: CGRect(origin: .zero, size: viewportSize))
    window.contentView = container
    defer { window.contentView = nil; window.close() }

    let surface = ViewportInputSurface.InputView(frame: container.bounds)
    container.addSubview(surface)
    surface.inputExclusionRects = [badgeExclusion]

    var pressedPoints: [CGPoint] = []
    surface.onPress = { point, _, _ in pressedPoints.append(point) }

    func press(at location: CGPoint) throws {
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: 0.0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1.0
            )
        )
        surface.mouseDown(with: event)
    }

    // The content view sits at the window's content origin, so a point in the
    // window reaches the surface through the same reflection `hitTest(_:)`
    // has to undo. The press the badge covers is refused; the press at the
    // mirror position reaches the canvas.
    try press(at: pointOnBadge)
    #expect(pressedPoints.isEmpty)

    try press(at: pointMirroringBadge)
    #expect(pressedPoints.count == 1)
    let reached = try #require(pressedPoints.first)
    #expect(reached.y == viewportSize.height - pointMirroringBadge.y)
}
