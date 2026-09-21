enum CADConstraintGeometryInput: Codable, Equatable, Hashable, Sendable {
    case line(CADLineChallengeInput)
    case circle(CADCircleChallengeInput)

    func validate(caseID: CADBenchmarkCaseID) throws {
        switch self {
        case let .line(line):
            try line.validate(caseID: caseID)
        case let .circle(circle):
            try circle.validate(caseID: caseID)
        }
    }
}
