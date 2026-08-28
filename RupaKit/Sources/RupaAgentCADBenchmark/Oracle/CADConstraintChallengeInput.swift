struct CADConstraintChallengeInput: Codable, Equatable, Hashable, Sendable {
    let relation: CADConstraintKind
    let first: CADConstraintGeometryInput
    let second: CADConstraintGeometryInput?

    init(
        relation: CADConstraintKind,
        first: CADConstraintGeometryInput,
        second: CADConstraintGeometryInput? = nil
    ) {
        self.relation = relation
        self.first = first
        self.second = second
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try first.validate(caseID: caseID)
        if let second {
            try second.validate(caseID: caseID)
        }
        switch relation {
        case .horizontal, .vertical:
            guard second == nil else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A single-line relation must have no second geometry."
                )
            }
            guard case .line = first else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "Horizontal and vertical relations require a line."
                )
            }
        case .concentric, .equalRadius:
            guard case .circle = first,
                  let second,
                  case .circle = second else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "Circular relations require two circles."
                )
            }
        case .coincident, .parallel, .perpendicular, .equalLength:
            guard case .line = first, case .line = second else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "Line relations require two lines."
                )
            }
        }
    }
}
