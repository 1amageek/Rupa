import Foundation
import SwiftCAD

/// Finds bodies whose sections overlap: two solids that occupy the same space cut through the
/// same area of the section plane.
///
/// A body's section is the even-odd region its closed contours bound. Two sections interfere when
/// their boundaries cross, or when a point just inside one section lies inside the other by more
/// than the tolerance (one section inside, or on top of, the other). Sections that only touch
/// along a shared boundary do not interfere.
struct SectionAnalysisInterferenceDetector {
    private struct Section {
        var bodyID: String
        var sceneNodeID: SceneNodeID?
        var occurrenceID: SceneOccurrenceID?
        var contourIDs: [String]
        var loops: [[Point2D]]
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }

    let tolerance: Double

    func interferences(
        in contours: [SectionAnalysisResult.IntersectionContour]
    ) -> [SectionAnalysisResult.Interference] {
        let sections = sections(from: contours)
        var result: [SectionAnalysisResult.Interference] = []
        for firstIndex in sections.indices {
            for secondIndex in sections.indices where secondIndex > firstIndex {
                let first = sections[firstIndex]
                let second = sections[secondIndex]
                guard boundsOverlap(first, second), interfere(first, second) else { continue }
                result.append(SectionAnalysisResult.Interference(
                    firstBodyID: first.bodyID,
                    firstSceneNodeID: first.sceneNodeID,
                    firstOccurrenceID: first.occurrenceID,
                    secondBodyID: second.bodyID,
                    secondSceneNodeID: second.sceneNodeID,
                    secondOccurrenceID: second.occurrenceID,
                    contourIDs: first.contourIDs + second.contourIDs
                ))
            }
        }
        return result
    }

    private func sections(from contours: [SectionAnalysisResult.IntersectionContour]) -> [Section] {
        var order: [String] = []
        var sections: [String: Section] = [:]
        for contour in contours where contour.isClosed && contour.points2D.count >= 3 {
            let key = "\(contour.bodyID)|\(contour.occurrenceID?.description ?? "")"
            var section = sections[key] ?? Section(
                bodyID: contour.bodyID, sceneNodeID: contour.sceneNodeID, occurrenceID: contour.occurrenceID,
                contourIDs: [], loops: [],
                minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity
            )
            if sections[key] == nil { order.append(key) }
            section.contourIDs.append(contour.id)
            section.loops.append(contour.points2D)
            for point in contour.points2D {
                section.minX = min(section.minX, point.x)
                section.minY = min(section.minY, point.y)
                section.maxX = max(section.maxX, point.x)
                section.maxY = max(section.maxY, point.y)
            }
            sections[key] = section
        }
        return order.compactMap { sections[$0] }
    }

    private func boundsOverlap(_ first: Section, _ second: Section) -> Bool {
        first.minX < second.maxX - tolerance && second.minX < first.maxX - tolerance
            && first.minY < second.maxY - tolerance && second.minY < first.maxY - tolerance
    }

    private func interfere(_ first: Section, _ second: Section) -> Bool {
        if boundariesCross(first, second) { return true }
        return hasInteriorSample(of: first, inside: second) || hasInteriorSample(of: second, inside: first)
    }

    private func boundariesCross(_ first: Section, _ second: Section) -> Bool {
        for loop in first.loops {
            for (a, b) in edges(of: loop) {
                for other in second.loops {
                    for (c, d) in edges(of: other) where segmentsCrossProperly(a, b, c, d) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Points just inside `section`, next to the quarter points of each boundary edge, tested
    /// against `other`.
    private func hasInteriorSample(of section: Section, inside other: Section) -> Bool {
        let inset = tolerance * 4.0
        for loop in section.loops {
            for (a, b) in edges(of: loop) {
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > inset * 2.0 else { continue }
                let normalX = -dy / length
                let normalY = dx / length
                for fraction in [0.25, 0.5, 0.75] {
                    let onEdge = Point2D(x: a.x + dx * fraction, y: a.y + dy * fraction)
                    for sign in [1.0, -1.0] {
                        let sample = Point2D(x: onEdge.x + normalX * inset * sign, y: onEdge.y + normalY * inset * sign)
                        guard contains(section, sample) else { continue }
                        if contains(other, sample), distanceToBoundary(of: other, from: sample) > tolerance {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func edges(of loop: [Point2D]) -> [(Point2D, Point2D)] {
        loop.indices.map { (loop[$0], loop[($0 + 1) % loop.count]) }
    }

    /// Even-odd containment across every loop of the section.
    private func contains(_ section: Section, _ point: Point2D) -> Bool {
        var inside = false
        for loop in section.loops {
            for (a, b) in edges(of: loop) where (a.y > point.y) != (b.y > point.y) {
                let x = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if point.x < x { inside.toggle() }
            }
        }
        return inside
    }

    private func distanceToBoundary(of section: Section, from point: Point2D) -> Double {
        var distance = Double.infinity
        for loop in section.loops {
            for (a, b) in edges(of: loop) {
                distance = min(distance, segmentDistance(point, a, b))
            }
        }
        return distance
    }

    private func segmentDistance(_ point: Point2D, _ a: Point2D, _ b: Point2D) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)) : 0
        let x = a.x + dx * t - point.x
        let y = a.y + dy * t - point.y
        return (x * x + y * y).squareRoot()
    }

    /// Segments crossing at a point inside both, each passing more than the tolerance to either
    /// side of the other; touching, T-junctions and collinear overlap do not count.
    private func segmentsCrossProperly(_ a: Point2D, _ b: Point2D, _ c: Point2D, _ d: Point2D) -> Bool {
        func side(_ p: Point2D, _ q: Point2D, _ r: Point2D) -> Int {
            let dx = q.x - p.x
            let dy = q.y - p.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { return 0 }
            let offset = (dx * (r.y - p.y) - dy * (r.x - p.x)) / length
            return offset > tolerance ? 1 : offset < -tolerance ? -1 : 0
        }
        let c1 = side(a, b, c)
        let c2 = side(a, b, d)
        let c3 = side(c, d, a)
        let c4 = side(c, d, b)
        return c1 != 0 && c2 != 0 && c3 != 0 && c4 != 0 && c1 != c2 && c3 != c4
    }
}
