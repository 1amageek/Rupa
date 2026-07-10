import RupaCore
import RupaViewportScene
import SwiftCAD

public struct ViewportCanvasDragSnapResolution: Equatable, Sendable {
    public var drag: ViewportModelDrag
    public var startResolution: ViewportSnapResolution
    public var endResolution: ViewportSnapResolution

    public var failureDescriptions: [String] {
        [
            startResolution.failureDescription,
            endResolution.failureDescription,
        ].compactMap(\.self)
    }
}

public struct ViewportCanvasDragSnapResolver: Sendable {
    public init() {}

    public func resolution(
        _ drag: ViewportModelDrag,
        document: DesignDocument,
        ruler: RulerConfiguration,
        snapOptions: SnapResolutionOptions?,
        axisConstraint: SketchAxisConstraint?
    ) -> ViewportCanvasDragSnapResolution {
        let resolver = ViewportSnapResolutionService()
        let startResolution = resolver.resolution(
            for: ViewportSnapQuery(point: drag.start, referencePoint: nil),
            document: document,
            ruler: ruler,
            options: snapOptions,
            modifierFlags: drag.modifierFlags
        )
        let startPoint = startResolution.resolvedPoint ?? drag.start
        let constrainedEndPoint = axisConstraint?.constrainedCanvasPoint(
            drag.end,
            from: startPoint,
            on: drag.sketchPlane
        ) ?? drag.end
        let endResolution = resolver.resolution(
            for: ViewportSnapQuery(point: constrainedEndPoint, referencePoint: startPoint),
            document: document,
            ruler: ruler,
            options: snapOptions,
            modifierFlags: drag.modifierFlags
        )
        let snappedEndPoint = endResolution.resolvedPoint ?? constrainedEndPoint
        let endPoint = axisConstraint?.constrainedCanvasPoint(
            snappedEndPoint,
            from: startPoint,
            on: drag.sketchPlane
        ) ?? snappedEndPoint
        let startWorldPoint = resolvedWorldPoint(
            for: startPoint,
            resolution: startResolution,
            fallbackPoint: drag.startWorldPoint,
            originalPoint: drag.start,
            sketchPlane: drag.sketchPlane
        )
        let endWorldPoint = resolvedWorldPoint(
            for: endPoint,
            resolution: endResolution,
            fallbackPoint: axisConstraint == nil ? drag.endWorldPoint : nil,
            originalPoint: drag.end,
            sketchPlane: drag.sketchPlane
        )

        return ViewportCanvasDragSnapResolution(
            drag: ViewportModelDrag(
                start: startPoint,
                end: endPoint,
                sketchPlane: drag.sketchPlane,
                modifierFlags: drag.modifierFlags,
                startWorldPoint: startWorldPoint,
                endWorldPoint: endWorldPoint,
                startViewRayAnchorWorldPoint: preservedViewRayAnchor(
                    drag.startViewRayAnchorWorldPoint,
                    originalPoint: drag.start,
                    resolvedPoint: startPoint,
                    resolvedWorldPoint: startWorldPoint
                ),
                endViewRayAnchorWorldPoint: preservedViewRayAnchor(
                    axisConstraint == nil ? drag.endViewRayAnchorWorldPoint : nil,
                    originalPoint: drag.end,
                    resolvedPoint: endPoint,
                    resolvedWorldPoint: endWorldPoint
                )
            ),
            startResolution: startResolution,
            endResolution: endResolution
        )
    }

    public func resolvedDrag(
        _ drag: ViewportModelDrag,
        document: DesignDocument,
        ruler: RulerConfiguration,
        snapOptions: SnapResolutionOptions?,
        axisConstraint: SketchAxisConstraint?
    ) -> ViewportModelDrag {
        resolution(
            drag,
            document: document,
            ruler: ruler,
            snapOptions: snapOptions,
            axisConstraint: axisConstraint
        ).drag
    }

    private func resolvedWorldPoint(
        for point: Point2D,
        resolution: ViewportSnapResolution,
        fallbackPoint: Point3D?,
        originalPoint: Point2D,
        sketchPlane: SketchPlane
    ) -> Point3D? {
        if let selectedWorldPoint = resolution.result?.selectedWorldPoint {
            return selectedWorldPoint
        }
        if case .plane = sketchPlane {
            do {
                let localPoint = SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
                    .localPoint(fromCanvas: point)
                return try SketchPlaneCoordinateSystem(plane: sketchPlane).point(from: localPoint)
            } catch {
                return fallbackPointIfUnchanged(fallbackPoint, originalPoint: originalPoint, resolvedPoint: point)
            }
        }
        return fallbackPointIfUnchanged(fallbackPoint, originalPoint: originalPoint, resolvedPoint: point)
    }

    private func fallbackPointIfUnchanged(
        _ fallbackPoint: Point3D?,
        originalPoint: Point2D,
        resolvedPoint: Point2D
    ) -> Point3D? {
        originalPoint == resolvedPoint ? fallbackPoint : nil
    }

    private func preservedViewRayAnchor(
        _ anchor: Point3D?,
        originalPoint: Point2D,
        resolvedPoint: Point2D,
        resolvedWorldPoint: Point3D?
    ) -> Point3D? {
        guard resolvedWorldPoint == nil,
              originalPoint == resolvedPoint else {
            return nil
        }
        return anchor
    }
}
