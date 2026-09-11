import CoreGraphics
import Foundation

/// The grid a selection rectangle samples a candidate on.
///
/// A rectangle can only ask the mounted frame what it draws *at a point*, so a
/// candidate has to be reduced to points before the frame can confirm it.
/// Reducing it to one representative point makes the answer depend on which
/// triangle the tessellator emitted first, and a single point the section cut
/// away or another solid covers then loses a candidate whose remainder is
/// plainly visible inside the rectangle. This grid replaces that one point with
/// a fixed set of them.
///
/// The rectangle is divided into `divisions` cells per axis, and each cell names
/// one point of the candidate's projected coverage of that cell. The coverage is
/// the union of the fragments the candidate's triangles clip into the cell, and
/// the point is a function of that union alone: the fragments are how the union
/// arrives, never part of what it is. Independence from the tessellator follows,
/// and it is stronger than independence from emission order — the same visible
/// face drawn as two triangles and as a fine mesh presents the same union and is
/// sampled at the same points.
///
/// A cell's point is built from the cell's own middle. When the coverage
/// contains the middle, the middle is the sample. Otherwise the sample is taken
/// on the ray leaving the middle towards the coverage's nearest point, and it is
/// the middle of the first piece of coverage that ray meets. Projection onto a
/// closed convex set is unique, so each fragment has one nearest point and the
/// union's is the nearest of those; the distance to it is therefore the smallest
/// ray parameter at which the coverage is met at all. The ray meets each
/// fragment in a closed interval, and those intervals, joined wherever they
/// touch, are the parameters the coverage occupies along it. The piece holding
/// the nearest point is the first of them, and the sample is its middle. Both of
/// that piece's ends are properties of the union rather than of any one
/// fragment, so neither depends on how the union was cut. Taking a middle rather
/// than the nearest point keeps the sample off the coverage's silhouette, where
/// the frame is entitled to answer with either of the two faces meeting there.
///
/// Taking the first piece rather than the whole span from the nearest point to
/// the furthest one is what makes the sample a point the candidate occupies. A
/// coverage that is not convex — two visible strips of one face with a gap
/// between them inside one cell — has a span whose middle can fall in that gap,
/// and a query there is one the frame must refuse however much of the cell the
/// candidate covers.
///
/// Every sample lies inside its cell and therefore inside the rectangle, because
/// the fragments are clipped to the cell, the cell is convex, and every point of
/// every interval is a point of it. That is what makes the guarantee stated on
/// `MeshSourcePresentationPlanLimits.rectangleSampleGridDivisions` hold: an
/// axis-aligned visible window whose sides span at least two cells contains a
/// whole cell, whose coverage then contains its middle, so the window holds that
/// cell's sample whatever the candidate's tessellation.
///
/// The rule is sound and not complete, and what stays incomplete is the size of
/// the window it can find rather than where a sample lands. One sample per cell
/// can miss a visible sliver thinner than a cell. A sample the candidate does
/// not occupy is refused by the frame, so what is lost is a candidate and never
/// a wrong one — but no caller may read an unsampled region as invisible.
/// `RupaRendering/DESIGN.md` owns that contract.
///
/// Samples are reported from the middle of the rectangle outwards, so a
/// candidate the user dragged the rectangle across is usually confirmed by its
/// first query. That order decides only how many queries a candidate costs: a
/// candidate is admitted when any one of its samples is confirmed, so the
/// admission itself is the same for every order.
///
/// No production path reaches this grid. The region visibility raster answers
/// the selection rectangle from what the mounted frame draws at every device
/// pixel of it, so the sampling rule this grid states is reachable only from
/// its own tests and from the two sampling resolvers, which are deprecated
/// with it. RK-4.3.5.6 removes all three once the region path's replacement
/// evidence passes on the mounted path.
@available(
    *, deprecated,
    message: "The region visibility raster answers the selection rectangle. Removed with the two sampling resolvers in RK-4.3.5.6."
)
struct ViewportRectangleSampleGrid {
    /// The rectangle being sampled.
    let rect: CGRect

    /// Cells per axis.
    let divisions: Int

    /// Cell indices in query order: nearest the rectangle's middle first, ties
    /// broken by index, so the order is a function of `divisions` alone.
    let queryOrder: [Int]

    /// How close two ray intervals must come to be read as one piece.
    ///
    /// Two fragments sharing an edge cross that edge's ray at one parameter in
    /// exact arithmetic and at two parameters a rounding apart in floating
    /// point, so without a tolerance a finely tessellated face presents as a run
    /// of hairline pieces and is sampled in the first of them instead of in the
    /// whole. The grid owns it because the rounding it absorbs is a function of
    /// the coordinates the grid clips: it is `1e-6` of the rectangle's larger
    /// side, far below one device pixel for any rectangle a pointer can drag and
    /// far above the rounding of a crossing parameter computed at that
    /// magnitude. `RupaRendering/DESIGN.md` owns the rule and names the two
    /// tests that hold its failure directions.
    let joinTolerance: Double

    /// How many pieces of coverage one cell's ray tracks.
    ///
    /// A ray crossing more keeps the earliest of them. The piece holding the
    /// nearest point has the smallest start by construction, so it is never the
    /// one dropped: a cell past this bound still samples a point the candidate
    /// occupies, and what it loses is only the guarantee that the piece it
    /// reports is the same for every tessellation of the same coverage. The
    /// bound belongs here rather than to the plan's limits because it bounds
    /// this sampling rule's own working set and not a count of native queries.
    static let maximumRayComponentsPerCell = 64

    init(
        rect: CGRect,
        divisions: Int = MeshSourcePresentationPlanLimits.rectangleSampleGridDivisions
    ) {
        let divisions = max(1, divisions)
        self.rect = rect
        self.divisions = divisions
        let extent = max(abs(Double(rect.width)), abs(Double(rect.height)))
        self.joinTolerance = extent.isFinite ? extent * 1.0e-6 : 0.0
        let middle = Double(divisions - 1) / 2.0
        self.queryOrder = (0 ..< (divisions * divisions)).sorted { lhs, rhs in
            let left = Self.squaredOffsetFromMiddle(lhs, divisions: divisions, middle: middle)
            let right = Self.squaredOffsetFromMiddle(rhs, divisions: divisions, middle: middle)
            return left == right ? lhs < rhs : left < right
        }
    }

    var cellCount: Int { divisions * divisions }

    /// The bounds of one cell. Adjacent cells share their boundary, so the
    /// cells cover the rectangle with no gap a fragment could fall into.
    func cell(at index: Int) -> CGRect {
        let column = index % divisions
        let row = index / divisions
        let minX = bound(rect.minX, rect.width, column)
        let maxX = bound(rect.minX, rect.width, column + 1)
        let minY = bound(rect.minY, rect.height, row)
        let maxY = bound(rect.minY, rect.height, row + 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The middle of one cell, which is the point that cell's coverage is
    /// measured against and the sample it names whenever the coverage holds it.
    func middle(of index: Int) -> CGPoint {
        let cell = cell(at: index)
        return CGPoint(x: cell.midX, y: cell.midY)
    }

    /// One sample per cell the candidate covers, in the grid's query order.
    ///
    /// `coverage` is asked for the candidate's convex screen fragments at most
    /// twice and must produce the same fragments each time. The first pass
    /// anchors every cell against the union it received; the second measures,
    /// along the ray each surviving anchor names, the intervals the coverage
    /// occupies there, and is skipped when every anchored cell holds its own
    /// middle — the case for a candidate large enough to fill cells. Both passes
    /// are CPU clipping over points the caller already projected, so the second
    /// costs no projection and no native query.
    func polygonSamples(
        _ coverage: (inout PolygonSink) throws -> Void
    ) rethrows -> [CGPoint] {
        var sink = PolygonSink(grid: self)
        try coverage(&sink)
        if sink.beginIntervalPass() {
            try coverage(&sink)
        }
        return sink.samples()
    }

    /// The parameters at which the grid samples a projected segment, in query
    /// order: the midpoint of the segment's surviving interval in each cell it
    /// crosses.
    ///
    /// A segment meets a convex cell in one interval, so a cell contributes at
    /// most one sample and no ordering between fragments arises. The result is
    /// in the segment's own parameter, which the caller maps back to a world
    /// parameter under the frame's projection rule.
    func segmentSamples(from start: CGPoint, to end: CGPoint) -> [Double] {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            return []
        }
        guard let columns = axisRange(
            minimum: min(start.x, end.x), maximum: max(start.x, end.x),
            origin: rect.minX, extent: rect.width
        ), let rows = axisRange(
            minimum: min(start.y, end.y), maximum: max(start.y, end.y),
            origin: rect.minY, extent: rect.height
        ) else { return [] }
        var parameters = [Double?](repeating: nil, count: cellCount)
        for row in rows {
            for column in columns {
                let index = row * divisions + column
                guard let interval = Self.clippedParameterInterval(
                    from: start, to: end, in: cell(at: index)
                ) else { continue }
                let midpoint = (interval.lower + interval.upper) / 2.0
                guard midpoint.isFinite else { continue }
                parameters[index] = midpoint
            }
        }
        var samples: [Double] = []
        samples.reserveCapacity(parameters.count)
        for index in queryOrder {
            guard let parameter = parameters[index] else { continue }
            samples.append(parameter)
        }
        return samples
    }

    /// Accumulates the convex screen fragments of one candidate and reports one
    /// sample per cell the candidate covers.
    ///
    /// The fragments are traversed twice. The first pass anchors every covered
    /// cell against the union it received: the cell's middle when the union
    /// holds it, and otherwise the union's nearest point to that middle. The
    /// second pass collects, along the anchored ray, the closed interval each
    /// fragment occupies, and joins the intervals wherever they touch. The piece
    /// holding the anchor is then the first of them and the sample is its
    /// middle, so the sample is a point the union covers rather than a point of
    /// its silhouette or of one of its gaps. Both ends of that piece are
    /// properties of the union, so neither depends on how the union was cut into
    /// fragments.
    struct PolygonSink {
        private let grid: ViewportRectangleSampleGrid
        private var anchors: [Anchor?]
        private var pieces: [[Piece]]
        private var isMeasuringIntervals = false

        fileprivate init(grid: ViewportRectangleSampleGrid) {
            self.grid = grid
            self.anchors = [Anchor?](repeating: nil, count: grid.cellCount)
            self.pieces = []
        }

        /// Clips one convex screen polygon into every cell it meets.
        ///
        /// A polygon of fewer than three points, and a polygon a clip reduced to
        /// a point or a segment, still name a place the candidate covers, so
        /// they take part like any other fragment. A degenerate fragment can
        /// only win a cell by lying nearer that cell's middle or reaching
        /// further along its ray than every other fragment, which is the same
        /// comparison a fragment with area faces.
        mutating func admit(_ polygon: [CGPoint]) {
            guard polygon.isEmpty == false else { return }
            var minimum = polygon[0]
            var maximum = polygon[0]
            for point in polygon {
                guard point.x.isFinite, point.y.isFinite else { return }
                minimum = CGPoint(x: min(minimum.x, point.x), y: min(minimum.y, point.y))
                maximum = CGPoint(x: max(maximum.x, point.x), y: max(maximum.y, point.y))
            }
            guard let columns = grid.axisRange(
                minimum: minimum.x, maximum: maximum.x,
                origin: grid.rect.minX, extent: grid.rect.width
            ), let rows = grid.axisRange(
                minimum: minimum.y, maximum: maximum.y,
                origin: grid.rect.minY, extent: grid.rect.height
            ) else { return }
            for row in rows {
                for column in columns {
                    let index = row * grid.divisions + column
                    if isMeasuringIntervals {
                        measureInterval(polygon, at: index)
                    } else {
                        anchor(polygon, at: index)
                    }
                }
            }
        }

        /// One sample per cell the candidate covered, in the grid's query order.
        ///
        /// A cell whose coverage holds its middle names that middle. Every other
        /// cell names the middle of the first piece its ray meets, which the
        /// interval pass seeded with the anchor itself, so the list is never
        /// empty and its first entry is always the piece the anchor lies in.
        func samples() -> [CGPoint] {
            var result: [CGPoint] = []
            result.reserveCapacity(anchors.count)
            for index in grid.queryOrder {
                guard let anchor = anchors[index] else { continue }
                let middle = grid.middle(of: index)
                guard anchor.distance > 0 else {
                    result.append(middle)
                    continue
                }
                let piece = pieces[index][0]
                let parameter = (piece.lower + piece.upper) / 2.0
                result.append(
                    CGPoint(
                        x: middle.x + CGFloat(parameter * Double(anchor.direction.x)),
                        y: middle.y + CGFloat(parameter * Double(anchor.direction.y))
                    )
                )
            }
            return result
        }

        /// Fixes each anchored cell's ray and opens the interval pass, answering
        /// whether the fragments have to be traversed again.
        ///
        /// A cell whose coverage holds its middle is already answered, so a
        /// candidate that fills the cells it meets — the common case — skips the
        /// second traversal entirely. Every other cell is seeded with the
        /// degenerate interval at its anchor, so a piece holding the anchor
        /// exists before any fragment is measured and the sample is a point of
        /// the coverage even when no fragment interval survives.
        fileprivate mutating func beginIntervalPass() -> Bool {
            isMeasuringIntervals = true
            pieces = [[Piece]](repeating: [], count: anchors.count)
            var isNeeded = false
            for index in anchors.indices {
                guard var anchor = anchors[index] else { continue }
                let middle = grid.middle(of: index)
                let dx = Double(anchor.point.x - middle.x)
                let dy = Double(anchor.point.y - middle.y)
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance.isFinite, distance > 0 else {
                    // The nearest point is the middle to the last representable
                    // digit, so the cell already names its own middle.
                    anchor.distance = 0
                    anchors[index] = anchor
                    continue
                }
                anchor.distance = distance
                anchor.direction = CGPoint(x: CGFloat(dx / distance), y: CGFloat(dy / distance))
                anchors[index] = anchor
                pieces[index] = [Piece(lower: distance, upper: distance)]
                isNeeded = true
            }
            return isNeeded
        }

        private mutating func anchor(_ polygon: [CGPoint], at index: Int) {
            if let current = anchors[index], current.distanceSquared == 0 { return }
            let clipped = ViewportRectangleSampleGrid.clipped(polygon, to: grid.cell(at: index))
            guard let candidate = ViewportRectangleSampleGrid.nearest(
                to: grid.middle(of: index), in: clipped
            ) else { return }
            guard let current = anchors[index] else {
                anchors[index] = Anchor(
                    distanceSquared: candidate.distanceSquared, point: candidate.point
                )
                return
            }
            guard ViewportRectangleSampleGrid.precedes(
                candidate, (point: current.point, distanceSquared: current.distanceSquared)
            ) else { return }
            anchors[index] = Anchor(
                distanceSquared: candidate.distanceSquared, point: candidate.point
            )
        }

        private mutating func measureInterval(_ polygon: [CGPoint], at index: Int) {
            guard let anchor = anchors[index], anchor.distance > 0 else { return }
            let clipped = ViewportRectangleSampleGrid.clipped(polygon, to: grid.cell(at: index))
            guard let interval = ViewportRectangleSampleGrid.rayInterval(
                from: grid.middle(of: index), along: anchor.direction, through: clipped
            ) else { return }
            join(Piece(lower: interval.lower, upper: interval.upper), at: index)
        }

        /// Merges one fragment's interval into the cell's pieces, joining across
        /// gaps no wider than `joinTolerance` and keeping the list ordered by
        /// where each piece starts.
        ///
        /// A cell that would hold more pieces than
        /// `maximumRayComponentsPerCell` drops the ones that start furthest
        /// along the ray, never the piece the anchor lies in.
        private mutating func join(_ interval: Piece, at index: Int) {
            let tolerance = grid.joinTolerance
            let current = pieces[index]
            var lower = interval.lower
            var upper = interval.upper
            var merged: [Piece] = []
            merged.reserveCapacity(current.count + 1)
            var cursor = 0
            while cursor < current.count, current[cursor].upper + tolerance < lower {
                merged.append(current[cursor])
                cursor += 1
            }
            while cursor < current.count, current[cursor].lower <= upper + tolerance {
                lower = min(lower, current[cursor].lower)
                upper = max(upper, current[cursor].upper)
                cursor += 1
            }
            merged.append(Piece(lower: lower, upper: upper))
            while cursor < current.count {
                merged.append(current[cursor])
                cursor += 1
            }
            let bound = ViewportRectangleSampleGrid.maximumRayComponentsPerCell
            if merged.count > bound {
                merged.removeLast(merged.count - bound)
            }
            pieces[index] = merged
        }
    }

    /// One connected run of ray parameters the coverage occupies, in the
    /// distance along a cell's ray.
    fileprivate struct Piece {
        var lower: Double
        var upper: Double
    }

    /// One cell's nearest point of the candidate's coverage of it.
    ///
    /// `distanceSquared` is what the first pass compares; `distance` and
    /// `direction` are the ray the second pass measures along, and exist only
    /// once `beginIntervalPass()` has fixed them.
    fileprivate struct Anchor {
        var distanceSquared: Double
        var point: CGPoint
        var distance: Double = 0
        var direction: CGPoint = .zero
    }

    /// The point of one convex fragment nearest `target`, with its squared
    /// distance, or nil when the fragment is empty.
    ///
    /// Projection onto a closed convex set is unique, so this is a property of
    /// the fragment rather than of the order its vertices arrive in. Taking the
    /// least of these over the fragments of a union gives the union's own
    /// nearest point: every point of the union at the least distance is some
    /// fragment's projection, and every fragment's projection is a point of the
    /// union.
    static func nearest(
        to target: CGPoint, in fragment: [CGPoint]
    ) -> (point: CGPoint, distanceSquared: Double)? {
        guard fragment.isEmpty == false else { return nil }
        guard fragment.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        guard target.x.isFinite, target.y.isFinite else { return nil }
        if fragment.count == 1 {
            return (fragment[0], squaredDistance(from: target, to: fragment[0]))
        }
        if contains(target, in: fragment) { return (target, 0.0) }
        var best: (point: CGPoint, distanceSquared: Double)?
        for index in fragment.indices {
            let start = fragment[index]
            let end = fragment[(index + 1) % fragment.count]
            let candidate = nearestOnSegment(to: target, from: start, to: end)
            guard candidate.distanceSquared.isFinite else { continue }
            guard let current = best else {
                best = candidate
                continue
            }
            if precedes(candidate, current) { best = candidate }
        }
        return best
    }

    /// The closed interval of ray parameters the fragment occupies, or nil when
    /// the ray misses it. `direction` must be a unit vector, so the bounds are
    /// distances.
    ///
    /// The least and greatest crossing parameters over every edge, which need no
    /// winding and cannot double count: a ray entering or leaving a convex
    /// fragment through a vertex meets two edges at the same parameter, and an
    /// extremum is indifferent to that. The origin lies outside the union the
    /// caller measures, so every crossing is at a non-negative parameter and the
    /// least of them is where the ray enters this fragment.
    static func rayInterval(
        from origin: CGPoint, along direction: CGPoint, through fragment: [CGPoint]
    ) -> (lower: Double, upper: Double)? {
        guard fragment.isEmpty == false else { return nil }
        guard origin.x.isFinite, origin.y.isFinite else { return nil }
        let dx = Double(direction.x)
        let dy = Double(direction.y)
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return nil }
        var lower: Double?
        var upper: Double?
        func admit(_ parameter: Double) {
            guard parameter.isFinite, parameter >= 0 else { return }
            lower = min(lower ?? parameter, parameter)
            upper = max(upper ?? parameter, parameter)
        }
        for index in fragment.indices {
            let start = fragment[index]
            let end = fragment[(index + 1) % fragment.count]
            guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
                return nil
            }
            let wx = Double(start.x - origin.x)
            let wy = Double(start.y - origin.y)
            let ex = Double(end.x - start.x)
            let ey = Double(end.y - start.y)
            let denominator = dx * ey - dy * ex
            if denominator != 0 {
                let alongRay = (wx * ey - wy * ex) / denominator
                let alongEdge = (wx * dy - wy * dx) / denominator
                guard alongRay.isFinite, alongEdge.isFinite else { continue }
                guard alongEdge >= 0, alongEdge <= 1 else { continue }
                admit(alongRay)
            } else {
                // Parallel to the ray: the edge can only be met where it lies on
                // the ray's own line, and then at its endpoints.
                guard wx * dy - wy * dx == 0 else { continue }
                admit(wx * dx + wy * dy)
                admit(Double(end.x - origin.x) * dx + Double(end.y - origin.y) * dy)
            }
        }
        guard let lower, let upper else { return nil }
        return (lower, upper)
    }

    /// Whether a convex polygon of three or more points holds `target`.
    ///
    /// Every edge turns the same way towards an interior point. A polygon a clip
    /// degenerated to a segment or a point turns no way at all, and answers
    /// false so the caller measures its edges instead of reading a whole line as
    /// covered.
    private static func contains(_ target: CGPoint, in polygon: [CGPoint]) -> Bool {
        var isPositive = false
        var isNegative = false
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let cross = Double(end.x - start.x) * Double(target.y - start.y)
                - Double(end.y - start.y) * Double(target.x - start.x)
            if cross > 0 { isPositive = true }
            if cross < 0 { isNegative = true }
            if isPositive, isNegative { return false }
        }
        return isPositive != isNegative
    }

    private static func nearestOnSegment(
        to target: CGPoint, from start: CGPoint, to end: CGPoint
    ) -> (point: CGPoint, distanceSquared: Double) {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return (start, squaredDistance(from: target, to: start))
        }
        let raw = (Double(target.x - start.x) * dx + Double(target.y - start.y) * dy)
            / lengthSquared
        let parameter = min(max(raw, 0.0), 1.0)
        let point = CGPoint(
            x: CGFloat(Double(start.x) + parameter * dx),
            y: CGFloat(Double(start.y) + parameter * dy)
        )
        return (point, squaredDistance(from: target, to: point))
    }

    /// The total order a cell's anchor is the least of: nearer first, then the
    /// smaller point. Two candidates that tie on all three name the same point,
    /// so the least is well defined without an arrival order.
    private static func precedes(
        _ lhs: (point: CGPoint, distanceSquared: Double),
        _ rhs: (point: CGPoint, distanceSquared: Double)
    ) -> Bool {
        if lhs.distanceSquared != rhs.distanceSquared {
            return lhs.distanceSquared < rhs.distanceSquared
        }
        if lhs.point.x != rhs.point.x { return lhs.point.x < rhs.point.x }
        return lhs.point.y < rhs.point.y
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return dx * dx + dy * dy
    }

    /// The convex polygon `polygon` clipped against `rect`.
    ///
    /// Sutherland–Hodgman against four half-planes, so the result is convex and
    /// lies inside both. Both selection rectangles clip through this one owner,
    /// so the CAD sub-shape rectangle and the occurrence rectangle cannot
    /// disagree about what meeting a cell means.
    static func clipped(_ polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
        var polygon = polygon
        guard polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        for boundary in Boundary.allCases {
            guard polygon.isEmpty == false else { return [] }
            var clipped: [CGPoint] = []
            clipped.reserveCapacity(polygon.count + 1)
            for index in polygon.indices {
                let current = polygon[index]
                let previous = polygon[(index + polygon.count - 1) % polygon.count]
                let retainsCurrent = boundary.retains(current, in: rect)
                let retainsPrevious = boundary.retains(previous, in: rect)
                if retainsCurrent {
                    if retainsPrevious == false {
                        clipped.append(boundary.intersection(from: previous, to: current, in: rect))
                    }
                    clipped.append(current)
                } else if retainsPrevious {
                    clipped.append(boundary.intersection(from: previous, to: current, in: rect))
                }
            }
            polygon = clipped
        }
        return polygon
    }

    /// The parameter interval of a projected segment that lies inside `rect`,
    /// or nil when the segment misses it.
    ///
    /// Liang–Barsky in the segment's own screen parameter, so a segment whose
    /// two endpoints both lie outside still reports the interval it crosses.
    static func clippedParameterInterval(
        from start: CGPoint,
        to end: CGPoint,
        in rect: CGRect
    ) -> (lower: Double, upper: Double)? {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            return nil
        }
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        var lower = 0.0
        var upper = 1.0
        for (denominator, numerator) in [
            (-dx, Double(start.x - rect.minX)),
            (dx, Double(rect.maxX - start.x)),
            (-dy, Double(start.y - rect.minY)),
            (dy, Double(rect.maxY - start.y)),
        ] {
            guard denominator != 0 else {
                if numerator < 0 { return nil }
                continue
            }
            let parameter = numerator / denominator
            guard parameter.isFinite else { return nil }
            if denominator < 0 {
                if parameter > upper { return nil }
                if parameter > lower { lower = parameter }
            } else {
                if parameter < lower { return nil }
                if parameter < upper { upper = parameter }
            }
        }
        guard lower <= upper else { return nil }
        return (lower, upper)
    }

    /// The cell indices along one axis a screen extent can meet, or nil when it
    /// misses the rectangle on that axis.
    fileprivate func axisRange(
        minimum: CGFloat,
        maximum: CGFloat,
        origin: CGFloat,
        extent: CGFloat
    ) -> Range<Int>? {
        guard minimum.isFinite, maximum.isFinite, extent.isFinite, extent > 0 else { return nil }
        guard maximum >= origin, minimum <= origin + extent else { return nil }
        let scale = CGFloat(divisions) / extent
        let lower = clampedIndex((minimum - origin) * scale)
        let upper = clampedIndex((maximum - origin) * scale)
        guard lower <= upper else { return nil }
        return lower ..< (upper + 1)
    }

    private func clampedIndex(_ value: CGFloat) -> Int {
        guard value.isFinite else { return value < 0 ? 0 : divisions - 1 }
        return Int(min(max(value, 0), CGFloat(divisions - 1)))
    }

    private func bound(_ origin: CGFloat, _ extent: CGFloat, _ step: Int) -> CGFloat {
        origin + extent * CGFloat(step) / CGFloat(divisions)
    }

    private static func squaredOffsetFromMiddle(
        _ index: Int,
        divisions: Int,
        middle: Double
    ) -> Double {
        let column = Double(index % divisions) - middle
        let row = Double(index / divisions) - middle
        return column * column + row * row
    }

    private enum Boundary: CaseIterable {
        case minX
        case maxX
        case minY
        case maxY

        func retains(_ point: CGPoint, in rect: CGRect) -> Bool {
            switch self {
            case .minX: point.x >= rect.minX
            case .maxX: point.x <= rect.maxX
            case .minY: point.y >= rect.minY
            case .maxY: point.y <= rect.maxY
            }
        }

        /// The crossing of a segment with this boundary.
        ///
        /// The caller forms it only for a segment with one retained and one
        /// rejected endpoint, so the denominator below is non-zero there; the
        /// guard keeps the function total rather than describing a reachable
        /// case.
        func intersection(from start: CGPoint, to end: CGPoint, in rect: CGRect) -> CGPoint {
            switch self {
            case .minX, .maxX:
                let bound = self == .minX ? rect.minX : rect.maxX
                let dx = end.x - start.x
                guard dx != 0 else { return CGPoint(x: bound, y: start.y) }
                let parameter = (bound - start.x) / dx
                return CGPoint(x: bound, y: start.y + (end.y - start.y) * parameter)
            case .minY, .maxY:
                let bound = self == .minY ? rect.minY : rect.maxY
                let dy = end.y - start.y
                guard dy != 0 else { return CGPoint(x: start.x, y: bound) }
                let parameter = (bound - start.y) / dy
                return CGPoint(x: start.x + (end.x - start.x) * parameter, y: bound)
            }
        }
    }
}
