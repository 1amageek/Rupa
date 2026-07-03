import SwiftUI

public extension View {
    func viewportCanvasGlassChrome() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: ViewportCanvasChromeMetrics.cornerRadius,
            style: .continuous
        )

        return glassEffect(.regular, in: shape)
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        let shape = Capsule()

        return glassEffect(.regular, in: shape)
    }
}
