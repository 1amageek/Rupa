import CoreGraphics
import RupaViewportScene

struct ViewportCanvasChromeLayout: Equatable {
    private struct ResolvedExclusion {
        var rect: CGRect
        var fittingEdges: ViewportCanvasFittingEdges
    }

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
    var additionalExclusions: [ViewportCanvasOverlayExclusion] = []
    var viewportBadgeWidth: CGFloat = Self.defaultViewportBadgeWidth

    init(
        viewportSize: CGSize,
        bottomReservedHeight: CGFloat = 0.0,
        additionalExclusions: [ViewportCanvasOverlayExclusion] = [],
        viewportBadgeWidth: CGFloat = Self.defaultViewportBadgeWidth
    ) {
        self.viewportSize = viewportSize
        self.bottomReservedHeight = bottomReservedHeight
        self.additionalExclusions = additionalExclusions
        self.viewportBadgeWidth = viewportBadgeWidth
    }

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
        rects.append(contentsOf: paddedAdditionalExclusions.map(\.rect))
        return rects.filter { rect in
            !rect.isEmpty && !rect.isNull
        }
    }

    var fittingInsets: ViewportLayout.FittingInsets {
        var top: CGFloat = 0.0
        var leading: CGFloat = 0.0
        var bottom: CGFloat = 0.0
        var trailing: CGFloat = 0.0

        for exclusion in fittingExclusions where !exclusion.rect.isEmpty && !exclusion.rect.isNull {
            let rect = exclusion.rect
            let edges = exclusion.fittingEdges
            if edges.contains(.top) {
                top = max(top, rect.maxY)
            }
            if edges.contains(.bottom) {
                bottom = max(bottom, viewportSize.height - rect.minY)
            }
            if edges.contains(.leading) {
                leading = max(leading, rect.maxX)
            }
            if edges.contains(.trailing) {
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

    private var fittingExclusions: [ResolvedExclusion] {
        [
            ResolvedExclusion(
                rect: viewportBadgeExclusionRect,
                fittingEdges: .top
            ),
            ResolvedExclusion(
                rect: axisControlExclusionRect,
                fittingEdges: .bottom
            ),
        ] + paddedAdditionalExclusions
    }

    private var paddedAdditionalExclusions: [ResolvedExclusion] {
        additionalExclusions.compactMap { exclusion in
            guard let clampedExclusion = exclusion.clamped(
                to: viewportSize,
                padding: Self.inputExclusionPadding
            ) else {
                return nil
            }
            return ResolvedExclusion(
                rect: clampedExclusion.rect,
                fittingEdges: clampedExclusion.fittingEdges
            )
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
        let exclusions = paddedAdditionalExclusions.map(\.rect).sorted { left, right in
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
