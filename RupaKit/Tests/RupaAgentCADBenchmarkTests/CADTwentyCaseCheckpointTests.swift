import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADTwentyCaseCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func exactlyTwentyCasesReplaySeriallyWithReviewedCoverage() async throws {
        let lineCases = CADActivatedLineCase.allCases
        let rectangleCases = CADActivatedRectangleCase.allCases
        let activatedIDs = lineCases.map(\.rawValue) + rectangleCases.map(\.rawValue)
        #expect(activatedIDs == [
            "LIN-001", "LIN-002", "LIN-003", "LIN-004", "LIN-005", "LIN-006",
            "LIN-007", "LIN-008", "LIN-009", "LIN-010", "LIN-011", "LIN-012",
            "REC-001", "REC-002", "REC-003", "REC-004",
            "REC-005", "REC-006", "REC-007", "REC-008",
        ])
        #expect(Set(activatedIDs).count == 20)

        let catalog = try CADBenchmarkCatalog()
        var planes: [CADSketchPlane] = []
        var units: [CADLengthUnit] = []
        for activatedCase in lineCases {
            let projection = try CADLineChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            planes.append(projection.orientation)
            units.append(projection.length.unit)
        }
        for activatedCase in rectangleCases {
            let projection = try CADRectangleChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            planes.append(projection.orientation)
            units.append(projection.width.unit)
            #expect(projection.width.unit == projection.height.unit)
            #expect(projection.center.unit == projection.width.unit)
        }
        #expect(planes.filter { $0 == .xy }.count == 11)
        #expect(planes.filter { $0 == .xz }.count == 5)
        #expect(planes.filter { $0 == .yz }.count == 4)
        #expect(units.filter { $0 == .millimeter }.count == 14)
        #expect(units.filter { $0 == .centimeter }.count == 2)
        #expect(units.filter { $0 == .meter }.count == 3)
        #expect(units.filter { $0 == .inch }.count == 1)

        for activatedCase in lineCases {
            let result = try await CADLineCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 1)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 0)
        }
        for activatedCase in rectangleCases {
            let result = try await CADRectangleCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 4)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 0)
        }
    }

    @Test
    func twentyCaseBoundaryRejectsUnreviewedRectangleCases() throws {
        for caseID in ["REC-009", "REC-010", "REC-011", "REC-012"] {
            do {
                _ = try CADActivatedRectangleCase(caseID: caseID)
                Issue.record("\(caseID) must remain outside the first-twenty boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error,
                      observed == caseID else {
                    Issue.record("Unexpected typed error for \(caseID): \(error)")
                    continue
                }
            }
        }
    }
}
