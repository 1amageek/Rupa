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
        viewRayAnchorWorldPoint: Point3D? = nil,
        sketchPlane: SketchPlane
    ) throws -> Result {
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
        if let modelWorldPoint {
            return mappedResult(
                for: modelWorldPoint,
                coordinateSystem: coordinateSystem,
                sketchPlane: sketchPlane
            )
        }

        if let viewRayAnchorWorldPoint {
            guard let viewNormal = projectionBasis.viewNormal else {
                throw Failure.unresolvedViewNormal
            }
            let worldPoint = try intersectPlane(
                rayOrigin: viewRayAnchorWorldPoint,
                rayDirection: viewNormal,
                coordinateSystem: coordinateSystem
            )
            return mappedResult(
                for: worldPoint,
                coordinateSystem: coordinateSystem,
                sketchPlane: sketchPlane
            )
        }

        guard case .plane = sketchPlane else {
            return Result(point: modelPoint, worldPoint: nil)
        }

        guard let viewNormal = projectionBasis.viewNormal else {
            throw Failure.unresolvedViewNormal
        }
        let rayOrigin = viewRayAnchorWorldPoint ?? Point3D(x: modelPoint.x, y: 0.0, z: modelPoint.y)
        let worldPoint = try intersectPlane(
            rayOrigin: rayOrigin,
            rayDirection: viewNormal,
            coordinateSystem: coordinateSystem
        )
        return mappedResult(
            for: worldPoint,
            coordinateSystem: coordinateSystem,
            sketchPlane: sketchPlane
        )
    }

    private func mappedResult(
        for worldPoint: Point3D,
        coordinateSystem: SketchPlaneCoordinateSystem,
        sketchPlane: SketchPlane
    ) -> Result {
        let localPoint = coordinateSystem.project(worldPoint).point
        return Result(
            point: SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
                .canvasPoint(fromLocal: localPoint),
            worldPoint: worldPoint
        )
    }

    private func intersectPlane(
        rayOrigin: Point3D,
        rayDirection: Vector3D,
        coordinateSystem: SketchPlaneCoordinateSystem
    ) throws -> Point3D {
        let denominator = rayDirection.dot(coordinateSystem.normal)
        guard abs(denominator) > tolerance else {
            throw Failure.viewRayParallelToPlane
        }
        let originOffset = Vector3D(
            x: coordinateSystem.origin.x - rayOrigin.x,
            y: coordinateSystem.origin.y - rayOrigin.y,
            z: coordinateSystem.origin.z - rayOrigin.z
        )
        let distance = originOffset.dot(coordinateSystem.normal) / denominator
        return Point3D(
            x: rayOrigin.x + rayDirection.x * distance,
            y: rayOrigin.y + rayDirection.y * distance,
            z: rayOrigin.z + rayDirection.z * distance
        )
    }

    public func resolvedWorldPoint(
        for point: Point2D,
        snappedWorldPoint: Point3D?,
        fallbackWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) throws -> Point3D? {
        if let snappedWorldPoint {
            return snappedWorldPoint
        }
        guard case .plane = sketchPlane else {
            return fallbackWorldPoint
        }
        return try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: point)
    }
}
