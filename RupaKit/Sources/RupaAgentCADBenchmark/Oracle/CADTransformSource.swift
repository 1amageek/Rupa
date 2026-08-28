enum CADTransformSource: Codable, Equatable, Hashable, Sendable {
    case line(CADLineChallengeInput)
    case rectangle(CADRectangleChallengeInput)
    case circle(CADCircleChallengeInput)
    case box(CADBoxChallengeInput)
    case cylinder(CADCylinderChallengeInput)

    func validate(caseID: CADBenchmarkCaseID) throws {
        switch self {
        case let .line(input):
            try input.validate(caseID: caseID)
        case let .rectangle(input):
            try input.validate(caseID: caseID)
        case let .circle(input):
            try input.validate(caseID: caseID)
        case let .box(input):
            try input.validate(caseID: caseID)
        case let .cylinder(input):
            try input.validate(caseID: caseID)
        }
    }
}
