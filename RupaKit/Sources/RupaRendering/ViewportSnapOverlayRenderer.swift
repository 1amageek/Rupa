import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftUI

struct ViewportSnapOverlayPresentation: Equatable {
    var projectedPoint: CGPoint
    var markerRect: CGRect
    var labelText: String?
    var labelBackgroundRect: CGRect?
    var labelPoint: CGPoint?
}

struct ViewportSnapOverlayRenderer {
    static func draw(
        result: SnapResolutionResult,
        layout: ViewportLayout,
        chromeLayout: ViewportCanvasChromeLayout,
        context overlayContext: ViewportSnapOverlayContext,
        in graphicsContext: inout GraphicsContext
    ) {
        guard let presentation = presentation(
            result: result,
            layout: layout,
            chromeLayout: chromeLayout,
            context: overlayContext
        ) else {
            return
        }

        let accent = Color.cyan
        let markerPath = Path(ellipseIn: presentation.markerRect)
        graphicsContext.fill(markerPath, with: .color(accent.opacity(0.22)))
        graphicsContext.stroke(markerPath, with: .color(accent.opacity(0.92)), lineWidth: 1.5)
        graphicsContext.stroke(
            crosshairPath(around: presentation.projectedPoint),
            with: .color(accent.opacity(0.84)),
            lineWidth: 1.0
        )

        guard let labelText = presentation.labelText,
              let backgroundRect = presentation.labelBackgroundRect,
              let labelPoint = presentation.labelPoint else {
            return
        }
        let backgroundPath = Path(roundedRect: backgroundRect, cornerRadius: 6.0)
        graphicsContext.fill(backgroundPath, with: .color(Color.black.opacity(0.72)))
        graphicsContext.stroke(backgroundPath, with: .color(accent.opacity(0.45)), lineWidth: 1.0)
        graphicsContext.draw(
            Text(labelText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white),
            at: labelPoint,
            anchor: .leading
        )
    }

    static func presentation(
        result: SnapResolutionResult,
        layout: ViewportLayout,
        chromeLayout: ViewportCanvasChromeLayout,
        context overlayContext: ViewportSnapOverlayContext
    ) -> ViewportSnapOverlayPresentation? {
        guard let candidate = result.selectedCandidate,
              ViewportSnapOverlayPolicy.drawsOverlay(
                  kind: candidate.kind,
                  context: overlayContext
              ) else {
            return nil
        }

        let projectedPoint = layout.project(CGPoint(
            x: result.resolvedPoint.x,
            y: result.resolvedPoint.y
        ))
        let markerRect = CGRect(
            x: projectedPoint.x - 4.0,
            y: projectedPoint.y - 4.0,
            width: 8.0,
            height: 8.0
        )

        guard ViewportSnapOverlayPolicy.drawsLabel(
            kind: candidate.kind,
            context: overlayContext
        ) else {
            return ViewportSnapOverlayPresentation(
                projectedPoint: projectedPoint,
                markerRect: markerRect,
                labelText: nil,
                labelBackgroundRect: nil,
                labelPoint: nil
            )
        }

        let backgroundRect = labelBackgroundRect(
            for: candidate.label,
            near: projectedPoint,
            chromeLayout: chromeLayout
        )
        return ViewportSnapOverlayPresentation(
            projectedPoint: projectedPoint,
            markerRect: markerRect,
            labelText: candidate.label,
            labelBackgroundRect: backgroundRect,
            labelPoint: CGPoint(
                x: backgroundRect.minX + 7.0,
                y: backgroundRect.midY
            )
        )
    }

    static func labelBackgroundRect(
        for label: String,
        near projectedPoint: CGPoint,
        chromeLayout: ViewportCanvasChromeLayout
    ) -> CGRect {
        chromeLayout.snapLabelRect(
            near: projectedPoint,
            size: CGSize(
                width: max(CGFloat(label.count) * 6.4 + 14.0, 34.0),
                height: 20.0
            )
        )
    }

    private static func crosshairPath(around point: CGPoint) -> Path {
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: point.x - 9.0, y: point.y))
        crosshair.addLine(to: CGPoint(x: point.x - 5.0, y: point.y))
        crosshair.move(to: CGPoint(x: point.x + 5.0, y: point.y))
        crosshair.addLine(to: CGPoint(x: point.x + 9.0, y: point.y))
        crosshair.move(to: CGPoint(x: point.x, y: point.y - 9.0))
        crosshair.addLine(to: CGPoint(x: point.x, y: point.y - 5.0))
        crosshair.move(to: CGPoint(x: point.x, y: point.y + 5.0))
        crosshair.addLine(to: CGPoint(x: point.x, y: point.y + 9.0))
        return crosshair
    }
}
