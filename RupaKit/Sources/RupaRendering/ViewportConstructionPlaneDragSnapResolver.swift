import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

struct ViewportConstructionPlaneDragSnapResolver: Sendable {
    func snappedTarget(
        _ target: ViewportConstructionPlaneDragTarget,
        sourceTarget: ViewportConstructionPlaneHandleTarget,
        screenPoint: CGPoint,
        document: DesignDocument,
        options: SnapResolutionOptions?,
        layout: ViewportLayout
    ) -> ViewportConstructionPlaneDragTarget {
        guard let options else {
            return target
        }

        switch target.handle {
        case .origin:
            guard let snappedOrigin = snappedWorldPoint(
                rawWorldPoint: target.origin,
                screenPoint: screenPoint,
                document: document,
                options: options,
                layout: layout,
                allowsPlanarFallback: true
            ) else {
                return target
            }
            return ViewportConstructionPlaneDragTarget(
                constructionPlaneID: target.constructionPlaneID,
                sceneNodeID: target.sceneNodeID,
                handle: target.handle,
                origin: snappedOrigin,
                normal: target.normal
            )
        case .normal:
            let rawNormalEnd = pointOffsetBy(sourceTarget.origin, target.normal)
            guard let snappedNormalEnd = snappedWorldPoint(
                rawWorldPoint: rawNormalEnd,
                screenPoint: screenPoint,
                document: document,
                options: options,
                layout: layout,
                allowsPlanarFallback: false
            ) else {
                return target
            }
            let snappedNormal = vector(from: sourceTarget.origin, to: snappedNormalEnd)
            guard snappedNormal.length > 1.0e-12,
                  snappedNormal.isFinite else {
                return target
            }
            return ViewportConstructionPlaneDragTarget(
                constructionPlaneID: target.constructionPlaneID,
                sceneNodeID: target.sceneNodeID,
                handle: target.handle,
                origin: target.origin,
                normal: snappedNormal
            )
        }
    }

    private func snappedWorldPoint(
        rawWorldPoint: Point3D,
        screenPoint: CGPoint,
        document: DesignDocument,
        options: SnapResolutionOptions,
        layout: ViewportLayout,
        allowsPlanarFallback: Bool
    ) -> Point3D? {
        let queryPoint = snapQueryPoint(
            rawWorldPoint: rawWorldPoint,
            screenPoint: screenPoint,
            document: document,
            options: options,
            layout: layout
        )
        do {
            let result = try SnapResolver().resolve(
                point: queryPoint,
                in: document,
                options: options
            )
            if let selectedWorldPoint = result.selectedWorldPoint {
                return selectedWorldPoint
            }
            guard allowsPlanarFallback,
                  result.selectedCandidate != nil else {
                return nil
            }
            return try planarFallbackWorldPoint(
                resolvedPoint: result.resolvedPoint,
                rawWorldPoint: rawWorldPoint,
                document: document,
                options: options
            )
        } catch {
            return nil
        }
    }

    private func snapQueryPoint(
        rawWorldPoint: Point3D,
        screenPoint _: CGPoint,
        document: DesignDocument,
        options: SnapResolutionOptions,
        layout _: ViewportLayout
    ) -> Point2D {
        if options.usesConstructionPlaneProjection,
           let sketchPlane = options.constructionPlane ?? document.activeConstructionPlane?.plane,
           let point = projectedPoint(rawWorldPoint, on: sketchPlane) {
            return point
        }
        return Point2D(x: rawWorldPoint.x, y: rawWorldPoint.z)
    }

    private func planarFallbackWorldPoint(
        resolvedPoint: Point2D,
        rawWorldPoint: Point3D,
        document: DesignDocument,
        options: SnapResolutionOptions
    ) throws -> Point3D {
        if options.usesConstructionPlaneProjection,
           let sketchPlane = options.constructionPlane ?? document.activeConstructionPlane?.plane {
            return try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: resolvedPoint)
        }
        return Point3D(
            x: resolvedPoint.x,
            y: rawWorldPoint.y,
            z: resolvedPoint.y
        )
    }

    private func projectedPoint(
        _ point: Point3D,
        on sketchPlane: SketchPlane
    ) -> Point2D? {
        do {
            return try SketchPlaneCoordinateSystem(plane: sketchPlane).project(point).point
        } catch {
            return nil
        }
    }

    private func pointOffsetBy(_ point: Point3D, _ vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }
}
