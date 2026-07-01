import Foundation
import SwiftCAD
import RupaCoreTypes

public struct WorkspaceScaleRecommendation: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        case modelExceedsComfortableSpan
        case modelTooSmallForWorkspace
    }

    public var reason: Reason
    public var modelSpanMeters: Double
    public var minimumComfortableModelSpanMeters: Double
    public var maximumComfortableModelSpanMeters: Double
    public var targetVisibleSpanMeters: Double
    public var currentScale: WorkspaceScaleSnapshot
    public var recommendedScale: WorkspaceScaleSnapshot
    public var recommendedPreset: WorkspaceScalePreset

    public init(
        reason: Reason,
        modelSpanMeters: Double,
        minimumComfortableModelSpanMeters: Double,
        maximumComfortableModelSpanMeters: Double,
        targetVisibleSpanMeters: Double,
        currentScale: WorkspaceScaleSnapshot,
        recommendedScale: WorkspaceScaleSnapshot,
        recommendedPreset: WorkspaceScalePreset
    ) {
        self.reason = reason
        self.modelSpanMeters = modelSpanMeters
        self.minimumComfortableModelSpanMeters = minimumComfortableModelSpanMeters
        self.maximumComfortableModelSpanMeters = maximumComfortableModelSpanMeters
        self.targetVisibleSpanMeters = targetVisibleSpanMeters
        self.currentScale = currentScale
        self.recommendedScale = recommendedScale
        self.recommendedPreset = recommendedPreset
    }
}

public struct WorkspaceScaleRecommendationService: Sendable {
    private static let minimumComfortableSpanRatio = 0.01
    private static let maximumComfortableSpanRatio = 0.80
    private static let targetVisibleSpanMultiplier = 4.0

    public init() {}

    public func recommendation(
        for bounds: MeasurementResult.Bounds?,
        currentRuler: RulerConfiguration
    ) -> WorkspaceScaleRecommendation? {
        guard let bounds else {
            return nil
        }
        let modelSpan = bounds.maximumSpan
        guard modelSpan.isFinite, modelSpan > 0.0 else {
            return nil
        }

        let currentRuler = currentRuler.normalizedForWorkspaceScale()
        let minimumComfortableSpan = currentRuler.visibleSpanMeters
            * Self.minimumComfortableSpanRatio
        let maximumComfortableSpan = currentRuler.visibleSpanMeters
            * Self.maximumComfortableSpanRatio

        let reason: WorkspaceScaleRecommendation.Reason
        if modelSpan > maximumComfortableSpan {
            reason = .modelExceedsComfortableSpan
        } else if modelSpan < minimumComfortableSpan {
            reason = .modelTooSmallForWorkspace
        } else {
            return nil
        }

        let preset = Self.recommendedPreset(
            forModelSpanMeters: modelSpan,
            preferredUnit: currentRuler.displayUnit
        )
        let recommendedRuler = preset.rulerConfiguration.normalizedForWorkspaceScale()
        guard recommendedRuler != currentRuler else {
            return nil
        }

        return WorkspaceScaleRecommendation(
            reason: reason,
            modelSpanMeters: modelSpan,
            minimumComfortableModelSpanMeters: minimumComfortableSpan,
            maximumComfortableModelSpanMeters: maximumComfortableSpan,
            targetVisibleSpanMeters: Self.targetVisibleSpan(forModelSpanMeters: modelSpan),
            currentScale: WorkspaceScaleSnapshot(ruler: currentRuler),
            recommendedScale: WorkspaceScaleSnapshot(ruler: recommendedRuler),
            recommendedPreset: preset
        )
    }

    public func recommendation(
        for evaluatedDocument: EvaluatedDocument,
        currentRuler: RulerConfiguration
    ) -> WorkspaceScaleRecommendation? {
        var accumulator = WorkspaceScaleBoundsAccumulator()
        for mesh in evaluatedDocument.meshes.values {
            for position in mesh.positions {
                accumulator.include(position)
            }
        }
        for curves in evaluatedDocument.curves.values {
            for curve in curves {
                for point in curve.points {
                    accumulator.include(point)
                }
            }
        }
        return recommendation(
            for: accumulator.bounds,
            currentRuler: currentRuler
        )
    }

    public func diagnostics(
        for recommendation: WorkspaceScaleRecommendation?
    ) -> [EditorDiagnostic] {
        guard let recommendation else {
            return []
        }
        return [
            EditorDiagnostic(
                severity: .info,
                message: message(for: recommendation)
            ),
        ]
    }

    private func message(
        for recommendation: WorkspaceScaleRecommendation
    ) -> String {
        let modelSpan = formattedLength(
            recommendation.modelSpanMeters,
            preferredUnit: recommendation.recommendedScale.displayUnit
        )
        let visibleSpan = formattedLength(
            recommendation.recommendedScale.visibleSpanMeters,
            preferredUnit: recommendation.recommendedScale.displayUnit
        )
        switch recommendation.reason {
        case .modelExceedsComfortableSpan:
            return "Workspace scale recommendation: model span \(modelSpan) exceeds the comfortable range for the current ruler. Use \(recommendation.recommendedPreset.title) with \(visibleSpan) visible span."
        case .modelTooSmallForWorkspace:
            return "Workspace scale recommendation: model span \(modelSpan) is too small for the current ruler. Use \(recommendation.recommendedPreset.title) with \(visibleSpan) visible span."
        }
    }

    private func formattedLength(
        _ meters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return LengthDisplayText.lengthString(fromMeters: meters, unit: unit)
    }

    private static func recommendedPreset(
        forModelSpanMeters modelSpanMeters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> WorkspaceScalePreset {
        let targetSpan = targetVisibleSpan(forModelSpanMeters: modelSpanMeters)
        let candidates = presetCandidates(preferredUnit: preferredUnit)
        return candidates.first {
            $0.rulerConfiguration.normalizedForWorkspaceScale().visibleSpanMeters >= targetSpan
        } ?? candidates[candidates.count - 1]
    }

    private static func targetVisibleSpan(
        forModelSpanMeters modelSpanMeters: Double
    ) -> Double {
        let requestedSpan = modelSpanMeters * targetVisibleSpanMultiplier
        return min(
            max(requestedSpan, RulerConfiguration.visibleSpanMetersRange.lowerBound),
            RulerConfiguration.visibleSpanMetersRange.upperBound
        )
    }

    private static func presetCandidates(
        preferredUnit: LengthDisplayUnit
    ) -> [WorkspaceScalePreset] {
        if preferredUnit.isMetric {
            return [
                .microFabrication,
                .precisionMechanical,
                .productDesign,
                .roomInterior,
                .architecture,
                .sitePlanning,
            ]
        }
        return [
            .microFabrication,
            .precisionMechanical,
            .productDesign,
            .roomInterior,
            .architectureImperial,
            .sitePlanningImperial,
        ]
    }
}

private struct WorkspaceScaleBoundsAccumulator {
    private(set) var bounds: MeasurementResult.Bounds?

    mutating func include(_ point: Point3D) {
        let next = MeasurementResult.Bounds(
            minX: point.x,
            minY: point.y,
            minZ: point.z,
            maxX: point.x,
            maxY: point.y,
            maxZ: point.z
        )
        guard let current = bounds else {
            bounds = next
            return
        }
        bounds = MeasurementResult.Bounds(
            minX: min(current.minX, next.minX),
            minY: min(current.minY, next.minY),
            minZ: min(current.minZ, next.minZ),
            maxX: max(current.maxX, next.maxX),
            maxY: max(current.maxY, next.maxY),
            maxZ: max(current.maxZ, next.maxZ)
        )
    }
}
