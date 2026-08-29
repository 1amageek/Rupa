import Testing
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCompoundCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func activatedCompoundPrefixReplaysThroughTheProductionRoute() async throws {
        #expect(CADActivatedCompoundCase.allCases.map(\.rawValue) == [
            "CMP-001", "CMP-002", "CMP-003", "CMP-004", "CMP-005",
        ])

        for activatedCase in CADActivatedCompoundCase.allCases {
            let expectedMemberCount: Int
            let expectedCommandCount: Int
            let expectedGenerationIncrement: UInt64
            let expectedReadCount: Int
            let expectedEntityCount: Int
            let expectedFeatureCount: Int
            let expectedBodyCount: Int
            let expectedFaceCount: Int
            let expectedEdgeCount: Int
            let expectedVertexCount: Int
            switch activatedCase {
            case .compound001:
                expectedMemberCount = 2
                expectedCommandCount = 2
                expectedGenerationIncrement = 2
                expectedReadCount = 2
                expectedEntityCount = 5
                expectedFeatureCount = 4
                expectedBodyCount = 2
                expectedFaceCount = 12
                expectedEdgeCount = 24
                expectedVertexCount = 16
            case .compound002:
                expectedMemberCount = 2
                expectedCommandCount = 2
                expectedGenerationIncrement = 2
                expectedReadCount = 2
                expectedEntityCount = 8
                expectedFeatureCount = 4
                expectedBodyCount = 2
                expectedFaceCount = 12
                expectedEdgeCount = 24
                expectedVertexCount = 16
            case .compound003:
                expectedMemberCount = 2
                expectedCommandCount = 2
                expectedGenerationIncrement = 2
                expectedReadCount = 2
                expectedEntityCount = 2
                expectedFeatureCount = 4
                expectedBodyCount = 2
                expectedFaceCount = 12
                expectedEdgeCount = 24
                expectedVertexCount = 16
            case .compound004:
                expectedMemberCount = 3
                expectedCommandCount = 3
                expectedGenerationIncrement = 3
                expectedReadCount = 2
                expectedEntityCount = 6
                expectedFeatureCount = 6
                expectedBodyCount = 3
                expectedFaceCount = 18
                expectedEdgeCount = 36
                expectedVertexCount = 24
            case .compound005:
                expectedMemberCount = 3
                expectedCommandCount = 3
                expectedGenerationIncrement = 3
                expectedReadCount = 2
                expectedEntityCount = 12
                expectedFeatureCount = 6
                expectedBodyCount = 3
                expectedFaceCount = 18
                expectedEdgeCount = 36
                expectedVertexCount = 24
            }
            let result = try await CADCompoundCaseRunner(case: activatedCase).runReference()

            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.memberCount == expectedMemberCount)
            #expect(result.routeEvidence.commandCount == expectedCommandCount)
            #expect(result.routeEvidence.evaluationPassCount == 1)
            #expect(result.routeEvidence.historyEntryCount == 1)
            #expect(result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + expectedGenerationIncrement)
            #expect(result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1)
            #expect(result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == expectedCommandCount)
            #expect(result.telemetry.readCount == expectedReadCount)
            #expect(result.telemetry.entityCount == expectedEntityCount)
            #expect(result.telemetry.featureCount == expectedFeatureCount)
            #expect(result.telemetry.bodyCount == expectedBodyCount)
            #expect(result.telemetry.faceCount == expectedFaceCount)
            #expect(result.telemetry.edgeCount == expectedEdgeCount)
            #expect(result.telemetry.vertexCount == expectedVertexCount)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func missingExtraReorderedAndSubstituteMembersFailBeforePublication() async throws {
        let activatedCase: CADActivatedCompoundCase = .compound001
        let reference = try referenceMembers(for: activatedCase)
        let variants: [[CADCompoundMemberAction]] = [
            Array(reference.dropLast()),
            reference + [reference[0]],
            Array(reference.reversed()),
            [
                CADCompoundMemberAction(
                    role: reference[0].role,
                    solid: reference[1].solid
                ),
                reference[1],
            ],
        ]

        for members in variants {
            let result = try await CADCompoundCaseRunner(case: activatedCase).run(actions: members)

            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence
            )
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func wrongCylinderAxisPublishesOnceThenFailsTheSourceOracle() async throws {
        let activatedCase: CADActivatedCompoundCase = .compound001
        var members = try referenceMembers(for: activatedCase)
        guard case let .cylinder(name, baseCenter, _, radius, depth) = members[1].solid else {
            Issue.record("CMP-001 second member was not the expected cylinder.")
            return
        }
        members[1] = CADCompoundMemberAction(
            role: members[1].role,
            name: name,
            baseCenter: baseCenter,
            axis: CADDirection3D(x: 1, y: 0, z: 0),
            radius: radius,
            depth: depth
        )

        let result = try await CADCompoundCaseRunner(case: activatedCase).run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.memberCount == 2)
        #expect(result.routeEvidence.commandCount == 2)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func laterMemberFailureRollsBackEarlierMemberThroughProductionBatch() async throws {
        let activatedCase: CADActivatedCompoundCase = .compound001
        let entry = try activatedCase.catalogEntry
        let projection = try CADCompoundChallengeProjection.decode(entry.challenge)
        let reference = try CADCompoundReferenceCandidate.members(for: entry.challenge)
        let firstCommand = try CADCompoundGeometryMapping.command(
            for: reference[0],
            expected: projection.members[0],
            modelingTolerance: .standard,
            caseID: activatedCase.caseID
        )
        let secondCommand = try CADCompoundGeometryMapping.command(
            for: reference[1],
            expected: projection.members[1],
            modelingTolerance: .standard,
            caseID: activatedCase.caseID
        )
        guard case let .createExtrudedCircle(name, plane, center, _, depth, direction) = secondCommand else {
            Issue.record("CMP-001 second member was not mapped to a circle extrusion.")
            return
        }
        let invalidSecondCommand = AutomationCommand.createExtrudedCircle(
            name: name,
            plane: plane,
            center: center,
            radius: .constant(.length(0, unit: .meter)),
            depth: depth,
            direction: direction
        )
        let harness = CADCaseLifecycleHarness(
            caseID: activatedCase.caseID,
            challenge: entry.challenge,
            routing: CADCaseActionRouting(
                operationName: "compoundPreparation.rollback",
                planBuilder: { _, _, _ in .batch([firstCommand, invalidSecondCommand]) }
            ),
            timeoutWallNanoseconds: 10_000_000_000
        )

        let record = try await harness.run(
            action: .compound(CADCompoundAction(members: reference))
        )

        #expect(record.outcome == .executionFailure)
        #expect(record.routeEvidence.didPublish == false)
        #expect(
            record.routeEvidence.initialDocumentGeneration
                == record.routeEvidence.finalDocumentGeneration
        )
        #expect(
            record.routeEvidence.initialTransactionRevision
                == record.routeEvidence.finalTransactionRevision
        )
        #expect(
            record.routeEvidence.initialPublicationSequence
                == record.routeEvidence.finalPublicationSequence
        )
        #expect(record.finalView?.document.document.cadDocument.designGraph.nodes.isEmpty == true)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound004ThirdCommandFailureRollsBackEarlierMembersAtomically() async throws {
        let activatedCase: CADActivatedCompoundCase = .compound004
        let entry = try activatedCase.catalogEntry
        let projection = try CADCompoundChallengeProjection.decode(entry.challenge)
        let reference = try CADCompoundReferenceCandidate.members(for: entry.challenge)
        let commands = try reference.enumerated().map { index, member in
            try CADCompoundGeometryMapping.command(
                for: member,
                expected: projection.members[index],
                modelingTolerance: .standard,
                caseID: activatedCase.caseID
            )
        }
        guard commands.count == 3,
              case let .createExtrudedCircle(name, plane, center, _, depth, direction) = commands[2]
        else {
            Issue.record("CMP-004 did not map to one plate command followed by two pin extrusions.")
            return
        }
        let invalidThirdCommand = AutomationCommand.createExtrudedCircle(
            name: name,
            plane: plane,
            center: center,
            radius: .constant(.length(0, unit: .meter)),
            depth: depth,
            direction: direction
        )
        let harness = CADCaseLifecycleHarness(
            caseID: activatedCase.caseID,
            challenge: entry.challenge,
            routing: CADCaseActionRouting(
                operationName: "compoundPreparation.rollback",
                planBuilder: { _, _, _ in
                    .batch([commands[0], commands[1], invalidThirdCommand])
                }
            ),
            timeoutWallNanoseconds: 10_000_000_000
        )

        let record = try await harness.run(
            action: .compound(CADCompoundAction(members: reference))
        )

        #expect(record.outcome == .executionFailure)
        #expect(record.routeEvidence.didPublish == false)
        #expect(
            record.routeEvidence.initialDocumentGeneration
                == record.routeEvidence.finalDocumentGeneration
        )
        #expect(
            record.routeEvidence.initialTransactionRevision
                == record.routeEvidence.finalTransactionRevision
        )
        #expect(
            record.routeEvidence.initialPublicationSequence
                == record.routeEvidence.finalPublicationSequence
        )
        #expect(record.telemetry.actionCount == 1)
        #expect(record.telemetry.commandCount == 3)
        guard let response = record.response else {
            Issue.record("CMP-004 third-command failure did not return a response.")
            return
        }
        guard case .failure = response else {
            Issue.record("CMP-004 third-command failure must stop before evaluation/history publication.")
            return
        }
        let failedBatchEvidence = CADCompoundRouteEvidence(from: record.routeEvidence)
        #expect(failedBatchEvidence.evaluationPassCount == 0)
        #expect(failedBatchEvidence.historyEntryCount == 0)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
        #expect(record.finalView?.document.document.cadDocument.designGraph.nodes.isEmpty == true)
    }

    private func referenceMembers(
        for activatedCase: CADActivatedCompoundCase
    ) throws -> [CADCompoundMemberAction] {
        let entry = try activatedCase.catalogEntry
        return try CADCompoundReferenceCandidate.members(for: entry.challenge)
    }
}
