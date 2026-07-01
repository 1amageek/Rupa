import RupaCore
import RupaRendering

struct WorkspaceCanvasPlaneInputMapper: Sendable {
    struct Result: Equatable, Sendable {
        var point: Point2D
        var worldPoint: Point3D?
    }

    enum Failure: Error, Equatable {
        case unresolvedViewNormal
        case viewRayParallelToPlane
    }

    var projectionBasis: ViewportProjectionBasis
    var tolerance: Double

    init(
        projectionBasis: ViewportProjectionBasis,
        tolerance: Double = 1.0e-10
    ) {
        self.projectionBasis = projectionBasis
        self.tolerance = tolerance
    }

    func map(
        modelPoint: Point2D,
        modelWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) throws -> Result {
        guard case .plane = sketchPlane else {
            return Result(point: modelPoint, worldPoint: modelWorldPoint)
        }

        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
        if let modelWorldPoint {
            return Result(
                point: coordinateSystem.project(modelWorldPoint).point,
                worldPoint: modelWorldPoint
            )
        }

        guard let viewNormal = projectionBasis.viewNormal else {
            throw Failure.unresolvedViewNormal
        }
        let rayOrigin = Point3D(x: modelPoint.x, y: 0.0, z: modelPoint.y)
        let denominator = viewNormal.dot(coordinateSystem.normal)
        guard abs(denominator) > tolerance else {
            throw Failure.viewRayParallelToPlane
        }

        let originOffset = Vector3D(
            x: coordinateSystem.origin.x - rayOrigin.x,
            y: coordinateSystem.origin.y - rayOrigin.y,
            z: coordinateSystem.origin.z - rayOrigin.z
        )
        let distance = originOffset.dot(coordinateSystem.normal) / denominator
        let worldPoint = Point3D(
            x: rayOrigin.x + viewNormal.x * distance,
            y: rayOrigin.y + viewNormal.y * distance,
            z: rayOrigin.z + viewNormal.z * distance
        )
        return Result(
            point: coordinateSystem.project(worldPoint).point,
            worldPoint: worldPoint
        )
    }
}
