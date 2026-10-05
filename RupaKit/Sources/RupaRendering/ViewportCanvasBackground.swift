import Foundation
import RupaCore
import simd

/// Exact canvas authoring value shared by native transport and SwiftUI composition.
enum ViewportCanvasBackground {
    static func color(for background: ViewportShading.Background) -> ColorRGBA {
        switch background {
        case .theme: ViewportTheme.backgroundColor
        case .custom(let color): color
        }
    }

    static func linearRGBA(for background: ViewportShading.Background) throws -> SIMD4<Float> {
        let color = color(for: background)
        let components = [color.r, color.g, color.b, color.a]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ViewportShadingError.invalidColor(field: "background")
        }
        func linear(_ value: Double) -> Float {
            Float(value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
        }
        return SIMD4(linear(color.r), linear(color.g), linear(color.b), Float(color.a))
    }
}
