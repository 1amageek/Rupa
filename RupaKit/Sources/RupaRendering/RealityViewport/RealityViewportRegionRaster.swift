import CoreGraphics
import RupaGeometry
import simd

/// One mounted frame's device-pixel visibility, rebuilt from the plan that
/// frame drew.
///
/// A selection rectangle is a region, not a set of sample points, so this
/// answers what the frame draws at *every* device pixel it covers rather than
/// at a grid of probes. The rule it reproduces is the one the point query
/// already obeys — same projection, same near clip, same section half-space,
/// same back-face sign, same inclusive depth interval — so the per-pixel
/// answer here and `surfaceHit` at that pixel name the same triangle.
///
/// `RealityViewport/DESIGN.md` owns that equality, the frame key this raster
/// is cached under, and the admission below. The two region ceilings belong to
/// `MeshSourcePresentationPlanLimits`.
///
/// Nothing here touches RealityKit or the main actor: the frame value carries
/// every camera term, so the whole rule is exercisable without a display.
final class RealityViewportRegionRaster {
    /// Device pixels per side of one lazily rasterized tile. A tile's depth
    /// buffer is scratch that never outlives the tile, so this size is what
    /// bounds that scratch rather than the viewport.
    static let tileExtent = 256

    private let frame: RealityViewportRegionFrame
    private let plan: MeshSourcePresentationRenderPlan
    private let triangles: [RealityViewportProjectedTriangle]
    private let tileColumns: Int
    private let tileRows: Int
    /// Start offset of each tile's run in `binEntries`, with a final total.
    private let binStart: [Int]
    /// Projected-triangle indices, grouped by tile and ascending within one
    /// tile, which is what makes a depth tie resolve in the plan's own order.
    private let binEntries: [Int32]
    /// The projected triangle each device pixel draws, or -1 for none. Only
    /// the pixels of a rasterized tile are meaningful.
    private var identity: [Int32]
    private var tileRasterized: [Bool]
    /// One tile's depths, allocated on first use and reused by every tile.
    private var depthScratch: [Double] = []
    /// One bit per projected triangle, used to de-duplicate a rectangle's
    /// pixels into an ascending emission. Always all-zero between queries.
    private var visit: [UInt64]

    /// How many tiles have been rasterized so far.
    ///
    /// A region query must not pay for pixels outside the rectangle it was
    /// asked about, which is a correctness contract rather than a tuning
    /// choice, so it needs to be observable. Nothing on the query path reads
    /// this.
    var rasterizedTileCount: Int {
        tileRasterized.reduce(into: 0) { $0 += $1 ? 1 : 0 }
    }

    /// One vertex while it is being clipped: camera-local position plus the
    /// section's signed distance, which is affine in this space and therefore
    /// exact to interpolate along a clip edge.
    private struct ClipVertex {
        var x: Double
        var y: Double
        var z: Double
        var section: Double
    }

    /// Projects and bins the whole plan against `frame`, then charges the
    /// result. Throws `.resourceExhausted` when either region ceiling is
    /// exceeded, so a refused frame answers no rectangle rather than part of
    /// one, and `.failed` when the frame's own projection produces a value it
    /// cannot describe.
    init(
        frame: RealityViewportRegionFrame,
        plan: MeshSourcePresentationRenderPlan
    ) throws {
        self.frame = frame
        self.plan = plan
        let projected = try Self.project(plan: plan, frame: frame)
        triangles = projected
        tileColumns = Self.tileCount(covering: frame.pixelWidth)
        tileRows = Self.tileCount(covering: frame.pixelHeight)
        let binning = try Self.bin(
            projected, frame: frame,
            tileColumns: tileColumns, tileRows: tileRows
        )
        binStart = binning.start
        binEntries = binning.entries
        identity = [Int32](
            repeating: -1,
            count: frame.pixelWidth * frame.pixelHeight
        )
        tileRasterized = [Bool](
            repeating: false, count: tileColumns * tileRows
        )
        visit = [UInt64](repeating: 0, count: (projected.count + 63) / 64)
    }

    // MARK: - Build

    private static func tileCount(covering pixels: Int) -> Int {
        guard pixels > 0 else { return 0 }
        return (pixels + tileExtent - 1) / tileExtent
    }

    /// Every triangle the frame draws, back-face culled, near clipped and
    /// projected, in the plan's own order.
    private static func project(
        plan: MeshSourcePresentationRenderPlan,
        frame: RealityViewportRegionFrame
    ) throws -> [RealityViewportProjectedTriangle] {
        var result: [RealityViewportProjectedTriangle] = []
        // A perspective near clip splits at most one triangle into two; an
        // orthographic frame never splits one.
        result.reserveCapacity(
            frame.usesPerspectiveProjection
                ? 2 * plan.triangleCount : plan.triangleCount
        )
        var vertices: [ClipVertex] = []
        var polygon = [ClipVertex](
            repeating: ClipVertex(x: 0, y: 0, z: 0, section: 0), count: 4
        )
        for (occurrenceIndex, occurrence) in plan.occurrences.enumerated() {
            try fill(&vertices, from: occurrence.positions, frame: frame)
            for triangleIndex in 0..<occurrence.triangleCount {
                let base = triangleIndex * 3
                let first = Int(occurrence.vertexIndices[base])
                let second = Int(occurrence.vertexIndices[base + 1])
                let third = Int(occurrence.vertexIndices[base + 2])
                guard !culls(
                    occurrence.positions[first],
                    occurrence.positions[second],
                    occurrence.positions[third],
                    frame: frame
                ) else { continue }
                let count = clip(
                    vertices[first], vertices[second], vertices[third],
                    into: &polygon, frame: frame
                )
                guard count >= 3 else { continue }
                for fan in 0..<(count - 2) {
                    guard let triangle = try projected(
                        polygon[0], polygon[fan + 1], polygon[fan + 2],
                        occurrenceIndex: occurrenceIndex,
                        triangleIndex: triangleIndex,
                        frame: frame
                    ) else { continue }
                    result.append(triangle)
                }
            }
        }
        return result
    }

    /// Camera-local positions and section distances for one occurrence. The
    /// storage is reused across occurrences, so the peak is one occurrence's
    /// vertex count and the whole scratch is released once the build ends.
    private static func fill(
        _ vertices: inout [ClipVertex],
        from positions: [GeometryPoint3D],
        frame: RealityViewportRegionFrame
    ) throws {
        if vertices.count < positions.count {
            vertices.append(contentsOf: repeatElement(
                ClipVertex(x: 0, y: 0, z: 0, section: 0),
                count: positions.count - vertices.count
            ))
        }
        for index in positions.indices {
            let position = positions[index]
            let scene = frame.nativeScene(
                x: position.x, y: position.y, z: position.z
            )
            guard scene.x.isFinite, scene.y.isFinite, scene.z.isFinite else {
                throw queryFailure(
                    "A plan position has no native scene representation."
                )
            }
            let local = frame.cameraLocal(scene)
            guard local.x.isFinite, local.y.isFinite, local.z.isFinite else {
                throw queryFailure(
                    "A plan position has no camera-local representation."
                )
            }
            vertices[index] = ClipVertex(
                x: local.x, y: local.y, z: local.z,
                section: frame.section.map { $0.signedDistance(to: scene) } ?? 0
            )
        }
    }

    /// The frame's own back-face rule. The triangle normal is a difference of
    /// positions, so it is the same vector in CAD world and in native scene
    /// space and only the eye needs translating.
    private static func culls(
        _ first: GeometryPoint3D,
        _ second: GeometryPoint3D,
        _ third: GeometryPoint3D,
        frame: RealityViewportRegionFrame
    ) -> Bool {
        let ab = SIMD3<Double>(
            second.x - first.x, second.y - first.y, second.z - first.z
        )
        let ac = SIMD3<Double>(
            third.x - first.x, third.y - first.y, third.z - first.z
        )
        return frame.culls(
            normal: simd_cross(ab, ac),
            firstPosition: frame.nativeScene(
                x: first.x, y: first.y, z: first.z
            )
        )
    }

    /// Clips one triangle against the perspective near plane, writing the
    /// resulting polygon into `polygon` and returning its vertex count. An
    /// orthographic frame is affine in depth and is not clipped at all; its
    /// depth bounds are enforced per fragment instead.
    private static func clip(
        _ first: ClipVertex,
        _ second: ClipVertex,
        _ third: ClipVertex,
        into polygon: inout [ClipVertex],
        frame: RealityViewportRegionFrame
    ) -> Int {
        guard frame.usesPerspectiveProjection else {
            polygon[0] = first
            polygon[1] = second
            polygon[2] = third
            return 3
        }
        let near = frame.nearDepth
        let firstInside = -first.z >= near
        let secondInside = -second.z >= near
        let thirdInside = -third.z >= near
        var count = 0
        if firstInside {
            polygon[count] = first
            count += 1
        }
        if firstInside != secondInside {
            polygon[count] = crossing(from: first, to: second, near: near)
            count += 1
        }
        if secondInside {
            polygon[count] = second
            count += 1
        }
        if secondInside != thirdInside {
            polygon[count] = crossing(from: second, to: third, near: near)
            count += 1
        }
        if thirdInside {
            polygon[count] = third
            count += 1
        }
        if thirdInside != firstInside {
            polygon[count] = crossing(from: third, to: first, near: near)
            count += 1
        }
        return count
    }

    /// The point where an edge meets the near plane. Depth is assigned rather
    /// than interpolated, because a rounded interpolation can land just under
    /// the plane and the inclusive fragment test would then reject the whole
    /// clip edge.
    private static func crossing(
        from start: ClipVertex, to end: ClipVertex, near: Double
    ) -> ClipVertex {
        let startDepth = -start.z
        let endDepth = -end.z
        let span = startDepth - endDepth
        let fraction = span == 0 ? 0 : (startDepth - near) / span
        return ClipVertex(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: -near,
            section: start.section + (end.section - start.section) * fraction
        )
    }

    /// One projected triangle, or `nil` when it is degenerate or covers no
    /// device pixel centre. Dropping those is not a discard of drawn geometry:
    /// a zero-area triangle and one whose bounding box holds no pixel centre
    /// both draw nothing this raster can be asked about.
    private static func projected(
        _ first: ClipVertex,
        _ second: ClipVertex,
        _ third: ClipVertex,
        occurrenceIndex: Int,
        triangleIndex: Int,
        frame: RealityViewportRegionFrame
    ) throws -> RealityViewportProjectedTriangle? {
        guard let a = frame.projected(SIMD3<Double>(first.x, first.y, first.z)),
              let b = frame.projected(
                  SIMD3<Double>(second.x, second.y, second.z)
              ),
              let c = frame.projected(SIMD3<Double>(third.x, third.y, third.z))
        else {
            throw queryFailure("""
                The mounted frame projects a drawn triangle to no finite \
                device pixel.
                """)
        }
        let doubledArea = (b.x - a.x) * (c.y - a.y)
            - (b.y - a.y) * (c.x - a.x)
        guard doubledArea.isFinite else {
            throw queryFailure(
                "The mounted frame projects a drawn triangle to no finite area."
            )
        }
        guard doubledArea != 0 else { return nil }
        let perspective = frame.usesPerspectiveProjection
        let depths = SIMD3<Double>(-first.z, -second.z, -third.z)
        let sections = SIMD3<Double>(
            first.section, second.section, third.section
        )
        let storedDepths = perspective ? 1 / depths : depths
        let storedSections = perspective ? sections / depths : sections
        let triangle = RealityViewportProjectedTriangle(
            firstX: a.x, firstY: a.y,
            secondX: b.x, secondY: b.y,
            thirdX: c.x, thirdY: c.y,
            firstDepth: storedDepths.x,
            secondDepth: storedDepths.y,
            thirdDepth: storedDepths.z,
            firstSection: storedSections.x,
            secondSection: storedSections.y,
            thirdSection: storedSections.z,
            inverseDoubledArea: 1 / doubledArea,
            occurrenceIndex: Int32(occurrenceIndex),
            triangleIndex: Int32(triangleIndex)
        )
        guard triangle.columns(clampedTo: frame.pixelWidth) != nil,
              triangle.rows(clampedTo: frame.pixelHeight) != nil else {
            return nil
        }
        return triangle
    }

    /// The one pass that both charges the frame and groups the projected
    /// triangles into tiles. Charging precedes every allocation it bounds.
    private static func bin(
        _ triangles: [RealityViewportProjectedTriangle],
        frame: RealityViewportRegionFrame,
        tileColumns: Int,
        tileRows: Int
    ) throws -> (start: [Int], entries: [Int32]) {
        let tileCount = tileColumns * tileRows
        var counts = [Int](repeating: 0, count: tileCount)
        var fragments = 0
        var entryCount = 0
        for triangle in triangles {
            guard let columns = triangle.columns(clampedTo: frame.pixelWidth),
                  let rows = triangle.rows(clampedTo: frame.pixelHeight) else {
                continue
            }
            fragments = try sum(
                fragments, try product(columns.count, rows.count)
            )
            guard fragments
                <= MeshSourcePresentationPlanLimits.maxRegionFragmentCount
            else {
                throw resourceFailure("""
                    The mounted frame projects \(fragments) region fragments, \
                    above the admitted \
                    \(MeshSourcePresentationPlanLimits.maxRegionFragmentCount).
                    """)
            }
            for row in (rows.lowerBound / tileExtent)
                ... (rows.upperBound / tileExtent) {
                for column in (columns.lowerBound / tileExtent)
                    ... (columns.upperBound / tileExtent) {
                    counts[row * tileColumns + column] += 1
                    entryCount += 1
                }
            }
        }
        let bytes = try sum(
            try sum(
                try product(
                    triangles.count,
                    MemoryLayout<RealityViewportProjectedTriangle>.stride
                ),
                try product(entryCount, MemoryLayout<Int32>.stride)
            ),
            try product(
                try product(frame.pixelWidth, frame.pixelHeight),
                MemoryLayout<Int32>.stride
            )
        )
        guard bytes
            <= MeshSourcePresentationPlanLimits.maxRegionRetainedByteCount
        else {
            throw resourceFailure("""
                The mounted frame's region raster retains \(bytes) bytes, \
                above the admitted \
                \(MeshSourcePresentationPlanLimits.maxRegionRetainedByteCount).
                """)
        }
        var start = [Int](repeating: 0, count: tileCount + 1)
        var total = 0
        for tile in 0..<tileCount {
            start[tile] = total
            total += counts[tile]
        }
        start[tileCount] = total
        var cursor = start
        var entries = [Int32](repeating: 0, count: total)
        for (index, triangle) in triangles.enumerated() {
            guard let columns = triangle.columns(clampedTo: frame.pixelWidth),
                  let rows = triangle.rows(clampedTo: frame.pixelHeight) else {
                continue
            }
            for row in (rows.lowerBound / tileExtent)
                ... (rows.upperBound / tileExtent) {
                for column in (columns.lowerBound / tileExtent)
                    ... (columns.upperBound / tileExtent) {
                    let tile = row * tileColumns + column
                    entries[cursor[tile]] = Int32(index)
                    cursor[tile] += 1
                }
            }
        }
        return (start: start, entries: entries)
    }

    // MARK: - Rasterization

    /// Builds one tile's visibility if it has not been built yet. A tile is
    /// built at most once per frame, so a drag over the same pixels pays for
    /// them once.
    private func rasterize(tile: Int) {
        guard !tileRasterized[tile] else { return }
        tileRasterized[tile] = true
        if depthScratch.isEmpty {
            depthScratch = [Double](
                repeating: .infinity,
                count: Self.tileExtent * Self.tileExtent
            )
        } else {
            for index in depthScratch.indices { depthScratch[index] = .infinity }
        }
        let originX = (tile % tileColumns) * Self.tileExtent
        let originY = (tile / tileColumns) * Self.tileExtent
        let lastX = min(originX + Self.tileExtent, frame.pixelWidth) - 1
        let lastY = min(originY + Self.tileExtent, frame.pixelHeight) - 1
        let perspective = frame.usesPerspectiveProjection
        let tolerance = frame.section?.tolerance
        for entry in binStart[tile]..<binStart[tile + 1] {
            let index = Int(binEntries[entry])
            let triangle = triangles[index]
            guard let columns = triangle.columns(clampedTo: frame.pixelWidth),
                  let rows = triangle.rows(clampedTo: frame.pixelHeight) else {
                continue
            }
            let firstX = max(columns.lowerBound, originX)
            let finalX = min(columns.upperBound, lastX)
            let firstY = max(rows.lowerBound, originY)
            let finalY = min(rows.upperBound, lastY)
            guard firstX <= finalX, firstY <= finalY else { continue }
            for row in firstY...finalY {
                let y = Double(row) + 0.5
                for column in firstX...finalX {
                    guard let weights = triangle.barycentric(
                        atX: Double(column) + 0.5, y: y
                    ) else { continue }
                    let depth = triangle.depth(
                        at: weights, perspective: perspective
                    )
                    guard frame.retainsDepth(depth) else { continue }
                    if let tolerance {
                        let distance = triangle.sectionDistance(
                            at: weights, perspective: perspective
                        )
                        guard distance >= -tolerance else { continue }
                    }
                    let scratch = (row - originY) * Self.tileExtent
                        + (column - originX)
                    // Strict, so equal depths keep the plan's own order.
                    guard depth < depthScratch[scratch] else { continue }
                    depthScratch[scratch] = depth
                    identity[row * frame.pixelWidth + column] = Int32(index)
                }
            }
        }
    }

    private func rasterizeTiles(
        columns: ClosedRange<Int>, rows: ClosedRange<Int>
    ) {
        for row in (rows.lowerBound / Self.tileExtent)
            ... (rows.upperBound / Self.tileExtent) {
            for column in (columns.lowerBound / Self.tileExtent)
                ... (columns.upperBound / Self.tileExtent) {
                rasterize(tile: row * tileColumns + column)
            }
        }
    }

    // MARK: - Queries

    /// Every distinct triangle the frame draws inside `rect`, delivered in the
    /// plan's own order.
    ///
    /// The answer is emitted rather than returned, because a hard-maximum
    /// frame can draw every triangle it holds and a caller that stops early
    /// should not have paid to materialise the rest. A triangle the near clip
    /// split is reported once.
    func forEachRegionTriangle(
        intersecting rect: CGRect,
        _ body: (MeshSourcePresentationTriangle) throws -> Void
    ) throws {
        guard let columns = devicePixels(
            from: rect.minX, to: rect.maxX, count: frame.pixelWidth
        ), let rows = devicePixels(
            from: rect.minY, to: rect.maxY, count: frame.pixelHeight
        ) else { return }
        rasterizeTiles(columns: columns, rows: rows)
        var lowestWord = Int.max
        var highestWord = Int.min
        // Cleared here rather than after the emission so a caller that throws
        // out of `body` still leaves the bitset all-zero for the next query.
        defer {
            if lowestWord <= highestWord {
                for word in lowestWord...highestWord { visit[word] = 0 }
            }
        }
        for row in rows {
            let offset = row * frame.pixelWidth
            for column in columns {
                let index = identity[offset + column]
                guard index >= 0 else { continue }
                let word = Int(index) >> 6
                visit[word] |= 1 << UInt64(Int(index) & 63)
                lowestWord = min(lowestWord, word)
                highestWord = max(highestWord, word)
            }
        }
        guard lowestWord <= highestWord else { return }
        var previous: (occurrence: Int32, triangle: Int32)?
        for word in lowestWord...highestWord {
            var bits = visit[word]
            while bits != 0 {
                let bit = bits.trailingZeroBitCount
                bits &= bits - 1
                let triangle = triangles[word << 6 | bit]
                let source = (triangle.occurrenceIndex, triangle.triangleIndex)
                // The near clip emits a split triangle's pieces at adjacent
                // indices, so an ascending walk sees them back to back.
                guard previous.map({ $0 != source }) ?? true else { continue }
                previous = source
                try body(
                    plan.occurrences[Int(triangle.occurrenceIndex)]
                        .triangle(at: Int(triangle.triangleIndex))
                )
            }
        }
    }

    /// The triangle the frame draws at one point, with the linear view-space
    /// depth it draws it at. A nil answer is the frame drawing nothing there.
    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        let x = Double(point.x) * frame.displayScale
        let y = Double(point.y) * frame.displayScale
        guard x.isFinite, y.isFinite else {
            throw Self.queryFailure(
                "The region fragment query point is not finite."
            )
        }
        guard x >= 0, y >= 0,
              x < Double(frame.pixelWidth), y < Double(frame.pixelHeight)
        else { return nil }
        let column = Int(x.rounded(.down))
        let row = Int(y.rounded(.down))
        rasterize(
            tile: (row / Self.tileExtent) * tileColumns
                + column / Self.tileExtent
        )
        return try drawn(column: column, row: row)
    }

    /// Walks a projected segment across the device pixels it covers inside
    /// `rect` and reports the first drawn one at or after `step`.
    ///
    /// The walk's pitch is the frame's own pixel lattice, which is what makes
    /// an edge's admission independent of both zoom and tessellation. A
    /// consumer rejecting the reported pixel resumes at the next step rather
    /// than restarting.
    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        guard step >= 0 else {
            throw Self.queryFailure(
                "The region segment probe cannot resume before its first step."
            )
        }
        let scale = frame.displayScale
        let first = SIMD2<Double>(
            Double(start.x) * scale, Double(start.y) * scale
        )
        let last = SIMD2<Double>(Double(end.x) * scale, Double(end.y) * scale)
        guard first.x.isFinite, first.y.isFinite,
              last.x.isFinite, last.y.isFinite else {
            throw Self.queryFailure(
                "The region segment probe endpoints are not finite."
            )
        }
        guard let columns = devicePixels(
            from: rect.minX, to: rect.maxX, count: frame.pixelWidth
        ), let rows = devicePixels(
            from: rect.minY, to: rect.maxY, count: frame.pixelHeight
        ) else {
            return RealityViewportRegionSegmentProbe(stepCount: 0, drawn: nil)
        }
        // The walk is clipped to the pixel bounds of those ranges, not to the
        // box of their centres. A segment can cross a one-pixel-tall
        // rectangle without ever meeting its centre line, and clipping to
        // centres would collapse that crossing to a single sample while the
        // frame draws every pixel along it. Keeping the sample inside the
        // range is the clamp's job below, not the clip's.
        guard let span = Self.clipped(
            from: first, to: last,
            minimumX: Double(columns.lowerBound),
            maximumX: Double(columns.upperBound + 1),
            minimumY: Double(rows.lowerBound),
            maximumY: Double(rows.upperBound + 1)
        ) else {
            return RealityViewportRegionSegmentProbe(stepCount: 0, drawn: nil)
        }
        let head = first + (last - first) * span.lowerBound
        let tail = first + (last - first) * span.upperBound
        let extent = max(abs(tail.x - head.x), abs(tail.y - head.y))
        guard extent.isFinite else {
            throw Self.queryFailure(
                "The region segment probe spans no finite pixel extent."
            )
        }
        let stepCount = Int(extent.rounded(.down)) + 1
        for current in step..<max(stepCount, step) {
            let offset = (Double(current) + 0.5) / Double(stepCount)
            let sample = head + (tail - head) * offset
            let column = min(
                max(Int(sample.x.rounded(.down)), columns.lowerBound),
                columns.upperBound
            )
            let row = min(
                max(Int(sample.y.rounded(.down)), rows.lowerBound),
                rows.upperBound
            )
            rasterize(
                tile: (row / Self.tileExtent) * tileColumns
                    + column / Self.tileExtent
            )
            guard let hit = try drawn(column: column, row: row) else { continue }
            return RealityViewportRegionSegmentProbe(
                stepCount: stepCount,
                drawn: RealityViewportRegionSegmentProbe.Drawn(
                    step: current,
                    fraction: span.lowerBound
                        + (span.upperBound - span.lowerBound) * offset,
                    triangle: hit.triangle,
                    depth: hit.depth
                )
            )
        }
        return RealityViewportRegionSegmentProbe(
            stepCount: stepCount, drawn: nil
        )
    }

    /// What one rasterized device pixel draws. Depth is recomputed from the
    /// pixel centre rather than retained, so both point-shaped answers read
    /// the same interpolation the tile used.
    private func drawn(
        column: Int, row: Int
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        let index = identity[row * frame.pixelWidth + column]
        guard index >= 0 else { return nil }
        let triangle = triangles[Int(index)]
        guard let weights = triangle.barycentric(
            atX: Double(column) + 0.5, y: Double(row) + 0.5
        ) else {
            throw Self.queryFailure(
                "A drawn device pixel lies outside the triangle drawing it."
            )
        }
        return (
            triangle: plan.occurrences[Int(triangle.occurrenceIndex)]
                .triangle(at: Int(triangle.triangleIndex)),
            depth: triangle.depth(
                at: weights, perspective: frame.usesPerspectiveProjection
            )
        )
    }

    /// The device pixels whose centres lie in the half-open point interval
    /// `[lower, upper)`, clamped to the viewport. Half-open is what keeps two
    /// abutting rectangles from both claiming the pixel on their shared edge.
    private func devicePixels(
        from lower: CGFloat, to upper: CGFloat, count: Int
    ) -> ClosedRange<Int>? {
        let scale = frame.displayScale
        let low = Double(lower) * scale
        let high = Double(upper) * scale
        guard low.isFinite, high.isFinite, count > 0 else { return nil }
        let firstValue = (low - 0.5).rounded(.up)
        let lastValue = (high - 0.5).rounded(.up) - 1
        let limit = Double(count - 1)
        guard lastValue >= 0, firstValue <= limit else { return nil }
        let first = Int(max(firstValue, 0))
        let last = Int(min(lastValue, limit))
        guard first <= last else { return nil }
        return first...last
    }

    /// The parameter interval of a segment inside an axis-aligned box, or
    /// `nil` when it has none. This is the frame's own clip and not the
    /// sampling grid's: that one is bound to a grid pitch this path has no
    /// pitch for.
    static func clipped(
        from start: SIMD2<Double>,
        to end: SIMD2<Double>,
        minimumX: Double,
        maximumX: Double,
        minimumY: Double,
        maximumY: Double
    ) -> ClosedRange<Double>? {
        var lower = 0.0
        var upper = 1.0
        let delta = end - start
        func narrow(direction: Double, distance: Double) -> Bool {
            if direction == 0 { return distance >= 0 }
            let parameter = distance / direction
            if direction < 0 {
                guard parameter <= upper else { return false }
                lower = max(lower, parameter)
            } else {
                guard parameter >= lower else { return false }
                upper = min(upper, parameter)
            }
            return true
        }
        guard narrow(direction: -delta.x, distance: start.x - minimumX),
              narrow(direction: delta.x, distance: maximumX - start.x),
              narrow(direction: -delta.y, distance: start.y - minimumY),
              narrow(direction: delta.y, distance: maximumY - start.y),
              lower <= upper else { return nil }
        return lower...upper
    }

    // MARK: - Arithmetic and failures

    private static func sum(_ first: Int, _ second: Int) throws -> Int {
        let result = first.addingReportingOverflow(second)
        guard !result.overflow else {
            throw resourceFailure("A region raster charge overflowed.")
        }
        return result.partialValue
    }

    private static func product(_ first: Int, _ second: Int) throws -> Int {
        let result = first.multipliedReportingOverflow(by: second)
        guard !result.overflow else {
            throw resourceFailure("A region raster charge overflowed.")
        }
        return result.partialValue
    }

    private static func resourceFailure(
        _ message: String
    ) -> MeshSourcePresentationRenderError {
        .init(code: .resourceExhausted, message: message)
    }

    private static func queryFailure(
        _ message: String
    ) -> MeshSourcePresentationRenderError {
        .init(code: .failed, message: message)
    }
}
