import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportConstructionPlaneHandleGeometry: Sendable {
    var tolerance: Double

    init(tolerance: Double = 1.0e-10) {
        self.tolerance = tolerance
    }

    func targets(
        document: DesignDocument,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportConstructionPlaneHandleTarget] {
        let ruler = document.ruler.normalizedForWorkspaceScale()
        let guideLength = normalGuideLength(ruler: ruler, layout: layout)
        var targets: [ViewportConstructionPlaneHandleTarget] = []

        for selectionTarget in selection.selectedTargets {
            let sceneNodeID = selectionTarget.sceneNodeID
            guard case .constructionPlane(let constructionPlaneID) = selectionTarget.component,
                  let source = document.productMetadata.constructionPlanes[constructionPlaneID],
                  document.productMetadata.sceneNodes[sceneNodeID]?.reference?.constructionPlaneID == constructionPlaneID,
                  let planeModel = planeModel(
                      constructionPlaneID: constructionPlaneID,
                      sceneNodeID: sceneNodeID,
                      plane: source.plane,
                      guideLength: guideLength,
                      layout: layout
                  ) else {
                continue
            }
            targets.append(planeModel.target(handle: .origin))
            targets.append(planeModel.target(handle: .normal))
        }

        return targets
    }

    func target(
        at point: CGPoint,
        document: DesignDocument,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> ViewportConstructionPlaneHandleTarget? {
        var nearest: (target: ViewportConstructionPlaneHandleTarget, distance: CGFloat)?
        for target in targets(
            document: document,
            selection: selection,
            layout: layout
        ) {
            guard let distance = hitDistance(point: point, target: target),
                  distance <= hitTolerance(for: target.handle) else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (target, distance)
            }
        }
        return nearest?.target
    }

    func draggedTarget(
        target: ViewportConstructionPlaneHandleTarget,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> ViewportConstructionPlaneDragTarget? {
        switch target.handle {
        case .origin:
            guard let delta = screenPlaneDelta(
                start: start,
                current: current,
                referencePoint: target.origin,
                layout: layout
            ) else {
                return nil
            }
            return ViewportConstructionPlaneDragTarget(
                constructionPlaneID: target.constructionPlaneID,
                sceneNodeID: target.sceneNodeID,
                handle: target.handle,
                origin: pointOffsetBy(target.origin, delta),
                normal: target.normal
            )
        case .normal:
            guard let delta = screenPlaneDelta(
                start: start,
                current: current,
                referencePoint: target.normalEnd,
                layout: layout
            ) else {
                return nil
            }
            let movedEnd = pointOffsetBy(target.normalEnd, delta)
            let normal = vector(from: target.origin, to: movedEnd)
            guard normal.length > tolerance,
                  normal.x.isFinite,
                  normal.y.isFinite,
                  normal.z.isFinite else {
                return nil
            }
            return ViewportConstructionPlaneDragTarget(
                constructionPlaneID: target.constructionPlaneID,
                sceneNodeID: target.sceneNodeID,
                handle: target.handle,
                origin: target.origin,
                normal: normal
            )
        }
    }

    private func planeModel(
        constructionPlaneID: ConstructionPlaneSourceID,
        sceneNodeID: SceneNodeID,
        plane: SketchPlane,
        guideLength: Double,
        layout: ViewportLayout
    ) -> ViewportConstructionPlaneHandlePlane? {
        let coordinateSystem: SketchPlaneCoordinateSystem
        do {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
        } catch {
            return nil
        }

        let normalEnd = pointOffsetBy(
            coordinateSystem.origin,
            scale(coordinateSystem.normal, by: guideLength)
        )
        let halfExtent = planeHalfExtent(guideLength: guideLength, layout: layout)
        let negativeU = scale(coordinateSystem.u, by: -halfExtent)
        let positiveU = scale(coordinateSystem.u, by: halfExtent)
        let negativeV = scale(coordinateSystem.v, by: -halfExtent)
        let positiveV = scale(coordinateSystem.v, by: halfExtent)
        let corners = [
            pointOffsetBy(pointOffsetBy(coordinateSystem.origin, negativeU), negativeV),
            pointOffsetBy(pointOffsetBy(coordinateSystem.origin, positiveU), negativeV),
            pointOffsetBy(pointOffsetBy(coordinateSystem.origin, positiveU), positiveV),
            pointOffsetBy(pointOffsetBy(coordinateSystem.origin, negativeU), positiveV),
        ]

        return ViewportConstructionPlaneHandlePlane(
            constructionPlaneID: constructionPlaneID,
            sceneNodeID: sceneNodeID,
            origin: coordinateSystem.origin,
            normal: coordinateSystem.normal,
            normalEnd: normalEnd,
            corners: corners,
            projectedOrigin: layout.project(coordinateSystem.origin),
            projectedNormalEnd: layout.project(normalEnd)
        )
    }

    private func normalGuideLength(
        ruler: RulerConfiguration,
        layout: ViewportLayout
    ) -> Double {
        let modelSpan = max(
            Double(max(layout.modelBounds.width, layout.modelBounds.height)),
            ruler.visibleSpanMeters
        )
        return max(
            ruler.majorTickMeters,
            min(ruler.visibleSpanMeters * 0.12, modelSpan * 0.20)
        )
    }

    private func planeHalfExtent(
        guideLength: Double,
        layout: ViewportLayout
    ) -> Double {
        let modelSpan = max(Double(max(layout.modelBounds.width, layout.modelBounds.height)), guideLength)
        return max(guideLength * 1.7, modelSpan * 0.14)
    }

    private func hitDistance(
        point: CGPoint,
        target: ViewportConstructionPlaneHandleTarget
    ) -> CGFloat? {
        switch target.handle {
        case .origin:
            return point.distance(to: target.projectedOrigin)
        case .normal:
            return min(
                point.distance(to: target.projectedNormalEnd),
                point.distanceToSegment(start: target.projectedOrigin, end: target.projectedNormalEnd)
            )
        }
    }

    private func hitTolerance(
        for handle: ViewportConstructionPlaneHandleKind
    ) -> CGFloat {
        switch handle {
        case .origin:
            return 12.0
        case .normal:
            return 14.0
        }
    }

    private func screenPlaneDelta(
        start: CGPoint,
        current: CGPoint,
        referencePoint: Point3D,
        layout: ViewportLayout
    ) -> Vector3D? {
        guard let startPoint = screenPlanePoint(
            at: start,
            referencePoint: referencePoint,
            layout: layout
        ),
        let currentPoint = screenPlanePoint(
            at: current,
            referencePoint: referencePoint,
            layout: layout
        ) else {
            return nil
        }
        return vector(from: startPoint, to: currentPoint)
    }

    private func screenPlanePoint(
        at point: CGPoint,
        referencePoint: Point3D,
        layout: ViewportLayout
    ) -> Point3D? {
        guard let viewNormal = layout.basis.viewNormal else {
            return nil
        }
        let footprint = layout.unproject(point)
        let rayOrigin = Point3D(
            x: Double(footprint.x),
            y: 0.0,
            z: Double(footprint.y)
        )
        let denominator = viewNormal.dot(viewNormal)
        guard denominator.isFinite,
              denominator > tolerance else {
            return nil
        }
        let offset = vector(from: rayOrigin, to: referencePoint)
        let distance = offset.dot(viewNormal) / denominator
        guard distance.isFinite else {
            return nil
        }
        return pointOffsetBy(rayOrigin, scale(viewNormal, by: distance))
    }

    private func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }

    private func pointOffsetBy(_ point: Point3D, _ vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private func scale(_ vector: Vector3D, by scalar: Double) -> Vector3D {
        Vector3D(
            x: vector.x * scalar,
            y: vector.y * scalar,
            z: vector.z * scalar
        )
    }
}
