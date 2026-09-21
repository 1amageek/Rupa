import AppKit
import Testing
@testable import RupaRendering

@MainActor
@Suite
struct ViewportInputSurfaceTests {
    @Test
    func mouseMovementPublishesCurrentMeasurementPreviewPoint() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var locations: [CGPoint?] = []
        view.onHover = { point, _ in locations.append(point) }
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 30, y: 40)))
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 70, y: 60)))
        #expect(locations.count == 2)
        #expect(locations[0] != locations[1])
        #expect(locations.allSatisfy { $0 != nil })
    }

    @Test
    func cancelRoutesToActiveToolWithoutPicking() {
        let view = ViewportInputSurface.InputView()
        var cancelled = false
        var picked = false
        view.onCancel = { cancelled = true; return true }
        view.onPick = { _, _, _ in picked = true }
        view.cancelOperation(nil)
        #expect(cancelled)
        #expect(!picked)
    }

    @Test
    func primaryClickCommitsBeforePreviewClear() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var events: [String] = []
        view.onPress = { _, _, _ in events.append("press") }
        view.onPick = { _, _, _ in events.append("pick") }
        view.onDragPreview = { start, end, _ in
            if start == nil, end == nil { events.append("clear") }
        }
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 12, y: 10)))
        #expect(events == ["press", "pick", "clear"])
    }

    @Test(arguments: [false, true])
    func handledEscapeConsumesPrimaryGestureUntilNextPress(dragged: Bool) throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var events: [String] = []
        view.onCancel = { events.append("cancel"); return true }
        view.onPick = { _, _, _ in events.append("pick") }
        view.onCanvasDrag = { _, _, _, _ in events.append("drag") }
        view.onDragPreview = { start, end, _ in
            events.append(start == nil && end == nil ? "clear" : "preview")
        }
        let start = CGPoint(x: 10, y: 10)
        let end = CGPoint(x: dragged ? 60 : 12, y: 10)
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: start))
        view.cancelOperation(nil)
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: end))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: end))
        #expect(events == ["cancel", "clear"])
        events.removeAll()
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: start))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: start))
        #expect(events == ["pick", "clear"])
    }

    @Test
    func primaryDragCommitsBeforePreviewClear() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var events: [String] = []
        view.onDragPreview = { start, end, _ in
            if start == nil, end == nil {
                events.append("preview.clear")
            } else {
                events.append("preview")
            }
        }
        view.onCanvasDrag = { _, _, _, _ in
            events.append("drag")
        }
        view.onPick = { _, _, _ in
            events.append("pick")
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 60, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 60, y: 10)))

        #expect(events == ["preview", "drag", "preview.clear"])
    }

    @Test
    func dragCancelledByInputExclusionDoesNotBecomePick() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var pickCount = 0
        var dragCount = 0
        view.onPick = { _, _, _ in
            pickCount += 1
        }
        view.onCanvasDrag = { _, _, _, _ in
            dragCount += 1
        }
        view.inputExclusionRects = [
            CGRect(x: 20, y: 20, width: 160, height: 100),
        ]

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 30, y: 30)))
        view.inputExclusionRects = []
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 30, y: 30)))

        #expect(pickCount == 0)
        #expect(dragCount == 0)
    }

    @Test
    func dragCancelledByHitTestExclusionDoesNotBecomePick() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var pickCount = 0
        var dragCount = 0
        view.onPick = { _, _, _ in
            pickCount += 1
        }
        view.onCanvasDrag = { _, _, _, _ in
            dragCount += 1
        }
        view.inputExclusionRects = [
            CGRect(x: 20, y: 20, width: 160, height: 100),
        ]

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        #expect(view.hitTest(CGPoint(x: 30, y: 30)) == nil)
        view.inputExclusionRects = []
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 30, y: 30)))

        #expect(pickCount == 0)
        #expect(dragCount == 0)
    }

    @Test
    func mouseUpInsideInputExclusionCancelsGestureWithoutPick() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var pickCount = 0
        var dragCount = 0
        view.onPick = { _, _, _ in
            pickCount += 1
        }
        view.onCanvasDrag = { _, _, _, _ in
            dragCount += 1
        }
        view.inputExclusionRects = [
            CGRect(x: 20, y: 20, width: 160, height: 100),
        ]

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 30, y: 30)))

        #expect(pickCount == 0)
        #expect(dragCount == 0)
    }

    @Test
    func aMiddleButtonDragTurnsTheViewInsteadOfPanningIt() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var orbits: [CGSize] = []
        var pans: [CGSize] = []
        view.onOrbit = { delta, _ in orbits.append(delta) }
        view.onPan = { delta, _ in pans.append(delta) }

        view.otherMouseDown(with: try mouseEvent(type: .otherMouseDown, location: CGPoint(x: 40, y: 40)))
        view.otherMouseDragged(with: try mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 70, y: 55)))
        view.otherMouseUp(with: try mouseEvent(type: .otherMouseUp, location: CGPoint(x: 70, y: 55)))

        #expect(pans.isEmpty)
        #expect(orbits == [CGSize(width: 30, height: -15)])
    }

    @Test
    func aMiddleButtonDragTurnsByEachStepItMoves() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var orbits: [CGSize] = []
        view.onOrbit = { delta, _ in orbits.append(delta) }

        view.otherMouseDown(with: try mouseEvent(type: .otherMouseDown, location: CGPoint(x: 40, y: 40)))
        view.otherMouseDragged(with: try mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 60, y: 40)))
        view.otherMouseDragged(with: try mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 60, y: 70)))

        #expect(orbits == [
            CGSize(width: 20, height: 0),
            CGSize(width: 0, height: -30),
        ])
    }

    @Test
    func aSecondaryButtonDragStillPansTheView() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var orbits: [CGSize] = []
        var pans: [CGSize] = []
        view.onOrbit = { delta, _ in orbits.append(delta) }
        view.onPan = { delta, _ in pans.append(delta) }

        view.rightMouseDown(with: try mouseEvent(type: .rightMouseDown, location: CGPoint(x: 40, y: 40)))
        view.rightMouseDragged(with: try mouseEvent(type: .rightMouseDragged, location: CGPoint(x: 70, y: 55)))

        #expect(orbits.isEmpty)
        #expect(pans == [CGSize(width: 30, height: -15)])
    }

    @Test
    func hoverTakesTheKeyboardWhenNothingIsEditingText() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        window.contentView = view
        _ = window.makeFirstResponder(nil)
        #expect(window.firstResponder !== view)

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 30, y: 40)))

        #expect(window.firstResponder === view)
    }

    @Test
    func hoverLeavesTheKeyboardWithATextFieldBeingEdited() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 80, height: 22))
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 22, width: 200, height: 98))
        container.addSubview(field)
        container.addSubview(view)
        window.contentView = container
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor())
        #expect(window.firstResponder === editor)

        var hovers: [CGPoint?] = []
        view.onHover = { point, _ in hovers.append(point) }
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 120, y: 60)))

        #expect(window.firstResponder === editor)
        #expect(hovers.count == 1)
        #expect(hovers.first.flatMap { $0 } != nil)
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        location: CGPoint
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }
}
