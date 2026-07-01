import Foundation
import SwiftCAD
import RupaCoreTypes

public struct WorkspacePrecisionDiagnosticService: Sendable {
    public typealias Reason = WorkspacePrecisionReport.Reason
    public typealias Report = WorkspacePrecisionReport

    public init() {}

    public func report(
        for bounds: MeasurementResult.Bounds?,
        ruler: RulerConfiguration,
        tolerance: ModelingTolerance? = nil
    ) -> Report? {
        guard let bounds else {
            return nil
        }

        let normalizedRuler = ruler.normalizedForWorkspaceScale()
        let modelingTolerance = tolerance ?? .workspaceScaleAware(for: normalizedRuler)
        let coordinateMagnitude = bounds.maximumAbsoluteCoordinate
        guard coordinateMagnitude.isFinite, coordinateMagnitude > 0.0 else {
            return nil
        }
        let originDistance = bounds.maximumDistanceFromOrigin
        guard originDistance.isFinite, originDistance > 0.0 else {
            return nil
        }

        let modelSpan = max(bounds.maximumSpan, normalizedRuler.minorTickMeters)
        guard modelSpan.isFinite, modelSpan > 0.0 else {
            return nil
        }

        let coordinateResolution = coordinateMagnitude.ulp
        let precisionBudget = max(modelingTolerance.distance * 0.1, Double.leastNonzeroMagnitude)
        let originRatio = originDistance / modelSpan
        let workspaceSpan = normalizedRuler.visibleSpanMeters
        let modelCenter = bounds.center
        let recommendedRebaseTranslation = Self.recommendedRebaseTranslation(
            center: modelCenter,
            modelSpanMeters: modelSpan,
            ruler: normalizedRuler,
            tolerance: modelingTolerance
        )

        if coordinateResolution >= precisionBudget {
            return Report(
                reason: .coordinateResolution,
                severity: .warning,
                originDistanceMeters: originDistance,
                maximumCoordinateMagnitudeMeters: coordinateMagnitude,
                coordinateResolutionMeters: coordinateResolution,
                precisionBudgetMeters: precisionBudget,
                modelSpanMeters: modelSpan,
                workspaceSpanMeters: workspaceSpan,
                originToModelSpanRatio: originRatio,
                modelCenter: modelCenter,
                recommendedRebaseTranslation: recommendedRebaseTranslation
            )
        }

        if originDistance >= workspaceSpan * 100.0,
           originRatio >= 1.0e6 {
            return Report(
                reason: .farFromOrigin,
                severity: .info,
                originDistanceMeters: originDistance,
                maximumCoordinateMagnitudeMeters: coordinateMagnitude,
                coordinateResolutionMeters: coordinateResolution,
                precisionBudgetMeters: precisionBudget,
                modelSpanMeters: modelSpan,
                workspaceSpanMeters: workspaceSpan,
                originToModelSpanRatio: originRatio,
                modelCenter: modelCenter,
                recommendedRebaseTranslation: recommendedRebaseTranslation
            )
        }

        return nil
    }

    public func diagnostics(
        for bounds: MeasurementResult.Bounds?,
        ruler: RulerConfiguration,
        displayUnit: LengthDisplayUnit,
        tolerance: ModelingTolerance? = nil
    ) -> [EditorDiagnostic] {
        diagnostics(
            for: report(for: bounds, ruler: ruler, tolerance: tolerance),
            displayUnit: displayUnit
        )
    }

    public func diagnostics(
        for report: Report?,
        displayUnit: LengthDisplayUnit
    ) -> [EditorDiagnostic] {
        guard let report else {
            return []
        }
        return [
            EditorDiagnostic(
                severity: report.severity,
                message: message(for: report, displayUnit: displayUnit)
            ),
        ]
    }

    public func diagnostics(
        for evaluatedDocument: EvaluatedDocument,
        ruler: RulerConfiguration,
        displayUnit: LengthDisplayUnit,
        tolerance: ModelingTolerance? = nil
    ) -> [EditorDiagnostic] {
        var accumulator = WorkspacePrecisionBoundsAccumulator()
        for mesh in evaluatedDocument.meshes.values {
            for position in mesh.positions {
                accumulator.include(position)
            }
        }
        return diagnostics(
            for: accumulator.bounds,
            ruler: ruler,
            displayUnit: displayUnit,
            tolerance: tolerance
        )
    }

    private func message(
        for report: Report,
        displayUnit: LengthDisplayUnit
    ) -> String {
        let coordinate = formattedLength(
            report.originDistanceMeters,
            preferredUnit: displayUnit
        )
        let resolution = formattedLength(
            report.coordinateResolutionMeters,
            preferredUnit: displayUnit
        )
        let budget = formattedLength(
            report.precisionBudgetMeters,
            preferredUnit: displayUnit
        )
        let span = formattedLength(
            report.modelSpanMeters,
            preferredUnit: displayUnit
        )

        switch report.reason {
        case .coordinateResolution:
            return "Workspace precision warning: geometry reaches \(coordinate) from origin; floating-point coordinate resolution at the largest axis value is \(resolution), above the precision budget \(budget). Rebase to a local origin before precise CAD edits."
        case .farFromOrigin:
            return "Workspace precision notice: geometry reaches \(coordinate) from origin while model span is \(span). Use a local origin or rebase workflow for precise CAD edits."
        }
    }

    private func formattedLength(
        _ meters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return LengthDisplayText.lengthString(fromMeters: meters, unit: unit)
    }

    private static func recommendedRebaseTranslation(
        center: Point3D,
        modelSpanMeters: Double,
        ruler: RulerConfiguration,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        let threshold = max(
            modelSpanMeters * 1_000.0,
            ruler.majorTickMeters,
            ruler.visibleSpanMeters * 0.5
        )
        let vector = Vector3D(
            x: recommendedAxisTranslation(center.x, threshold: threshold),
            y: recommendedAxisTranslation(center.y, threshold: threshold),
            z: recommendedAxisTranslation(center.z, threshold: threshold)
        )
        guard vector.isFinite, vector.length > tolerance.distance else {
            return nil
        }
        return vector
    }

    private static func recommendedAxisTranslation(
        _ center: Double,
        threshold: Double
    ) -> Double {
        guard center.isFinite, threshold.isFinite, abs(center) >= threshold else {
            return 0.0
        }
        return -center
    }
}

private struct WorkspacePrecisionBoundsAccumulator {
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
