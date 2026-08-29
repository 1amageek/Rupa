import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCompoundCaseTests {
    private static let activatedCases: [CADCompoundActivatedCase] = [
        .compound001,
        .compound002,
        .compound003,
        .compound004,
        .compound005,
        .compound006,
        .compound007,
    ]

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func allSevenCompoundCasesPublishOneOrderedAtomicBatch() async throws {
        #expect(CADCompoundActivatedCase.allCases == Self.activatedCases)
        #expect(Self.activatedCases.count == 7)
        #expect(Set(Self.activatedCases).count == 7)

        for activatedCase in Self.activatedCases {
            let result = try await CADCompoundCaseRunner(case: activatedCase).runReference()

            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.realized)
            #expect(result.candidateResults?.count == Self.expectedMemberCount(for: activatedCase))
            #expect(result.candidateResults?.allSatisfy { $0.status == .published } == true)
            #expect(result.candidateResults?.allSatisfy { $0.createdFeatureIDs.count == 2 } == true)
            #expect(result.roleBindings?.bindings.map(\.role) == Self.expectedRoles(for: activatedCase))

            let memberCount = Self.expectedMemberCount(for: activatedCase)
            #expect(result.routeEvidence.didPublish)
            #expect(
                result.routeEvidence.finalDocumentGeneration.value
                    == result.routeEvidence.initialDocumentGeneration.value + UInt64(memberCount)
            )
            #expect(
                result.routeEvidence.finalTransactionRevision.value
                    == result.routeEvidence.initialTransactionRevision.value + 1
            )
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence + 1
            )
            #expect(
                result.routeEvidence.finalWorkspaceRevision
                    == result.routeEvidence.initialWorkspaceRevision
            )
            #expect(result.routeEvidence.memberCount == memberCount)
            #expect(result.routeEvidence.commandCount == memberCount)
            #expect(result.routeEvidence.evaluationPassCount == 1)
            #expect(result.routeEvidence.historyEntryCount == 1)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)

            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == memberCount)
            #expect(result.telemetry.readCount >= 2)
            #expect(result.telemetry.entityCount == Self.expectedEntityCount(for: activatedCase))
            #expect(result.telemetry.featureCount == memberCount * 2)
            #expect(result.telemetry.bodyCount == memberCount)
            #expect(result.telemetry.faceCount == memberCount * 6)
            #expect(result.telemetry.edgeCount == memberCount * 12)
            #expect(result.telemetry.vertexCount == memberCount * 8)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }
    }

    @Test
    func referenceCandidateProjectsPublicRoleOrderAndCylinderAxesForAllSevenCases() throws {
        let catalog = try CADBenchmarkCatalog()

        for activatedCase in Self.activatedCases {
            let challenge = try catalog.challenge(for: activatedCase.caseID)
            let projection = try CADCompoundChallengeProjection.decode(challenge)
            let members = try CADCompoundReferenceCandidate.members(for: challenge)

            #expect(members.count == projection.members.count)
            #expect(members.map(\.role) == projection.members.map(\.role))
            for (member, projected) in zip(members, projection.members) {
                #expect(member.primitive == projected.primitive)
                switch (member.solid, projected.primitive) {
                case let (.box(_, origin, width, depth, height), .box):
                    #expect(origin == projected.box?.origin)
                    #expect(width == projected.box?.width)
                    #expect(depth == projected.box?.depth)
                    #expect(height == projected.box?.height)
                case let (.cylinder(_, baseCenter, axis, radius, depth), .cylinder):
                    #expect(baseCenter == projected.cylinder?.baseCenter)
                    #expect(axis == projected.cylinder?.axis)
                    #expect(radius == projected.cylinder?.radius)
                    #expect(depth == projected.cylinder?.depth)
                default:
                    Issue.record("Reference candidate changed a public member primitive.")
                }
            }
        }
    }

    @Test
    func referenceCandidateUsesOnlyPublicCompoundContext() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "CMP-003")
        let context = CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: "test.v1",
                statuses: [CADCapabilityStatus(
                    id: challenge.requiredCapability.id,
                    version: challenge.requiredCapability.version,
                    available: true
                )]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )

        let plan = try await CADCompoundReferenceCandidate().decide(for: context)

        try context.validate()
        #expect(plan.members.map(\.role) == ["shaft", "collar"])
        for member in plan.members {
            let encoded = String(decoding: try JSONEncoder().encode(member.solid), as: UTF8.self)
            for privateName in ["FeatureID", "EntityID", "expectation", "tolerance", "oracle"] {
                #expect(encoded.contains(privateName) == false)
            }
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongPlacementPublishesOnceThenFailsTheSourceOracleWithoutRetry() async throws {
        let activatedCase: CADCompoundActivatedCase = .compound001
        var members = try Self.referenceMembers(for: activatedCase)
        guard case let .box(name, origin, width, depth, height) = members[0].solid else {
            Issue.record("CMP-001 first member was not the expected box.")
            return
        }
        members[0] = CADCompoundMemberAction(
            role: members[0].role,
            name: name,
            origin: CADPoint3D(x: origin.x, y: origin.y, z: origin.z + 1, unit: origin.unit),
            width: width,
            depth: depth,
            height: height
        )

        let result = try await CADCompoundCaseRunner(case: activatedCase).run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 2)
        #expect(result.routeEvidence.commandCount == 2)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 5)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func failureTelemetryReadIsReportedAsOracleFailureAfterOneCompoundPublication() async throws {
        var members = try Self.referenceMembers(for: .compound001)
        guard case let .box(name, origin, width, depth, height) = members[0].solid else {
            Issue.record("CMP-001 first member was not the expected box.")
            return
        }
        members[0] = CADCompoundMemberAction(
            role: members[0].role,
            name: name,
            origin: CADPoint3D(x: origin.x, y: origin.y, z: origin.z + 1, unit: origin.unit),
            width: width,
            depth: depth,
            height: height
        )
        let result = try await CADCompoundCaseRunner(
            case: .compound001,
            failureSourceReader: { _ in throw CADCompoundTestFailure.unavailable }
        ).run(actions: members)

        try result.validate()
        #expect(result.outcome == .oracleFailure)
        #expect(result.routeEvidence.didPublish)
        #expect(result.telemetry.readCount == 2)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("failure telemetry read failed") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func timeoutCancellationAndStaleBatchRetainCleanupAndNoRetryEvidence() async throws {
        let timeout = try await CADCompoundCaseRunner(
            case: .compound001,
            timeoutWallNanoseconds: 1
        ).runReference()
        try timeout.validate()
        #expect(timeout.outcome == .timeout)
        #expect(!timeout.routeEvidence.didPublish)
        #expect(timeout.telemetry.totalWallNanoseconds >= timeout.telemetry.timeoutWallNanoseconds)
        #expect(timeout.routeEvidence.cleanupCompleted)
        #expect(timeout.routeEvidence.remainingRegistrationCount == 0)

        let stale = try await CADCompoundCaseRunner(case: .compound001).runStaleReference()
        try stale.validate()
        #expect(stale.outcome == .executionFailure)
        #expect(!stale.routeEvidence.didPublish)
        #expect(stale.telemetry.actionCount == 2)
        #expect(stale.telemetry.commandCount == 4)
        #expect(stale.routeEvidence.cleanupCompleted)
        #expect(stale.routeEvidence.remainingRegistrationCount == 0)

        let task = Task { @MainActor in
            await Task.yield()
            return try await CADCompoundCaseRunner(case: .compound001).runReference()
        }
        task.cancel()
        let cancellation = try await task.value
        try cancellation.validate()
        #expect(cancellation.outcome == .cancellation)
        #expect(!cancellation.routeEvidence.didPublish)
        #expect(cancellation.routeEvidence.cleanupCompleted)
        #expect(cancellation.routeEvidence.remainingRegistrationCount == 0)
    }

    private static func expectedMemberCount(for activatedCase: CADCompoundActivatedCase) -> Int {
        switch activatedCase {
        case .compound001, .compound002, .compound003, .compound007:
            2
        case .compound004, .compound006:
            3
        case .compound005:
            3
        }
    }

    private static func expectedEntityCount(for activatedCase: CADCompoundActivatedCase) -> Int {
        switch activatedCase {
        case .compound001:
            5
        case .compound002:
            8
        case .compound003:
            2
        case .compound004:
            6
        case .compound005:
            12
        case .compound006:
            9
        case .compound007:
            5
        }
    }

    private static func expectedRoles(for activatedCase: CADCompoundActivatedCase) -> [String] {
        switch activatedCase {
        case .compound001:
            ["base", "post"]
        case .compound002:
            ["left", "right"]
        case .compound003:
            ["shaft", "collar"]
        case .compound004:
            ["plate", "pin-a", "pin-b"]
        case .compound005:
            ["frame", "upright-a", "upright-b"]
        case .compound006:
            ["hub", "arm-a", "arm-b"]
        case .compound007:
            ["block", "bore"]
        }
    }

    private static func referenceMembers(
        for activatedCase: CADCompoundActivatedCase
    ) throws -> [CADCompoundMemberAction] {
        let challenge = try activatedCase.catalogEntry.challenge
        return try CADCompoundReferenceCandidate.members(for: challenge)
    }
}

private enum CADCompoundTestFailure: Error {
    case unavailable
}
