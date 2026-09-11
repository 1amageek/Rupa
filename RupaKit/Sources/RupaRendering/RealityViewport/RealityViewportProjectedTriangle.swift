import simd

/// One triangle of a mounted frame after projection, back-face culling and,
/// for a perspective frame, the near clip.
///
/// The layout is the retained cost the region admission charges, so it is
/// fixed rather than incidental: thirteen `Double` values and two `Int32`
/// indices, 112 bytes of stride. `MeshSourcePresentationPlanLimits` states the
/// worst admissible projected set in bytes at that stride, and the test suite
/// asserts the stride so the two cannot drift apart.
///
/// `Double` is a correctness requirement and not a precision preference. A
/// perspective frame's near-clipped vertices project past a billion device
/// pixels, where an edge-function product reaches 1e18 and loses its sign in
/// `Float`. Discarding such a triangle instead is not open to this owner: the
/// frame draws it, so the region answer must contain it.
///
/// Depth and the section scalar are stored in the form that is linear in
/// screen space, because that is the form barycentric interpolation is exact
/// in. An orthographic frame stores each directly; a perspective frame stores
/// their reciprocal-depth forms and the fragment recovers them.
struct RealityViewportProjectedTriangle {
    var firstX: Double
    var firstY: Double
    var secondX: Double
    var secondY: Double
    var thirdX: Double
    var thirdY: Double
    /// Linear view-space depth, or its reciprocal under a perspective frame.
    var firstDepth: Double
    var secondDepth: Double
    var thirdDepth: Double
    /// The section's signed distance, divided by depth under a perspective
    /// frame. Zero throughout when the frame holds no section.
    var firstSection: Double
    var secondSection: Double
    var thirdSection: Double
    /// The signed reciprocal of twice the projected area. Multiplying the
    /// three edge functions by it yields barycentric weights whose signs no
    /// longer depend on the winding, so containment is all three at or above
    /// zero either way.
    var inverseDoubledArea: Double
    var occurrenceIndex: Int32
    var triangleIndex: Int32

    /// The barycentric weights of a device-pixel centre, or `nil` when the
    /// centre lies outside the triangle. A degenerate triangle never reaches
    /// here, because it is dropped before it is stored.
    func barycentric(atX x: Double, y: Double) -> SIMD3<Double>? {
        let first = ((thirdX - secondX) * (y - secondY)
            - (thirdY - secondY) * (x - secondX)) * inverseDoubledArea
        guard first >= 0 else { return nil }
        let second = ((firstX - thirdX) * (y - thirdY)
            - (firstY - thirdY) * (x - thirdX)) * inverseDoubledArea
        guard second >= 0 else { return nil }
        let third = ((secondX - firstX) * (y - firstY)
            - (secondY - firstY) * (x - firstX)) * inverseDoubledArea
        guard third >= 0 else { return nil }
        return SIMD3<Double>(first, second, third)
    }

    /// The linear view-space depth at a fragment.
    func depth(at weights: SIMD3<Double>, perspective: Bool) -> Double {
        let interpolated = simd_dot(
            weights, SIMD3<Double>(firstDepth, secondDepth, thirdDepth)
        )
        guard perspective else { return interpolated }
        return 1 / interpolated
    }

    /// The section's signed distance at a fragment, which the frame compares
    /// against the half-space's own tolerance rather than against zero.
    func sectionDistance(
        at weights: SIMD3<Double>, perspective: Bool
    ) -> Double {
        let interpolated = simd_dot(
            weights, SIMD3<Double>(firstSection, secondSection, thirdSection)
        )
        guard perspective else { return interpolated }
        let reciprocalDepth = simd_dot(
            weights, SIMD3<Double>(firstDepth, secondDepth, thirdDepth)
        )
        return interpolated / reciprocalDepth
    }

    /// The inclusive device-pixel columns the triangle can cover, clamped to
    /// a viewport `width` pixels wide, or `nil` when it covers none.
    func columns(clampedTo width: Int) -> ClosedRange<Int>? {
        Self.pixels(
            lower: min(firstX, min(secondX, thirdX)),
            upper: max(firstX, max(secondX, thirdX)),
            count: width
        )
    }

    /// The inclusive device-pixel rows, clamped to a viewport `height` pixels
    /// tall, or `nil` when the triangle covers none.
    func rows(clampedTo height: Int) -> ClosedRange<Int>? {
        Self.pixels(
            lower: min(firstY, min(secondY, thirdY)),
            upper: max(firstY, max(secondY, thirdY)),
            count: height
        )
    }

    /// Pixel centres sit at `index + 0.5`, so a closed coordinate span covers
    /// the indices from `ceil(lower - 0.5)` to `floor(upper - 0.5)`. The
    /// comparison happens in `Double` and is clamped before it is converted,
    /// because a near-clipped coordinate can exceed what `Int` represents.
    private static func pixels(
        lower: Double, upper: Double, count: Int
    ) -> ClosedRange<Int>? {
        guard lower.isFinite, upper.isFinite, count > 0 else { return nil }
        let limit = Double(count) - 0.5
        guard upper >= 0.5, lower <= limit else { return nil }
        let first = Int((max(lower, 0.5) - 0.5).rounded(.up))
        let last = Int((min(upper, limit) - 0.5).rounded(.down))
        guard first <= last else { return nil }
        return first...last
    }
}
