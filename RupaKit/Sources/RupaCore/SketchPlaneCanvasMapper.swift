import Foundation
import SwiftCAD

public struct SketchPlaneCanvasMapper: Sendable {
    public var sketchPlane: SketchPlane

    public init(sketchPlane: SketchPlane) {
        self.sketchPlane = sketchPlane
    }

    public func localPoint(fromCanvas point: Point2D) -> Point2D {
        switch sketchPlane {
        case .xy, .yz, .plane:
            return point
        case .zx:
            return Point2D(x: point.y, y: point.x)
        }
    }

    public func canvasPoint(fromLocal point: Point2D) -> Point2D {
        switch sketchPlane {
        case .xy, .yz, .plane:
            return point
        case .zx:
            return Point2D(x: point.y, y: point.x)
        }
    }

    public func normalizedCanvasDirection(
        fromLocal direction: Point2D,
        tolerance: Double = 1.0e-12
    ) -> Point2D? {
        guard tolerance.isFinite, tolerance > 0.0 else {
            return nil
        }
        let canvasDirection = canvasPoint(fromLocal: direction)
        let length = hypot(canvasDirection.x, canvasDirection.y)
        guard length > tolerance else {
            return nil
        }
        return Point2D(
            x: canvasDirection.x / length,
            y: canvasDirection.y / length
        )
    }
}
