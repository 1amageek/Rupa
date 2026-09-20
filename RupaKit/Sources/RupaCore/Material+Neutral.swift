import SwiftCAD

extension Material {
    /// The base color a body carries before a document authors a material for it.
    ///
    /// Core owns this value because it is where an authored appearance starts.
    /// The native surface draws a body that names no material with the same
    /// color by reading it here rather than by holding its own copy.
    public static let neutralBaseColor = ColorRGBA(r: 0.64, g: 0.69, b: 0.73, a: 1.0)

    /// The metallic response a body carries before a document authors one.
    public static let neutralMetallic = 0.0

    /// The roughness a body carries before a document authors one.
    public static let neutralRoughness = 0.38

    /// The opacity a body carries before a document authors one.
    public static let neutralOpacity = 1.0

    /// A material carrying the neutral appearance under `name`.
    ///
    /// This is the end of the chain a node's appearance resolves through, not a
    /// fixed seed: `sceneNodeAppearance(id:)` answers with it only when neither
    /// the node nor the document names a material, and an appearance edit that
    /// has to create a material copies whatever that read answered with. See
    /// `RupaCore/DESIGN.md`.
    public static func neutral(named name: String) -> Material {
        Material(
            name: name,
            baseColor: neutralBaseColor,
            metallic: neutralMetallic,
            roughness: neutralRoughness,
            opacity: neutralOpacity
        )
    }
}
