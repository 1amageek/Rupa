import Foundation

public enum CADActivatedCaseExecutorError: Error, Equatable, Sendable, CustomStringConvertible {
    case inactiveCase(CADBenchmarkCaseID)
    case candidateFailure(CADBenchmarkCaseID)
    case catalogFailure(CADBenchmarkCaseID)
    case invalidResult(CADBenchmarkCaseID)

    public var description: String {
        switch self {
        case .inactiveCase(let caseID):
            "The benchmark case is not activated: \(caseID.rawValue)."
        case .candidateFailure(let caseID):
            "The candidate failed before publication for \(caseID.rawValue)."
        case .catalogFailure(let caseID):
            "The activated benchmark catalog could not be resolved for \(caseID.rawValue)."
        case .invalidResult(let caseID):
            "The activated benchmark produced an invalid sanitized result for \(caseID.rawValue)."
        }
    }
}
