import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func replaysTheCompleteSphereCategoryThroughTheProductionCapabilityRoute() async throws {
        let expectedCases: [CADActivatedSphereCase] = [
            .sphere001, .sphere002, .sphere003, .sphere004, .sphere005,
        ]
        #expect(CADActivatedSphereCase.allCases == expectedCases)
        #expect(
            CADActivatedSphereCase.allCases.map(\.caseID)
                == CADSpherePreparationCase.allCases.map(\.caseID)
        )

        let executor = DefaultCADActivatedCaseExecutor()
        let catalog = try CADBenchmarkCatalog()
        #expect(executor.activatedCaseIDs.count == 100)
        #expect(Set(executor.activatedCaseIDs) == Set(catalog.caseIDs))
        #expect(Array(executor.activatedCaseIDs.suffix(expectedCases.count)) == expectedCases.map(\.caseID))

        var centers: [CADPoint3D] = []
        var radiusUnits: [CADLengthUnit] = []
        for activatedCase in expectedCases {
            let entry = try activatedCase.preparedCase.catalogEntry
            guard case let .sphere(expected) = entry.input else {
                Issue.record("\(activatedCase.rawValue) must retain an analytic sphere target.")
                continue
            }
            centers.append(expected.center)
            radiusUnits.append(expected.radius.unit)

            let result = try await CADSphereCaseRunner(case: activatedCase).runReference()
            try result.validate()

            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .expectedUnsupported)
            #expect(result.realized == false)
            #expect(result.routeEvidence.capabilityObservedThroughController)
            #expect(result.routeEvidence.initialDocumentGeneration == result.routeEvidence.finalDocumentGeneration)
            #expect(result.routeEvidence.initialTransactionRevision == result.routeEvidence.finalTransactionRevision)
            #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
            #expect(result.routeEvidence.initialWorkspaceRevision == result.routeEvidence.finalWorkspaceRevision)
            #expect(result.routeEvidence.didPublish == false)
            #expect(result.routeEvidence.commandCount == 0)
            #expect(result.routeEvidence.sourceMutationCount == 0)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)

            #expect(result.telemetry.capabilityRequestCount == 1)
            #expect(result.telemetry.readCount == 1)
            #expect(result.telemetry.actionCount == 0)
            #expect(result.telemetry.commandCount == 0)
            #expect(result.telemetry.entityCount == 0)
            #expect(result.telemetry.featureCount == 0)
            #expect(result.telemetry.bodyCount == 0)
            #expect(result.telemetry.publicationCount == 0)
            #expect(result.telemetry.sourceMutationCount == 0)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds == 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)

            guard case let .unsupported(declaration) = result.candidateDecision else {
                Issue.record("\(activatedCase.rawValue) must return typed unsupported.")
                continue
            }
            #expect(declaration.reason == .analyticSphereUnavailable)
            #expect(declaration.capabilityID == "cad.solid.analytic-sphere")
            #expect(declaration.capabilityVersion == "1")
            guard case .analyticSphereUnavailable = result.capabilityError else {
                Issue.record("\(activatedCase.rawValue) must retain the typed capability observation.")
                continue
            }
        }

        #expect(radiusUnits.filter { $0 == .millimeter }.count == 3)
        #expect(radiusUnits.filter { $0 == .meter }.count == 1)
        #expect(radiusUnits.filter { $0 == .inch }.count == 1)
        #expect(centers == [
            CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            CADPoint3D(x: 50, y: -25, z: 10, unit: .millimeter),
            CADPoint3D(x: 0, y: 0, z: 0.1, unit: .meter),
            CADPoint3D(x: -2, y: 3, z: 1, unit: .inch),
            CADPoint3D(x: -100, y: 100, z: -50, unit: .millimeter),
        ])
    }
}
