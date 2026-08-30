import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBenchmarkBaselineReportTests {
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func completeSerialAndParallelRunsProduceTheCanonicalBaselineReport() async throws {
        let scheduler = CADBenchmarkScheduler()
        let builder = CADBenchmarkAggregateBuilder()
        let serial = try await scheduler.run(
            configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 1)
        )
        let established = try builder.build(
            run: serial,
            mode: .establish(existing: nil)
        )
        let parallel = try await scheduler.run(
            configuration: CADBenchmarkRunConfiguration(maximumConcurrentCases: 2)
        )
        let compared = try builder.build(
            run: parallel,
            mode: .compare(expected: established.executionBaseline)
        )

        #expect(established.capabilityBaseline.statuses.count == 10)
        #expect(established.report.status == .valid)
        #expect(established.report.baselineDrifts.isEmpty)
        #expect(established.report.score.totalCases == 100)
        #expect(established.report.score.realizedCases == 95)
        #expect(established.report.score.expectedUnsupportedCases == 5)
        #expect(established.report.score.supportedCases == 95)
        #expect(established.report.score.supportedRealizedCases == 95)
        #expect(established.report.score.capabilityDecisionTotal == 100)
        #expect(established.report.score.capabilityDecisionsCorrect == 100)
        #expect(established.report.results.allSatisfy {
            $0.durationMilliseconds == nil && $0.capabilityDecisionCorrect == true
        })
        #expect(try established.report.canonicalJSON() == compared.report.canonicalJSON())
        #expect(established.executionBaseline == compared.executionBaseline)

        do {
            _ = try builder.build(
                run: serial,
                mode: .establish(existing: established.executionBaseline)
            )
            Issue.record("An established baseline must never be overwritten implicitly.")
        } catch let error as CADBenchmarkBaselineError {
            #expect(error == .baselineAlreadyExists)
        }

        let driftEnvironment = try CADBenchmarkEnvironmentFingerprint(
            manifestDigest: established.executionBaseline.environment.manifestDigest,
            expectationDigest: established.executionBaseline.environment.expectationDigest,
            capabilityAvailabilityDigest:
                established.executionBaseline.environment.capabilityAvailabilityDigest,
            agentRouteVersion: "project-agent-command-controller.v2"
        )
        let driftBaseline = try CADExecutionRegressionBaseline(
            environment: driftEnvironment,
            records: established.executionBaseline.records
        )
        let drifted = try builder.build(
            run: serial,
            mode: .compare(expected: driftBaseline)
        )
        #expect(drifted.report.status == .baselineDrift)
        #expect(drifted.report.baselineDrifts == [.agentRoute])

        let historicalEnvironment = try CADBenchmarkEnvironmentFingerprint(
            manifestDigest: String(repeating: "0", count: 64),
            expectationDigest: established.executionBaseline.environment.expectationDigest,
            capabilityAvailabilityDigest:
                established.executionBaseline.environment.capabilityAvailabilityDigest
        )
        let historicalBaseline = try CADExecutionRegressionBaseline(
            environment: historicalEnvironment,
            records: established.executionBaseline.records
        )
        let manifestDrift = try builder.build(
            run: serial,
            mode: .compare(expected: historicalBaseline)
        )
        #expect(manifestDrift.report.status == .baselineDrift)
        #expect(manifestDrift.report.baselineDrifts == [.manifest])

        var invalidRecords = established.executionBaseline.records
        let firstRecord = try #require(invalidRecords.first)
        invalidRecords[0] = try CADCaseRegressionRecord(
            caseID: firstRecord.caseID,
            outcome: .oracleFailure,
            capabilityDecisionCorrect: false,
            route: firstRecord.route,
            counts: firstRecord.counts,
            caseContractDigest: firstRecord.caseContractDigest,
            oracleDisposition: .rejected
        )
        #expect(throws: CADBenchmarkBaselineError.invalidExecutionBaseline) {
            _ = try CADExecutionRegressionBaseline(
                environment: established.executionBaseline.environment,
                records: invalidRecords
            )
        }

        let canonical = try established.report.canonicalJSON()
        #expect(canonical.count <= CADBenchmarkReport.maximumEncodedBytes)
        #expect(nextPowerOfTwo(canonical.count) == CADBenchmarkReport.maximumEncodedBytes)
        let fixtureURL: URL
        if let output = ProcessInfo.processInfo.environment["T12_FIXTURE_OUTPUT"] {
            fixtureURL = URL(fileURLWithPath: output)
            try canonical.write(to: fixtureURL, options: .atomic)
        } else {
            fixtureURL = try #require(Bundle.module.url(
                forResource: "t12-reference-execution-v1",
                withExtension: "json"
            ))
        }
        let fixture = try Data(contentsOf: fixtureURL)
        #expect(fixture == canonical)
        let decoded = try JSONDecoder().decode(CADBenchmarkReport.self, from: fixture)
        try decoded.validate()
        #expect(try decoded.canonicalJSON() == fixture)

        let tamperedBytes = try #require(String(data: fixture, encoding: .utf8))
            .replacingOccurrences(of: "\"status\":\"valid\"", with: "\"status\":\"invalid\"")
            .data(using: .utf8)
        let tampered = try JSONDecoder().decode(
            CADBenchmarkReport.self,
            from: try #require(tamperedBytes)
        )
        #expect(throws: CADBenchmarkBaselineError.invalidReport) {
            try tampered.validate()
        }

        var decodedObject = try #require(
            JSONSerialization.jsonObject(with: fixture) as? [String: Any]
        )
        var reorderedResults = try #require(decodedObject["results"] as? [[String: Any]])
        reorderedResults.swapAt(0, 1)
        decodedObject["results"] = reorderedResults
        let reorderedBytes = try JSONSerialization.data(
            withJSONObject: decodedObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let reordered = try JSONDecoder().decode(
            CADBenchmarkReport.self,
            from: reorderedBytes
        )
        #expect(throws: CADBenchmarkBaselineError.invalidReport) {
            try reordered.validate()
        }
    }

    @Test
    func capabilityMergeRejectsSnapshotAndStatusDrift() throws {
        let catalog = try CADBenchmarkCatalog()
        var contexts = catalog.challenges.map { Self.context($0) }
        let baseline = try CADCapabilityAvailabilityBaseline(contexts: contexts)
        try baseline.validate()
        #expect(baseline.statuses.count == 10)

        contexts[0] = Self.context(
            catalog.challenges[0],
            snapshotVersion: "agent-capabilities.v2"
        )
        #expect(throws: CADBenchmarkBaselineError.self) {
            _ = try CADCapabilityAvailabilityBaseline(contexts: contexts)
        }

        contexts = catalog.challenges.map { Self.context($0) }
        let conflictingChallenge = catalog.challenges[1]
        contexts[1] = CADCandidateContext(
            challenge: conflictingChallenge,
            capabilities: CADCapabilitySnapshot(
                version: "agent-capabilities.v1",
                statuses: [CADCapabilityStatus(
                    id: conflictingChallenge.requiredCapability.id,
                    version: conflictingChallenge.requiredCapability.version,
                    available: false,
                    reasonCode: "not-exposed"
                )]
            ),
            remainingRounds: conflictingChallenge.budget.maximumRounds,
            remainingActions: conflictingChallenge.budget.maximumActions
        )
        #expect(throws: CADBenchmarkBaselineError.self) {
            _ = try CADCapabilityAvailabilityBaseline(contexts: contexts)
        }
    }

    @Test
    func fixedDenominatorScoreRejectsPartialInput() throws {
        let challenge = try #require(try CADBenchmarkCatalog().challenges.first)
        let partial = CADCaseResult(
            id: challenge.id,
            category: challenge.category,
            outcome: .realized,
            capabilityDecisionCorrect: true
        )
        #expect(throws: CADBenchmarkError.self) {
            _ = try CADBenchmarkScore(results: [partial])
        }
    }

    private static func context(
        _ challenge: CADChallenge,
        snapshotVersion: String = "agent-capabilities.v1"
    ) -> CADCandidateContext {
        let available = challenge.category != .sphere
        return CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: snapshotVersion,
                statuses: [CADCapabilityStatus(
                    id: challenge.requiredCapability.id,
                    version: challenge.requiredCapability.version,
                    available: available,
                    reasonCode: available ? nil : "not-exposed"
                )]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
    }

    private func nextPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value {
            result *= 2
        }
        return result
    }
}
