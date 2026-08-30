@MainActor
struct CADBenchmarkAggregateBuilder {
    func build(
        run: CADBenchmarkScheduledRun,
        mode: CADBenchmarkBaselineMode
    ) throws -> CADBenchmarkAggregateResult {
        try run.attempt.validate()
        try run.drainEvidence.validate()
        let capabilityBaseline = try CADCapabilityAvailabilityBaseline(
            contexts: run.attempt.executions.map(\.context)
        )
        let observed = try CADExecutionRegressionBaseline(
            attempt: run.attempt,
            capabilityBaseline: capabilityBaseline
        )

        let expected: CADExecutionRegressionBaseline
        let drifts: [CADBenchmarkBaselineDrift]
        switch mode {
        case .establish(let existing):
            guard existing == nil else {
                throw CADBenchmarkBaselineError.baselineAlreadyExists
            }
            expected = observed
            drifts = []
        case .compare(let supplied):
            try supplied.validate()
            expected = supplied
            drifts = try observed.differences(from: supplied)
        }
        let report = try CADBenchmarkReport(
            attempt: run.attempt,
            capabilityBaseline: capabilityBaseline,
            expectedBaseline: expected,
            observedBaseline: observed,
            baselineDrifts: drifts
        )
        return CADBenchmarkAggregateResult(
            capabilityBaseline: capabilityBaseline,
            executionBaseline: observed,
            report: report
        )
    }
}
