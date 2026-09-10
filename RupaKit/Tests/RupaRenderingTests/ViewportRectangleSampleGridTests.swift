import CoreGraphics
import Testing
@testable import RupaRendering

// MARK: - Fixtures

/// The rectangle these tests sample. At four cells per axis its cells are 25
/// screen points wide, so every coordinate below is exact in binary and the
/// expectations state places rather than tolerances.
private let gridRect = CGRect(x: 0, y: 0, width: 100, height: 100)

private func makeGrid(_ rect: CGRect = gridRect) -> ViewportRectangleSampleGrid {
    ViewportRectangleSampleGrid(rect: rect)
}

private func corners(of rect: CGRect) -> [CGPoint] {
    [
        CGPoint(x: rect.minX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.maxY),
        CGPoint(x: rect.minX, y: rect.maxY),
    ]
}

private func samples(
    of polygons: [[CGPoint]],
    on grid: ViewportRectangleSampleGrid
) -> [CGPoint] {
    grid.polygonSamples { sink in
        for polygon in polygons {
            sink.admit(polygon)
        }
    }
}

/// Two sample lists name the same points.
///
/// Compared to a tolerance rather than exactly: two tessellations of one shape
/// reach the same nearest point and the same chord end through different
/// clipped fragments, so their last binary digits need not agree.
private func expectSamplesMatch(
    _ result: [CGPoint],
    _ expected: [CGPoint],
    _ subject: Comment
) {
    #expect(result.count == expected.count, subject)
    for (point, other) in zip(result, expected) {
        #expect(abs(point.x - other.x) < 0.000001, subject)
        #expect(abs(point.y - other.y) < 0.000001, subject)
    }
}

/// Convex screen polygons that overlap each other, so several of them reach the
/// same cell and the cell has to choose between them.
private let overlappingPolygons: [[CGPoint]] = [
    [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)],
    [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)],
    [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20), CGPoint(x: 80, y: 80), CGPoint(x: 20, y: 80)],
    [CGPoint(x: 45, y: -10), CGPoint(x: 55, y: -10), CGPoint(x: 55, y: 110), CGPoint(x: 45, y: 110)],
    [CGPoint(x: -20, y: 40), CGPoint(x: 120, y: 40), CGPoint(x: 120, y: 60), CGPoint(x: -20, y: 60)],
    [CGPoint(x: 90, y: 90), CGPoint(x: 110, y: 90), CGPoint(x: 110, y: 110), CGPoint(x: 90, y: 110)],
]

/// `rect` divided into `rows` by `columns` axis-aligned tiles.
private func tiles(of rect: CGRect, rows: Int, columns: Int) -> [CGRect] {
    var result: [CGRect] = []
    result.reserveCapacity(rows * columns)
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            let minX = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
            let maxX = rect.minX + rect.width * CGFloat(column + 1) / CGFloat(columns)
            let minY = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
            let maxY = rect.minY + rect.height * CGFloat(row + 1) / CGFloat(rows)
            result.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
    }
    return result
}

/// One way of tessellating a window: axis-aligned tiles.
private func tiledPolygons(of rect: CGRect, rows: Int, columns: Int) -> [[CGPoint]] {
    tiles(of: rect, rows: rows, columns: columns).map(corners(of:))
}

/// Another way of tessellating the same window: two triangles per tile.
private func triangulatedPolygons(of rect: CGRect, rows: Int, columns: Int) -> [[CGPoint]] {
    var result: [[CGPoint]] = []
    for tile in tiles(of: rect, rows: rows, columns: columns) {
        let tileCorners = corners(of: tile)
        result.append([tileCorners[0], tileCorners[1], tileCorners[2]])
        result.append([tileCorners[0], tileCorners[2], tileCorners[3]])
    }
    return result
}

/// The same rectangle presented at several densities: whole, tiled, and cut
/// into triangles. Every entry is the same shape, so what the grid answers must
/// not distinguish them.
private func tessellations(of rect: CGRect) -> [[[CGPoint]]] {
    var result: [[[CGPoint]]] = [[corners(of: rect)]]
    for (rows, columns) in [(1, 2), (2, 3), (3, 2), (5, 5), (7, 1)] {
        result.append(tiledPolygons(of: rect, rows: rows, columns: columns))
        result.append(triangulatedPolygons(of: rect, rows: rows, columns: columns))
    }
    return result
}

/// Windows wider and taller than two cells, so each one wholly contains a cell.
/// The last is deliberately off the cell boundaries.
private let widerThanTwoCellWindows: [CGRect] = [
    CGRect(x: 50, y: 0, width: 50, height: 100),
    CGRect(x: 0, y: 0, width: 100, height: 50),
    CGRect(x: 50, y: 50, width: 50, height: 50),
    CGRect(x: 25, y: 25, width: 50, height: 50),
    CGRect(x: 13, y: 41, width: 57, height: 52),
]

// MARK: - Tests

@Suite struct ViewportRectangleSampleGridTests {
    /// A cell's sample is built from the union of the fragments it received,
    /// through extrema over that union rather than a first or a last arrival,
    /// so the same candidate answers the same rectangle whatever order its
    /// triangles are stored in.
    @Test(.timeLimit(.minutes(1)))
    func gridReportsTheSameSamplesWhateverOrderFragmentsArriveIn() throws {
        let grid = makeGrid()
        let expected = samples(of: overlappingPolygons, on: grid)
        #expect(expected.isEmpty == false)

        for shift in 0 ..< overlappingPolygons.count {
            let rotated = (0 ..< overlappingPolygons.count).map { index in
                overlappingPolygons[(index + shift) % overlappingPolygons.count]
            }
            #expect(samples(of: rotated, on: grid) == expected)
            #expect(samples(of: rotated.reversed(), on: grid) == expected)
        }
    }

    /// A cell whose coverage holds its middle is sampled at that middle, even
    /// when the coverage arrives as fragments none of which is centred there.
    /// Neither fragment's own shape nor its area takes part in the answer.
    @Test(.timeLimit(.minutes(1)))
    func gridSamplesTheCellMiddleWhenTheCoverageHoldsIt() throws {
        let grid = makeGrid(CGRect(x: 0, y: 0, width: 40, height: 40))
        // Both stand wholly inside the cell `x, y` in 10...20 and meet along
        // `x == 15`, so their union holds that cell's middle `(15, 15)` while
        // neither of them is centred on it.
        let left = [
            CGPoint(x: 11, y: 11), CGPoint(x: 15, y: 11),
            CGPoint(x: 15, y: 19), CGPoint(x: 11, y: 19),
        ]
        let right = [
            CGPoint(x: 15, y: 11), CGPoint(x: 19, y: 11),
            CGPoint(x: 19, y: 19), CGPoint(x: 15, y: 19),
        ]

        #expect(samples(of: [left, right], on: grid) == [CGPoint(x: 15, y: 15)])
        #expect(samples(of: [right, left], on: grid) == [CGPoint(x: 15, y: 15)])
    }

    /// A cell whose coverage misses its middle is sampled at the middle of the
    /// chord the coverage cuts on the ray towards its nearest point, so the
    /// sample stands inside the coverage and off its silhouette.
    ///
    /// The square `2...8` by `2...8` lies wholly inside the first cell, whose
    /// middle `(12.5, 12.5)` it does not contain. Its nearest point to that
    /// middle is the corner `(8, 8)`, the ray leaves the square at `(2, 2)`,
    /// and the chord's middle is `(5, 5)` — the square's own centre, which no
    /// single fragment of it needs to be centred on.
    @Test(.timeLimit(.minutes(1)))
    func gridSamplesTheChordMiddleWhenTheCoverageMissesTheCellMiddle() throws {
        let grid = makeGrid()
        let coverage = CGRect(x: 2, y: 2, width: 6, height: 6)
        for tessellation in tessellations(of: coverage) {
            expectSamplesMatch(
                samples(of: tessellation, on: grid),
                [CGPoint(x: 5, y: 5)],
                "chord middle"
            )
        }
    }

    /// The rule reads the union of a candidate's fragments and never the
    /// fragments themselves, so one shape answers alike however finely it was
    /// cut up — including shapes narrower than a cell, which no cell middle
    /// falls inside.
    ///
    /// Independence from the order fragments arrive in is a weaker property
    /// than this one: it holds for any rule that is a function of the fragment
    /// set, including rules that read a fragment's own shape.
    @Test(.timeLimit(.minutes(1)))
    func gridReportsTheSameSamplesHoweverTheUnionWasCutIntoFragments() throws {
        let grid = makeGrid()
        let shapes = widerThanTwoCellWindows + [
            CGRect(x: 0, y: 0, width: 5, height: 100),
            CGRect(x: 47, y: 3, width: 6, height: 94),
            CGRect(x: 2, y: 2, width: 6, height: 6),
        ]
        for shape in shapes {
            let cut = tessellations(of: shape)
            let expected = try #require(cut.first.map { samples(of: $0, on: grid) })
            #expect(expected.isEmpty == false)
            for tessellation in cut.dropFirst() {
                expectSamplesMatch(
                    samples(of: tessellation, on: grid),
                    expected,
                    Comment(rawValue: "\(shape)")
                )
            }
        }
    }

    /// The covering guarantee: a window the candidate is visible in, wider and
    /// taller than two cells, always receives a sample strictly inside it, and
    /// never a sample outside it — however the window's own geometry was
    /// tessellated before it was admitted.
    @Test(.timeLimit(.minutes(1)))
    func gridSamplesInsideEveryWindowWiderThanTwoCells() throws {
        let grid = makeGrid()
        for window in widerThanTwoCellWindows {
            var tessellations: [[[CGPoint]]] = [[corners(of: window)]]
            for (rows, columns) in [(2, 3), (3, 2), (5, 5)] {
                tessellations.append(tiledPolygons(of: window, rows: rows, columns: columns))
                tessellations.append(
                    triangulatedPolygons(of: window, rows: rows, columns: columns)
                )
            }
            for tessellation in tessellations {
                let result = samples(of: tessellation, on: grid)
                #expect(result.isEmpty == false)
                let outer = window.insetBy(dx: -0.001, dy: -0.001)
                for sample in result {
                    #expect(outer.contains(sample))
                    #expect(gridRect.insetBy(dx: -0.001, dy: -0.001).contains(sample))
                }
                let inner = window.insetBy(dx: 0.001, dy: 0.001)
                #expect(result.contains { inner.contains($0) })
            }
        }
    }

    /// A candidate covering the whole rectangle is sampled once per cell, at
    /// each cell's own middle, and the cells are reported from the middle of
    /// the rectangle outwards. The order decides only how many queries a
    /// candidate costs, never which candidates are admitted.
    @Test(.timeLimit(.minutes(1)))
    func gridSamplesOneCellMiddleEachFromTheRectangleMiddleOutwards() throws {
        let grid = makeGrid()
        try #require(grid.divisions == 4)
        #expect(grid.divisions == MeshSourcePresentationPlanLimits.rectangleSampleGridDivisions)
        #expect(grid.queryOrder.count == grid.cellCount)
        #expect(Set(grid.queryOrder).count == grid.cellCount)
        #expect(Array(grid.queryOrder.prefix(4)) == [5, 6, 9, 10])

        let expected = grid.queryOrder.map { index -> CGPoint in
            let cell = grid.cell(at: index)
            return CGPoint(x: cell.midX, y: cell.midY)
        }

        #expect(samples(of: [corners(of: gridRect)], on: grid) == expected)
    }

    /// A projected segment is sampled once in each cell it crosses, at the
    /// middle of the interval it spends there, and a segment that misses the
    /// rectangle is sampled nowhere. Both endpoints may stand outside the
    /// rectangle and the crossing is still found.
    @Test(.timeLimit(.minutes(1)))
    func gridSamplesASegmentOnceInEachCellItCrosses() throws {
        let grid = makeGrid()
        let start = CGPoint(x: -20, y: 60)
        let end = CGPoint(x: 120, y: 60)

        let parameters = grid.segmentSamples(from: start, to: end)
        let points = parameters.map { start.x + CGFloat($0) * (end.x - start.x) }

        // The segment crosses the third row of cells, so the four samples are
        // the middles of that row's cells, in the grid's query order.
        #expect(points.count == 4)
        for (point, expected) in zip(points, [37.5, 62.5, 12.5, 87.5] as [CGFloat]) {
            #expect(abs(point - expected) < 0.0001)
        }

        #expect(
            grid.segmentSamples(
                from: CGPoint(x: -20, y: 200), to: CGPoint(x: 120, y: 200)
            ).isEmpty
        )
    }
}
