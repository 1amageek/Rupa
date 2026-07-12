import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel

public struct UniversalViewportScene: Equatable, Sendable {
    public let snapshotID: EvaluationSnapshotID
    public let projectID: ProjectID
    public let items: [UniversalViewportSceneItem]

    public init(
        snapshotID: EvaluationSnapshotID,
        projectID: ProjectID,
        items: [UniversalViewportSceneItem]
    ) {
        self.snapshotID = snapshotID
        self.projectID = projectID
        self.items = items
    }

    public var worldBounds: GeometryBounds3D? {
        guard let first = items.first else {
            return nil
        }
        var minimum = first.worldBounds.minimum
        var maximum = first.worldBounds.maximum
        for item in items.dropFirst() {
            minimum.x = min(minimum.x, item.worldBounds.minimum.x)
            minimum.y = min(minimum.y, item.worldBounds.minimum.y)
            minimum.z = min(minimum.z, item.worldBounds.minimum.z)
            maximum.x = max(maximum.x, item.worldBounds.maximum.x)
            maximum.y = max(maximum.y, item.worldBounds.maximum.y)
            maximum.z = max(maximum.z, item.worldBounds.maximum.z)
        }
        do {
            return try GeometryBounds3D(minimum: minimum, maximum: maximum)
        } catch {
            return nil
        }
    }
}
