import RupaCore
import RupaViewportScene
import SwiftCAD

struct ViewportPlacementFootprint: Equatable, Sendable {
    var bottomLeft: Point3D
    var bottomRight: Point3D
    var topRight: Point3D
    var topLeft: Point3D

    init?(
        centeredAt canvasPoint: Point2D,
        sideMeters: Double,
        sketchPlane: SketchPlane
    ) {
        guard canvasPoint.x.isFinite,
              canvasPoint.y.isFinite,
              sideMeters.isFinite,
              sideMeters > 0.0 else {
            return nil
        }

        do {
            let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
            let center = SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
                .localPoint(fromCanvas: canvasPoint)
            let halfSide = sideMeters / 2.0
            bottomLeft = coordinateSystem.point(
                from: Point2D(x: center.x - halfSide, y: center.y - halfSide)
            )
            bottomRight = coordinateSystem.point(
                from: Point2D(x: center.x + halfSide, y: center.y - halfSide)
            )
            topRight = coordinateSystem.point(
                from: Point2D(x: center.x + halfSide, y: center.y + halfSide)
            )
            topLeft = coordinateSystem.point(
                from: Point2D(x: center.x - halfSide, y: center.y + halfSide)
            )
        } catch {
            return nil
        }
    }

    func projected(in layout: ViewportLayout) -> ViewportProjectedRect {
        ViewportProjectedRect(
            bottomLeft: layout.project(bottomLeft),
            bottomRight: layout.project(bottomRight),
            topRight: layout.project(topRight),
            topLeft: layout.project(topLeft)
        )
    }
}
