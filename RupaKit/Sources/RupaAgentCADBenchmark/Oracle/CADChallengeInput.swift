enum CADChallengeInput: Codable, Equatable, Hashable, Sendable {
    case line(CADLineChallengeInput)
    case rectangle(CADRectangleChallengeInput)
    case circle(CADCircleChallengeInput)
    case angle(CADAngleChallengeInput)
    case box(CADBoxChallengeInput)
    case cylinder(CADCylinderChallengeInput)
    case constraint(CADConstraintChallengeInput)
    case transform(CADTransformChallengeInput)
    case compound(CADCompoundChallengeInput)
    case sphere(CADSphereChallengeInput)

    var category: CADBenchmarkCategory {
        switch self {
        case .line:
            .line
        case .rectangle:
            .rectangle
        case .circle:
            .circle
        case .angle:
            .angle
        case .box:
            .box
        case .cylinder:
            .cylinder
        case .constraint:
            .constraint
        case .transform:
            .transform
        case .compound:
            .compound
        case .sphere:
            .sphere
        }
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        switch self {
        case let .line(input):
            try input.validate(caseID: caseID)
        case let .rectangle(input):
            try input.validate(caseID: caseID)
        case let .circle(input):
            try input.validate(caseID: caseID)
        case let .angle(input):
            try input.validate(caseID: caseID)
        case let .box(input):
            try input.validate(caseID: caseID)
        case let .cylinder(input):
            try input.validate(caseID: caseID)
        case let .constraint(input):
            try input.validate(caseID: caseID)
        case let .transform(input):
            try input.validate(caseID: caseID)
        case let .compound(input):
            try input.validate(caseID: caseID)
        case let .sphere(input):
            try input.validate(caseID: caseID)
        }
    }
}
