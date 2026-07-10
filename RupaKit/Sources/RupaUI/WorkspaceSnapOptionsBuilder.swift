import RupaCore
import RupaRendering

struct WorkspaceSnapOptionsBuilder {
    var isGridSnapEnabled: Bool
    var isObjectTargetingEnabled: Bool
    var isConstructionPlaneSnapEnabled: Bool
    var constructionPlane: SketchPlane?
    var overrideState: WorkspaceSnapOverrideState
    var referenceLineAnchors: [SketchReferenceLineAnchor]

    func options(
        referencePoint: Point2D? = nil,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) -> SnapResolutionOptions {
        SnapResolutionOptions(
            usesGrid: isGridSnapEnabled,
            usesObjects: isObjectTargetingEnabled,
            objectTargetingOverride: overrideState.objectTargetingOverride(for: modifierFlags),
            suppressedCandidateKinds: overrideState.suppressedCandidateKinds,
            constructionPlane: isConstructionPlaneSnapEnabled ? constructionPlane : nil,
            maximumCandidateCount: 16,
            referencePoint: referencePoint,
            referenceLineAnchors: referenceLineAnchors
        )
    }
}
