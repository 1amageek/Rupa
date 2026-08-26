import CoreGraphics
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene
import SwiftCAD

struct MeshSourcePresentationScreenHitTester {
    func occurrenceID(
        at point: CGPoint,
        in plan: MeshSourcePresentationRenderPlan,
        layout: ViewportLayout,
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver? = nil
    ) throws -> SceneOccurrenceID? {
        var bestOccurrenceID: SceneOccurrenceID?
        var bestDepth: Double?

        try plan.forEachTriangle { triangle in
            let polygon: ViewportTrianglePolygon
            if let sectionGeometryResolver {
                guard let resolvedPolygon = sectionGeometryResolver.polygon(for: triangle) else {
                    return
                }
                polygon = resolvedPolygon
            } else {
                polygon = ViewportTrianglePolygon(
                    first: point3D(triangle.firstPosition),
                    second: point3D(triangle.secondPosition),
                    third: point3D(triangle.thirdPosition)
                )
            }
            guard let depth = hitDepth(
                at: point,
                in: polygon,
                layout: layout
            ) else {
                return
            }
            if isNearer(depth, than: bestDepth) {
                bestOccurrenceID = triangle.occurrenceID
                bestDepth = depth
            }
        }
        return bestOccurrenceID
    }

    func occurrenceIDs(
        intersecting rect: CGRect,
        in plan: MeshSourcePresentationRenderPlan,
        layout: ViewportLayout,
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver? = nil
    ) throws -> [SceneOccurrenceID] {
        let normalizedRect = rect.standardized
        guard normalizedRect.isEmpty == false else {
            return []
        }
        var occurrenceIDs: [SceneOccurrenceID] = []
        var seen: Set<SceneOccurrenceID> = []
        try plan.forEachTriangle { triangle in
            guard seen.contains(triangle.occurrenceID) == false else {
                return
            }
            let polygon: ViewportTrianglePolygon
            if let sectionGeometryResolver {
                guard let resolvedPolygon = sectionGeometryResolver.polygon(for: triangle) else {
                    return
                }
                polygon = resolvedPolygon
            } else {
                polygon = ViewportTrianglePolygon(
                    first: point3D(triangle.firstPosition),
                    second: point3D(triangle.secondPosition),
                    third: point3D(triangle.thirdPosition)
                )
            }
            guard polygonIntersects(
                normalizedRect,
                polygon: polygon,
                layout: layout
            ) else {
                return
            }
            seen.insert(triangle.occurrenceID)
            occurrenceIDs.append(triangle.occurrenceID)
        }
        return occurrenceIDs
    }

    private func polygonIntersects(
        _ rect: CGRect,
        polygon: ViewportTrianglePolygon,
        layout: ViewportLayout
    ) -> Bool {
        guard rect.intersects(projectedBounds(of: polygon, layout: layout)) else {
            return false
        }
        let first = layout.project(polygon.first)
        let second = layout.project(polygon.second)
        let third = layout.project(polygon.third)
        let fourth = polygon.fourth.map(layout.project)

        if rect.contains(first) || rect.contains(second) || rect.contains(third) {
            return true
        }
        if let fourth, rect.contains(fourth) {
            return true
        }

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        if polygonContains(topLeft, first: first, second: second, third: third, fourth: fourth)
            || polygonContains(topRight, first: first, second: second, third: third, fourth: fourth)
            || polygonContains(bottomRight, first: first, second: second, third: third, fourth: fourth)
            || polygonContains(bottomLeft, first: first, second: second, third: third, fourth: fourth) {
            return true
        }

        if segmentIntersectsRect(first, second, rect: rect)
            || segmentIntersectsRect(second, third, rect: rect) {
            return true
        }
        if let fourth {
            return segmentIntersectsRect(third, fourth, rect: rect)
                || segmentIntersectsRect(fourth, first, rect: rect)
        }
        return segmentIntersectsRect(third, first, rect: rect)
    }

    private func polygonContains(
        _ point: CGPoint,
        first: CGPoint,
        second: CGPoint,
        third: CGPoint,
        fourth: CGPoint?
    ) -> Bool {
        if barycentricWeights(
            for: point,
            first: first,
            second: second,
            third: third
        ) != nil {
            return true
        }
        guard let fourth else {
            return false
        }
        return barycentricWeights(
            for: point,
            first: first,
            second: third,
            third: fourth
        ) != nil
    }

    private func segmentIntersectsRect(
        _ first: CGPoint,
        _ second: CGPoint,
        rect: CGRect
    ) -> Bool {
        if rect.contains(first) || rect.contains(second) {
            return true
        }
        guard max(first.x, second.x) >= rect.minX,
              min(first.x, second.x) <= rect.maxX,
              max(first.y, second.y) >= rect.minY,
              min(first.y, second.y) <= rect.maxY else {
            return false
        }
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        return segmentsIntersect(first, second, topLeft, topRight)
            || segmentsIntersect(first, second, topRight, bottomRight)
            || segmentsIntersect(first, second, bottomRight, bottomLeft)
            || segmentsIntersect(first, second, bottomLeft, topLeft)
    }

    private func segmentsIntersect(
        _ firstStart: CGPoint,
        _ firstEnd: CGPoint,
        _ secondStart: CGPoint,
        _ secondEnd: CGPoint
    ) -> Bool {
        let firstDirection = cross(firstStart, firstEnd, secondStart)
        let secondDirection = cross(firstStart, firstEnd, secondEnd)
        let thirdDirection = cross(secondStart, secondEnd, firstStart)
        let fourthDirection = cross(secondStart, secondEnd, firstEnd)
        let tolerance = 1.0e-9

        if ((firstDirection > tolerance && secondDirection < -tolerance)
            || (firstDirection < -tolerance && secondDirection > tolerance))
            && ((thirdDirection > tolerance && fourthDirection < -tolerance)
                || (thirdDirection < -tolerance && fourthDirection > tolerance)) {
            return true
        }
        if abs(firstDirection) <= tolerance, point(secondStart, liesOn: firstStart, firstEnd) {
            return true
        }
        if abs(secondDirection) <= tolerance, point(secondEnd, liesOn: firstStart, firstEnd) {
            return true
        }
        if abs(thirdDirection) <= tolerance, point(firstStart, liesOn: secondStart, secondEnd) {
            return true
        }
        return abs(fourthDirection) <= tolerance
            && point(firstEnd, liesOn: secondStart, secondEnd)
    }

    private func cross(_ start: CGPoint, _ end: CGPoint, _ point: CGPoint) -> Double {
        Double(end.x - start.x) * Double(point.y - start.y)
            - Double(end.y - start.y) * Double(point.x - start.x)
    }

    private func point(_ point: CGPoint, liesOn start: CGPoint, _ end: CGPoint) -> Bool {
        let tolerance = 1.0e-9
        return point.x >= min(start.x, end.x) - tolerance
            && point.x <= max(start.x, end.x) + tolerance
            && point.y >= min(start.y, end.y) - tolerance
            && point.y <= max(start.y, end.y) + tolerance
    }

    private func projectedBounds(
        of polygon: ViewportTrianglePolygon,
        layout: ViewportLayout
    ) -> CGRect {
        var bounds = CGRect.null
        bounds = bounds.union(zeroSizeRect(at: layout.project(polygon.first)))
        bounds = bounds.union(zeroSizeRect(at: layout.project(polygon.second)))
        bounds = bounds.union(zeroSizeRect(at: layout.project(polygon.third)))
        if let fourth = polygon.fourth {
            bounds = bounds.union(zeroSizeRect(at: layout.project(fourth)))
        }
        return bounds
    }

    private func zeroSizeRect(at point: CGPoint) -> CGRect {
        CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0)
    }

    private func hitDepth(
        at point: CGPoint,
        in polygon: ViewportTrianglePolygon,
        layout: ViewportLayout
    ) -> Double? {
        var bestDepth = triangleHitDepth(
            at: point,
            first: polygon.first,
            second: polygon.second,
            third: polygon.third,
            layout: layout
        )
        if let fourth = polygon.fourth,
           let depth = triangleHitDepth(
               at: point,
               first: polygon.first,
               second: polygon.third,
               third: fourth,
               layout: layout
           ),
           isNearer(depth, than: bestDepth) {
            bestDepth = depth
        }
        return bestDepth
    }

    private func triangleHitDepth(
        at point: CGPoint,
        first: Point3D,
        second: Point3D,
        third: Point3D,
        layout: ViewportLayout
    ) -> Double? {
        guard let weights = barycentricWeights(
            for: point,
            first: layout.project(first),
            second: layout.project(second),
            third: layout.project(third)
        ) else {
            return nil
        }
        return interpolatedDepth(
            first: first,
            second: second,
            third: third,
            weights: weights,
            layout: layout
        )
    }

    private func barycentricWeights(
        for point: CGPoint,
        first: CGPoint,
        second: CGPoint,
        third: CGPoint
    ) -> (first: Double, second: Double, third: Double)? {
        let denominator = Double(
            (second.y - third.y) * (first.x - third.x)
                + (third.x - second.x) * (first.y - third.y)
        )
        guard denominator.isFinite, abs(denominator) > 1.0e-12 else {
            return nil
        }
        let firstWeight = Double(
            (second.y - third.y) * (point.x - third.x)
                + (third.x - second.x) * (point.y - third.y)
        ) / denominator
        let secondWeight = Double(
            (third.y - first.y) * (point.x - third.x)
                + (first.x - third.x) * (point.y - third.y)
        ) / denominator
        let thirdWeight = 1.0 - firstWeight - secondWeight
        let tolerance = 1.0e-9
        guard firstWeight >= -tolerance,
              secondWeight >= -tolerance,
              thirdWeight >= -tolerance else {
            return nil
        }
        return (firstWeight, secondWeight, thirdWeight)
    }

    private func interpolatedDepth(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        weights: (first: Double, second: Double, third: Double),
        layout: ViewportLayout
    ) -> Double? {
        guard let firstDepth = layout.projectedDepth(first),
              let secondDepth = layout.projectedDepth(second),
              let thirdDepth = layout.projectedDepth(third) else {
            return nil
        }
        return firstDepth * weights.first
            + secondDepth * weights.second
            + thirdDepth * weights.third
    }

    private func isNearer(_ candidate: Double, than current: Double?) -> Bool {
        guard let current else {
            return true
        }
        return candidate > current
    }

    private func point3D(_ point: GeometryPoint3D) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }
}
