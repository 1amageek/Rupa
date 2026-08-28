enum CADExpectedGeometry: Codable, Equatable, Sendable {
    case line(CADLineChallengeInput)
    case rectangle(CADRectangleChallengeInput)
    case circle(CADCircleChallengeInput)
    case angle(CADAngleChallengeInput)
    case box(CADBoxChallengeInput)
    case cylinder(CADCylinderChallengeInput)
    case constraint(CADConstraintChallengeInput)
    case transform(CADTransformChallengeInput)
    case compound(CADCompoundChallengeInput)
    case sphere(CADSphereChallengeInput, requiresAnalyticSurface: Bool)
}
