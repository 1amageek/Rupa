import SwiftUI

public extension View {
    func viewportCanvasGlassChrome() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: ViewportCanvasChromeMetrics.cornerRadius,
            style: .continuous
        )

        return glassEffect(
            .regular,
            in: shape
        )
        .overlay {
            shape.strokeBorder(
                Color.primary.opacity(ViewportCanvasChromeMetrics.topControlBorderOpacity),
                lineWidth: ViewportCanvasChromeMetrics.topControlBorderWidth
            )
        }
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        let shape = Capsule()

        return glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(ViewportCanvasChromeMetrics.topControlBorderOpacity),
                    lineWidth: ViewportCanvasChromeMetrics.topControlBorderWidth
                )
            }
    }
}
