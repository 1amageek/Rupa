enum CADInternalCatalogStore {
    static let definitions: [CADCanonicalChallengeDefinition] =
        CADSketchChallengeCatalog.definitions + CADSolidChallengeCatalog.definitions

    static func entries() throws -> [CADCatalogEntry] {
        try definitions.sorted { $0.id < $1.id }.map { definition in
            let challenge = try definition.projectChallenge()
            let expected: CADExpectedGeometry
            switch definition.input {
            case let .line(input):
                expected = .line(input)
            case let .rectangle(input):
                expected = .rectangle(input)
            case let .circle(input):
                expected = .circle(input)
            case let .angle(input):
                expected = .angle(input)
            case let .box(input):
                expected = .box(input)
            case let .cylinder(input):
                expected = .cylinder(input)
            case let .constraint(input):
                expected = .constraint(input)
            case let .transform(input):
                expected = .transform(input)
            case let .compound(input):
                expected = .compound(input)
            case let .sphere(input):
                expected = .sphere(input, requiresAnalyticSurface: true)
            }
            return try CADCatalogEntry(
                challenge: challenge,
                input: definition.input,
                expected: expected,
                requiresAnalyticSurface: definition.category == .sphere
            )
        }
    }

    static func expectationContract() throws -> CADBenchmarkExpectationContract {
        let contract = try CADBenchmarkExpectationContract(entries: entries())
        try contract.validate()
        return contract
    }
}
