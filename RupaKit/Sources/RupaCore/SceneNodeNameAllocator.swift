import Foundation

/// Picks a scene node name that is not already taken.
///
/// Groups are created without the user naming them, so the name has to be chosen for them. Reusing
/// a name that is already in the tree makes the browser ambiguous, so the allocator numbers the
/// base name until it is free.
public struct SceneNodeNameAllocator: Sendable {
    public init() {}

    /// `base` when no node carries that name, otherwise `base` followed by the lowest free number.
    public func uniqueName(base: String, in metadata: ProductMetadata) -> String {
        let taken = Set(metadata.sceneNodes.values.map(\.name))
        guard taken.contains(base) else {
            return base
        }
        var ordinal = 2
        while taken.contains("\(base) \(ordinal)") {
            ordinal += 1
        }
        return "\(base) \(ordinal)"
    }
}
