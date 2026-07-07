import RupaCore
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
        options: SnapResolutionOptions,
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> WorkspaceSnapInputResolution {
        guard options.shouldResolve(for: modifierFlags) else {
            return WorkspaceSnapInputResolution(
                input: SnappedModelInput(point: point),
                didAttemptResolution: false,
                failureMessage: nil
            )
        }

        var resolvedOptions = options
        if modifierFlags.containsControl {
            resolvedOptions.objectTargetingOverride = .forceEnabled
        }
        resolvedOptions.referencePoint = referencePoint

        do {
            let result = try SnapResolver().resolve(
                point: point,
                in: document,
                options: resolvedOptions
            )
            return WorkspaceSnapInputResolution(
                input: SnappedModelInput(
                    point: result.resolvedPoint,
                    worldPoint: result.selectedWorldPoint
                ),
                didAttemptResolution: true,
                failureMessage: nil
            )
        } catch {
            return WorkspaceSnapInputResolution(
                input: SnappedModelInput(point: point),
                didAttemptResolution: true,
                failureMessage: error.localizedDescription
            )
        }
    }
}
