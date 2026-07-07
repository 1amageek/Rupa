import CoreGraphics
import RupaViewportScene

struct ViewportCanvasChromeLayout: Equatable {
    static let axisControlSize = CGSize(width: 286.0, height: 42.0)
    static let axisBottomPadding: CGFloat = 14.0
    static let minimumViewportBadgeWidth: CGFloat = 112.0
    static let maximumViewportBadgeWidth: CGFloat = ViewportCanvasChromeMetrics.topControlMaximumWidth
    static let defaultViewportBadgeWidth: CGFloat = minimumViewportBadgeWidth
    static let viewportBadgeHeight: CGFloat = ViewportCanvasChromeMetrics.topControlHeight
    static let viewportBadgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let inputExclusionPadding: CGFloat = 6.0

    var viewportSize: CGSize
    var bottomReservedHeight: CGFloat = 0.0
    var additionalExclusionRects: [CGRect] = []
    var viewportBadgeWidth: CGFloat = Self.defaultViewportBadgeWidth

    var axisControlRect: CGRect {
        clamped(
            CGRect(
                x: (viewportSize.width - Self.axisControlSize.width) / 2.0,
                y: viewportSize.height
                    - bottomReservedHeight
                    - Self.axisBottomPadding
                    - Self.axisControlSize.height,
                width: Self.axisControlSize.width,
                height: Self.axisControlSize.height
            )
        )
    }

    var axisControlExclusionRect: CGRect {
        clamped(axisControlRect.insetBy(
            dx: -Self.inputExclusionPadding,
            dy: -Self.inputExclusionPadding
        ))
    }

    var viewportBadgeRect: CGRect {
        badgeRectAvoidingAdditionalExclusions(
            clamped(
                CGRect(
                    x: Self.viewportBadgePadding,
                    y: Self.viewportBadgePadding,
                    width: clampedViewportBadgeWidth,
                    height: Self.viewportBadgeHeight
                )
            )
        )
    }

    var viewportBadgeExclusionRect: CGRect {
        clamped(viewportBadgeRect.insetBy(
            dx: -Self.inputExclusionPadding,
            dy: -Self.inputExclusionPadding
        ))
    }

    var inputExclusionRects: [CGRect] {
        var rects = [
            viewportBadgeExclusionRect,
            axisControlExclusionRect,
        ]
        rects.append(contentsOf: paddedAdditionalExclusionRects)
        return rects.filter { rect in
            !rect.isEmpty && !rect.isNull
        }
    }

    var fittingInsets: ViewportLayout.FittingInsets {
        var top: CGFloat = 0.0
        var leading: CGFloat = 0.0
        var bottom: CGFloat = 0.0
        var trailing: CGFloat = 0.0
        let edgeTolerance = Self.inputExclusionPadding + 1.0
        let bottomAnchorTolerance = max(
            edgeTolerance,
            Self.axisBottomPadding + Self.inputExclusionPadding + 1.0
        )
        let minimumVerticalChromeHeight = min(
            max(viewportSize.height * 0.20, 80.0),
            max(viewportSize.height, 0.0)
        )

        for rect in inputExclusionRects where !rect.isEmpty && !rect.isNull {
            if rect.minY <= edgeTolerance {
                top = max(top, rect.maxY)
            }
            if viewportSize.height - rect.maxY <= bottomAnchorTolerance {
                bottom = max(bottom, viewportSize.height - rect.minY)
            }
            guard rect.height >= minimumVerticalChromeHeight else {
                continue
            }
            if rect.minX <= edgeTolerance {
                leading = max(leading, rect.maxX)
            }
            if viewportSize.width - rect.maxX <= edgeTolerance {
                trailing = max(trailing, viewportSize.width - rect.minX)
            }
        }

        return ViewportLayout.FittingInsets(
            top: top,
            leading: leading,
            bottom: bottom,
            trailing: trailing
        )
    }

    private var paddedAdditionalExclusionRects: [CGRect] {
        additionalExclusionRects.map { rect in
            clamped(
                rect.insetBy(
                    dx: -Self.inputExclusionPadding,
                    dy: -Self.inputExclusionPadding
                )
            )
        }
        .filter { rect in
            !rect.isEmpty && !rect.isNull
        }
    }

    private var clampedViewportBadgeWidth: CGFloat {
        min(
            max(viewportBadgeWidth, Self.minimumViewportBadgeWidth),
            Self.maximumViewportBadgeWidth
        )
    }

    func containsCanvasChrome(_ point: CGPoint) -> Bool {
        inputExclusionRects.contains { $0.contains(point) }
    }

    func intersectsCanvasChrome(_ rect: CGRect) -> Bool {
        inputExclusionRects.contains { $0.intersects(rect) }
    }

    func snapLabelRect(near point: CGPoint, size: CGSize) -> CGRect {
        let candidateOffsets = [
            CGSize(width: 7.0, height: -25.0),
            CGSize(width: -size.width - 7.0, height: -25.0),
            CGSize(width: 7.0, height: 5.0),
            CGSize(width: -size.width - 7.0, height: 5.0),
        ]
        let candidates = candidateOffsets.map { offset in
            rectWithinViewport(CGRect(
                x: point.x + offset.width,
                y: point.y + offset.height,
                width: size.width,
                height: size.height
            ))
        }

        if let clearCandidate = candidates.first(where: { candidate in
            !intersectsCanvasChrome(candidate)
        }) {
            return clearCandidate
        }

        return candidates.first ?? .zero
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let bounds = CGRect(origin: .zero, size: viewportSize)
        let intersection = rect.intersection(bounds)
        if intersection.isNull {
            return .zero
        }
        return intersection
    }

    private func rectWithinViewport(_ rect: CGRect) -> CGRect {
        guard !rect.isEmpty, !rect.isNull else {
            return .zero
        }
        let maxOriginX = max(0.0, viewportSize.width - rect.width)
        let maxOriginY = max(0.0, viewportSize.height - rect.height)
        return CGRect(
            x: min(max(0.0, rect.origin.x), maxOriginX),
            y: min(max(0.0, rect.origin.y), maxOriginY),
            width: min(rect.width, viewportSize.width),
            height: min(rect.height, viewportSize.height)
        )
    }

    private func badgeRectAvoidingAdditionalExclusions(_ rect: CGRect) -> CGRect {
        guard !rect.isEmpty, !rect.isNull else {
            return .zero
        }

        var candidate = rect
        let exclusions = paddedAdditionalExclusionRects.sorted { left, right in
            if left.minY != right.minY {
                return left.minY < right.minY
            }
            return left.minX < right.minX
        }
        for exclusion in exclusions where candidate.intersects(exclusion) {
            let availableMaxY = max(0.0, viewportSize.height - candidate.height)
            let nextY = min(exclusion.maxY + Self.inputExclusionPadding, availableMaxY)
            if nextY > candidate.minY {
                candidate.origin.y = nextY
            }
        }
        return clamped(candidate)
    }
}
