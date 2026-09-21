import Foundation

/// The prism an all-edge fillet rounds, measured the way the kernel's builders measure it.
///
/// `RoundedBoxFilletBuilder` rounds a corner with a spherical octant and so bounds the radius by
/// each side of the box, while `RoundedCylinderFilletBuilder` rides its rim on a torus whose
/// center circle `radius - r` must clear its own tube `r`, bounding the radius by half the
/// cylinder's own radius rather than by half its diameter. `RoundedPrismFilletBuilder` bounds a
/// straight side by the corner turn its two ends pay for and an arc by its own torus. No single
/// formula states those bounds, so every caller names the prism it holds before it validates.
enum AllEdgeFilletTarget: Equatable, Sendable {
    case box(sizes: [Double])
    /// A cylinder with no height yet: a circle profile carries a latent bevel before anything
    /// extrudes it, and only its cross-section can bound that radius.
    case cylinder(radius: Double, height: Double?)
    /// A prism whose cap is a regular polygon, bounded by the turn each corner charges its sides.
    case regularPolygon(sideLength: Double, sideCount: Int, height: Double?)
    /// A prism whose cap is two parallel sides closed by half-turn arcs of one radius.
    case stadium(capRadius: Double, height: Double?)
}

extension AllEdgeFilletTarget {
    /// Whether the kernel's all-edge fillet accepts this radius on this prism.
    func admits(_ radius: Double, tolerance: Double) -> Bool {
        switch self {
        case let .box(sizes):
            return !sizes.isEmpty && sizes.allSatisfy { $0 - 2.0 * radius > tolerance }
        case let .cylinder(sectionRadius, height):
            guard sectionRadius - 2.0 * radius > tolerance else { return false }
            return Self.admitsHeight(height, radius: radius, tolerance: tolerance)
        case let .regularPolygon(sideLength, sideCount, height):
            guard sideCount >= 3 else { return false }
            guard sideLength - 2.0 * radius * Self.halfCornerTangent(sideCount: sideCount)
                    > tolerance else { return false }
            return Self.admitsHeight(height, radius: radius, tolerance: tolerance)
        case let .stadium(capRadius, height):
            // The two straight sides meet the caps tangentially and charge the radius nothing, so
            // the cap arcs carrying their own tori are the whole of the cross-section bound.
            guard capRadius - 2.0 * radius > tolerance else { return false }
            return Self.admitsHeight(height, radius: radius, tolerance: tolerance)
        }
    }

    /// The exclusive upper bound of the radii `admits(_:tolerance:)` accepts.
    ///
    /// The bound itself is refused, so a control offers a value strictly inside it.
    func radiusBound(tolerance: Double) -> Double {
        switch self {
        case let .box(sizes):
            guard let shortest = sizes.min() else { return 0 }
            return (shortest - tolerance) / 2.0
        case let .cylinder(sectionRadius, height):
            return Self.bound((sectionRadius - tolerance) / 2.0, height: height, tolerance: tolerance)
        case let .regularPolygon(sideLength, sideCount, height):
            guard sideCount >= 3 else { return 0 }
            let crossSection = (sideLength - tolerance)
                / (2.0 * Self.halfCornerTangent(sideCount: sideCount))
            return Self.bound(crossSection, height: height, tolerance: tolerance)
        case let .stadium(capRadius, height):
            return Self.bound((capRadius - tolerance) / 2.0, height: height, tolerance: tolerance)
        }
    }

    /// The tangent of half the turn a regular polygon takes at one corner.
    ///
    /// At four sides the turn is a right angle and this is one, which reduces the polygon bound to
    /// the box bound the kernel applies to the same square prism.
    private static func halfCornerTangent(sideCount: Int) -> Double {
        tan(.pi / Double(sideCount))
    }

    private static func admitsHeight(_ height: Double?, radius: Double, tolerance: Double) -> Bool {
        guard let height else { return true }
        return height - 2.0 * radius > tolerance
    }

    private static func bound(_ crossSection: Double, height: Double?, tolerance: Double) -> Double {
        guard let height else { return crossSection }
        return min(crossSection, (height - tolerance) / 2.0)
    }
}
