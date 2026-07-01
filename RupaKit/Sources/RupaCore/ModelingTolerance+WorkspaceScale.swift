import Foundation
import SwiftCAD

public extension ModelingTolerance {
    static func workspaceScaleAware(for ruler: RulerConfiguration) -> ModelingTolerance {
        let normalizedRuler = ruler.normalizedForWorkspaceScale()
        let distance = Self.clampedWorkspaceDistanceTolerance(
            normalizedRuler.visibleSpanMeters * 1.0e-9
        )
        return ModelingTolerance(
            distance: distance,
            angle: Self.standard.angle
        )
    }

    static func workspaceScaleAware(for document: DesignDocument) -> ModelingTolerance {
        workspaceScaleAware(for: document.ruler)
    }

    private static func clampedWorkspaceDistanceTolerance(_ value: Double) -> Double {
        guard value.isFinite else {
            return Self.standard.distance
        }
        return min(max(value, 1.0e-8), 1.0e-3)
    }
}
