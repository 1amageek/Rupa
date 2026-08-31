import Foundation
import RupaCore
import RupaCoreTypes

/// Exact project coordinate supplied once by a semantic Agent request.
public struct AgentProjectAuthorityCoordinate: Codable, Equatable, Sendable {
    public let projectID: ProjectID
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let workspaceRevision: WorkspaceRevision

    private enum CodingKeys: String, CodingKey {
        case projectID
        case documentGeneration
        case transactionRevision
        case publicationSequence
        case workspaceRevision
    }

    public init(
        projectID: ProjectID,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        workspaceRevision: WorkspaceRevision
    ) {
        self.projectID = projectID
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.workspaceRevision = workspaceRevision
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [
                "projectID", "documentGeneration", "transactionRevision",
                "publicationSequence", "workspaceRevision",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projectID: try container.decode(ProjectID.self, forKey: .projectID),
            documentGeneration: try container.decode(DocumentGeneration.self, forKey: .documentGeneration),
            transactionRevision: try container.decode(DocumentTransactionRevision.self, forKey: .transactionRevision),
            publicationSequence: try container.decode(UInt64.self, forKey: .publicationSequence),
            workspaceRevision: try container.decode(WorkspaceRevision.self, forKey: .workspaceRevision)
        )
    }
}
