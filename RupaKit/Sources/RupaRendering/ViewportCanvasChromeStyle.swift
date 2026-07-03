import SwiftUI

public extension View {
    func viewportCanvasGlassChrome() -> some View {
        glassEffect(
            .regular,
            in: RoundedRectangle(
                cornerRadius: ViewportCanvasChromeMetrics.cornerRadius,
                style: .continuous
            )
        )
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        glassEffect(.regular, in: Capsule())
    }
}
