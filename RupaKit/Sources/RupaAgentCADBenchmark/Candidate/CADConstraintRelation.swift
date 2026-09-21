import Foundation

public enum CADConstraintRelation: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case coincident
    case parallel
    case perpendicular
    case horizontal
    case vertical
    case equalLength
    case concentric
    case equalRadius
}
