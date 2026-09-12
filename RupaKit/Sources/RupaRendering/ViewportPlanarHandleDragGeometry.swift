import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPlanarHandleDragGeometry: Equatable {
    var localPoint: Point3D
    var modelTransform: Transform3D

    var displayPoint: Point3D {
        modelTransform.viewportTransformedPoint(localPoint)
    }

    func projectedPoint(layout: ViewportLayout) -> CGPoint? {
        layout.projectedPoint(displayPoint)?.point
    }

    func localAxisEndpoint(
        direction: Vector3D,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        endpoint(localDirection: direction, viewportLength: viewportLength, layout: layout)
    }

    private func endpoint(
        localDirection: Vector3D,
        viewportLength: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint? {
        guard let axisVector = projectedVector(localDirection: localDirection, layout: layout) else {
            return nil
        }
        guard axisVector.length > 1.0e-9 else {
            return nil
        }
        let amount = Double(viewportLength / axisVector.length)
        let displayDirection = modelTransform.viewportTransformedVector(localDirection)
        return layout.projectedPoint(Point3D(
            x: displayPoint.x + displayDirection.x * amount,
            y: displayPoint.y + displayDirection.y * amount,
            z: displayPoint.z + displayDirection.z * amount
        ))?.point
    }

    private func projectedVector(
        localDirection: Vector3D,
        layout: ViewportLayout
    ) -> CGVector? {
        guard let start = layout.projectedPoint(displayPoint)?.point else {
            return nil
        }
        let displayDirection = modelTransform.viewportTransformedVector(localDirection)
        guard let end = layout.projectedPoint(Point3D(
            x: displayPoint.x + displayDirection.x,
            y: displayPoint.y + displayDirection.y,
            z: displayPoint.z + displayDirection.z
        ))?.point else {
            return nil
        }
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }
}
