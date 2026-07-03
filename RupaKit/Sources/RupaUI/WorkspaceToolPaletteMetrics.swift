import CoreGraphics
import RupaCore
import RupaRendering

enum WorkspaceToolPaletteMetrics {
    static let buttonSize: CGFloat = 32.0
    static let itemSpacing: CGFloat = 4.0
    static let containerPadding: CGFloat = ViewportCanvasChromeMetrics.edgePadding / 2.0
    static let iconSize: CGFloat = 14.0
    static let selectedStrokeWidth: CGFloat = 1.0

    static func height(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else {
            return containerPadding * 2.0
        }
        return containerPadding * 2.0
            + buttonSize * CGFloat(itemCount)
            + itemSpacing * CGFloat(itemCount - 1)
    }

    static var defaultHeight: CGFloat {
        height(itemCount: ModelingTool.allCases.count)
    }
}
