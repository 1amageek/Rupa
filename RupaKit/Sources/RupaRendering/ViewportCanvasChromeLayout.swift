import CoreGraphics

struct ViewportCanvasChromeLayout: Equatable {
    static let axisControlSize = CGSize(width: 286.0, height: 42.0)
    static let axisBottomPadding: CGFloat = 14.0
    static let viewportBadgeSize = CGSize(
        width: ViewportCanvasChromeMetrics.topControlMaximumWidth,
        height: ViewportCanvasChromeMetrics.topControlHeight
    )
    static let viewportBadgePadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding
    static let inputExclusionPadding: CGFloat = 6.0

    var viewportSize: CGSize
    var bottomReservedHeight: CGFloat = 0.0
    var additionalExclusionRects: [CGRect] = []

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
        clamped(
            CGRect(
                x: Self.viewportBadgePadding,
                y: Self.viewportBadgePadding,
                width: Self.viewportBadgeSize.width,
                height: Self.viewportBadgeSize.height
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
        rects.append(contentsOf: additionalExclusionRects.map { rect in
            clamped(
                rect.insetBy(
                    dx: -Self.inputExclusionPadding,
                    dy: -Self.inputExclusionPadding
                )
            )
        })
        return rects.filter { rect in
            !rect.isEmpty && !rect.isNull
        }
    }

    func containsCanvasChrome(_ point: CGPoint) -> Bool {
        inputExclusionRects.contains { $0.contains(point) }
    }

    func intersectsCanvasChrome(_ rect: CGRect) -> Bool {
        inputExclusionRects.contains { $0.intersects(rect) }
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let bounds = CGRect(origin: .zero, size: viewportSize)
        let intersection = rect.intersection(bounds)
        if intersection.isNull {
            return .zero
        }
        return intersection
    }
}
