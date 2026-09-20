import Foundation
import RupaCore
import RupaCoreTypes
import SwiftCAD

/// Presentation-only lighting and color choices for a mounted viewport.
///
/// This value never enters a document, evaluation snapshot, or saved view.
public struct ViewportShading: Equatable, Hashable, Sendable {
    public enum Style: String, CaseIterable, Hashable, Sendable {
        case studio
        case matCap
        case flat

        var shaderValue: Float {
            switch self {
            case .studio: 0
            case .matCap: 1
            case .flat: 2
            }
        }
    }

    public enum SolidColor: Equatable, Hashable, Sendable {
        case single(ColorRGBA)
        case material
        case random
    }

    public enum Background: Equatable, Hashable, Sendable {
        case theme
        case custom(ColorRGBA)
    }

    public enum WireColor: String, CaseIterable, Hashable, Sendable {
        case theme
        case object
        case random
    }

    public var style: Style
    public var studioRotationDegrees: Double
    public var isSpecularEnabled: Bool
    public var solidColor: SolidColor
    public var background: Background
    public var wireColor: WireColor
    public var isBackfaceCullingEnabled: Bool

    public static let standard = ViewportShading(
        style: .studio,
        studioRotationDegrees: 0,
        isSpecularEnabled: true,
        solidColor: .material,
        background: .theme,
        wireColor: .theme,
        isBackfaceCullingEnabled: false
    )

    public init(
        style: Style = .studio,
        studioRotationDegrees: Double = 0,
        isSpecularEnabled: Bool = true,
        solidColor: SolidColor = .material,
        background: Background = .theme,
        wireColor: WireColor = .theme,
        isBackfaceCullingEnabled: Bool = false
    ) {
        self.style = style
        self.studioRotationDegrees = studioRotationDegrees
        self.isSpecularEnabled = isSpecularEnabled
        self.solidColor = solidColor
        self.background = background
        self.wireColor = wireColor
        self.isBackfaceCullingEnabled = isBackfaceCullingEnabled
    }

    public func validate() throws {
        guard studioRotationDegrees.isFinite else {
            throw ViewportShadingError.nonFiniteStudioRotation
        }
        guard (0..<360).contains(studioRotationDegrees) else {
            throw ViewportShadingError.studioRotationOutOfRange
        }
        switch solidColor {
        case .single(let color):
            try color.validateForViewportShading(field: "solidColor")
        case .material, .random:
            break
        }
        if case .custom(let color) = background {
            try color.validateForViewportShading(field: "background")
        }
    }

    /// Hardware culling is meaningful only for triangle surface passes. The
    /// line-based edge and wire passes retain their depth-tested boundaries.
    public func isBackfaceCullingActive(in displayMode: ViewportDisplayMode) -> Bool {
        isBackfaceCullingEnabled
            && (displayMode == .solid || displayMode == .normals)
    }

    /// Resolves a stable color without using Swift's process-randomized hash.
    func resolvedColor(
        for occurrenceID: SceneOccurrenceID,
        materialColor: ColorRGBA?
    ) -> SIMD4<Float> {
        switch solidColor {
        case .single(let color):
            return color.simdFloat
        case .material:
            return (materialColor ?? Material.neutralBaseColor).simdFloat
        case .random:
            return Self.stableRandomColor(seed: occurrenceID.rawValue)
        }
    }

    func resolvedWireColor(
        for occurrenceID: SceneOccurrenceID,
        objectColor: SIMD4<Float>
    ) -> SIMD4<Float> {
        switch wireColor {
        case .theme:
            return SIMD4<Float>(0.48, 0.56, 0.64, 1)
        case .object:
            return objectColor
        case .random:
            return Self.stableRandomColor(seed: occurrenceID.rawValue + ":wire")
        }
    }

    private static func stableRandomColor(seed: String) -> SIMD4<Float> {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let red = Float(0.30 + Double((hash >> 0) & 0xFF) / 255.0 * 0.52)
        let green = Float(0.30 + Double((hash >> 8) & 0xFF) / 255.0 * 0.52)
        let blue = Float(0.30 + Double((hash >> 16) & 0xFF) / 255.0 * 0.52)
        return SIMD4<Float>(red, green, blue, 1)
    }
}

public enum ViewportShadingError: Error, Equatable, LocalizedError, Sendable {
    case nonFiniteStudioRotation
    case studioRotationOutOfRange
    case invalidColor(field: String)

    public var errorDescription: String? {
        switch self {
        case .nonFiniteStudioRotation:
            "Studio light rotation must be finite."
        case .studioRotationOutOfRange:
            "Studio light rotation must be in the range 0..<360 degrees."
        case .invalidColor(let field):
            "Viewport shading color \(field) must contain finite components in 0...1."
        }
    }
}

private extension ColorRGBA {
    var simdFloat: SIMD4<Float> {
        SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }

    func validateForViewportShading(field: String) throws {
        let values = [r, g, b, a]
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ViewportShadingError.invalidColor(field: field)
        }
    }
}
