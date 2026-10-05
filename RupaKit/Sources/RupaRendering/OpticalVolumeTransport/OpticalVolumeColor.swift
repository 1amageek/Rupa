import AppKit
import simd

/// Converts the same calibrated native authoring color into linear GPU radiance.
enum OpticalVolumeColor {
    static func linear(red: Double, green: Double, blue: Double, alpha: Double) throws -> SIMD4<Float> {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite }) else { throw invalid() }
        let source = NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
        guard let native = source.usingColorSpace(.extendedLinearSRGB) else { throw invalid() }
        let image = SIMD4<Float>(Float(native.redComponent), Float(native.greenComponent),
            Float(native.blueComponent), Float(native.alphaComponent))
        guard (0..<4).allSatisfy({ image[$0].isFinite }) else { throw invalid() }
        return image
    }

    static func spatialLinear(_ color: SIMD4<Float>) throws -> SIMD4<Float> {
        let source = NSColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w))
        guard let native = source.usingColorSpace(.extendedLinearSRGB) else { throw invalid() }
        let image = SIMD4<Float>(Float(native.redComponent), Float(native.greenComponent),
            Float(native.blueComponent), Float(native.alphaComponent))
        guard (0..<4).allSatisfy({ image[$0].isFinite }) else { throw invalid() }
        return image
    }

    private static func invalid() -> MeshSourcePresentationRenderError {
        .init(code: .invalidSceneItem, message: "Optical native color cannot be represented in linear RGBA.")
    }
}
