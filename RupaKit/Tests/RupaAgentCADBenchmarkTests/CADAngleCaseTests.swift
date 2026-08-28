import Foundation
import Testing
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADAngleCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001CreatesTwoExactLinesInOneProductionBatch() async throws {
        let result = try await CADAngleCaseRunner(case: .ang001).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-001")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang002CreatesTheTranslatedFortyFiveDegreePairInOneProductionBatch() async throws {
        let result = try await CADAngleCaseRunner(case: .ang002).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-002")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang002RejectsSwappedSegmentLengthsAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang002).run(
            action: angle002Action(
                firstEnd: CADPoint3D(x: 60, y: -10, z: 50, unit: .millimeter),
                secondEnd: CADPoint3D(
                    x: 10 + 30 * 0.707106781187,
                    y: -10 + 30 * 0.707106781187,
                    z: 50,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang002RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang002).run(
            action: angle002Action(
                firstEnd: CADPoint3D(x: 40, y: -10, z: 52, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang002TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang002,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang003CreatesTheTranslatedSixtyDegreePairInOneProductionBatch() async throws {
        let result = try await CADAngleCaseRunner(case: .ang003).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-003")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang003RejectsWrongSecondDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang003).run(
            action: angle003Action(
                secondEnd: CADPoint3D(
                    x: -25 + 75 * 0.707106781187,
                    y: 15 + 75 * 0.707106781187,
                    z: 125,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang003RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang003).run(
            action: angle003Action(
                firstEnd: CADPoint3D(x: 20, y: 15, z: 127, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang003TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang003,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang004CreatesTheTranslatedSeventyFiveDegreePairInOneProductionBatch() async throws {
        let result = try await CADAngleCaseRunner(case: .ang004).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-004")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang004RejectsShiftedSecondSegmentAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang004).run(
            action: angle004Action(
                secondStart: CADPoint3D(x: 31, y: 25, z: 150, unit: .millimeter),
                secondEnd: CADPoint3D(
                    x: 31 + 100 * 0.258819045103,
                    y: 25 + 100 * 0.965925826289,
                    z: 150,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang004RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang004).run(
            action: angle004Action(
                firstEnd: CADPoint3D(x: 90, y: 25, z: 152, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang004TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang004,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang005CreatesTheOrthogonalSeventyFiveAndOneHundredTwentyFiveMillimeterPair() async throws {
        let result = try await CADAngleCaseRunner(case: .ang005).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-005")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang005RejectsOppositeSecondDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang005).run(
            action: angle005Action(
                secondEnd: CADPoint3D(x: 0, y: -125, z: 200, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang005RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang005).run(
            action: angle005Action(
                firstEnd: CADPoint3D(x: 75, y: 0, z: 202, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang005TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang005,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang006CreatesTheOneHundredFiveDegreePairAtNegativeXPlacement() async throws {
        let result = try await CADAngleCaseRunner(case: .ang006).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-006")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang006RejectsTheSeventyFiveDegreeSecondDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang006).run(
            action: angle006Action(
                secondEnd: CADPoint3D(
                    x: -50 + 150 * 0.258819045103,
                    y: 40 + 150 * 0.965925826289,
                    z: 250,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang006RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang006).run(
            action: angle006Action(
                firstEnd: CADPoint3D(x: 40, y: 40, z: 252, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang006TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang006,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang007CreatesTheOneHundredTwentyDegreePairAtTranslatedPlacement() async throws {
        let result = try await CADAngleCaseRunner(case: .ang007).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-007")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang007RejectsReversedFirstDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang007).run(
            action: angle007Action(
                firstEnd: CADPoint3D(x: -85, y: -35, z: 300, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang007RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang007).run(
            action: angle007Action(
                firstEnd: CADPoint3D(x: 125, y: -35, z: 302, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang007TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang007,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang008CreatesTheOneHundredThirtyFiveDegreePairAtOrigin() async throws {
        let result = try await CADAngleCaseRunner(case: .ang008).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-008")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang008RejectsShortenedSecondSegmentAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang008).run(
            action: angle008Action(
                secondEnd: CADPoint3D(
                    x: -125 * 0.707106781187,
                    y: 125 * 0.707106781187,
                    z: 350,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang008RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang008).run(
            action: angle008Action(
                firstEnd: CADPoint3D(x: 120, y: 0, z: 352, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang008TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang008,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang009CreatesTheOneHundredFiftyDegreePairAtTranslatedPlacement() async throws {
        let result = try await CADAngleCaseRunner(case: .ang009).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-009")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang009RejectsTranslatedPairAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang009).run(
            action: angle009Action(
                firstStart: CADPoint3D(x: 75, y: 60, z: 400, unit: .millimeter),
                firstEnd: CADPoint3D(x: 210, y: 60, z: 400, unit: .millimeter),
                secondStart: CADPoint3D(x: 75, y: 60, z: 400, unit: .millimeter),
                secondEnd: CADPoint3D(
                    x: 75 - 300 * 0.866025403784,
                    y: 60 + 300 * 0.5,
                    z: 400,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang009RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang009).run(
            action: angle009Action(
                firstEnd: CADPoint3D(x: 210, y: 50, z: 402, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang009TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang009,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang010CreatesTheOneHundredSixtyFiveDegreePairAtNegativePlacement() async throws {
        let result = try await CADAngleCaseRunner(case: .ang010).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-010")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang010RejectsTheOneHundredFiftyDegreeDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang010).run(
            action: angle010Action(
                secondEnd: CADPoint3D(
                    x: -75 - 350 * 0.866025403784,
                    y: -50 + 350 * 0.5,
                    z: 450,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang010RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang010).run(
            action: angle010Action(
                firstEnd: CADPoint3D(x: 75, y: -50, z: 452, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang010TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang010,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang011CreatesTheFortyFiveDegreePairOnCanonicalXZPlane() async throws {
        let result = try await CADAngleCaseRunner(case: .ang011).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-011")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang011RejectsTheThirtyDegreeSecondDirectionAfterOnePublicationWithoutRetry() async throws {
        let result = try await CADAngleCaseRunner(case: .ang011).run(
            action: angle011Action(
                secondEnd: CADPoint3D(
                    x: 60 * 0.866025403784,
                    y: 0,
                    z: 80 + 60 * 0.5,
                    unit: .millimeter
                )
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang011RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang011).run(
            action: angle011Action(
                firstEnd: CADPoint3D(x: 30, y: 2, z: 80, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang011TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang011,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang012CreatesTheSixtyDegreePairOnCanonicalYZPlane() async throws {
        let result = try await CADAngleCaseRunner(case: .ang012).runReference()

        try result.validate()
        #expect(result.caseID == "ANG-012")
        #expect(result.outcome == .realized)
        #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
        #expect(result.candidateResults.allSatisfy { $0.status == .published })
        #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang012RejectsSwappedSegmentGeometriesAfterOnePublicationWithoutRetry() async throws {
        let correctFirstEnd = CADPoint3D(x: 10, y: 20, z: 120, unit: .millimeter)
        let correctSecondEnd = CADPoint3D(
            x: 10,
            y: -20 + 100 * 0.5,
            z: 120 + 100 * 0.866025403784,
            unit: .millimeter
        )
        let result = try await CADAngleCaseRunner(case: .ang012).run(
            action: angle012Action(
                firstEnd: correctSecondEnd,
                secondEnd: correctFirstEnd
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang012RejectsOffPlaneEndpointBeforePublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang012).run(
            action: angle012Action(
                firstEnd: CADPoint3D(x: 12, y: 20, z: 120, unit: .millimeter)
            )
        )

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang012TimeoutRetainsAtomicCleanupEvidence() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang012,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001RejectsNonintersectingPairAfterOnePublicationWithoutRetry() async throws {
        let action = angleAction(
            secondStart: CADPoint3D(x: 1, y: 0, z: 35, unit: .millimeter),
            secondEnd: CADPoint3D(
                x: 1 + 25 * 0.866025403784,
                y: 12.5,
                z: 35,
                unit: .millimeter
            )
        )
        let result = try await CADAngleCaseRunner(case: .ang001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence + 1
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 2)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 2)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001RejectsOffPlaneEndpointBeforePublication() async throws {
        let action = angleAction(
            secondEnd: CADPoint3D(
                x: 25 * 0.866025403784,
                y: 12.5,
                z: 37,
                unit: .millimeter
            )
        )
        let result = try await CADAngleCaseRunner(case: .ang001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(
            result.routeEvidence.finalPublicationSequence
                == result.routeEvidence.initialPublicationSequence
        )
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001BatchRollsBackFirstLineWhenSecondLineFails() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
        let plane = try angleSourcePlane()
        let valid = lineCommand(
            name: "ANG-001.rollback.first",
            plane: plane,
            start: Point2D(x: 0, y: 0),
            end: Point2D(x: 0.015, y: 0)
        )
        let invalid = lineCommand(
            name: "ANG-001.rollback.second",
            plane: plane,
            start: Point2D(x: 0, y: 0),
            end: Point2D(x: 0, y: 0)
        )
        let harness = CADCaseLifecycleHarness(
            caseID: "ANG-001",
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: "createAngleLines",
                planBuilder: { _, _, _ in .batch([valid, invalid]) }
            ),
            timeoutWallNanoseconds: 10_000_000_000
        )
        let record = try await harness.run(action: angleAction())

        #expect(record.outcome == .executionFailure)
        #expect(record.routeEvidence.didPublish == false)
        #expect(record.routeEvidence.initialDocumentGeneration == record.routeEvidence.finalDocumentGeneration)
        #expect(record.routeEvidence.initialTransactionRevision == record.routeEvidence.finalTransactionRevision)
        #expect(record.routeEvidence.initialPublicationSequence == record.routeEvidence.finalPublicationSequence)
        #expect(record.finalView?.document.document.cadDocument.designGraph.nodes.isEmpty == true)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001StaleBatchIsRejectedWithoutSecondPublication() async throws {
        let result = try await CADAngleCaseRunner(case: .ang001).runStaleReference()

        try result.validate()
        #expect(result.outcome == .executionFailure)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.actionCount == 2)
        #expect(result.telemetry.commandCount == 4)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADAngleCaseRunner(
            case: .ang001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001CancellationBeforePlanningPublishesNothing() async throws {
        let task = Task { @MainActor in
            await Task.yield()
            return try await CADAngleCaseRunner(case: .ang001).runReference()
        }
        task.cancel()

        let result = try await task.value

        try result.validate()
        #expect(result.outcome == .cancellation)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func ang001ReferenceCandidateUsesOnlyPublicIntersectionAndDirections() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let context = try executor.context(for: "ANG-001")
        #expect(context.capabilities.statuses == [
            CADCapabilityStatus(
                id: "cad.sketch.intersection",
                version: "1",
                available: true
            ),
        ])
        let decision = try await CADAngleReferenceCandidate().decide(for: context)

        guard case .action(.automation(.sketch(.angle(
            _, let plane, let firstStart, let firstEnd, let secondStart, let secondEnd
        )))) = decision else {
            Issue.record("ANG-001 candidate did not produce one angle action.")
            return
        }
        #expect(plane == .xy)
        #expect(firstStart == CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter))
        #expect(secondStart == firstStart)
        #expect(abs(firstEnd.meters.x - 0.015) <= 1e-12)
        #expect(abs(firstEnd.meters.y) <= 1e-12)
        #expect(abs(firstEnd.meters.z - 0.035) <= 1e-12)
        #expect(abs(secondEnd.meters.x - 0.025 * 0.866025403784) <= 1e-12)
        #expect(abs(secondEnd.meters.y - 0.0125) <= 1e-12)
        #expect(abs(secondEnd.meters.z - 0.035) <= 1e-12)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001FailureTelemetryReadFailureIsAnOracleFailure() async throws {
        let action = angleAction(
            secondStart: CADPoint3D(x: 1, y: 0, z: 35, unit: .millimeter),
            secondEnd: CADPoint3D(
                x: 1 + 25 * 0.866025403784,
                y: 12.5,
                z: 35,
                unit: .millimeter
            )
        )
        let result = try await CADAngleCaseRunner(
            case: .ang001,
            failureSourceReader: { _ in throw FailureSourceReadError.unavailable }
        ).run(action: action)

        try result.validate()
        #expect(result.outcome == .oracleFailure)
        #expect(result.telemetry.readCount == 2)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("failure telemetry read failed") })
    }

    @Test
    func ang001BindingContractRejectsMissingAndDuplicateAndIdentifiesSwappedOrder() throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
        let steps = [
            CADCandidateStepResult(
                stepIndex: 0,
                operation: "first",
                status: .published,
                primaryFeatureID: UUID().uuidString,
                createdFeatureIDs: []
            ),
            CADCandidateStepResult(
                stepIndex: 1,
                operation: "second",
                status: .published,
                primaryFeatureID: UUID().uuidString,
                createdFeatureIDs: []
            ),
        ]
        let missing = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
        ])
        let duplicate = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .primary),
        ])
        let swapped = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 1, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .primary),
        ])

        #expect(throws: CADBenchmarkError.self) {
            try missing.validate(for: challenge, availableStepResults: steps)
        }
        #expect(throws: CADBenchmarkError.self) {
            try duplicate.validate(for: challenge, availableStepResults: steps)
        }
        try swapped.validate(for: challenge, availableStepResults: steps)
        #expect(swapped.bindings != [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary),
        ])
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func ang001OracleRejectsMissingExtraSubstituteAndSwappedProductionSources() async throws {
        let commands = try exactAngleCommands()
        let missing = try await productionRecord(commands: [commands[0]])
        try expectOracleMismatch(
            record: missing,
            bindings: CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            ])
        )

        let extra = try await productionRecord(commands: commands + [commands[0]])
        try expectOracleMismatch(record: extra, bindings: canonicalBindings())

        let plane = try angleSourcePlane()
        let substitute = AutomationCommand.createCircleSketch(
            name: "ANG-001.substitute",
            plane: plane,
            center: SketchPoint(
                x: .constant(.length(0, unit: .meter)),
                y: .constant(.length(0, unit: .meter))
            ),
            radius: .constant(.length(0.01, unit: .meter))
        )
        let substituted = try await productionRecord(commands: [commands[0], substitute])
        try expectOracleMismatch(record: substituted, bindings: canonicalBindings())

        let exact = try await productionRecord(commands: commands)
        try expectOracleMismatch(
            record: exact,
            bindings: CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "first-line", stepIndex: 1, selector: .primary),
                CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .primary),
            ])
        )
    }

    private func angleAction(
        firstStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 15, y: 0, z: 35, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 25 * 0.866025403784,
            y: 12.5,
            z: 35,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-001",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle002Action(
        firstStart: CADPoint3D = CADPoint3D(x: 10, y: -10, z: 50, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 40, y: -10, z: 50, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 10, y: -10, z: 50, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 10 + 50 * 0.707106781187,
            y: -10 + 50 * 0.707106781187,
            z: 50,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-002",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle003Action(
        firstStart: CADPoint3D = CADPoint3D(x: -25, y: 15, z: 125, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 20, y: 15, z: 125, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: -25, y: 15, z: 125, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: -25 + 75 * 0.5,
            y: 15 + 75 * 0.866025403784,
            z: 125,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-003",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle004Action(
        firstStart: CADPoint3D = CADPoint3D(x: 30, y: 25, z: 150, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 90, y: 25, z: 150, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 30, y: 25, z: 150, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 30 + 100 * 0.258819045103,
            y: 25 + 100 * 0.965925826289,
            z: 150,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-004",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle005Action(
        firstStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 200, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 75, y: 0, z: 200, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 200, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(x: 0, y: 125, z: 200, unit: .millimeter)
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-005",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle006Action(
        firstStart: CADPoint3D = CADPoint3D(x: -50, y: 40, z: 250, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 40, y: 40, z: 250, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: -50, y: 40, z: 250, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: -50 - 150 * 0.258819045103,
            y: 40 + 150 * 0.965925826289,
            z: 250,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-006",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle007Action(
        firstStart: CADPoint3D = CADPoint3D(x: 20, y: -35, z: 300, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 125, y: -35, z: 300, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 20, y: -35, z: 300, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 20 - 200 * 0.5,
            y: -35 + 200 * 0.866025403784,
            z: 300,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-007",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle008Action(
        firstStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 350, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 120, y: 0, z: 350, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 350, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: -250 * 0.707106781187,
            y: 250 * 0.707106781187,
            z: 350,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-008",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle009Action(
        firstStart: CADPoint3D = CADPoint3D(x: 75, y: 50, z: 400, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 210, y: 50, z: 400, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 75, y: 50, z: 400, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 75 - 300 * 0.866025403784,
            y: 50 + 300 * 0.5,
            z: 400,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-009",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle010Action(
        firstStart: CADPoint3D = CADPoint3D(x: -75, y: -50, z: 450, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 75, y: -50, z: 450, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: -75, y: -50, z: 450, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: -75 - 350 * 0.965925826289,
            y: -50 + 350 * 0.258819045103,
            z: 450,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-010",
                    plane: .xy,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle011Action(
        firstStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 80, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 30, y: 0, z: 80, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 0, y: 0, z: 80, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 60 * 0.707106781187,
            y: 0,
            z: 80 + 60 * 0.707106781187,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-011",
                    plane: .xz,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angle012Action(
        firstStart: CADPoint3D = CADPoint3D(x: 10, y: -20, z: 120, unit: .millimeter),
        firstEnd: CADPoint3D = CADPoint3D(x: 10, y: 20, z: 120, unit: .millimeter),
        secondStart: CADPoint3D = CADPoint3D(x: 10, y: -20, z: 120, unit: .millimeter),
        secondEnd: CADPoint3D = CADPoint3D(
            x: 10,
            y: -20 + 100 * 0.5,
            z: 120 + 100 * 0.866025403784,
            unit: .millimeter
        )
    ) -> CADCandidateAction {
        .automation(
            .sketch(
                .angle(
                    name: "ANG-012",
                    plane: .yz,
                    firstStart: firstStart,
                    firstEnd: firstEnd,
                    secondStart: secondStart,
                    secondEnd: secondEnd
                )
            )
        )
    }

    private func angleSourcePlane() throws -> SketchPlaneReference {
        let sourcePlane = try CADAngleGeometryMapping.sourcePlane(
            orientation: .xy,
            intersection: CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
            modelingTolerance: .standard,
            caseID: "ANG-001"
        )
        return SketchPlaneReference(sketchPlane: sourcePlane)
    }

    private func lineCommand(
        name: String,
        plane: SketchPlaneReference,
        start: Point2D,
        end: Point2D
    ) -> AutomationCommand {
        .createLineSketch(
            name: name,
            plane: plane,
            start: SketchPoint(
                x: .constant(.length(start.x, unit: .meter)),
                y: .constant(.length(start.y, unit: .meter))
            ),
            end: SketchPoint(
                x: .constant(.length(end.x, unit: .meter)),
                y: .constant(.length(end.y, unit: .meter))
            )
        )
    }

    @MainActor
    private func exactAngleCommands() throws -> [AutomationCommand] {
        let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
        let projection = try CADAngleChallengeProjection.decode(challenge)
        let sourcePlane = try CADAngleGeometryMapping.sourcePlane(
            orientation: projection.orientation,
            intersection: projection.intersection,
            modelingTolerance: .standard,
            caseID: "ANG-001"
        )
        let points = [
            projection.intersection,
            projection.firstEnd,
            projection.intersection,
            projection.secondEnd,
        ]
        let local = try points.enumerated().map { index, point in
            try CADAngleGeometryMapping.localPoint(
                from: point,
                sourcePlane: sourcePlane,
                modelingTolerance: .standard,
                caseID: "ANG-001",
                field: "fixture.\(index)"
            )
        }
        let reference = SketchPlaneReference(sketchPlane: sourcePlane)
        return [
            lineCommand(
                name: "ANG-001.first-line",
                plane: reference,
                start: local[0],
                end: local[1]
            ),
            lineCommand(
                name: "ANG-001.second-line",
                plane: reference,
                start: local[2],
                end: local[3]
            ),
        ]
    }

    @MainActor
    private func productionRecord(
        commands: [AutomationCommand]
    ) async throws -> CADCaseLifecycleRecord {
        let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
        let harness = CADCaseLifecycleHarness(
            caseID: "ANG-001",
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: "createAngleLines.fixture",
                planBuilder: { _, _, _ in .batch(commands) }
            ),
            timeoutWallNanoseconds: 10_000_000_000
        )
        return try await harness.run(action: angleAction())
    }

    private func canonicalBindings() -> CADOutputRoleBindings {
        CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary),
        ])
    }

    private func expectOracleMismatch(
        record: CADCaseLifecycleRecord,
        bindings: CADOutputRoleBindings
    ) throws {
        let view = try #require(record.finalView)
        guard let response = record.response,
              case .batch(let batch) = response else {
            Issue.record("The production fixture did not return one batch response.")
            return
        }
        let steps = batch.results.enumerated().map { index, result in
            CADCandidateStepResult(
                stepIndex: index,
                operation: "fixture.\(index)",
                status: result.didMutate ? .published : .unchanged,
                primaryFeatureID: result.primaryFeatureID?.description,
                createdFeatureIDs: result.createdFeatureIDs.map(\.description)
            )
        }
        let entry = try CADActivatedAngleCase.ang001.catalogEntry
        guard case .angle(let expected) = entry.expected else {
            Issue.record("ANG-001 has no private angle expectation.")
            return
        }
        #expect(throws: CADAngleOracleError.self) {
            try CADAngleOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                bindings: bindings,
                stepResults: steps,
                snapshot: view
            )
        }
    }
}

private enum FailureSourceReadError: Error {
    case unavailable
}
