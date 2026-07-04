import CoreGraphics
import RupaRendering

enum WorkspaceChromeControlMetrics {
    static let containerHeight: CGFloat = ViewportCanvasChromeMetrics.topControlHeight
    static let containerHorizontalPadding: CGFloat =
        ViewportCanvasChromeMetrics.topControlHorizontalPadding
    static let itemSpacing: CGFloat = ViewportCanvasChromeMetrics.topControlItemSpacing
    static let controlHeight: CGFloat = ViewportCanvasChromeMetrics.topControlContentHeight
    static let horizontalPadding: CGFloat = ViewportCanvasChromeMetrics.topControlHorizontalPadding
    static let cornerRadius: CGFloat = ViewportCanvasChromeMetrics.cornerRadius - 2.0
    static let dividerHeight: CGFloat = ViewportCanvasChromeMetrics.topControlDividerHeight

    static var iconButtonSize: CGSize {
        CGSize(width: controlHeight, height: controlHeight)
    }

    static var containerVerticalPadding: CGFloat {
        (ViewportCanvasChromeMetrics.topControlHeight - controlHeight) / 2.0
    }
}
