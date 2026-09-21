import Foundation

/// The cap profile family an all-edge fillet reads out of a sketch.
///
/// One recognition order answers three questions — the bound a body publishes, whether a corner
/// may be committed onto that body, and whether a profile nothing has extruded may hold a latent
/// bevel — so the order is owned here instead of being restated at each of them.
///
/// An axis-aligned square is recognized as a rectangle before the regular polygon that would also
/// describe it, which is the same choice `AllEdgeFilletBuilder` makes when it routes six planar
/// faces to its box builder. The two bounds agree at four sides, so matching earlier costs the
/// caller nothing.
enum AllEdgeFilletProfile: Equatable, Sendable {
    case circle(radius: Double)
    case rectangle(sizeX: Double, sizeY: Double, cornerRadius: Double)
    case regularPolygon(sideLength: Double, sideCount: Int)
    case stadium(capRadius: Double)
}
