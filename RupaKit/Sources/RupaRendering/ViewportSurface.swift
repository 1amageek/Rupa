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
    var clearcoat: Double = 0
    var clearcoatRoughness: Double = 0
    /// The sheen color already scaled by the sheen amount.
    var sheen: ColorRGBA = ColorRGBA(r: 0, g: 0, b: 0, a: 1)
    var specularIntensity: Double = 1
    var transmission: Double = 0

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
        guard let material else { return }
        clearcoat = material.clearcoat
        clearcoatRoughness = material.clearcoatRoughness
        sheen = ColorRGBA(
            r: material.sheenColor.r * material.sheen,
            g: material.sheenColor.g * material.sheen,
            b: material.sheenColor.b * material.sheen,
            a: 1
        )
        specularIntensity = material.specularIntensity
        transmission = material.transmission
    }

    /// The opacity the canvas blends with: a transmitting material shows through at up to half
    /// its opacity, as Plasticity draws transparent materials outside render mode.
    var displayedOpacity: Double {
        opacity * (1 - transmission / 2)
    }

    /// Whether this surface needs native transparent blending.
    var isTransparent: Bool { displayedOpacity < 1 }
}
