import Foundation
import RupaCoreTypes
import RupaProjectModel

public struct EvaluationSnapshotID: Codable, Equatable, Hashable, Sendable {
    public var projectID: ProjectID
    public var sourceRevision: DocumentTransactionRevision

    public init(projectID: ProjectID, sourceRevision: DocumentTransactionRevision) {
        self.projectID = projectID
        self.sourceRevision = sourceRevision
    }
}
