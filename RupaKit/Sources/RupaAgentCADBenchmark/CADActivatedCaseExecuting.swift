@MainActor
public protocol CADActivatedCaseExecuting: Sendable {
    var activatedCaseIDs: [CADBenchmarkCaseID] { get }

    func context(for caseID: CADBenchmarkCaseID) throws -> CADCandidateContext

    func evaluate(
        caseID: CADBenchmarkCaseID,
        candidate: any CADCandidateProtocol
    ) async throws -> CADCaseResult
}
