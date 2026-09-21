import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBenchmarkIntegratedExecutionTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executionPolicyCompletesAndMatchesTheCommittedCanonicalFixture() async throws {
        let scheduledRun = try await CADBenchmarkScheduler().runUsingExecutionPolicy()

        try scheduledRun.attempt.validate()
        try scheduledRun.drainEvidence.validate()
        #expect(scheduledRun.attempt.executions.count == 100)
        #expect(
            scheduledRun.attempt.publicResults.map(\.id)
                == scheduledRun.attempt.manifest.orderedCaseIDs
        )
        #expect(scheduledRun.drainEvidence.startedCases == 100)
        #expect(scheduledRun.drainEvidence.completedCases == 100)
        #expect(scheduledRun.drainEvidence.activeCasesAfterDrain == 0)
        #expect(scheduledRun.drainEvidence.remainingRegistrations == 0)
        #expect(
            scheduledRun.measurement.requestedConcurrency
                == CADBenchmarkExecutionPolicy.maximumConcurrentCases
        )
        #expect(scheduledRun.measurement.observedInFlightCases == 1)
        #expect(scheduledRun.measurement.observedMainActorEntryConcurrency == 1)
        #expect(
            scheduledRun.measurement.wholeRunWallNanoseconds
                < CADBenchmarkExecutionPolicy.wholeRunDeadlineNanoseconds
        )

        let builder = CADBenchmarkAggregateBuilder()
        let established = try builder.build(
            run: scheduledRun,
            mode: .establish(existing: nil)
        )
        let compared = try builder.build(
            run: scheduledRun,
            mode: .compare(expected: established.executionBaseline)
        )
        #expect(compared.report.status == .valid)
        #expect(compared.report.baselineDrifts.isEmpty)
        #expect(compared.executionBaseline == established.executionBaseline)

        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "t12-reference-execution-v1",
                withExtension: "json"
            )
        )
        let fixture = try Data(contentsOf: fixtureURL)
        #expect(try established.report.canonicalJSON() == fixture)
        #expect(try compared.report.canonicalJSON() == fixture)
    }
}
