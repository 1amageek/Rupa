import RupaCore

public extension SnapResolutionOptions {
    func shouldResolve(for modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()) -> Bool {
        usesGrid
            || usesObjects
            || usesConstructionPlaneProjection
            || objectTargetingOverride == .forceEnabled
            || modifierFlags.containsControl
            || !referenceLineAnchors.isEmpty
    }
}
