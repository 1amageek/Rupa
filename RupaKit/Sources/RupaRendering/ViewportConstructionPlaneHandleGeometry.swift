import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportConstructionPlaneHandleGeometry: Sendable {
    func targets(
        document: DesignDocument,
        ruler: RulerConfiguration,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportConstructionPlaneHandleTarget] {
        let ruler = ruler.normalizedForWorkspaceScale()
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
        guard let projectedOrigin = layout.projectedPoint(coordinateSystem.origin)?.point,
              let projectedNormalEnd = layout.projectedPoint(normalEnd)?.point else {
            return nil
        }

        return ViewportConstructionPlaneHandlePlane(
            constructionPlaneID: constructionPlaneID,
            sceneNodeID: sceneNodeID,
            origin: coordinateSystem.origin,
            normal: coordinateSystem.normal,
            normalEnd: normalEnd,
            corners: corners,
            projectedOrigin: projectedOrigin,
            projectedNormalEnd: projectedNormalEnd
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
