import Foundation
import RupaCoreTypes

struct CADCaseRegressionRecord: Codable, Equatable, Sendable {
    static let schemaVersion = "t12.case-regression.v1"

    let schemaVersion: String
    let caseID: CADBenchmarkCaseID
    let category: CADBenchmarkCategory
    let outcome: CADCaseOutcome
    let capabilityDecisionCorrect: Bool
    let route: Route
    let counts: Counts
    let caseContractDigest: String
    let oracleDisposition: OracleDisposition
    let digest: String

    init(
        caseID: CADBenchmarkCaseID,
        outcome: CADCaseOutcome,
        capabilityDecisionCorrect: Bool,
        route: Route,
        counts: Counts,
        caseContractDigest: String,
        oracleDisposition: OracleDisposition
    ) throws {
        guard let category = caseID.category else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        self.schemaVersion = Self.schemaVersion
        self.caseID = caseID
        self.category = category
        self.outcome = outcome
        self.capabilityDecisionCorrect = capabilityDecisionCorrect
        self.route = route
        self.counts = counts
        self.caseContractDigest = caseContractDigest
        self.oracleDisposition = oracleDisposition
        self.digest = try Self.computeDigest(Payload(
            schemaVersion: Self.schemaVersion,
            caseID: caseID,
            category: category,
            outcome: outcome,
            capabilityDecisionCorrect: capabilityDecisionCorrect,
            route: route,
            counts: counts,
            caseContractDigest: caseContractDigest,
            oracleDisposition: oracleDisposition
        ))
        try validate()
    }

    func validate() throws {
        try caseID.validate()
        guard schemaVersion == Self.schemaVersion,
              category == caseID.category,
              caseContractDigest.count == 64,
              route.cleanupCompleted,
              route.remainingRegistrationCount == 0,
              route.documentGenerationDelta >= 0,
              route.transactionRevisionDelta >= 0,
              route.publicationSequenceDelta >= 0,
              counts.action >= 0,
              counts.command >= 0,
              counts.read >= 0 else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        switch oracleDisposition {
        case .accepted:
            guard outcome == .realized,
                  route.didPublish,
                  capabilityDecisionCorrect else {
                throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
            }
        case .expectedUnsupported:
            guard outcome == .expectedUnsupported,
                  category == .sphere,
                  route.didPublish == false,
                  route.publicationSequenceDelta == 0,
                  counts.command == 0,
                  counts.sourceMutation == 0,
                  capabilityDecisionCorrect else {
                throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
            }
        case .rejected:
            guard outcome != .realized,
                  outcome != .expectedUnsupported,
                  capabilityDecisionCorrect == false else {
                throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
            }
        }
        let recomputed = try Self.computeDigest(Payload(
            schemaVersion: schemaVersion,
            caseID: caseID,
            category: category,
            outcome: outcome,
            capabilityDecisionCorrect: capabilityDecisionCorrect,
            route: route,
            counts: counts,
            caseContractDigest: caseContractDigest,
            oracleDisposition: oracleDisposition
        ))
        guard recomputed == digest else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
    }

    struct Route: Codable, Equatable, Sendable {
        let didPublish: Bool
        let documentGenerationDelta: Int64
        let transactionRevisionDelta: Int64
        let publicationSequenceDelta: Int64
        let workspaceRevisionChanged: Bool
        let cleanupCompleted: Bool
        let remainingRegistrationCount: Int
    }

    struct Counts: Codable, Equatable, Sendable {
        let action: Int
        let command: Int
        let read: Int
        let entity: Int?
        let feature: Int?
        let sceneNode: Int?
        let body: Int?
        let face: Int?
        let edge: Int?
        let vertex: Int?
        let evaluationPass: UInt64?
        let historyEntry: Int?
        let capabilityRequest: Int?
        let sourceMutation: Int?
    }

    enum OracleDisposition: String, Codable, Equatable, Sendable {
        case accepted
        case expectedUnsupported
        case rejected
    }

    private struct Payload: Codable {
        let schemaVersion: String
        let caseID: CADBenchmarkCaseID
        let category: CADBenchmarkCategory
        let outcome: CADCaseOutcome
        let capabilityDecisionCorrect: Bool
        let route: Route
        let counts: Counts
        let caseContractDigest: String
        let oracleDisposition: OracleDisposition
    }

    private static func computeDigest(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return StableDigest.sha256Hex(for: try encoder.encode(payload))
    }
}
