import RupaCore
import RupaViewportScene
import SwiftCAD

public struct WorkspaceCanvasPlaneInputMapper: Sendable {
    public struct Result: Equatable, Sendable {
        public var point: Point2D
        public var worldPoint: Point3D?

        public init(point: Point2D, worldPoint: Point3D?) {
            self.point = point
            self.worldPoint = worldPoint
        }
    }

    public enum Failure: Error, Equatable {
        case unresolvedViewNormal
        case viewRayParallelToPlane
    }

    public var projectionBasis: ViewportProjectionBasis
    public var tolerance: Double

    public init(
        projectionBasis: ViewportProjectionBasis,
        tolerance: Double = 1.0e-10
    ) {
        self.projectionBasis = projectionBasis
        self.tolerance = tolerance
    }

    public func map(
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

    public func resolvedWorldPoint(
        for point: Point2D,
        topologyWorldPoint: Point3D?,
        fallbackWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) throws -> Point3D? {
        if let topologyWorldPoint {
            return topologyWorldPoint
        }
        guard case .plane = sketchPlane else {
            return fallbackWorldPoint
        }
        return try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: point)
    }
}
