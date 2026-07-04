import SwiftUI

public extension View {
    func viewportCanvasGlassChrome() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: ViewportCanvasChromeMetrics.cornerRadius,
            style: .continuous
        )

        return modifier(ViewportCanvasGlassChromeModifier(shape: shape))
    }

    func viewportCanvasCapsuleGlassChrome() -> some View {
        let shape = Capsule()

        return modifier(ViewportCanvasGlassChromeModifier(shape: shape))
    }
}

private struct ViewportCanvasGlassChromeModifier<ChromeShape: InsettableShape>: ViewModifier {
    var shape: ChromeShape

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(Color.primary.opacity(ViewportCanvasChromeMetrics.surfaceTintOpacity))
            }
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(ViewportCanvasChromeMetrics.borderOpacity),
                    lineWidth: ViewportCanvasChromeMetrics.borderWidth
                )
            }
    }
}
