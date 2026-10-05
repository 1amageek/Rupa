import Foundation

/// Draft Face's taper method as an editor command states it, its picks as selection targets of
/// the drafted body: Isocline (the default), Curve about pivot edges lying on the drafted faces,
/// Surface against another face's outward normal, and Normal against the reference's own normal.
public enum BodyFaceDraftMethod: Codable, Equatable, Hashable, Sendable {
    case isocline
    case curve(pivots: [SelectionTarget])
    case surface(reference: SelectionTarget)
    case normal
}
