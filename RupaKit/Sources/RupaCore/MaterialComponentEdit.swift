import SwiftCAD

/// One component of one material's authored appearance.
///
/// An appearance edit names exactly one component, so a command carrying one of
/// these describes the whole edit and the three components it does not name keep
/// the values the material already held. See `RupaCore/DESIGN.md`.
public enum MaterialComponentEdit: Codable, Equatable, Sendable {
    case baseColor(ColorRGBA)
    case opacity(Double)
    case metallic(Double)
    case roughness(Double)
}
