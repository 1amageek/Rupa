import RupaCore
import RupaViewportScene
import SwiftCAD

struct ViewportCanvasDragSnapResolution: Equatable {
    var drag: ViewportModelDrag
    var startResolution: ViewportSnapResolution
    var endResolution: ViewportSnapResolution

    var failureDescriptions: [String] {
        [
            startResolution.failureDescription,
            endResolution.failureDescription,
        ].compactMap(\.self)
    }
}

public struct ViewportCanvasDragSnapResolver: Sendable {
    public init() {}

    func resolution(
        _ drag: ViewportModelDrag,
        document: DesignDocument,
        snapOptions: SnapResolutionOptions?,
        axisConstraint: SketchAxisConstraint?
    ) -> ViewportCanvasDragSnapResolution {
        let resolver = ViewportSnapResolutionService()
        let startResolution = resolver.resolution(
            for: ViewportSnapQuery(point: drag.start, referencePoint: nil),
            document: document,
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
            options: snapOptions,
            modifierFlags: drag.modifierFlags
        )
        let snappedEndPoint = endResolution.resolvedPoint ?? constrainedEndPoint
        let endPoint = axisConstraint?.constrainedCanvasPoint(
            snappedEndPoint,
            from: startPoint,
            on: drag.sketchPlane
        ) ?? snappedEndPoint

        return ViewportCanvasDragSnapResolution(
            drag: ViewportModelDrag(
                start: startPoint,
                end: endPoint,
                sketchPlane: drag.sketchPlane,
                modifierFlags: drag.modifierFlags,
                startViewRayAnchorWorldPoint: drag.startViewRayAnchorWorldPoint
            ),
            startResolution: startResolution,
            endResolution: endResolution
        )
    }

    public func resolvedDrag(
        _ drag: ViewportModelDrag,
        document: DesignDocument,
        snapOptions: SnapResolutionOptions?,
        axisConstraint: SketchAxisConstraint?
    ) -> ViewportModelDrag {
        resolution(
            drag,
            document: document,
            snapOptions: snapOptions,
            axisConstraint: axisConstraint
        ).drag
    }
}
