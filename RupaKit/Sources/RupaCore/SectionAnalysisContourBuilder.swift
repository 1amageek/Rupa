import Foundation
import RupaCoreTypes
import SwiftCAD

struct SectionAnalysisContourBuilder: Sendable {
    private struct BodyOccurrence: Hashable, Sendable {
        var bodyID: String
        var sceneNodeID: SceneNodeID?
        var occurrenceID: SceneOccurrenceID?
    }

    private typealias PointKey = Int

    private struct Cell: Hashable {
        var x: Int64
        var y: Int64
    }

    private struct Endpoint {
        var point: Point3D
        var projected: Point2D
        var sourceIndex: Int
    }

    private struct UndirectedEdgeKey: Hashable, Sendable {
        var bodyID: String
        var sceneNodeID: SceneNodeID?
        var occurrenceID: SceneOccurrenceID?
        var first: PointKey
        var second: PointKey
    }

    private struct Edge: Sendable {
        var bodyID: String
        var sceneNodeID: SceneNodeID?
        var occurrenceID: SceneOccurrenceID?
        var startKey: PointKey
        var endKey: PointKey
        var start: Point3D
        var end: Point3D
        var start2D: Point2D
        var end2D: Point2D
    }

    private var tolerance: Double

    init(tolerance: Double) {
        self.tolerance = tolerance
    }

    func build(
        segments: [SectionAnalysisResult.IntersectionSegment]
    ) -> [SectionAnalysisResult.IntersectionContour] {
        let edges = uniqueEdges(from: segments)
        guard edges.isEmpty == false else {
            return []
        }

        let groupedEdges = Dictionary(grouping: edges, by: {
            BodyOccurrence(bodyID: $0.bodyID, sceneNodeID: $0.sceneNodeID, occurrenceID: $0.occurrenceID)
        })
        return groupedEdges.keys.sorted {
            if $0.bodyID != $1.bodyID { return $0.bodyID < $1.bodyID }
            return ($0.occurrenceID?.rawValue ?? $0.sceneNodeID?.description ?? "") < ($1.occurrenceID?.rawValue ?? $1.sceneNodeID?.description ?? "")
        }.flatMap { key in
            contours(
                for: groupedEdges[key] ?? [],
                bodyID: key.bodyID,
                sceneNodeID: key.sceneNodeID,
                occurrenceID: key.occurrenceID
            )
        }
    }

    private func uniqueEdges(
        from segments: [SectionAnalysisResult.IntersectionSegment]
    ) -> [Edge] {
        let groups = Dictionary(grouping: segments) {
            BodyOccurrence(bodyID: $0.bodyID, sceneNodeID: $0.sceneNodeID, occurrenceID: $0.occurrenceID)
        }
        var edges: [Edge] = []
        edges.reserveCapacity(segments.count)
        for (occurrence, segments) in groups {
            var endpoints: [Endpoint] = []
            endpoints.reserveCapacity(segments.count * 2)
            for (index, segment) in segments.enumerated() {
                endpoints.append(Endpoint(point: segment.start, projected: segment.start2D, sourceIndex: index * 2))
                endpoints.append(Endpoint(point: segment.end, projected: segment.end2D, sourceIndex: index * 2 + 1))
            }
            endpoints.sort {
                if $0.projected.x != $1.projected.x { return $0.projected.x < $1.projected.x }
                if $0.projected.y != $1.projected.y { return $0.projected.y < $1.projected.y }
                if $0.point.x != $1.point.x { return $0.point.x < $1.point.x }
                if $0.point.y != $1.point.y { return $0.point.y < $1.point.y }
                return $0.point.z < $1.point.z
            }
            guard let origin = endpoints.first?.projected else { continue }
            var representatives: [Endpoint] = []
            var cells: [Cell: [Int]] = [:]
            var unindexed: [Int] = []
            var indices = Array(repeating: 0, count: endpoints.count)
            for endpoint in endpoints {
                let cell = cell(for: endpoint.projected, origin: origin)
                var candidates = unindexed
                if let cell {
                    for dx in -1...1 {
                        for dy in -1...1 {
                            candidates.append(contentsOf: cells[Cell(x: cell.x + Int64(dx), y: cell.y + Int64(dy))] ?? [])
                        }
                    }
                } else {
                    // ponytail: unindexable or imprecise coordinate ranges use O(n²) distance search;
                    // replace with a spatial tree if such ranges become a measured workload.
                    var lower = 0, upper = representatives.count
                    while lower < upper {
                        let middle = lower + (upper - lower) / 2
                        if endpoint.projected.x - representatives[middle].projected.x > tolerance { lower = middle + 1 }
                        else { upper = middle }
                    }
                    candidates = Array(lower..<representatives.count)
                }
                if let match = candidates.filter({ distance(representatives[$0].projected, endpoint.projected) <= tolerance }).min() {
                    indices[endpoint.sourceIndex] = match
                } else {
                    let index = representatives.count
                    representatives.append(endpoint)
                    indices[endpoint.sourceIndex] = index
                    if let cell { cells[cell, default: []].append(index) }
                    else { unindexed.append(index) }
                }
            }
            var seen = Set<UndirectedEdgeKey>()
            var occurrenceEdges: [Edge] = []
            for index in segments.indices {
                let first = min(indices[index * 2], indices[index * 2 + 1])
                let second = max(indices[index * 2], indices[index * 2 + 1])
                guard first != second else { continue }
                let key = undirectedEdgeKey(bodyID: occurrence.bodyID, sceneNodeID: occurrence.sceneNodeID,
                    occurrenceID: occurrence.occurrenceID, startKey: first, endKey: second)
                guard seen.insert(key).inserted else { continue }
                let a = representatives[first], b = representatives[second]
                occurrenceEdges.append(Edge(bodyID: occurrence.bodyID, sceneNodeID: occurrence.sceneNodeID,
                    occurrenceID: occurrence.occurrenceID, startKey: first, endKey: second,
                    start: a.point, end: b.point, start2D: a.projected, end2D: b.projected))
            }
            occurrenceEdges.sort { $0.startKey != $1.startKey ? $0.startKey < $1.startKey : $0.endKey < $1.endKey }
            edges.append(contentsOf: occurrenceEdges)
        }
        return edges
    }

    private func cell(for point: Point2D, origin: Point2D) -> Cell? {
        let dx = point.x - origin.x, dy = point.y - origin.y
        // Two-tolerance cells leave room for bounded subtraction/division rounding.
        // Fall back to distance search before coordinate precision can skip a neighbor cell.
        let xCell = (dx / tolerance) / 2, yCell = (dy / tolerance) / 2
        guard dx.ulp <= tolerance / 8, dy.ulp <= tolerance / 8,
              xCell.ulp <= 0.125, yCell.ulp <= 0.125,
              let x = Int64(exactly: floor(xCell)), let y = Int64(exactly: floor(yCell)),
              x > Int64.min, x < Int64.max, y > Int64.min, y < Int64.max else { return nil }
        return Cell(x: x, y: y)
    }

    private func contours(
        for edges: [Edge],
        bodyID: String,
        sceneNodeID: SceneNodeID?,
        occurrenceID: SceneOccurrenceID?
    ) -> [SectionAnalysisResult.IntersectionContour] {
        var adjacency: [PointKey: [Int]] = [:]
        for (index, edge) in edges.enumerated() {
            adjacency[edge.startKey, default: []].append(index)
            adjacency[edge.endKey, default: []].append(index)
        }

        var usedEdges = Set<Int>()
        var contours: [SectionAnalysisResult.IntersectionContour] = []
        for index in edges.indices where usedEdges.contains(index) == false {
            let contour = traceContour(
                startIndex: index,
                edges: edges,
                adjacency: adjacency,
                usedEdges: &usedEdges,
                bodyID: bodyID,
                sceneNodeID: sceneNodeID, occurrenceID: occurrenceID,
                contourIndex: contours.count
            )
            if let contour {
                contours.append(contour)
            }
        }
        return contours
    }

    private func traceContour(
        startIndex: Int,
        edges: [Edge],
        adjacency: [PointKey: [Int]],
        usedEdges: inout Set<Int>,
        bodyID: String,
        sceneNodeID: SceneNodeID?,
        occurrenceID: SceneOccurrenceID?,
        contourIndex: Int
    ) -> SectionAnalysisResult.IntersectionContour? {
        let firstEdge = edges[startIndex]
        usedEdges.insert(startIndex)

        var startKey = firstEdge.startKey
        var currentKey = firstEdge.endKey
        var points = [firstEdge.start, firstEdge.end]
        var points2D = [firstEdge.start2D, firstEdge.end2D]
        var segmentCount = 1

        // A face may contribute the middle segment of an open chain first.
        // Trace its two ends so input triangle order cannot fragment the contour.
        for direction in 0..<2 {
            while currentKey != startKey {
                guard let nextIndex = nextUnusedEdgeIndex(
                    at: currentKey,
                    adjacency: adjacency,
                    usedEdges: usedEdges
                ) else {
                    break
                }
                let nextEdge = edges[nextIndex]
                usedEdges.insert(nextIndex)
                segmentCount += 1

                if nextEdge.startKey == currentKey {
                    append(
                        point: nextEdge.end,
                        point2D: nextEdge.end2D,
                        to: &points,
                        points2D: &points2D
                    )
                    currentKey = nextEdge.endKey
                } else {
                    append(
                        point: nextEdge.start,
                        point2D: nextEdge.start2D,
                        to: &points,
                        points2D: &points2D
                    )
                    currentKey = nextEdge.startKey
                }
            }
            if currentKey == startKey || direction == 1 { break }
            points.reverse()
            points2D.reverse()
            swap(&startKey, &currentKey)
        }

        let isClosed = currentKey == startKey && points2D.count >= 3
        if isClosed,
           let first = points2D.first,
           let last = points2D.last,
           distance(first, last) <= tolerance {
            points.removeLast()
            points2D.removeLast()
        }

        guard points2D.count >= (isClosed ? 3 : 2) else {
            return nil
        }

        return SectionAnalysisResult.IntersectionContour(
            id: "\(bodyID):\(occurrenceID?.rawValue ?? sceneNodeID?.description ?? "root"):contour:\(contourIndex)",
            bodyID: bodyID,
            sceneNodeID: sceneNodeID, occurrenceID: occurrenceID,
            points: points,
            points2D: points2D,
            isClosed: isClosed,
            signedAreaSquareMeters: isClosed ? signedArea(points2D) : 0.0,
            lengthMeters: length(points2D, closes: isClosed),
            segmentCount: segmentCount
        )
    }

    private func nextUnusedEdgeIndex(
        at key: PointKey,
        adjacency: [PointKey: [Int]],
        usedEdges: Set<Int>
    ) -> Int? {
        adjacency[key]?.first { usedEdges.contains($0) == false }
    }

    private func append(
        point: Point3D,
        point2D: Point2D,
        to points: inout [Point3D],
        points2D: inout [Point2D]
    ) {
        points.append(point)
        points2D.append(point2D)
    }

    private func undirectedEdgeKey(
        bodyID: String,
        sceneNodeID: SceneNodeID?,
        occurrenceID: SceneOccurrenceID?,
        startKey: PointKey,
        endKey: PointKey
    ) -> UndirectedEdgeKey {
        if ordered(startKey, before: endKey) {
            return UndirectedEdgeKey(bodyID: bodyID, sceneNodeID: sceneNodeID, occurrenceID: occurrenceID, first: startKey, second: endKey)
        }
        return UndirectedEdgeKey(bodyID: bodyID, sceneNodeID: sceneNodeID, occurrenceID: occurrenceID, first: endKey, second: startKey)
    }

    private func ordered(_ lhs: PointKey, before rhs: PointKey) -> Bool {
        lhs <= rhs
    }

    private func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func signedArea(_ points: [Point2D]) -> Double {
        guard points.count >= 3, let origin = points.first else {
            return 0.0
        }
        var sum = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            // Rebase to a local origin so the shoelace stays exact when the section
            // contour is projected on a canonical plane far from the world origin
            // (site-planning ~1e12). Signed area is translation invariant.
            let currentX = current.x - origin.x
            let currentY = current.y - origin.y
            let nextX = next.x - origin.x
            let nextY = next.y - origin.y
            sum += currentX * nextY - nextX * currentY
        }
        return sum * 0.5
    }

    private func length(_ points: [Point2D], closes: Bool) -> Double {
        guard points.count >= 2 else {
            return 0.0
        }
        var total = 0.0
        for index in 0..<(points.count - 1) {
            total += distance(points[index], points[index + 1])
        }
        if closes, let first = points.first, let last = points.last {
            total += distance(last, first)
        }
        return total
    }
}
