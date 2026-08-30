enum CADBenchmarkBaselineMode: Equatable, Sendable {
    case establish(existing: CADExecutionRegressionBaseline?)
    case compare(expected: CADExecutionRegressionBaseline)
}
