import Foundation
import SwiftCAD
import RupaCoreTypes

public struct WorkspacePrecisionDiagnosticService: Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        case coordinateResolution
        case farFromOrigin
    }

    public struct Report: Codable, Equatable, Sendable {
        public var reason: Reason
        public var severity: EditorDiagnostic.Severity
        public var originDistanceMeters: Double
        public var maximumCoordinateMagnitudeMeters: Double
        public var coordinateResolutionMeters: Double
        public var precisionBudgetMeters: Double
        public var modelSpanMeters: Double
        public var workspaceSpanMeters: Double
        public var originToModelSpanRatio: Double

        public init(
            reason: Reason,
            severity: EditorDiagnostic.Severity,
            originDistanceMeters: Double,
            maximumCoordinateMagnitudeMeters: Double,
            coordinateResolutionMeters: Double,
            precisionBudgetMeters: Double,
            modelSpanMeters: Double,
            workspaceSpanMeters: Double,
            originToModelSpanRatio: Double
        ) {
            self.reason = reason
            self.severity = severity
            self.originDistanceMeters = originDistanceMeters
            self.maximumCoordinateMagnitudeMeters = maximumCoordinateMagnitudeMeters
            self.coordinateResolutionMeters = coordinateResolutionMeters
            self.precisionBudgetMeters = precisionBudgetMeters
            self.modelSpanMeters = modelSpanMeters
            self.workspaceSpanMeters = workspaceSpanMeters
            self.originToModelSpanRatio = originToModelSpanRatio
        }
    }

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
                originToModelSpanRatio: originRatio
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
                originToModelSpanRatio: originRatio
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
        guard let report = report(for: bounds, ruler: ruler, tolerance: tolerance) else {
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

private extension MeasurementResult.Bounds {
    var maximumAbsoluteCoordinate: Double {
        [
            minX,
            minY,
            minZ,
            maxX,
            maxY,
            maxZ,
        ].map(abs).max() ?? 0.0
    }

    var maximumSpan: Double {
        max(abs(sizeX), abs(sizeY), abs(sizeZ))
    }

    var maximumDistanceFromOrigin: Double {
        [
            hypot(hypot(minX, minY), minZ),
            hypot(hypot(minX, minY), maxZ),
            hypot(hypot(minX, maxY), minZ),
            hypot(hypot(minX, maxY), maxZ),
            hypot(hypot(maxX, minY), minZ),
            hypot(hypot(maxX, minY), maxZ),
            hypot(hypot(maxX, maxY), minZ),
            hypot(hypot(maxX, maxY), maxZ),
        ].max() ?? 0.0
    }
}
