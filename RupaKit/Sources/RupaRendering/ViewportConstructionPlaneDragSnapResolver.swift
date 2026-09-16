import RupaCore
import RupaViewportScene
import SwiftCAD

struct ViewportConstructionPlaneDragSnapResolver: Sendable {
    private let snapResolver: SnapResolver

    init(snapResolver: SnapResolver = SnapResolver()) {
        self.snapResolver = snapResolver
    }

    /// Snaps a dragged construction-plane handle onto the document's snap
    /// candidates.
    ///
    /// The dragged target already carries the origin the gesture started from,
    /// because a normal handle rotates about its plane's origin rather than
    /// moving it, so no separate source target is needed. Snapping is a
    /// document query, so it names no screen point and no viewport layout.
    ///
    /// The query carries the caller's published evaluation context, so a handle
    /// dragged over a document with CAD topology costs the kernel what the
    /// caller already paid rather than a whole-document evaluation per pointer
    /// move. The
    /// [snap topology demand contract](../RupaCore/DESIGN.md#snap-topology-demand-contract)
    /// owns whether that context is reused.
    func snappedTarget(
        _ target: ViewportConstructionPlaneDragTarget,
        document: DesignDocument,
        ruler: RulerConfiguration,
        options: SnapResolutionOptions?,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) -> ViewportConstructionPlaneDragTarget {
        guard let options else {
            return target
        }

        switch target.handle {
        case .origin:
            guard let snappedOrigin = snappedWorldPoint(
                rawWorldPoint: target.origin,
                document: document,
                ruler: ruler,
                options: options,
                allowsPlanarFallback: true,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
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
            let rawNormalEnd = pointOffsetBy(target.origin, target.normal)
            guard let snappedNormalEnd = snappedWorldPoint(
                rawWorldPoint: rawNormalEnd,
                document: document,
                ruler: ruler,
                options: options,
                allowsPlanarFallback: false,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            ) else {
                return target
            }
            let snappedNormal = vector(from: target.origin, to: snappedNormalEnd)
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
        document: DesignDocument,
        ruler: RulerConfiguration,
        options: SnapResolutionOptions,
        allowsPlanarFallback: Bool,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) -> Point3D? {
        let queryPoint = snapQueryPoint(
            rawWorldPoint: rawWorldPoint,
            options: options
        )
        do {
            let result = try snapResolver.resolve(
                point: queryPoint,
                in: document,
                ruler: ruler,
                options: options,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
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
                options: options
            )
        } catch {
            return nil
        }
    }

    private func snapQueryPoint(
        rawWorldPoint: Point3D,
        options: SnapResolutionOptions
    ) -> Point2D {
        if let sketchPlane = options.constructionPlane,
           let point = projectedPoint(rawWorldPoint, on: sketchPlane) {
            return point
        }
        return Point2D(x: rawWorldPoint.x, y: rawWorldPoint.z)
    }

    private func planarFallbackWorldPoint(
        resolvedPoint: Point2D,
        rawWorldPoint: Point3D,
        options: SnapResolutionOptions
    ) throws -> Point3D {
        if let sketchPlane = options.constructionPlane {
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
