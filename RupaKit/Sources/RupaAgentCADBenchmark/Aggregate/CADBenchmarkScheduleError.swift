enum CADBenchmarkScheduleError: Error, Equatable, Sendable {
    case invalidConcurrency(Int)
    case invalidMeasurement
    case invalidDrain
    case cancelled(CADBenchmarkDrainEvidence)
    case deadlineExceeded(CADBenchmarkDrainEvidence)
    case executionFailed(CADBenchmarkCaseID, CADBenchmarkDrainEvidence)
    case nondeterministicRun
    case parallelAdmissionNotObserved
    case invalidWholeRunDeadline
}
