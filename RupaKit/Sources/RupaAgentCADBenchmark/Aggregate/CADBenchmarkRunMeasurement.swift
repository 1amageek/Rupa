struct CADBenchmarkRunMeasurement: Equatable, Sendable {
    let requestedConcurrency: Int
    let observedInFlightCases: Int
    let observedMainActorEntryConcurrency: Int
    let wholeRunWallNanoseconds: UInt64
    let cases: [CADCaseMeasurement]

    func validate(manifest: CADBenchmarkManifest) throws {
        guard requestedConcurrency == 1 || requestedConcurrency == 2,
              observedInFlightCases >= 1,
              observedInFlightCases <= requestedConcurrency,
              observedMainActorEntryConcurrency == 1,
              wholeRunWallNanoseconds > 0,
              cases.count == manifest.orderedCaseIDs.count,
              cases.map(\.caseID) == manifest.orderedCaseIDs else {
            throw CADBenchmarkScheduleError.invalidMeasurement
        }
    }
}
