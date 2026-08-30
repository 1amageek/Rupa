struct CADBenchmarkScheduledRun: Equatable, Sendable {
    let attempt: CADBenchmarkReferenceRunAttempt
    let measurement: CADBenchmarkRunMeasurement
    let drainEvidence: CADBenchmarkDrainEvidence

    init(
        attempt: CADBenchmarkReferenceRunAttempt,
        measurement: CADBenchmarkRunMeasurement,
        drainEvidence: CADBenchmarkDrainEvidence
    ) throws {
        try attempt.validate()
        try measurement.validate(manifest: attempt.manifest)
        try drainEvidence.validate()
        guard drainEvidence.startedCases == attempt.executions.count else {
            throw CADBenchmarkScheduleError.invalidDrain
        }
        self.attempt = attempt
        self.measurement = measurement
        self.drainEvidence = drainEvidence
    }
}
