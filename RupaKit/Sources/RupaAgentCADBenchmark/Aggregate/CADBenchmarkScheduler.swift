import Foundation

@MainActor
struct CADBenchmarkScheduler {
    typealias PostDrainHook = @MainActor @Sendable () async -> Void

    private let runner: CADBenchmarkReferenceRunner
    private let postDrainHook: PostDrainHook?

    init(
        runner: CADBenchmarkReferenceRunner = CADBenchmarkReferenceRunner(),
        postDrainHook: PostDrainHook? = nil
    ) {
        self.runner = runner
        self.postDrainHook = postDrainHook
    }

    func run(
        configuration: CADBenchmarkRunConfiguration
    ) async throws -> CADBenchmarkScheduledRun {
        try await runBounded(configuration: configuration)
    }

    func runUsingExecutionPolicy() async throws -> CADBenchmarkScheduledRun {
        try await run(
            configuration: CADBenchmarkExecutionPolicy.configuration(),
            wholeRunDeadlineNanoseconds:
                CADBenchmarkExecutionPolicy.wholeRunDeadlineNanoseconds
        )
    }

    func run(
        configuration: CADBenchmarkRunConfiguration,
        wholeRunDeadlineNanoseconds: UInt64
    ) async throws -> CADBenchmarkScheduledRun {
        guard wholeRunDeadlineNanoseconds > 0 else {
            throw CADBenchmarkScheduleError.invalidWholeRunDeadline
        }
        return try await withThrowingTaskGroup(of: CADBenchmarkScheduledRun.self) { group in
            group.addTask {
                try await runBounded(configuration: configuration)
            }
            group.addTask {
                let delay = Int64(min(wholeRunDeadlineNanoseconds, UInt64(Int64.max)))
                try await Task.sleep(for: .nanoseconds(delay))
                throw CADBenchmarkDeadlineMarker()
            }

            do {
                guard let completed = try await group.next() else {
                    throw CADBenchmarkScheduleError.invalidMeasurement
                }
                group.cancelAll()
                await Self.drain(group: &group)
                return completed
            } catch is CADBenchmarkDeadlineMarker {
                group.cancelAll()
                let drain = await Self.drainAfterDeadline(group: &group)
                try drain.validate()
                throw CADBenchmarkScheduleError.deadlineExceeded(drain)
            } catch {
                let firstError = error
                group.cancelAll()
                await Self.drain(group: &group)
                throw firstError
            }
        }
    }

    private func runBounded(
        configuration: CADBenchmarkRunConfiguration
    ) async throws -> CADBenchmarkScheduledRun {
        let manifest = try runner.validatedManifest()
        guard !Task.isCancelled else {
            throw CADBenchmarkScheduleError.cancelled(.empty)
        }

        let start = Self.now()
        let probe = CADBenchmarkInFlightProbe()
        let registrationLedger = CADBenchmarkRegistrationLedger()
        let mainActorProbe = CADBenchmarkMainActorEntryProbe()
        var ordered = Array<CADActivatedCaseExecution?>(
            repeating: nil,
            count: manifest.orderedCaseIDs.count
        )

        do {
            try await CADBenchmarkRegistrationObservation.$ledger.withValue(
                registrationLedger
            ) {
                try await withThrowingTaskGroup(of: CADBenchmarkIndexedExecution.self) { group in
                    var nextIndex = 0

                    func admit(_ index: Int) {
                        let caseID = manifest.orderedCaseIDs[index]
                        group.addTask {
                            await probe.started()
                            do {
                                try Task.checkCancellation()
                                await Task.yield()
                                await mainActorProbe.observeEntry()
                                let execution = try await runner.executeReference(caseID: caseID)
                                await probe.completed()
                                let expectedOutcome: CADCaseOutcome =
                                    execution.publicResult.category == .sphere
                                        ? .expectedUnsupported
                                        : .realized
                                guard execution.publicResult.outcome == expectedOutcome,
                                      execution.regressionRecord.capabilityDecisionCorrect else {
                                    throw CADBenchmarkChildFailure(
                                        caseID: caseID,
                                        wasCancelled:
                                            execution.publicResult.outcome == .cancellation
                                    )
                                }
                                return CADBenchmarkIndexedExecution(
                                    index: index,
                                    execution: execution
                                )
                            } catch let failure as CADBenchmarkChildFailure {
                                throw failure
                            } catch {
                                await probe.completed()
                                throw CADBenchmarkChildFailure(
                                    caseID: caseID,
                                    wasCancelled: error is CancellationError || Task.isCancelled
                                )
                            }
                        }
                    }

                    while nextIndex < configuration.maximumConcurrentCases,
                          nextIndex < manifest.orderedCaseIDs.count {
                        admit(nextIndex)
                        nextIndex += 1
                    }

                    do {
                        while let completed = try await group.next() {
                            ordered[completed.index] = completed.execution
                            if nextIndex < manifest.orderedCaseIDs.count {
                                admit(nextIndex)
                                nextIndex += 1
                            }
                        }
                    } catch {
                        let firstError = error
                        group.cancelAll()
                        while true {
                            do {
                                guard try await group.next() != nil else { break }
                            } catch {
                                continue
                            }
                        }
                        throw firstError
                    }
                }
            }
        } catch let failure as CADBenchmarkChildFailure {
            let drain = await drainEvidence(
                probe: probe,
                registrationLedger: registrationLedger
            )
            try drain.validate()
            if failure.wasCancelled || Task.isCancelled {
                throw CADBenchmarkScheduleError.cancelled(drain)
            }
            throw CADBenchmarkScheduleError.executionFailed(failure.caseID, drain)
        } catch is CancellationError {
            let drain = await drainEvidence(
                probe: probe,
                registrationLedger: registrationLedger
            )
            try drain.validate()
            throw CADBenchmarkScheduleError.cancelled(drain)
        }

        let drain = await drainEvidence(
            probe: probe,
            registrationLedger: registrationLedger
        )
        try drain.validate()
        if let postDrainHook {
            await postDrainHook()
        }
        guard !Task.isCancelled else {
            throw CADBenchmarkScheduleError.cancelled(drain)
        }
        let executions = ordered.compactMap { $0 }
        guard executions.count == manifest.orderedCaseIDs.count else {
            throw CADBenchmarkReferenceRunError.incompleteRun(
                expected: manifest.orderedCaseIDs.count,
                actual: executions.count
            )
        }
        let attempt = try CADBenchmarkReferenceRunAttempt(
            manifest: manifest,
            executions: executions
        )
        let peakInFlightCases = await probe.peakInFlightCases()
        guard !Task.isCancelled else {
            throw CADBenchmarkScheduleError.cancelled(drain)
        }
        let measurement = CADBenchmarkRunMeasurement(
            requestedConcurrency: configuration.maximumConcurrentCases,
            observedInFlightCases: peakInFlightCases,
            observedMainActorEntryConcurrency: mainActorProbe.peakConcurrency,
            wholeRunWallNanoseconds: max(1, Self.now() - start),
            cases: attempt.measurements
        )
        return try CADBenchmarkScheduledRun(
            attempt: attempt,
            measurement: measurement,
            drainEvidence: drain
        )
    }

    private func drainEvidence(
        probe: CADBenchmarkInFlightProbe,
        registrationLedger: CADBenchmarkRegistrationLedger
    ) async -> CADBenchmarkDrainEvidence {
        let lifecycle = await probe.lifecycleCounts()
        let remainingRegistrations = await registrationLedger.activeRegistrationCount()
        return CADBenchmarkDrainEvidence(
            startedCases: lifecycle.started,
            completedCases: lifecycle.completed,
            activeCasesAfterDrain: lifecycle.active,
            remainingRegistrations: remainingRegistrations
        )
    }

    private static func drain(
        group: inout ThrowingTaskGroup<CADBenchmarkScheduledRun, any Error>
    ) async {
        while true {
            do {
                guard try await group.next() != nil else { break }
            } catch {
                continue
            }
        }
    }

    private static func drainAfterDeadline(
        group: inout ThrowingTaskGroup<CADBenchmarkScheduledRun, any Error>
    ) async -> CADBenchmarkDrainEvidence {
        var observedDrain = CADBenchmarkDrainEvidence.empty
        while true {
            do {
                guard let completed = try await group.next() else { break }
                observedDrain = completed.drainEvidence
            } catch let error as CADBenchmarkScheduleError {
                if case .cancelled(let drain) = error {
                    observedDrain = drain
                }
            } catch {
                continue
            }
        }
        return observedDrain
    }

    private static func now() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded())
    }
}

private struct CADBenchmarkIndexedExecution: Sendable {
    let index: Int
    let execution: CADActivatedCaseExecution
}

private struct CADBenchmarkChildFailure: Error, Sendable {
    let caseID: CADBenchmarkCaseID
    let wasCancelled: Bool
}

private struct CADBenchmarkDeadlineMarker: Error, Sendable {}

private actor CADBenchmarkInFlightProbe {
    private var startedCases = 0
    private var completedCases = 0
    private var activeCases = 0
    private var peakCases = 0

    func started() {
        startedCases += 1
        activeCases += 1
        peakCases = max(peakCases, activeCases)
    }

    func completed() {
        completedCases += 1
        activeCases -= 1
    }

    func peakInFlightCases() -> Int {
        peakCases
    }

    func lifecycleCounts() -> (started: Int, completed: Int, active: Int) {
        (startedCases, completedCases, activeCases)
    }
}

@MainActor
private final class CADBenchmarkMainActorEntryProbe {
    private var activeEntries = 0
    private(set) var peakConcurrency = 0

    func observeEntry() {
        activeEntries += 1
        peakConcurrency = max(peakConcurrency, activeEntries)
        activeEntries -= 1
    }
}
