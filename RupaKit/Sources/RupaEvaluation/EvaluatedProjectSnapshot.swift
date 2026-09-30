import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

public struct EvaluatedProjectSnapshot: Sendable {
    public let id: EvaluationSnapshotID
    public let projectID: ProjectID
    public let occurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot]
    public let copyTelemetry: GeometryCopyTelemetry

    public init(
        id: EvaluationSnapshotID,
        projectID: ProjectID,
        occurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot],
        copyTelemetry: GeometryCopyTelemetry
    ) {
        self.id = id
        self.projectID = projectID
        self.occurrences = occurrences
        self.copyTelemetry = copyTelemetry
    }
}

extension EvaluatedProjectSnapshot {
    /// This evaluation named as the unpublished candidate `candidate`: the same content under an
    /// identity no other candidate of the same proposed revision shares.
    public func identifyingCandidate(_ candidate: UUID) -> EvaluatedProjectSnapshot {
        EvaluatedProjectSnapshot(
            id: EvaluationSnapshotID(
                projectID: id.projectID,
                purpose: id.purpose,
                sourceRevision: id.sourceRevision,
                candidate: candidate
            ),
            projectID: projectID,
            occurrences: occurrences,
            copyTelemetry: copyTelemetry
        )
    }
}
