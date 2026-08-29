import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADConstraintCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func replaysAllActivatedConstraintsThroughTheProductionRoute() async throws {
        let expectedCases: [CADActivatedConstraintCase] = [
            .constraint001, .constraint002, .constraint003, .constraint004,
            .constraint005, .constraint006, .constraint007, .constraint008,
        ]
        let expectedRelations: [CADConstraintRelation] = [
            .coincident, .parallel, .perpendicular, .horizontal,
            .vertical, .equalLength, .concentric, .equalRadius,
        ]
        let expectedEntityCounts = [2, 2, 2, 1, 1, 2, 2, 2]

        #expect(CADActivatedConstraintCase.allCases == expectedCases)
        #expect(expectedCases.count == 8)
        #expect(Set(expectedCases).count == 8)

        let catalog = try CADBenchmarkCatalog()
        var observedRelations: [CADConstraintRelation] = []
        var lineCaseCount = 0
        var circleCaseCount = 0
        var unaryRelationCount = 0
        var binaryRelationCount = 0
        var observedEntityCounts: [Int] = []

        for activatedCase in expectedCases {
            let projection = try CADConstraintChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            observedRelations.append(projection.relation)
            #expect(projection.plane == .xy)

            switch projection.first {
            case let .line(start, end):
                lineCaseCount += 1
                #expect(start.unit == .millimeter)
                #expect(end.unit == .millimeter)
                if let second = projection.second {
                    guard case let .line(secondStart, secondEnd) = second else {
                        Issue.record("A line constraint has a non-line second geometry.")
                        continue
                    }
                    #expect(secondStart.unit == .millimeter)
                    #expect(secondEnd.unit == .millimeter)
                }
            case let .circle(center, radius):
                circleCaseCount += 1
                #expect(center.unit == .millimeter)
                #expect(radius.unit == .millimeter)
                guard let second = projection.second,
                      case let .circle(secondCenter, secondRadius) = second else {
                    Issue.record("A circle constraint requires a second circle.")
                    continue
                }
                #expect(secondCenter.unit == .millimeter)
                #expect(secondRadius.unit == .millimeter)
            }
            if projection.second == nil {
                unaryRelationCount += 1
            } else {
                binaryRelationCount += 1
            }

            let result = try await CADConstraintCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.realized)
            #expect(result.candidateResult?.status == .published)
            #expect(result.candidateResult?.createdFeatureIDs.count == 1)
            #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
            #expect(result.roleBindings?.bindings.count == 1)
            #expect(result.roleBindings?.bindings.first?.role == "relation")

            #expect(result.routeEvidence.didPublish)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence + 1
            )
            #expect(
                result.routeEvidence.finalDocumentGeneration.value
                    == result.routeEvidence.initialDocumentGeneration.value + 1
            )
            #expect(
                result.routeEvidence.finalTransactionRevision.value
                    == result.routeEvidence.initialTransactionRevision.value + 1
            )
            #expect(
                result.routeEvidence.finalWorkspaceRevision
                    == result.routeEvidence.initialWorkspaceRevision
            )
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)

            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 0)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
            observedEntityCounts.append(result.telemetry.entityCount)
        }

        #expect(observedRelations == expectedRelations)
        #expect(lineCaseCount == 6)
        #expect(circleCaseCount == 2)
        #expect(unaryRelationCount == 2)
        #expect(binaryRelationCount == 6)
        #expect(observedEntityCounts == expectedEntityCounts)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorRetainsExactConstraintSuffixAndTransformBoundary() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let expectedConstraints = CADActivatedConstraintCase.allCases.map(\.caseID)

        #expect(executor.activatedCaseIDs.count == 81)
        #expect(Array(executor.activatedCaseIDs.prefix(80).suffix(8)) == expectedConstraints)
        #expect(executor.activatedCaseIDs.last == "TRN-001")
        do {
            _ = try executor.context(for: "TRN-002")
            Issue.record("TRN-002 must remain inactive until its vertical gate.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("TRN-002"))
        }
    }
}
