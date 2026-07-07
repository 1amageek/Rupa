import Foundation
import RupaCore
import RupaViewportScene

struct ViewportSnapOverlayProbe: Equatable {
    var point: Point2D
    var referencePoint: Point2D?
}

struct ViewportSnapOverlayResolution: Equatable {
    var result: SnapResolutionResult?
    var failureDescription: String?

    func publishedKind(context: ViewportSnapOverlayContext) -> SnapCandidateKind? {
        ViewportSnapOverlayPolicy.publishedKind(
            result?.selectedCandidate?.kind,
            context: context
        )
    }
}

struct ViewportSnapOverlayResolutionService {
    func resolution(
        for probe: ViewportSnapOverlayProbe?,
        document: DesignDocument,
        options baseOptions: SnapResolutionOptions?,
        modifierFlags: ViewportInputModifierFlags
    ) -> ViewportSnapOverlayResolution {
        guard let probe,
              var options = baseOptions,
              options.shouldResolve(for: modifierFlags) else {
            return ViewportSnapOverlayResolution(result: nil, failureDescription: nil)
        }

        if modifierFlags.containsControl {
            options.objectTargetingOverride = .forceEnabled
        }
        options.referencePoint = probe.referencePoint

        do {
            let result = try SnapResolver().resolve(
                point: probe.point,
                in: document,
                options: options
            )
            return ViewportSnapOverlayResolution(
                result: result.selectedCandidate == nil ? nil : result,
                failureDescription: nil
            )
        } catch {
            return ViewportSnapOverlayResolution(
                result: nil,
                failureDescription: String(describing: error)
            )
        }
    }
}
