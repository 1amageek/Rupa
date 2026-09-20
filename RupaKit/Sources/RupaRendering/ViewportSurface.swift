import RupaCore
import SwiftCAD

/// One occurrence's resolved surface, as the native material builder consumes it.
///
/// The color is what the shading policy and any highlight decided; the other
/// three components are what the document authored. Separating them keeps the
/// builder from having to know whether a base color survived a session setting,
/// and keeps a selection highlight from repainting what a body is made of.
/// See `RupaRendering/DESIGN.md`.
struct ViewportSurface: Equatable, Sendable {
    var color: ColorRGBA
    var opacity: Double
    var metallic: Double
    var roughness: Double

    /// The surface a body carries before a document authors a material for it.
    static let neutral = ViewportSurface(
        color: Material.neutralBaseColor,
        opacity: Material.neutralOpacity,
        metallic: Material.neutralMetallic,
        roughness: Material.neutralRoughness
    )

    init(color: ColorRGBA, opacity: Double, metallic: Double, roughness: Double) {
        self.color = color
        self.opacity = opacity
        self.metallic = metallic
        self.roughness = roughness
    }

    /// The surface drawn with `color` carrying the appearance `material` authors.
    ///
    /// An occurrence naming no scene node carries no material, and the neutral
    /// appearance answers for it rather than a second policy stated here.
    init(color: ColorRGBA, authoring material: Material?) {
        self.init(
            color: color,
            opacity: material?.opacity ?? Material.neutralOpacity,
            metallic: material?.metallic ?? Material.neutralMetallic,
            roughness: material?.roughness ?? Material.neutralRoughness
        )
    }

    /// Whether this surface needs native transparent blending.
    var isTransparent: Bool { opacity < 1 }
}
