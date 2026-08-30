import RupaCore
@testable import RupaAgentCADBenchmark

struct CADDirectReferenceProjection: Equatable {
    let caseID: CADBenchmarkCaseID
    let outcome: CADCaseOutcome
    let route: CADCaseRegressionRecord.Route
    let counts: CADCaseRegressionRecord.Counts

    @MainActor
    static func run(caseID: CADBenchmarkCaseID) async throws -> CADDirectReferenceProjection {
        guard let category = caseID.category else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        let evidence: CADActivatedCaseEvidence = switch category {
        case .line:
            .line(try await CADLineCaseRunner(
                case: CADActivatedLineCase(caseID: caseID)
            ).runReference())
        case .rectangle:
            .rectangle(try await CADRectangleCaseRunner(
                case: CADActivatedRectangleCase(caseID: caseID)
            ).runReference())
        case .circle:
            .circle(try await CADCircleCaseRunner(
                case: CADActivatedCircleCase(caseID: caseID)
            ).runReference())
        case .angle:
            .angle(try await CADAngleCaseRunner(
                case: CADActivatedAngleCase(caseID: caseID)
            ).runReference())
        case .box:
            .box(try await CADBoxCaseRunner(
                case: CADActivatedBoxCase(caseID: caseID)
            ).runReference())
        case .cylinder:
            .cylinder(try await CADCylinderCaseRunner(
                case: CADActivatedCylinderCase(caseID: caseID)
            ).runReference())
        case .constraint:
            .constraint(try await CADConstraintCaseRunner(
                case: CADActivatedConstraintCase(caseID: caseID)
            ).runReference())
        case .transform:
            .transform(try await CADTransformCaseRunner(
                case: CADActivatedTransformCase(caseID: caseID).preparedCase
            ).runReference())
        case .compound:
            .compound(try await CADCompoundCaseRunner(
                case: CADActivatedCompoundCase(caseID: caseID)
            ).runReference())
        case .sphere:
            .sphere(try await CADSphereCaseRunner(
                case: CADActivatedSphereCase(caseID: caseID)
            ).runReference())
        }
        try evidence.validate()
        return try CADDirectReferenceProjection(evidence: evidence)
    }

    private init(evidence: CADActivatedCaseEvidence) throws {
        caseID = evidence.caseID
        outcome = evidence.outcome
        switch evidence {
        case .line(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.commonCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount
            )
        case .rectangle(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.commonCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount
            )
        case .circle(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.commonCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount
            )
        case .angle(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.commonCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount
            )
        case .box(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.solidCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount,
                face: result.telemetry.faceCount,
                edge: result.telemetry.edgeCount,
                vertex: result.telemetry.vertexCount
            )
        case .cylinder(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.solidCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount,
                face: result.telemetry.faceCount,
                edge: result.telemetry.edgeCount,
                vertex: result.telemetry.vertexCount
            )
        case .constraint(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = Self.commonCounts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                body: result.telemetry.bodyCount
            )
        case .transform(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = CADCaseRegressionRecord.Counts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: nil,
                feature: result.telemetry.featureCount,
                sceneNode: result.telemetry.sceneNodeCount,
                body: result.telemetry.bodyCount,
                face: nil,
                edge: nil,
                vertex: nil,
                evaluationPass: nil,
                historyEntry: nil,
                capabilityRequest: nil,
                sourceMutation: nil
            )
        case .compound(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = CADCaseRegressionRecord.Counts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                sceneNode: nil,
                body: result.telemetry.bodyCount,
                face: result.telemetry.faceCount,
                edge: result.telemetry.edgeCount,
                vertex: result.telemetry.vertexCount,
                evaluationPass: result.routeEvidence.evaluationPassCount,
                historyEntry: result.routeEvidence.historyEntryCount,
                capabilityRequest: nil,
                sourceMutation: nil
            )
        case .sphere(let result):
            route = try Self.route(result.routeEvidence, caseID: result.caseID)
            counts = CADCaseRegressionRecord.Counts(
                action: result.telemetry.actionCount,
                command: result.telemetry.commandCount,
                read: result.telemetry.readCount,
                entity: result.telemetry.entityCount,
                feature: result.telemetry.featureCount,
                sceneNode: nil,
                body: result.telemetry.bodyCount,
                face: nil,
                edge: nil,
                vertex: nil,
                evaluationPass: nil,
                historyEntry: nil,
                capabilityRequest: result.telemetry.capabilityRequestCount,
                sourceMutation: result.telemetry.sourceMutationCount
            )
        }
    }

    private static func route<Route: CADDirectRouteEvidence>(
        _ source: Route,
        caseID: CADBenchmarkCaseID
    ) throws -> CADCaseRegressionRecord.Route {
        CADCaseRegressionRecord.Route(
            didPublish: source.didPublish,
            documentGenerationDelta: try delta(
                final: source.finalDocumentGeneration.value,
                initial: source.initialDocumentGeneration.value,
                caseID: caseID
            ),
            transactionRevisionDelta: try delta(
                final: source.finalTransactionRevision.value,
                initial: source.initialTransactionRevision.value,
                caseID: caseID
            ),
            publicationSequenceDelta: try delta(
                final: source.finalPublicationSequence,
                initial: source.initialPublicationSequence,
                caseID: caseID
            ),
            workspaceRevisionChanged: source.finalWorkspaceRevision != source.initialWorkspaceRevision,
            cleanupCompleted: source.cleanupCompleted,
            remainingRegistrationCount: source.remainingRegistrationCount
        )
    }

    private static func commonCounts(
        action: Int,
        command: Int,
        read: Int,
        entity: Int,
        feature: Int,
        body: Int
    ) -> CADCaseRegressionRecord.Counts {
        CADCaseRegressionRecord.Counts(
            action: action,
            command: command,
            read: read,
            entity: entity,
            feature: feature,
            sceneNode: nil,
            body: body,
            face: nil,
            edge: nil,
            vertex: nil,
            evaluationPass: nil,
            historyEntry: nil,
            capabilityRequest: nil,
            sourceMutation: nil
        )
    }

    private static func solidCounts(
        action: Int,
        command: Int,
        read: Int,
        entity: Int,
        feature: Int,
        body: Int,
        face: Int,
        edge: Int,
        vertex: Int
    ) -> CADCaseRegressionRecord.Counts {
        CADCaseRegressionRecord.Counts(
            action: action,
            command: command,
            read: read,
            entity: entity,
            feature: feature,
            sceneNode: nil,
            body: body,
            face: face,
            edge: edge,
            vertex: vertex,
            evaluationPass: nil,
            historyEntry: nil,
            capabilityRequest: nil,
            sourceMutation: nil
        )
    }

    private static func delta(
        final: UInt64,
        initial: UInt64,
        caseID: CADBenchmarkCaseID
    ) throws -> Int64 {
        guard final >= initial,
              let delta = Int64(exactly: final - initial) else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        return delta
    }
}

private protocol CADDirectRouteEvidence {
    var initialDocumentGeneration: DocumentGeneration { get }
    var finalDocumentGeneration: DocumentGeneration { get }
    var initialTransactionRevision: DocumentTransactionRevision { get }
    var finalTransactionRevision: DocumentTransactionRevision { get }
    var initialPublicationSequence: UInt64 { get }
    var finalPublicationSequence: UInt64 { get }
    var initialWorkspaceRevision: WorkspaceRevision { get }
    var finalWorkspaceRevision: WorkspaceRevision { get }
    var didPublish: Bool { get }
    var cleanupCompleted: Bool { get }
    var remainingRegistrationCount: Int { get }
}

extension CADLineRouteEvidence: CADDirectRouteEvidence {}
extension CADRectangleRouteEvidence: CADDirectRouteEvidence {}
extension CADCircleRouteEvidence: CADDirectRouteEvidence {}
extension CADAngleRouteEvidence: CADDirectRouteEvidence {}
extension CADBoxRouteEvidence: CADDirectRouteEvidence {}
extension CADCylinderRouteEvidence: CADDirectRouteEvidence {}
extension CADConstraintRouteEvidence: CADDirectRouteEvidence {}
extension CADTransformRouteEvidence: CADDirectRouteEvidence {}
extension CADCompoundRouteEvidence: CADDirectRouteEvidence {}
extension CADSphereRouteEvidence: CADDirectRouteEvidence {}
