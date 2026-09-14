import CoreGraphics

/// Segment-versus-rectangle overlap for bounds-ruler placement.
///
/// Placement rejects a candidate whose dimension line or extension leader
/// would cross an already accepted label, the projected object rectangle, or
/// a viewport chrome exclusion.  The predicate is purely two-dimensional: it
/// carries no picking, depth or occlusion meaning, reads no scene geometry,
/// and resolves no identity.
enum ViewportMeasurementRulerCollision {
    static func segmentIntersects(
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

    private static func segmentsIntersect(
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

    private static func cross(_ start: CGPoint, _ end: CGPoint, _ point: CGPoint) -> Double {
        Double(end.x - start.x) * Double(point.y - start.y)
            - Double(end.y - start.y) * Double(point.x - start.x)
    }

    private static func point(_ point: CGPoint, liesOn start: CGPoint, _ end: CGPoint) -> Bool {
        let tolerance = 1.0e-9
        return point.x >= min(start.x, end.x) - tolerance
            && point.x <= max(start.x, end.x) + tolerance
            && point.y >= min(start.y, end.y) - tolerance
            && point.y <= max(start.y, end.y) + tolerance
    }
}
