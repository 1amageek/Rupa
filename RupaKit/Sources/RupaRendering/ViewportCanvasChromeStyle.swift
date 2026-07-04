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
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        let shape = Capsule()

        return background {
            shape.fill(Color.primary.opacity(ViewportCanvasChromeMetrics.surfaceTintOpacity))
        }
        .glassEffect(.regular, in: shape)
    }
}
