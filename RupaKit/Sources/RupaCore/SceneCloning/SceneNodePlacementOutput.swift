/// What Place creates at each placement.
public enum SceneNodePlacementOutput: String, Codable, Hashable, Sendable {
    /// Independent copies with their own editable sources.
    case independentCopy
    /// Instances of the selection's component definition, which follow edits to the originals.
    case componentInstance
}
