import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBenchmarkConcurrencyTests {
    @MainActor
    @Test(.timeLimit(.minutes(3)))
    func boundedParallelRunPreservesSerialEvidenceAndLexicalOrder() async throws {
        let scheduler = CADBenchmarkScheduler()
        let serial = try await scheduler.run(
            configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 1)
        )
        let parallel = try await scheduler.run(
            configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 2)
        )

        #expect(serial.attempt.regressionRecords == parallel.attempt.regressionRecords)
        #expect(serial.attempt.publicResults.map(\.id) == serial.attempt.manifest.orderedCaseIDs)
        #expect(parallel.attempt.publicResults.map(\.id) == parallel.attempt.manifest.orderedCaseIDs)
        #expect(serial.measurement.observedInFlightCases == 1)
        #expect(parallel.measurement.observedInFlightCases == 2)
        #expect(serial.measurement.observedMainActorEntryConcurrency == 1)
        #expect(parallel.measurement.observedMainActorEntryConcurrency == 1)
        try serial.drainEvidence.validate()
        try parallel.drainEvidence.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func firstFatalFailureCancelsAndDrainsEveryAdmittedChild() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let firstID = try #require(CADBenchmarkCatalog().manifest.orderedCaseIDs.first)
        let wrongAngle = CADCandidateAction.automation(.sketch(.angle(
            name: "ANG-001.scheduler-postpublication-failure",
            plane: .xy,
            firstStart: CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
            firstEnd: CADPoint3D(x: 15, y: 0, z: 35, unit: .millimeter),
            secondStart: CADPoint3D(x: 1, y: 0, z: 35, unit: .millimeter),
            secondEnd: CADPoint3D(
                x: 1 + 25 * 0.866025403784,
                y: 12.5,
                z: 35,
                unit: .millimeter
            )
        )))
        let runner = CADBenchmarkReferenceRunner(
            executor: executor,
            executionOverride: { caseID, candidate in
                if caseID == firstID {
                    let result = try await CADAngleCaseRunner(case: .ang001).run(
                        action: wrongAngle
                    )
                    guard result.outcome == .invalidSubmission,
                          result.routeEvidence.didPublish,
                          result.routeEvidence.remainingRegistrationCount == 0 else {
                        throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
                    }
                    return try CADActivatedCaseExecution(
                        context: executor.context(for: caseID),
                        evidence: .angle(result)
                    )
                }
                try await Task.sleep(for: .seconds(5))
                return try await executor.executeDetailed(
                    caseID: caseID,
                    candidate: candidate
                )
            }
        )

        do {
            _ = try await CADBenchmarkScheduler(runner: runner).run(
                configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 2)
            )
            Issue.record("The first fatal child failure must abort the complete run.")
        } catch let error as CADBenchmarkScheduleError {
            guard case .executionFailed(let caseID, let drain) = error else {
                Issue.record("Expected an executionFailed schedule error, got \(error).")
                return
            }
            #expect(caseID == firstID)
            #expect(drain.startedCases == 2)
            #expect(drain.completedCases == 2)
            try drain.validate()
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wholeRunDeadlineCancelsAndDrainsAdmittedChildren() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let runner = CADBenchmarkReferenceRunner(
            executor: executor,
            executionOverride: { caseID, candidate in
                try await Task.sleep(for: .seconds(5))
                return try await executor.executeDetailed(
                    caseID: caseID,
                    candidate: candidate
                )
            }
        )
        do {
            _ = try await CADBenchmarkScheduler(runner: runner).run(
                configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 2),
                wholeRunDeadlineNanoseconds: 50_000_000
            )
            Issue.record("The whole-run deadline must abort the complete run.")
        } catch let error as CADBenchmarkScheduleError {
            guard case .deadlineExceeded(let drain) = error else {
                Issue.record("Expected deadlineExceeded, got \(error).")
                return
            }
            #expect(drain.startedCases == 2)
            #expect(drain.completedCases == 2)
            try drain.validate()
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func cancellationAfterChildDrainCannotPublishASuccessfulAttempt() async throws {
        let scheduler = CADBenchmarkScheduler(postDrainHook: {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        })
        do {
            _ = try await scheduler.run(
                configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 1)
            )
            Issue.record("Cancellation after child drain must prevent publication.")
        } catch let error as CADBenchmarkScheduleError {
            guard case .cancelled(let drain) = error else {
                Issue.record("Expected a cancelled schedule error, got \(error).")
                return
            }
            #expect(drain.startedCases == 100)
            #expect(drain.completedCases == 100)
            try drain.validate()
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationBeforeAndDuringSchedulingReturnsDrainedEvidence() async throws {
        let configuration = try CADBenchmarkRunConfiguration(maximumConcurrentCases: 2)
        let preCancelled = Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await CADBenchmarkScheduler().run(configuration: configuration)
        }
        do {
            _ = try await preCancelled.value
            Issue.record("A pre-cancelled run must not admit a case.")
        } catch let error as CADBenchmarkScheduleError {
            #expect(error == .cancelled(.empty))
        }

        let executor = DefaultCADActivatedCaseExecutor()
        let runner = CADBenchmarkReferenceRunner(
            executor: executor,
            executionOverride: { caseID, candidate in
                try await Task.sleep(for: .seconds(5))
                return try await executor.executeDetailed(
                    caseID: caseID,
                    candidate: candidate
                )
            }
        )
        let midRun = Task { @MainActor in
            try await CADBenchmarkScheduler(runner: runner).run(configuration: configuration)
        }
        try await Task.sleep(for: .milliseconds(50))
        midRun.cancel()

        do {
            _ = try await midRun.value
            Issue.record("A cancelled run must not publish a complete attempt.")
        } catch let error as CADBenchmarkScheduleError {
            guard case .cancelled(let drain) = error else {
                Issue.record("Expected a cancelled schedule error, got \(error).")
                return
            }
            #expect(drain.startedCases == 2)
            #expect(drain.completedCases == 2)
            try drain.validate()
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(5)))
    func alternatingExperimentMeasuresSixEquivalentRunsAndSelectsByNoiseBound() async throws {
        let result = try await CADBenchmarkConcurrencyExperiment().run()

        try result.validate()
        #expect(result.serialMeasurements.count == 3)
        #expect(result.parallelMeasurements.count == 3)
        #expect(result.parallelMeasurements.allSatisfy { $0.observedInFlightCases == 2 })
        #expect(result.serialMeasurements.allSatisfy {
            $0.observedMainActorEntryConcurrency == 1
        })
        #expect(result.parallelMeasurements.allSatisfy {
            $0.observedMainActorEntryConcurrency == 1
        })
        #expect(result.regressionRecords.count == 100)
        #expect(result.wholeRunDeadlineSeconds < 1_000)

        let serialWalls = result.serialMeasurements.map(\.wholeRunWallNanoseconds)
        let parallelWalls = result.parallelMeasurements.map(\.wholeRunWallNanoseconds)
        let serialMedian = serialWalls.sorted()[1]
        let parallelMedian = parallelWalls.sorted()[1]
        let improvement = serialMedian > parallelMedian ? serialMedian - parallelMedian : 0
        let serialRange = try #require(serialWalls.max()) - (try #require(serialWalls.min()))
        let parallelRange = try #require(parallelWalls.max()) - (try #require(parallelWalls.min()))
        let expectedConcurrency = improvement > max(serialRange, parallelRange) ? 2 : 1
        #expect(result.selectedConfiguration.maximumConcurrentCases == expectedConcurrency)
        print(
            "T12-I.2 measurement serial=\(serialWalls) parallel=\(parallelWalls) "
                + "selected=\(expectedConcurrency) deadline=\(result.wholeRunDeadlineSeconds)s"
        )
    }

    @Test
    func configurationRejectsUnboundedConcurrency() {
        #expect(CADBenchmarkExecutionPolicy.maximumConcurrentCases == 1)
        #expect(CADBenchmarkExecutionPolicy.wholeRunDeadlineSeconds == 38)
        for invalid in [0, 3, 100] {
            do {
                _ = try CADBenchmarkRunConfiguration(maximumConcurrentCases: invalid)
                Issue.record("Concurrency \(invalid) must be rejected.")
            } catch let error as CADBenchmarkScheduleError {
                #expect(error == .invalidConcurrency(invalid))
            } catch {
                Issue.record("Unexpected error for concurrency \(invalid): \(error)")
            }
        }
    }
}
