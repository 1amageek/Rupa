import CoreGraphics
import SwiftUI

struct ViewportGridRenderer {
    static func draw(
        _ grid: ViewportProjectedGrid,
        chromeLayout: ViewportCanvasChromeLayout,
        in context: inout GraphicsContext
    ) {
        var minorPath = Path()
        var majorPath = Path()
        var originPath = Path()

        for line in grid.lines {
            if line.isOrigin {
                originPath.move(to: line.start)
                originPath.addLine(to: line.end)
            } else if line.isMajor {
                majorPath.move(to: line.start)
                majorPath.addLine(to: line.end)
            } else {
                minorPath.move(to: line.start)
                minorPath.addLine(to: line.end)
            }
        }

        context.stroke(minorPath, with: .color(ViewportTheme.gridMinor), lineWidth: 0.45)
        context.stroke(majorPath, with: .color(ViewportTheme.gridMajor), lineWidth: 0.85)
        context.stroke(originPath, with: .color(ViewportTheme.gridOrigin), lineWidth: 1.05)
        drawScaleLabels(
            visibleScaleLabels(from: grid.scaleLabels, chromeLayout: chromeLayout),
            in: &context
        )
    }

    static func visibleScaleLabels(
        from labels: [ViewportProjectedGrid.ScaleLabel],
        chromeLayout: ViewportCanvasChromeLayout
    ) -> [ViewportProjectedGrid.ScaleLabel] {
        labels.filter { label in
            !chromeLayout.intersectsCanvasChrome(scaleLabelRect(for: label))
        }
    }

    static func scaleLabelRect(
        for label: ViewportProjectedGrid.ScaleLabel
    ) -> CGRect {
        let width = max(CGFloat(label.text.count) * 6.2 + 10.0, 28.0)
        return CGRect(
            x: label.position.x - width / 2.0,
            y: label.position.y - 8.0,
            width: width,
            height: 16.0
        )
    }

    private static func drawScaleLabels(
        _ labels: [ViewportProjectedGrid.ScaleLabel],
        in context: inout GraphicsContext
    ) {
        for label in labels {
            context.draw(
                Text(label.text)
                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                    .foregroundStyle(ViewportTheme.gridScaleLabel),
                at: label.position,
                anchor: .center
            )
        }
    }
}
