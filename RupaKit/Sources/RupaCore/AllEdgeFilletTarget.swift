import Foundation

/// The prism an all-edge fillet rounds, measured the way the kernel's builders measure it.
///
/// `RoundedBoxFilletBuilder` rounds a corner with a spherical octant and so bounds the radius by
/// each side of the box, while `RoundedCylinderFilletBuilder` rides its rim on a torus whose
/// center circle `radius - r` must clear its own tube `r`, bounding the radius by half the
/// cylinder's own radius rather than by half its diameter. No single formula states both bounds,
/// so every caller names the prism it holds before it validates a radius against it.
enum AllEdgeFilletTarget: Equatable, Sendable {
    case box(sizes: [Double])
    /// A cylinder with no height yet: a circle profile carries a latent bevel before anything
    /// extrudes it, and only its cross-section can bound that radius.
    case cylinder(radius: Double, height: Double?)
}

extension AllEdgeFilletTarget {
    /// Whether the kernel's all-edge fillet accepts this radius on this prism.
    func admits(_ radius: Double, tolerance: Double) -> Bool {
        switch self {
        case let .box(sizes):
            return !sizes.isEmpty && sizes.allSatisfy { $0 - 2.0 * radius > tolerance }
        case let .cylinder(sectionRadius, height):
            guard sectionRadius - 2.0 * radius > tolerance else { return false }
            guard let height else { return true }
            return height - 2.0 * radius > tolerance
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
            let crossSection = (sectionRadius - tolerance) / 2.0
            guard let height else { return crossSection }
            return min(crossSection, (height - tolerance) / 2.0)
        }
    }
}
