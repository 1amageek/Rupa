import AppKit
import SwiftUI

struct ViewportInputSurface: NSViewRepresentable {
    var onPress: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onPick: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onCanvasDrag: (CGPoint, CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onDragPreview: (CGPoint?, CGPoint?, CGSize) -> Void
    var onHover: (CGPoint?, CGSize) -> Void
    var onPan: (CGSize) -> Void
    var onZoom: (CGFloat, CGPoint, CGSize) -> Void
    var onOrbit: (CGSize) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.allowedTouchTypes = [.indirect]
        view.wantsRestingTouches = false
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {
        nsView.onPress = onPress
        nsView.onPick = onPick
        nsView.onCanvasDrag = onCanvasDrag
        nsView.onDragPreview = onDragPreview
        nsView.onHover = onHover
        nsView.onPan = onPan
        nsView.onZoom = onZoom
        nsView.onOrbit = onOrbit
    }
}

extension ViewportInputSurface {
    final class InputView: NSView {
        var onPress: ((CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onPick: ((CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onCanvasDrag: ((CGPoint, CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onDragPreview: ((CGPoint?, CGPoint?, CGSize) -> Void)?
        var onHover: ((CGPoint?, CGSize) -> Void)?
        var onPan: ((CGSize) -> Void)?
        var onZoom: ((CGFloat, CGPoint, CGSize) -> Void)?
        var onOrbit: ((CGSize) -> Void)?

        private var dragStart: CGPoint?
        private var isOrbiting = false
        private var lastOrbitCentroid: CGPoint?

        override var isFlipped: Bool {
            true
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            for trackingArea in trackingAreas {
                removeTrackingArea(trackingArea)
            }

            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [
                        .activeInKeyWindow,
                        .inVisibleRect,
                        .mouseEnteredAndExited,
                        .mouseMoved,
                    ],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            dragStart = location(from: event)
            if let dragStart {
                onPress?(dragStart, bounds.size, selectionIntent(from: event))
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart else {
                return
            }
            onDragPreview?(dragStart, location(from: event), bounds.size)
        }

        override func mouseUp(with event: NSEvent) {
            let end = location(from: event)
            let intent = selectionIntent(from: event)
            guard let start = dragStart else {
                onPick?(end, bounds.size, intent)
                return
            }

            dragStart = nil
            onDragPreview?(nil, nil, bounds.size)
            let dragDistance = hypot(end.x - start.x, end.y - start.y)
            if dragDistance <= 4.0 {
                onPick?(end, bounds.size, intent)
            } else {
                onCanvasDrag?(start, end, bounds.size, intent)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            dragStart = location(from: event)
        }

        override func rightMouseDragged(with event: NSEvent) {
            panDrag(to: location(from: event))
        }

        override func rightMouseUp(with event: NSEvent) {
            dragStart = nil
        }

        override func otherMouseDown(with event: NSEvent) {
            dragStart = location(from: event)
        }

        override func otherMouseDragged(with event: NSEvent) {
            panDrag(to: location(from: event))
        }

        override func otherMouseUp(with event: NSEvent) {
            dragStart = nil
        }

        override func mouseMoved(with event: NSEvent) {
            onHover?(location(from: event), bounds.size)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(nil, bounds.size)
        }

        override func scrollWheel(with event: NSEvent) {
            resetOrbitTracking()
            handlePanZoomScroll(event)
        }

        private func handlePanZoomScroll(_ event: NSEvent) {
            let location = location(from: event)
            let shouldZoom = event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.option)
                || !event.hasPreciseScrollingDeltas

            if shouldZoom {
                let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.010 : 0.080
                let factor = min(max(exp(event.scrollingDeltaY * sensitivity), 0.20), 5.0)
                onZoom?(factor, location, bounds.size)
            } else {
                onPan?(
                    CGSize(
                        width: event.scrollingDeltaX,
                        height: event.scrollingDeltaY
                    )
                )
            }
        }

        override func magnify(with event: NSEvent) {
            guard !isOrbiting else {
                return
            }

            let factor = min(max(1.0 + event.magnification, 0.20), 5.0)
            onZoom?(factor, location(from: event), bounds.size)
        }

        override func touchesBegan(with event: NSEvent) {
            handleOrbitTouches(event)
        }

        override func touchesMoved(with event: NSEvent) {
            handleOrbitTouches(event)
        }

        override func touchesEnded(with event: NSEvent) {
            endOrbitIfNeeded(event)
        }

        override func touchesCancelled(with event: NSEvent) {
            resetOrbitTracking()
        }

        private func panDrag(to end: CGPoint) {
            guard let start = dragStart else {
                dragStart = end
                return
            }

            dragStart = end
            onPan?(
                CGSize(
                    width: end.x - start.x,
                    height: end.y - start.y
                )
            )
        }

        private func handleOrbitTouches(_ event: NSEvent) {
            let touches = activeIndirectTouches(from: event)
            guard touches.count == 3 else {
                endOrbitIfNeeded(event)
                return
            }

            isOrbiting = true
            dragStart = nil
            onDragPreview?(nil, nil, bounds.size)

            let current = averagePosition(touches.map(\.normalizedPosition))
            guard let previous = lastOrbitCentroid else {
                lastOrbitCentroid = current
                return
            }
            lastOrbitCentroid = current

            let delta = CGSize(
                width: (current.x - previous.x) * bounds.width,
                height: -(current.y - previous.y) * bounds.height
            )
            guard hypot(delta.width, delta.height) > 0.01 else {
                return
            }
            onOrbit?(delta)
        }

        private func endOrbitIfNeeded(_ event: NSEvent) {
            if activeIndirectTouches(from: event).count < 3 {
                resetOrbitTracking()
            }
        }

        private func resetOrbitTracking() {
            isOrbiting = false
            lastOrbitCentroid = nil
        }

        private func activeIndirectTouches(from event: NSEvent) -> [NSTouch] {
            event.touches(matching: .touching, in: self)
                .filter { touch in
                    touch.type == .indirect && !touch.isResting
                }
        }

        private func averagePosition(_ positions: [CGPoint]) -> CGPoint {
            guard !positions.isEmpty else {
                return .zero
            }
            let total = positions.reduce(CGPoint.zero) { partialResult, point in
                CGPoint(
                    x: partialResult.x + point.x,
                    y: partialResult.y + point.y
                )
            }
            let count = CGFloat(positions.count)
            return CGPoint(x: total.x / count, y: total.y / count)
        }

        private func location(from event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        private func selectionIntent(from event: NSEvent) -> ViewportSelectionIntent {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.shift) {
                return .toggle
            }
            return .replace
        }
    }
}
