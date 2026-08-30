enum CADBenchmarkExecutionPolicy {
    static let maximumConcurrentCases = 1
    static let wholeRunDeadlineSeconds: UInt64 = 38

    static var wholeRunDeadlineNanoseconds: UInt64 {
        wholeRunDeadlineSeconds * 1_000_000_000
    }

    static func configuration() throws -> CADBenchmarkRunConfiguration {
        try CADBenchmarkRunConfiguration(
            maximumConcurrentCases: maximumConcurrentCases
        )
    }
}
