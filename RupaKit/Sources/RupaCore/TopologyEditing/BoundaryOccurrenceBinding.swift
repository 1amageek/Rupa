import SwiftCAD

/// Retains the scene occurrences that own the two live boundary placements.
public struct BoundaryOccurrenceBinding: Codable, Hashable, Sendable {
    public var first: SceneNodeID
    public var second: SceneNodeID

    public init(first: SceneNodeID, second: SceneNodeID) {
        self.first = first
        self.second = second
    }
}
