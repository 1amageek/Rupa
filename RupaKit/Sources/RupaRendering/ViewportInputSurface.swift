import AppKit
import SwiftUI
import RupaViewportScene

extension ViewportInputModifierFlags {
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
    /// How far a press has to travel before it counts as a drag rather than a click.
    ///
    /// One number decides both halves of the gesture: whether the release commits an edit, and
    /// whether the edit is shown on the way there. Two numbers would let the canvas preview an
    /// edit the release then declines to make. The secondary button asks the same question of
    /// its own release, and the canvas drag placeholder of its rectangle, so they read it too.
    static let dragActivationDistance: CGFloat = 4.0

    var onPress: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onPick: (CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onCanvasDrag: (CGPoint, CGPoint, CGSize, ViewportSelectionIntent) -> Void
    var onDragPreview: (CGPoint?, CGPoint?, CGSize) -> Void
    var onHover: (CGPoint?, CGSize) -> Void
    var onPan: (CGSize, CGSize) -> Void
    var onZoom: (CGFloat, CGPoint, CGSize) -> Void
    var onOrbit: (CGSize, CGSize) -> Void
    var onModifierFlagsChange: (ViewportInputModifierFlags, CGSize) -> Void
    var onSecondaryClick: (CGPoint, CGSize) -> Void
    var onShiftScroll: (ViewportScrollDirection) -> Bool
    var onShiftTap: (CGPoint, CGSize) -> Bool
    var onCancel: () -> Bool = { false }
    var onDelete: () -> Bool = { false }
    var inputExclusionRects: [CGRect] = []

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
        nsView.onCancel = onCancel
        nsView.onDelete = onDelete
        nsView.inputExclusionRects = inputExclusionRects
    }
}

extension ViewportInputSurface {
    final class InputView: NSView {
        var onPress: ((CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onPick: ((CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onCanvasDrag: ((CGPoint, CGPoint, CGSize, ViewportSelectionIntent) -> Void)?
        var onDragPreview: ((CGPoint?, CGPoint?, CGSize) -> Void)?
        var onHover: ((CGPoint?, CGSize) -> Void)?
        var onPan: ((CGSize, CGSize) -> Void)?
        var onZoom: ((CGFloat, CGPoint, CGSize) -> Void)?
        var onOrbit: ((CGSize, CGSize) -> Void)?
        var onModifierFlagsChange: ((ViewportInputModifierFlags, CGSize) -> Void)?
        var onSecondaryClick: ((CGPoint, CGSize) -> Void)?
        var onShiftScroll: ((ViewportScrollDirection) -> Bool)?
        var onShiftTap: ((CGPoint, CGSize) -> Bool)?
        var onCancel: (() -> Bool)?
        var onDelete: (() -> Bool)?
        var inputExclusionRects: [CGRect] = [] {
            didSet {
                guard oldValue != inputExclusionRects else {
                    return
                }
                reevaluateInputExclusionForTrackedPointer()
            }
        }

        private var dragStart: CGPoint?
        private var secondaryDragStart: CGPoint?
        private var primaryDragCancelled = false
        private var primaryDragActivated = false
        private var isOrbiting = false
        private var isInsideInputExclusion = false
        private var trackedPointerLocation: CGPoint?
        private var lastOrbitCentroid: CGPoint?
        private var shiftScrollAccumulator: CGFloat = 0.0
        private var isShiftPressed = false

        override var isFlipped: Bool {
            true
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 51 || event.keyCode == 117),
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               onDelete?() == true {
                return
            }
            super.keyDown(with: event)
        }

        override func cancelOperation(_ sender: Any?) {
            guard onCancel?() == true else {
                // `NSResponder` declares `cancelOperation(_:)` as a key-binding
                // command but provides no implementation, so calling `super`
                // raises an unrecognized selector. Forward the command up the
                // chain instead, starting past this view so it cannot recurse,
                // and let it be dropped when no responder handles it.
                _ = nextResponder?.tryToPerform(
                    #selector(NSStandardKeyBindingResponding.cancelOperation(_:)),
                    with: sender
                )
                return
            }
            if dragStart != nil { primaryDragCancelled = true }
            dragStart = nil
            secondaryDragStart = nil
            primaryDragActivated = false
            onDragPreview?(nil, nil, bounds.size)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        /// Refuses the points the canvas chrome covers, so a control drawn over
        /// the viewport receives the click the canvas would otherwise take.
        ///
        /// AppKit states the point in the superview's coordinate system, and
        /// the superview is not flipped. This view is, and the exclusions are
        /// published in this view's own coordinates, so the point has to be
        /// converted before it can be compared with them. `super` is still
        /// given the point it was handed.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = inputExclusionLocation(for: point)
            trackPointer(at: localPoint)
            if isInputExcluded(localPoint) {
                clearInteractionStateForInputExclusion()
                return nil
            }
            return super.hitTest(point)
        }

        /// Restates a point `hitTest(_:)` was given in this view's coordinates,
        /// which is the space the exclusions and the tracked pointer use.
        private func inputExclusionLocation(for point: NSPoint) -> CGPoint {
            guard let superview else {
                return point
            }
            return convert(point, from: superview)
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
            primaryDragCancelled = false
            primaryDragActivated = false
            dragStart = location(from: event)
            guard let dragStart,
                  !isInputExcluded(dragStart) else {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            onPress?(dragStart, bounds.size, selectionIntent(from: event))
        }

        override func mouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            guard let dragStart else {
                return
            }
            markCanvasInputActive()
            let location = location(from: event)
            guard updatePrimaryDragActivation(from: dragStart, to: location) else {
                return
            }
            onDragPreview?(dragStart, location, bounds.size)
        }

        /// Whether the press that began at `start` has become a drag by the time it reached
        /// `current`, taking note when it has.
        ///
        /// A hand resting on the button moves a pixel or two, and every one of those pixels used
        /// to be published as a drag: pressing a handle to select it moved the thing it was aimed
        /// at, evaluated the edit, and put it back on release. The release already ignored that
        /// movement, so the canvas was showing edits the release had no intention of making.
        ///
        /// Once a press has travelled far enough it stays a drag. Bringing a drag back to its
        /// press point is how it is reduced to nothing, and the release commits that nothing
        /// rather than re-measuring and picking whatever the pointer came to rest on.
        private func updatePrimaryDragActivation(from start: CGPoint, to current: CGPoint) -> Bool {
            if primaryDragActivated {
                return true
            }
            let distance = hypot(current.x - start.x, current.y - start.y)
            primaryDragActivated = distance > ViewportInputSurface.dragActivationDistance
            return primaryDragActivated
        }

        override func mouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
            let end = location(from: event)
            if isInputExcluded(end) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            let intent = selectionIntent(from: event)
            guard let start = dragStart else {
                if !primaryDragCancelled {
                    onPick?(end, bounds.size, intent)
                }
                primaryDragCancelled = false
                return
            }

            dragStart = nil
            if updatePrimaryDragActivation(from: start, to: end) {
                onCanvasDrag?(start, end, bounds.size, intent)
                onDragPreview?(nil, nil, bounds.size)
            } else {
                onPick?(end, bounds.size, intent)
                onDragPreview?(nil, nil, bounds.size)
            }
            primaryDragActivated = false
            primaryDragCancelled = false
        }

        override func rightMouseDown(with event: NSEvent) {
            publishModifierFlags(from: event)
            let location = location(from: event)
            guard !isInputExcluded(location) else {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            dragStart = location
            secondaryDragStart = location
        }

        override func rightMouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            panDrag(to: location(from: event))
        }

        override func rightMouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
            let end = location(from: event)
            if isInputExcluded(end) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            if let start = secondaryDragStart {
                let dragDistance = hypot(end.x - start.x, end.y - start.y)
                if dragDistance <= ViewportInputSurface.dragActivationDistance {
                    onSecondaryClick?(end, bounds.size)
                }
            }
            dragStart = nil
            secondaryDragStart = nil
        }

        override func otherMouseDown(with event: NSEvent) {
            publishModifierFlags(from: event)
            dragStart = location(from: event)
            if let dragStart,
               isInputExcluded(dragStart) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
        }

        override func otherMouseDragged(with event: NSEvent) {
            publishModifierFlags(from: event)
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            orbitDrag(to: location(from: event))
        }

        override func otherMouseUp(with event: NSEvent) {
            publishModifierFlags(from: event)
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            dragStart = nil
        }

        override func mouseMoved(with event: NSEvent) {
            publishModifierFlags(from: event)
            takeKeyboardForHover()
            let location = location(from: event)
            guard !isInputExcluded(location) else {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
            onHover?(location, bounds.size)
        }

        override func mouseExited(with event: NSEvent) {
            trackedPointerLocation = nil
            markCanvasInputActive()
            onHover?(nil, bounds.size)
        }

        override func scrollWheel(with event: NSEvent) {
            publishModifierFlags(from: event)
            resetOrbitTracking()
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()
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
                    ),
                    bounds.size
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
            guard bounds.contains(location),
                  !isInputExcluded(location) else {
                return
            }
            markCanvasInputActive()
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
            if isInputExcluded(location(from: event)) {
                clearInteractionStateForInputExclusion()
                return
            }
            markCanvasInputActive()

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
                ),
                bounds.size
            )
        }

        private func orbitDrag(to end: CGPoint) {
            guard let start = dragStart else {
                dragStart = end
                return
            }

            dragStart = end
            onOrbit?(
                CGSize(
                    width: end.x - start.x,
                    height: end.y - start.y
                ),
                bounds.size
            )
        }

        /// Hovering the canvas takes the keyboard so the viewport's own key handling
        /// reaches the tool under the pointer, except while the window is editing text.
        private func takeKeyboardForHover() {
            guard let window,
                  window.firstResponder !== self,
                  !isWindowEditingText(window) else {
                return
            }

            window.makeFirstResponder(self)
        }

        private func isWindowEditingText(_ window: NSWindow) -> Bool {
            guard let responder = window.firstResponder else { return false }
            if responder is NSTextInputClient { return true }
            guard let control = responder as? NSControl else { return false }
            return control.currentEditor() != nil
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
            onOrbit?(delta, bounds.size)
        }

        private func endOrbitIfNeeded(_ event: NSEvent) {
            if activeIndirectTouches(from: event).count < 3 {
                resetOrbitTracking()
            }
        }

        private func isInputExcluded(_ point: CGPoint) -> Bool {
            inputExclusionRects.contains { $0.contains(point) }
        }

        private func trackPointer(at point: CGPoint) {
            guard point.x.isFinite,
                  point.y.isFinite,
                  bounds.contains(point) else {
                trackedPointerLocation = nil
                return
            }
            trackedPointerLocation = point
        }

        private func reevaluateInputExclusionForTrackedPointer() {
            guard let trackedPointerLocation else {
                return
            }
            if isInputExcluded(trackedPointerLocation) {
                clearInteractionStateForInputExclusion()
            } else if isInsideInputExclusion {
                markCanvasInputActive()
            }
        }

        private func clearInteractionStateForInputExclusion() {
            if dragStart != nil {
                primaryDragCancelled = true
            }
            let shouldPublishClear = !isInsideInputExclusion
                || dragStart != nil
                || secondaryDragStart != nil
                || isOrbiting
            dragStart = nil
            secondaryDragStart = nil
            primaryDragActivated = false
            shiftScrollAccumulator = 0.0
            resetOrbitTracking()
            isInsideInputExclusion = true
            guard shouldPublishClear else {
                return
            }
            onDragPreview?(nil, nil, bounds.size)
            onHover?(nil, bounds.size)
        }

        private func markCanvasInputActive() {
            isInsideInputExclusion = false
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
            let point = convert(event.locationInWindow, from: nil)
            trackPointer(at: point)
            return point
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
