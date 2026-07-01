import SwiftCAD

public struct WorkspacePrecisionReport: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        case coordinateResolution
        case farFromOrigin
    }

    public var reason: Reason
    public var severity: EditorDiagnostic.Severity
    public var originDistanceMeters: Double
    public var maximumCoordinateMagnitudeMeters: Double
    public var coordinateResolutionMeters: Double
    public var precisionBudgetMeters: Double
    public var modelSpanMeters: Double
    public var workspaceSpanMeters: Double
    public var originToModelSpanRatio: Double
    public var modelCenter: Point3D
    public var recommendedRebaseTranslation: Vector3D?

    public init(
        reason: Reason,
        severity: EditorDiagnostic.Severity,
        originDistanceMeters: Double,
        maximumCoordinateMagnitudeMeters: Double,
        coordinateResolutionMeters: Double,
        precisionBudgetMeters: Double,
        modelSpanMeters: Double,
        workspaceSpanMeters: Double,
        originToModelSpanRatio: Double,
        modelCenter: Point3D,
        recommendedRebaseTranslation: Vector3D?
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
        self.modelCenter = modelCenter
        self.recommendedRebaseTranslation = recommendedRebaseTranslation
    }
}
