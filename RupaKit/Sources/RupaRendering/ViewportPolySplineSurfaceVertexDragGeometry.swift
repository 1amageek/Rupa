import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPolySplineSurfaceVertexDragGeometry: Equatable {
    var localPoint: Point3D
    var modelTransform: Transform3D

    var displayPoint: Point3D {
        modelTransform.viewportTransformedPoint(localPoint)
    }

    func projectedPoint(layout: ViewportLayout) -> CGPoint {
        layout.project(displayPoint)
    }

    func projectedAxisVector(
        axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGVector {
        projectedVector(localDirection: axis.localDirection, layout: layout)
    }

    func projectedLocalAxisVector(
        direction: Vector3D,
        layout: ViewportLayout
    ) -> CGVector {
        projectedVector(localDirection: direction, layout: layout)
    }

    func axisEndpoint(
        axis: ViewportCoordinateAxis,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        endpoint(localDirection: axis.localDirection, viewportLength: viewportLength, layout: layout)
    }

    func localAxisEndpoint(
        direction: Vector3D,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        endpoint(localDirection: direction, viewportLength: viewportLength, layout: layout)
    }

    func localDelta(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Point3D {
        let amount = ViewportSurfaceVertexAxisDragMapping.modelAmount(
            axisVector: projectedAxisVector(axis: axis, layout: layout),
            start: start,
            current: current
        )
        return ViewportSurfaceVertexAxisDragMapping.delta(axis: axis, amount: amount)
    }

    func localDelta(
        direction: Vector3D,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Point3D {
        let amount = ViewportSurfaceVertexAxisDragMapping.modelAmount(
            axisVector: projectedLocalAxisVector(direction: direction, layout: layout),
            start: start,
            current: current
        )
        return ViewportSurfaceVertexAxisDragMapping.delta(direction: direction, amount: amount)
    }

    func localPlanarDelta(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Point3D {
        let startPoint = layout.unproject(start)
        let currentPoint = layout.unproject(current)
        let displayDelta = Vector3D(
            x: Double(currentPoint.x - startPoint.x),
            y: 0.0,
            z: Double(currentPoint.y - startPoint.y)
        )
        let localDelta = modelTransform.viewportInverseTransformedVector(displayDelta) ?? displayDelta
        return Point3D(x: localDelta.x, y: localDelta.y, z: localDelta.z)
    }

    func displayPoint(offsetByLocalDelta delta: Point3D) -> Point3D {
        modelTransform.viewportTransformedPoint(Point3D(
            x: localPoint.x + delta.x,
            y: localPoint.y + delta.y,
            z: localPoint.z + delta.z
        ))
    }

    private func endpoint(
        localDirection: Vector3D,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        let axisVector = projectedVector(localDirection: localDirection, layout: layout)
        guard axisVector.length > 1.0e-9 else {
            return nil
        }
        let amount = Double(viewportLength / axisVector.length)
        let displayDirection = modelTransform.viewportTransformedVector(localDirection)
        return layout.project(Point3D(
            x: displayPoint.x + displayDirection.x * amount,
            y: displayPoint.y + displayDirection.y * amount,
            z: displayPoint.z + displayDirection.z * amount
        ))
    }

    private func projectedVector(
        localDirection: Vector3D,
        layout: ViewportLayout
    ) -> CGVector {
        let start = layout.project(displayPoint)
        let displayDirection = modelTransform.viewportTransformedVector(localDirection)
        let end = layout.project(Point3D(
            x: displayPoint.x + displayDirection.x,
            y: displayPoint.y + displayDirection.y,
            z: displayPoint.z + displayDirection.z
        ))
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }
}

private extension ViewportCoordinateAxis {
    var localDirection: Vector3D {
        switch self {
        case .x:
            Vector3D(x: 1.0, y: 0.0, z: 0.0)
        case .y:
            Vector3D(x: 0.0, y: 1.0, z: 0.0)
        case .z:
            Vector3D(x: 0.0, y: 0.0, z: 1.0)
        }
    }
}
