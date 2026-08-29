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
            "CMP-001", "CMP-002", "CMP-003",
        ])

        for activatedCase in CADActivatedCompoundCase.allCases {
            let result = try await CADCompoundCaseRunner(case: activatedCase).runReference()

            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.memberCount == 2)
            #expect(result.routeEvidence.commandCount == 2)
            #expect(result.routeEvidence.evaluationPassCount == 1)
            #expect(result.routeEvidence.historyEntryCount == 1)
            #expect(result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 2)
            #expect(result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1)
            #expect(result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 2)
            #expect(result.telemetry.readCount == 2)
            let expectedEntityCount: Int
            switch activatedCase {
            case .compound001:
                expectedEntityCount = 5
            case .compound002:
                expectedEntityCount = 8
            case .compound003:
                expectedEntityCount = 2
            }
            #expect(result.telemetry.entityCount == expectedEntityCount)
            #expect(result.telemetry.featureCount == 4)
            #expect(result.telemetry.bodyCount == 2)
            #expect(result.telemetry.faceCount == 12)
            #expect(result.telemetry.edgeCount == 24)
            #expect(result.telemetry.vertexCount == 16)
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

    private func referenceMembers(
        for activatedCase: CADActivatedCompoundCase
    ) throws -> [CADCompoundMemberAction] {
        let entry = try activatedCase.catalogEntry
        return try CADCompoundReferenceCandidate.members(for: entry.challenge)
    }
}
