enum CADActivatedCaseEvidence: Equatable, Sendable {
    case line(CADLineCaseResult)
    case rectangle(CADRectangleCaseResult)
    case circle(CADCircleCaseResult)
    case angle(CADAngleCaseResult)
    case box(CADBoxCaseResult)
    case cylinder(CADCylinderCaseResult)
    case constraint(CADConstraintCaseResult)
    case transform(CADTransformCaseResult)
    case compound(CADCompoundCaseResult)
    case sphere(CADSphereCaseResult)

    var caseID: CADBenchmarkCaseID {
        switch self {
        case .line(let result): result.caseID
        case .rectangle(let result): result.caseID
        case .circle(let result): result.caseID
        case .angle(let result): result.caseID
        case .box(let result): result.caseID
        case .cylinder(let result): result.caseID
        case .constraint(let result): result.caseID
        case .transform(let result): result.caseID
        case .compound(let result): result.caseID
        case .sphere(let result): result.caseID
        }
    }

    var outcome: CADCaseOutcome {
        switch self {
        case .line(let result): result.outcome
        case .rectangle(let result): result.outcome
        case .circle(let result): result.outcome
        case .angle(let result): result.outcome
        case .box(let result): result.outcome
        case .cylinder(let result): result.outcome
        case .constraint(let result): result.outcome
        case .transform(let result): result.outcome
        case .compound(let result): result.outcome
        case .sphere(let result): result.outcome
        }
    }

    var totalWallNanoseconds: UInt64 {
        switch self {
        case .line(let result): result.telemetry.totalWallNanoseconds
        case .rectangle(let result): result.telemetry.totalWallNanoseconds
        case .circle(let result): result.telemetry.totalWallNanoseconds
        case .angle(let result): result.telemetry.totalWallNanoseconds
        case .box(let result): result.telemetry.totalWallNanoseconds
        case .cylinder(let result): result.telemetry.totalWallNanoseconds
        case .constraint(let result): result.telemetry.totalWallNanoseconds
        case .transform(let result): result.telemetry.totalWallNanoseconds
        case .compound(let result): result.telemetry.totalWallNanoseconds
        case .sphere(let result): result.telemetry.totalWallNanoseconds
        }
    }

    func validate() throws {
        switch self {
        case .line(let result): try result.validate()
        case .rectangle(let result): try result.validate()
        case .circle(let result): try result.validate()
        case .angle(let result): try result.validate()
        case .box(let result): try result.validate()
        case .cylinder(let result): try result.validate()
        case .constraint(let result): try result.validate()
        case .transform(let result): try result.validate()
        case .compound(let result): try result.validate()
        case .sphere(let result): try result.validate()
        }
    }
}
