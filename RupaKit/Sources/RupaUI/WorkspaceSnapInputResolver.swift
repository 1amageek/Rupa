import RupaCore
import RupaRendering
import RupaViewportScene

struct WorkspaceSnapInputResolution {
    var input: SnappedModelInput
    var didAttemptResolution: Bool
    var failureMessage: String?
}

struct WorkspaceSnapInputResolver {
    func resolve(
        _ point: Point2D,
        in document: DesignDocument,
        ruler: RulerConfiguration,
        options: SnapResolutionOptions,
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> WorkspaceSnapInputResolution {
        let resolution = ViewportSnapResolutionService().resolution(
            for: ViewportSnapQuery(point: point, referencePoint: referencePoint),
            document: document,
            ruler: ruler,
            options: options,
            modifierFlags: modifierFlags
        )
        if let result = resolution.result {
            return WorkspaceSnapInputResolution(
                input: SnappedModelInput(
                    point: result.resolvedPoint,
                    worldPoint: result.selectedWorldPoint
                ),
                didAttemptResolution: resolution.attemptedResolution,
                failureMessage: nil
            )
        }
        return WorkspaceSnapInputResolution(
            input: SnappedModelInput(point: point),
            didAttemptResolution: resolution.attemptedResolution,
            failureMessage: resolution.failureDescription
        )
    }
}
