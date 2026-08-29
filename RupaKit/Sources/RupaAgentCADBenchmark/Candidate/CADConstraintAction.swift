import Foundation

public struct CADConstraintAction: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let plane: CADSketchPlane
    public let relation: CADConstraintRelation
    public let first: CADConstraintGeometry
    public let second: CADConstraintGeometry?

    public init(
        name: String,
        plane: CADSketchPlane,
        relation: CADConstraintRelation,
        first: CADConstraintGeometry,
        second: CADConstraintGeometry? = nil
    ) {
        self.name = name
        self.plane = plane
        self.relation = relation
        self.first = first
        self.second = second
    }
}
