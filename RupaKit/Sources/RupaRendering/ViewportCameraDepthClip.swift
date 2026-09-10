import CoreGraphics
import RupaCore

/// Clips candidate geometry against the mounted camera's depth interval, in
/// world space.
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
enum ViewportCameraDepthClip {
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
        guard polygon.count >= 3 else { return [] }
        guard interval.lowerBound.isFinite, interval.upperBound.isFinite else { return [] }
        for vertex in polygon where !vertex.depth.isFinite {
            return []
        }
        let near = clipped(polygon, against: interval.lowerBound, retainingDepthsAbove: true)
        guard near.count >= 3 else { return [] }
        let far = clipped(near, against: interval.upperBound, retainingDepthsAbove: false)
        return far.count >= 3 ? far : []
    }

    /// The parameter interval of a world segment whose depth lies inside
    /// `interval`, or nil when none of it does.
    ///
    /// Depth is affine along the segment, so the interval is exact and the
    /// caller recovers its endpoints by interpolating the world positions.
    static func clippedParameterInterval(
        startDepth: Double,
        endDepth: Double,
        to interval: ClosedRange<Double>
    ) -> (lower: Double, upper: Double)? {
        guard startDepth.isFinite, endDepth.isFinite,
              interval.lowerBound.isFinite, interval.upperBound.isFinite else {
            return nil
        }
        var lower = 0.0
        var upper = 1.0
        let delta = endDepth - startDepth
        guard delta.isFinite else { return nil }
        // depth(parameter) = startDepth + parameter * delta, so each plane is
        // one linear constraint whose direction follows the sign of `delta`.
        for (bound, retainsAbove) in [(interval.lowerBound, true), (interval.upperBound, false)] {
            guard delta != 0 else {
                let retained = retainsAbove ? startDepth >= bound : startDepth <= bound
                if retained == false { return nil }
                continue
            }
            let crossing = (bound - startDepth) / delta
            guard crossing.isFinite else { return nil }
            if (delta > 0) == retainsAbove {
                lower = max(lower, crossing)
            } else {
                upper = min(upper, crossing)
            }
        }
        guard lower <= upper else { return nil }
        return (lower, upper)
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
