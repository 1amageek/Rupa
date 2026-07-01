import CoreGraphics

struct ViewportCanvasChromeLayout: Equatable {
    static let axisControlSize = CGSize(width: 286.0, height: 42.0)
    static let axisBottomPadding: CGFloat = 14.0
    static let viewportBadgeSize = CGSize(width: 326.0, height: 30.0)
    static let viewportBadgePadding: CGFloat = 12.0
    static let inputExclusionPadding: CGFloat = 6.0

    var viewportSize: CGSize
    var bottomReservedHeight: CGFloat = 0.0

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
        [
            viewportBadgeExclusionRect,
            axisControlExclusionRect,
        ].filter { !$0.isEmpty && !$0.isNull }
    }

    func containsCanvasChrome(_ point: CGPoint) -> Bool {
        inputExclusionRects.contains { $0.contains(point) }
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
