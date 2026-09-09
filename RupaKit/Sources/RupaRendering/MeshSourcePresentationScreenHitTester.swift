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
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver? = nil,
        cullBackFaces: Bool = false
    ) -> SceneOccurrenceID? {
        triangle(
            at: point,
            in: plan,
            layout: layout,
            sectionGeometryResolver: sectionGeometryResolver,
            cullBackFaces: cullBackFaces
        )?.occurrenceID
    }

    /// Returns the world point on the front-most visible triangle under the
    /// pointer. The same triangle/depth/culling path as occurrence picking is
    /// used, so measurement cannot resolve against geometry that the picker
    /// would not expose.
    func worldPoint(
        at point: CGPoint,
        in plan: MeshSourcePresentationRenderPlan,
        layout: ViewportLayout,
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver? = nil,
        cullBackFaces: Bool = false
    ) -> (point: Point3D, occurrenceID: SceneOccurrenceID)? {
        guard let triangle = triangle(
            at: point,
            in: plan,
            layout: layout,
            sectionGeometryResolver: sectionGeometryResolver,
            cullBackFaces: cullBackFaces
        ) else {
            return nil
        }
        guard let ray = layout.viewportRay(for: point) else { return nil }
        let first = point3D(triangle.firstPosition)
        let second = point3D(triangle.secondPosition)
        let third = point3D(triangle.thirdPosition)
        // Screen barycentrics are not world barycentrics under perspective.
        // Picking already admitted the clipped polygon; intersect its plane.
        let normal = (second - first).cross(third - first)
        let denominator = ray.direction.dot(normal)
        guard denominator.isFinite, denominator != 0 else { return nil }
        let distance = (first - ray.origin).dot(normal) / denominator
        let worldPoint = ray.origin + ray.direction * distance
        guard worldPoint.isFinite, layout.projectedPoint(worldPoint) != nil else { return nil }
        return (worldPoint, triangle.occurrenceID)
    }

    private func triangle(
        at point: CGPoint,
        in plan: MeshSourcePresentationRenderPlan,
        layout: ViewportLayout,
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver?,
        cullBackFaces: Bool
    ) -> MeshSourcePresentationTriangle? {
        var bestTriangle: MeshSourcePresentationTriangle?
        var bestDepth: Double?

        plan.forEachTriangle { triangle in
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
            guard !cullBackFaces || isFrontFacing(polygon, layout: layout) else {
                return
            }
            guard let depth = hitDepth(
                at: point,
                in: polygon,
                layout: layout
            ) else {
                return
            }
            if isNearer(depth, than: bestDepth) {
                bestTriangle = triangle
                bestDepth = depth
            }
        }
        return bestTriangle
    }

    func meshElement(
        at point: CGPoint,
        domain: GeometryAttributeDomain,
        in plan: MeshSourcePresentationRenderPlan,
        scene: UniversalViewportScene,
        layout: ViewportLayout,
        tolerance: CGFloat = 8,
        sectionGeometryResolver: MeshSourcePresentationSectionGeometryResolver? = nil,
        cullBackFaces: Bool = false
    ) -> ViewportMeshElementHit? {
        guard plan.snapshotID == scene.snapshotID,
              let triangle = triangle(
                  at: point,
                  in: plan,
                  layout: layout,
                  sectionGeometryResolver: sectionGeometryResolver,
                  cullBackFaces: cullBackFaces
              ),
              case .authoredMesh(let sourceID) = triangle.sourceReference else { return nil }
        let element: MeshSelectionElement
        switch domain {
        case .face:
            element = .face(triangle.faceID)
        case .vertex, .edge:
            let ids = [triangle.firstVertexID, triangle.secondVertexID, triangle.thirdVertexID]
            let points = [triangle.firstPosition, triangle.secondPosition, triangle.thirdPosition]
                .compactMap { layout.projectedPoint(point3D($0))?.point }
            guard points.count == 3 else {
                return nil
            }
            if domain == .vertex {
                guard let index = (0..<3).min(by: { distanceSquared(point, points[$0]) < distanceSquared(point, points[$1]) }),
                      distanceSquared(point, points[index]) <= tolerance * tolerance else { return nil }
                element = .vertex(ids[index])
            } else {
                let edgeIDs = [triangle.firstEdgeID, triangle.secondEdgeID, triangle.thirdEdgeID]
                var nearest: (id: MeshEdgeID, distance: CGFloat)?
                // Only original face-loop edges qualify, never tessellation diagonals.
                for side in 0..<3 {
                    guard let edgeID = edgeIDs[side] else { continue }
                    let next = (side + 1) % 3
                    let distance = segmentDistanceSquared(point, points[side], points[next])
                    guard distance <= tolerance * tolerance, distance < (nearest?.distance ?? .infinity) else { continue }
                    nearest = (edgeID, distance)
                }
                guard let nearest else { return nil }
                element = .edge(nearest.id)
            }
        default:
            return nil
        }
        return ViewportMeshElementHit(snapshotID: scene.snapshotID, occurrenceID: triangle.occurrenceID, sourceID: sourceID, element: element)
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let x = a.x - b.x, y = a.y - b.y
        return x * x + y * y
    }

    private func segmentDistanceSquared(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let x = b.x - a.x, y = b.y - a.y
        let length = x * x + y * y
        guard length > 0 else { return distanceSquared(point, a) }
        let t = min(1, max(0, ((point.x - a.x) * x + (point.y - a.y) * y) / length))
        return distanceSquared(point, CGPoint(x: a.x + t * x, y: a.y + t * y))
    }

    /// Metal uses counter-clockwise front faces in clip space. ViewportLayout
    /// projects to a y-down AppKit coordinate system, so the equivalent screen
    /// winding is clockwise (negative signed area).
    private func isFrontFacing(
        _ polygon: ViewportTrianglePolygon,
        layout: ViewportLayout
    ) -> Bool {
        let projected = layout.projectedPolygon(polygon.points)
        guard projected.count >= 3 else { return false }
        let first = projected[0].point
        let second = projected[1].point
        let third = projected[2].point
        let signedArea = (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
        return signedArea < 0
    }

    func segmentIntersectsRect(
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
        projectedBounds(of: layout.projectedPolygon(polygon.points).map(\.point))
    }

    private func projectedBounds(of points: [CGPoint]) -> CGRect {
        var bounds = CGRect.null
        for point in points where point.x.isFinite && point.y.isFinite {
            bounds = bounds.union(zeroSizeRect(at: point))
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
        let projected = layout.projectedPolygon(polygon.points)
        guard projected.count >= 3 else { return nil }
        var bestDepth: Double?
        for index in 1..<(projected.count - 1) {
            guard let weights = barycentricWeights(
                for: point,
                first: projected[0].point,
                second: projected[index].point,
                third: projected[index + 1].point
            ) else {
                continue
            }
            let depth = projected[0].depth * weights.first
                + projected[index].depth * weights.second
                + projected[index + 1].depth * weights.third
            if isNearer(depth, than: bestDepth) {
                bestDepth = depth
            }
        }
        return bestDepth
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
