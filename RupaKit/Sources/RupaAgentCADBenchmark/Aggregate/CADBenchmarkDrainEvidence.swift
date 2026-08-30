struct CADBenchmarkDrainEvidence: Equatable, Sendable {
    let startedCases: Int
    let completedCases: Int
    let activeCasesAfterDrain: Int
    let remainingRegistrations: Int

    func validate() throws {
        guard startedCases >= 0,
              completedCases == startedCases,
              activeCasesAfterDrain == 0,
              remainingRegistrations == 0 else {
            throw CADBenchmarkScheduleError.invalidDrain
        }
    }

    static let empty = CADBenchmarkDrainEvidence(
        startedCases: 0,
        completedCases: 0,
        activeCasesAfterDrain: 0,
        remainingRegistrations: 0
    )
}
