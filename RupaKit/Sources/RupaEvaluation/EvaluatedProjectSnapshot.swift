import RupaCoreTypes
import RupaProjectModel

public struct EvaluatedProjectSnapshot: Sendable {
    public let id: EvaluationSnapshotID
    public let projectID: ProjectID
    public let occurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot]

    public init(
        id: EvaluationSnapshotID,
        projectID: ProjectID,
        occurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot]
    ) {
        self.id = id
        self.projectID = projectID
        self.occurrences = occurrences
    }
}
