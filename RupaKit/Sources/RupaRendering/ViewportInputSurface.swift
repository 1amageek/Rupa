import AppKit
import SwiftUI

public struct ViewportInputModifierFlags: Equatable, Sendable {
    public var containsShift: Bool
    public var containsControl: Bool
    public var containsCommand: Bool
    public var containsOption: Bool

    public init(
        containsShift: Bool = false,
        containsControl: Bool = false,
        containsCommand: Bool = false,
        containsOption: Bool = false
    ) {
        self.containsShift = containsShift
        self.containsControl = containsControl
        self.containsCommand = containsCommand
        self.containsOption = containsOption
    }

    init(_ flags: NSEvent.ModifierFlags) {
        self.init(
            containsShift: flags.contains(.shift),
            containsControl: flags.contains(.control),
            containsCommand: flags.contains(.command),
            containsOption: flags.contains(.option)
        )
    }
}

struct ViewportInputSurface: NSViewRepresentable {
    var onPress: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onPick: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onCanvasDrag: (CGPoint, CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onDragPreview: (CGPoint?, CGPoint?, CGSize) -> Void
    var onHover: (CGPoint?, CGSize) -> Void
    var onPan: (CGSize) -> Void
    var onZoom: (CGFloat, CGPoint, CGSize) -> Void
    var onOrbit: (CGSize) -> Void
    var onModifierFlagsChange: (ViewportInputModifierFlags, CGSize) -> Void
    var onSecondaryClick: (CGPoint, CGSize) -> Void
    var onShiftScroll: (ViewportScrollDirection) -> Bool
    var onShiftTap: (CGPoint, CGSize) -> Bool

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
        nsView.onModifierFlagsChange = onModifierFlagsChange
        nsView.onSecondaryClick = onSecondaryClick
        nsView.onShiftScroll = onShiftScroll
        nsView.onShiftTap = onShiftTap
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
        var onModifierFlagsChange: ((ViewportInputModifierFlags, CGSize) -> Void)?
        var onSecondaryClick: ((CGPoint, CGSize) -> Void)?
        var onShiftScroll: ((ViewportScrollDirection) -> Bool)?
        var onShiftTap: ((CGPoint, CGSize) -> Bool)?

        private var dragStart: CGPoint?
        private var secondaryDragStart: CGPoint?
        private var isOrbiting = false
        private var lastOrbitCentroid: CGPoint?
        private var shiftScrollAccumulator: CGFloat = 0.0
        private var isShiftPressed = false

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
            publishModifierFlags(from: event)
            window?.makeFirstResponder(self)
            dragStart = location(from: event)
            if let dragStart {
                onPress?(dragStart, bounds.size, selectionIntent(from: event))
            }
        }

        override func mouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            guard let dragStart else {
                return
            }
            onDragPreview?(dragStart, location(from: event), bounds.size)
        }

        override func mouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
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
            publishModifierFlags(from: event)
            let location = location(from: event)
            dragStart = location
            secondaryDragStart = location
        }

        override func rightMouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            panDrag(to: location(from: event))
        }

        override func rightMouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
            let end = location(from: event)
            if let start = secondaryDragStart {
                let dragDistance = hypot(end.x - start.x, end.y - start.y)
                if dragDistance <= 4.0 {
                    onSecondaryClick?(end, bounds.size)
                }
            }
            dragStart = nil
            secondaryDragStart = nil
        }

        override func otherMouseDown(with event: NSEvent) {
            publishModifierFlags(from: event)
            dragStart = location(from: event)
        }

        override func otherMouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            panDrag(to: location(from: event))
        }

        override func otherMouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
            dragStart = nil
        }

        override func mouseMoved(with event: NSEvent) {
            publishModifierFlags(from: event)
            window?.makeFirstResponder(self)
            onHover?(location(from: event), bounds.size)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(nil, bounds.size)
        }

        override func scrollWheel(with event: NSEvent) {
            publishModifierFlags(from: event)
            resetOrbitTracking()
            if handleShiftScroll(event) {
                return
            }
            handlePanZoomScroll(event)
        }

        private func handlePanZoomScroll(_ event: NSEvent) {
            shiftScrollAccumulator = 0.0
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

        override func flagsChanged(with event: NSEvent) {
            publishModifierFlags(from: event)
            let isPressed = event.modifierFlags.contains(.shift)
            defer {
                isShiftPressed = isPressed
            }
            guard isPressed, !isShiftPressed else {
                return
            }
            let location = location(from: event)
            guard bounds.contains(location) else {
                return
            }
            _ = onShiftTap?(location, bounds.size)
        }

        private func handleShiftScroll(_ event: NSEvent) -> Bool {
            guard let onShiftScroll,
                  event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option) else {
                shiftScrollAccumulator = 0.0
                return false
            }

            let vertical = event.scrollingDeltaY
            let horizontal = event.scrollingDeltaX
            let dominant = abs(vertical) >= abs(horizontal) ? vertical : horizontal
            guard dominant != 0.0 else {
                return true
            }

            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8.0 : 1.0
            shiftScrollAccumulator += dominant
            while shiftScrollAccumulator >= threshold {
                _ = onShiftScroll(.up)
                shiftScrollAccumulator -= threshold
            }
            while shiftScrollAccumulator <= -threshold {
                _ = onShiftScroll(.down)
                shiftScrollAccumulator += threshold
            }
            return true
        }

        override func magnify(with event: NSEvent) {
            publishModifierFlags(from: event)
            guard !isOrbiting else {
                return
            }

            let factor = min(max(1.0 + event.magnification, 0.20), 5.0)
            onZoom?(factor, location(from: event), bounds.size)
        }

        private func publishModifierFlags(from event: NSEvent) {
            onModifierFlagsChange?(ViewportInputModifierFlags(event.modifierFlags), bounds.size)
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
            secondaryDragStart = nil
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
