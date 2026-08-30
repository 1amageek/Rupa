import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBenchmarkSerialIntegrationTests {
    @MainActor
    @Test(.timeLimit(.minutes(5)))
    func completeReferenceRunReplaysLexicalHundredWithDeterministicDetailedEvidence() async throws {
        let runner = CADBenchmarkReferenceRunner()
        let attempt = try await runner.runSerial()

        try attempt.validate()
        #expect(attempt.executions.count == 100)
        #expect(attempt.publicResults.map(\.id) == attempt.manifest.orderedCaseIDs)
        #expect(attempt.publicResults.filter { $0.outcome == .realized }.count == 95)
        #expect(attempt.publicResults.filter { $0.outcome == .expectedUnsupported }.count == 5)
        #expect(attempt.publicResults.allSatisfy { $0.durationMilliseconds != nil })
        #expect(attempt.regressionRecords.allSatisfy { $0.capabilityDecisionCorrect })
        #expect(attempt.regressionRecords.allSatisfy { $0.route.cleanupCompleted })
        #expect(attempt.regressionRecords.allSatisfy { $0.route.remainingRegistrationCount == 0 })
        #expect(attempt.regressionRecords.filter {
            $0.oracleDisposition == .expectedUnsupported
        }.map(\.caseID) == ["SPH-001", "SPH-002", "SPH-003", "SPH-004", "SPH-005"])

        for (caseID, record) in zip(
            attempt.manifest.orderedCaseIDs,
            attempt.regressionRecords
        ) {
            let direct = try await CADDirectReferenceProjection.run(caseID: caseID)
            #expect(direct.caseID == record.caseID)
            #expect(direct.outcome == record.outcome)
            #expect(direct.route == record.route)
            #expect(direct.counts == record.counts)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func activationMismatchAndDuplicateAbortBeforeAnyCaseExecution() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let missing = Array(executor.activatedCaseIDs.dropLast())
        do {
            _ = try await CADBenchmarkReferenceRunner(
                executor: executor,
                activatedCaseIDs: missing
            ).runSerial()
            Issue.record("A missing activation must abort the complete run.")
        } catch let error as CADBenchmarkReferenceRunError {
            #expect(error == .incompleteRun(expected: 100, actual: 99))
        }

        var duplicate = executor.activatedCaseIDs
        duplicate[duplicate.count - 1] = duplicate[0]
        do {
            _ = try await CADBenchmarkReferenceRunner(
                executor: executor,
                activatedCaseIDs: duplicate
            ).runSerial()
            Issue.record("A duplicate activation must abort the complete run.")
        } catch let error as CADBenchmarkReferenceRunError {
            #expect(error == .duplicateCase(duplicate[0]))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func mismatchedDetailedExecutionCannotBecomeACompleteAttempt() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let lineID = CADBenchmarkCaseID(rawValue: "LIN-001")
        let lineContext = try executor.context(for: lineID)
        let lineCandidate = try CADReferenceCandidateFactory.candidate(for: lineContext)
        let lineExecution = try await executor.executeDetailed(
            caseID: lineID,
            candidate: lineCandidate
        )
        let firstLexicalID = try #require(CADBenchmarkCatalog().manifest.orderedCaseIDs.first)

        do {
            _ = try await CADBenchmarkReferenceRunner(
                executor: executor,
                executionOverride: { _, _ in lineExecution }
            ).runSerial()
            Issue.record("A mismatched detailed execution must abort the attempt.")
        } catch let error as CADBenchmarkReferenceRunError {
            #expect(error == .invalidEvidence(firstLexicalID))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func validDetailedFailurePreservesItsCaseIDAsAnInvalidOutcome() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let lineID = CADBenchmarkCaseID(rawValue: "LIN-001")
        let wrong = CADCandidateAction.automation(.sketch(.line(
            name: "LIN-001.aggregate-invalid-outcome",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            end: CADPoint3D(x: 30, y: 0, z: 0, unit: .millimeter)
        )))
        let invalidResult = try await CADLineCaseRunner(case: .lin001).run(action: wrong)
        #expect(invalidResult.outcome == .invalidSubmission)
        let invalidExecution = try CADActivatedCaseExecution(
            context: executor.context(for: lineID),
            evidence: .line(invalidResult)
        )

        do {
            _ = try await CADBenchmarkReferenceRunner(
                executor: executor,
                executionOverride: { caseID, candidate in
                    if caseID == lineID {
                        return invalidExecution
                    }
                    return try await executor.executeDetailed(
                        caseID: caseID,
                        candidate: candidate
                    )
                }
            ).runSerial()
            Issue.record("A complete run with a failed case must preserve the failing case ID.")
        } catch let error as CADBenchmarkReferenceRunError {
            #expect(error == .invalidOutcome(lineID))
        }
    }
}
