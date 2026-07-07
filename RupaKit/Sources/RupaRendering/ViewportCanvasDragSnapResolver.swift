import RupaCore
import RupaViewportScene
import SwiftCAD

public struct ViewportCanvasDragSnapResolver: Sendable {
    public init() {}

    public func resolvedDrag(
        _ drag: ViewportModelDrag,
        document: DesignDocument,
        snapOptions: SnapResolutionOptions?,
        axisConstraint: SketchAxisConstraint?
    ) -> ViewportModelDrag {
        let startPoint = resolvedPoint(
            drag.start,
            document: document,
            snapOptions: snapOptions,
            referencePoint: nil,
            modifierFlags: drag.modifierFlags
        )
        let constrainedEndPoint = axisConstraint?.constrainedCanvasPoint(
            drag.end,
            from: startPoint,
            on: drag.sketchPlane
        ) ?? drag.end
        let snappedEndPoint = resolvedPoint(
            constrainedEndPoint,
            document: document,
            snapOptions: snapOptions,
            referencePoint: startPoint,
            modifierFlags: drag.modifierFlags
        )
        let endPoint = axisConstraint?.constrainedCanvasPoint(
            snappedEndPoint,
            from: startPoint,
            on: drag.sketchPlane
        ) ?? snappedEndPoint

        return ViewportModelDrag(
            start: startPoint,
            end: endPoint,
            sketchPlane: drag.sketchPlane,
            modifierFlags: drag.modifierFlags,
            startViewRayAnchorWorldPoint: drag.startViewRayAnchorWorldPoint
        )
    }

    private func resolvedPoint(
        _ point: Point2D,
        document: DesignDocument,
        snapOptions: SnapResolutionOptions?,
        referencePoint: Point2D?,
        modifierFlags: ViewportInputModifierFlags
    ) -> Point2D {
        guard var snapOptions,
              shouldResolve(snapOptions, modifierFlags: modifierFlags) else {
            return point
        }
        if modifierFlags.containsControl {
            snapOptions.objectTargetingOverride = .forceEnabled
        }
        snapOptions.referencePoint = referencePoint
        do {
            return try SnapResolver().resolve(
                point: point,
                in: document,
                options: snapOptions
            ).resolvedPoint
        } catch {
            return point
        }
    }

    private func shouldResolve(
        _ snapOptions: SnapResolutionOptions,
        modifierFlags: ViewportInputModifierFlags
    ) -> Bool {
        snapOptions.usesGrid
            || snapOptions.usesObjects
            || snapOptions.usesConstructionPlaneProjection
            || snapOptions.objectTargetingOverride == .forceEnabled
            || modifierFlags.containsControl
            || !snapOptions.referenceLineAnchors.isEmpty
    }
}
