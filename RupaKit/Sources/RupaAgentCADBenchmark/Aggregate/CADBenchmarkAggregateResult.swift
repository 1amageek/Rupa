struct CADBenchmarkAggregateResult: Equatable, Sendable {
    let capabilityBaseline: CADCapabilityAvailabilityBaseline
    let executionBaseline: CADExecutionRegressionBaseline
    let report: CADBenchmarkReport
}
