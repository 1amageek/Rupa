import CoreGraphics
import RupaCore

/// Clips candidate geometry in world space against the half-spaces of a scalar
/// that varies affinely along it: the mounted camera's depth interval, and the
/// signed distance of the frame's active section.
///
/// A selection rectangle that dropped every triangle or edge with one vertex
/// outside the camera's near and far planes would lose geometry the camera
/// plainly draws: a face crossing the near plane keeps everything in front of
/// it. Clipping first keeps that part instead of discarding the whole
/// primitive.
///
/// The clip runs in world space because camera depth is an affine function of
/// world position under both projection modes the viewport mounts, so the
/// crossing of a clip plane interpolates exactly rather than approximately.
/// Screen position is *not* affine under a perspective camera, which is why a
/// vertex this clip creates carries no projection: the caller must ask the
/// mounted frame for one.
///
/// The interval itself belongs to the frame. This owner never names a near or
/// far plane of its own; it takes the interval
/// `RealityViewport.cameraDepthInterval(revision:)` reports and the depths
/// `projectedPointWithDepth(_:revision:)` reports, so the rectangle and the
/// point path cannot disagree about where the camera stops drawing.
///
/// That interval's far bound is unbounded whenever the frame draws with the
/// perspective camera's infinite far plane. An unbounded far plane retains
/// every finite depth, so it contributes no constraint and has no crossing to
/// interpolate; this owner skips it rather than refusing the interval, because
/// refusing it would drop every candidate under the perspective camera.
///
/// A segment is clipped against every such half-space in its own parameter,
/// through `AffineScalarBound` and `ParameterInterval`, which name a bound by
/// the scalar's values at the segment's endpoints rather than by the plane that
/// produced them. This owner therefore never learns whether it is narrowing
/// against a camera or against a cut. A polygon is clipped against depth only,
/// because the near plane is the one plane a projected triangle cannot be
/// carried across.
enum ViewportCameraDepthClip {
    /// Whether this owner can clip against `interval`.
    ///
    /// A caller that holds the frame's interval asks here instead of writing
    /// its own finiteness rule, so no caller can disagree with the clip about
    /// which intervals name a camera.
    static func canClip(against interval: ClosedRange<Double>) -> Bool {
        guard interval.lowerBound.isFinite else { return false }
        return interval.upperBound.isFinite || interval.upperBound == .infinity
    }

    /// One half-space over a scalar that varies affinely along a segment.
    ///
    /// Depth is such a scalar under both cameras the viewport mounts, and so
    /// is the signed distance of a section. Naming the bound by the scalar's
    /// values instead of by the plane is what lets one narrowing rule serve
    /// both: the caller evaluates its own scalar at the two endpoints and says
    /// which side it keeps.
    struct AffineScalarBound {
        /// The scalar at parameter 0.
        let start: Double
        /// The scalar at parameter 1.
        let end: Double
        /// The value the half-space is bounded at.
        let bound: Double
        /// Whether the retained side is at or above `bound` rather than at or
        /// below it. Both are inclusive, matching the inclusive near and far
        /// admission a native hit already passes and the `>= -tolerance` a
        /// section keeps.
        let retainsValuesAtLeastBound: Bool

        init(start: Double, end: Double, bound: Double, retainsValuesAtLeastBound: Bool) {
            self.start = start
            self.end = end
            self.bound = bound
            self.retainsValuesAtLeastBound = retainsValuesAtLeastBound
        }
    }

    /// The part of a segment's `0...1` parameter that survives every bound
    /// narrowed against it.
    ///
    /// Narrowing in place is what keeps a probe allocation-free: a segment is
    /// clipped against near, far and the cut without building an array of
    /// bounds or a polygon per bound, which matters because the rectangle
    /// narrows one of these per candidate edge.
    struct ParameterInterval {
        /// The whole segment, before any bound has been narrowed against it.
        static let whole = ParameterInterval(lower: 0, upper: 1)

        private(set) var lower: Double
        private(set) var upper: Double

        /// Whether no parameter survives. An empty interval is a complete
        /// answer -- the segment lies outside the half-space -- and is not the
        /// refusal `narrow(by:)` reports.
        var isEmpty: Bool { lower > upper }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        /// Narrows by one bound, reporting whether the bound was
        /// representable.
        ///
        /// A non-finite endpoint, bound, or difference names no crossing, so
        /// this answers `false` and leaves the interval untouched rather than
        /// emptying it: the caller has to refuse such a segment instead of
        /// reporting that the half-space excluded it.
        mutating func narrow(by bound: AffineScalarBound) -> Bool {
            guard bound.start.isFinite, bound.end.isFinite, bound.bound.isFinite else {
                return false
            }
            let delta = bound.end - bound.start
            guard delta.isFinite else { return false }
            // scalar(parameter) = start + parameter * delta, so the half-space
            // is one linear constraint whose direction follows the sign of
            // `delta`. A constant scalar crosses nothing and either retains the
            // whole segment or none of it.
            guard delta != 0 else {
                let retained = bound.retainsValuesAtLeastBound
                    ? bound.start >= bound.bound
                    : bound.start <= bound.bound
                if retained == false {
                    lower = 1
                    upper = 0
                }
                return true
            }
            let crossing = (bound.bound - bound.start) / delta
            guard crossing.isFinite else { return false }
            if (delta > 0) == bound.retainsValuesAtLeastBound {
                lower = max(lower, crossing)
            } else {
                upper = min(upper, crossing)
            }
            return true
        }
    }

    /// One vertex of a candidate as it enters and leaves depth clipping.
    struct Vertex {
        /// The world position.
        let point: Point3D
        /// The mounted camera's linear view-space depth for `point`.
        let depth: Double
        /// The camera's projection of `point` where the caller already holds
        /// one. A vertex this clip created has none, so the caller projects it.
        let projected: CGPoint?

        init(point: Point3D, depth: Double, projected: CGPoint?) {
            self.point = point
            self.depth = depth
            self.projected = projected
        }
    }

    /// The part of a convex world polygon whose depth lies inside `interval`.
    ///
    /// An empty result means the camera draws none of the polygon. A polygon
    /// wholly inside the interval is returned unchanged, so a caller that
    /// already projected its vertices spends no further native call on it.
    static func clipped(_ polygon: [Vertex], to interval: ClosedRange<Double>) -> [Vertex] {
        guard polygon.count >= 3, canClip(against: interval) else { return [] }
        for vertex in polygon where !vertex.depth.isFinite {
            return []
        }
        let near = clipped(polygon, against: interval.lowerBound, retainingDepthsAbove: true)
        guard near.count >= 3 else { return [] }
        guard interval.upperBound.isFinite else { return near }
        let far = clipped(near, against: interval.upperBound, retainingDepthsAbove: false)
        return far.count >= 3 ? far : []
    }

    /// The parameter interval of a world segment whose depth lies inside
    /// `interval`, or nil when none of it does.
    ///
    /// Depth is affine along the segment, so the interval is exact and the
    /// caller recovers its endpoints by interpolating the world positions.
    ///
    /// This is the depth specialisation of `ParameterInterval`: it supplies the
    /// near and far bounds out of the frame's interval and collapses both an
    /// unrepresentable bound and an emptied interval into nil, which is the
    /// answer this signature has always given. `canClip(against:)` stays here
    /// rather than moving inward, because naming a camera is a property of a
    /// depth interval and not of an affine scalar.
    static func clippedParameterInterval(
        startDepth: Double,
        endDepth: Double,
        to interval: ClosedRange<Double>
    ) -> (lower: Double, upper: Double)? {
        guard canClip(against: interval) else { return nil }
        var parameters = ParameterInterval.whole
        guard parameters.narrow(by: AffineScalarBound(
            start: startDepth,
            end: endDepth,
            bound: interval.lowerBound,
            retainsValuesAtLeastBound: true
        )) else { return nil }
        if interval.upperBound.isFinite {
            guard parameters.narrow(by: AffineScalarBound(
                start: startDepth,
                end: endDepth,
                bound: interval.upperBound,
                retainsValuesAtLeastBound: false
            )) else { return nil }
        }
        guard parameters.isEmpty == false else { return nil }
        return (parameters.lower, parameters.upper)
    }

    /// The point at `parameter` along the world segment from `start` to `end`,
    /// or nil when it is not representable.
    ///
    /// Every world interpolation the rectangle performs goes through this one
    /// function, so the depth clip and the callers that reconstruct a clipped
    /// endpoint cannot disagree about what a parameter means.
    static func interpolated(
        _ start: Point3D,
        _ end: Point3D,
        _ parameter: Double
    ) -> Point3D? {
        guard parameter.isFinite else { return nil }
        let point = Point3D(
            x: start.x + (end.x - start.x) * parameter,
            y: start.y + (end.y - start.y) * parameter,
            z: start.z + (end.z - start.z) * parameter
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        return point
    }

    /// Sutherland–Hodgman against one depth half-space.
    private static func clipped(
        _ polygon: [Vertex],
        against bound: Double,
        retainingDepthsAbove: Bool
    ) -> [Vertex] {
        var result: [Vertex] = []
        result.reserveCapacity(polygon.count + 1)
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[(index + polygon.count - 1) % polygon.count]
            let retainsCurrent = retains(current.depth, bound: bound, above: retainingDepthsAbove)
            let retainsPrevious = retains(previous.depth, bound: bound, above: retainingDepthsAbove)
            if retainsCurrent {
                if retainsPrevious == false, let crossing = crossing(previous, current, bound: bound) {
                    result.append(crossing)
                }
                result.append(current)
            } else if retainsPrevious, let crossing = crossing(previous, current, bound: bound) {
                result.append(crossing)
            }
        }
        return result
    }

    private static func retains(_ depth: Double, bound: Double, above: Bool) -> Bool {
        above ? depth >= bound : depth <= bound
    }

    /// The crossing of a segment with one depth plane.
    ///
    /// The caller forms it only for a segment with one retained and one
    /// rejected endpoint, so the depths differ there; the guard keeps the
    /// function total rather than describing a reachable case.
    private static func crossing(_ start: Vertex, _ end: Vertex, bound: Double) -> Vertex? {
        let delta = end.depth - start.depth
        guard delta != 0, delta.isFinite else { return nil }
        let parameter = (bound - start.depth) / delta
        guard let point = interpolated(start.point, end.point, parameter) else { return nil }
        return Vertex(point: point, depth: bound, projected: nil)
    }
}
