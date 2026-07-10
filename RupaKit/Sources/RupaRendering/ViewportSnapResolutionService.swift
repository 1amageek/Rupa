import Foundation
import RupaCore
import RupaViewportScene

public struct ViewportSnapQuery: Equatable, Sendable {
    public var point: Point2D
    public var referencePoint: Point2D?

    public init(
        point: Point2D,
        referencePoint: Point2D? = nil
    ) {
        self.point = point
        self.referencePoint = referencePoint
    }
}

public struct ViewportSnapResolution: Equatable, Sendable {
    public var attemptedResolution: Bool
    public var result: SnapResolutionResult?
    public var failureDescription: String?

    public var resolvedPoint: Point2D? {
        result?.resolvedPoint
    }

    func publishedKind(context: ViewportSnapOverlayContext) -> SnapCandidateKind? {
        ViewportSnapOverlayPolicy.publishedKind(
            result?.selectedCandidate?.kind,
            context: context
        )
    }
}

public struct ViewportSnapResolutionService: Sendable {
    public init() {}

    public func resolution(
        for query: ViewportSnapQuery?,
        document: DesignDocument,
        ruler: RulerConfiguration,
        options baseOptions: SnapResolutionOptions?,
        modifierFlags: ViewportInputModifierFlags
    ) -> ViewportSnapResolution {
        guard let query,
              var options = baseOptions,
              options.shouldResolve(for: modifierFlags) else {
            return ViewportSnapResolution(
                attemptedResolution: false,
                result: nil,
                failureDescription: nil
            )
        }

        if modifierFlags.containsControl {
            options.objectTargetingOverride = .forceEnabled
        }
        options.referencePoint = query.referencePoint

        do {
            let result = try SnapResolver().resolve(
                point: query.point,
                in: document,
                ruler: ruler,
                options: options
            )
            return ViewportSnapResolution(
                attemptedResolution: true,
                result: result.selectedCandidate == nil ? nil : result,
                failureDescription: nil
            )
        } catch {
            return ViewportSnapResolution(
                attemptedResolution: true,
                result: nil,
                failureDescription: String(describing: error)
            )
        }
    }
}
