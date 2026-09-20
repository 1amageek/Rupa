import SwiftCAD

extension Material {
    /// The base color a body carries before a document authors a material for it.
    ///
    /// Core owns this value because it is where an authored appearance starts.
    /// The native surface draws a body that names no material with the same
    /// color by reading it here rather than by holding its own copy.
    public static let neutralBaseColor = ColorRGBA(r: 0.64, g: 0.69, b: 0.73, a: 1.0)

    /// A material carrying the neutral appearance under `name`.
    ///
    /// An appearance edit that has to create a material starts from this one, so
    /// authoring a single component moves that component and leaves the other
    /// three where the canvas already had them. See `RupaCore/DESIGN.md`.
    public static func neutral(named name: String) -> Material {
        Material(
            name: name,
            baseColor: neutralBaseColor,
            metallic: 0.0,
            roughness: 0.38,
            opacity: 1.0
        )
    }
}
