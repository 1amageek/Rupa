import SwiftCAD

/// One component of one material's authored appearance.
///
/// An appearance edit names exactly one component, so a command carrying one of
/// these describes the whole edit and the components it does not name keep the
/// values the material already held. See `RupaCore/DESIGN.md`.
public enum MaterialComponentEdit: Codable, Equatable, Sendable {
    case baseColor(ColorRGBA)
    case opacity(Double)
    case metallic(Double)
    case roughness(Double)
    case ior(Double)
    case clearcoat(Double)
    case clearcoatRoughness(Double)
    case sheen(Double)
    case sheenColor(ColorRGBA)
    case sheenRoughness(Double)
    case specularColor(ColorRGBA)
    case specularIntensity(Double)
    case iridescence(Double)
    case iridescenceIOR(Double)
    /// Thickness in meters.
    case thickness(Double)
    case transmission(Double)
    /// Density in kilograms per cubic meter, or `nil` for a material without mass.
    case density(Double?)
}
