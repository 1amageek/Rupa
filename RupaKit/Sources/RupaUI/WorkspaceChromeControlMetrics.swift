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

    /// A status message is a sentence, and the window toolbar it sits in also holds the document
    /// title and the commands. The sentence is allowed this much and truncates past it; the Logs
    /// pane the chip opens carries the rest.
    static let statusMessageMaximumWidth: CGFloat = 360.0

    static var iconButtonSize: CGSize {
        CGSize(width: controlHeight, height: controlHeight)
    }

    static var containerVerticalPadding: CGFloat {
        (ViewportCanvasChromeMetrics.topControlHeight - controlHeight) / 2.0
    }
}
