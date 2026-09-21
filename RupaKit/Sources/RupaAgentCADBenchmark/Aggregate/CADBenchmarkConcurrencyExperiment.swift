@MainActor
struct CADBenchmarkConcurrencyExperiment {
    private static let repetitions = 3
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    private static let perCaseDeadlineNanoseconds: UInt64 = 10_000_000_000

    private let scheduler: CADBenchmarkScheduler

    init(scheduler: CADBenchmarkScheduler = CADBenchmarkScheduler()) {
        self.scheduler = scheduler
    }

    func run() async throws -> CADBenchmarkConcurrencyExperimentResult {
        let serial = try CADBenchmarkRunConfiguration(maximumConcurrentCases: 1)
        let parallel = try CADBenchmarkRunConfiguration(maximumConcurrentCases: 2)
        var serialMeasurements: [CADBenchmarkRunMeasurement] = []
        var parallelMeasurements: [CADBenchmarkRunMeasurement] = []
        var referenceRecords: [CADCaseRegressionRecord]?
        var maximumWallNanoseconds: UInt64 = 0

        for _ in 0..<Self.repetitions {
            let serialRun = try await scheduler.run(configuration: serial)
            try admit(
                serialRun,
                expectedPeak: 1,
                referenceRecords: &referenceRecords
            )
            serialMeasurements.append(serialRun.measurement)
            maximumWallNanoseconds = max(
                maximumWallNanoseconds,
                serialRun.measurement.wholeRunWallNanoseconds
            )

            let parallelRun = try await scheduler.run(configuration: parallel)
            try admit(
                parallelRun,
                expectedPeak: 2,
                referenceRecords: &referenceRecords
            )
            parallelMeasurements.append(parallelRun.measurement)
            maximumWallNanoseconds = max(
                maximumWallNanoseconds,
                parallelRun.measurement.wholeRunWallNanoseconds
            )
        }

        guard let referenceRecords else {
            throw CADBenchmarkScheduleError.nondeterministicRun
        }
        let serialWalls = serialMeasurements.map(\.wholeRunWallNanoseconds)
        let parallelWalls = parallelMeasurements.map(\.wholeRunWallNanoseconds)
        let improvement = median(serialWalls) > median(parallelWalls)
            ? median(serialWalls) - median(parallelWalls)
            : 0
        let variability = max(range(serialWalls), range(parallelWalls))
        let selected = improvement > variability ? parallel : serial
        let deadlineSeconds = try wholeRunDeadlineSeconds(
            maximumWallNanoseconds: maximumWallNanoseconds,
            caseCount: referenceRecords.count
        )
        let result = CADBenchmarkConcurrencyExperimentResult(
            serialMeasurements: serialMeasurements,
            parallelMeasurements: parallelMeasurements,
            selectedConfiguration: selected,
            wholeRunDeadlineSeconds: deadlineSeconds,
            regressionRecords: referenceRecords
        )
        try result.validate()
        return result
    }

    private func admit(
        _ run: CADBenchmarkScheduledRun,
        expectedPeak: Int,
        referenceRecords: inout [CADCaseRegressionRecord]?
    ) throws {
        guard run.measurement.observedInFlightCases == expectedPeak else {
            throw CADBenchmarkScheduleError.parallelAdmissionNotObserved
        }
        if let referenceRecords {
            guard run.attempt.regressionRecords == referenceRecords else {
                throw CADBenchmarkScheduleError.nondeterministicRun
            }
        } else {
            referenceRecords = run.attempt.regressionRecords
        }
    }

    private func median(_ values: [UInt64]) -> UInt64 {
        values.sorted()[values.count / 2]
    }

    private func range(_ values: [UInt64]) -> UInt64 {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private func wholeRunDeadlineSeconds(
        maximumWallNanoseconds: UInt64,
        caseCount: Int
    ) throws -> UInt64 {
        guard maximumWallNanoseconds > 0,
              maximumWallNanoseconds <= UInt64.max / 2,
              let count = UInt64(exactly: caseCount),
              count <= UInt64.max / Self.perCaseDeadlineNanoseconds else {
            throw CADBenchmarkScheduleError.invalidWholeRunDeadline
        }
        let doubled = maximumWallNanoseconds * 2
        let quotient = doubled / Self.nanosecondsPerSecond
        let deadlineSeconds = quotient + (doubled.isMultiple(of: Self.nanosecondsPerSecond) ? 0 : 1)
        let summedPerCaseDeadline = count * Self.perCaseDeadlineNanoseconds
        guard deadlineSeconds > 0,
              deadlineSeconds < summedPerCaseDeadline / Self.nanosecondsPerSecond else {
            throw CADBenchmarkScheduleError.invalidWholeRunDeadline
        }
        return deadlineSeconds
    }
}
