import Foundation
import SwiftCAD

struct SectionAnalysisContourBuilder: Sendable {
    private struct PointKey: Hashable, Sendable {
        var x: Int64
        var y: Int64
    }

    private struct UndirectedEdgeKey: Hashable, Sendable {
        var bodyID: String
        var first: PointKey
        var second: PointKey
    }

    private struct Edge: Sendable {
        var bodyID: String
        var startKey: PointKey
        var endKey: PointKey
        var start: Point3D
        var end: Point3D
        var start2D: Point2D
        var end2D: Point2D
    }

    private var tolerance: Double

    init(tolerance: Double) {
        self.tolerance = max(tolerance, 1.0e-12)
    }

    func build(
        segments: [SectionAnalysisResult.IntersectionSegment]
    ) -> [SectionAnalysisResult.IntersectionContour] {
        let edges = uniqueEdges(from: segments)
        guard edges.isEmpty == false else {
            return []
        }

        let groupedEdges = Dictionary(grouping: edges, by: \.bodyID)
        return groupedEdges.keys.sorted().flatMap { bodyID in
            contours(for: groupedEdges[bodyID] ?? [], bodyID: bodyID)
        }
    }

    private func uniqueEdges(
        from segments: [SectionAnalysisResult.IntersectionSegment]
    ) -> [Edge] {
        var seen = Set<UndirectedEdgeKey>()
        var edges: [Edge] = []
        edges.reserveCapacity(segments.count)

        for segment in segments {
            let startKey = key(for: segment.start2D)
            let endKey = key(for: segment.end2D)
            guard startKey != endKey else {
                continue
            }
            let edgeKey = undirectedEdgeKey(
                bodyID: segment.bodyID,
                startKey: startKey,
                endKey: endKey
            )
            guard seen.insert(edgeKey).inserted else {
                continue
            }
            edges.append(Edge(
                bodyID: segment.bodyID,
                startKey: startKey,
                endKey: endKey,
                start: segment.start,
                end: segment.end,
                start2D: segment.start2D,
                end2D: segment.end2D
            ))
        }
        return edges
    }

    private func contours(
        for edges: [Edge],
        bodyID: String
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
        contourIndex: Int
    ) -> SectionAnalysisResult.IntersectionContour? {
        let firstEdge = edges[startIndex]
        usedEdges.insert(startIndex)

        let startKey = firstEdge.startKey
        var currentKey = firstEdge.endKey
        var points = [firstEdge.start, firstEdge.end]
        var points2D = [firstEdge.start2D, firstEdge.end2D]
        var segmentCount = 1

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
            id: "\(bodyID):contour:\(contourIndex)",
            bodyID: bodyID,
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
        guard let last = points2D.last,
              distance(last, point2D) <= tolerance else {
            points.append(point)
            points2D.append(point2D)
            return
        }
        points[points.count - 1] = point
        points2D[points2D.count - 1] = point2D
    }

    private func key(for point: Point2D) -> PointKey {
        PointKey(
            x: quantized(point.x),
            y: quantized(point.y)
        )
    }

    private func quantized(_ value: Double) -> Int64 {
        let scaled = (value / tolerance).rounded()
        if scaled >= Double(Int64.max) {
            return Int64.max
        }
        if scaled <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(scaled)
    }

    private func undirectedEdgeKey(
        bodyID: String,
        startKey: PointKey,
        endKey: PointKey
    ) -> UndirectedEdgeKey {
        if ordered(startKey, before: endKey) {
            return UndirectedEdgeKey(bodyID: bodyID, first: startKey, second: endKey)
        }
        return UndirectedEdgeKey(bodyID: bodyID, first: endKey, second: startKey)
    }

    private func ordered(_ lhs: PointKey, before rhs: PointKey) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.y <= rhs.y
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
