struct CADBenchmarkConcurrencyExperimentResult: Equatable, Sendable {
    let serialMeasurements: [CADBenchmarkRunMeasurement]
    let parallelMeasurements: [CADBenchmarkRunMeasurement]
    let selectedConfiguration: CADBenchmarkRunConfiguration
    let wholeRunDeadlineSeconds: UInt64
    let regressionRecords: [CADCaseRegressionRecord]

    func validate() throws {
        guard serialMeasurements.count == 3,
              parallelMeasurements.count == 3,
              serialMeasurements.allSatisfy({
                  $0.requestedConcurrency == 1
                      && $0.observedInFlightCases == 1
                      && $0.observedMainActorEntryConcurrency == 1
              }),
              parallelMeasurements.allSatisfy({
                  $0.requestedConcurrency == 2
                      && $0.observedInFlightCases == 2
                      && $0.observedMainActorEntryConcurrency == 1
              }),
              selectedConfiguration.maximumConcurrentCases == 1
                  || selectedConfiguration.maximumConcurrentCases == 2,
              wholeRunDeadlineSeconds > 0,
              regressionRecords.count == 100 else {
            throw CADBenchmarkScheduleError.invalidMeasurement
        }
    }
}
