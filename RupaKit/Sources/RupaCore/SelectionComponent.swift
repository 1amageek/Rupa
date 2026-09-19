import Foundation

public enum SelectionComponent: Codable, Equatable, Hashable, Sendable {
    case object
    case face(SelectionComponentID)
    case edge(SelectionComponentID)
    case vertex(SelectionComponentID)
    case sketchEntity(SelectionComponentID)
    case region(SelectionComponentID)
    case constructionPlane(ConstructionPlaneSourceID)

    /// Whether the component names the whole scene node rather than a part of it.
    ///
    /// Every target carries a scene node, so a command that reads only the scene node cannot tell a
    /// picked body from a picked face on that body. That distinction matters wherever the command acts
    /// on the node itself — deleting a face's node would remove the body the face was picked on.
    public var isWholeSceneNode: Bool {
        switch self {
        case .object, .constructionPlane:
            return true
        case .face, .edge, .vertex, .sketchEntity, .region:
            return false
        }
    }
}
