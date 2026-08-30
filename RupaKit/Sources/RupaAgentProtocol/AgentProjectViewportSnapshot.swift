import RupaCoreTypes
import RupaGeometry

/// The exact visible viewport projection captured with one project authority coordinate.
public struct AgentProjectViewportSnapshot: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let evaluationSnapshotID: EvaluationSnapshotID
    public let items: [AgentProjectViewportItem]
    public let worldBounds: GeometryBounds3D?
    public let triangleCount: UInt64
    public let copyTelemetry: GeometryCopyTelemetry

    public init(
        coordinates: AgentProjectViewCoordinates,
        evaluationSnapshotID: EvaluationSnapshotID,
        items: [AgentProjectViewportItem],
        worldBounds: GeometryBounds3D?,
        triangleCount: UInt64,
        copyTelemetry: GeometryCopyTelemetry
    ) {
        self.coordinates = coordinates
        self.evaluationSnapshotID = evaluationSnapshotID
        self.items = items
        self.worldBounds = worldBounds
        self.triangleCount = triangleCount
        self.copyTelemetry = copyTelemetry
    }
}
