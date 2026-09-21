struct CADCaseMeasurement: Equatable, Sendable {
    let caseID: CADBenchmarkCaseID
    let totalWallNanoseconds: UInt64

    init(caseID: CADBenchmarkCaseID, totalWallNanoseconds: UInt64) throws {
        guard totalWallNanoseconds > 0 else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        self.caseID = caseID
        self.totalWallNanoseconds = totalWallNanoseconds
    }
}
