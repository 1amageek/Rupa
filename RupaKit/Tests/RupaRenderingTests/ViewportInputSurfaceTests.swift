import AppKit
import SwiftUI
import Testing
@testable import RupaRendering

@MainActor
@Suite
struct ViewportInputSurfaceTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nativeDeleteReachesHostingCommandWithoutStealingTextEditing(handledByCanvas: Bool) async throws {
        let input = ViewportInputSurface.InputView()
        struct Host: NSViewRepresentable {
            let input: ViewportInputSurface.InputView
            func makeNSView(context: Context) -> NSView { input }
            func updateNSView(_ nsView: NSView, context: Context) {}
        }
        var deletes = 0
        var hostingDeletes = 0
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        input.onDelete = {
            if handledByCanvas { deletes += 1 }
            return handledByCanvas
        }
        window.contentView = NSHostingView(rootView: Host(input: input).onDeleteCommand { hostingDeletes += 1 })
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.makeFirstResponder(input))
        for (characters, code) in [("\u{7f}", UInt16(51)), ("\u{f728}", UInt16(117))] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
            window.sendEvent(event)
            await Task.yield()
        }
        #expect(deletes == (handledByCanvas ? 2 : 0))
        #expect(hostingDeletes == (handledByCanvas ? 0 : 1))
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 100, height: 24))
        field.stringValue = "Box"
        input.addSubview(field)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor())
        editor.selectedRange = NSRange(location: 3, length: 0)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51))
        window.sendEvent(event)
        #expect(editor.string == "Bo")
        #expect(deletes == (handledByCanvas ? 2 : 0))
        #expect(hostingDeletes == (handledByCanvas ? 0 : 1))
    }

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

    @Test
    func aPressThatBarelyMovesPublishesNoDragPreview() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var previews: [CGPoint] = []
        var picks: [CGPoint] = []
        view.onDragPreview = { start, _, _ in
            if let start { previews.append(start) }
        }
        view.onPick = { point, _, _ in picks.append(point) }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 13, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 12, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 12, y: 10)))

        #expect(previews.isEmpty)
        #expect(picks.count == 1)
    }

    @Test
    func aDragBroughtBackToItsPressPointStillCommitsAsADrag() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var drags: [(CGPoint, CGPoint)] = []
        var picks: [CGPoint] = []
        view.onCanvasDrag = { start, end, _, _ in drags.append((start, end)) }
        view.onPick = { point, _, _ in picks.append(point) }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 40, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 11, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 11, y: 10)))

        #expect(picks.isEmpty)
        #expect(drags.count == 1)
        #expect(drags.first?.0 == CGPoint(x: 10, y: 110))
        #expect(drags.first?.1 == CGPoint(x: 11, y: 110))
    }

    @Test
    func theDragPreviewBeginsAtThePressPointOnceTheDragActivates() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var previews: [(CGPoint, CGPoint)] = []
        view.onDragPreview = { start, end, _ in
            if let start, let end { previews.append((start, end)) }
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 12, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 40, y: 10)))

        #expect(previews.count == 1)
        #expect(previews.first?.0 == CGPoint(x: 10, y: 110))
        #expect(previews.first?.1 == CGPoint(x: 40, y: 110))
    }

    @Test
    func theDragActivationLatchIsReleasedByTheNextPress() throws {
        let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        var previews: [CGPoint] = []
        view.onDragPreview = { start, _, _ in
            if let start { previews.append(start) }
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 60, y: 10)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 60, y: 10)))
        let activatedPreviews = previews.count

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 13, y: 10)))

        #expect(activatedPreviews == 1)
        #expect(previews.count == activatedPreviews)
    }

    /// The distance that starts the preview is the distance that commits the
    /// release: one step short of it the gesture is a click that drew nothing,
    /// one step past it a drag that drew its preview first.
    @Test
    func oneDistanceDecidesBothHalvesOfThePrimaryGesture() throws {
        func gesture(travel: CGFloat) throws -> (previews: Int, picks: Int, drags: Int) {
            let view = ViewportInputSurface.InputView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
            var previews = 0
            var picks = 0
            var drags = 0
            view.onDragPreview = { start, _, _ in
                if start != nil { previews += 1 }
            }
            view.onPick = { _, _, _ in picks += 1 }
            view.onCanvasDrag = { _, _, _, _ in drags += 1 }

            let end = CGPoint(x: 10 + travel, y: 10)
            view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 10, y: 10)))
            view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: end))
            view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: end))
            return (previews, picks, drags)
        }

        let short = try gesture(travel: 4.0)
        #expect(short.previews == 0)
        #expect(short.picks == 1)
        #expect(short.drags == 0)

        let long = try gesture(travel: 5.0)
        #expect(long.previews == 1)
        #expect(long.picks == 0)
        #expect(long.drags == 1)
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
