import AppKit
import Testing
@testable import RupaRendering

@MainActor
@Suite
struct ViewportInputSurfaceTests {
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
