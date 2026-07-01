import Foundation

public enum SelectionComponent: Codable, Equatable, Hashable, Sendable {
    case object
    case face(SelectionComponentID)
    case edge(SelectionComponentID)
    case vertex(SelectionComponentID)
    case sketchEntity(SelectionComponentID)
    case region(SelectionComponentID)
    case constructionPlane(ConstructionPlaneSourceID)
}
