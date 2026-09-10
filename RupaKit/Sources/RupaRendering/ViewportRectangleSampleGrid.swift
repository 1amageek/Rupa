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
/// The rectangle is divided into `divisions` cells per axis. A candidate's
/// projected geometry is clipped into every cell it meets, and each cell keeps
/// the largest fragment it received, ordered by that fragment's area and then
/// by its own sample point. The order is total, so a cell's sample is a maximum
/// and not a first arrival: it is a function of the fragment set alone and not
/// of the order the fragments arrived in.
///
/// A fragment's sample is the mean of its vertices. A fragment is convex — it
/// is a convex polygon clipped against a cell's four half-planes — so the mean
/// lies inside the fragment, inside the cell, and therefore inside the
/// rectangle. That is what makes the guarantee stated on
/// `MeshSourcePresentationPlanLimits.rectangleSampleGridDivisions` hold: an
/// axis-aligned visible window whose sides span at least two cells contains a
/// whole cell, and that cell's sample lies inside the window whatever the
/// candidate's tessellation.
///
/// Samples are reported from the middle of the rectangle outwards, so a
/// candidate the user dragged the rectangle across is usually confirmed by its
/// first query. That order decides only how many queries a candidate costs: a
/// candidate is admitted when any one of its samples is confirmed, so the
/// admission itself is the same for every order.
struct ViewportRectangleSampleGrid {
    /// The rectangle being sampled.
    let rect: CGRect

    /// Cells per axis.
    let divisions: Int

    /// Cell indices in query order: nearest the rectangle's middle first, ties
    /// broken by index, so the order is a function of `divisions` alone.
    let queryOrder: [Int]

    init(
        rect: CGRect,
        divisions: Int = MeshSourcePresentationPlanLimits.rectangleSampleGridDivisions
    ) {
        let divisions = max(1, divisions)
        self.rect = rect
        self.divisions = divisions
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

    /// An accumulator over the fragments of one candidate.
    func polygonSampler() -> PolygonSampler {
        PolygonSampler(grid: self)
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
    /// sample per cell that received any.
    struct PolygonSampler {
        private let grid: ViewportRectangleSampleGrid
        private var best: [Fragment?]

        fileprivate init(grid: ViewportRectangleSampleGrid) {
            self.grid = grid
            self.best = [Fragment?](repeating: nil, count: grid.cellCount)
        }

        /// Clips one convex screen polygon into every cell it meets.
        ///
        /// A polygon of fewer than three points, and a polygon a clip reduced
        /// to a point or a segment, still name a place the candidate covers, so
        /// they contribute a zero-area fragment. Any fragment with area beats
        /// them, which is what keeps a degenerate touch from displacing a real
        /// overlap.
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
                    let clipped = ViewportRectangleSampleGrid.clipped(
                        polygon, to: grid.cell(at: index)
                    )
                    guard let fragment = Fragment(clipped) else { continue }
                    guard let current = best[index] else {
                        best[index] = fragment
                        continue
                    }
                    if fragment.precedes(current) {
                        best[index] = fragment
                    }
                }
            }
        }

        /// One sample per cell that received a fragment, in the grid's query
        /// order.
        func samples() -> [CGPoint] {
            var result: [CGPoint] = []
            result.reserveCapacity(best.count)
            for index in grid.queryOrder {
                guard let fragment = best[index] else { continue }
                result.append(fragment.point)
            }
            return result
        }

        private struct Fragment {
            let area: Double
            let point: CGPoint

            init?(_ polygon: [CGPoint]) {
                guard polygon.isEmpty == false else { return nil }
                var sumX = 0.0
                var sumY = 0.0
                for point in polygon {
                    sumX += Double(point.x)
                    sumY += Double(point.y)
                }
                let count = Double(polygon.count)
                let point = CGPoint(x: CGFloat(sumX / count), y: CGFloat(sumY / count))
                guard point.x.isFinite, point.y.isFinite else { return nil }
                var twiceArea = 0.0
                for index in polygon.indices {
                    let current = polygon[index]
                    let next = polygon[(index + 1) % polygon.count]
                    twiceArea += Double(current.x) * Double(next.y)
                        - Double(next.x) * Double(current.y)
                }
                let area = abs(twiceArea) / 2.0
                guard area.isFinite else { return nil }
                self.area = area
                self.point = point
            }

            /// The total order a cell's sample is the maximum of: larger area
            /// first, then the smaller sample point. Two fragments that tie on
            /// all three name the same point, so the maximum is well defined
            /// without an arrival order.
            func precedes(_ other: Fragment) -> Bool {
                if area != other.area { return area > other.area }
                if point.x != other.point.x { return point.x < other.point.x }
                return point.y < other.point.y
            }
        }
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
