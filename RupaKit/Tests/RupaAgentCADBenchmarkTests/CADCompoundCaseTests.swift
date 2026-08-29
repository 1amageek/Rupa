import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCompoundCaseTests {
    private static let activatedCase: CADActivatedCompoundCase = .compound001
    private static let secondActivatedCase: CADActivatedCompoundCase = .compound002
    private static let thirdActivatedCase: CADActivatedCompoundCase = .compound003
    private static let fourthActivatedCase: CADActivatedCompoundCase = .compound004
    private static let fifthActivatedCase: CADActivatedCompoundCase = .compound005
    private static let sixthActivatedCase: CADActivatedCompoundCase = .compound006

    @Test
    func preparedAndActivatedBoundariesRemainDistinct() throws {
        #expect(CADCompoundPreparedCase.allCases.map(\.rawValue) == [
            "CMP-001", "CMP-002", "CMP-003", "CMP-004", "CMP-005", "CMP-006", "CMP-007",
        ])
        #expect(CADActivatedCompoundCase.allCases.map(\.rawValue) == [
            "CMP-001", "CMP-002", "CMP-003", "CMP-004", "CMP-005", "CMP-006",
        ])
        #expect(CADCompoundPreparedCase(rawValue: "CMP-002") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-002") != nil)
        #expect(CADCompoundPreparedCase(rawValue: "CMP-003") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-003") != nil)
        #expect(CADCompoundPreparedCase(rawValue: "CMP-004") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-004") != nil)
        #expect(CADCompoundPreparedCase(rawValue: "CMP-005") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-005") != nil)
        #expect(CADCompoundPreparedCase(rawValue: "CMP-006") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-006") != nil)
        #expect(CADCompoundPreparedCase(rawValue: "CMP-007") != nil)
        #expect(CADActivatedCompoundCase(rawValue: "CMP-007") == nil)
    }

    @Test
    func compoundActionIsPublicCodableAndPreservesMemberOrder() throws {
        let challenge = try Self.activatedCase.catalogEntry.challenge
        let action = try CADCompoundReferenceCandidate.action(for: challenge)
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CADCandidateAction.self, from: encoded)

        guard case .compound(let compound) = decoded else {
            Issue.record("The compound action did not retain its public discriminator.")
            return
        }
        #expect(decoded == action)
        #expect(compound.members.map(\.role) == ["base", "post"])
        #expect(String(decoding: encoded, as: UTF8.self).contains("compound"))
    }

    @Test
    func requiredPrimitiveOperationsAreStableAndDeduplicated() throws {
        let challenge = try Self.activatedCase.catalogEntry.challenge
        let reference = try CADCompoundReferenceCandidate.members(for: challenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: reference) == [
            "createExtrudedRectangle", "createExtrudedCircle",
        ])
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: [
            reference[1], reference[0], reference[1],
        ]) == ["createExtrudedCircle", "createExtrudedRectangle"])

        let secondChallenge = try Self.secondActivatedCase.catalogEntry.challenge
        let secondReference = try CADCompoundReferenceCandidate.members(for: secondChallenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: secondReference) == [
            "createExtrudedRectangle",
        ])

        let thirdChallenge = try Self.thirdActivatedCase.catalogEntry.challenge
        let thirdReference = try CADCompoundReferenceCandidate.members(for: thirdChallenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: thirdReference) == [
            "createExtrudedCircle",
        ])

        let fourthChallenge = try Self.fourthActivatedCase.catalogEntry.challenge
        let fourthReference = try CADCompoundReferenceCandidate.members(for: fourthChallenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: fourthReference) == [
            "createExtrudedRectangle", "createExtrudedCircle",
        ])

        let fifthChallenge = try Self.fifthActivatedCase.catalogEntry.challenge
        let fifthReference = try CADCompoundReferenceCandidate.members(for: fifthChallenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: fifthReference) == [
            "createExtrudedRectangle",
        ])

        let sixthChallenge = try Self.sixthActivatedCase.catalogEntry.challenge
        let sixthReference = try CADCompoundReferenceCandidate.members(for: sixthChallenge)
        #expect(CADCompoundGeometryMapping.requiredOperationNames(for: sixthReference) == [
            "createExtrudedCircle", "createExtrudedRectangle",
        ])
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound001PublishesOneAtomicBatchWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.activatedCase).runReference()

        try result.validate()
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 2
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 2)
        #expect(result.routeEvidence.commandCount == 2)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["base", "post"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 5)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.telemetry.faceCount == 12)
        #expect(result.telemetry.edgeCount == 24)
        #expect(result.telemetry.vertexCount == 16)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound002PublishesTwoOrderedCubesWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.secondActivatedCase).runReference()

        try result.validate()
        #expect(result.caseID == "CMP-002")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 2
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 2)
        #expect(result.routeEvidence.commandCount == 2)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["left", "right"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 8)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.telemetry.faceCount == 12)
        #expect(result.telemetry.edgeCount == 24)
        #expect(result.telemetry.vertexCount == 16)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound003PublishesTwoOrderedCylindersWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.thirdActivatedCase).runReference()

        try result.validate()
        #expect(result.caseID == "CMP-003")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 2
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 2)
        #expect(result.routeEvidence.commandCount == 2)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["shaft", "collar"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.telemetry.faceCount == 12)
        #expect(result.telemetry.edgeCount == 24)
        #expect(result.telemetry.vertexCount == 16)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound004PublishesPlateAndOrderedPinsWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.fourthActivatedCase).runReference()

        try result.validate()
        #expect(result.caseID == "CMP-004")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 3
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["plate", "pin-a", "pin-b"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 6)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.telemetry.faceCount == 18)
        #expect(result.telemetry.edgeCount == 36)
        #expect(result.telemetry.vertexCount == 24)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound005PublishesFrameAndOrderedUprightsWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.fifthActivatedCase).runReference()

        try result.validate()
        #expect(result.caseID == "CMP-005")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 3
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["frame", "upright-a", "upright-b"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 12)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.telemetry.faceCount == 18)
        #expect(result.telemetry.edgeCount == 36)
        #expect(result.telemetry.vertexCount == 24)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound006PublishesHubAndOrderedArmsWithExactSourceAndTopology() async throws {
        let result = try await CADCompoundCaseRunner(case: Self.sixthActivatedCase).runReference()

        try result.validate()
        #expect(result.caseID == "CMP-006")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalDocumentGeneration.value
                == result.routeEvidence.initialDocumentGeneration.value + 3
        )
        #expect(
            result.routeEvidence.finalTransactionRevision.value
                == result.routeEvidence.initialTransactionRevision.value + 1
        )
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.roleBindings?.bindings.map(\.role) == ["hub", "arm-a", "arm-b"])
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 9)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.telemetry.faceCount == 18)
        #expect(result.telemetry.edgeCount == 36)
        #expect(result.telemetry.vertexCount == 24)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound003SwappedCylinderPayloadsPublishOnceThenFailRoleSensitiveOracle() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.thirdActivatedCase.catalogEntry.challenge
        )
        let members = [
            CADCompoundMemberAction(role: reference[0].role, solid: reference[1].solid),
            CADCompoundMemberAction(role: reference[1].role, solid: reference[0].solid),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.thirdActivatedCase)
            .run(actions: members)

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
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound004SwappedPinPayloadsPublishOnceThenFailRoleSensitiveOracle() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.fourthActivatedCase.catalogEntry.challenge
        )
        let members = [
            reference[0],
            CADCompoundMemberAction(role: reference[1].role, solid: reference[2].solid),
            CADCompoundMemberAction(role: reference[2].role, solid: reference[1].solid),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.fourthActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 6)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound005SwappedUprightPayloadsPublishOnceThenFailRoleSensitiveOracle() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.fifthActivatedCase.catalogEntry.challenge
        )
        let members = [
            reference[0],
            CADCompoundMemberAction(role: reference[1].role, solid: reference[2].solid),
            CADCompoundMemberAction(role: reference[2].role, solid: reference[1].solid),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.fifthActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 12)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.telemetry.faceCount == 18)
        #expect(result.telemetry.edgeCount == 36)
        #expect(result.telemetry.vertexCount == 24)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound006SwappedArmPayloadsPublishOnceThenFailRoleSensitiveOracle() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.sixthActivatedCase.catalogEntry.challenge
        )
        let members = [
            reference[0],
            CADCompoundMemberAction(role: reference[1].role, solid: reference[2].solid),
            CADCompoundMemberAction(role: reference[2].role, solid: reference[1].solid),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.sixthActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.memberCount == 3)
        #expect(result.routeEvidence.commandCount == 3)
        #expect(result.routeEvidence.evaluationPassCount == 1)
        #expect(result.routeEvidence.historyEntryCount == 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 3)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 9)
        #expect(result.telemetry.featureCount == 6)
        #expect(result.telemetry.bodyCount == 3)
        #expect(result.telemetry.faceCount == 18)
        #expect(result.telemetry.edgeCount == 36)
        #expect(result.telemetry.vertexCount == 24)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound003DegenerateLaterMemberFailsBeforePublication() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.thirdActivatedCase.catalogEntry.challenge
        )
        guard case let .cylinder(name, baseCenter, axis, _, depth) = reference[1].solid else {
            Issue.record("CMP-003 later member was not a cylinder.")
            return
        }
        let zeroRadius = CADCompoundMemberAction(
            role: reference[1].role,
            name: name,
            baseCenter: baseCenter,
            axis: axis,
            radius: CADLength(value: 0, unit: .millimeter),
            depth: depth
        )
        let zeroAxis = CADCompoundMemberAction(
            role: reference[1].role,
            name: name,
            baseCenter: baseCenter,
            axis: CADDirection3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: 12, unit: .millimeter),
            depth: depth
        )

        for laterMember in [zeroRadius, zeroAxis] {
            let members = [
                reference[0],
                laterMember,
            ]
            let result = try await CADCompoundCaseRunner(case: Self.thirdActivatedCase)
                .run(actions: members)

            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence
            )
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound004DegenerateThirdMemberFailsBeforePublication() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.fourthActivatedCase.catalogEntry.challenge
        )
        guard case let .cylinder(name, baseCenter, axis, _, depth) = reference[2].solid else {
            Issue.record("CMP-004 third member was not a cylinder.")
            return
        }
        let zeroRadius = CADCompoundMemberAction(
            role: reference[2].role,
            name: name,
            baseCenter: baseCenter,
            axis: axis,
            radius: CADLength(value: 0, unit: .millimeter),
            depth: depth
        )
        let zeroAxis = CADCompoundMemberAction(
            role: reference[2].role,
            name: name,
            baseCenter: baseCenter,
            axis: CADDirection3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: 8, unit: .millimeter),
            depth: depth
        )

        for thirdMember in [zeroRadius, zeroAxis] {
            let members = [
                reference[0],
                reference[1],
                thirdMember,
            ]
            let result = try await CADCompoundCaseRunner(case: Self.fourthActivatedCase)
                .run(actions: members)

            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence
            )
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound005DegenerateThirdMemberFailsBeforePublication() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.fifthActivatedCase.catalogEntry.challenge
        )
        guard case let .box(name, origin, _, depth, height) = reference[2].solid else {
            Issue.record("CMP-005 third member was not a box.")
            return
        }
        let members = [
            reference[0],
            reference[1],
            CADCompoundMemberAction(
                role: reference[2].role,
                name: name,
                origin: origin,
                width: CADLength(value: 0, unit: .millimeter),
                depth: depth,
                height: height
            ),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.fifthActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound006DegenerateThirdMemberFailsBeforePublication() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.sixthActivatedCase.catalogEntry.challenge
        )
        guard case let .box(name, origin, _, depth, height) = reference[2].solid else {
            Issue.record("CMP-006 third member was not a box.")
            return
        }
        let members = [
            reference[0],
            reference[1],
            CADCompoundMemberAction(
                role: reference[2].role,
                name: name,
                origin: origin,
                width: CADLength(value: 0, unit: .millimeter),
                depth: depth,
                height: height
            ),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.sixthActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func wrongPostPlacementPublishesOnceThenFailsWithoutRetry() async throws {
        var members = try Self.referenceMembers()
        guard case let .cylinder(name, baseCenter, axis, radius, depth) = members[1].solid else {
            Issue.record("CMP-001 post member was not a cylinder.")
            return
        }
        members[1] = CADCompoundMemberAction(
            role: members[1].role,
            name: name,
            baseCenter: CADPoint3D(
                x: baseCenter.x + 1,
                y: baseCenter.y,
                z: baseCenter.z,
                unit: baseCenter.unit
            ),
            axis: axis,
            radius: radius,
            depth: depth
        )

        let result = try await CADCompoundCaseRunner(case: Self.activatedCase).run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence
            == result.routeEvidence.initialPublicationSequence + 1)
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
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound002SwappedOriginsPublishOnceThenFailRoleSensitiveOracle() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.secondActivatedCase.catalogEntry.challenge
        )
        let members = [
            CADCompoundMemberAction(role: reference[0].role, solid: reference[1].solid),
            CADCompoundMemberAction(role: reference[1].role, solid: reference[0].solid),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.secondActivatedCase)
            .run(actions: members)

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
        #expect(result.telemetry.entityCount == 8)
        #expect(result.telemetry.featureCount == 4)
        #expect(result.telemetry.bodyCount == 2)
        #expect(result.diagnostics.contains { $0.lowercased().contains("oracle mismatch") })
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func compound002ZeroDimensionFailsBeforePublication() async throws {
        let reference = try CADCompoundReferenceCandidate.members(
            for: Self.secondActivatedCase.catalogEntry.challenge
        )
        guard case let .box(name, origin, _, depth, height) = reference[1].solid else {
            Issue.record("CMP-002 right member was not a box.")
            return
        }
        let members = [
            reference[0],
            CADCompoundMemberAction(
                role: reference[1].role,
                name: name,
                origin: origin,
                width: CADLength(value: 0, unit: .millimeter),
                depth: depth,
                height: height
            ),
        ]

        let result = try await CADCompoundCaseRunner(case: Self.secondActivatedCase)
            .run(actions: members)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.commandCount == 0)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func missingExtraReorderedSubstitutedAndDegenerateMembersFailBeforePublication() async throws {
        let reference = try Self.referenceMembers()
        var zeroAxis = reference
        if case let .cylinder(name, baseCenter, _, radius, depth) = zeroAxis[1].solid {
            zeroAxis[1] = CADCompoundMemberAction(
                role: zeroAxis[1].role,
                name: name,
                baseCenter: baseCenter,
                axis: CADDirection3D(x: 0, y: 0, z: 0),
                radius: radius,
                depth: depth
            )
        }
        var zeroRadius = reference
        if case let .cylinder(name, baseCenter, axis, _, depth) = zeroRadius[1].solid {
            zeroRadius[1] = CADCompoundMemberAction(
                role: zeroRadius[1].role,
                name: name,
                baseCenter: baseCenter,
                axis: axis,
                radius: CADLength(value: 0, unit: .millimeter),
                depth: depth
            )
        }
        let variants: [[CADCompoundMemberAction]] = [
            Array(reference.dropLast()),
            reference + [reference[0]],
            Array(reference.reversed()),
            [CADCompoundMemberAction(role: reference[0].role, solid: reference[1].solid), reference[1]],
            zeroAxis,
            zeroRadius,
        ]

        for members in variants {
            let result = try await CADCompoundCaseRunner(case: Self.activatedCase).run(actions: members)
            try result.validate()
            #expect(result.outcome == .invalidSubmission)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.finalDocumentGeneration
                == result.routeEvidence.initialDocumentGeneration)
            #expect(result.routeEvidence.finalTransactionRevision
                == result.routeEvidence.initialTransactionRevision)
            #expect(result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func singlePrimitiveActionIsRejectedBeforePublication() async throws {
        let reference = try Self.referenceMembers()
        let result = try await CADCompoundCaseRunner(case: Self.activatedCase).run(
            candidate: CADSinglePrimitiveCandidate(
                action: .automation(.solid(reference[0].solid))
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.finalPublicationSequence
            == result.routeEvidence.initialPublicationSequence)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func timeoutStaleAndCancellationRetainNoPublicationAndCleanup() async throws {
        for activatedCase in CADActivatedCompoundCase.allCases {
            let expectedStaleCommandCount = try activatedCase.catalogEntry.challenge.outputRoles.count * 2
            let timeout = try await CADCompoundCaseRunner(
                case: activatedCase,
                timeoutWallNanoseconds: 1
            ).runReference()
            try timeout.validate()
            #expect(timeout.caseID == activatedCase.caseID)
            #expect(timeout.outcome == .timeout)
            #expect(timeout.routeEvidence.didPublish == false)
            #expect(timeout.routeEvidence.cleanupCompleted)
            #expect(timeout.routeEvidence.remainingRegistrationCount == 0)

            let stale = try await CADCompoundCaseRunner(case: activatedCase).runStaleReference()
            try stale.validate()
            #expect(stale.caseID == activatedCase.caseID)
            #expect(stale.outcome == .executionFailure)
            #expect(stale.routeEvidence.didPublish == false)
            #expect(stale.telemetry.actionCount == 2)
            #expect(stale.telemetry.commandCount == expectedStaleCommandCount)
            #expect(stale.routeEvidence.cleanupCompleted)
            #expect(stale.routeEvidence.remainingRegistrationCount == 0)

            let task = Task { @MainActor in
                await Task.yield()
                return try await CADCompoundCaseRunner(case: activatedCase).runReference()
            }
            task.cancel()
            let cancellation = try await task.value
            try cancellation.validate()
            #expect(cancellation.caseID == activatedCase.caseID)
            #expect(cancellation.outcome == .cancellation)
            #expect(cancellation.routeEvidence.didPublish == false)
            #expect(cancellation.routeEvidence.cleanupCompleted)
            #expect(cancellation.routeEvidence.remainingRegistrationCount == 0)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func telemetryReaderFailureRemainsTypedOracleFailureAfterPublication() async throws {
        var members = try Self.referenceMembers()
        guard case let .box(name, origin, width, depth, height) = members[0].solid else {
            Issue.record("CMP-001 base member was not a box.")
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
            case: Self.activatedCase,
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

    private static func referenceMembers() throws -> [CADCompoundMemberAction] {
        try CADCompoundReferenceCandidate.members(for: activatedCase.catalogEntry.challenge)
    }
}

private enum CADCompoundTestFailure: Error {
    case unavailable
}

private struct CADSinglePrimitiveCandidate: CADCandidateProtocol {
    let action: CADCandidateAction

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(action)
    }
}
