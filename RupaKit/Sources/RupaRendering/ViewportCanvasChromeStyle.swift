import SwiftUI

public extension View {
    func viewportCanvasGlassChrome() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: ViewportCanvasChromeMetrics.cornerRadius,
            style: .continuous
        )

        return background {
            shape.fill(Color.primary.opacity(ViewportCanvasChromeMetrics.surfaceTintOpacity))
        }
        .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(ViewportCanvasChromeMetrics.outlineOpacity),
                    lineWidth: ViewportCanvasChromeMetrics.outlineWidth
                )
            }
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        let shape = Capsule()

        return background {
            shape.fill(Color.primary.opacity(ViewportCanvasChromeMetrics.surfaceTintOpacity))
        }
        .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(ViewportCanvasChromeMetrics.outlineOpacity),
                    lineWidth: ViewportCanvasChromeMetrics.outlineWidth
                )
            }
    }
}
