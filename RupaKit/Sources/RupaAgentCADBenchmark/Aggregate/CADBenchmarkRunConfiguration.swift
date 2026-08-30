struct CADBenchmarkRunConfiguration: Equatable, Sendable {
    let maximumConcurrentCases: Int

    init(maximumConcurrentCases: Int) throws {
        guard maximumConcurrentCases == 1 || maximumConcurrentCases == 2 else {
            throw CADBenchmarkScheduleError.invalidConcurrency(maximumConcurrentCases)
        }
        self.maximumConcurrentCases = maximumConcurrentCases
    }
}
